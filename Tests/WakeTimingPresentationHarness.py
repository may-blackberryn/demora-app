#!/usr/bin/env python3
"""Source-level editor/localization checks, not an interactive iOS UI test."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
editor = (ROOT / "Latch/WakeTimingEditor.swift").read_text()
groups = (ROOT / "Latch/DayNightViews.swift").read_text()
limits = (ROOT / "Latch/WakeScheduleView.swift").read_text()
for control in ("startMinutes", "waitMinutes", "weekdays", "dayTimings", "latestMinutes"):
    assert f"@Binding var {control}" in editor
assert "ForEach(weekdays.sorted()" in editor
assert "dayTimings.removeValue(forKey: day)" in editor
assert "WakeTimingEditor(" in groups and "WakeTimingEditor(" in limits
assert "$draft.weekdayWakeTimings" in groups and "$schedule.dayTimings" in limits
assert "$draft.wakeLatestMinutes" in groups and "$schedule.latestMinutes" in limits
assert "latestMinutes: latestMinutes" in editor
assert ".setGroupWakeSchedule(" in limits
assert 'tr("Give each group its own daily wake-up tap and wait. These group gates begin at midnight;' not in limits
assert "timingsAreValid" in groups
assert 'if !model.state.limits.isEmpty {\n                    NavigationLink { WakeScheduleView() }' in groups
assert "NavigationLink { WakeBlockEditor() }" in groups
keys = [
    "Change wake-up schedule for %@",
    "Customize wake-up by day",
    "Days without custom times use the default start, wait and latest time above.",
    "A running wait keeps its deadline, but never extends past its configured latest wake-up time. Other blocks still apply.",
    "Give each limit or group its own wake-up start, wait and weekdays. One Wake up tap starts all eligible waits. Overlapping rules still apply.",
    "Sleep ends at the following wake-up start, using that day's custom time if set.",
    "Custom wake-up times by day",
]
keys += ["Set a latest wake-up time", "Wake blocking ends by", "Latest wake-up: %@",
         "At this time, this wake-up block ends even if you haven't tapped Wake up or its wait is still running.",
         "Choose a latest time after the wake-up day begins."]
placeholder = re.compile(r"%(?:\d+\$)?(?:@|d|f|s)")
files = list((ROOT / "Shared").glob("Localization*.swift"))
assert len(files) == 7
for path in files:
    entries = re.findall(r'^\s*"((?:[^"\\]|\\.)*)"\s*:\s*"((?:[^"\\]|\\.)*)",?\s*$', path.read_text(), re.M)
    for key in keys:
        values = [value for source, value in entries if source == key]
        assert len(values) == 1, (path.name, key, len(values))
        assert placeholder.findall(key) == placeholder.findall(values[0]), (path.name, key)
print("Shared wake editor/cutoff bindings, per-day defaults/reset, delay-gated navigation and 7-language localization/placeholder checks passed (source-level)")
