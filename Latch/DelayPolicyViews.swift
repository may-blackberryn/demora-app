import SwiftUI

/// Shared by first-run setup, the replay finish, and ordinary delayed edits.
struct DelayPolicyPicker: View {
    @Binding var policy: DelayPolicy
    @AppAccent private var accent

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(DelayMode.allCases) { mode in
                Button {
                    policy.mode = mode
                    if mode == .separate && policy.strictDelay < 60 { policy.strictDelay = 300 }
                } label: {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: policy.mode == mode ? "checkmark.circle.fill" : "circle")
                            .font(.title2).foregroundStyle(accent)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(mode.label).font(.system(.title3, design: .serif))
                                .foregroundStyle(Ink.ink)
                            Text(mode.explanation).font(.subheadline).foregroundStyle(Ink.faint)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 8).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(policy.mode == mode ? .isSelected : [])
            }
            VStack(alignment: .leading, spacing: 12) {
                if policy.mode == .separate {
                    DelayPicker(title: tr("More-strict delay"), seconds: $policy.strictDelay)
                }
                DelayPicker(title: policy.mode == .shared ? tr("Delay for every change")
                            : tr("Less-strict delay"), seconds: $policy.lenientDelay)
                if policy.mode == .lenientOnly {
                    Text(tr("More-strict changes apply immediately."))
                        .font(.footnote).foregroundStyle(Ink.faint)
                }
                if !policy.isValid {
                    Text(tr("Choose a delay of at least one minute."))
                        .font(.footnote).foregroundStyle(Ink.danger)
                }
            }
            .demoraSurface()
        }
    }
}

struct DelayPolicyNavigationRows: View {
    @EnvironmentObject private var model: AppModel
    private var policy: DelayPolicy { model.state.delayPolicy }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink { DelayPolicySettingsView() } label: {
                GridCard(symbol: "slider.horizontal.3", title: tr("How changes wait"),
                         subtitle: policy.mode.label)
            }
            HStack(alignment: .top, spacing: 14) {
                if policy.mode != .shared {
                    NavigationLink { DelayPolicySettingsView() } label: {
                        DemoraDelayRow(title: tr("More strict"),
                                       duration: policy.mode == .lenientOnly ? tr("Immediately")
                                        : policy.delay(for: .stricter).shortDelayLabel,
                                       symbol: strictLockSymbol)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                NavigationLink { DelayPolicySettingsView() } label: {
                    DemoraDelayRow(title: policy.mode == .shared ? tr("Every change") : tr("Less strict"),
                                   duration: policy.delay(for: .lenient).shortDelayLabel,
                                   symbol: policy.mode == .shared ? "hourglass" : "lock.open")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Your waits (§5.7 K). The new policy follows the current one; countdowns
/// already running keep their time.
struct DelayPolicySettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var policy = DelayPolicy()
    @State private var loaded = false
    @State private var receipt: ChangeReceiptRequest?
    private var action: ChangeAction { .setDelayPolicy(policy.normalized) }
    private var pending: Bool {
        model.state.pending.contains { ChangeEngine.conflictKey($0.action) == "delayPolicy" }
    }
    private var changed: Bool {
        loaded && policy.isValid && policy.normalized != model.state.delayPolicy.normalized
    }
    var body: some View {
        RuleEditorPage(title: tr("Your waits"), presentation: .pushed,
                       isDirty: changed, canReview: changed, waiting: pending,
                       onReview: { receipt = ChangeReceiptRequest(action: action) }) {
            EditorNote(text: tr("New waits follow your current waits. Countdowns already running keep their time."))
            DelayPolicyPicker(policy: $policy)
        }
        .changeReceipt($receipt) { dismiss() }
        .onAppear {
            guard !loaded else { return }
            policy = model.state.delayPolicy
            loaded = true
        }
    }
}
