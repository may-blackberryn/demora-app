import SwiftUI
import FamilyControls

/// The live entry point. Only this view and its queued-editor wrapper use AppModel.
/// Setup and the reusable editor below never read or write the shared store.
struct DayNightSchedulesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var editing: DayNightGroup?
    @State private var removing: DayNightGroup?
    @State private var waking = false
    @State private var wakeFailed = false

    init() {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                DemoraPageTitle(title: tr("Day & night"))
                DayNightExplanation()
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    if model.state.dayNightGroups.contains(where: {
                        DayNightWake.status(group: $0) == .needsTap
                    }) {
                        Button {
                            guard !waking else { return }
                            waking = true
                            wakeFailed = false
                            Task { @MainActor in
                                let saved = await ChangeEngine.wakeUpAllOffMain()
                                wakeFailed = !saved && model.state.dayNightGroups.contains {
                                    DayNightWake.status(group: $0) == .needsTap
                                }
                                waking = false
                                model.tick()
                            }
                        } label: {
                            Label(tr("Wake up"), systemImage: "sunrise")
                        }
                        .buttonStyle(DemoraPrimaryButtonStyle())
                        .disabled(waking)
                        if wakeFailed {
                            Text(tr("Wake-up could not be saved. Try again."))
                                .font(.footnote).foregroundStyle(Ink.danger)
                        }
                    }
                }
                Text(String(format: tr("%d day/night groups"), model.state.dayNightGroups.count))
                    .font(.caption.smallCaps()).foregroundStyle(Ink.faint)
                if model.state.dayNightGroups.isEmpty {
                    Text(tr("Add a group to give its apps their own wake-up wait and sleep time."))
                        .foregroundStyle(Ink.faint)
                }
                ForEach(model.state.dayNightGroups) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        Button { editing = group } label: {
                            DayNightGroupSummary(group: group, limits: model.state.limits)
                        }
                        .buttonStyle(.plain)
                        .disabled(hasPendingCollectionChange)
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            DayNightLiveWakeStatus(group: group)
                        }
                        if isPending(group.id) {
                            Text(tr("A change for this group is pending. Its current rules stay in place until that change applies."))
                                .font(.footnote).foregroundStyle(Ink.faint)
                        }
                        Button(tr("Remove group"), role: .destructive) { removing = group }
                            .disabled(hasPendingCollectionChange)
                    }
                    .demoraSurface()
                }
                // A queued addition isn't active yet, but remains visible here.
                ForEach(pendingAdditions) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        DayNightGroupSummary(group: group, limits: model.state.limits)
                        Label(tr("Pending change"), systemImage: "clock")
                            .font(.footnote).foregroundStyle(Ink.faint)
                    }
                    .demoraSurface()
                }
                Button { editing = DayNightGroup(name: "") } label: {
                    Label(tr("Add day/night group"), systemImage: "plus")
                }
                .buttonStyle(DemoraPrimaryButtonStyle())
                .disabled(hasPendingCollectionChange || model.state.dayNightGroups.count >= 5)
                if hasPendingCollectionChange {
                    Text(tr("Wait for the pending day/night change before adding, editing or removing another group."))
                        .font(.footnote).foregroundStyle(Ink.faint)
                }
                if model.state.dayNightGroups.count >= 5 {
                    Text(tr("You can create up to five day/night groups."))
                        .font(.footnote).foregroundStyle(Ink.faint)
                }
                if !model.state.limits.isEmpty {
                    NavigationLink { WakeScheduleView() } label: {
                        GridCard(symbol: "sunrise", title: tr("Group wake-up"),
                                 subtitle: tr("Limits & blocks"))
                    }
                    .buttonStyle(.plain)
                }
                legacyLinks
            }
            .padding(24).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .paper()
        .casedNavigationTitle(tr("Day & night"))
        .sheet(item: $editing) { group in
            DayNightQueuedEditor(group: group)
        }
        .alert(tr("Remove day/night group?"), isPresented: Binding(
            get: { removing != nil }, set: { if !$0 { removing = nil } }
        )) {
            Button(tr("Queue change"), role: .destructive) {
                guard let group = removing, !hasPendingCollectionChange,
                      model.state.dayNightGroups.contains(where: { $0.id == group.id }) else { return }
                model.queue(.removeDayNightGroup(id: group.id))
                removing = nil
            }
            Button(tr("Cancel"), role: .cancel) { removing = nil }
        } message: {
            if let group = removing {
                let (direction, delay) = model.preview(.removeDayNightGroup(id: group.id))
                Text(group.name + "\n" + String(format: tr("%@ — takes effect in %@"),
                                               direction.label, delay.shortDelayLabel))
            }
        }
    }

    private var hasPendingCollectionChange: Bool {
        model.state.pending.contains {
            switch $0.action {
            case .upsertDayNightGroup, .removeDayNightGroup: return true
            default: return false
            }
        }
    }

    private func isPending(_ id: UUID) -> Bool {
        model.state.pending.contains {
            switch $0.action {
            case .upsertDayNightGroup(let group): return group.id == id
            case .removeDayNightGroup(let pendingID): return pendingID == id
            default: return false
            }
        }
    }

    private var pendingAdditions: [DayNightGroup] {
        model.state.pending.compactMap {
            guard case .upsertDayNightGroup(let group) = $0.action,
                  !model.state.dayNightGroups.contains(where: { $0.id == group.id }) else { return nil }
            return group
        }
    }

    private var hasLegacyWake: Bool {
        model.state.wakeRule != WakeBlockRule()
            || hasLegacySleep // Sleep's end hour is edited on the legacy wake page.
            || model.state.pending.contains {
                switch $0.action {
                case .setWakeRule: return true
                default: return false
                }
            }
    }

    private var hasLegacySleep: Bool {
        model.state.sleepRule != SleepBlockRule()
            || model.state.pending.contains {
                if case .setSleepRule = $0.action { return true }
                return false
            }
    }

    @ViewBuilder private var legacyLinks: some View {
        if hasLegacyWake || hasLegacySleep {
            VStack(alignment: .leading, spacing: 12) {
                Text(tr("Existing wake/sleep settings")).font(.headline)
                Text(tr("These existing settings still apply alongside your day/night groups."))
                    .font(.footnote).foregroundStyle(Ink.faint)
                if hasLegacyWake {
                    NavigationLink { WakeBlockEditor() } label: {
                        GridCard(symbol: "sunrise", title: tr("General wake-up schedule"),
                                 subtitle: tr("Existing wake-up settings"))
                    }
                }
                if hasLegacySleep {
                    NavigationLink { SleepBlockEditor() } label: {
                        GridCard(symbol: "moon.stars", title: tr("Sleep"),
                                 subtitle: tr("Existing sleep settings"))
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
}

private struct DayNightLiveWakeStatus: View {
    let group: DayNightGroup

    var body: some View {
        switch DayNightWake.status(group: group) {
        case .needsTap:
            Label(tr("Wake-up tap needed"), systemImage: "sunrise")
                .font(.subheadline).foregroundStyle(Ink.faint)
        case .waiting(let release):
            HStack {
                Label(tr("Wake-up wait"), systemImage: "clock")
                Spacer()
                let remaining = max(1, release.timeIntervalSince(TimeGuard.now()))
                Text(timerInterval: Date.now...Date.now.addingTimeInterval(remaining), countsDown: true)
                    .monospacedDigit()
            }
            .font(.subheadline).foregroundStyle(Ink.faint)
        case .awake:
            Label(tr("Awake for today"), systemImage: "checkmark")
                .font(.subheadline).foregroundStyle(Ink.faint)
        case .inactive:
            EmptyView()
        }
    }
}

private struct DayNightQueuedEditor: View {
    let group: DayNightGroup
    @EnvironmentObject private var model: AppModel

    private var hasPendingChange: Bool {
        model.state.pending.contains {
            switch $0.action {
            case .upsertDayNightGroup, .removeDayNightGroup: return true
            default: return false
            }
        }
    }

    var body: some View {
        DayNightGroupEditor(
            group: group, limits: model.state.limits, groups: model.state.dayNightGroups,
            canChooseApps: model.authorized, saveTitle: tr("Queue change"),
            saveExplanation: { draft in
                if hasPendingChange {
                    return tr("Wait for the pending day/night change before adding, editing or removing another group.")
                }
                let (direction, delay) = model.preview(.upsertDayNightGroup(draft))
                return String(format: tr("%@ — takes effect in %@"), direction.label, delay.shortDelayLabel)
            },
            canSave: { draft in
                !hasPendingChange
                    && model.state.dayNightGroups.first(where: { $0.id == draft.id }) != draft
            },
            onSave: { draft in
                guard !hasPendingChange,
                      draft.isValid(limits: model.state.limits),
                      DayNightGroup.isValidCollection(
                        dayNightReplacing(draft, in: model.state.dayNightGroups),
                        limits: model.state.limits) else { return false }
                return model.queue(.upsertDayNightGroup(draft)) != nil
            })
    }
}

/// Embeddable onboarding/upgrade content. The binding is the entire write surface.
struct DayNightSetupDraftView: View {
    let limits: [AppLimit]
    @Binding private var groups: [DayNightGroup]
    let isDemo: Bool
    let canChooseApps: Bool
    @State private var editing: DayNightGroup?

    init(limits: [AppLimit], groups: Binding<[DayNightGroup]>,
         isDemo: Bool = false, canChooseApps: Bool = true) {
        self.limits = limits
        self._groups = groups
        self.isDemo = isDemo
        self.canChooseApps = canChooseApps
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            DayNightExplanation()
            if groups.isEmpty {
                Text(tr("Optional — add day/night groups now, or set them up later in Schedules."))
                    .font(.subheadline).foregroundStyle(Ink.faint)
            }
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 12) {
                    Button { editing = group } label: {
                        DayNightGroupSummary(group: group, limits: limits)
                    }
                    .buttonStyle(.plain)
                    Button(tr("Remove group"), role: .destructive) {
                        groups.removeAll { $0.id == group.id }
                    }
                }
                .demoraSurface()
            }
            if !isDemo && !groups.isEmpty
                && !DayNightGroup.isValidCollection(groups, limits: limits) {
                Text(tr("Review these groups: choose valid apps, timings and exceptions before continuing."))
                    .font(.footnote).foregroundStyle(Ink.danger)
            }
            if let error = dayNightCollectionError(groups, limits: limits) {
                Text(error).font(.footnote).foregroundStyle(Ink.danger)
            }
            Button { editing = DayNightGroup(name: "") } label: {
                Label(tr("Add day/night group"), systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .disabled(groups.count >= 5)
            if groups.count >= 5 {
                Text(tr("You can create up to five day/night groups."))
                    .font(.footnote).foregroundStyle(Ink.faint)
            }
        }
        .sheet(item: $editing) { group in
            DayNightGroupEditor(group: group, limits: limits, groups: groups,
                                isDemo: isDemo, canChooseApps: canChooseApps) { draft in
                let replacement = dayNightReplacing(draft, in: groups)
                guard dayNightDraftIsValid(draft, groups: replacement, limits: limits,
                                          isDemo: isDemo) else { return false }
                groups = replacement
                return true
            }
        }
    }
}

/// A local draft with an explicit save callback; dismissing or using the picker
/// cannot mutate an existing rule. Demo callers must pass an isolated binding.
struct DayNightGroupEditor: View {
    let limits: [AppLimit]
    let groups: [DayNightGroup]
    let isDemo: Bool
    let canChooseApps: Bool
    let saveTitle: String?
    let saveExplanation: ((DayNightGroup) -> String?)?
    let canSave: (DayNightGroup) -> Bool
    let onSave: (DayNightGroup) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var draft: DayNightGroup
    @State private var showPicker = false
    @State private var saveRejected = false

    init(group: DayNightGroup, limits: [AppLimit], groups: [DayNightGroup] = [],
         isDemo: Bool = false, canChooseApps: Bool = true, saveTitle: String? = nil,
         saveExplanation: ((DayNightGroup) -> String?)? = nil,
         canSave: @escaping (DayNightGroup) -> Bool = { _ in true },
         onSave: @escaping (DayNightGroup) -> Bool) {
        self._draft = State(initialValue: group)
        self.limits = limits
        self.groups = groups
        self.isDemo = isDemo
        self.canChooseApps = canChooseApps
        self.saveTitle = saveTitle
        self.saveExplanation = saveExplanation
        self.canSave = canSave
        self.onSave = onSave
    }

    private var normalizedDraft: DayNightGroup {
        var value = draft
        value.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return value
    }

    private var valid: Bool {
        dayNightDraftIsValid(normalizedDraft,
                            groups: dayNightReplacing(normalizedDraft, in: groups),
                            limits: limits, isDemo: isDemo)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    #if DEBUG
                    if isDemo { DeveloperDemoNotice() }
                    #endif
                    VStack(alignment: .leading, spacing: 12) {
                        Text(tr("Name")).font(.headline)
                        TextField(tr("e.g. Social apps at night"), text: $draft.name)
                            .textFieldStyle(.roundedBorder)
                        if normalizedDraft.name.count > 80 {
                            Text(tr("Use a name of 80 characters or fewer."))
                                .font(.footnote).foregroundStyle(Ink.danger)
                        }
                    }
                    .demoraSurface()
                    timingEditor
                    weekdayEditor
                    scopeEditor
                    if !valid {
                        Text(tr("Choose a name, at least one boundary, weekdays and a valid app scope. Sleep and wake-up times must differ."))
                            .font(.footnote).foregroundStyle(Ink.danger)
                    }
                    if let error = dayNightCollectionError(
                        dayNightReplacing(normalizedDraft, in: groups), limits: limits) {
                        Text(error).font(.footnote).foregroundStyle(Ink.danger)
                    }
                    if let explanation = saveExplanation?(normalizedDraft) {
                        Label(explanation, systemImage: "clock")
                            .font(.footnote).foregroundStyle(Ink.faint)
                    }
                    if saveRejected {
                        Text(tr("This group could not be saved. Review pending changes and your app selection, then try again."))
                            .font(.footnote).foregroundStyle(Ink.danger)
                    }
                    Text(tr("Overlapping rules use the strictest boundary. An exception here does not bypass another group or limit."))
                        .font(.footnote).foregroundStyle(Ink.faint)
                }
                .padding(24).frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            .paper()
            .casedNavigationTitle(tr("Day/night group"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveTitle ?? tr("Save")) {
                        guard valid, canSave(normalizedDraft) else { return }
                        if onSave(normalizedDraft) { dismiss() }
                        else { saveRejected = true }
                    }
                    .disabled(!valid || !canSave(normalizedDraft))
                }
            }
            .sheet(isPresented: $showPicker) {
                // Defense in depth: a demo never creates a real system picker,
                // even if its presentation flag is accidentally set.
                if !isDemo && canChooseApps {
                    AppPickerSheet(selection: $draft.scope.selection)
                }
            }
        }
    }

    private var timingEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(tr("Require wake-up tap"), isOn: $draft.wakeEnabled)
            WakeTimingEditor(startMinutes: Binding(get: { draft.defaultWakeStart },
                                                  set: { draft.wakeStartMinutes = $0 }),
                             waitMinutes: $draft.waitMinutes, weekdays: $draft.weekdays,
                             dayTimings: $draft.weekdayWakeTimings,
                             showsWeekdays: false, showsWait: draft.wakeEnabled)
            Text(tr("Sleep blocking ends at this time, even if the wake-up tap is off."))
                .font(.footnote).foregroundStyle(Ink.faint)
            Toggle(tr("Enable sleep blocking"), isOn: $draft.sleepEnabled)
            if draft.sleepEnabled {
                Text(tr("Sleep begins")).font(.headline)
                HStack {
                    Picker(tr("Hour"), selection: sleepHour) {
                        ForEach(0..<24, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                    }
                    Picker(tr("Minute"), selection: sleepMinute) {
                        ForEach(0...(draft.sleepStartMinutes / 60 == 23 ? 30 : 59), id: \.self) {
                            Text(String(format: "%02d", $0)).tag($0)
                        }
                    }
                }
                Text(tr("Sleep ends at the following wake-up start, using that day's custom time if set."))
                    .font(.footnote).foregroundStyle(Ink.faint)
            }
        }
        .demoraSurface()
    }

    private var sleepHour: Binding<Int> {
        Binding(get: { draft.sleepStartMinutes / 60 }, set: {
            draft.sleepStartMinutes = $0 * 60 + min(draft.sleepStartMinutes % 60, $0 == 23 ? 30 : 59)
        })
    }

    private var sleepMinute: Binding<Int> {
        Binding(get: { draft.sleepStartMinutes % 60 }, set: {
            draft.sleepStartMinutes = draft.sleepStartMinutes / 60 * 60 + $0
        })
    }

    private var weekdayEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("Weekdays")).font(.headline)
            ForEach(1...7, id: \.self) { day in
                Toggle(dayNightWeekdayNames[day - 1], isOn: Binding(
                    get: { draft.weekdays.contains(day) },
                    set: { selected in
                        if selected { draft.weekdays.insert(day) }
                        else { draft.weekdays.remove(day) }
                    }))
            }
            Text(tr("Weekdays apply to the wake-up morning and the evening when sleep begins."))
                .font(.footnote).foregroundStyle(Ink.faint)
        }
        .demoraSurface()
    }

    private var scopeEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(tr("Apps")).font(.headline)
            Picker(tr("App scope"), selection: $draft.scope.mode) {
                Text(tr("Selected limits and extra apps")).tag(DayNightScopeMode.selected)
                Text(tr("All other apps except…")).tag(DayNightScopeMode.allOtherApps)
            }
            .pickerStyle(.menu)
            Text(draft.scope.mode == .selected
                 ? tr("Check existing limits and choose extra apps for this group's boundaries.")
                 : tr("The fallback automatically excludes apps targeted by your other named day/night groups. Check limits and choose individual apps for additional exceptions. Other rules still apply."))
                .font(.footnote).foregroundStyle(Ink.faint)
            Text(draft.scope.mode == .selected ? tr("Existing limits") : tr("Limits to exclude"))
                .font(.subheadline.weight(.semibold))
            if limits.isEmpty {
                Text(tr("No existing limits. You can choose apps below."))
                    .font(.footnote).foregroundStyle(Ink.faint)
            }
            ForEach(limits) { limit in
                limitChecklistRow(limit)
            }
            let selectedIDs = draft.scope.limitIDs.union(draft.scope.excludedLimitIDs)
            if !selectedIDs.isSubset(of: Set(limits.map(\.id))) {
                Text(tr("Some selected limits no longer exist. Remove their references before saving."))
                    .font(.footnote).foregroundStyle(Ink.danger)
                Button(tr("Remove missing limits")) {
                    let available = Set(limits.map(\.id))
                    draft.scope.limitIDs.formIntersection(available)
                    draft.scope.excludedLimitIDs.formIntersection(available)
                }
            }
            Text(draft.scope.mode == .selected ? tr("Extra apps") : tr("Apps to exclude"))
                .font(.subheadline.weight(.semibold))
            if isDemo {
                Text(tr("Demo: select sample limits above. The real app picker is not opened."))
                    .font(.footnote).foregroundStyle(Ink.faint)
            } else {
                Button(tr("Choose apps")) { if canChooseApps { showPicker = true } }
                    .disabled(!canChooseApps)
                if !canChooseApps {
                    Text(tr("App selection is unavailable until Screen Time access is allowed."))
                        .font(.footnote).foregroundStyle(Ink.faint)
                }
            }
            SelectedAppsView(selection: draft.scope.selection)
            if draft.scope.mode == .allOtherApps {
                Text(tr("Only one all-other-apps fallback is allowed."))
                    .font(.footnote).foregroundStyle(Ink.faint)
                Text(tr("Category exceptions are not supported. Choose individual apps or limits without categories; choosing a category cannot allow all of its apps."))
                    .font(.footnote).foregroundStyle(Ink.faint)
                if !draft.scope.selection.categoryTokens.isEmpty {
                    Text(tr("Remove category exceptions before saving this fallback group."))
                        .font(.footnote).foregroundStyle(Ink.danger)
                    Button(tr("Remove category exceptions")) {
                        draft.scope.selection.categoryTokens.removeAll()
                    }
                }
            }
        }
        .demoraSurface()
    }

    private func limitChecklistRow(_ limit: AppLimit) -> some View {
        let selected = draft.scope.mode == .selected
            ? draft.scope.limitIDs.contains(limit.id) : draft.scope.excludedLimitIDs.contains(limit.id)
        let unsupported = draft.scope.mode == .allOtherApps && !limit.selection.categoryTokens.isEmpty
        return Button {
            if draft.scope.mode == .selected {
                if selected { draft.scope.limitIDs.remove(limit.id) }
                else { draft.scope.limitIDs.insert(limit.id) }
            } else {
                if selected { draft.scope.excludedLimitIDs.remove(limit.id) }
                else if !unsupported { draft.scope.excludedLimitIDs.insert(limit.id) }
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                VStack(alignment: .leading, spacing: 4) {
                    Text(limit.name).foregroundStyle(Ink.ink)
                    Text(String(format: tr("%d apps, %d categories, %d websites"),
                                limit.selection.applicationTokens.count, limit.selection.categoryTokens.count,
                                limit.selection.webDomainTokens.count))
                        .font(.caption).foregroundStyle(Ink.faint)
                    if unsupported {
                        Text(tr("Contains categories — cannot be a fallback exception."))
                            .font(.caption).foregroundStyle(Ink.danger)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(unsupported && !selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue(selected ? tr("Selected") : tr("Not selected"))
    }
}

private struct DayNightExplanation: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("Give each group its own wake-up wait and sleep time."))
                .font(.subheadline)
            Text(tr("One Wake up tap on Home starts every eligible group's wait together. Each group unlocks after its own wait; sleep blocking ends at its wake-up start time."))
                .font(.footnote).foregroundStyle(Ink.faint)
            Text(tr("Overlapping rules use the strictest boundary. An exception here does not bypass another group or limit."))
                .font(.footnote).foregroundStyle(Ink.faint)
            Text(tr("An all-other-apps fallback automatically excludes apps targeted by your named selected groups. Category-based groups cannot be combined with this fallback."))
                .font(.footnote).foregroundStyle(Ink.faint)
        }
    }
}

