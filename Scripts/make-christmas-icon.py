#!/usr/bin/env python3
"""Paints Gradey's Christmas icons from the regular one.

The regular icon is a hand-drawn paper on a mint-to-green gradient. Every
green pixel is repainted on a light-to-deep red gradient: the position on the
gradient comes from the pixel's saturation (the green runs from 0.48 in the
top-left to 1.0 in the bottom-right) and the result keeps the pixel's
brightness, so the anti-aliased edges against the black lines stay clean.
The paper, the lines and the red A+ are left alone.

Writes:
  AppIconChristmas.appiconset/christmas-1024.png  (iOS alternate icon)
  ChristmasDockIcon.imageset/christmas-dock.png   (Mac Dock tile, pre-masked)

Needs Pillow. Run from anywhere: python3 Scripts/make-christmas-icon.py
"""

import colorsys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "Gradely" / "Assets.xcassets"
SOURCE = ASSETS / "AppIcon.appiconset" / "IMG_0362.png"
IOS_OUT = ASSETS / "AppIconChristmas.appiconset" / "christmas-1024.png"
DOCK_OUT = ASSETS / "ChristmasDockIcon.imageset" / "christmas-dock.png"

LIGHT_RED = (0xFF, 0x5A, 0x6A)
DEEP_RED = (0xD0, 0x10, 0x2C)

# The macOS icon grid: an 824-point rounded square centred on a 1024 canvas.
MAC_CANVAS = 1024
MAC_SHAPE = 824
MAC_RADIUS = 185.4


def repaint(image: Image.Image) -> Image.Image:
    image = image.convert("RGB")
    pixels = image.load()
    width, height = image.size
    for y in range(height):
        for x in range(width):
            r, g, b = pixels[x, y]
            hue, saturation, value = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            if saturation < 0.12 or not 100 / 360 <= hue <= 190 / 360:
                continue
            t = min(max((saturation - 0.48) / 0.52, 0), 1)
            pixels[x, y] = tuple(
                round((light + (deep - light) * t) * value)
                for light, deep in zip(LIGHT_RED, DEEP_RED)
            )
    return image


def dock_tile(art: Image.Image) -> Image.Image:
    scale = 4
    big = MAC_CANVAS * scale
    inset = (MAC_CANVAS - MAC_SHAPE) // 2 * scale
    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (inset, inset, big - inset - 1, big - inset - 1),
        radius=MAC_RADIUS * scale,
        fill=255,
    )
    mask = mask.resize((MAC_CANVAS, MAC_CANVAS), Image.LANCZOS)

    offset = (MAC_CANVAS - MAC_SHAPE) // 2
    content = Image.new("RGBA", (MAC_CANVAS, MAC_CANVAS), (0, 0, 0, 0))
    content.paste(art.resize((MAC_SHAPE, MAC_SHAPE), Image.LANCZOS), (offset, offset))
    content.putalpha(mask)

    shadow_alpha = ImageChops.offset(mask, 0, 10).filter(ImageFilter.GaussianBlur(12))
    shadow_alpha = shadow_alpha.point(lambda a: int(a * 0.3))
    shadow = Image.new("RGBA", (MAC_CANVAS, MAC_CANVAS), (0, 0, 0, 0))
    shadow.putalpha(shadow_alpha)
    return Image.alpha_composite(shadow, content)


def main() -> None:
    art = repaint(Image.open(SOURCE))
    IOS_OUT.parent.mkdir(exist_ok=True)
    DOCK_OUT.parent.mkdir(exist_ok=True)
    art.save(IOS_OUT, optimize=True)
    dock_tile(art).save(DOCK_OUT, optimize=True)
    print(f"Wrote {IOS_OUT.relative_to(ROOT)} and {DOCK_OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
