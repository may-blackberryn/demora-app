#!/usr/bin/env python3
"""Source routing contracts for Rules/Today after the four-tab switch.

Checks live replacements, not deleted tutorial/list pages. No interactive iOS
navigation, Screen Time access, network request or saved-state write.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / "Latch/SchedulesView.swift").read_text()
rules = (ROOT / "Latch/RulesView.swift").read_text()
home = (ROOT / "Latch/HomeView.swift").read_text()
summary = (ROOT / "Latch/RuleSummarySheet.swift").read_text()
editors = (ROOT / "Latch/RuleEditors.swift").read_text()
presentation = (ROOT / "Latch/RulesPresentation.swift").read_text()
day_night = (ROOT / "Latch/DayNightViews.swift").read_text()

for retired in ("struct SchedulesView:", "struct SessionsListView:",
                "struct PlannedListView:", "struct RecurringListView:",
                "struct ScheduledItemDetailView:", "TutorialScheduleEditorView",
                "tutorialHighlight", "model.tutorial", "model.inTutorial"):
    assert retired not in source, retired

editor_routes = rules.split("private func editor(for kind:", 1)[1].split("private func destination", 1)[0]
for route in ("case .blockNow: SessionStartView()", "case .repeating: ScheduleEditorView()",
              "case .planned: PlannedEditorView()", "case .dayNight: DayNightQueuedEditor("):
    assert route in editor_routes, ("New rule keeps each schedule kind reachable", route)
assert 'Button { showSession = true }' in home and 'SessionStartView()' in home
assert 'case .calendar: CalendarView(onSeeChange:' in rules
assert 'CalendarView(onSeeChange:' in home and 'showCalendar = false' in home
assert '.ruleSummary($summary)' in source and 'RuleSummaryRequest(ref: e.ref)' in source
for ref in ('.schedule(s.id)', '.exemption(e.id)', '.planned(w.id)', '.session(s.id)'):
    assert ref in source, ('Calendar uses the real rule identity', ref)

# Free periods remain kinds, not an obsolete top-level destination.
assert 'Text(tr("Free")).tag(SessionKind.free)' in editors
assert 'Picker(tr("Type"), selection: $isFree)' in editors
assert 'case .exemption(let id)' in summary and 'state.exemptions' in summary
assert 'case .session(let id)' in summary and 'state.sessions' in summary
assert '.endSessionEarly(id: id)' in summary and '.changeReceipt($receipt)' in summary
assert 'case .exemption: return .freePeriod' in presentation
assert 'case .session, .queuedSession: return .session' in presentation
# The Day & night and Group wake-up list pages are retired at the four-tab
# switch (rules spec R1/R7); their rules stay reachable from the summary sheet.
assert 'struct DayNightSchedulesView' not in day_night and 'WakeScheduleView' not in day_night
assert 'struct WakeScheduleView' not in (ROOT / "Latch/WakeScheduleView.swift").read_text()
assert 'case .legacyWake: WakeBlockEditor(presentation: .sheet)' in summary
assert 'case .legacySleep: SleepBlockEditor(presentation: .sheet)' in summary
assert 'GroupWakeDelayEditor(limitID: id)' in summary
assert 'receipt = ChangeReceiptRequest(action: .removeDayNightGroup(id: id))' in summary

calendar = source.split('struct CalendarView: View {', 1)[1]
for forbidden in ('model.queue', 'SharedStore.save', 'ChangeEngine.', 'ShieldController.'):
    assert forbidden not in calendar + editor_routes, forbidden
# Calendar restyle (rules spec §5.8): tokens only, full touch targets.
for token in ('.paperCard()', '.paperCard(padding: 0)', '.demoraType(.cardTitle)', 'Ink.inkSoft', 'DemoraSpace.'):
    assert token in calendar, ('calendar uses redesign tokens', token)
for retired_style in ('.demoraSurface()', 'design: .monospaced', 'DemoraSectionTitle', 'GridCard('):
    assert retired_style not in calendar, ('calendar keeps no pre-redesign styling', retired_style)
assert calendar.count('.frame(minWidth: 44, minHeight: 44)') == 2, 'month arrows keep 44 pt targets'
assert 'minHeight: max(44, dayControlSize)' in calendar and 'ViewThatFits(in: .horizontal)' in calendar, \
    'day cells keep 44 pt targets and scroll rather than shrink at large text'
assert '.accessibilityAddTraits(isSel ? [.isSelected] : [])' in calendar
print('Schedule routing: Rules editors, Today Block now, Calendar summaries and restyle, free periods and delayed session removal passed')
