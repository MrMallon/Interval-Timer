#!/usr/bin/env python3
"""Check Shared/Localizable.xcstrings against the strings the compiler extracted.

The build must run with SWIFT_EMIT_LOC_STRINGS=YES so each Swift file produces
a .stringsdata file listing every localizable key it uses.

Fails (exit 1) when:
- a key used in code is missing from the catalog, or
- a key is not translated into every required language.
Warns for catalog keys no longer used in code.

Usage: check_strings.py <derived-data-build-dir> <catalog.xcstrings> [--dump keys.json]
"""
import glob
import json
import os
import sys

LANGUAGES = ["nl", "fr", "de", "it", "ja", "ko", "pt-BR", "ru", "zh-Hans", "es", "sv", "th", "zh-Hant", "tr"]


def escape(text):
    return text.replace("%", "%25").replace("\r", "").replace("\n", "%0A")


def code_keys(build_dir):
    keys = {}
    for path in glob.glob(os.path.join(build_dir, "**", "*.stringsdata"), recursive=True):
        try:
            data = json.load(open(path))
        except Exception:
            continue
        for entry in data.get("tables", {}).get("Localizable", []):
            keys.setdefault(entry["key"], entry.get("comment") or "")
    return keys


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


def main():
    build_dir, catalog_path = sys.argv[1], sys.argv[2]
    keys = code_keys(build_dir)
    if not keys:
        print("::error title=Strings::No .stringsdata found; is SWIFT_EMIT_LOC_STRINGS on?")
        sys.exit(1)

    if "--dump" in sys.argv:
        out = sys.argv[sys.argv.index("--dump") + 1]
        json.dump(keys, open(out, "w"), indent=1, ensure_ascii=False, sort_keys=True)

    catalog = json.load(open(catalog_path)) if os.path.exists(catalog_path) else {"strings": {}}
    strings = catalog.get("strings", {})

    missing = sorted(k for k in keys if k not in strings)
    stale = sorted(k for k, v in strings.items() if k not in keys and v.get("extractionState") != "manual")
    untranslated = {}
    for key in keys:
        if key in strings and strings[key].get("shouldTranslate") is False:
            continue
        if key not in strings:
            continue
        langs = [lang for lang in LANGUAGES if not is_translated(strings[key], lang)]
        if langs:
            untranslated[key] = langs

    print(f"::notice title=Strings::{len(keys)} keys in code, {len(strings)} in catalog, "
          f"{len(missing)} missing, {len(untranslated)} not fully translated, {len(stale)} unused")
    if missing:
        print("::error title=Missing from Localizable.xcstrings::" + escape("\n".join(json.dumps(k, ensure_ascii=False) for k in missing)))
    if untranslated:
        lines = [f"{json.dumps(k, ensure_ascii=False)}: {', '.join(v)}" for k, v in sorted(untranslated.items())]
        print("::error title=Untranslated::" + escape("\n".join(lines[:200])))
    if stale:
        print("::warning title=Unused catalog keys::" + escape("\n".join(json.dumps(k, ensure_ascii=False) for k in stale)))
    sys.exit(1 if (missing or untranslated) else 0)


if __name__ == "__main__":
    main()
