#!/usr/bin/env python3
"""Source-only Guide checks; no build, device access, or enforcement simulation.

Use --new-keys for the exact Guide English keys missing from the current Spanish
localization catalog. This list shrinks as the root adds translations.
"""
import json
from pathlib import Path
import re
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
SETTINGS = (ROOT / "Latch/SettingsView.swift").read_text()
GUIDE = SETTINGS.split("// MARK: - Guide\n", 1)[1].split("// MARK: - Contact\n", 1)[0]
LITERAL = r'"(?:[^"\\]|\\.)*"'


def literals(pattern, source):
    return [json.loads(value) for value in re.findall(pattern, source)]


KEYS = literals(r'\btr\((' + LITERAL + r')\)', GUIDE)
TOPICS = dict(re.findall(
    r'GuideTopic\(\s*id: "([^"\n]+)"(.*?)(?=\n            GuideTopic\(|\n        \])',
    GUIDE, re.S))


class GuideContentTests(unittest.TestCase):
    def test_topics_and_navigation(self):
        self.assertEqual(set(TOPICS), {
            "delays", "limits", "daynight", "schedules", "conflicts",
            "overrides", "usage", "troubleshooting", "notifications"})
        ids = re.findall(r'\bid: "([^"\n]+)"', GUIDE)
        self.assertEqual(len(ids), len(set(ids)))
        self.assertIn("NavigationLink { GuideView() }", SETTINGS)
        self.assertIn("ForEach(topics)", GUIDE)
        self.assertIn("NavigationLink { GuideTopicView(topic: topic) }", GUIDE)
        self.assertIn("ForEach(topic.sections.indices, id: \\.self)", GUIDE)
        self.assertIn(".accessibilityAddTraits(.isHeader)", GUIDE)
        for topic in TOPICS.values():
            self.assertGreaterEqual(topic.count("GuideSection("), 2)
        # Every path named by the guide still has a destination surface.
        sources = "\n".join((ROOT / path).read_text() for path in [
            "Latch/SchedulesView.swift", "Latch/DayNightViews.swift",
            "Latch/ScheduleConflictsView.swift", "Latch/LimitsView.swift"])
        for label in ["Sessions", "Day & night", "Calendar", "Now", "Planned",
                      "Recurring", "Schedule conflicts", "Recheck blocked limits",
                      "New limit"]:
            self.assertTrue(f'"{label}"' in sources, f"Missing destination: {label}")
        self.assertIn("UsageInsightsView()", (ROOT / "Latch/HomeView.swift").read_text())
        usage = (ROOT / "Latch/UsageInsightsView.swift").read_text()
        self.assertIn('tr("Edit weekly estimate")', usage)
        self.assertIn("value: -28, to: today", usage)

    def test_localized_nonempty_content(self):
        fields = re.findall(r'\b(?:title|summary|body):\s*([^\n]+)',
                            "\n".join(TOPICS.values()))
        self.assertTrue(fields)
        for field in fields:
            self.assertTrue(field.startswith("tr("), field)
        self.assertTrue(all(key.strip() for key in KEYS))
        self.assertNotIn("Text(\"", GUIDE)
        self.assertNotIn("GridCard(title: \"", GUIDE)
        for topic in TOPICS.values():
            bodies = literals(r'body: tr\((' + LITERAL + r')\)', topic)
            self.assertTrue(all(len(body.split()) <= 100 for body in bodies))

    def test_replay_is_not_exposed(self):
        for obsolete in ["replayTutorial", "replayFailed", "Replay walkthrough",
                         "Couldn't start the walkthrough", ".alert("]:
            self.assertNotIn(obsolete, GUIDE)
        model = (ROOT / "Latch/AppModel.swift").read_text()
        self.assertIn("func replayTutorial()", model)  # recovery engine retained

    def test_delay_and_limit_invariants(self):
        for phrase in ["separate waits", "one shared wait", "immediate tightening",
                       "current policy, not the new one", "keep their deadlines",
                       "Background application depends on iOS callbacks"]:
            self.assertIn(phrase, TOPICS["delays"])
        for phrase in ["tap New limit", "Different limits by weekday", "three portions",
                       "two-portion", "carryover", "does not give it a fresh",
                       "Selection edits follow the less-strict delay",
                       "five ordered uses", "app-usage minutes",
                       "only after the full daily budget", "reset at midnight",
                       "does not skip an early split portion"]:
            self.assertIn(phrase, TOPICS["limits"])

    def test_wake_sleep_and_scoped_priority(self):
        for phrase in ["per-weekday", "does not restart", "latest wake-up time",
                       "ends only that wake gate", "does not end sleep blocking",
                       "following morning", "running wait's deadline",
                       "new wait applies to the next tap", "once it applies",
                       "whole-category exceptions are not supported"]:
            self.assertIn(phrase, TOPICS["daynight"])
        for phrase in ["wake/sleep → recurring → planned → sessions",
                       "only within their scope", "not a global unblock",
                       "does not reset daily usage", "uncertain",
                       "Both actions always queue a less-strict change",
                       "last one promoted applies last"]:
            self.assertIn(phrase, TOPICS["conflicts"])
        for phrase in ["Now, Planned or Recurring", "duration starts when it takes effect",
                       "Screen Time checkpoints", "not the same as free usage",
                       "less-strict delay"]:
            self.assertIn(phrase, TOPICS["schedules"])

    def test_override_permissions_and_honest_troubleshooting(self):
        for phrase in ["named passwords and phrases", "own allowed uses",
                       "secret-only change", "not an immediate permissions change",
                       "separately for each contact", "Extra-time permission is opt-in",
                       "enter the short code", "eligible request's wait"]:
            self.assertIn(phrase, TOPICS["overrides"])
        for phrase in ["respects denial", "does not automatically redirect",
                       "not an unbypassable guarantee", "blank Screen Time report",
                       "around 30 seconds", "keeps current blocks in place",
                       "not a bypass", "failed or interrupted", "iOS 17.4"]:
            self.assertIn(phrase, TOPICS["troubleshooting"])
        for obsolete in ["can't be quietly bypassed", "Demora has two delays",
                         "the most specific one wins", "Every change waits out"]:
            self.assertNotIn(obsolete, GUIDE)

    def test_reports_and_privacy(self):
        for phrase in ["Home → Usage & trends", "four complete seven-day periods",
                       "today's partial day shown separately",
                       "recent history provided by iOS, not a permanent archive",
                       "not zero usage", "Edit weekly estimate", "per week, not per day",
                       "its date shows when it was recorded", "your own estimate",
                       "not a measured historical", "other devices of the same kind"]:
            self.assertIn(phrase, TOPICS["usage"])
        self.assertNotIn("everlasting", GUIDE)
        self.assertNotIn("being added", TOPICS["usage"])
        self.assertNotIn("tap +", TOPICS["limits"])
        for phrase in ["five-minute", "longer than five minutes", "suppressed during free periods",
                       "read-only", "small local summary", "stay on-device",
                       "CloudKit or Cloudflare and Resend", "readable message and code",
                       "Apple's website", "App Attest", "not the enforcement mechanism"]:
            self.assertIn(phrase, TOPICS["notifications"])
        self.assertNotIn("no data sharing", GUIDE)
        self.assertNotIn("no data collection", GUIDE)


def new_keys():
    catalog = (ROOT / "Shared/Localization.swift").read_text()
    existing = {json.loads(value) for value in re.findall(
        r'^\s*(' + LITERAL + r')\s*:', catalog, re.M)}
    return list(dict.fromkeys(key for key in KEYS if key not in existing))


if __name__ == "__main__":
    if sys.argv[1:] == ["--new-keys"]:
        print("NEWKEYS=" + json.dumps(new_keys(), ensure_ascii=False, indent=2))
    else:
        unittest.main()
