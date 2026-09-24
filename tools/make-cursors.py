#!/usr/bin/env python3
"""Build the Monogray cursor theme (original artwork, MIT).

Pale body so it stands out on the dark glass UI, a thin dark outline so it
stays visible on white pages, and a soft blue glow; the crosshair
dot, spinner and help badge carry the accent.

    python3 tools/make-cursors.py [out-dir]     (default: cursor/theme)

Writes both formats into one icon theme directory:
  cursors/      Xcursor files (GTK, XWayland, anything X11-ish)
  aliases.txt   "alias target" pairs, linked into cursors/ at install time
  hyprcursors/  hyprcursor .hlc files (Hyprland itself), from the same SVGs

Needs: rsvg-convert, magick, hyprcursor-util. No Python packages.
"""
import math
import shutil
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

NAME = "Monogray-Cursor"
FILL, OUTLINE, ACCENT, RED = "#eef1f8", "#16161c", "#6a97ff", "#da4453"
GLOW = "#6a97ff"
XSIZES = [24, 32, 48, 64, 96]
FRAMES, FRAME_MS = 12, 55

# ---------------------------------------------------------------- drawing
# Every cursor is drawn on a 256x256 canvas. Shapes are listed once and
# painted three times: a blurred accent glow, a thick dark stroke (the
# outline), then the pale fill on top. Stroking the whole group before
# filling makes overlapping parts read as one clean silhouette.

OUT_W = 22  # outline stroke width; half of it shows outside the fill


def svg(shapes, extra="", glow=True):
    glow_layer = (
        f'<g filter="url(#g)" fill="{GLOW}" stroke="{GLOW}" stroke-width="{OUT_W}" '
        f'stroke-linejoin="round" opacity="0.55">{shapes}</g>' if glow else ""
    )
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">
<defs><filter id="g" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="9"/></filter></defs>
{glow_layer}
<g fill="{OUTLINE}" stroke="{OUTLINE}" stroke-width="{OUT_W}" stroke-linejoin="round" stroke-linecap="round">{shapes}</g>
<g fill="{FILL}">{shapes}</g>
{extra}
</svg>"""


# Pointer: a tailless dart with a notched back, symmetric about the line from
# the tip (48,32) to the notch (112,146). The half below that line is a shade
# deeper and the fold carries a thin accent line, so it reads as a folded
# paper dart rather than the classic tailed arrow.
ARROW = '<path d="M48 32 L178 150 L112 146 L81 205 Z"/>'
SHADE = "#c3cad9"


def dart_facets():
    return (f'<path d="M48 32 L112 146 L81 205 Z" fill="{SHADE}"/>'
            f'<path d="M52 40 L110 142" stroke="{ACCENT}" stroke-width="6" stroke-linecap="round"/>')


def arrow():
    return svg(ARROW, dart_facets())


def hand(folded=False):
    if folded:  # closed hand for "grabbing"
        fingers = ('<circle cx="104" cy="118" r="20"/><circle cx="138" cy="110" r="20"/>'
                   '<circle cx="171" cy="113" r="19"/><circle cx="199" cy="124" r="16"/>')
        thumb = '<rect x="50" y="128" width="32" height="64" rx="16" transform="rotate(-38 66 160)"/>'
        palm = '<rect x="78" y="116" width="136" height="100" rx="38"/>'
        seams = ""
    else:
        fingers = ('<rect x="96" y="30" width="36" height="128" rx="18"/>'
                   '<rect x="132" y="96" width="32" height="76" rx="16"/>'
                   '<rect x="162" y="104" width="30" height="70" rx="15"/>'
                   '<rect x="190" y="118" width="26" height="58" rx="13"/>')
        thumb = '<rect x="50" y="124" width="32" height="76" rx="16" transform="rotate(-38 66 162)"/>'
        palm = '<rect x="76" y="140" width="140" height="84" rx="38"/>'
        seams = (f'<g stroke="{OUTLINE}" stroke-width="7" stroke-linecap="round">'
                 '<path d="M133 110 V150"/><path d="M163 116 V152"/><path d="M191 128 V156"/></g>')
    return svg(fingers + thumb + palm, seams)


def ibeam():
    shapes = ('<rect x="120" y="60" width="16" height="136" rx="6"/>'
              '<rect x="96" y="52" width="64" height="16" rx="8"/>'
              '<rect x="96" y="188" width="64" height="16" rx="8"/>')
    return svg(shapes)


def crosshair():
    shapes = ('<rect x="36" y="121" width="68" height="14" rx="7"/>'
              '<rect x="152" y="121" width="68" height="14" rx="7"/>'
              '<rect x="121" y="36" width="14" height="68" rx="7"/>'
              '<rect x="121" y="152" width="14" height="68" rx="7"/>')
    dot = f'<circle cx="128" cy="128" r="12" fill="{ACCENT}" stroke="{OUTLINE}" stroke-width="6"/>'
    return svg(shapes, dot)


def spinner(cx, cy, r, w, frame):
    """Pale ring with an accent arc; frame 0..FRAMES-1 rotates the arc."""
    ang = 360 * frame / FRAMES
    a0, a1 = math.radians(ang - 90), math.radians(ang + 20)
    x0, y0 = cx + r * math.cos(a0), cy + r * math.sin(a0)
    x1, y1 = cx + r * math.cos(a1), cy + r * math.sin(a1)
    return (f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="none" stroke="{OUTLINE}" stroke-width="{w + 12}"/>'
            f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="none" stroke="{FILL}" stroke-width="{w}"/>'
            f'<path d="M{x0:.1f} {y0:.1f} A{r} {r} 0 0 1 {x1:.1f} {y1:.1f}" fill="none" '
            f'stroke="{ACCENT}" stroke-width="{w}" stroke-linecap="round"/>')


def wait(frame):
    ring = spinner(128, 128, 58, 22, frame)
    halo = (f'<circle cx="128" cy="128" r="58" fill="none" stroke="{GLOW}" stroke-width="34" '
            f'filter="url(#g)" opacity="0.45"/>')
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">
<defs><filter id="g" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="9"/></filter></defs>
{halo}{ring}</svg>"""


