//
//  BlockingDiagnosticsView.swift
//  2.0.1: what Demora's background blocking is doing right now — which
//  background monitors are running and which recorded failures are behind the
//  "Background blocking may be incomplete" warning. Opened from that warning.
//
//  Read-only except "Try again", which runs the same idempotent repair the app
//  runs when it comes to the foreground. Shows activity names and error text,
//  never usage, app names or tokens.
//

import SwiftUI
import DeviceActivity

struct BlockingDiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    @State private var failures: [SharedStore.EnforcementFailure] = []
    @State private var monitors: [String] = []
    @State private var loaded = false
    @State private var retrying = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DemoraSpace.sectionGap) {
                    problems
                    running
                    Button {
                        retry()
                    } label: {
                        Text(tr("Try again"))
                    }
                    .buttonStyle(DemoraPrimaryButtonStyle())
                    .disabled(retrying)
                }
                .padding(.horizontal, DemoraSpace.pageGutter)
                .padding(.vertical, DemoraSpace.l)
                .frame(maxWidth: DemoraSpace.maxContentWidth)
                .frame(maxWidth: .infinity)
            }
            .background(Ink.paper.ignoresSafeArea())
            .casedNavigationTitle(tr("Background blocking"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Done")) { dismiss() }
                }
            }
            .task { await reload() }
        }
    }

    private var problems: some View {
        VStack(alignment: .leading, spacing: DemoraSpace.s) {
            DemoraSectionTitle(title: tr("Problems"))
            if loaded && failures.isEmpty {
                Text(tr("Everything is set up."))
                    .demoraType(.body)
                    .foregroundStyle(Ink.ink)
            }
            ForEach(failures, id: \.key) { failure in
                VStack(alignment: .leading, spacing: DemoraSpace.xxs) {
                    Text(failure.key)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(Ink.ink)
                        .textSelection(.enabled)
                    Text(failure.detail)
                        .demoraType(.meta)
                        .foregroundStyle(Ink.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    Text(failure.at.appFormatted(date: .abbreviated, time: .shortened))
                        .demoraType(.meta)
                        .foregroundStyle(Ink.faint)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .paperCard()
            }
        }
    }

    private var running: some View {
        VStack(alignment: .leading, spacing: DemoraSpace.s) {
            DemoraSectionTitle(title: String(format: tr("Running monitors: %d of %d"),
                                             monitors.count, MonitoringBudget.maximum))
            VStack(alignment: .leading, spacing: DemoraSpace.xxs) {
                ForEach(monitors, id: \.self) { name in
                    Text(name)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Ink.inkSoft)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .textSelection(.enabled)
        }
    }

    /// Screen Time's activity list is synchronous XPC: read it off the main
    /// actor.
    private func reload() async {
        let names = await Task.detached(priority: .userInitiated) {
            DeviceActivityCenter().activities.map(\.rawValue).sorted()
        }.value
        failures = SharedStore.enforcementFailures
        monitors = names
        loaded = true
    }

    private func retry() {
        retrying = true
        Task {
            await ChangeEngine.ensureMonitoringOffMain()
            await ChangeEngine.housekeepingOffMain()
            model.refreshEnforcementStatus()
            await reload()
            retrying = false
        }
    }
}
