#!/usr/bin/env python3
"""Check/fill missing Chronically Online variants for native SwiftUI lookup.

Run --write after adding base-language strings; --check exits nonzero when a
variant is missing. Existing dialect translations are never changed. Authored
LocalizableCO copy takes precedence over automatically transformed base copy.
The token list and format expression come from AppLanguageStore.swift so the
compiled catalog and runtime Bundle fallback use the same casing rules.
"""
import argparse
import copy
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "Gradely/Resources/Localizable.xcstrings"
AUTHORED = ROOT / "Gradely/Resources/LocalizableCO.xcstrings"
RUNTIME = ROOT / "Gradely/Stores/AppLanguageStore.swift"
DIALECTS = (("en", "en-CO"), ("cs", "cs-US"))


def runtime_rules():
    source = RUNTIME.read_text(encoding="utf-8")
    token_match = re.search(r"private static let preservedTokens = \[(.*?)\]\.sorted", source, re.S)
    format_match = re.search(r'private static let formatRegex:.*?let pattern = ("(?:[^"\\]|\\.)*")', source, re.S)
    if not token_match or not format_match:
        raise ValueError("Cannot read CO casing rules from AppLanguageStore.swift")
    tokens = [json.loads('"' + token + '"') for token in re.findall(r'"((?:[^"\\]|\\.)*)"', token_match.group(1))]
    return sorted(tokens, key=len, reverse=True), re.compile(json.loads(format_match.group(1)))


def transform(text, brands, format_pattern):
    protected = []

    def protect(value):
        marker = "\ue000" + str(len(protected)) + "\ue001"
        protected.append((marker, value))
        return marker

    text = format_pattern.sub(lambda match: protect(match.group(0)), text)
    for brand in brands:
        text = re.sub(r"(?<!\w)" + re.escape(brand) + r"(?!\w)", lambda match, brand=brand: protect(brand), text, flags=re.I)
    text = text.lower()
    for marker, value in reversed(protected):
        text = text.replace(marker, value)
    return text


def transformed_localization(localization, brands, format_pattern):
    result = copy.deepcopy(localization)

    def visit(node):
        if isinstance(node, dict):
            unit = node.get("stringUnit")
            if isinstance(unit, dict) and isinstance(unit.get("value"), str):
                unit["value"] = transform(unit["value"], brands, format_pattern)
            for value in node.values():
                visit(value)
        elif isinstance(node, list):
            for value in node:
                visit(value)

    visit(result)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--write", action="store_true", help="fill missing dialect translations")
    mode.add_argument("--check", action="store_true", help="check without changing files (default)")
    args = parser.parse_args()
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    authored = json.loads(AUTHORED.read_text(encoding="utf-8"))["strings"]
    brands, format_pattern = runtime_rules()
    missing = []
    for key, entry in catalog["strings"].items():
        localizations = entry.get("localizations", {})
        for base, dialect in DIALECTS:
            if base not in localizations or dialect in localizations:
                continue
            missing.append((key, dialect))
            if args.write:
                custom = authored.get(key, {}).get("localizations", {}).get(base)
                localizations[dialect] = copy.deepcopy(custom) if custom is not None else transformed_localization(localizations[base], brands, format_pattern)
    mismatches = []
    for key, entry in authored.items():
        for base, dialect in DIALECTS:
            custom = entry.get("localizations", {}).get(base, {}).get("stringUnit", {}).get("value")
            native = catalog["strings"].get(key, {}).get("localizations", {}).get(dialect, {}).get("stringUnit", {}).get("value")
            if custom is not None and native is not None and custom != native:
                mismatches.append((key, dialect))
    if mismatches:
        for key, dialect in mismatches:
            print("Authored/native CO mismatch {}: {}".format(dialect, key))
        print("Update both LocalizableCO and the matching Localizable dialect entry to the intended wording.")
        return 1
    if missing and args.write:
        rendered = json.dumps(catalog, ensure_ascii=False, indent=2, separators=(",", " : "))
        # Match Xcode's empty-object layout to avoid unrelated catalog churn.
        rendered = re.sub(r'(?m)^( +)("(?:[^"\\]|\\.)*" : )\{\}(,?)$',
                          lambda match: match[1] + match[2] + "{\n\n" + match[1] + "}" + match[3], rendered)
        CATALOG.write_text(rendered + "\n", encoding="utf-8")
        print("Filled {} missing CO translations; authored variants unchanged.".format(len(missing)))
        return 0
    if missing:
        for key, dialect in missing:
            print("Missing {}: {}".format(dialect, key))
        print("Run python3 Scripts/sync-co-localizations.py --write")
        return 1
    print("CO localization check passed: all dialect variants exist and authored/native copy agrees.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
