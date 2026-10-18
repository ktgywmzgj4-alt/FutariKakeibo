#!/usr/bin/env python3
"""お財布の絵だけを、まわりを透明にして取り出す（待ち時間のくるくる用）。

BrandMark は白い正方形の上にがま口が載った1枚絵で、そのまま回すと
**白い四角ごと回る**。青い保存ボタンの上では白い角丸の板が回って見えた
（2026-10-15 利用者の指摘）。ここで外側の白だけを抜いて WalletGlyph を作る。

- 抜くのは**外側とつながった白**だけ。「¥」も白なので、白を一律に抜くと「¥」まで透ける
- 囲まれた白は「¥」（囲まれた白でいちばん大きいもの）だけ残す。1x では口金と袋の
  すき間が画素の粗さで閉じて「囲まれた白」になるが、2x・3x では外とつながっていて
  抜けるので、見え方をそろえるために1xでも抜く
- **輪郭のなめらかさは保つ。** 縁の画素は「黒・青・珊瑚のどれかと白の混ざり」なので、
  混ざり具合から透明度と元の色を逆算する。白との境をそのまま残すと、
  青い地の上で輪郭に白いふちが出る
- **回転の中心は「¥」。** 「¥」の中心を画像の中心に合わせる（回すと「¥」が止まって見え、
  そのまわりをお財布が回る。2026-10-18 利用者の希望）。
  画像の大きさは BrandMark と同じにしておく（呼ぶ側の大きさ指定を変えなくて済む）

使い方:
  python3 scripts/make_wallet_glyph.py
"""
import json
import math
import os
import sys
from collections import deque

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pngio import read_png, write_png_rgba  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, 'FutariKakeibo', 'Resources', 'Assets.xcassets')
SOURCE = os.path.join(ASSETS, 'BrandMark.imageset')
TARGET = os.path.join(ASSETS, 'WalletGlyph.imageset')
SCALES = [('', '1x'), ('@2x', '2x'), ('@3x', '3x')]

# 絵に使われている色。AppTheme.swift と scripts/recolour_app_icon.py の値。
INK = [(0, 0, 0), (0x2D, 0x5B, 0xD1), (0xEE, 0x5D, 0x59)]

# 白とみなす幅。原案の白は 253〜255 に散っている。
WHITE_TOLERANCE = 12
# 外側の白から何画素までを「縁」とみなして、混ざり具合を逆算するか。
EDGE_BAND = 2


def is_white(pixel):
    return (765 - sum(pixel)) <= WHITE_TOLERANCE


def components(width, height, mask):
    """mask が真の画素を4近傍でつないだ塊に分ける。[(画素の一覧, 外周に触れるか)]"""
    seen = bytearray(width * height)
    found = []
    for start in range(width * height):
        if not mask[start] or seen[start]:
            continue
        seen[start] = 1
        queue = deque([start])
        members = []
        touches_border = False
        while queue:
            i = queue.popleft()
            members.append(i)
            x, y = i % width, i // width
            if x in (0, width - 1) or y in (0, height - 1):
                touches_border = True
            for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if 0 <= nx < width and 0 <= ny < height:
                    j = ny * width + nx
                    if mask[j] and not seen[j]:
                        seen[j] = 1
                        queue.append(j)
        found.append((members, touches_border))
    return found


def unblend(pixel):
    """白と混ざった画素から、元の色と不透明度を逆算する。

    pixel = a * ink + (1 - a) * 白 を、使われている色のそれぞれで最小二乗で解き、
    いちばん当てはまる色を採る。
    """
    best = None
    for ink in INK:
        numerator = sum((255 - pixel[c]) * (255 - ink[c]) for c in range(3))
        denominator = sum((255 - ink[c]) ** 2 for c in range(3))
        alpha = max(0.0, min(1.0, numerator / denominator))
        error = sum((pixel[c] - (alpha * ink[c] + (1 - alpha) * 255)) ** 2 for c in range(3))
        if best is None or error < best[0]:
            best = (error, ink, alpha)
    return best[1], best[2]


