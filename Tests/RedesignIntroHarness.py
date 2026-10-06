#!/usr/bin/env python3
"""Test real intro gates/timing and intrinsic reveal layout on macOS.

No app, App Group, permission prompt, or live rule store is opened.
Native font/layout checks use macOS SwiftUI/AppKit, not an iOS screenshot.
Run: python3 Tests/RedesignIntroHarness.py
"""
from pathlib import Path
import subprocess
import tempfile
import itertools
import hashlib

ROOT = Path(__file__).resolve().parents[1]
intro = (ROOT / "Latch/RedesignIntroView.swift").read_text()
root = (ROOT / "Latch/LatchApp.swift").read_text()
demos = (ROOT / "Latch/DeveloperDemosView.swift").read_text()
store = (ROOT / "Shared/SharedStore.swift").read_text()

pure_types = intro[intro.index("enum RedesignIntroGate"):
                   intro.index("/// The same short opening")]
checks = []
for unavailable, tutorial, welcome, seen in itertools.product([False, True], repeat=4):
    values = [str(v).lower() for v in (unavailable, tutorial, welcome, seen)]
    expected = str(not any((unavailable, tutorial, welcome, seen))).lower()
    checks.append("precondition(RedesignIntroGate.shouldShow(storageUnavailable: "
                  + values[0] + ", tutorialActive: " + values[1]
                  + ", welcomeSeen: " + values[2] + ", introSeen: " + values[3]
                  + ") == " + expected + ")")
