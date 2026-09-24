#!/usr/bin/env python3
"""Generate the Monogray default wallpaper: an original grayscale night
cityscape (layered skylines in haze, lit windows, moon, wet-street reflection).

    python3 tools/make-cityscape.py [out.png] [--seed N] [--size 2560x1440]
                                    [--fog 1.0] [--no-moon] [--no-stars]

Needs numpy and pillow. Deterministic for a given seed. Run the result through
tools/progressive-blur.sh to add the blurred strip the transparent bar sits on.
"""
import argparse

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ap = argparse.ArgumentParser()
ap.add_argument("out", nargs="?", default="cityscape.png")
ap.add_argument("--seed", type=int, default=7)
ap.add_argument("--size", default="2560x1440")
ap.add_argument("--fog", type=float, default=1.0, help="haze strength multiplier")
ap.add_argument("--no-moon", action="store_true")
ap.add_argument("--no-stars", action="store_true")
args = ap.parse_args()

W, H = (int(v) for v in args.size.split("x"))
SS = 2  # supersample for clean edges on antennas and window grids
w, h = W * SS, H * SS
rng = np.random.default_rng(args.seed)
horizon = int(h * 0.70)  # where the street/water starts


def blur(img, r):
    return img.filter(ImageFilter.GaussianBlur(r * SS))


def to_arr(img):
    return np.asarray(img, dtype=np.float32) / 255.0


# ---------------------------------------------------------------- sky
y = np.linspace(0, 1, horizon)[:, None]
sky = 0.03 + 0.20 * (y ** 2.4) + 0.16 * np.exp((y - 1) * 9)  # near-black top, city glow at the horizon
sky = np.repeat(sky, w, axis=1)

