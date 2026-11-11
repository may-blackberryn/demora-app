import SwiftUI

/// Per-limit wake-up (R7): only for limits that already use one. Its own
/// change (`.setGroupWakeSchedule`), separate from the limit editor.
struct GroupWakeDelayEditor: View {
    let limitID: UUID
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var enabled = false
    @State private var minutes = 10
    @State private var schedule = LimitWakeSchedule()
    @State private var loaded = false
    @State private var receipt: ChangeReceiptRequest?

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
        RuleEditorPage(title: limit?.name ?? tr("Group wake-up"), presentation: .pushed,
                       isDirty: loaded && changed,
                       canReview: limit != nil && changed && !isPending && schedule.isValid,
                       waiting: isPending,
                       onReview: { receipt = ChangeReceiptRequest(action: action) }) {
            EditorSection(tr("Wake-up")) {
                Toggle(tr("Ask me to tap Wake up"), isOn: $enabled).frame(minHeight: 44)
                if enabled {
                    WakeTimingEditor(startMinutes: $schedule.startMinutes, waitMinutes: $minutes,
                                     weekdays: $schedule.weekdays, dayTimings: $schedule.dayTimings,
                                     latestMinutes: $schedule.latestMinutes)
                }
            }
            EditorNote(text: tr("A new wait applies to the next tap. A latest wake-up time can end today's gate once this delayed change applies. Turning this off still follows your less-strict delay.")
                       + " " + tr("Usage already spent, split budgets and extra-time grants are not reset by this change."))
        }
        .changeReceipt($receipt) { dismiss() }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            enabled = limit?.wakeDelayMinutes != nil
            minutes = limit?.wakeDelayMinutes ?? 10
            schedule = limit?.wakeSchedule ?? LimitWakeSchedule()
        }
    }
}
