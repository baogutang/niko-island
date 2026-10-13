#!/usr/bin/env python3
"""Add or update Simplified Chinese translations in Assets/Localizable.xcstrings.

    scripts/add-strings.py <<'JSON'
    { "English key": "中文", "Another %@ key": "另一个 %@" }
    JSON

Keys are the English strings passed to L() in the code. `--prune FILE...`
additionally drops keys that no longer appear in the given Swift sources.
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CATALOG = ROOT / "Assets" / "Localizable.xcstrings"


def main() -> int:
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    strings = catalog["strings"]
    incoming = json.loads(sys.stdin.read() or "{}")
    for key, value in incoming.items():
        strings[key] = {"localizations": {"zh-Hans": {"stringUnit": {"state": "translated", "value": value}}}}
    if "--prune" in sys.argv:
        used = set()
        for path in (ROOT / "Sources").rglob("*.swift"):
            text = path.read_text(encoding="utf-8")
            used.update(m.group(1).encode().decode("unicode_escape").encode("latin-1").decode("utf-8")
                        if "\\" in m.group(1) else m.group(1)
                        for m in re.finditer(r'L\("((?:[^"\\]|\\.)*)"', text))
        stale = sorted(k for k in strings if k not in used)
        for key in stale:
            del strings[key]
        print(f"pruned {len(stale)}: {stale}" if stale else "nothing to prune")
    catalog["strings"] = dict(sorted(strings.items()))
    CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"{len(incoming)} added or updated, {len(strings)} strings in the catalog")
    return 0


if __name__ == "__main__":
    sys.exit(main())
