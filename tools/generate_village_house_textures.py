from __future__ import annotations

import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "textures" / "generated"
SIZE = 512
SEED = 4172


def clamp_channel(value: float) -> int:
    return max(0, min(255, int(round(value))))


def vary(color: tuple[int, int, int], spread: int, rng: random.Random) -> tuple[int, int, int]:
    return tuple(clamp_channel(channel + rng.randint(-spread, spread)) for channel in color)


def vertical_gradient(
    image: Image.Image,
    top: tuple[int, int, int],
    bottom: tuple[int, int, int],
) -> None:
    pixels = image.load()
    for y in range(image.height):
        t = y / max(1, image.height - 1)
        row = tuple(int(top[i] * (1.0 - t) + bottom[i] * t) for i in range(3))
        for x in range(image.width):
            pixels[x, y] = row


def paint_plaster(path: Path, rng: random.Random) -> None:
    image = Image.new("RGB", (SIZE, SIZE), (231, 216, 182))
    vertical_gradient(image, (239, 225, 192), (212, 194, 160))
    draw = ImageDraw.Draw(image, "RGBA")

    for _ in range(140):
        x0 = rng.randint(0, SIZE - 80)
        y0 = rng.randint(0, SIZE - 80)
        x1 = x0 + rng.randint(30, 120)
        y1 = y0 + rng.randint(18, 90)
        color = vary((200, 182, 146), 18, rng) + (rng.randint(18, 38),)
        draw.ellipse((x0, y0, x1, y1), fill=color)

    for _ in range(260):
        x = rng.randint(0, SIZE - 1)
        y = rng.randint(0, SIZE - 1)
        radius = rng.randint(1, 4)
        color = vary((245, 234, 210), 10, rng) + (rng.randint(24, 64),)
        draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=color)

    image = image.filter(ImageFilter.GaussianBlur(radius=0.6))
    image.save(path)


def paint_wood(path: Path, rng: random.Random) -> None:
    image = Image.new("RGB", (SIZE, SIZE), (148, 96, 44))
    vertical_gradient(image, (165, 108, 51), (124, 77, 35))
    draw = ImageDraw.Draw(image, "RGBA")
    plank_count = 7
    plank_h = SIZE / plank_count

    for plank in range(plank_count):
        y0 = int(plank * plank_h)
        y1 = int((plank + 1) * plank_h)
        fill = vary((149, 96, 45), 12, rng)
        draw.rectangle((0, y0, SIZE, y1), fill=fill)
        seam = clamp_channel(sum(fill) / 3 - 32)
        draw.line((0, y0, SIZE, y0), fill=(seam, seam - 6, seam - 10, 190), width=3)

        for _ in range(rng.randint(9, 14)):
            y = rng.randint(y0 + 5, max(y0 + 6, y1 - 6))
            start = rng.randint(0, 100)
            end = rng.randint(SIZE - 100, SIZE)
            draw.line((start, y, end, y + rng.randint(-5, 5)), fill=(92, 57, 28, 95), width=rng.randint(1, 3))

        for _ in range(rng.randint(3, 5)):
            x = rng.randint(50, SIZE - 50)
            y = rng.randint(y0 + 12, y1 - 12)
            r = rng.randint(7, 15)
            draw.ellipse((x - r, y - r * 0.7, x + r, y + r * 0.7), outline=(90, 55, 26, 120), width=2)

    image = image.filter(ImageFilter.GaussianBlur(radius=0.45))
    image.save(path)


def paint_roof(path: Path, rng: random.Random) -> None:
    image = Image.new("RGB", (SIZE, SIZE), (47, 101, 152))
    draw = ImageDraw.Draw(image, "RGBA")
    tile_w = 96
    tile_h = 72

    for row in range(math.ceil(SIZE / tile_h) + 1):
        offset = 0 if row % 2 == 0 else tile_w // 2
        y0 = row * tile_h - 8
        for col in range(math.ceil(SIZE / tile_w) + 2):
            x0 = col * tile_w - offset
            x1 = x0 + tile_w - 10
            y1 = y0 + tile_h - 12
            fill = vary((49, 105, 160), 14, rng) + (255,)
            draw.rounded_rectangle((x0, y0, x1, y1), radius=14, fill=fill)
            draw.line((x0 + 8, y0 + 8, x1 - 8, y0 + 6), fill=(89, 143, 193, 110), width=3)
            draw.line((x0 + 12, y1 - 10, x1 - 10, y1 - 8), fill=(23, 56, 94, 140), width=4)

    for _ in range(160):
        x = rng.randint(0, SIZE - 1)
        y = rng.randint(0, SIZE - 1)
        draw.ellipse((x, y, x + 8, y + 8), fill=(255, 255, 255, rng.randint(8, 20)))

    image = image.filter(ImageFilter.GaussianBlur(radius=0.45))
    image.save(path)


def paint_stone(path: Path, rng: random.Random) -> None:
    image = Image.new("RGB", (SIZE, SIZE), (145, 135, 124))
    draw = ImageDraw.Draw(image, "RGBA")
    cell_w = 100
    cell_h = 84

    for row in range(math.ceil(SIZE / cell_h) + 1):
        shift = 0 if row % 2 == 0 else cell_w // 2
        for col in range(math.ceil(SIZE / cell_w) + 2):
            x0 = col * cell_w - shift + rng.randint(-5, 5)
            y0 = row * cell_h + rng.randint(-5, 5)
            x1 = x0 + cell_w - rng.randint(14, 24)
            y1 = y0 + cell_h - rng.randint(14, 24)
            fill = vary((151, 142, 132), 16, rng) + (255,)
            draw.rounded_rectangle((x0, y0, x1, y1), radius=10, fill=fill)
            draw.line((x0 + 10, y0 + 8, x1 - 10, y0 + 12), fill=(196, 190, 184, 90), width=3)
            draw.line((x0 + 12, y1 - 10, x1 - 8, y1 - 12), fill=(89, 82, 78, 130), width=4)

    image = image.filter(ImageFilter.GaussianBlur(radius=0.35))
    image.save(path)


def paint_lantern(path: Path, rng: random.Random) -> None:
    image = Image.new("RGB", (256, 256), (20, 12, 2))
    draw = ImageDraw.Draw(image, "RGBA")
    center = 128
    for radius in range(110, 8, -2):
        t = radius / 110.0
        color = (
            int(255 * (1.0 - 0.08 * t)),
            int(204 * (1.0 - 0.2 * t)),
            int(85 * (1.0 - 0.55 * t)),
            220,
        )
        draw.ellipse((center - radius, center - radius, center + radius, center + radius), fill=color)

    for _ in range(18):
        x = rng.randint(80, 176)
        y = rng.randint(70, 186)
        r = rng.randint(6, 16)
        draw.ellipse((x - r, y - r, x + r, y + r), fill=(255, 240, 160, rng.randint(18, 46)))

    image = image.filter(ImageFilter.GaussianBlur(radius=6.0))
    image.save(path)


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    rng = random.Random(SEED)
    paint_plaster(OUT_DIR / "village_house_plaster_albedo.png", rng)
    paint_wood(OUT_DIR / "village_house_wood_albedo.png", rng)
    paint_roof(OUT_DIR / "village_house_roof_albedo.png", rng)
    paint_stone(OUT_DIR / "village_house_stone_albedo.png", rng)
    paint_lantern(OUT_DIR / "village_house_lantern_emissive.png", rng)
    print(f"Generated textures in {OUT_DIR}")


if __name__ == "__main__":
    main()
