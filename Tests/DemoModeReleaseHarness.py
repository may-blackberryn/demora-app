#!/usr/bin/env python3
"""The screenshot demo mode never reaches Release.
Run: python3 Tests/DemoModeReleaseHarness.py
     DEMORA_RELEASE_APP=<path>/Release-iphoneos/Latch.app python3 Tests/DemoModeReleaseHarness.py
Source guards: Latch/DemoMode.swift is wrapped whole in `#if DEBUG`; every
other mention of the demo (types, launch arguments, suite, fake token prefix,
mock app names) sits inside a `#if DEBUG` branch; extensions never mention
it; the demo's tr() keys already exist (no new translation keys).
With DEMORA_RELEASE_APP set, the built Release binary is also scanned for
the demo's strings. Not a device test.
"""
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEMO = ROOT / "Latch/DemoMode.swift"
MARKERS = ["DemoMode", "DemoScreen", "DemoLimitsUsageCard", "DemoInsightsView",
           "DemoSelectedApps", "DemoAppLabel", "DemoraDemoMode", "DemoraDemoScreen",
           "demora.screenshot-demo", "demora-demo:"]
MOCK_STRINGS = ["DemoraDemoMode", "DemoraDemoScreen", "demora.screenshot-demo", "demora-demo:",
                "Chatterly", "Picnook", "Inkpost", "Wavely", "Pebble Run", "K7P4QX", "HK4T7Q", "demo-only"]
failures = []

# 1. The demo file is DEBUG from its first to its last line of code.
source = DEMO.read_text()
code = [line for line in source.splitlines() if line.strip() and not line.strip().startswith("//")]
if code[0].strip() != "#if DEBUG" or code[-1].strip() != "#endif":
    failures.append("Latch/DemoMode.swift is not wrapped whole in #if DEBUG … #endif")
if re.search(r"^\s*#(else|elseif)\b", source, re.M):
    failures.append("Latch/DemoMode.swift has an #else branch that Release would compile")


def outside_debug(text):
    """Lines (number, text) compiled when DEBUG is off."""
    stack, found = [], []
    for number, line in enumerate(text.splitlines(), 1):
        stripped = line.strip()
        if stripped.startswith("#if"):
            stack.append(stripped == "#if DEBUG")
            continue
        if stripped.startswith("#elseif") or stripped == "#else":
            stack[-1] = False   # an #else of #if DEBUG is the Release branch
            continue
        if stripped == "#endif":
            stack.pop()
            continue
        if not any(flag is True for flag in stack) and not stripped.startswith("//"):
            found.append((number, line))
    return found


# 2. Everywhere else, the demo only appears inside #if DEBUG.
for folder in ["Latch", "Shared", "LatchMonitor", "LatchReport", "LatchWidgets", "LatchShieldUI"]:
    for path in sorted((ROOT / folder).glob("**/*.swift")):
        if path == DEMO:
            continue
        for number, line in outside_debug(path.read_text()):
            for marker in MARKERS:
                if marker in line:
                    failures.append(f"{path.relative_to(ROOT)}:{number} uses {marker} outside #if DEBUG")

# 3. Extensions never mention the demo at all.
for folder in ["LatchMonitor", "LatchReport", "LatchWidgets", "LatchShieldUI"]:
    for path in (ROOT / folder).glob("**/*.swift"):
        if any(marker in path.read_text() for marker in MARKERS):
            failures.append(f"{path.relative_to(ROOT)} mentions the demo")

# 4. The store switch is DEBUG-only and the App Group stays the Release path.
store = (ROOT / "Shared/SharedStore.swift").read_text()
if "return UserDefaults(suiteName: LatchConstants.appGroupID)!" not in store:
    failures.append("SharedStore.defaults no longer returns the App Group suite")
hooks = {"Latch/LatchApp.swift": "DemoMode.prepare()", "Latch/AppModel.swift": "if DemoMode.isOn {",
         "Latch/HomeView.swift": "DemoLimitsUsageCard(", "Latch/UsageInsightsView.swift": "DemoInsightsView()",
         "Latch/CheckInSheet.swift": "DemoMode.homeFix", "Shared/SharedStore.swift": "DemoModeLaunch.isOn"}
for name, hook in hooks.items():
    if hook not in (ROOT / name).read_text():
        failures.append(f"{name}: expected demo hook {hook!r} is gone (update this harness)")

# 5. No new translation keys: every tr("…") literal in the demo already exists.
catalog = (ROOT / "Shared/Localization.swift").read_text()
spanish = catalog[catalog.index("let spanishStrings"):]
for key in sorted(set(re.findall(r'\btr\("((?:[^"\\]|\\.)*)"\)', source))):
    if f'"{key}":' not in spanish:
        failures.append(f"Latch/DemoMode.swift uses tr({key!r}), which is not an existing catalog key")

# 6. Optional: the built Release binary carries none of the demo's strings.
release = os.environ.get("DEMORA_RELEASE_APP")
binary_note = "Release binary not scanned (set DEMORA_RELEASE_APP)"
if release:
    executable = Path(release) / "Latch"
    data = executable.read_bytes()
    for text in MOCK_STRINGS:
        if text.encode() in data:
            failures.append(f"Release binary {executable} contains {text!r}")
    if b"group.com.may.screentimedelay" not in data:
        failures.append("Release binary scan looks wrong: the App Group ID wasn't found either")
    binary_note = f"Release binary scanned: {executable}"

if failures:
    print("\n".join("FAIL " + item for item in failures))
    sys.exit(1)
print(f"Demo mode release guard: DEBUG-only file and hooks, no extension use, no new keys. {binary_note}")