def make_glyph(source_path):
    width, height, rgb = read_png(source_path)
    pixels = [(rgb[i * 3], rgb[i * 3 + 1], rgb[i * 3 + 2]) for i in range(width * height)]
    white = [is_white(p) for p in pixels]

    # 1. 外側とつながった白は地。囲まれた白は「¥」だけ残す。
    background = bytearray(width * height)
    enclosed = []
    for members, touches_border in components(width, height, white):
        if touches_border:
            for i in members:
                background[i] = 1
        else:
            enclosed.append(members)
    enclosed.sort(key=len, reverse=True)
    for members in enclosed[1:]:
        for i in members:
            background[i] = 1

    # 2. 地から EDGE_BAND 画素以内の縁は、混ざり具合から透明度を逆算する。
    near_background = bytearray(width * height)
    for i in range(width * height):
        if not background[i]:
            continue
        x, y = i % width, i // width
        for dy in range(-EDGE_BAND, EDGE_BAND + 1):
            for dx in range(-EDGE_BAND, EDGE_BAND + 1):
                nx, ny = x + dx, y + dy
                if 0 <= nx < width and 0 <= ny < height:
                    near_background[ny * width + nx] = 1

    rgba = [(0, 0, 0, 0)] * (width * height)
    for i, pixel in enumerate(pixels):
        if background[i]:
            continue
        if near_background[i] and not white[i]:
            ink, alpha = unblend(pixel)
            rgba[i] = (*ink, round(alpha * 255))
        else:
            rgba[i] = (*pixel, 255)

    # 3. 「¥」の中心を、画像の中心に合わせる。回すと「¥」が止まって見え、
    #    そのまわりをお財布が回る（2026-10-18 利用者の希望。以前は絵の外接矩形の中心で回していて、
    #    「¥」ごと円を描いていた）。「¥」は 1 で残した、囲まれた白のうちいちばん大きいもの。
    yen = enclosed[0]
    yen_xs = [i % width for i in yen]
    yen_ys = [i // width for i in yen]
    shift_x = round((width - 1) / 2 - (min(yen_xs) + max(yen_xs)) / 2)
    shift_y = round((height - 1) / 2 - (min(yen_ys) + max(yen_ys)) / 2)

    centre_x, centre_y = (width - 1) / 2, (height - 1) / 2
    out = bytearray(width * height * 4)
    dropped = 0
    reach = 0.0
    for i, pixel in enumerate(rgba):
        if pixel[3] == 0:
            continue
        x, y = i % width + shift_x, i // width + shift_y
        if 0 <= x < width and 0 <= y < height:
            j = (y * width + x) * 4
            out[j:j + 4] = bytes(pixel)
            reach = max(reach, math.hypot(x - centre_x, y - centre_y))
        else:
            dropped += 1
    # 動かした結果、絵の端が画像の外に出たら作り直しが要る（黙って欠けさせない）。
    if dropped:
        sys.exit(f'{source_path}: 「¥」を中心にすると {dropped} 画素がはみ出します。')
    # 回したときにお財布が描く円の半径（画像の幅の半分を 1 とする）。1 以下なら枠に収まる。
    return width, height, out, (shift_x, shift_y), len(enclosed), reach / (width / 2)


def main():
    os.makedirs(TARGET, exist_ok=True)
    images = []
    for suffix, scale in SCALES:
        width, height, out, shift, enclosed, reach = make_glyph(
            os.path.join(SOURCE, f'BrandMark{suffix}.png'))
        name = f'WalletGlyph{suffix}.png'
        write_png_rgba(os.path.join(TARGET, name), width, height, out)
        images.append({'filename': name, 'idiom': 'universal', 'scale': scale})
        print(f"{name}: {width}x{height}  「¥」を中心に {shift}  囲まれた白 {enclosed}個（「¥」だけ残した）  回る円の半径 {reach:.2f}")

    contents = {
        'images': images,
        'info': {'author': 'xcode', 'version': 1},
        # 色をそのまま出す。テンプレート扱いにすると単色で塗られる。
        'properties': {'template-rendering-intent': 'original'},
    }
    with open(os.path.join(TARGET, 'Contents.json'), 'w') as f:
        json.dump(contents, f, indent=2)
        f.write('\n')


if __name__ == '__main__':
    main()