private struct DayNightGroupSummary: View {
    let group: DayNightGroup
    let limits: [AppLimit]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(group.name).font(.system(.title3, design: .serif)).foregroundStyle(Ink.ink)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Ink.faint)
            }
            if group.wakeEnabled {
                Label(String(format: tr("Wake from %@ · wait %d minutes after tap"),
                             minutesLabel(group.wakeTiming(on: Date()).startMinutes), group.wakeTiming(on: Date()).waitMinutes), systemImage: "sunrise")
            }
            if group.sleepEnabled {
                Label(String(format: tr("Sleep %@–%@"), minutesLabel(group.sleepStartMinutes),
                             minutesLabel(group.wakeTiming(on: Date()).startMinutes)), systemImage: "moon.stars")
            }
            if !group.weekdayWakeTimings.isEmpty {
                Text(tr("Custom wake-up times by day"))
            }
            Text(group.weekdays == Set(1...7) ? tr("Every day")
                 : group.weekdays.sorted().filter { (1...7).contains($0) }
                    .map { dayNightWeekdayNames[$0 - 1] }.joined(separator: " · "))
            Text(group.scope.mode == .selected ? tr("Selected limits and extra apps") : tr("All other apps except…"))
                .fontWeight(.semibold)
            let ids = group.scope.mode == .selected ? group.scope.limitIDs : group.scope.excludedLimitIDs
            let names = limits.filter { ids.contains($0.id) }.map(\.name)
            if !names.isEmpty { Text(names.joined(separator: ", ")) }
            let targets = group.scope.resolved(limits: limits)
            Text(String(format: tr("%d limits · %d apps, %d categories, %d websites"),
                        ids.count, targets.applicationTokens.count,
                        targets.categoryTokens.count, targets.webDomainTokens.count))
        }
        .font(.caption).foregroundStyle(Ink.faint)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// Keep Calendar's Sunday-first indexing (1...7), but use the app's selected
