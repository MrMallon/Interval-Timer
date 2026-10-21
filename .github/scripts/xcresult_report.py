#!/usr/bin/env python3
"""Summarise an .xcresult bundle for GitHub Actions.

- Prints a GitHub notice listing every test with pass/fail and duration.
- Prints a GitHub error per failing test (first 10).
- Writes a Markdown table to $GITHUB_STEP_SUMMARY.
- Exports screenshots / text attachments to a folder with readable names.

Usage: xcresult_report.py <path.xcresult> <attachments-out-dir>
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile


def run_json(args):
    out = subprocess.run(args, capture_output=True, text=True)
    if out.returncode != 0:
        print(out.stderr, file=sys.stderr)
        return None
    return json.loads(out.stdout)


def walk(node, bundle=None, suite=None):
    kind = node.get("nodeType")
    if kind == "Unit test bundle" or kind == "UI test bundle":
        bundle = node.get("name")
    if kind == "Test Suite":
        suite = node.get("name")
    if kind == "Test Case":
        failures = [c.get("name", "") for c in node.get("children", []) if c.get("nodeType") == "Failure Message"]
        yield {
            "bundle": bundle,
            "suite": suite,
            "name": node.get("name"),
            "result": node.get("result"),
            "duration": node.get("durationInSeconds") or 0,
            "failures": failures,
        }
        return
    for child in node.get("children", []):
        yield from walk(child, bundle, suite)


def escape(text):
    return text.replace("%", "%25").replace("\r", "").replace("\n", "%0A")


def export_attachments(xcresult, out_dir):
    raw = tempfile.mkdtemp()
    res = subprocess.run(
        ["xcrun", "xcresulttool", "export", "attachments", "--path", xcresult, "--output-path", raw],
        capture_output=True, text=True,
    )
    if res.returncode != 0:
        print(res.stderr, file=sys.stderr)
        return []
    manifest_path = os.path.join(raw, "manifest.json")
    if not os.path.exists(manifest_path):
        return []
    os.makedirs(out_dir, exist_ok=True)
    written = []
    for test in json.load(open(manifest_path)):
        for item in test.get("attachments", []):
            src = os.path.join(raw, item["exportedFileName"])
            human = item.get("suggestedHumanReadableName") or item["exportedFileName"]
            # "01-library_0_6F3A....png" -> "01-library.png"
            stem, ext = os.path.splitext(human)
            stem = re.sub(r"_\d+_[0-9A-Fa-f-]{36}$", "", stem)
            # Only screenshots and our own text logs; skip videos and XCTest debug dumps.
            if ext.lower() not in (".png", ".jpg", ".jpeg", ".txt"):
                continue
            if ext.lower() == ".txt" and not stem.startswith("cue-log"):
                continue
            stem = re.sub(r'[^A-Za-z0-9._-]+', "-", stem).strip("-")
            dest = os.path.join(out_dir, stem + ext)
            shutil.copy(src, dest)
            written.append(os.path.basename(dest))
    return sorted(written)


def main():
    xcresult, out_dir = sys.argv[1], sys.argv[2]
    data = run_json(["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", xcresult])
    tests = []
    if data:
        for root in data.get("testNodes", []):
            tests.extend(walk(root))

    passed = sum(1 for t in tests if t["result"] == "Passed")
    failed = [t for t in tests if t["result"] == "Failed"]
    lines = [f"{passed} passed, {len(failed)} failed, {len(tests)} total"]
    for t in tests:
        mark = "PASS" if t["result"] == "Passed" else t["result"].upper()
        lines.append(f"{mark}  {t['suite']}.{t['name']}  ({t['duration']:.1f}s)")
    print(f"::notice title=Simulator tests::{escape(chr(10).join(lines))}")
    for t in failed[:10]:
        message = "\n".join(t["failures"]) or "Failed"
        print(f"::error title={t['suite']}.{t['name']}::{escape(message)}")

    files = export_attachments(xcresult, out_dir)
    texts = []
    for name in files:
        if name.endswith(".txt"):
            body = open(os.path.join(out_dir, name)).read().strip()
            texts.append(f"{name}: {body}")
    if texts:
        print(f"::notice title=Test logs::{escape(chr(10).join(texts))}")

    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a") as fh:
            fh.write("## Simulator tests\n\n")
            fh.write(f"**{lines[0]}**\n\n| Result | Test | Time |\n| --- | --- | --- |\n")
            for t in tests:
                fh.write(f"| {t['result']} | {t['suite']}.{t['name']} | {t['duration']:.1f}s |\n")
            for t in failed:
                fh.write(f"\n**{t['suite']}.{t['name']}**\n\n```\n" + "\n".join(t["failures"]) + "\n```\n")
            if texts:
                fh.write("\n### Logs\n\n" + "\n".join(f"- `{x}`" for x in texts) + "\n")

    if not tests:
        print("::error title=Simulator tests::No test results found")
        sys.exit(1)


if __name__ == "__main__":
    main()
