#!/usr/bin/env python3
"""F6 (iPhone Duo / resizable windows): a SOURCE GUARD, not a UI test.

This reads Swift text only. It does not compile, render or run anything and
does not prove the layout on a device or simulator.
It pins the rules from Apple's foldable guidance that the code can show:
layouts never branch on the device idiom, screen or orientation; the one
idiom read left is the Screen Time data filter; sheets touched by F6 keep the
shared readable width; the photo cropper refits when its window resizes.
"""
from pathlib import Path
import plistlib
import re

ROOT = Path(__file__).resolve().parents[1]
TARGETS = ("Latch", "LatchReport", "LatchWidgets", "LatchShieldUI", "LatchMonitor", "Shared")
sources = {p: p.read_text() for t in TARGETS for p in (ROOT / t).rglob("*.swift")}
assert len(sources) > 50, len(sources)


BLOCK_COMMENT = re.compile(r"/\*.*?\*/", re.S)
MULTILINE_STRING = re.compile(r'""".*?"""', re.S)
STRING = re.compile(r'"(?:\\.|[^"\\\n])*"')


def code_lines(text):
    """Code with comments and string contents removed, line by line.

    Strings go before `//` is cut, so a "https://" inside a string neither
    hides the code after it nor counts as code. Block comments and multi-line
    strings keep their newlines so line counts stay close.
    """
    blank = lambda m: "\n" * m.group(0).count("\n")
    text = BLOCK_COMMENT.sub(blank, text)
    text = MULTILINE_STRING.sub(lambda m: '""' + blank(m), text)
    for line in text.splitlines():
        line = STRING.sub('""', line)
        yield line.split("//")[0]


# 0. The comment/string stripper itself.
assert list(code_lines('let u = "https://x" ; UIScreen.main')) == ['let u = "" ; UIScreen.main']
assert list(code_lines('a /* UIScreen.main */ b')) == ['a  b']
assert list(code_lines('x // UIScreen.main')) == ['x ']
assert list(code_lines('t("a \\"q\\" // b") + c')) == ['t("") + c']
assert list(code_lines('/* one\nUIScreen\n*/ y')) == ['', '', ' y']


# 1. No screen-, window- or orientation-based layout anywhere. Size-class
# reads are banned too: today one layout fits every width (a centred 640 pt
# column), so a new size-class branch must update this guard on purpose.
forbidden = re.compile(
    r"UIScreen\b|\.mainScreen\b|UIDevice\.current\.orientation|interfaceOrientation"
    r"|\bwindow\??\.screen\b|windowScene\??\.screen\b|\.screen\.(bounds|nativeBounds|scale)\b"
    r"|UIApplication\.shared\.windows|connectedScenes|keyWindow|isKeyWindow"
    r"|horizontalSizeClass|verticalSizeClass|UITraitCollection\.current")
for bad in ("UIScreen.main.bounds", "view.window?.screen", "self.window.screen",
            "UIApplication.shared.connectedScenes", "scene.keyWindow",
            "@Environment(\\.horizontalSizeClass) var h", "traitCollection.verticalSizeClass"):
    assert forbidden.search(bad), bad
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
header = insights[insights.index("private var header: some View"):]
header = header[:header.index("private func headerButton")]
assert ".frame(maxWidth: DemoraSpace.maxContentWidth, alignment: .leading)\n        .frame(maxWidth: .infinity)" in header
editors = sources[ROOT / "Latch/RuleEditors.swift"]
help_sheet = editors[editors.index("let paragraphs: [String]"):]
help_sheet = help_sheet[:help_sheet.index(".presentationDetents")]
assert ".frame(maxWidth: DemoraSpace.maxContentWidth, alignment: .leading)" in help_sheet

