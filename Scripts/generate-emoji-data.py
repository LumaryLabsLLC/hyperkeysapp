#!/usr/bin/env python3
"""Regenerates HyperKeysPackage/Sources/HyperKeysFeature/Resources/emoji.json.

Sources (Unicode, Inc. — https://www.unicode.org/terms_of_use.html):
  - Emoji list, names and groups: https://unicode.org/Public/emoji/latest/emoji-test.txt
  - Search keywords (CLDR):        https://github.com/unicode-org/cldr-json (annotations/en)

Output: [{"name": group, "emoji": [[emoji, name, [keywords…]], …]}, …]
Skin-tone variants and the "Component" group are skipped; Smileys and People are merged.
"""
import json
import re
import urllib.request
from pathlib import Path

EMOJI_TEST = "https://unicode.org/Public/emoji/latest/emoji-test.txt"
ANNOTATIONS = "https://raw.githubusercontent.com/unicode-org/cldr-json/main/cldr-json/cldr-annotations-full/annotations/en/annotations.json"
OUTPUT = Path(__file__).resolve().parent.parent / "HyperKeysPackage/Sources/HyperKeysFeature/Resources/emoji.json"
MERGE = {"Smileys & Emotion": "Smileys & People", "People & Body": "Smileys & People"}
SKIN_TONES = {chr(c) for c in range(0x1F3FB, 0x1F400)}


def fetch(url):
    with urllib.request.urlopen(url) as response:
        return response.read().decode("utf-8")


def main():
    annotations = json.loads(fetch(ANNOTATIONS))["annotations"]["annotations"]

    def keywords(emoji):
        for key in (emoji, emoji.replace("️", "")):
            if key in annotations:
                return annotations[key].get("default", [])
        return []

    groups, order, group = {}, [], None
    for line in fetch(EMOJI_TEST).splitlines():
        if line.startswith("# group:"):
            name = line.split(":", 1)[1].strip()
            group = MERGE.get(name, name)
            if group != "Component" and group not in groups:
                groups[group] = []
                order.append(group)
            continue
        if "; fully-qualified" not in line or group == "Component":
            continue
        match = re.match(r"^[0-9A-F ]+;\s*fully-qualified\s*#\s*(\S+)\s+E[\d.]+\s+(.+)$", line.strip())
        if not match or any(ch in SKIN_TONES for ch in match.group(1)):
            continue
        emoji, name = match.group(1), match.group(2).replace("flag: ", "flag ")
        groups[group].append([emoji, name, [k for k in keywords(emoji) if k.lower() != name.lower()]])

    data = [{"name": g, "emoji": groups[g]} for g in order]
    OUTPUT.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"Wrote {sum(len(g['emoji']) for g in data)} emoji to {OUTPUT}")


if __name__ == "__main__":
    main()
