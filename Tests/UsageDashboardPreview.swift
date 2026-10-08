// Native SwiftUI layout fixtures, macOS-only; not included in any app target.
// Compile with the actual report view/model/presentation/localization files.
import AppKit
import SwiftUI

enum AppGroup { static let id = "demora.dashboard.preview." + UUID().uuidString }

@main
struct UsageDashboardPreview {
    @MainActor static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 6 || arguments.count == 7 else { fatalError("output width height appearance language [day/week/empty/partial/large]") }
        let mode = arguments.count == 7 ? arguments[6] : "day"
        let output = arguments[1]
        let width = Double(arguments[2])!
        let height = Double(arguments[3])!
        let defaults = UserDefaults(suiteName: AppGroup.id)!
        defer { defaults.removePersistentDomain(forName: AppGroup.id) }
        defaults.set(arguments[4], forKey: "latch.appearance")
        defaults.set(arguments[5], forKey: "latch.language")
        if arguments[4] == "dark" { defaults.set("red", forKey: "latch.accentColor") }
        _ = NSApplication.shared
        NSApplication.shared.setActivationPolicy(.prohibited)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Mexico_City")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 12))!
        let today = calendar.startOfDay(for: now)
        var accumulator = UsageInsightsAccumulator(now: now, calendar: calendar)
        for index in -28...0 {
            if mode == "empty" || (mode == "partial" && index < -3) { continue }
            let start = calendar.date(byAdding: .day, value: index, to: today)!
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
            let minutes = index == 0 ? 167 : (index < -7 ? 230 : [184, 193, 143, 210, 222, 177, 160][abs(index) % 7])
            accumulator.add(source: 0, start: start, end: end, seconds: Double(minutes * 60), updatedAt: now)
        }
        let configuration = accumulator.configuration(baseline: nil)
        let root = UsageInsightsView(configuration: configuration, initiallyWeekly: mode == "week")
            .dynamicTypeSize(mode == "large" ? .accessibility3 : .large)
            .frame(width: width, height: height)
        let hosting = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        hosting.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { fatalError("No bitmap") }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("No PNG") }
        try data.write(to: URL(fileURLWithPath: output))
    }
}
