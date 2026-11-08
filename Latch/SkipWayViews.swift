//
//  SkipWayViews.swift
//  "Ways to skip a wait" (docs/you-redesign.md §5.3, Y2/Y3): trusted
//  contacts, passwords and phrases as one list, each row saying what it may
//  skip with at most one state chip. Decisions live in YouPresentation.swift.
//

import SwiftUI

// MARK: - The section on You

struct WaysToSkipSection: View {
    @AppAccent private var accent
    @EnvironmentObject private var model: AppModel
    let onOpen: (SkipWayRow) -> Void
    let onAdd: () -> Void
    /// Opens the receipt for turning contact approvals on (true) or off.
    let onToggleContacts: (Bool) -> Void
    let showsSentLink: Bool
    let onSent: () -> Void
    @State private var collapsed: Set<SkipWayKind> = []

    var body: some View {
        let list = SkipWayList.make(overrides: model.state.overrides, pending: model.state.pending,
                                    unavailableCodes: model.unavailableContactCodes)
        VStack(alignment: .leading, spacing: DemoraSpace.cardGap) {
            SectionHeader(tr("Ways to skip a wait"))
            Text(tr("These can let a change apply before its wait ends. Changes to them wait too."))
                .demoraType(.meta)
                .foregroundStyle(Ink.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            if list.isEmpty {
                EmptyStateView(title: tr("Nothing can skip a wait yet."),
                               systemImage: "hourglass",
                               description: tr("That's the strictest setup."),
                               actionTitle: tr("Add a way to skip a wait"),
                               action: onAdd)
            } else {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    card(list, now: context.date)
                }
            }
            if showsSentLink {
                Button(tr("Requests you sent"), action: onSent)
                    .buttonStyle(.plain)
                    .demoraType(.meta)
                    .foregroundStyle(accent)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
        }
    }

    private func card(_ list: SkipWayList, now: Date) -> some View {
        let kinds = [SkipWayKind.contact, .password, .phrase].filter { !list.rows(of: $0).isEmpty }
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(kinds.enumerated()), id: \.element) { index, kind in
                if index > 0 { YouRowDivider(heavy: true) }
                if list.collapsesKinds { kindHeader(kind, count: list.rows(of: kind).count) }
                if list.isExpanded(kind, collapsed: collapsed) {
                    ForEach(Array(list.rows(of: kind).enumerated()), id: \.element.id) { offset, row in
                        if offset > 0 { YouRowDivider() }
                        Button { onOpen(row) } label: {
                            SkipWayRowView(row: row, now: now)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if kind == .contact, let toggle = list.contactsSwitch {
                    YouRowDivider()
                    contactsSwitchRow(toggle)
                }
            }
            YouRowDivider()
            Button(action: onAdd) {
                Label(tr("Add a way to skip a wait"), systemImage: "plus.circle")
                    .font(DemoraType.button)
                    .foregroundStyle(accent)
                    .padding(.horizontal, DemoraSpace.cardPadding)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .paperCard(padding: 0)
    }

    private func kindHeader(_ kind: SkipWayKind, count: Int) -> some View {
        let open = !collapsed.contains(kind)
        return Button {
            if open { collapsed.insert(kind) } else { collapsed.remove(kind) }
        } label: {
            HStack {
                Text(String(format: SkipWayRowText.kindTitle(kind), count))
                    .demoraType(.label)
                    .foregroundStyle(Ink.inkSoft)
                Spacer()
                Image(systemName: open ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Ink.inkSoft)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, DemoraSpace.cardPadding)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isHeader)
        .accessibilityValue(open ? tr("Expanded") : tr("Collapsed"))
    }

    /// "Contacts can approve · On". Tapping opens the receipt for the other
    /// state; while a switch change waits, it opens that change instead.
    @ViewBuilder private func contactsSwitchRow(_ toggle: SkipWayList.ContactsSwitch) -> some View {
        if let id = toggle.pendingChangeID,
           let change = model.state.pending.first(where: { $0.id == id }) {
            VStack(alignment: .leading, spacing: 0) {
                YouRowLabel(title: tr("Contacts can approve"),
                            value: toggle.enabled ? tr("On") : tr("Off"), chevron: false)
                PendingLine(change: change, label: tr("Changes in")) {
                    model.youPath.append(.ledger(change.id))
                }
                .padding(.horizontal, DemoraSpace.cardPadding)
            }
        } else {
            YouNavigationRow(title: tr("Contacts can approve"),
                             value: toggle.enabled ? tr("On") : tr("Off")) {
                onToggleContacts(!toggle.enabled)
            }
        }
    }
}

// MARK: - One row (SkipWayRow, §5.3)

struct SkipWayRowView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.locale) private var locale
    let row: SkipWayRow
    let now: Date

    private var contact: TrustedContact? {
        guard row.kind == .contact else { return nil }
        return model.state.overrides.contacts.first { $0.id == row.id }
            ?? model.state.pending.lazy.compactMap { change -> TrustedContact? in
                if case .addContact(let c) = change.action, c.id == row.id { return c }
                return nil
            }.first
    }

    private var name: String {
        if let contact, let code = contact.latchUserCode {
            return resolvedName(forCode: code, model: model,
                                fallback: contact.name.isEmpty ? tr("Unnamed") : contact.name)
        }
        return row.name.isEmpty ? tr("Unnamed") : row.name
    }

    var body: some View {
        let permissions = SkipWayPermissionText.summary(row.allowed, translate: tr)
        let chip = SkipWayRowText.chip(row.chip, now: now, locale: locale)
        HStack(alignment: .center, spacing: DemoraSpace.s) {
            leading
            VStack(alignment: .leading, spacing: DemoraSpace.xxs) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: DemoraSpace.xs) {
                        title
                        Spacer(minLength: DemoraSpace.xs)
                        if let chip { StateChip(kind: chip.kind, text: chip.text) }
                    }
                    VStack(alignment: .leading, spacing: DemoraSpace.xxs) {
                        title
                        if let chip { StateChip(kind: chip.kind, text: chip.text) }
                    }
                }
                Text(permissions)
                    .demoraType(.meta)
                    .foregroundStyle(Ink.inkSoft)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Ink.inkSoft)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, DemoraSpace.cardPadding)
        .padding(.vertical, DemoraSpace.s)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .opacity(row.isPendingAddition ? 0.6 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([name, String(format: tr("can skip: %@"), permissions), chip?.text]
            .compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(.isButton)
    }

    private var title: some View {
        HStack(alignment: .firstTextBaseline, spacing: DemoraSpace.xxs) {
            Text(name)
                .demoraType(.cardTitle)
                .foregroundStyle(row.isPendingAddition ? Ink.inkSoft : Ink.ink)
            if let phrase = row.phrase {
                Text("· " + SkipWayRowText.phrase(phrase))
                    .demoraType(.meta)
                    .foregroundStyle(Ink.inkSoft)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var leading: some View {
        switch row.kind {
        case .contact:
            ContactAvatarView(avatar: contact.flatMap { c in
                c.latchUserCode.flatMap { resolvedAvatar(forCode: $0, model: model) } ?? c.avatar
            }, size: 36)
        case .password:
            SkipWaySymbol(symbol: "key")
        case .phrase:
            SkipWaySymbol(symbol: "text.quote")
        }
    }
}

/// A 36 pt circle with a password or phrase symbol.
struct SkipWaySymbol: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Ink.inkSoft)
            .frame(width: 36, height: 36)
            .background(Circle().strokeBorder(Ink.hairline, lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// Words for the pure row facts.
enum SkipWayRowText {
    static func kindTitle(_ kind: SkipWayKind) -> String {
        switch kind {
        case .contact: return tr("Contacts (%d)")
        case .password: return tr("Passwords (%d)")
        case .phrase: return tr("Phrases (%d)")
        }
    }

    static func phrase(_ detail: SkipWayPhraseDetail) -> String {
        switch detail {
        case .words(let count): return String(format: tr("%d words"), count)
        case .custom: return tr("custom")
        }
    }

    static func chip(_ chip: SkipWayChip?, now: Date,
                     locale: Locale) -> (kind: StateChip.Kind, text: String)? {
        var calendar = Calendar.current
        calendar.locale = locale
        switch chip {
        case nil: return nil
        case .removed(let date):
            return (.upcoming, String(format: tr("Removed %@"),
                                      TodayTimeText.short(date, now: now, calendar: calendar, locale: locale)))
        case .added(let date):
            return (.upcoming, String(format: tr("Added %@"),
                                      TodayTimeText.short(date, now: now, calendar: calendar, locale: locale)))
        case .changes(let date):
            return (.upcoming, String(format: tr("Changes in %@"), shortWait(until: date, locale: locale)))
        case .waitingToAccept: return (.neutral, tr("Waiting to accept"))
        case .cantReach: return (.blocked, tr("Can't reach"))
        case .paused: return (.neutral, tr("Paused"))
        }
    }

    /// "3h", "12m": the guarded wait, one unit, rounded up.
    static func shortWait(until date: Date, locale: Locale) -> String {
        let remaining = CountdownProjection.remaining(until: date, guardedNow: TimeGuard.now())
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let formatter = DateComponentsFormatter()
        formatter.calendar = calendar
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.maximumUnitCount = 1
        let minutes = max(1, (remaining / 60).rounded(.up))
        return formatter.string(from: minutes * 60) ?? ""
    }
}
