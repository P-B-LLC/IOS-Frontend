#!/usr/bin/env python3
"""Every string the app looks up must be in the catalog.

The catalog tests check what is in `Localizable.xcstrings`: every entry
translated into every language, no entry left stale. They cannot see a string
that never reached the catalog. Xcode adds new strings after an IDE build, but
`xcodebuild` does not, so code written and built from the command line can
ship strings that show in English in every language while every test passes.

That happened when main's photo and video posts merged into the localized
branch: twelve composer and feed strings were missing, and nothing failed.

The compiler already says which strings the code looks up. Each Swift file's
build leaves a `.stringsdata` file listing them, and this compares those keys
against the catalog.

    python3 Scripts/check-localization-coverage.py [derived-data-path]

Build first (the CI Build step's command will do; the default path is its
`.build/DerivedData`). Exits non-zero and names every missing string with
where it is used. Add it to the catalog and translate it for every language;
`bash Scripts/sync-localizations.sh` adds it untranslated.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "IOS Frontend" / "IOS Frontend" / "Localizable.xcstrings"
TABLE = "Localizable"


def objects_directory(derived: Path) -> Path | None:
    """The app target's intermediates for one architecture.

    Debug and Release extract the same strings, so one build is enough. The
    widget extension has its own target directory and is left out: its strings
    live in the same catalog but are looked up through the app's bundle only
    when the app draws them.
    """
    base = derived / "Build" / "Intermediates.noindex" / "IOS Frontend.build"
    candidates = sorted(base.glob("*/IOS Frontend.build/Objects-normal/arm64"))
    return candidates[0] if candidates else None


def used_strings(objects: Path) -> dict[str, list[str]]:
    used: dict[str, list[str]] = {}
    for path in sorted(objects.glob("*.stringsdata")):
        if path.name == "ExtractedAppShortcutsMetadata.stringsdata":
            continue
        data = json.loads(path.read_text())
        source = Path(data.get("source", path.stem)).name
        for entry in data.get("tables", {}).get(TABLE, []):
            line = entry.get("location", {}).get("startingLine", "?")
            used.setdefault(entry["key"], []).append(f"{source}:{line}")
    return used


def main() -> int:
    derived = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / ".build" / "DerivedData"
    objects = objects_directory(derived)
    if objects is None:
        print(f"No app build found under {derived}. Build the app first.")
        return 1

    used = used_strings(objects)
    if not used:
        print(f"The build in {objects} extracted no strings. Is SWIFT_EMIT_LOC_STRINGS on?")
        return 1

    catalog = json.loads(CATALOG.read_text())["strings"]
    missing = sorted(key for key in used if key not in catalog)
    print(f"checking {len(used)} strings the code looks up against {len(catalog)} catalog entries")
    if missing:
        print(f"\n{len(missing)} not in {CATALOG.name}, so shown in English in every language:")
        for key in missing:
            print(f"  {key!r}  ({', '.join(used[key][:3])})")
        return 1

    print("every string the code looks up is in the catalog")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
