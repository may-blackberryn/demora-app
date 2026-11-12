#!/usr/bin/env python3
"""Generate Latch/CountryBorders.bin, the offline country borders for When &
where country conditions (docs/conditional-sessions-redesign.md §5.7, C5, Q4).

Source: Natural Earth admin-0 countries, public domain, pinned to one release
and checked by SHA-256 before anything is written (see SOURCE below and
Latch/COUNTRY_BORDERS_ATTRIBUTION.md). This script never downloads anything:
fetch the source once, from the official Natural Earth repository, with

    curl -sSfL -o ne_10m_admin_0_countries.geojson \\
      https://raw.githubusercontent.com/nvkelso/natural-earth-vector/v5.1.2/geojson/ne_10m_admin_0_countries.geojson

and pass its path. Usage:

    python3 Tests/GenerateCountryBorders.py --source PATH            # write
    python3 Tests/GenerateCountryBorders.py --source PATH --check    # compare

The app never reads the network for borders: it reads only the bundled file.

What it does, deterministically:
- One entry per ISO 3166-1 alpha-2 code from `ISO_A2_EH` (features sharing a
  code are merged, e.g. Australia's territories). Features without a code
  (`-99`: disputed or indeterminate areas such as Northern Cyprus, Somaliland,
  Siachen) are kept under the code "~~": the app treats a point inside them,
  or on their edge, as "too close to a border to tell" (Q4).
- Rings are simplified with Douglas-Peucker on a local equirectangular plane,
  in metres. Land borders (vertices another entry shares; Natural Earth's
  10m borders share exact vertices) keep BORDER_TOLERANCE_M and are
  simplified once in a canonical direction, so both neighbours keep the same
  vertices: no gaps or overlaps along land borders. Coastlines keep
  COAST_TOLERANCE_M (the app treats sea next to a single country as that
  country). Junctions and border/coast transitions are never removed. Rings
  whose simplification would collapse keep their source points. Coordinates
  are then rounded to 1e-4 degrees (at most 8 m), the same on both sides.
- Rings are written as zigzag varint deltas (format below), little-endian.

Format (version 1):
    "DMCB" · u8 version · u32 units per degree · u16 country count
    per country (sorted by code): 2 ASCII bytes · varint ring count
      per ring: varint point count (closing point not repeated)
        per point: zigzag varint Δlongitude, Δlatitude in units
                   (from the previous point; the first from 0, 0)
"""

import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
import sys

ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / 'Latch/CountryBorders.bin'
SOURCE = {
    'name': 'Natural Earth 1:10m Cultural Vectors, Admin 0 - Countries',
    'version': '5.1.2',
    'url': 'https://raw.githubusercontent.com/nvkelso/natural-earth-vector/v5.1.2/geojson/'
           'ne_10m_admin_0_countries.geojson',
    'sha256': '239eec57ac17f100a11e2536cffc56752c318b50ae765b0918ff7aab4ce8f255',
}
BORDER_TOLERANCE_M = 100.0
COAST_TOLERANCE_M = 1000.0
UNITS = 10_000
UNIDENTIFIED = '~~'
EARTH_M = 6_371_008.8
MAGIC = b'DMCB'
VERSION = 1


def zigzag(value):
    return (value << 1) ^ (value >> 63) if value < 0 else value << 1


def varint(value):
    out = bytearray()
    while True:
        byte = value & 0x7F
        value >>= 7
        if value:
            out.append(byte | 0x80)
        else:
            out.append(byte)
            return bytes(out)


def segment_distance_m(p, a, b):
    """Distance from p to segment ab on a plane local to p (metres)."""
    scale = math.cos(math.radians(p[1]))
    ax, ay = (a[0] - p[0]) * scale, a[1] - p[1]
    bx, by = (b[0] - p[0]) * scale, b[1] - p[1]
    dx, dy = bx - ax, by - ay
    length = dx * dx + dy * dy
    t = 0.0 if length == 0 else max(0.0, min(1.0, -(ax * dx + ay * dy) / length))
    x, y = ax + t * dx, ay + t * dy
    return math.hypot(x, y) * math.pi / 180 * EARTH_M


def simplify_chain(points, tolerance):
    """Douglas-Peucker on an open chain; keeps both ends."""
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        first, last = stack.pop()
        best, index = -1.0, -1
        for i in range(first + 1, last):
            distance = segment_distance_m(points[i], points[first], points[last])
            if distance > best:
                best, index = distance, i
        if index >= 0 and best > tolerance:
            keep[index] = True
            stack.append((first, index))
            stack.append((index, last))
    return [p for p, k in zip(points, keep) if k]


