#!/usr/bin/env python3
"""重建应用图标（AppIcon.icns）。

图形不是凭手画出来的：设计稿末页把图标画成了矢量，本脚本直接从那份 PDF 里
*读取*它的几何——车体、风挡、车灯、腰线、转向架、轨道的路径坐标，以及底板的
实测像素边界——再绘制。设计改稿只要换一份 PDF，坐标随之更新。

为什么用 Pillow 画而不是生成 SVG 再渲染：
**PyMuPDF 的 SVG 渲染器不支持 `linearGradient`**，会把渐变底板渲染成纯黑。
这一点曾经悄悄毁掉过一版图标——脚本跑完不报错，产出的 .icns 却是一个黑底方块，
直到关于面板把它显示出来才被发现。所以这里直接用 Pillow 逐路径绘制，
顺带省掉一层转换；脚本末尾还会自检底板颜色，不对就以非零码退出。

依赖：
    pip install pymupdf pillow
    iconutil（系统自带）

用法：
    python3 script/build_icon.py [设计稿.pdf]
"""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile

import fitz
from PIL import Image, ImageDraw

DEFAULT_PDF = os.path.expanduser("~/Downloads/FairTicketMac GUI 设计稿.pdf")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESOURCES = os.path.join(ROOT, "Resources")

AMBER = (0xFF, 0x7A, 0x17)          # 与 Theme.brand 同值
AMBER_DEEP = (0xFF, 0x4A, 0x00)    # 设计稿的深橙
CORNER_RATIO = 0.225               # 设计稿：圆角 = 边长 × 22.5%
SUPERSAMPLE = 4                    # 先放大再缩小，得到抗锯齿

# ≤128px 用简化版：设计稿要求去掉车灯与转向架，小尺寸下它们只会糊成一团
FULL_FROM = 256


# ---------------------------------------------------------------- 读设计稿

def _vector_geometry(page: fitz.Page) -> dict:
    """从设计稿末页取出图标各元素的路径与底板边界。"""
    paths = page.get_drawings()
    box = fitz.Rect(40, 150, 360, 430)   # 主图标所在的方框

    def one(kind: str, w_range, y_range=None, key=None):
        want = (255, 255, 255) if kind == "white" else (255, 121, 23)
        found = []
        for p in paths:
            if not box.contains(p["rect"]):
                continue
            f = p.get("fill")
            if f is None or tuple(int(c * 255) for c in f) != want:
                continue
            r = p["rect"]
            if not (w_range[0] < r.width < w_range[1]):
                continue
            if y_range and not (y_range[0] < r.y0 < y_range[1]):
                continue
            found.append(p)
        if not found:
            raise RuntimeError(f"设计稿里找不到构件：{kind} 宽度{w_range} 位置{y_range}")
        found.sort(key=key or (lambda p: p["rect"].x0))
        return found

    body = one("white", (130, 200), (150, 260), key=lambda p: -p["rect"].width)[0]
    rail = one("white", (120, 170), (350, 400))[0]
    bogies = one("white", (10, 40), (330, 375))
    windshield = one("orange", (60, 120), (200, 260))[0]
    waist = one("orange", (60, 120), (300, 330))[0]
    lamps = one("orange", (8, 20), (270, 300))

    return {
        "body": body, "windshield": windshield, "lamps": lamps,
        "waist": waist, "bogies": bogies, "rail": rail,
        "plate": _measure_plate(page),
    }


def _measure_plate(page: fitz.Page) -> fitz.Rect:
    """量出底板边界。

    底板是渐变填充，`get_drawings` 拿不到它的 fill，只能按像素找橙色区域。
    不用设计稿文字里的「图形占中央 74%」反推——实测是 52.5%，按文字算会让车体
    几乎撑满整张图，那是本脚本第一版的错。
    """
    clip = fitz.Rect(0, 80, 480, 560)
    pix = page.get_pixmap(clip=clip, dpi=150)
    scale = 150 / 72.0
    data, w, h, nc = pix.samples, pix.width, pix.height, pix.n
    minx, miny, maxx, maxy = w, h, -1, -1
    for y in range(h):
        row = y * w
        for x in range(w):
            i = (row + x) * nc
            if data[i] > 200 and 60 < data[i + 1] < 160 and data[i + 2] < 90:
                minx = min(minx, x); miny = min(miny, y)
                maxx = max(maxx, x); maxy = max(maxy, y)
    if maxx < 0:
        raise RuntimeError("在设计稿里找不到橙色底板")
    return fitz.Rect(
        minx / scale + clip.x0, miny / scale + clip.y0,
        maxx / scale + clip.x0, maxy / scale + clip.y0,
    )


# ---------------------------------------------------------------- 绘制

