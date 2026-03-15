#!/usr/bin/env python3

from __future__ import annotations

import json
import os
import re
import sys
from collections import defaultdict
from pathlib import Path


ENGINE_PATTERNS = [
    ("madara", re.compile(r"\bMadara\b")),
    ("mangaThemesia", re.compile(r"\bMangaThemesia\b")),
    ("zeistManga", re.compile(r"\bZeistManga\b")),
    ("fmReader", re.compile(r"\bFMReader\b")),
    ("foolSlide", re.compile(r"\bFoolSlide\b")),
    ("newToki", re.compile(r"\bNewToki\b")),
    ("natsuId", re.compile(r"\bNatsuId\b")),
    ("api", re.compile(r"\bGraphQL\b|\bRetrofit\b|\bJsonObject\b")),
]


def classify_file(text: str) -> str:
    for family, pattern in ENGINE_PATTERNS:
        if pattern.search(text):
            return family
    if "HttpSource" in text or "ParsedHttpSource" in text:
        return "customParsed"
    return "unknown"


def main() -> int:
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("./extensions-source/src")
    if not root.exists():
        print(json.dumps({"error": f"missing path: {root}"}))
        return 1

    families: dict[str, list[dict[str, str]]] = defaultdict(list)
    unsupported: list[dict[str, str]] = []
    seen_sources: set[tuple[str, str]] = set()

    for path in root.rglob("*.kt"):
        if "/src/eu/kanade/tachiyomi/extension/" not in path.as_posix():
            continue
        text = path.read_text(encoding="utf-8", errors="ignore")
        family = classify_file(text)
        parts = path.parts
        try:
            src_index = parts.index("src")
            language = parts[src_index + 1]
            slug = parts[src_index + 2]
        except (ValueError, IndexError):
            language = "unknown"
            slug = path.stem.lower()

        record = {
            "language": language,
            "slug": slug,
            "path": path.as_posix(),
        }
        source_key = (language, slug)
        if source_key in seen_sources:
            continue
        seen_sources.add(source_key)
        families[family].append(record)
        if family == "unknown":
            unsupported.append(record)

    counts = {family: len(items) for family, items in sorted(families.items(), key=lambda item: (-len(item[1]), item[0]))}
    payload = {
        "sourceRoot": root.as_posix(),
        "counts": counts,
        "families": families,
        "unsupported": unsupported,
    }
    json.dump(payload, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
