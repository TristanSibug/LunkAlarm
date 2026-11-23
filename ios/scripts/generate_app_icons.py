#!/usr/bin/env python3
"""Render the theme app icons with Inkscape and Pillow, or verify a built bundle."""

import argparse
from io import BytesIO
import json
from pathlib import Path
import plistlib
import re
import subprocess


IOS = Path(__file__).resolve().parents[1]
CATALOG = IOS / "LunkAlarm/Resources/Assets.xcassets"
THEMES = IOS / "LunkAlarm/Views/AlarmTheme.swift"


def color(line, field):
    match = re.search(rf"\b{field}: (?:Color\(hex: 0x([0-9a-fA-F]{{6}})\)|\.(black|white))", line)
    if not match:
        raise ValueError(f"Missing {field} in {line.strip()}")
    return f"#{match[1]}" if match[1] else match[2]


def theme_colors():
    for line in THEMES.read_text().splitlines():
        match = re.search(r'AlarmTheme\(id: "([a-z-]+)"', line)
        if not match or match[1] == "sunrise":
            continue
        theme = match[1]
        clapper = color(line, "card") if theme == "signal-blue" else "url(#bell)"
        yield f"AppIcon-{theme}", color(line, "background"), color(line, "accent"), color(line, "accent2"), clapper


def generate():
    from PIL import Image

    for name, background, accent, second_accent, clapper in theme_colors():
        # Render the original outline and clapper proportions on a full-bleed
        # square. iOS applies the Home Screen mask.
        svg = f"""<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024">
  <defs>
    <linearGradient id="bell" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop stop-color="{accent}"/>
      <stop offset="1" stop-color="{second_accent}"/>
    </linearGradient>
  </defs>
  <rect width="1024" height="1024" fill="{background}"/>
  <path d="M242 670 C301 622 332 531 332 402 C332 303 413 220 512 220
           C611 220 692 303 692 402 C692 531 723 622 782 670 Z"
        fill="none" stroke="url(#bell)" stroke-width="45" stroke-linejoin="round"/>
  <path d="M461 790 C484 828 540 828 563 790" fill="none"
        stroke="{clapper}" stroke-width="45" stroke-linecap="round"/>
</svg>"""
        png = subprocess.run(
            ["inkscape", "--pipe", "--export-type=png", "--export-filename=-"],
            input=svg.encode(), stdout=subprocess.PIPE, check=True,
        ).stdout
        directory = CATALOG / f"{name}.appiconset"
        directory.mkdir(exist_ok=True)
        Image.open(BytesIO(png)).convert("RGB").save(directory / "AppIcon.png", optimize=True)
        contents = {
            "images": [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
            "info": {"author": "xcode", "version": 1},
        }
        (directory / "Contents.json").write_text(json.dumps(contents, separators=(",", ":")) + "\n")


def verify_bundle(bundle):
    expected = {name for name, *_ in theme_colors()}
    with (bundle / "Info.plist").open("rb") as file:
        plist = plistlib.load(file)
    for key in ("CFBundleIcons", "CFBundleIcons~ipad"):
        metadata = plist.get(key, plist.get("CFBundleIcons", {}))
        actual = set(metadata.get("CFBundleAlternateIcons", {}))
        if actual != expected:
            raise SystemExit(f"{key}: missing {sorted(expected - actual)}, unexpected {sorted(actual - expected)}")
        if not metadata.get("CFBundlePrimaryIcon"):
            raise SystemExit(f"{key}: missing the primary Sunrise icon")
    print(f"Verified the primary icon and {len(expected)} alternate icons for iPhone and iPad.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify-bundle", type=Path)
    arguments = parser.parse_args()
    if arguments.verify_bundle:
        verify_bundle(arguments.verify_bundle)
    else:
        generate()
