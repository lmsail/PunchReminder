#!/usr/bin/env python3
"""Render a 1024px macOS app icon: 824px squircle, indigo ring, white check."""

from pathlib import Path
import math

from PIL import Image, ImageChops, ImageDraw, ImageFilter

SIZE = 1024
SCALE = 4
S = SIZE * SCALE
CX = CY = S / 2
BODY = 824
MARGIN = 100
CORNER = 185.4
OUTER = S * 0.30
STROKE = S * 0.072


def body_box(scale=SCALE):
    margin = MARGIN * scale
    body = BODY * scale
    radius = CORNER * scale
    return (margin, margin, margin + body - 1, margin + body - 1), radius


def body_mask(size=S, scale=SCALE):
    mask = Image.new("L", (size, size), 0)
    box, radius = body_box(scale)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius=radius, fill=255)
    return mask


def plate():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    box, radius = body_box()
    draw.rounded_rectangle(box, radius=radius, fill=(247, 247, 248, 255))
    highlight = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    hd = ImageDraw.Draw(highlight)
    hd.rectangle((0, 0, S, int(S * 0.38)), fill=(255, 255, 255, 36))
    highlight = highlight.filter(ImageFilter.GaussianBlur(40 * SCALE))
    highlight.putalpha(ImageChops.multiply(highlight.split()[-1], body_mask()))
    return Image.alpha_composite(img, highlight)


def disc(draw, radius, fill):
    draw.ellipse((CX - radius, CY - radius, CX + radius, CY + radius), fill=fill)


def badge():
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    disc(draw, OUTER, (82, 94, 214, 255))
    disc(draw, OUTER - STROKE * 0.55, (72, 84, 204, 255))
    for i in range(12):
        angle = math.radians(i * 30 - 90)
        inner = OUTER * 0.78
        outer = OUTER * 0.92
        width = int(STROKE * 0.22) if i % 3 == 0 else int(STROKE * 0.14)
        x1 = CX + math.cos(angle) * inner
        y1 = CY + math.sin(angle) * inner
        x2 = CX + math.cos(angle) * outer
        y2 = CY + math.sin(angle) * outer
        draw.line([(x1, y1), (x2, y2)], fill=(255, 255, 255, 210), width=max(width, SCALE))
    width = int(STROKE * 0.95)
    p1 = (CX - OUTER * 0.32, CY + OUTER * 0.04)
    p2 = (CX - OUTER * 0.05, CY + OUTER * 0.28)
    p3 = (CX + OUTER * 0.38, CY - OUTER * 0.26)
    white = (255, 255, 255, 255)
    draw.line([p1, p2], fill=white, width=width)
    draw.line([p2, p3], fill=white, width=width)
    cap = width / 2
    for x, y in (p1, p2, p3):
        draw.ellipse((x - cap, y - cap, x + cap, y + cap), fill=white)
    return layer


def main():
    img = plate()
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    disc(sd, OUTER, (20, 24, 40, 50))
    shifted = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shifted.paste(shadow, (0, int(OUTER * 0.06)))
    img = Image.alpha_composite(img, shifted.filter(ImageFilter.GaussianBlur(int(OUTER * 0.08))))
    img = Image.alpha_composite(img, badge())
    img.putalpha(ImageChops.multiply(img.split()[-1], body_mask()))
    dest = Path(__file__).resolve().parents[1] / "Resources" / "AppIcon.png"
    img.resize((SIZE, SIZE), Image.Resampling.LANCZOS).save(dest, "PNG")
    print(dest)


if __name__ == "__main__":
    main()
