#!/usr/bin/env python3
import sys
from pathlib import Path

def _read_token(data, idx):
    size = len(data)
    while idx < size:
        b = data[idx]
        if b == 35:  # '#'
            idx += 1
            while idx < size and data[idx] not in (10, 13):
                idx += 1
        elif b in (9, 10, 13, 32):
            idx += 1
        else:
            break
    start = idx
    while idx < size and data[idx] not in (9, 10, 13, 32):
        idx += 1
    if start == idx:
        raise ValueError('Invalid PNM header')
    return data[start:idx], idx

def load_p5(path):
    data = Path(path).read_bytes()
    if not data.startswith(b'P5'):
        raise ValueError(f'{path} is not a binary PGM (P5) file')
    idx = 2
    width_bytes, idx = _read_token(data, idx)
    height_bytes, idx = _read_token(data, idx)
    maxval_bytes, idx = _read_token(data, idx)
    width = int(width_bytes)
    height = int(height_bytes)
    maxval = int(maxval_bytes)
    if maxval > 255:
        raise ValueError('Only 8-bit PGM files supported')
    while idx < len(data) and data[idx] in (9, 10, 13, 32):
        idx += 1
    payload = data[idx:]
    expected = width * height
    if len(payload) != expected:
        raise ValueError(f'Unexpected payload size ({len(payload)} vs {expected})')
    return width, height, maxval, payload

def compare(path_a, path_b):
    dim_a = load_p5(path_a)
    dim_b = load_p5(path_b)
    if dim_a[:2] != dim_b[:2]:
        raise ValueError('Image dimensions mismatch')
    if dim_a[2] != dim_b[2]:
        print('Warning: maxval differs, continuing comparison')
    samples_a = dim_a[3]
    samples_b = dim_b[3]
    total = 0
    max_diff = 0
    min_diff = 255
    mismatch = 0
    examples = []
    for idx, (a, b) in enumerate(zip(samples_a, samples_b)):
        diff = abs(a - b)
        total += diff
        if diff > max_diff:
            max_diff = diff
        if diff < min_diff:
            min_diff = diff
        if diff and len(examples) < 10:
            examples.append((idx, diff, a, b))
        if diff:
            mismatch += 1
    avg = total / len(samples_a)
    if min_diff == 255:
        min_diff = 0
    return max_diff, min_diff, avg, mismatch, examples

def main(argv):
    if len(argv) != 3:
        print('Usage: python scripts/compare_pgm.py <image_a.pgm> <image_b.pgm>')
        return 1
    max_diff, min_diff, avg, mismatch, examples = compare(argv[1], argv[2])
    print(f'max diff {max_diff}, min diff {min_diff}, avg diff {avg:.4f}, mismatched samples {mismatch}')
    for idx, (sample_idx, diff, a, b) in enumerate(examples):
        print(f'  example {idx}: idx={sample_idx} valA={a} valB={b} diff={diff}')
    return 0

if __name__ == '__main__':
    raise SystemExit(main(sys.argv))
