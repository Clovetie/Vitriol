#!/usr/bin/env python3
"""qte-preview-png.py - rasterise the QTE overlay preview.

`tools/qte-build-ui.js` writes the layout preview as SVG, because SVG is the
format that stays correct at any size and opens anywhere. Some places to look at
a file (a chat, a document, an issue) only take a bitmap, so this script renders
the same file to PNG.

It reads the generated SVG - it does not know anything about the overlay - so it
can only ever draw what the SVG already says.

Usage:
    python3 tools/qte-preview-png.py                       # qte/UI/QTEOverlay.preview.svg -> .png
    python3 tools/qte-preview-png.py IN.svg OUT.png

Requires Pillow (`pip install pillow`).
"""

import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:  # pragma: no cover - dependency hint
    sys.exit("qte-preview-png: Pillow is required (`pip install pillow`)")

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_IN = ROOT / "qte/UI/QTEOverlay.preview.svg"
DEFAULT_OUT = ROOT / "qte/UI/QTEOverlay.preview.png"

SUPERSAMPLE = 2
FONT_BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
FONT_REGULAR = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
NS = "{http://www.w3.org/2000/svg}"


def parse_colour(value):
    """'rgb(1,2,3)' / 'rgba(1,2,3,0.5)' / '#rrggbb' -> (r, g, b, a 0-255)."""
    value = (value or "").strip()
    if value.startswith("#"):
        value = value[1:]
        if len(value) == 3:
            value = "".join(c * 2 for c in value)
        return (int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16), 255)
    match = re.match(r"rgba?\(([^)]+)\)", value)
    if not match:
        return None
    parts = [p.strip() for p in match.group(1).split(",")]
    r, g, b = (int(float(p)) for p in parts[:3])
    alpha = float(parts[3]) if len(parts) > 3 else 1.0
    return (r, g, b, int(round(alpha * 255)))


def font_for(size, bold):
    path = FONT_BOLD if bold else FONT_REGULAR
    try:
        return ImageFont.truetype(path, int(size))
    except OSError:  # pragma: no cover - font path differs
        return ImageFont.load_default()


def load(svg_path):
    tree = ET.parse(svg_path)
    root = tree.getroot()
    width = int(float(root.get("width")))
    height = int(float(root.get("height")))
    return root, width, height


def draw(root, width, height, scale):
    canvas = Image.new("RGBA", (width * scale, height * scale), (0, 0, 0, 0))
    draw_ = ImageDraw.Draw(canvas, "RGBA")

    def px(value):
        return float(value) * scale

    for element in root.iter():
        tag = element.tag.replace(NS, "")
        if tag == "rect":
            colour = parse_colour(element.get("fill"))
            x, y = px(element.get("x", 0)), px(element.get("y", 0))
            w, h = px(element.get("width", 0)), px(element.get("height", 0))
            if w <= 0 or h <= 0:
                continue  # degenerate or intentionally empty: nothing to draw
            if colour and element.get("fill") != "none":
                draw_.rectangle([x, y, x + w - 1, y + h - 1], fill=colour)
            stroke = parse_colour(element.get("stroke"))
            if element.get("stroke") and element.get("stroke") != "none":
                dash = element.get("stroke-dasharray")
                if dash:
                    on, off = (float(part) * scale for part in dash.split())
                    step = on + off
                    # Dashes along the top and bottom edges only: a dashed outline is
                    # an annotation, and this keeps it readable at any rect size.
                    edge = x
                    while edge < x + w:
                        draw_.line([edge, y, min(edge + on, x + w), y], fill=stroke, width=max(1, int(scale)))
                        draw_.line([edge, y + h, min(edge + on, x + w), y + h], fill=stroke, width=max(1, int(scale)))
                        edge += step
                    edge = y
                    while edge < y + h:
                        draw_.line([x, edge, x, min(edge + on, y + h)], fill=stroke, width=max(1, int(scale)))
                        draw_.line([x + w, edge, x + w, min(edge + on, y + h)], fill=stroke, width=max(1, int(scale)))
                        edge += step
                else:
                    draw_.rectangle([x, y, x + w - 1, y + h - 1], outline=stroke, width=max(1, int(scale)))
        elif tag == "text":
            colour = parse_colour(element.get("fill")) or (255, 255, 255, 255)
            size = float(element.get("font-size", 12)) * scale
            text = element.text or ""
            if not text.strip():
                continue
            font = font_for(size, "700" in (element.get("font-weight") or "") or "800" in (element.get("font-weight") or ""))
            spacing = float(element.get("letter-spacing", 0)) * scale
            x, y = px(element.get("x", 0)), px(element.get("y", 0))
            if spacing > 0:
                total = sum(draw_.textlength(ch, font=font) + spacing for ch in text) - spacing
                cursor = x - total / 2
                for ch in text:
                    draw_.text((cursor, y), ch, font=font, fill=colour, anchor="lm")
                    cursor += draw_.textlength(ch, font=font) + spacing
            else:
                anchor = "mm" if element.get("text-anchor") == "middle" else "lm"
                draw_.text((x, y), text, font=font, fill=colour, anchor=anchor)
    return canvas


def main():
    argv = sys.argv[1:]
    src = Path(argv[0]) if len(argv) > 0 else DEFAULT_IN
    dst = Path(argv[1]) if len(argv) > 1 else (DEFAULT_OUT if len(argv) < 1 else src.with_suffix(".png"))
    if not src.exists():
        sys.exit(f"qte-preview-png: {src} not found - run `node tools/qte-build-ui.js` first")
    root, width, height = load(src)
    image = draw(root, width, height, SUPERSAMPLE)
    image = image.resize((width, height), Image.LANCZOS)
    dst.parent.mkdir(parents=True, exist_ok=True)
    image.save(dst)
    print(f"qte-preview-png: wrote {dst.relative_to(ROOT) if dst.is_relative_to(ROOT) else dst} ({width}x{height})")


if __name__ == "__main__":
    main()
