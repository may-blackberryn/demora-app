#!/usr/bin/env python3
"""Source-level routing checks, not an interactive SwiftUI navigation test."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / "Latch/SchedulesView.swift").read_text()
root = source[:source.index("// MARK: - Overview model")]
destinations = root[root.index("    private var scheduleDestinations"):
                    root.index("    private func schedulePage")]
sessions = root[root.index("    private var sessionsIndex"):
                root.index("    private var calendarIndex")]
day_night = (ROOT / "Latch/DayNightViews.swift").read_text()
calendar = root[root.index("    private var calendarIndex"):]

for old_tabs in ("ScheduleSection", "selectedSection", "sectionSelector", "selectTutorialSection"):
    assert old_tabs not in root, old_tabs
assert 'schedulePage(title: tr("Sessions")) { sessionsIndex }' in destinations
assert 'DayNightSchedulesView()' in destinations
assert "calendarIndex" in destinations
assert all(view in sessions for view in ("SessionsListView()", "PlannedListView()",
                                         "RecurringListView()"))
assert "ExemptionsListView" not in source and "RecurringSessionChoiceView" not in source
assert 'tr("Free periods")' not in sessions + destinations
assert 'case .recurring: ScheduleEditorView()' in root
# Free periods are still a session kind and recurring editor option. Existing
# recurring exemptions remain in Recurring, not a redundant top-level menu.
assert 'Text(tr("Free")).tag(SessionKind.free)' in source
assert 'Picker(tr("Type"), selection: $isFree)' in source
assert 'ForEach(model.state.exemptions)' in source
assert "WakeScheduleView()" in day_night and "SleepBlockEditor()" in day_night
assert "CalendarView()" in calendar and "embedded" not in source
assert "overviewSection" in root and 'Label(tr("New session")' in root
assert all(kind in root for kind in ("newSession = .now", "newSession = .planned",
                                     "newSession = .recurring"))
# The tutorial retains its direct Recurring and Calendar links, and no new
# model action, queue, or timer mutation is introduced in the navigation hub.
assert "if model.inTutorial {\n                        // Keep the practice" in root
assert 'model.tutorial == .removeSchedule' in sessions
assert 'model.tutorial == .exploreCalendar' in calendar
assert 'model.tutorialScreen == "schedulesRoot"' in sessions + calendar
for forbidden in ("model.queue", "SharedStore.save", "ChangeEngine.", "ShieldController."):
    assert forbidden not in destinations + calendar, forbidden
print("Schedules single-page hub, nested session lists, unchanged quick actions and tutorial routing: source checks passed")
