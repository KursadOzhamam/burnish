#!/usr/bin/env python3
"""Every String Catalog entry must have both Turkish and English text (CLAUDE.md §15)."""
import glob, json, sys

problems = []
for path in glob.glob("**/Localizable.xcstrings", recursive=True):
    if "/.build/" in path or "/DerivedData/" in path:
        continue
    catalog = json.load(open(path, encoding="utf-8"))
    for key, entry in catalog.get("strings", {}).items():
        locs = entry.get("localizations", {})
        for lang in ("tr", "en"):
            value = locs.get(lang, {}).get("stringUnit", {}).get("value", "")
            if not value.strip():
                problems.append(f"{path}: '{key}' has no {lang} text")
if problems:
    print("\n".join(problems))
    sys.exit(1)
print("localization: every entry has tr and en")