# soft cloud bands: low-frequency noise stretched horizontally
cloud = Image.fromarray((rng.random((horizon // 64 + 2, w // 256 + 2)) * 255).astype(np.uint8))
cloud = cloud.resize((w, horizon), Image.BICUBIC)
cloud = to_arr(blur(cloud, 30))
band = np.clip((cloud - 0.5) * 2.2, 0, 1) * (0.25 + 0.75 * y) * 0.09
sky += band

# stars, fading out toward the horizon glow
n = 0 if args.no_stars else int(w * horizon / 9000)
sx, sy = rng.integers(0, w, n), (rng.random(n) ** 1.8 * horizon * 0.6).astype(int)
star = Image.new("L", (w, horizon), 0)
d = ImageDraw.Draw(star)
for x, yy, b in zip(sx, sy, rng.random(n)):
    r = SS * (1.4 if b > 0.97 else 0.8)
    d.ellipse([x - r, yy - r, x + r, yy + r], fill=int(90 + 165 * b))
sky += to_arr(blur(star, 0.5)) * 0.55

# moon with halo, upper right third
mx, my, mr = int(w * 0.76), int(h * 0.17), int(h * 0.032)
yy, xx = np.mgrid[0:horizon, 0:w]
dist = np.sqrt((xx - mx) ** 2 + (yy - my) ** 2) / mr
moon_on = 0.0 if args.no_moon else 1.0
sky += (np.exp(-np.maximum(dist - 1, 0) * 0.35) * 0.09 + np.exp(-np.maximum(dist - 1, 0) * 2.2) * 0.10) * moon_on
disc = np.clip((1.0 - dist) * 6, 0, 1)
crater = to_arr(blur(Image.fromarray((rng.random((horizon, w)) * 255).astype(np.uint8)), 6))
sky = np.maximum(sky, disc * (0.74 + (crater - 0.5) * 0.35) * moon_on)
del yy, xx, dist, crater

canvas = np.zeros((h, w), np.float32)
canvas[:horizon] = sky


# ------------------------------------------------------------ skylines
def skyline(base_tone, min_h, max_h, min_w, max_w, window_p, window_tone, haze, detail):
    """One depth layer: returns (tone image, alpha mask) as float arrays."""
    tone = Image.new("L", (w, horizon), 0)
    mask = Image.new("L", (w, horizon), 0)
    dt, dm = ImageDraw.Draw(tone), ImageDraw.Draw(mask)
    x = -int(rng.integers(0, max_w))
    while x < w:
        bw = int(rng.integers(min_w, max_w))
        bh = int(rng.uniform(min_h, max_h) * (0.55 + 0.45 * np.sin(x / w * np.pi * 1.3 + 0.4) ** 2))
        top = horizon - bh
        shade = int(np.clip(base_tone + rng.normal(0, 6), 0, 255))
        rects = [(x, top, x + bw, horizon)]
        kind = rng.random()
        if detail and kind < 0.25:  # stepped setback tower
            inset = bw // 5
            rects.append((x + inset, top - bh // 7, x + bw - inset, top))
            rects.append((x + 2 * inset, top - bh // 7 - bh // 10, x + bw - 2 * inset, top))
        elif detail and kind < 0.40:  # spire / antenna
            cx = x + bw // 2
            rects.append((cx - 2 * SS, top - bh // 4, cx + 2 * SS, top))
            dm.ellipse([cx - 4 * SS, top - bh // 4 - 4 * SS, cx + 4 * SS, top - bh // 4 + 4 * SS], fill=255)
            dt.ellipse([cx - 4 * SS, top - bh // 4 - 4 * SS, cx + 4 * SS, top - bh // 4 + 4 * SS], fill=235)
        elif detail and kind < 0.50:  # slanted roof
            dm.polygon([(x, top), (x + bw, top), (x + bw, top - bw // 3)], fill=255)
            dt.polygon([(x, top), (x + bw, top), (x + bw, top - bw // 3)], fill=shade)
        for r in rects:
            dm.rectangle(r, fill=255)
            dt.rectangle(r, fill=shade)
            # moonlight catches the right-hand edge (the moon sits right of center)
            if detail:
                dt.rectangle([r[2] - SS * 2, r[1], r[2], r[3]], fill=min(255, shade + 22))
        # lit windows on a grid
        if window_p > 0:
            ww = max(SS * 2, bw // 26)
            wh = max(SS * 2, int(ww * 1.5))
            gx, gy = int(ww * 2.3), int(wh * 1.8)
            lit = window_p * rng.uniform(0.25, 1.8)  # some towers mostly dark, some busy
            for wy in range(top + gy, horizon - gy, gy):
                if rng.random() < 0.12:
                    continue  # dark floor
                for wx in range(x + gx // 2, x + bw - ww, gx):
                    if rng.random() < lit:
                        b = int(np.clip(window_tone * rng.uniform(0.55, 1.0), 0, 255))
                        dt.rectangle([wx, wy, wx + ww, wy + wh], fill=b)
        x += bw + int(rng.integers(0, max(1, min_w // 3)))
    t, m = to_arr(tone), to_arr(mask)
    if haze:
        t, m = to_arr(blur(Image.fromarray((t * 255).astype(np.uint8)), haze)), to_arr(blur(Image.fromarray((m * 255).astype(np.uint8)), haze))
    return t, m


layers = [
    # tone, min_h, max_h, min_w, max_w, window_p, window_tone, haze, detail
    (92, 0.16, 0.30, 30, 90, 0.10, 125, 3.0, False),
    (66, 0.20, 0.44, 45, 130, 0.14, 160, 1.6, True),
    (40, 0.22, 0.56, 60, 170, 0.18, 200, 0.6, True),
    (16, 0.08, 0.28, 90, 220, 0.22, 230, 0.0, True),
]
fog_y = np.linspace(0, 1, horizon)[:, None]
for i, (tone, a, b, mnw, mxw, wp, wt, haze, det) in enumerate(layers):
    t, m = skyline(tone, a * h, b * h, mnw * SS, mxw * SS, wp, wt, haze, det)
    region = canvas[:horizon]
    region[:] = region * (1 - m) + t * m
    # ground fog rising in front of this layer, strongest at the base
    fog = np.clip((fog_y - 0.55) / 0.45, 0, 1) ** 1.8 * (0.30 - i * 0.07) * args.fog
    region[:] = region + fog * (1 - region)

# ------------------------------------------------ wet street reflection
refl_h = h - horizon
src = canvas[horizon - refl_h:horizon][::-1].copy()
# horizontal ripples: shift each row by a small sine offset
rows = np.arange(refl_h)
shift = (np.sin(rows / (3.0 * SS)) * (0.5 + rows / refl_h * 3) * SS).astype(int)
for r in range(refl_h):
    src[r] = np.roll(src[r], shift[r])
# wet asphalt smears lights vertically: squash, blur, stretch back
refl = Image.fromarray((np.clip(src, 0, 1) * 255).astype(np.uint8))
refl = blur(refl.resize((w, max(1, refl_h // 24)), Image.BILINEAR).resize((w, refl_h), Image.BICUBIC), 3)
refl = to_arr(refl)
fade = np.linspace(0.62, 0.10, refl_h)[:, None]
canvas[horizon:] = 0.03 + refl * fade
# a thin bright edge where street meets skyline
canvas[horizon:horizon + SS * 2] = np.maximum(canvas[horizon:horizon + SS * 2], 0.22)

# ------------------------------------------------------ vignette + grain
yy, xx = np.mgrid[0:h, 0:w]
vig = 1 - 0.35 * (((xx - w / 2) / (w / 2)) ** 2 * 0.6 + ((yy - h * 0.45) / (h / 2)) ** 2 * 0.4)
canvas *= np.clip(vig, 0.55, 1)
del yy, xx, vig

img = Image.fromarray((np.clip(canvas, 0, 1) * 255).astype(np.uint8)).resize((W, H), Image.LANCZOS)
grain = rng.normal(0, 3.2, (H, W))
out = np.clip(np.asarray(img, np.float32) + grain, 0, 255).astype(np.uint8)
Image.fromarray(out).convert("RGB").save(args.out)
print(f"wrote {args.out} ({W}x{H}, seed {args.seed})")