def _flatten(items, to_px, steps: int = 28) -> list[tuple[float, float]]:
    """把 PDF 的路径项（直线 + 三次贝塞尔）摊成折线点。"""
    pts: list[tuple[float, float]] = []
    cur = None
    for it in items:
        kind = it[0]
        if kind == "l":
            if cur is None:
                cur = it[1]
                pts.append(to_px(cur.x, cur.y))
            pts.append(to_px(it[2].x, it[2].y))
            cur = it[2]
        elif kind == "c":
            if cur is None:
                cur = it[1]
                pts.append(to_px(cur.x, cur.y))
            p1, p2, p3 = it[2], it[3], it[4]
            for i in range(1, steps + 1):
                t = i / steps
                m = 1 - t
                x = m**3 * cur.x + 3 * m * m * t * p1.x + 3 * m * t * t * p2.x + t**3 * p3.x
                y = m**3 * cur.y + 3 * m * m * t * p1.y + 3 * m * t * t * p2.y + t**3 * p3.y
                pts.append(to_px(x, y))
            cur = p3
    return pts


def _gradient(size: int) -> Image.Image:
    """135° 橙色渐变。

    先在 64×64 上算再放大：1024×1024 逐像素是百万次 Python 循环，而放大后
    肉眼无差。
    """
    small = Image.new("RGB", (64, 64))
    px = small.load()
    for y in range(64):
        for x in range(64):
            t = (x + y) / 126.0
            px[x, y] = tuple(
                round(AMBER[i] + (AMBER_DEEP[i] - AMBER[i]) * t) for i in range(3)
            )
    return small.resize((size, size), Image.BICUBIC)


def _render(geo: dict, size: int, detailed: bool) -> Image.Image:
    plate: fitz.Rect = geo["plate"]
    big = size * SUPERSAMPLE
    bscale = (size / plate.width) * SUPERSAMPLE

    def to_px(x, y):
        return ((x - plate.x0) * bscale, (y - plate.y0) * bscale)

    canvas = _gradient(big).convert("RGBA")
    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, big - 1, big - 1], radius=int(big * CORNER_RATIO), fill=255
    )
    canvas.putalpha(mask)

    draw = ImageDraw.Draw(canvas)
    draw.polygon(_flatten(geo["body"]["items"], to_px), fill=(255, 255, 255, 255))
    draw.polygon(_flatten(geo["windshield"]["items"], to_px), fill=AMBER + (255,))

    if detailed:
        for lamp in geo["lamps"]:
            draw.polygon(_flatten(lamp["items"], to_px), fill=AMBER + (255,))
    draw.polygon(_flatten(geo["waist"]["items"], to_px), fill=AMBER + (255,))

    if detailed:
        for bogie in geo["bogies"]:
            draw.polygon(_flatten(bogie["items"], to_px), fill=(255, 255, 255, 255))
    draw.polygon(_flatten(geo["rail"]["items"], to_px), fill=(255, 255, 255, 255))

    return canvas.resize((size, size), Image.LANCZOS)


# ---------------------------------------------------------------- 主流程

def main() -> int:
    pdf = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_PDF
    if not os.path.exists(pdf):
        print(f"找不到设计稿：{pdf}")
        return 1

    doc = fitz.open(pdf)
    geo = _vector_geometry(doc[doc.page_count - 1])
    print(f"底板边长 {geo['plate'].width:.1f}pt，车灯 {len(geo['lamps'])} 个")

    # 先画一次并自检，再写文件——坏图不该覆盖掉原本能用的 .icns
    probe = _render(geo, 128, detailed=True).convert("RGB")
    r, g, b = probe.load()[20, 110]
    if not (r > 200 and 60 < g < 160 and b < 90):
        print(f"自检失败：底板不是橙色而是 #{r:02X}{g:02X}{b:02X}", file=sys.stderr)
        return 1
    print(f"自检通过：底板 #{r:02X}{g:02X}{b:02X}")

    work = tempfile.mkdtemp(prefix="fairticket-icon-")
    iconset = os.path.join(work, "AppIcon.iconset")
    os.makedirs(iconset)

    plan = [
        (16,   "icon_16x16.png"),
        (32,   "icon_16x16@2x.png"),
        (32,   "icon_32x32.png"),
        (64,   "icon_32x32@2x.png"),
        (128,  "icon_128x128.png"),
        (256,  "icon_128x128@2x.png"),
        (256,  "icon_256x256.png"),
        (512,  "icon_256x256@2x.png"),
        (512,  "icon_512x512.png"),
        (1024, "icon_512x512@2x.png"),
    ]
    for size, name in plan:
        _render(geo, size, detailed=size >= FULL_FROM).save(os.path.join(iconset, name))
        print(f"  {name:24s} {size}x{size}")

    icns = os.path.join(work, "AppIcon.icns")
    subprocess.run(["iconutil", "-c", "icns", iconset, "-o", icns], check=True)

    with open(icns, "rb") as src:
        data = src.read()
    # 顶层给打包脚本，模块内那份给关于面板（离屏渲染与 Previews 只能读模块）
    for target in (
        os.path.join(RESOURCES, "AppIcon.icns"),
        os.path.join(ROOT, "Sources", "FairTicketUI", "Resources", "AppIcon.icns"),
    ):
        os.makedirs(os.path.dirname(target), exist_ok=True)
        with open(target, "wb") as dst:
            dst.write(data)
        print(f"已写入 {target}")

    print("下一步：重新打包，并 killall Dock 刷新图标缓存。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
