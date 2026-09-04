#!/usr/bin/env python3
"""PNG の読み書き。外部ライブラリを使わない（zlib と struct だけ）。

MacもPillowも無い環境でアイコンを作り直すための道具。
scripts/recolour_app_icon.py から使う。
"""
import struct
import zlib


def read_png(path):
    """PNG を (幅, 高さ, RGBのbytearray) にする。白の上に重ねて不透明にする。"""
    data = open(path, 'rb').read()
    assert data[:8] == b'\x89PNG\r\n\x1a\n', 'PNG ではありません'

    pos = 8
    idat = bytearray()
    palette = None
    trns = None
    width = height = depth = colour_type = interlace = None

    while pos < len(data):
        length = struct.unpack('>I', data[pos:pos + 4])[0]
        tag = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if tag == b'IHDR':
            width, height, depth, colour_type, _, _, interlace = struct.unpack('>IIBBBBB', body)
        elif tag == b'PLTE':
            palette = body
        elif tag == b'tRNS':
            trns = body
        elif tag == b'IDAT':
            idat += body
        elif tag == b'IEND':
            break

    assert depth == 8, f'8ビット以外は未対応（depth={depth}）'
    assert interlace == 0, 'インターレースは未対応'

    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[colour_type]
    stride = width * channels
    raw = zlib.decompress(bytes(idat))

    out = bytearray(stride * height)
    previous = bytearray(stride)
    offset = 0
    for y in range(height):
        filter_type = raw[offset]
        offset += 1
        line = bytearray(raw[offset:offset + stride])
        offset += stride
        if filter_type == 1:      # Sub
            for i in range(channels, stride):
                line[i] = (line[i] + line[i - channels]) & 0xFF
        elif filter_type == 2:    # Up
            for i in range(stride):
                line[i] = (line[i] + previous[i]) & 0xFF
        elif filter_type == 3:    # Average
            for i in range(stride):
                left = line[i - channels] if i >= channels else 0
                line[i] = (line[i] + ((left + previous[i]) >> 1)) & 0xFF
        elif filter_type == 4:    # Paeth
            for i in range(stride):
                left = line[i - channels] if i >= channels else 0
                up = previous[i]
                upleft = previous[i - channels] if i >= channels else 0
                p = left + up - upleft
                pa, pb, pc = abs(p - left), abs(p - up), abs(p - upleft)
                if pa <= pb and pa <= pc:
                    pred = left
                elif pb <= pc:
                    pred = up
                else:
                    pred = upleft
                line[i] = (line[i] + pred) & 0xFF
        out[y * stride:(y + 1) * stride] = line
        previous = line

    rgb = bytearray(width * height * 3)
    for i in range(width * height):
        if colour_type == 2:
            r, g, b, a = out[i * 3], out[i * 3 + 1], out[i * 3 + 2], 255
        elif colour_type == 6:
            r, g, b, a = out[i * 4], out[i * 4 + 1], out[i * 4 + 2], out[i * 4 + 3]
        elif colour_type == 0:
            r = g = b = out[i]
            a = 255
        elif colour_type == 4:
            r = g = b = out[i * 2]
            a = out[i * 2 + 1]
        else:  # palette
            index = out[i]
            r, g, b = palette[index * 3], palette[index * 3 + 1], palette[index * 3 + 2]
            a = trns[index] if trns and index < len(trns) else 255
        if a != 255:  # 透明は白に重ねる
            k = a / 255.0
            r = int(r * k + 255 * (1 - k) + 0.5)
            g = int(g * k + 255 * (1 - k) + 0.5)
            b = int(b * k + 255 * (1 - k) + 0.5)
        rgb[i * 3] = r
        rgb[i * 3 + 1] = g
        rgb[i * 3 + 2] = b
    return width, height, rgb


def write_png(path, size, pixels):
    """RGB（アルファ無し）で書く。App Store はアルファを許さない。"""
    rows = bytearray()
    stride = size * 3
    for y in range(size):
        rows.append(0)
        rows += pixels[y * stride:(y + 1) * stride]

    def chunk(tag, body):
        return (struct.pack('>I', len(body)) + tag + body
                + struct.pack('>I', zlib.crc32(tag + body) & 0xFFFFFFFF))

    out = b'\x89PNG\r\n\x1a\n'
    out += chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 2, 0, 0, 0))
    out += chunk(b'IDAT', zlib.compress(bytes(rows), 9))
    out += chunk(b'IEND', b'')
    open(path, 'wb').write(out)