program = "import Foundation\n" + pure_types + "\n" + "\n".join(checks) + """
precondition(RedesignIntroPhase.allCases == [.logo, .wordmark, .version, .tagline])
precondition(RedesignIntroPhase.allCases.reduce(UInt64(0)) { $0 + $1.holdNanoseconds }
             == 4_100_000_000)
for phase in RedesignIntroPhase.allCases {
    precondition(phase.holdNanoseconds > 0)
    if phase != .tagline {
        precondition(RedesignIntroPhase(rawValue: phase.rawValue + 1) != nil)
    }
}
// Completing only the intro must not complete either setup or the welcome.
precondition(!RedesignIntroGate.shouldShow(storageUnavailable: false,
    tutorialActive: false, welcomeSeen: false, introSeen: true))
print("Intro gate and ordered timing: all 16 combinations passed")
"""
with tempfile.TemporaryDirectory(prefix="demora-intro-tests-") as temporary:
    source = Path(temporary) / "main.swift"
    binary = Path(temporary) / "test"
    source.write_text(program)
    subprocess.run(["swiftc", str(source), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)

# The real root prioritizes recovery, then intro, then migration, then app/setup.
body = root[root.index("    var body: some View {", root.index("struct RootView")):
            root.index("    private func requestUpdateReviewIfNeeded")]
assert body.index("if model.setupStorageUnavailable") < body.index("RedesignIntroGate.shouldShow")
assert body.index("RedesignIntroView") < body.index("RedesignWelcomeView") < body.index("OnboardingView()")
assert "RedesignIntroView { redesignIntroSeen = true }" in body
assert "static let redesignIntroKey" in store
assert "@AppStorage(SharedStore.redesignIntroKey, store: SharedStore.defaults)" in root
assert "showRedesignWelcome" not in root  # no underlying Home flash/presentation race

# Cancellation/backgrounding never consumes the marker; skip/finish is idempotent.
assert ".task(id: scenePhase)" in intro
assert "try Task.checkCancellation()" in intro
assert "guard scenePhase == .active, !completed else { return }" in intro
assert "guard !completed else { return }\n        completed = true\n        onComplete()" in intro
assert "UIAccessibility.isVoiceOverRunning" in intro and "accessibilityReduceMotion" in intro
assert "ScrollView(showsIndicators: false)" in intro
assert "min(52.0" in intro and "max(28.0" in intro
assert '.font(.system(.subheadline, design: .serif))' in intro
heading = intro[intro.index("    private func heading("):intro.index("    private var accessibilityTitle")]
assert "HStack(alignment: .firstTextBaseline" in heading
assert 'wordmark(fontSize: fontSize, reveals: reveals)' in heading
assert 'Text("2.0")' in heading and intro.count('Text("2.0")') == 1
assert "fontSize * 0.65" in heading
wordmark = intro[intro.index("    private func wordmark("):intro.index("    private func heading(")]
assert 'IntroWordmarkReveal(progress: reveals ? 1 : 0)' in wordmark
assert 'Text("emora")' in wordmark and '.fixedSize()' in wordmark
assert '.padding(.trailing, 2)' in wordmark
assert 'fontSize * 2.6' not in wordmark and '.frame(width:' not in wordmark
assert '.alignmentGuide(.bottom) { $0[.lastTextBaseline] }' in wordmark
assert '.clipped()' in wordmark
assert 'heading(fontSize: fontSize, reveals: true)' in intro  # Reduce Motion: full width throughout
layout = intro[intro.index("private struct IntroWordmarkReveal:"):]
assert 'var animatableData: CGFloat' in layout
assert layout.count('text.sizeThatFits(.unspecified)') == 2
assert 'proposal: ProposedViewSize(width: size.width, height: size.height)' in layout

# Compile the actual Layout, then compare its fitting size to native intrinsic
# Text at every supported font size and multiple animation fractions. No window
# is created. CoreText ink bounds independently reproduce the old trailing clip.
layout_program = "import SwiftUI\nimport AppKit\nimport CoreText\n" + layout + r'''
func label(_ size: CGFloat) -> some View {
    Text("emora")
        .font(.system(size: size, weight: .regular, design: .serif))
        .tracking(-1)
        .fixedSize()
        .padding(.trailing, 2)
}
var clippedSizes = 0
for integerSize in 28...52 {
    let size = CGFloat(integerSize)
    let intrinsic = NSHostingView(rootView: label(size)).fittingSize
    precondition(intrinsic.width > 0 && intrinsic.height > 0)
    let reference = NSHostingView(rootView: HStack(alignment: .bottom, spacing: 2) {
        Color.clear.frame(width: size * 0.56, height: size * 0.82)
        label(size).alignmentGuide(.bottom) { $0[.lastTextBaseline] }
    }).fittingSize
    let wordmark = NSHostingView(rootView: HStack(alignment: .bottom, spacing: 2) {
        Color.clear.frame(width: size * 0.56, height: size * 0.82)
        IntroWordmarkReveal(progress: 1) { label(size) }
            .alignmentGuide(.bottom) { $0[.lastTextBaseline] }
            .clipped()
    }).fittingSize
    precondition(wordmark == reference, "Reveal layout must preserve wordmark baseline geometry")
    for progress: CGFloat in [-0.1, 0, 0.25, 0.5, 0.75, 1, 1.1] {
        let revealed = NSHostingView(rootView:
            IntroWordmarkReveal(progress: progress) { label(size) }).fittingSize
        let fraction = min(1, max(0, progress))
        // NSHostingView rounds its fitting size to whole points.
        precondition(abs(revealed.width - intrinsic.width * fraction) < 1.01,
                     "Reveal must use intrinsic width at \(size), \(progress): \(revealed.width) vs \(intrinsic.width * fraction)")
        precondition(abs(revealed.height - intrinsic.height) < 0.01)
        if fraction == 0 || fraction == 1 {
            precondition(revealed.width == intrinsic.width * fraction)
        }
    }
    let descriptor = NSFont.systemFont(ofSize: size).fontDescriptor.withDesign(.serif)!
    let font = NSFont(descriptor: descriptor, size: size)!
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: "emora",
        attributes: [.font: font, .kern: -1]))
    let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    precondition(ink.maxX <= intrinsic.width + 0.5,
                 "Full reveal must contain the trailing glyph at \(size): ink \(ink.maxX), intrinsic \(intrinsic.width), font \(font.fontName)")
    if ink.maxX > size * 2.6 { clippedSizes += 1 }
    if integerSize == 52 {
        print("52pt emora: intrinsic \(intrinsic.width), ink right \(ink.maxX), old clip \(size * 2.6)")
    }
}
precondition(clippedSizes > 0, "Font checks must reproduce the old clipping")
for width: CGFloat in [200, 240, 320, 375, 430, 768, 1024] {
    let size = min(52, max(28, (width - 48) / 4.3))
    let textWidth = NSHostingView(rootView: label(size)).fittingSize.width
    let versionWidth = NSHostingView(rootView: Text("2.0")
        .font(.system(size: size * 0.65, weight: .light, design: .serif))
        .fixedSize()).fittingSize.width
    precondition(versionWidth <= size * 1.1, "Version must fit its existing slot")
    let headingWidth = size * 0.56 + 2 + textWidth + size * 1.1
    precondition(headingWidth <= width, "Compact heading must fit at \(width)pt")
}
print("Intrinsic reveal: 25 font sizes × 7 fractions; glyph bounds and 7 compact widths passed")
'''
with tempfile.TemporaryDirectory(prefix="demora-intro-layout-") as temporary:
    source = Path(temporary) / "main.swift"
    binary = Path(temporary) / "test"
    source.write_text(layout_program)
    subprocess.run(["swiftc", str(source), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)

for forbidden in ("SharedStore.", "ChangeEngine.", "requestAuthorization", "ContactsRelay."):
    assert forbidden not in intro, forbidden
assert demos.count("RedesignIntroView(") == 2
assert demos.count("onComplete: { introPlayed = true }, isDemo: true") == 2
assert "finished = false; introPlayed = false" in demos
assert "introPlayed = false; showWelcome = true" in demos

for filename in ("Localization.swift", "Localization+German.swift", "Localization+French.swift",
                 "Localization+Portuguese.swift", "Localization+Polish.swift",
                 "Localization+Turkish.swift", "Localization+Hindi.swift"):
    assert (ROOT / "Shared" / filename).read_text().count('"more powerful, more intuitive":') == 1
asset = ROOT / "Latch/Assets.xcassets/DemoraLogo.imageset/demora-logo.png"
assert hashlib.sha256(asset.read_bytes()).hexdigest() == "1ec4ea7fb72d10ea93cf1693531fd0c16c046b63b29a75a3a2888aabf684e6b3"
print("Root routing, cancellation, accessibility, demo isolation, translations and original asset checks passed (source-level)")
