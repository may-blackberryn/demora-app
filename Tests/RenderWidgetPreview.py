#!/usr/bin/env python3
"""Synthetic native macOS renders of actual widget views, not WidgetKit/iOS QA.

Usage: python3 Tests/RenderWidgetPreview.py /absolute/output.png [en|de|hi] [light|dark]
The provider is excluded; preference reads become fixed fixture choices. UIKit
trait resolution, system redaction/margins/tint and real timelines are not tested.
"""
from pathlib import Path
import json
import subprocess
import sys
import tempfile
sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[1]


def block(source, signature):
    start = source.index(signature)
    opening = source.index('{', start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


theme = (ROOT / 'LatchWidgets/WidgetTheme.swift').read_text().replace('import UIKit', 'import AppKit')
theme = theme.replace(block(theme, 'static func accentValue()'),
                      'static func accentValue() -> String { Preview.dark ? "red" : "blue" }')
theme = theme.replace(block(theme, 'static func color(_ pair:'), '''
static func color(_ pair: WidgetInkPair) -> Color {
    let rgb = Preview.dark ? pair.dark : pair.light
    return Color(red: Double((rgb >> 16) & 255) / 255,
                 green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255)
}''')
views = (ROOT / 'LatchWidgets/DemoraWidgets.swift').read_text().split('private struct NowNextWidget:', 1)[0]
views = views.replace(block(views, 'private struct DemoraProvider:'), '')
views = views.replace('#available(iOS 17.0, *)', '#available(macOS 14.0, *)')
# Accessory families are unavailable on macOS. Inject a fixture-only family
# environment with the same cases; production view branches are unchanged.
views = views.replace(r'\.widgetFamily', r'\.previewWidgetFamily')
views = views.replace('private struct ', 'struct ')
language = sys.argv[2] if len(sys.argv) > 2 else 'en'
suffix = {'de': '+German', 'hi': '+Hindi'}.get(language)
table = {}
if suffix:
    import GenerateWidgetLocalization as generator
    table = dict(generator.entries((ROOT / f'Shared/Localization{suffix}.swift').read_text()))
keys = ['until %@', 'Next %@ · %@', 'Used up today', 'No timed rule active',
        'Changes you make wait here.', 'Good morning. Tap to wake up.', 'Looser', 'Stricter',
        'Open Demora', 'Now', 'Next', 'Changing soon', 'Nothing coming up', 'No changes waiting']
translations = 'let words: [String: String] = [\n' + ',\n'.join(
    json.dumps(key, ensure_ascii=False) + ': ' + json.dumps(table.get(key, key), ensure_ascii=False)
    for key in keys) + '\n]\nfunc word(_ key: String) -> String { words[key] ?? key }\n'
program = 'import AppKit\nimport SwiftUI\nimport WidgetKit\n' + '''
enum Preview { static let dark = CommandLine.arguments[3] == "dark" }
enum PreviewWidgetFamily { case systemSmall, systemMedium, accessoryInline, accessoryRectangular }
struct PreviewWidgetFamilyKey: EnvironmentKey {
    static let defaultValue = PreviewWidgetFamily.systemSmall
}
extension EnvironmentValues {
    var previewWidgetFamily: PreviewWidgetFamily {
        get { self[PreviewWidgetFamilyKey.self] }
        set { self[PreviewWidgetFamilyKey.self] = newValue }
    }
}
''' + theme + views + translations + r'''
let now = Date()
var snapshot = DemoraWidgetSnapshot(
    windows: [.init(title: "Evening focus", kind: "Schedule", startsAt: now.addingTimeInterval(-600),
        endsAt: now.addingTimeInterval(3600), priority: 100, style: "block")],
    pending: [.init(title: "Games 20 → 30 min", appliesAt: now.addingTimeInterval(11524), direction: "lenient")],
    savedAt: now, nowLabel: word("Now"), nextLabel: word("Next"), pendingLabel: word("Changing soon"),
    noTimedRuleLabel: word("No timed rule active"), noNextLabel: word("Nothing coming up"),
    noPendingLabel: word("No changes waiting"),
    copy: .init(untilFormat: word("until %@"), nextFormat: word("Next %@ · %@"),
        usedUp: word("Used up today"), nothingBlocked: word("No timed rule active"),
        changesWaitHere: word("Changes you make wait here."), wakeDue: word("Good morning. Tap to wake up."),
        looser: word("Looser"), stricter: word("Stricter"), openDemora: word("Open Demora")))
let entry = DemoraEntry(date: now, snapshot: snapshot)
var empty = snapshot
empty.windows = []; empty.pending = []
let emptyEntry = DemoraEntry(date: now, snapshot: empty)
let root = VStack(alignment: .leading, spacing: 20) {
    Text("Synthetic widget layout · " + CommandLine.arguments[2]).font(.caption).foregroundStyle(WidgetInk.inkSoft)
    HStack(spacing: 20) {
        NowNextView(entry: entry).environment(\.previewWidgetFamily, .systemSmall)
            .padding(16).frame(width: 170, height: 170).background(WidgetInk.card, in: RoundedRectangle(cornerRadius: 20))
        PendingView(entry: entry).environment(\.previewWidgetFamily, .systemSmall)
            .padding(16).frame(width: 170, height: 170).background(WidgetInk.card, in: RoundedRectangle(cornerRadius: 20))
    }
    NowNextView(entry: entry).environment(\.previewWidgetFamily, .systemMedium)
        .padding(16).frame(width: 360, height: 170).background(WidgetInk.card, in: RoundedRectangle(cornerRadius: 20))
    HStack(spacing: 20) {
        NowNextView(entry: entry).environment(\.previewWidgetFamily, .accessoryRectangular).frame(width: 170, height: 80)
        PendingView(entry: entry).environment(\.previewWidgetFamily, .accessoryRectangular).frame(width: 170, height: 80)
    }
    NowNextView(entry: entry).environment(\.previewWidgetFamily, .accessoryInline).frame(width: 360, height: 24)
    HStack(spacing: 20) {
        NowNextView(entry: emptyEntry).environment(\.previewWidgetFamily, .systemSmall)
            .padding(16).frame(width: 170, height: 170).background(WidgetInk.card, in: RoundedRectangle(cornerRadius: 20))
        PendingView(entry: emptyEntry).environment(\.previewWidgetFamily, .systemSmall)
            .padding(16).frame(width: 170, height: 170).background(WidgetInk.card, in: RoundedRectangle(cornerRadius: 20))
    }
}.padding(24).frame(width: 408, height: 800, alignment: .topLeading).background(WidgetInk.paper)
 .environment(\.colorScheme, Preview.dark ? .dark : .light)
 .environment(\.locale, Locale(identifier: CommandLine.arguments[2]))
_ = NSApplication.shared
NSApplication.shared.setActivationPolicy(.prohibited)
let hosting = NSHostingView(rootView: root)
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 408, height: 800),
    styleMask: [.borderless], backing: .buffered, defer: false)
window.contentView = hosting
hosting.frame = NSRect(x: 0, y: 0, width: 408, height: 800)
hosting.layoutSubtreeIfNeeded()
window.displayIfNeeded()
guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { fatalError("No bitmap") }
hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
'''
with tempfile.TemporaryDirectory(prefix='demora-widget-preview-') as directory:
    folder = Path(directory)
    (folder / 'main.swift').write_text(program)
    binary = folder / 'preview'
    subprocess.run(['swiftc', '-D', 'WIDGET_EXTENSION', '-target', 'arm64-apple-macosx14.0',
                    str(ROOT / 'Shared/DemoraWidgetSnapshot.swift'), str(folder / 'main.swift'),
                    '-o', str(binary)], check=True)
    subprocess.run([str(binary), sys.argv[1], language,
                    sys.argv[3] if len(sys.argv) > 3 else 'light'], check=True)
