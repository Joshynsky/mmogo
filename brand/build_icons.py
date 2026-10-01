"""Rebuild the mmogo launcher icons from the SVG sources in this folder.

Needs Python with Pillow and Google Chrome (headless) on Windows.
Run from the app root:  python brand/build_icons.py
Writes: android/app/src/main/res/mipmap-*/ic_launcher*.png and brand/export/*.png
Colours (PM decision 2026-10-01): tile Ocean #0A6E8A, pocket white, coin Sun #FFB703.
"""
import os, subprocess, tempfile
from pathlib import Path
from PIL import Image, ImageDraw

CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"
ROOT = Path(__file__).resolve().parent.parent
BRAND = ROOT / "brand"
RES = ROOT / "android/app/src/main/res"
BG = (0x0A, 0x6E, 0x8A, 255)
tmp = Path(tempfile.mkdtemp())

def render(name):
    html = tmp / f"{name}.html"
    png = tmp / f"{name}.png"
    src = (BRAND / f"{name}.svg").as_uri()
    html.write_text(f'<!doctype html><body style="margin:0;background:transparent"><img src="{src}" style="display:block;width:1024px;height:1024px">')
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                    "--default-background-color=00000000", "--window-size=1100,1200",
                    f"--screenshot={png}", html.as_uri()], check=True, capture_output=True)
    return Image.open(png).convert("RGBA").crop((0, 0, 1024, 1024))

fg_m, fg_ring, mono_m = render("foreground-m"), render("foreground-ring"), render("monochrome-m")

def shape_mask(size, shape):
    s = size * 4
    m = Image.new("L", (s, s), 0)
    d = ImageDraw.Draw(m)
    if shape == "circle":
        d.ellipse((0, 0, s - 1, s - 1), fill=255)
    else:
        d.rounded_rectangle((0, 0, s - 1, s - 1), radius=int(s * {"squircle": 0.30, "rounded": 0.12}[shape]), fill=255)
    return m.resize((size, size), Image.LANCZOS)

def composite(fg, size, shape, crop=True):
    base = Image.new("RGBA", (1024, 1024), BG)
    base.alpha_composite(fg)
    if crop:  # visible window of an adaptive icon is 72 of 108 dp
        a, b = int(1024 * 18 / 108), int(1024 * 90 / 108)
        base = base.crop((a, a, b, b))
    base = base.resize((size, size), Image.LANCZOS)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(base, (0, 0), shape_mask(size, shape))
    return out

for d, k in {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}.items():
    px = int(108 * k)
    (RES / f"mipmap-{d}").mkdir(parents=True, exist_ok=True)
    fg_m.resize((px, px), Image.LANCZOS).save(RES / f"mipmap-{d}/ic_launcher_foreground.png")
    mono_m.resize((px, px), Image.LANCZOS).save(RES / f"mipmap-{d}/ic_launcher_monochrome.png")
for d, px in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
    composite(fg_m, px, "rounded").save(RES / f"mipmap-{d}/ic_launcher.png")  # API 21-25
(BRAND / "export").mkdir(exist_ok=True)
for nm, fg in (("with-m", fg_m), ("no-m", fg_ring)):
    for shape in ("squircle", "circle"):
        composite(fg, 512, shape).save(BRAND / f"export/mmogo-icon-{nm}-{shape}-512.png")
    composite(fg, 512, "rounded", crop=False).save(BRAND / f"export/mmogo-icon-{nm}-full-512.png")
print("icons rebuilt")
