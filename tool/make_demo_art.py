#!/usr/bin/env python3
"""生成 README 截图用的占位插画（不包含任何真实作品）。

输出 `{pid}_p{n}.png`，文件名符合 pixez 的落盘规则，扫描时会被当成
「一个作品的多页」。示意图：行星 + 星点 + 光锥，色相按作品区分。

用法：
    python tool/make_demo_art.py /tmp/demo_art
    adb push /tmp/demo_art/. /sdcard/Pictures/lightcone-demo/
"""

import colorsys
import math
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFilter


def rgb(h, s, v):
    r, g, b = colorsys.hsv_to_rgb(h % 1.0, s, v)
    return (int(r * 255), int(g * 255), int(b * 255))


def gradient(w, h, top, bottom):
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        t = y / max(1, h - 1)
        c = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        for x in range(w):
            px[x, y] = c
    return img


def make(w, h, hue, seed):
    random.seed(seed)
    base_top = rgb(hue, 0.62, 0.10)
    base_bot = rgb(hue + 0.05, 0.55, 0.30)
    img = gradient(w, h, base_top, base_bot).convert("RGBA")

    # 星点
    stars = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    sd = ImageDraw.Draw(stars)
    for _ in range(int(w * h / 9000)):
        x, y = random.randint(0, w), random.randint(0, h)
        r = random.choice([1, 1, 1, 2, 2, 3])
        a = random.randint(40, 190)
        sd.ellipse([x - r, y - r, x + r, y + r], fill=(255, 255, 255, a))
    img = Image.alpha_composite(img, stars)

    # 行星
    pr = int(min(w, h) * random.uniform(0.16, 0.24))
    pcx = int(w * random.uniform(0.35, 0.68))
    pcy = int(h * random.uniform(0.30, 0.52))
    planet_col = rgb(hue + random.uniform(-0.04, 0.04), 0.35, 0.85)
    shadow_col = rgb(hue, 0.55, 0.22)

    # 环（先画，行星会盖住一部分）
    ring = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    rd = ImageDraw.Draw(ring)
    rw, rh = int(pr * 1.9), int(pr * 0.5)
    rd.ellipse([pcx - rw, pcy - rh, pcx + rw, pcy + rh],
               outline=(255, 255, 255, 70), width=max(2, pr // 22))
    rd.ellipse([pcx - int(rw * 0.78), pcy - int(rh * 0.78),
                pcx + int(rw * 0.78), pcy + int(rh * 0.78)],
               outline=(255, 255, 255, 40), width=max(1, pr // 34))
    ring = ring.rotate(random.uniform(-18, 18), center=(pcx, pcy), resample=Image.BICUBIC)
    img = Image.alpha_composite(img, ring)

    planet = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    pd = ImageDraw.Draw(planet)
    for i in range(pr, 0, -2):
        t = i / pr
        col = tuple(int(shadow_col[k] + (planet_col[k] - shadow_col[k]) * (1 - t))
                    for k in range(3))
        pd.ellipse([pcx - i, pcy - i, pcx + i, pcy + i], fill=col + (255,))
    hl = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    hd = ImageDraw.Draw(hl)
    hd.ellipse([pcx - int(pr * 0.55), pcy - int(pr * 0.75),
                pcx + int(pr * 0.15), pcy - int(pr * 0.15)],
               fill=(255, 255, 255, 55))
    hl = hl.filter(ImageFilter.GaussianBlur(pr * 0.18))
    planet = Image.alpha_composite(planet, hl)
    img = Image.alpha_composite(img, planet)

    # 光锥
    cone = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    cd = ImageDraw.Draw(cone)
    ax = int(w * random.uniform(0.2, 0.8))
    ay = int(h * random.uniform(0.10, 0.22))
    half = int(w * 0.18)
    base = int(h * 0.95)
    cd.polygon([(ax, ay), (ax - half, base), (ax + half, base)],
               fill=(235, 244, 255, 26))
    cone = cone.filter(ImageFilter.GaussianBlur(18))
    img = Image.alpha_composite(img, cone)

    # 暗角
    vig = Image.new("L", (w, h), 0)
    vd = ImageDraw.Draw(vig)
    vd.ellipse([-w * 0.25, -h * 0.2, w * 1.25, h * 1.2], fill=180)
    vig = vig.filter(ImageFilter.GaussianBlur(min(w, h) * 0.12))
    dark = Image.new("RGBA", (w, h), (0, 0, 0, 70))
    img = Image.composite(img, Image.alpha_composite(img, dark), vig)

    d = ImageDraw.Draw(img, "RGBA")
    d.text((int(w * 0.05), int(h * 0.95)), "LIGHTCONE", fill=(255, 255, 255, 90))
    return img.convert("RGB")


# (pid, page, width, height, hue)
SPECS = [
    (900001, 0, 1200, 1600, 0.60), (900001, 1, 1200, 1600, 0.62), (900001, 2, 1200, 1600, 0.58),
    (900002, 0, 1200, 1200, 0.50),
    (900003, 0, 1200, 1800, 0.72), (900003, 1, 1200, 1800, 0.74), (900003, 2, 1200, 1800, 0.70),
    (900003, 3, 1200, 1800, 0.76), (900003, 4, 1200, 1800, 0.68),
    (900004, 0, 1400, 1000, 0.45),
    (900005, 0, 1200, 1500, 0.85),
    (900006, 0, 1200, 1350, 0.08),
    (900007, 0, 1000, 1400, 0.30),
    (900008, 0, 1200, 1600, 0.93),
    (900009, 0, 1200, 1100, 0.15),
    (900010, 0, 1200, 1750, 0.55),
    (900011, 0, 1200, 1450, 0.65),
    (900012, 0, 1200, 1250, 0.78),
]


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "demo_art"
    os.makedirs(out, exist_ok=True)
    for i, (pid, page, w, h, hue) in enumerate(SPECS):
        make(w, h, hue, 1000 + i).save(os.path.join(out, f"{pid}_p{page}.png"), optimize=True)
    print(f"generated {len(SPECS)} files into {out}")


if __name__ == "__main__":
    main()
