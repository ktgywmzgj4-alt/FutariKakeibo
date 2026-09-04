#!/usr/bin/env python3
"""原案のアイコンの色だけを、アプリの色にそろえる。

形は一切さわらない。変えるのは次の3つだけ。
  1. 留め金ふたつの色を AppTheme.swift の値にする
  2. 地をまっ白に、袋をまっ黒にそろえる（原案はわずかに灰色がかっている）
  3. 1024px・アルファ無しにする（App Store の条件）

輪郭のなめらかさ（アンチエイリアス）は保つ。
留め金のふちは「元の色と白の混ざり具合」を先に求めてから、
同じ割合で新しい色と白を混ぜ直している。塗りつぶすと輪郭がぎざぎざになる。
"""
import sys

from pngio import read_png, write_png

# AppTheme.swift の値。
BLUE = (0x2D, 0x5B, 0xD1)   # メンバー1（accent）
CORAL = (0xEE, 0x5D, 0x59)  # メンバー2（coral）

# 原案の留め金の色（画像から数えたいちばん多い色）。
SOURCE_BLUE = (24, 97, 203)
SOURCE_CORAL = (253, 86, 82)

# 地と袋。原案は 253〜255 と 0〜1 に散っているので、両端に寄せる。
GROUND_LEVEL = 254
INK_LEVEL = 1

# 色とみなす差。これ未満は灰色として扱う。
COLOUR_THRESHOLD = 6


def mixing_ratio(value, source_channel):
    """白と元の色が何割で混ざっているかを、いちばん差の大きい面から求める。"""
    span = 255 - source_channel
    if span <= 0:
        return 1.0
    return min(1.0, max(0.0, (255 - value) / span))


def recolour(width, height, pixels):
    blue_channel = 0   # 青は赤の面がいちばん白から遠い
    coral_channel = 2  # コーラルは青の面がいちばん白から遠い
    span = GROUND_LEVEL - INK_LEVEL

    for i in range(width * height):
        j = i * 3
        r, g, b = pixels[j], pixels[j + 1], pixels[j + 2]

        if b - r > COLOUR_THRESHOLD:
            ratio = mixing_ratio(r, SOURCE_BLUE[blue_channel])
            target = BLUE
        elif r - b > COLOUR_THRESHOLD and r - g > COLOUR_THRESHOLD:
            ratio = mixing_ratio(b, SOURCE_CORAL[coral_channel])
            target = CORAL
        else:
            # 灰色。地をまっ白へ、袋をまっ黒へ寄せる。
            for k, value in enumerate((r, g, b)):
                level = (value - INK_LEVEL) * 255.0 / span
                pixels[j + k] = int(min(255.0, max(0.0, level)) + 0.5)
            continue

        for k in range(3):
            pixels[j + k] = int(target[k] * ratio + 255 * (1 - ratio) + 0.5)


def resize(width, height, pixels, size):
    """面積で平均して縮める。細い軸をつぶさないための素直な方法。"""
    out = bytearray(size * size * 3)
    step_x = width / size
    step_y = height / size
    for oy in range(size):
        y0 = oy * step_y
        y1 = y0 + step_y
        first_y, last_y = int(y0), min(height - 1, int(y1 - 1e-9))
        for ox in range(size):
            x0 = ox * step_x
            x1 = x0 + step_x
            first_x, last_x = int(x0), min(width - 1, int(x1 - 1e-9))
            total = [0.0, 0.0, 0.0]
            weight_sum = 0.0
            for sy in range(first_y, last_y + 1):
                wy = min(y1, sy + 1) - max(y0, sy)
                if wy <= 0:
                    continue
                row = sy * width
                for sx in range(first_x, last_x + 1):
                    wx = min(x1, sx + 1) - max(x0, sx)
                    if wx <= 0:
                        continue
                    weight = wx * wy
                    j = (row + sx) * 3
                    total[0] += pixels[j] * weight
                    total[1] += pixels[j + 1] * weight
                    total[2] += pixels[j + 2] * weight
                    weight_sum += weight
            k = (oy * size + ox) * 3
            for c in range(3):
                out[k + c] = int(total[c] / weight_sum + 0.5)
    return out


if __name__ == '__main__':
    source = sys.argv[1]
    out_dir = sys.argv[2]
    width, height, pixels = read_png(source)
    recolour(width, height, pixels)
    for size, name in ((1024, 'AppIcon.png'),
                       (384, 'BrandMark@3x.png'),
                       (256, 'BrandMark@2x.png'),
                       (128, 'BrandMark.png')):
        write_png(f'{out_dir}/{name}', size, resize(width, height, pixels, size))
        print(f'{name} {size}x{size}')
