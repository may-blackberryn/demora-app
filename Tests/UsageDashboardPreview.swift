// Native SwiftUI layout fixtures, macOS-only; not included in any app target.
// Compile with the actual report view/model/presentation/localization files.
import AppKit
import SwiftUI

enum AppGroup { static let id = "demora.dashboard.preview." + UUID().uuidString }

@main
struct UsageDashboardPreview {
    @MainActor static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 6 || arguments.count == 7 else { fatalError("output width height appearance language [day/week/app/appweek/missingapp/empty/partial/large/trends/apptrends/trendpartial/trendempty/trendlarge/trendbaseline/noestimate/onlytoday/redaccent]") }
        let mode = arguments.count == 7 ? arguments[6] : "day"
        let output = arguments[1]
        let width = Double(arguments[2])!
        let height = Double(arguments[3])!
        let defaults = UserDefaults(suiteName: AppGroup.id)!
        defer { defaults.removePersistentDomain(forName: AppGroup.id) }
        defaults.set(arguments[4], forKey: "latch.appearance")
        defaults.set(arguments[5], forKey: "latch.language")
        if arguments[4] == "dark" || mode == "redaccent" { defaults.set("red", forKey: "latch.accentColor") }
        _ = NSApplication.shared
        NSApplication.shared.setActivationPolicy(.prohibited)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Mexico_City")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 12))!
        let today = calendar.startOfDay(for: now)
        var accumulator = UsageInsightsAccumulator(now: now, calendar: calendar)
        var appAccumulator = ApplicationUsageAccumulator(now: now, calendar: calendar)
        for index in -28...0 {
            if mode == "empty" || mode == "trendempty" || ((mode == "partial" || mode == "trendpartial") && index < -3)
                || (mode == "onlytoday" && index < 0) { continue }
            let start = calendar.date(byAdding: .day, value: index, to: today)!
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
            let minutes = index == 0 ? 167 : (index < -7 ? 230 : [184, 193, 143, 210, 222, 177, 160][abs(index) % 7])
            accumulator.add(source: 0, start: start, end: end, seconds: Double(minutes * 60), updatedAt: now)
            appAccumulator.add(source: 0, start: start, end: end, updatedAt: now,
                applications: [0: Double((index == 0 ? 20 : 20 + abs(index) % 15) * 60),
                               1: Double((index == 0 ? 48 : 25 + abs(index) % 30) * 60),
                               2: Double((index == 0 ? 35 : 15 + abs(index) % 10) * 60),
                               3: 840, 4: 600, 5: 180, 6: 60])
        }
        let baseline = mode == "trendbaseline" ? UsageInsightsBaseline(weeklyMinutes: 1800, recordedAt: calendar.date(byAdding: .day, value: -30, to: now)!) : nil
        var configuration = accumulator.configuration(baseline: baseline)
        configuration.applications = appAccumulator.applications()
        if mode == "missingapp" { configuration.applications.removeAll { $0.id == 0 } }
        let names = ["Instagram", "YouTube", "Spotify", "Safari", "Messages", "Books", "Maps"]
        // Synthetic fixtures for the three segments (§8): Day, Week, Trends,
        // an app scope, no estimate (trends/noestimate) and partial data.
        let segment: UsageInsightsSegment = ["week", "appweek", "onlytoday"].contains(mode) ? .week
            : ["trends", "apptrends", "trendpartial", "trendempty", "trendlarge", "trendbaseline", "noestimate"].contains(mode) ? .trends : .day
        let root = UsageInsightsView(configuration: configuration, initialSegment: segment,
            initiallySelectedApplication: mode == "app" || mode == "appweek" || mode == "missingapp" || mode == "apptrends" ? 0 : nil,
            applicationLabel: { id in
                AnyView(HStack(spacing: 10) {
                    Image(systemName: ["camera", "play.rectangle", "music.note", "safari", "message", "book", "map"][id])
                        .frame(width: 28, height: 28).background(Color.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
                    Text(names[id])
                })
            })
            .dynamicTypeSize(mode == "large" || mode == "trendlarge" ? .accessibility3 : .large)
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
