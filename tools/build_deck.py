#!/usr/bin/env python3
"""Builds the Deep Math deck from content/*.yaml.

Reads content/course.yaml (levels and branches) and one content/<branch>.yaml per branch,
checks every card, orders the deck from Grade 5 up to Masters, and writes
app/Sources/DeepMath/Resources/deck.json. Every formula is then parsed with the bundled
KaTeX (tools/check_tex.mjs), so a typo fails the build instead of showing up as red text
in the app.

Usage: python3 tools/build_deck.py [--out PATH] [--skip-tex-check]
"""
import argparse
import json
import shutil
import subprocess
import sys
from collections import Counter
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
CONTENT = ROOT / "content"
DEFAULT_OUT = ROOT / "app" / "Sources" / "DeepMath" / "Resources" / "deck.json"

NOTATION_FIELDS = {"id", "group", "level", "name", "tex", "read", "meaning", "example", "ai"}
EQUATION_FIELDS = {"id", "group", "level", "name", "tex", "read", "meaning", "terms", "ai", "cite"}
REQUIRED = {"id", "group", "level", "name", "tex", "read", "meaning"}


def fail(msg):
    sys.exit(f"error: {msg}")


def text(value):
    return " ".join(str(value).split()) if value is not None else ""


def load_cards(source, levels, seen):
    path = CONTENT / f"{source['id']}.yaml"
    if not path.exists():
        fail(f"{path.relative_to(ROOT)} is missing")
    data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    groups = {g["id"]: i for i, g in enumerate(source["groups"])}
    cards = []
    for kind, fields in (("notation", NOTATION_FIELDS), ("equation", EQUATION_FIELDS)):
        key = "notation" if kind == "notation" else "equations"
        for raw in data.get(key) or []:
            where = f"{path.name}: {raw.get('id', '?')}"
            if missing := REQUIRED - raw.keys():
                fail(f"{where} is missing {sorted(missing)}")
            if unknown := raw.keys() - fields:
                fail(f"{where} has unknown fields {sorted(unknown)}")
            if raw["id"] in seen:
                fail(f"{where}: duplicate id (also in {seen[raw['id']]})")
            seen[raw["id"]] = path.name
            if raw["group"] not in groups:
                fail(f"{where}: group {raw['group']!r} is not listed for {source['id']} in course.yaml")
            if raw["level"] not in levels:
                fail(f"{where}: level {raw['level']!r} is not one of {sorted(levels)}")
            terms = []
            for term in raw.get("terms") or []:
                if not (isinstance(term, list) and len(term) == 2):
                    fail(f"{where}: each term must be a [tex, meaning] pair, got {term!r}")
                terms.append({"tex": str(term[0]).strip(), "text": text(term[1])})
            cards.append({
                "id": raw["id"],
                "kind": kind,
                "src": source["id"],
                "group": raw["group"],
                "level": raw["level"],
                "name": text(raw["name"]),
                "tex": str(raw["tex"]).strip(),
                "read": text(raw["read"]),
                "meaning": text(raw["meaning"]),
                "example": str(raw.get("example") or "").strip(),
                "terms": terms,
                "ai": text(raw.get("ai")),
                "cite": text(raw.get("cite")),
                "_order": (raw["level"], groups[raw["group"]], len(cards)),
            })
    return cards


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT)
    ap.add_argument("--skip-tex-check", action="store_true", help="don't parse formulas with KaTeX")
    args = ap.parse_args()

    course = yaml.safe_load((CONTENT / "course.yaml").read_text(encoding="utf-8"))
    levels = {lv["id"]: lv["label"] for lv in course["levels"]}
    seen = {}
    cards = []
    for rank, source in enumerate(course["sources"]):
        for card in load_cards(source, levels, seen):
            level, group, index = card["_order"]
            card["_order"] = (level, rank, group, index)
            cards.append(card)
    cards.sort(key=lambda c: c.pop("_order"))

    deck = {
        "title": course["title"],
        "levels": course["levels"],
        "sources": [
            {"id": s["id"], "title": s["title"], "ai": s.get("ai", ""),
             "groups": [{"id": g["id"], "label": g["label"]} for g in s["groups"]]}
            for s in course["sources"]
        ],
        "cards": cards,
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(deck, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")

    if not args.skip_tex_check:
        node = shutil.which("node")
        if node is None:
            print("warning: node not found; formulas were not checked with KaTeX", file=sys.stderr)
        else:
            result = subprocess.run([node, str(ROOT / "tools" / "check_tex.mjs"), str(args.out)])
            if result.returncode != 0:
                sys.exit(result.returncode)

    kinds = Counter(c["kind"] for c in cards)
    print(f"Wrote {args.out.relative_to(ROOT) if args.out.is_relative_to(ROOT) else args.out}: "
          f"{kinds['notation']} notation cards, {kinds['equation']} equation cards")
    by_source = Counter(c["src"] for c in cards)
    by_level = Counter(c["level"] for c in cards)
    for s in course["sources"]:
        print(f"  {s['title']:<28} {by_source[s['id']]:>4}")
    for lv in course["levels"]:
        print(f"  {lv['label']:<28} {by_level[lv['id']]:>4}")


if __name__ == "__main__":
    main()