/// language rather than the device locale, matching the limit editor.
private var dayNightWeekdayNames: [String] {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = AppLanguage.current.locale
    return calendar.weekdaySymbols
}

private func dayNightReplacing(_ group: DayNightGroup, in groups: [DayNightGroup]) -> [DayNightGroup] {
    if groups.contains(where: { $0.id == group.id }) {
        return groups.map { $0.id == group.id ? group : $0 }
    }
    return groups + [group]
}

private func dayNightDraftIsValid(_ group: DayNightGroup, groups: [DayNightGroup],
                                limits: [AppLimit], isDemo: Bool) -> Bool {
    guard dayNightCollectionError(groups, limits: limits) == nil else { return false }
    // This check applies even in previews: never imply that category exceptions work.
    if group.scope.mode == .allOtherApps {
        guard group.scope.selection.categoryTokens.isEmpty,
              !limits.contains(where: {
                  group.scope.excludedLimitIDs.contains($0.id) && !$0.selection.categoryTokens.isEmpty
              }) else { return false }
    }
    guard isDemo else {
        return group.isValid(limits: limits) && DayNightGroup.isValidCollection(groups, limits: limits)
    }
    // Isolated sample limits have no real tokens. Real limit creation rejects
    // empty selections; previews can still exercise the checklist with IDs.
    let knownIDs = Set(limits.map(\.id))
    let hasSelectedTargets = !group.scope.limitIDs.isEmpty
        || !group.scope.selection.applicationTokens.isEmpty
        || !group.scope.selection.categoryTokens.isEmpty
        || !group.scope.selection.webDomainTokens.isEmpty
    return !group.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && group.name.count <= 80
        && (group.wakeEnabled || group.sleepEnabled)
        && group.timingsAreValid
        && (0...1410).contains(group.sleepStartMinutes)
        && !group.weekdays.isEmpty && group.weekdays.isSubset(of: Set(1...7))
        && group.scope.limitIDs.isSubset(of: knownIDs)
        && group.scope.excludedLimitIDs.isSubset(of: knownIDs)
        && (group.scope.mode == .allOtherApps || hasSelectedTargets)
        && Set(groups.map(\.id)).count == groups.count
}

private func dayNightCollectionError(_ groups: [DayNightGroup], limits: [AppLimit]) -> String? {
    if groups.count > 5 { return tr("You can create up to five day/night groups.") }
    let fallbacks = groups.filter { $0.scope.mode == .allOtherApps }
    if fallbacks.count > 1 { return tr("Only one all-other-apps fallback is allowed.") }
    guard !fallbacks.isEmpty else { return nil }
    let categoryGroups = groups.filter { group in
        group.scope.mode == .selected && (!group.scope.selection.categoryTokens.isEmpty
            || limits.contains { group.scope.limitIDs.contains($0.id) && !$0.selection.categoryTokens.isEmpty })
    }
    if !categoryGroups.isEmpty {
        return String(format: tr("The all-other-apps fallback cannot exclude whole categories used by these groups: %@. Choose individual apps instead, or remove the fallback."),
                      categoryGroups.map(\.name).joined(separator: ", "))
    }
    return nil
}
