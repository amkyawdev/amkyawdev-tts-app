#!/usr/bin/env python3
"""Generate launcher icons from assets/branding/icon.svg.

The SVG is the canonical source. Flutter/Android/iOS cannot consume SVG
launcher icons directly, so this script rasterises it with cairosvg:

    pip install cairosvg
    python3 tool/generate_icons.py

Outputs:
  * android/app/src/main/res/mipmap-*/ic_launcher.png          legacy icon
  * android/app/src/main/res/mipmap-*/ic_launcher_foreground.png
                                                              adaptive foreground
  * ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png        opaque App Store set
  * assets/branding/icon_256.png, icon_512.png                 in-app brand mark

Adaptive icons put the glyph inside a 108dp canvas so the launcher mask never
clips it; legacy and iOS icons are full-bleed and opaque.
"""

from __future__ import annotations

import io
import re
from pathlib import Path

import cairosvg

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets" / "branding" / "icon.svg"
BACKGROUND = "#0A0A11"
GLYPH_INSET = 0.60  # fraction of the canvas occupied by the glyph viewBox

ANDROID_DENSITIES = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}

ADAPTIVE_DENSITIES = {
    "mdpi": 108,
    "hdpi": 162,
    "xhdpi": 216,
    "xxhdpi": 324,
    "xxxhdpi": 432,
}

IOS_ICONS = {
    "Icon-App-20x20@1x.png": 20,
    "Icon-App-20x20@2x.png": 40,
    "Icon-App-20x20@3x.png": 60,
    "Icon-App-29x29@1x.png": 29,
    "Icon-App-29x29@2x.png": 58,
    "Icon-App-29x29@3x.png": 87,
    "Icon-App-40x40@1x.png": 40,
    "Icon-App-40x40@2x.png": 80,
    "Icon-App-40x40@3x.png": 120,
    "Icon-App-60x60@2x.png": 120,
    "Icon-App-60x60@3x.png": 180,
    "Icon-App-76x76@1x.png": 76,
    "Icon-App-76x76@2x.png": 152,
    "Icon-App-83.5x83.5@2x.png": 167,
    "Icon-App-1024x1024@1x.png": 1024,
}


def glyph_markup() -> str:
    text = SOURCE.read_text(encoding="utf-8")
    inner = re.search(r"<svg[^>]*>(.*)</svg>", text, re.S)
    if inner is None:
        raise SystemExit("icon.svg is not a valid SVG document")
    return inner.group(1)


def document(*, background: bool, inset: float, radius: float = 0.0) -> str:
    glyph = glyph_markup()
    scale = inset
    parts = [
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" '
        'width="512" height="512">',
    ]
    if background:
        parts.append(
            f'<rect x="0" y="0" width="512" height="512" rx="{radius}" '
            f'fill="{BACKGROUND}"/>'
        )
    parts.append(
        f'<g transform="translate(256 256) scale({scale}) translate(-256 -256)">'
    )
    parts.append(glyph)
    parts.append("</g></svg>")
    return "".join(parts)


def render(svg: str, size: int) -> bytes:
    return cairosvg.svg2png(
        bytestring=svg.encode("utf-8"),
        output_width=size,
        output_height=size,
    )


def write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    print(f"  {path.relative_to(ROOT)}  ({len(data)} bytes)")


def main() -> None:
    res = ROOT / "android" / "app" / "src" / "main" / "res"
    ios = ROOT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    branding = ROOT / "assets" / "branding"

    legacy_svg = document(background=True, inset=0.86, radius=96)
    adaptive_svg = document(background=False, inset=GLYPH_INSET)
    ios_svg = document(background=True, inset=0.80)

    print("Android legacy launcher icons")
    for density, size in ANDROID_DENSITIES.items():
        write(res / f"mipmap-{density}" / "ic_launcher.png", render(legacy_svg, size))

    print("Android adaptive foreground icons")
    for density, size in ADAPTIVE_DENSITIES.items():
        write(
            res / f"mipmap-{density}" / "ic_launcher_foreground.png",
            render(adaptive_svg, size),
        )

    print("iOS app icons")
    for name, size in IOS_ICONS.items():
        write(ios / name, render(ios_svg, size))

    print("In-app brand marks")
    write(branding / "icon_256.png", render(document(background=True, inset=0.92, radius=72), 256))
    write(branding / "icon_512.png", render(document(background=True, inset=0.92, radius=144), 512))
    # Transparent glyph for documentation and theming.
    write(branding / "icon_glyph_512.png", render(document(background=False, inset=1.0), 512))

    print("Done.")


if __name__ == "__main__":
    main()
