import SwiftUI

struct WakeScheduleView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                DemoraPageTitle(title: tr("Group wake-up"))
                Text(tr("Give each limit or group its own wake-up start, wait and weekdays. One Wake up tap starts all eligible waits. Overlapping rules still apply."))
                    .font(.footnote).foregroundStyle(Ink.faint)
                if model.state.limits.isEmpty {
                    Text(tr("Create a group in Limits & blocks first."))
                        .foregroundStyle(Ink.faint)
                }
                ForEach(model.state.limits) { limit in
                    VStack(alignment: .leading, spacing: 12) {
                        NavigationLink { GroupWakeDelayEditor(limitID: limit.id) } label: {
                            GridCard(symbol: "sun.max", title: limit.name,
                                     subtitle: limit.wakeDelayMinutes.map {
                                         let timing = (limit.wakeSchedule ?? LimitWakeSchedule()).timing(on: Date(), defaultWait: $0)
                                         return String(format: tr("Wake from %@ · wait %d minutes after tap"), minutesLabel(timing.startMinutes), timing.waitMinutes)
                                     } ?? tr("Off"))
                        }
                        if limit.wakeDelayMinutes != nil {
                            TimelineView(.periodic(from: .now, by: 30)) { _ in
                                GroupWakeAction(limit: limit)
                            }
                        }
                    }
                }
            }
            .padding(24).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .paper()
        .casedNavigationTitle(tr("Group wake-up"))
    }
}

private struct GroupWakeAction: View {
    let limit: AppLimit
    @EnvironmentObject private var model: AppModel
    @State private var tapping = false

    var body: some View {
        switch ChangeEngine.wakeState(for: limit) {
        case .needsTap:
            Button {
                tapping = true
                Task { @MainActor in
                    _ = await ChangeEngine.wakeUpAllOffMain()
                    tapping = false
                    model.tick()
                }
            } label: {
                Label(tr("Wake up"), systemImage: "sunrise")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            }
            .disabled(tapping)
        case .waiting(let release):
            HStack {
                Text(tr("Wake-up wait"))
                Spacer()
                let remaining = max(1, release.timeIntervalSince(TimeGuard.now()))
                Text(timerInterval: Date.now...Date.now.addingTimeInterval(remaining), countsDown: true)
                    .monospacedDigit()
            }
            .font(.subheadline).foregroundStyle(Ink.faint)
        case .awake:
            Label(tr("Awake for today"), systemImage: "checkmark")
                .font(.subheadline).foregroundStyle(Ink.faint)
        case .notConfigured:
            EmptyView()
        }
    }
}

private struct GroupWakeDelayEditor: View {
    let limitID: UUID
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var enabled = false
    @State private var minutes = 10
    @State private var schedule = LimitWakeSchedule()
    @State private var loaded = false

    private var limit: AppLimit? { model.state.limits.first { $0.id == limitID } }
    private var action: ChangeAction { .setGroupWakeSchedule(id: limitID, minutes: enabled ? minutes : nil, schedule: schedule) }
    private var isPending: Bool {
        model.state.pending.contains { ChangeEngine.conflictKey($0.action) == ChangeEngine.conflictKey(action) }
    }
    private var changed: Bool {
        limit?.wakeDelayMinutes != (enabled ? minutes : nil)
            || (enabled && (limit?.wakeSchedule ?? LimitWakeSchedule()) != schedule)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                DemoraPageTitle(title: limit?.name ?? tr("Group wake-up"))
                Toggle(tr("Require wake-up tap"), isOn: $enabled)
                if enabled {
                    WakeTimingEditor(startMinutes: $schedule.startMinutes, waitMinutes: $minutes,
                                     weekdays: $schedule.weekdays, dayTimings: $schedule.dayTimings)
                }
                Text(tr("The current day's wake-up countdown stays unchanged. A new wait applies to the next tap. Turning this off still waits through your less-strict delay."))
                    .font(.footnote).foregroundStyle(Ink.faint)
                Text(tr("Usage already spent, split budgets and extra-time grants are not reset by this change."))
                    .font(.footnote).foregroundStyle(Ink.faint)
                if isPending {
                    Text(tr("Wait for this group's pending change before editing its wake-up wait."))
                        .foregroundStyle(Ink.faint)
                }
                if changed {
                    let (direction, delay) = model.preview(action)
                    Text(String(format: tr("%@ — takes effect in %@"), direction.label, delay.shortDelayLabel))
                        .font(.footnote).foregroundStyle(Ink.faint)
                }
                Button(tr("Queue change")) {
                    if model.queue(action) != nil { dismiss() }
                }
                .buttonStyle(DemoraPrimaryButtonStyle())
                .disabled(limit == nil || !changed || isPending || !schedule.isValid)
            }
            .padding(24).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .paper()
        .casedNavigationTitle(tr("Group wake-up"))
        .onAppear {
            guard !loaded else { return }
            loaded = true
            enabled = limit?.wakeDelayMinutes != nil
            minutes = limit?.wakeDelayMinutes ?? 10
            schedule = limit?.wakeSchedule ?? LimitWakeSchedule()
        }
    }
}
