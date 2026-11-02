#!/usr/bin/env python3
"""Pure contrast checks for the foundations palette (docs/foundations-redesign.md §5.1).

Reads the hex pairs from `InkPalette` in Latch/Theme.swift and checks every
text/background pair in light and dark, with both accents, against WCAG 2.x:
body text ≥ 4.5:1, large serif ≥ 3:1. No Xcode build, defaults or UI involved.
"""
from pathlib import Path
import math
import re
import sys
sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[1]
BODY, LARGE = 4.5, 3.0


def channel(value):
    c = value / 255
    return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4


def luminance(rgb):
    r, g, b = (rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF
    return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)


def contrast(a, b):
    hi, lo = sorted((luminance(a), luminance(b)), reverse=True)
    return (hi + 0.05) / (lo + 0.05)


def blend(top, bottom, amount):
    """Mirror of `Ink.blend` (Swift `.rounded()` rounds half away from zero)."""
    out = 0
    for shift in (16, 8, 0):
        a, b = (top >> shift) & 0xFF, (bottom >> shift) & 0xFF
        out |= int(math.floor(a * amount + b * (1 - amount) + 0.5)) << shift
    return out


def palette(source):
    block = source.split('enum InkPalette {', 1)[1].split('\n}\n', 1)[0]
    pairs = {name: {'light': int(light, 16), 'dark': int(dark, 16)} for name, light, dark in
             re.findall(r'static let (\w+)\s*=\s*InkPair\(light:\s*0x([0-9A-Fa-f]{6}),'
                        r'\s*dark:\s*0x([0-9A-Fa-f]{6})\)', block)}
    tints = {mode: float(value) for mode, value in
             re.findall(r'static let tint(Light|Dark): Double = ([0-9.]+)', block)}
    return pairs, {'light': tints['Light'], 'dark': tints['Dark']}


def checks(pairs, tints):
    """Yield (label, foreground, background, minimum) for every pair in §5.1."""
    for accent in ('blue', 'red'):
        accent_ink = pairs['accentBlue' if accent == 'blue' else 'accentRed']
        loosen_ink = pairs['loosenOchre' if accent == 'red' else 'loosen']
        inks = {'ink': pairs['ink'], 'inkSoft': pairs['inkSoft'], 'accent': accent_ink,
                'loosen': loosen_ink, 'free': pairs['free']}
        families = {'accent': accent_ink, 'loosen': loosen_ink, 'free': pairs['free']}
        for mode in ('light', 'dark'):
            where = f'{mode}/{accent} accent'
            for bg in ('paper', 'card', 'cardRaised'):
                for name, ink in inks.items():
                    yield f'{name} on {bg} ({where})', ink[mode], pairs[bg][mode], BODY
            for name, ink in families.items():
                tint = blend(ink[mode], pairs['card'][mode], tints[mode])
                # Chips and receipts: full-strength ink on its own tint.
                yield f'{name} on tint({name}) ({where})', ink[mode], tint, BODY
                # Buttons and HoldButton fill: paper-coloured label on full ink.
                yield f'paper label on {name} fill ({where})', pairs['paper'][mode], ink[mode], BODY
            # Large serif times sit on the same surfaces; ≥ 3:1 is implied by
            # the body checks above but kept explicit for the spec's target.
            for bg in ('paper', 'card'):
                yield f'timeLarge accent on {bg} ({where})', accent_ink[mode], pairs[bg][mode], LARGE


def main():
    # Self-test of the maths against known WCAG values.
    assert round(contrast(0x000000, 0xFFFFFF), 2) == 21.0
    assert 4.47 < contrast(0x777777, 0xFFFFFF) < 4.49
    assert blend(0xFF0000, 0x000000, 0.5) == 0x800000

    source = (ROOT / 'Latch/Theme.swift').read_text()
    pairs, tints = palette(source)
    required = {'paper', 'card', 'cardRaised', 'ink', 'inkSoft', 'hairline', 'accentBlue',
                'accentRed', 'loosen', 'loosenOchre', 'free'}
    assert required <= pairs.keys(), ('missing palette tokens', sorted(required - pairs.keys()))
    # F2: with the red accent, "blocked/looser" must not equal the primary colour.
    assert pairs['loosenOchre'] != pairs['accentRed']
    assert 'accentValue == "red" ? InkPalette.loosenOchre : InkPalette.loosen' in source

    results = list(checks(pairs, tints))
    failures = [(label, round(contrast(fg, bg), 2), minimum)
                for label, fg, bg, minimum in results if contrast(fg, bg) < minimum]
    assert not failures, ('contrast below target', failures)

    # The harness must catch a regression: the spec's original 22 % dark tint
    # leaves red text on its tint at about 3.8:1.
    broken = list(checks(pairs, {'light': tints['light'], 'dark': 0.22}))
    assert any(contrast(fg, bg) < minimum for _, fg, bg, minimum in broken), \
        'harness failed to detect a known failing tint'

    worst = min(results, key=lambda item: contrast(item[1], item[2]) / item[3])
    print(f'PASS: {len(results)} text/background pairs (light+dark, blue+red accents) '
          f'meet body {BODY}:1 / large {LARGE}:1; tightest is {worst[0]} at '
          f'{contrast(worst[1], worst[2]):.2f}:1; a known failing tint is detected.')


if __name__ == '__main__':
    main()