def canonical_simplify(chain, tolerance):
    """Douglas-Peucker in one canonical direction, so a border shared by two
    countries (walked in opposite directions) keeps the same vertices."""
    if len(chain) <= 2:
        return chain
    if chain[0] == chain[-1]:
        far = max(range(1, len(chain) - 1), key=lambda i: (
            (chain[i][0] - chain[0][0]) ** 2 + (chain[i][1] - chain[0][1]) ** 2, chain[i]))
        return canonical_simplify(chain[:far + 1], tolerance)[:-1] + canonical_simplify(chain[far:], tolerance)
    if chain[0] > chain[-1]:
        return list(reversed(simplify_chain(list(reversed(chain)), tolerance)))
    return simplify_chain(chain, tolerance)


def simplify_ring(ring, code, owners):
    """Land borders (vertices shared with another entry) keep BORDER_TOLERANCE_M,
    coastlines COAST_TOLERANCE_M. Junctions and border/coast transitions are
    never removed; between them each chain is simplified on its own."""
    points = [tuple(p[:2]) for p in ring]
    if len(points) > 1 and points[0] == points[-1]:
        points = points[:-1]
    count = len(points)
    if count < 4:
        return points
    labels = [frozenset(owners[p] - {code}) for p in points]
    fixed = [i for i in range(count)
             if len(owners[points[i]]) >= 3 or labels[i] != labels[i - 1] or labels[i] != labels[(i + 1) % count]]
    if not fixed:
        # A whole island, or a whole enclave ring: start at its smallest
        # vertex, the same on both sides of a shared ring.
        fixed = [min(range(count), key=lambda i: points[i])]
    result = []
    for n, start in enumerate(fixed):
        end = fixed[(n + 1) % len(fixed)]
        chain = [points[(start + k) % count] for k in range(((end - start) % count or count) + 1)]
        interior = chain[1:-1]
        shared = bool(interior) and bool(labels[(start + 1) % count])
        kept = canonical_simplify(chain, BORDER_TOLERANCE_M if shared else COAST_TOLERANCE_M)
        result.extend(kept[:-1])
    return result if len(result) >= 3 else points


def quantize(ring):
    out = []
    for lon, lat in ring:
        point = (round(lon * UNITS), round(lat * UNITS))
        if not out or out[-1] != point:
            out.append(point)
    while len(out) > 1 and out[0] == out[-1]:
        out.pop()
    return out


def build(source_bytes):
    data = json.loads(source_bytes)
    countries = {}
    owners = {}
    for feature in data['features']:
        code = feature['properties'].get('ISO_A2_EH') or '-99'
        code = UNIDENTIFIED if code == '-99' else code
        geometry = feature['geometry']
        polygons = geometry['coordinates'] if geometry['type'] == 'MultiPolygon' else [geometry['coordinates']]
        for polygon in polygons:
            for ring in polygon:
                for point in ring:
                    owners.setdefault(tuple(point[:2]), set()).add(code)
    for feature in data['features']:
        code = feature['properties'].get('ISO_A2_EH') or '-99'
        if code == '-99':
            code = UNIDENTIFIED
        if not (code == UNIDENTIFIED or (len(code) == 2 and code.isascii() and code.isupper())):
            raise SystemExit(f'unexpected code {code!r}')
        geometry = feature['geometry']
        polygons = geometry['coordinates'] if geometry['type'] == 'MultiPolygon' else [geometry['coordinates']]
        rings = countries.setdefault(code, [])
        for polygon in polygons:
            for ring in polygon:
                simplified = quantize(simplify_ring(ring, code, owners))
                if len(simplified) >= 3:
                    rings.append(simplified)
    out = bytearray(MAGIC)
    out += struct.pack('<BIH', VERSION, UNITS, len(countries))
    points = 0
    for code in sorted(countries):
        rings = countries[code]
        out += code.encode('ascii') + varint(len(rings))
        for ring in rings:
            out += varint(len(ring))
            last = (0, 0)
            for point in ring:
                out += varint(zigzag(point[0] - last[0])) + varint(zigzag(point[1] - last[1]))
                last = point
            points += len(ring)
    return bytes(out), len(countries), points


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', required=True, type=Path)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    source_bytes = args.source.read_bytes()
    digest = hashlib.sha256(source_bytes).hexdigest()
    if digest != SOURCE['sha256']:
        raise SystemExit(f'source SHA-256 {digest} is not the pinned {SOURCE["sha256"]}')
    output, count, points = build(source_bytes)
    output_digest = hashlib.sha256(output).hexdigest()
    print(f'{count} entries, {points} points, {len(output)} bytes, sha256 {output_digest}')
    if args.check:
        if not TARGET.exists() or TARGET.read_bytes() != output:
            print(f'FAIL {TARGET.relative_to(ROOT)} differs from the generated output')
            return 1
        print('OK: bundled borders match the pinned source')
        return 0
    TARGET.write_bytes(output)
    return 0


if __name__ == '__main__':
    sys.exit(main())