# 5. The tab bar keeps its centred 700 pt items; the paper and its top
# hairline run edge to edge (the overlay comes after the full-width frame).
tab = app[app.index("private struct DemoraTabBar"):]
tab = tab[:tab.index("private func dotDescription")]
cap = tab.index(".frame(maxWidth: 700)\n        .frame(maxWidth: .infinity)")
line = tab.index("Rectangle().fill(Ink.hairline).frame(height: 1)")
paper = tab.index(".background(Ink.paper.ignoresSafeArea(edges: .bottom))")
assert cap < line < paper, (cap, line, paper)
assert tab.count(".overlay(alignment: .top)") == 1
# Duo outer display (F6 simulator pass): at accessibility sizes the labels
# broke mid-word and the bar took a third of the screen. The bar's text size
# is capped and each item offers the large content viewer instead, like the
# system tab bar. Its hairline, and the Insights header line, also reach under
# a side safe area (the outer display's status column).
assert ".dynamicTypeSize(...DynamicTypeSize.xLarge)" in tab
assert ".accessibilityShowsLargeContentViewer {" in tab
assert "Label(tr(item.1), systemImage: item.2)" in tab
assert "Rectangle().fill(Ink.hairline).frame(height: 1)\n                .ignoresSafeArea(edges: .horizontal)" in tab
body = insights[insights.index("    var body: some View {"):]
body = body[:body.index("DeviceActivityReport(")]
assert "Rectangle().fill(Ink.hairline).frame(height: 1)\n                    .ignoresSafeArea(edges: .horizontal)" in body

# 6. The square cropper: sized from the safe area above its buttons, no
# automatic insets, refits whenever the square changes (fold, rotation, Split
# View, safe area), and croppedImage() maps through that same square.
contacts = sources[ROOT / "Latch/ContactsOverrideViews.swift"]
crop = contacts[contacts.index("final class SquareCropViewController"):]
crop = crop[:crop.index("extension UIImage")]
assert "scrollView.contentInsetAdjustmentBehavior = .never" in crop
assert "let safe = view.safeAreaLayoutGuide.layoutFrame" in crop
assert "safe.height - buttonBand" in crop
assert "guard square != cropRect else { return }" in crop
assert "refit(to: square)" in crop
assert "focus = CGPoint(x: (oldOffset.x + old.midX) / oldZoom" in crop
assert "guard let square = cropRect" in crop
assert "(offset.x + square.minX) / zoom" in crop
assert "min(scrollView.bounds.width, scrollView.bounds.height)" not in crop
assert "configured" not in crop

# 7. iPhone stays portrait-only in the plist; iPad keeps every orientation and
# multitasking (no UIRequiresFullScreen).
project = (ROOT / "Latch.xcodeproj/project.pbxproj").read_text()
assert project.count("INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = UIInterfaceOrientationPortrait;") == 2
assert "UIRequiresFullScreen" not in project
for plist in ROOT.glob("Latch*/Info.plist"):
    assert "UIRequiresFullScreen" not in plist.read_text(), plist
assert "IPHONEOS_DEPLOYMENT_TARGET = 16.0;" in project
# One window per app: two Demora windows would share one AppModel (selected
# tab, navigation paths, polling). Split View beside other apps still works.
# Xcode's generated scene manifest always says YES (the build setting
# INFOPLIST_KEY_UIApplicationSupportsMultipleScenes is ignored, checked in the
# built Info.plist with Xcode 27.2), so the host turns generation off and
# Latch/Info.plist carries the whole manifest.
assert "INFOPLIST_KEY_UIApplicationSupportsMultipleScenes" not in project
for config in ("Debug", "Release"):
    host = project[project.index("CODE_SIGN_ENTITLEMENTS = Latch/Latch" + ("Debug" if config == "Debug" else "") + ".entitlements;"):]
    host = host[:host.index("name = " + config + ";")]
    assert "INFOPLIST_KEY_UIApplicationSceneManifest_Generation = NO;" in host, config
    assert "INFOPLIST_FILE = Latch/Info.plist;" in host, config
assert "INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES" not in project
host_plist = plistlib.loads((ROOT / "Latch/Info.plist").read_bytes())
assert host_plist["UIApplicationSceneManifest"] == {
    "UIApplicationSupportsMultipleScenes": False, "UISceneConfigurations": {}}, host_plist.get("UIApplicationSceneManifest")
assert not re.search(r"IPHONEOS_DEPLOYMENT_TARGET = (?!16\.0;)", project)

print("ResizableLayoutHarness: all checks passed")
