#!/usr/bin/env python3
"""Generate the non-city Monogray wallpapers (grayscale, original art).

    python3 tools/make-landscape.py mountains out.png [--seed N] [--size WxH]
    python3 tools/make-landscape.py planet    out.png [--seed N] [--size WxH]

  mountains  layered misty ridges under a low moon, fog pooling in the valleys
  planet     a ringed gas giant rising over a flat dark horizon (a nod to the
             planet wallpaper in juxtopposed/Mystical-Blue-Theme)

Needs numpy and pillow. Tint afterwards with tools/tint.sh if wanted, then run
tools/progressive-blur.sh for the bar strip.
"""
import argparse

import numpy as np
from PIL import Image, ImageFilter

ap = argparse.ArgumentParser()
ap.add_argument("scene", choices=["mountains", "planet"])
ap.add_argument("out")
ap.add_argument("--seed", type=int, default=3)
ap.add_argument("--size", default="2560x1440")
args = ap.parse_args()

W, H = (int(v) for v in args.size.split("x"))
rng = np.random.default_rng(args.seed)
yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
v = yy / H  # 0 top .. 1 bottom
u = xx / W


def gblur(a, r):
    img = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))
    return np.asarray(img.filter(ImageFilter.GaussianBlur(r)), np.float32) / 255.0


def fbm1d(n, octaves=7, rough=0.52):
    """1-D fractal noise in [-1, 1], length n."""
    out = np.zeros(n)
    amp, total = 1.0, 0.0
    for o in range(octaves):
        k = 2 ** (o + 2)
        pts = rng.uniform(-1, 1, k + 1)
        out += np.interp(np.linspace(0, k, n), np.arange(k + 1), pts) * amp
        total += amp
        amp *= rough
    return out / total


def stars(density, fade_to):
    s = np.zeros((H, W), np.float32)
    n = int(W * H * density)
    x, y = rng.integers(0, W, n), (rng.random(n) ** 1.6 * H * fade_to).astype(int)
    s[y, x] = rng.uniform(0.3, 1.0, n)
    return gblur(s, 0.7) * 1.8


def moon(cx, cy, r, glow=0.12):
    d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / r
    halo = np.exp(-np.maximum(d - 1, 0) * 0.4) * glow + np.exp(-np.maximum(d - 1, 0) * 2.5) * 0.1
    disc = np.clip((1 - d) * 5, 0, 1)
    tex = gblur(rng.random((H, W)).astype(np.float32), 5)
    return halo, disc * (0.72 + (tex - 0.5) * 0.4)


if args.scene == "mountains":
    img = 0.03 + 0.22 * v ** 1.6  # night sky brightening toward the haze
    img += stars(1 / 7000, 0.55) * (1 - v) ** 2
    halo, disc = moon(W * 0.30, H * 0.26, H * 0.04)
    img = np.maximum(img + halo, disc)

    ridges = 6
    for i in range(ridges):
        t = i / (ridges - 1)  # 0 far .. 1 near
        base = H * (0.50 + 0.40 * t)
        amp = H * (0.16 + 0.08 * t)
        f = fbm1d(W, rough=0.5 + 0.08 * t)
        f = (f - f.min()) / (f.max() - f.min())  # use the full range so peaks stand out
        line = base - f ** 1.3 * amp * 1.5
        mask = (yy >= line[None, :]).astype(np.float32)
        mask = gblur(mask, 2.5 - 2.2 * t)
        tone = 0.21 * (1 - t) ** 1.3 + 0.02
        # moonlit face: slope toward the moon catches a little light
        slope = np.gradient(line)
        lit = np.clip(-slope * 0.02, 0, 0.06)[None, :] * np.exp(-(yy - line[None, :]) / (H * 0.02))
        layer = tone + lit * (1 - t)
        img = img * (1 - mask) + layer * mask
        # fog pooling in the valley in front of this ridge
        fog = np.exp(-((yy - base - H * 0.02) / (H * 0.05)) ** 2) * 0.22 * (1 - t * 0.6)
        img += fog * (1 - img)

else:  # planet
    img = 0.02 + 0.10 * v ** 2
    img += stars(1 / 5000, 0.9)
    # gas giant, centered, rising behind the horizon
    cx, cy, r = W * 0.5, H * 0.60, H * 0.40
    tilt = -0.18  # ring and band tilt, radians
    dx, dy = (xx - cx) / r, (yy - cy) / r
    by = dy * np.cos(tilt) + dx * np.sin(tilt)  # band axis follows the ring plane
    d = np.sqrt(dx ** 2 + dy ** 2)
    inside = d < 1
    # banded atmosphere, warped with noise so bands swirl
    warp = gblur(rng.random((H, W)).astype(np.float32), 18) - 0.5
    bands = np.sin((by + warp * 0.35) * 22 + np.sin(by * 7) * 1.5) * 0.5 + 0.5
    fine = np.sin((by + warp * 0.15) * 90) * 0.5 + 0.5
    zz = np.sqrt(np.clip(1 - d ** 2, 0, 1))
    shade = np.clip(0.25 + 0.75 * (zz * 0.6 + (-dx * 0.55 - dy * 0.35)), 0, 1)  # lit from upper left
    surface = (0.30 + bands * 0.22 + fine * 0.08) * shade
    edge = np.clip((1 - d) * r / 3, 0, 1)
    img = img * (1 - edge * inside) + surface * edge * inside
    atmo = np.exp(-np.abs(d - 1) * 40) * 0.35 * np.clip(-dx * 0.8 - dy + 0.4, 0, 1)
    img += atmo
    # thin rings, tilted; the near half passes in front of the planet
    rx = dx * np.cos(tilt) - dy * np.sin(tilt)
    ry = (dy * np.cos(tilt) + dx * np.sin(tilt)) / 0.22
    rd = np.sqrt(rx ** 2 + ry ** 2)
    ring = ((rd > 1.35) & (rd < 1.9)).astype(np.float32)
    ring *= 0.55 + 0.45 * np.sin(rd * 70) ** 2
    ring = gblur(ring, 1.2) * 0.42
    # the planet's shadow falls across the far side of the rings
    ring *= np.where((ry < 0) & (np.abs(rx) < 1), 0.35, 1.0)
    front = (ry > 0) | ~inside
    img = np.where(front, img + ring * (1 - img), img)
    # flat dark horizon with a faint glow line
    hz = H * 0.88
    ground = (yy >= hz).astype(np.float32)
    img = img * (1 - ground) + (0.025 + 0.05 * np.exp(-(yy - hz) / (H * 0.02))) * ground
    img += np.exp(-np.abs(yy - hz) / (H * 0.006)) * 0.10

# vignette + grain
vig = 1 - 0.32 * (((u - 0.5) * 2) ** 2 * 0.6 + ((v - 0.48) * 2) ** 2 * 0.4)
img = np.clip(img * np.clip(vig, 0.55, 1), 0, 1) * 255
img = np.clip(img + rng.normal(0, 3.0, img.shape), 0, 255).astype(np.uint8)
Image.fromarray(img).convert("RGB").save(args.out)
print(f"wrote {args.out} ({args.scene}, {W}x{H}, seed {args.seed})")
