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

struct DelayPolicySettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var policy = DelayPolicy()
    @State private var loaded = false
    private var action: ChangeAction { .setDelayPolicy(policy.normalized) }
    private var pending: Bool {
        model.state.pending.contains { ChangeEngine.conflictKey($0.action) == "delayPolicy" }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                DemoraPageTitle(title: tr("How changes wait"))
                Text(tr("Changing your delay mode follows your current delays. Countdowns already running keep their original deadline."))
                    .font(.subheadline).foregroundStyle(Ink.faint)
                DelayPolicyPicker(policy: $policy)
                if pending {
                    Text(tr("A change for this setting is already pending. Cancel it on the Home tab first if you want something different."))
                        .font(.footnote).foregroundStyle(Ink.faint)
                }
                if policy.isValid && policy.normalized != model.state.delayPolicy.normalized {
                    let (direction, delay) = model.preview(action)
                    Label(String(format: tr("%@ — takes effect in %@"),
                                 direction.label, delay.shortDelayLabel), systemImage: "clock")
                        .font(.footnote).foregroundStyle(Ink.faint)
                    Button(tr("Queue change")) {
                        if model.queue(action) != nil { dismiss() }
                    }
                    .buttonStyle(DemoraPrimaryButtonStyle()).disabled(pending)
                }
            }
            .padding(26).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(tr("Delays"))
        .onAppear {
            guard !loaded else { return }
            policy = model.state.delayPolicy
            loaded = true
        }
    }
}
