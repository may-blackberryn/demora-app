#!/usr/bin/env python3
"""F6 (iPhone Duo / resizable windows): source-level guards only.

This does not render anything or prove the layout on a device or simulator.
It pins the rules from Apple's foldable guidance that the code can show:
layouts never branch on the device idiom, screen or orientation; the one
idiom read left is the Screen Time data filter; sheets touched by F6 keep the
shared readable width; the photo cropper refits when its window resizes.
"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
TARGETS = ("Latch", "LatchReport", "LatchWidgets", "LatchShieldUI", "LatchMonitor", "Shared")
sources = {p: p.read_text() for t in TARGETS for p in (ROOT / t).rglob("*.swift")}
assert len(sources) > 50, len(sources)


def code_lines(text):
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("//") or stripped.startswith("///"):
            continue
        yield line.split("//")[0]


# 1. No screen-based or orientation-based layout anywhere.
forbidden = re.compile(
    r"UIScreen\b|\.mainScreen\b|UIDevice\.current\.orientation|interfaceOrientation"
    r"|windowScene\??\.screen|UIApplication\.shared\.windows")
for path, text in sources.items():
    for line in code_lines(text):
        assert not forbidden.search(line), f"{path.relative_to(ROOT)}: {line.strip()}"

# 2. The only idiom read is the DeviceActivity data filter (which device's
# usage to show), not layout. An unfolded Duo is still an iPhone.
idiom_uses = [(p, l) for p, t in sources.items() for l in code_lines(t)
              if "userInterfaceIdiom" in l]
assert len(idiom_uses) == 1, idiom_uses
path, line = idiom_uses[0]
assert path == ROOT / "Latch/UsageInsightsView.swift", path
assert "? .iPad : .iPhone" in line, line
insights = sources[ROOT / "Latch/UsageInsightsView.swift"]
assert "let devices: DeviceActivityFilter.Devices" in insights
assert "This is data, not\n        // layout" in insights

# 3. The DEBUG appearance toggle no longer moves by device.
app = sources[ROOT / "Latch/LatchApp.swift"]
assert ".overlay(alignment: .top) {" in app
assert "? .bottomLeading : .top" not in app

# 4. Readable width on the sheets F6 found uncapped (shared helper only).
assert "static let maxContentWidth: CGFloat = 640" in sources[ROOT / "Latch/Theme.swift"]
summary = sources[ROOT / "Latch/RuleSummarySheet.swift"]
apps = summary[summary.index("case .apps:"):summary.index("case .groupWake")]
assert ".frame(maxWidth: DemoraSpace.maxContentWidth, alignment: .leading)" in apps
assert ".frame(maxWidth: .infinity)" in apps
onboarding = sources[ROOT / "Latch/OnboardingView.swift"]
for step in ("dayNightStep", "overridesStep"):
    block = onboarding[onboarding.index(f"                            {step}\n"):]
    block = block[:block.index(".paper()")]
    assert ".frame(maxWidth: DemoraSpace.maxContentWidth)" in block, step
estimate = insights[insights.index("private var estimateEditor"):]
estimate = estimate[:estimate.index(".casedNavigationTitle")]
assert ".frame(maxWidth: DemoraSpace.maxContentWidth)" in estimate

# 5. The tab bar keeps its centred cap and full-width paper.
tab = app[app.index("private struct DemoraTabBar"):]
assert ".frame(maxWidth: 700)\n        .frame(maxWidth: .infinity)" in tab
assert ".background(Ink.paper.ignoresSafeArea(edges: .bottom))" in tab

# 6. The square cropper refits after a resize (fold, rotation, Split View);
# croppedImage() maps through the current insets, so they must follow.
contacts = sources[ROOT / "Latch/ContactsOverrideViews.swift"]
assert "private var configuredSize: CGSize?" in contacts
assert "guard scrollView.bounds.size != configuredSize else { return }" in contacts
assert "private var configured = false" not in contacts

# 7. iPhone stays portrait-only in the plist; iPad keeps every orientation and
# multitasking (no UIRequiresFullScreen).
project = (ROOT / "Latch.xcodeproj/project.pbxproj").read_text()
assert project.count("INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = UIInterfaceOrientationPortrait;") == 2
assert "UIRequiresFullScreen" not in project
for plist in ROOT.glob("Latch*/Info.plist"):
    assert "UIRequiresFullScreen" not in plist.read_text(), plist
assert "IPHONEOS_DEPLOYMENT_TARGET = 16.0;" in project
assert not re.search(r"IPHONEOS_DEPLOYMENT_TARGET = (?!16\.0;)", project)

print("ResizableLayoutHarness: all checks passed")
