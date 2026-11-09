#!/usr/bin/env python3
"""Render actual setup-card views with synthetic drafts on macOS, not iOS.

Usage: python3 Tests/RenderSetupPreview.py /tmp/setup.png [en|de|hi] [light|dark] [width]
No app model, saved preferences, permissions, real tokens or contact services.
"""
from pathlib import Path
import json
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def block(source, signature):
    start = source.index(signature)
    opening = source.index('{', start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


onboarding = (ROOT / 'Latch/OnboardingView.swift').read_text()
theme = (ROOT / 'Latch/Theme.swift').read_text()
components = (ROOT / 'Latch/DemoraComponents.swift').read_text()
summary = (ROOT / 'Latch/RuleSummarySheet.swift').read_text()
body = block(onboarding, 'private var makeYoursStep: some View').replace(
    'private var makeYoursStep:', 'var body:')
types = '\n'.join(block(theme, signature) for signature in
                  ['struct InkPair', 'enum InkPalette', 'enum DemoraSpace', 'enum DemoraRadius', 'enum DemoraType'])
# The modifiers belong on View; every other extracted declaration is complete.
types += '\nextension View {\n' + block(theme, 'func demoraType(') + '\n}'
types += '\nextension View {\n' + block(components, 'func paperCard(') + '\n}'
types += '\n' + block(components, 'struct SectionHeader<Trailing: View>')
types += '\n' + block(components, 'extension SectionHeader where Trailing == EmptyView')
for signature in ['struct DemoraWelcomeProgress:', 'struct DemoraWelcomeEntry:',
                  'struct SetupOptionalCard:', 'struct SetupEstimateDisclosure:']:
    types += '\n' + block(onboarding, signature)
types += '\n' + block(summary, 'struct FactRow:')
stub = r'''
import AppKit
import SwiftUI
enum Preview {
    static let dark = CommandLine.arguments[3] == "dark"
    static let language = CommandLine.arguments[2]
}
enum Ink {
    static func color(_ pair: InkPair) -> Color {
        let rgb = Preview.dark ? pair.dark : pair.light
        return Color(red: Double((rgb >> 16) & 255) / 255,
                     green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255)
    }
    static var paper: Color { color(InkPalette.paper) }
    static var card: Color { color(InkPalette.card) }
    static var ink: Color { color(InkPalette.ink) }
    static var inkSoft: Color { color(InkPalette.inkSoft) }
    static var hairline: Color { color(InkPalette.hairline) }
    static var danger: Color { color(InkPalette.loosen) }
}
@propertyWrapper struct AppAccent: DynamicProperty {
    var wrappedValue: Color { Ink.color(Preview.dark ? InkPalette.accentRed : InkPalette.accentBlue) }
}
// Closed by default; the expanded estimate's controls aren't under visual test.
struct WeeklyUsageEstimateDraft: View {
    @Binding var enabled: Bool
    @Binding var minutes: Int
    var body: some View { Text("Synthetic estimate draft") }
}
struct SampleGroup { let name: String }
struct SampleLimit { let name: String; let minutesPerDay: Int }
struct SampleOverrides { let contacts = [1]; let phrasePolicies = [1]; let passwordPolicies: [Int] = [] }
struct SetupFixture: View {
    @State private var showDayNight = false
    @State private var showOverrides = false
    @State private var wantsUsageEstimate = false
    @State private var usageEstimateMinutes = 1260
    private let dayNightGroups = [SampleGroup(name: "Morning focus")]
    private let dayNightValid = true
    private let accessGranted = true
    private let overrides = SampleOverrides()
    private let firstLimit: SampleLimit? = SampleLimit(name: "Social", minutesPerDay: 30)
    private let policySummary = "5 min · 1 day"
'''
stub += block(onboarding, 'private var overridesSummary:') + '\n'
suffix = {'de': '+German', 'hi': '+Hindi'}.get(sys.argv[2] if len(sys.argv) > 2 else 'en')
keys = set(re.findall(r'\btr\("((?:[^"\\]|\\.)*)"\)', body + types + stub))
table = {}
if suffix:
    source = (ROOT / f'Shared/Localization{suffix}.swift').read_text()
    string = r'"((?:[^"\\]|\\.)*)"'
    for key, value in re.findall(string + r'\s*:\s*' + string, source):
        if key in keys:
            table[json.loads('"' + key + '"')] = json.loads('"' + value + '"')
translations = 'let previewStrings: [String: String] = [\n' + ',\n'.join(
    json.dumps(key, ensure_ascii=False) + ': ' + json.dumps(value, ensure_ascii=False)
    for key, value in table.items()) + ('\n]' if table else ':\n]')
program = stub + body + '\n}\n' + types + '\n' + translations + r'''
func tr(_ key: String) -> String { previewStrings[key] ?? key }
let width = Double(CommandLine.arguments[4])!
let height = 1500.0
let root = VStack(alignment: .leading, spacing: 24) {
    DemoraWelcomeProgress(step: 4, total: 5)
    SetupFixture()
}.padding(20).frame(width: width).frame(maxHeight: .infinity, alignment: .topLeading).background(Ink.paper)
 .environment(\.colorScheme, Preview.dark ? .dark : .light)
 .environment(\.locale, Locale(identifier: Preview.language))
_ = NSApplication.shared
NSApplication.shared.setActivationPolicy(.prohibited)
let hosting = NSHostingView(rootView: root)
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                      styleMask: [.borderless], backing: .buffered, defer: false)
window.contentView = hosting
hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
hosting.layoutSubtreeIfNeeded()
window.displayIfNeeded()
guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { fatalError("No bitmap") }
hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
'''
with tempfile.TemporaryDirectory(prefix='demora-setup-preview-') as directory:
    folder = Path(directory)
    (folder / 'main.swift').write_text(program)
    binary = folder / 'preview'
    subprocess.run(['swiftc', str(folder / 'main.swift'), '-o', str(binary)], check=True)
    subprocess.run([str(binary), sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else 'en',
                    sys.argv[3] if len(sys.argv) > 3 else 'light',
                    sys.argv[4] if len(sys.argv) > 4 else '390'], check=True)
