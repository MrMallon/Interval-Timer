#!/usr/bin/env python3
"""Check Shared/Localizable.xcstrings against the strings the compiler extracted.

The build must run with SWIFT_EMIT_LOC_STRINGS=YES so each Swift file produces
a .stringsdata file listing every localizable key it uses.

Fails (exit 1) when:
- a key used in code is missing from the catalog, or
- a key is not translated into every required language.
Warns for catalog keys no longer used in code.

Usage: check_strings.py <derived-data-build-dir> <Table=catalog.xcstrings>... [--dump keys.json]
       (a bare path means the Localizable table)
"""
import glob
import json
import os
import sys

LANGUAGES = ["nl", "fr", "de", "it", "ja", "ko", "pt-BR", "ru", "zh-Hans", "es", "sv", "th", "zh-Hant", "tr"]


def escape(text):
    return text.replace("%", "%25").replace("\r", "").replace("\n", "%0A")


def code_keys(build_dir, table):
    keys = {}
    for path in glob.glob(os.path.join(build_dir, "**", "*.stringsdata"), recursive=True):
        try:
            data = json.load(open(path))
        except Exception:
            continue
        for entry in data.get("tables", {}).get(table, []):
            keys.setdefault(entry["key"], entry.get("comment") or "")
    return keys


def all_tables(build_dir):
    tables = set()
    for path in glob.glob(os.path.join(build_dir, "**", "*.stringsdata"), recursive=True):
        try:
            tables.update(json.load(open(path)).get("tables", {}).keys())
        except Exception:
            pass
    return tables


def is_translated(entry, lang):
    loc = entry.get("localizations", {}).get(lang)
    if not loc:
        return False
    if "stringUnit" in loc:
        return loc["stringUnit"].get("state") == "translated" and loc["stringUnit"].get("value", "") != ""
    if "variations" in loc:
        def walk(node):
            if "stringUnit" in node:
                return node["stringUnit"].get("state") == "translated"
            return all(walk(child) for group in node.values() for child in group.values())
        return walk(loc["variations"])
    return False


def check_table(build_dir, table, catalog_path, dump):
    keys = code_keys(build_dir, table)
    if dump is not None:
        dump[table] = keys

    catalog = json.load(open(catalog_path)) if os.path.exists(catalog_path) else {"strings": {}}
    strings = catalog.get("strings", {})

    missing = sorted(k for k in keys if k not in strings)
    stale = sorted(k for k, v in strings.items() if k not in keys and v.get("extractionState") != "manual")
    untranslated = {}
    for key in keys:
        if key not in strings or strings[key].get("shouldTranslate") is False:
            continue
        langs = [lang for lang in LANGUAGES if not is_translated(strings[key], lang)]
        if langs:
            untranslated[key] = langs

    print(f"::notice title={table} strings::{len(keys)} keys in code, {len(strings)} in catalog, "
          f"{len(missing)} missing, {len(untranslated)} not fully translated, {len(stale)} unused")
    if missing:
        print(f"::error title=Missing from {os.path.basename(catalog_path)}::" + escape("\n".join(json.dumps(k, ensure_ascii=False) for k in missing)))
    if untranslated:
        lines = [f"{json.dumps(k, ensure_ascii=False)}: {', '.join(v)}" for k, v in sorted(untranslated.items())]
        print(f"::error title=Untranslated ({table})::" + escape("\n".join(lines[:200])))
    if stale:
        print(f"::warning title=Unused keys in {os.path.basename(catalog_path)}::" + escape("\n".join(json.dumps(k, ensure_ascii=False) for k in stale)))
    return bool(missing or untranslated)


def main():
    args = sys.argv[1:]
    dump_path = None
    if "--dump" in args:
        i = args.index("--dump")
        dump_path = args[i + 1]
        del args[i:i + 2]
    build_dir, specs = args[0], args[1:]
    tables = {}
    for spec in specs:
        table, _, path = spec.rpartition("=")
        tables[table or "Localizable"] = path

    found = all_tables(build_dir)
    if not found:
        print("::error title=Strings::No .stringsdata found; is SWIFT_EMIT_LOC_STRINGS on?")
        sys.exit(1)
    unknown = sorted(found - set(tables))
    if unknown:
        print(f"::error title=Strings::Strings in tables with no catalog: {', '.join(unknown)}")

    dump = {} if dump_path else None
    failed = bool(unknown)
    for table, path in tables.items():
        failed |= check_table(build_dir, table, path, dump)
    if dump_path:
        json.dump(dump, open(dump_path, "w"), indent=1, ensure_ascii=False, sort_keys=True)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
