#!/usr/bin/env python3
"""Build every Vow icon from the source artwork in docs/assets/icon.png.

Run from the repository root: python3 scripts/make-icon.py (needs Pillow).

Writes:
  apps/apple/Vow/AppIcon.icon           the Icon Composer document Xcode ships
                                        (iPadOS and macOS 26: one glass layer
                                        over an indigo fill)
  apps/apple/Vow/Assets.xcassets/AppIcon.appiconset
                                        flat renditions of the same design
  apps/web/public/vow-mark.png          the icon on the site's closing panel
  apps/web/public/vow-glyph.png         the bare V in the site's header
  apps/web/src/app/icon.png             the site's favicon
"""

import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "docs/assets/icon.png"
ICON = ROOT / "apps/apple/Vow/AppIcon.icon"
ICONSET = ROOT / "apps/apple/Vow/Assets.xcassets/AppIcon.appiconset"
WEB = ROOT / "apps/web"

CANVAS = 1024
# The glyph spans 62% of the canvas, inside Apple's icon grid, so the system's
# corner mask and Liquid Glass edge never touch it.
GLYPH_WIDTH = 636
# A V carries its weight high. Centred on its bounding box it reads as sitting
# high, and centred on its centre of mass it sits low, so it rests halfway.
OPTICAL_SHIFT = 10

# Deep indigo in both appearances. The artwork's pale lavender ridges wash out
# on a light ground; on indigo every ridge reads, down to 16 px.
GROUND = ((30, 27, 62), (14, 12, 34))
FILL = "srgb:0.07500,0.06700,0.16500,1.00000"

# macOS's icon body: an 824 pt rounded square in a 1024 pt canvas, with the
# standard soft shadow under it.
MAC_BODY = 824
MAC_SHADOW = dict(offset=12, blur=14, alpha=90)


def artwork() -> Image.Image:
    """The V alone, cropped to its edges."""
    art = Image.open(SOURCE).convert("RGBA")
    alpha = art.getchannel("A").point(lambda v: 0 if v < 12 else v)  # drop the cut-out's haze
    art.putalpha(alpha)
    return art.crop(alpha.getbbox())


def glyph_layer() -> Image.Image:
    """The artwork alone on a transparent 1024 canvas, sized and placed."""
    art = artwork()
    height = round(art.height * GLYPH_WIDTH / art.width)
    art = art.resize((GLYPH_WIDTH, height), Image.LANCZOS)
    layer = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    layer.alpha_composite(art, ((CANVAS - GLYPH_WIDTH) // 2, (CANVAS - height) // 2 + OPTICAL_SHIFT))
    return layer


def background(size: int) -> Image.Image:
    ramp = Image.linear_gradient("L").resize((size, size))
    top = Image.new("RGB", (size, size), GROUND[0])
    bottom = Image.new("RGB", (size, size), GROUND[1])
    return Image.composite(bottom, top, ramp).convert("RGBA")


def squircle(size: int, exponent: float = 5.0) -> Image.Image:
    """A continuous-corner mask, the shape Apple's platforms round icons to."""
    scale = 4
    big = size * scale
    half = big / 2
    points = []
    for step in range(720):
        angle = 2 * math.pi * step / 720
        c, s = math.cos(angle), math.sin(angle)
        x = half + half * math.copysign(abs(c) ** (2 / exponent), c)
        y = half + half * math.copysign(abs(s) ** (2 / exponent), s)
        points.append((x, y))
    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).polygon(points, fill=255)
    return mask.resize((size, size), Image.LANCZOS)


def flat(glyph: Image.Image) -> Image.Image:
    """iPadOS: a full-bleed, opaque square. The system rounds it."""
    tile = background(CANVAS)
    tile.alpha_composite(glyph)
    return tile.convert("RGB")


def rounded(tile: Image.Image) -> Image.Image:
    """The flat icon with its corners cut, for places that do not mask it."""
    out = tile.convert("RGBA")
    out.putalpha(squircle(CANVAS))
    return out


def mac(tile: Image.Image) -> Image.Image:
    """macOS: the same design on the 824 pt body, with its shadow, in a clear canvas."""
    inset = (CANVAS - MAC_BODY) // 2
    mask = squircle(MAC_BODY)
    body = tile.convert("RGBA").resize((MAC_BODY, MAC_BODY), Image.LANCZOS)
    body.putalpha(mask)
    shadow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    shade = Image.new("RGBA", (MAC_BODY, MAC_BODY), (0, 0, 0, MAC_SHADOW["alpha"]))
    shade.putalpha(mask.point(lambda v: v * MAC_SHADOW["alpha"] // 255))
    shadow.alpha_composite(shade, (inset, inset + MAC_SHADOW["offset"]))
    shadow = shadow.filter(ImageFilter.GaussianBlur(MAC_SHADOW["blur"]))
    shadow.alpha_composite(body, (inset, inset))
    return shadow


def main() -> None:
    glyph = glyph_layer()
    tile = flat(glyph)

    # The layered document: one fill, one glass layer. The system adds the
    # highlights, the shadow and the tinted and clear renditions.
    (ICON / "Assets").mkdir(parents=True, exist_ok=True)
    glyph.save(ICON / "Assets/glyph.png")
    document = {
        "fill": {"automatic-gradient": FILL},
        "groups": [
            {
                "layers": [{"glass": True, "image-name": "glyph.png", "name": "glyph"}],
                "shadow": {"kind": "neutral", "opacity": 0.5},
                "specular": True,
                "translucency": {"enabled": False, "value": 0},
            }
        ],
        "supported-platforms": {"squares": "shared"},
    }
    (ICON / "icon.json").write_text(json.dumps(document, indent=2) + "\n")

    # Flat renditions for the asset catalog.
    tile.save(ICONSET / "AppIcon-iPad.png")
    desktop = mac(tile)
    for points in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            size = points * scale
            desktop.resize((size, size), Image.LANCZOS).save(ICONSET / f"AppIcon-{points}@{scale}x.png")

    # The website: the bare V for the header, the square icon for the closing
    # panel, a rounded one for the tab.
    bare = artwork()
    bare.resize((280, round(bare.height * 280 / bare.width)), Image.LANCZOS).save(
        WEB / "public/vow-glyph.png"
    )
    tile.resize((256, 256), Image.LANCZOS).save(WEB / "public/vow-mark.png")
    rounded(tile).resize((256, 256), Image.LANCZOS).save(WEB / "src/app/icon.png")


if __name__ == "__main__":
    main()
