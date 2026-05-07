#!/usr/bin/env python3
import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


def load_font(path, size, index=0):
    try:
        return ImageFont.truetype(path, size, index=index)
    except Exception:
        return ImageFont.load_default(size=size)


def draw_centered(draw, text, font, y, width):
    bbox = draw.textbbox((0, 0), text, font=font)
    text_width = bbox[2] - bbox[0]
    x = (width - text_width) // 2
    for dx, dy, alpha in [(0, 5, 110), (0, 2, 155), (2, 2, 90)]:
        draw.text((x + dx, y + dy), text, font=font, fill=(0, 0, 0, alpha))
    draw.text((x, y), text, font=font, fill=(255, 255, 255, 242))


def main():
    parser = argparse.ArgumentParser(description="Create a transparent title overlay PNG for BGM videos.")
    parser.add_argument("--output", default="title_overlay.png")
    parser.add_argument("--title", required=True)
    parser.add_argument("--subtitle", default="")
    parser.add_argument("--width", type=int, default=1920)
    parser.add_argument("--height", type=int, default=1080)
    parser.add_argument("--title-size", type=int, default=88)
    parser.add_argument("--subtitle-size", type=int, default=44)
    parser.add_argument("--font", default="/System/Library/Fonts/HelveticaNeue.ttc")
    parser.add_argument("--panel-alpha", type=int, default=46)
    args = parser.parse_args()

    image = Image.new("RGBA", (args.width, args.height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    panel_y = int(args.height * 0.50)
    panel_h = int(args.height * 0.25)
    image.alpha_composite(Image.new("RGBA", (args.width, panel_h), (0, 0, 0, args.panel_alpha)), (0, panel_y))

    title_font = load_font(args.font, args.title_size, index=1)
    subtitle_font = load_font(args.font, args.subtitle_size, index=0)
    draw_centered(draw, args.title, title_font, int(args.height * 0.565), args.width)
    if args.subtitle:
        draw_centered(draw, args.subtitle, subtitle_font, int(args.height * 0.665), args.width)

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    image.save(output)
    print(output)


if __name__ == "__main__":
    main()
