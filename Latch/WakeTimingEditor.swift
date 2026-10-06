import SwiftUI

/// Shared by named day/night groups, legacy limits and both setup paths.
struct WakeTimingEditor: View {
    @Binding var startMinutes: Int
    @Binding var waitMinutes: Int
    @Binding var weekdays: Set<Int>
    @Binding var dayTimings: [Int: WakeDayTiming]
    var showsWeekdays = true
    var showsWait = true

    private var weekdayNames: [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = AppLanguage.current.locale
        return calendar.weekdaySymbols
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            WakeClockPicker(minutes: $startMinutes)
            if showsWait {
                Text(tr("Wait after tapping Wake up")).font(.subheadline.weight(.semibold))
                DurationPicker(minutes: $waitMinutes, maxHours: 24, minMinutes: 0)
            }
            if showsWeekdays {
                Text(tr("Weekdays")).font(.headline)
                ForEach(1...7, id: \.self) { day in
                    Toggle(weekdayNames[day - 1], isOn: Binding(
                        get: { weekdays.contains(day) },
                        set: { if $0 { weekdays.insert(day) } else { weekdays.remove(day) } }))
                }
            }
            DisclosureGroup(tr("Customize wake-up by day")) {
                VStack(alignment: .leading, spacing: 18) {
                    Text(tr("Days without custom times use the default start and wait above."))
                        .font(.footnote).foregroundStyle(Ink.faint)
                    ForEach(weekdays.sorted(), id: \.self) { day in
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle(weekdayNames[day - 1], isOn: Binding(
                                get: { dayTimings[day] != nil },
                                set: { customized in
                                    if customized { dayTimings[day] = WakeDayTiming(startMinutes: startMinutes, waitMinutes: waitMinutes) }
                                    else { dayTimings.removeValue(forKey: day) }
                                }))
                            if dayTimings[day] != nil {
                                WakeClockPicker(minutes: timing(day, \.startMinutes))
                                if showsWait {
                                    Text(tr("Wait after tapping Wake up")).font(.subheadline)
                                    DurationPicker(minutes: timing(day, \.waitMinutes), maxHours: 24, minMinutes: 0)
                                }
                            }
                        }
                        Divider()
                    }
                }.padding(.top, 12)
            }
            Text(tr("A wake-up wait already in progress keeps its original deadline."))
                .font(.footnote).foregroundStyle(Ink.faint)
        }
    }

    private func timing(_ day: Int, _ keyPath: WritableKeyPath<WakeDayTiming, Int>) -> Binding<Int> {
        Binding(get: {
            (dayTimings[day] ?? WakeDayTiming(startMinutes: startMinutes, waitMinutes: waitMinutes))[keyPath: keyPath]
        }, set: { value in
            var timing = dayTimings[day] ?? WakeDayTiming(startMinutes: startMinutes, waitMinutes: waitMinutes)
            timing[keyPath: keyPath] = value
            dayTimings[day] = timing
        })
    }
}

private struct WakeClockPicker: View {
    @Binding var minutes: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("Wake-up day begins")).font(.headline)
            HStack {
                Picker(tr("Hour"), selection: Binding(get: { minutes / 60 }, set: {
                    minutes = $0 * 60 + min(minutes % 60, $0 == 23 ? 30 : 59)
                })) {
                    ForEach(0..<24, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                }
                Text(":")
                Picker(tr("Minute"), selection: Binding(get: { minutes % 60 }, set: {
                    minutes = minutes / 60 * 60 + $0
                })) {
                    ForEach(0...(minutes / 60 == 23 ? 30 : 59), id: \.self) {
                        Text(String(format: "%02d", $0)).tag($0)
                    }
                }
            }.pickerStyle(.menu)
        }
    }
}