def progress(frame):
    return svg(ARROW, dart_facets() + spinner(192, 196, 30, 14, frame))


def forbidden():
    ring = ('<circle cx="128" cy="128" r="66" fill="none" stroke="{c}" stroke-width="{w}"/>'
            '<path d="M82 82 L174 174" stroke="{c}" stroke-width="{w}" stroke-linecap="round"/>')
    glow = (f'<g filter="url(#g)" opacity="0.5">' + ring.format(c=GLOW, w=34) + '</g>')
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">
<defs><filter id="g" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="9"/></filter></defs>
{glow}{ring.format(c=OUTLINE, w=34)}{ring.format(c=RED, w=20)}</svg>"""


def help_():
    badge = (f'<circle cx="190" cy="192" r="32" fill="{ACCENT}" stroke="{OUTLINE}" stroke-width="8"/>'
             f'<path d="M178 184 a12 12 0 1 1 17 11 q-5 3 -5 10" fill="none" stroke="{FILL}" '
             f'stroke-width="8" stroke-linecap="round"/>'
             f'<circle cx="190" cy="215" r="5" fill="{FILL}"/>')
    return svg(ARROW, dart_facets() + badge)


def double_arrow(rotate):
    shapes = ('<rect x="121" y="70" width="14" height="116" rx="7"/>'
              '<path d="M128 34 L90 82 L166 82 Z"/>'
              '<path d="M128 222 L90 174 L166 174 Z"/>')
    return svg(f'<g transform="rotate({rotate} 128 128)">{shapes}</g>')


def move():
    head = '<path d="M128 30 L96 70 L160 70 Z"/>'
    heads = "".join(f'<g transform="rotate({a} 128 128)">{head}</g>' for a in (0, 90, 180, 270))
    bars = ('<rect x="121" y="64" width="14" height="128" rx="7"/>'
            '<rect x="64" y="121" width="128" height="14" rx="7"/>')
    return svg(bars + heads)


# ---------------------------------------------------------- cursor table
# name: (drawer, hotspot on the 256 canvas, aliases). Aliases cover CSS names,
# the X11 core font names, and the hash names Qt and Chromium look up.
CURSORS = {
    "default": (arrow, (48, 32), [
        "left_ptr", "arrow", "top_left_arrow", "context-menu", "copy", "alias", "cell",
        "dnd-copy", "dnd-link", "dnd-move", "dnd-ask", "zoom-in", "zoom-out", "center_ptr",
        "right_ptr", "draft", "link", "1081e37283d90000800003c07f3ef6bf",
        "6407b0e94181790501fd1e167b474872", "3085a0e285430894940527032f8b26df",
        "640fb0e74195791501fd1ed57b41487f", "b66166c04f8c3109214a4fbd64a50fc8"]),
    "pointer": (hand, (114, 32), [
        "hand1", "hand2", "pointing_hand", "grab", "openhand", "hand",
        "e29285e634086352946a0e7090d73106", "9d800788f1b08800ae810202380a0822",
        "5aca4d189052212118709018842178c0"]),
    "grabbing": (lambda: hand(folded=True), (140, 150), [
        "closedhand", "dnd-none", "208530c400c041818281048008011002",
        "fcf21c00b30f7e3f83fe0dfd12e71cff"]),
    "text": (ibeam, (128, 128), ["xterm", "ibeam", "vertical-text", "048008013003cff3c00c801001200000"]),
    "crosshair": (crosshair, (128, 128), ["cross", "tcross", "diamond_cross", "cross_reverse", "plus"]),
    "not-allowed": (forbidden, (128, 128), [
        "forbidden", "crossed_circle", "no-drop", "circle", "dnd-no-drop",
        "03b6e0fcb3499374a867c041f52298f0"]),
    "help": (help_, (48, 32), [
        "question_arrow", "whats_this", "left_ptr_help",
        "5c6cd98b3f3ebcb1f9c7f1c204630408", "d9ce0ab605698f320427677b458ad60b"]),
    "move": (move, (128, 128), [
        "all-scroll", "fleur", "size_all", "pointer-move",
        "4498f0e0c1937ffe01fd06f973665830", "9081237383d90e509aa00f00170e968f"]),
    "ns-resize": (lambda: double_arrow(0), (128, 128), [
        "n-resize", "s-resize", "row-resize", "size_ver", "sb_v_double_arrow", "v_double_arrow",
        "top_side", "bottom_side", "double_arrow", "split_v", "00008160000006810000408080010102",
        "2870a09082c103050810ffdffffe0204"]),
    "ew-resize": (lambda: double_arrow(90), (128, 128), [
        "e-resize", "w-resize", "col-resize", "size_hor", "sb_h_double_arrow", "h_double_arrow",
        "left_side", "right_side", "split_h", "028006030e0e7ebffc7f7070c0600140",
        "14fef782d02440884392942c11205230"]),
    "nwse-resize": (lambda: double_arrow(-45), (128, 128), [
        "nw-resize", "se-resize", "size_fdiag", "bd_double_arrow", "top_left_corner",
        "bottom_right_corner", "c7088f0f3e6c8088236ef8e1e3e70000"]),
    "nesw-resize": (lambda: double_arrow(45), (128, 128), [
        "ne-resize", "sw-resize", "size_bdiag", "fd_double_arrow", "top_right_corner",
        "bottom_left_corner", "fcf1c3c7cd4491d801f1e1c78f100000"]),
}
ANIMATED = {
    "wait": (wait, (128, 128), ["watch"]),
    "progress": (progress, (48, 32), [
        "left_ptr_watch", "half-busy", "08e8e1c95fe2fc01f976f1e063a24ccd",
        "3ecb610c1bf2410f44200f48c40d3599", "00000000000000020006000e7e9ffc3f"]),
}


# ------------------------------------------------------------ rendering
def render_png(svg_path, size, out):
    subprocess.run(["rsvg-convert", "-w", str(size), "-h", str(size), "-o", str(out), str(svg_path)], check=True)


def argb_pixels(png, size):
    raw = subprocess.run(["magick", str(png), "-depth", "8", "RGBA:-"], check=True, capture_output=True).stdout
    out = bytearray()
    for i in range(0, size * size * 4, 4):
        r, g, b, a = raw[i:i + 4]
        # Xcursor pixels are premultiplied ARGB, little-endian
        out += struct.pack("<I", (a << 24) | ((r * a // 255) << 16) | ((g * a // 255) << 8) | (b * a // 255))
    return bytes(out)


def write_xcursor(path, images):
    """images: list of (nominal, size, xhot, yhot, delay_ms, argb_bytes)."""
    ntoc = len(images)
    header = struct.pack("<4sIII", b"Xcur", 16, 0x10000, ntoc)
    pos = 16 + ntoc * 12
    toc, chunks = b"", b""
    for nominal, size, xh, yh, delay, px in images:
        toc += struct.pack("<III", 0xFFFD0002, nominal, pos)
        chunk = struct.pack("<IIIIIIIII", 36, 0xFFFD0002, nominal, 1, size, size, xh, yh, delay) + px
        chunks += chunk
        pos += len(chunk)
    path.write_bytes(header + toc + chunks)


def main():
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "cursor/theme").resolve()
    work = Path(tempfile.mkdtemp())
    src = work / "src"
    xdir = work / "cursors"
    hsrc = work / "hypr"
    for d in (src, xdir, hsrc / "hyprcursors"):
        d.mkdir(parents=True)

    (hsrc / "manifest.hl").write_text(
        f"name = {NAME}\ndescription = Monogray cursors for Omarchy\nversion = 1.0\ncursors_directory = hyprcursors\n")

    def build(name, frames_svgs, hot, aliases):
        hx, hy = hot
        hdir = hsrc / "hyprcursors" / name
        hdir.mkdir()
        meta = [f"resize_algorithm = bilinear", f"hotspot_x = {hx / 256:.3f}", f"hotspot_y = {hy / 256:.3f}", ""]
        meta += [f"define_override = {a}" for a in aliases]
        meta.append("")
        images = []
        for i, text in enumerate(frames_svgs):
            svgname = f"{name}-{i:02d}.svg" if len(frames_svgs) > 1 else f"{name}.svg"
            (hdir / svgname).write_text(text)
            (src / svgname).write_text(text)
            delay = FRAME_MS if len(frames_svgs) > 1 else 0
            meta.append(f"define_size = 0, {svgname}" + (f", {delay}" if delay else ""))
            for s in XSIZES:
                png = work / f"{svgname}.{s}.png"
                render_png(src / svgname, s, png)
                images.append((s, s, round(hx * s / 256), round(hy * s / 256), delay, argb_pixels(png, s)))
        (hdir / "meta.hl").write_text("\n".join(meta) + "\n")
        # Xcursor expects images grouped by size, frames in order within each size
        images.sort(key=lambda im: im[0])
        write_xcursor(xdir / name, images)
        # Omarchy plugins may not contain symlinks, so aliases are listed in
        # aliases.txt and linked by apply.sh when the theme is installed.
        alias_lines.extend(f"{a} {name}" for a in aliases)
        print(f"  {name:12s} {len(frames_svgs):2d} frame(s), {len(aliases)} aliases")

    alias_lines = []
    print(f"Building {NAME}")
    for name, (draw, hot, aliases) in CURSORS.items():
        build(name, [draw()], hot, aliases)
    for name, (draw, hot, aliases) in ANIMATED.items():
        build(name, [draw(f) for f in range(FRAMES)], hot, aliases)

    hout = work / "hout"
    hout.mkdir()  # hyprcursor-util aborts if the output dir is missing
    subprocess.run(["hyprcursor-util", "--create", str(hsrc), "--output", str(hout)], check=True,
                   stdout=subprocess.DEVNULL)
    built = next(hout.iterdir())

    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    shutil.copytree(xdir, out / "cursors")
    (out / "aliases.txt").write_text("\n".join(alias_lines) + "\n")
    shutil.copytree(built / "hyprcursors", out / "hyprcursors")
    shutil.copy(built / "manifest.hl", out / "manifest.hl")
    (out / "index.theme").write_text(
        f"[Icon Theme]\nName={NAME}\nComment=Monogray cursors for Omarchy\nInherits=Adwaita\n")
    # The SVG sources ship next to the built theme so the art is editable.
    shutil.rmtree(out.parent / "svg", ignore_errors=True)
    shutil.copytree(src, out.parent / "svg")
    shutil.rmtree(work)
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
