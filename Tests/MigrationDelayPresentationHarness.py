#!/usr/bin/env python3
"""Focused source contracts; does not build Swift or exercise interactive iOS UI."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


def source(path):
    return (ROOT / path).read_text()


def between(text, start, end):
    return text.split(start, 1)[1].split(end, 1)[0]


def configuration(text, debug):
    """Resolve this view's DEBUG branches for routing checks, not a Swift parser."""
    active = [True]
    result = []
    for line in text.splitlines():
        directive = line.strip()
        if directive == "#if DEBUG":
            active.append(active[-1] and debug)
        elif directive == "#else":
            active[-1] = active[-2] and not active[-1]
        elif directive == "#endif":
            active.pop()
        elif active[-1]:
            result.append(line)
    if len(active) != 1:
        raise AssertionError("Unbalanced conditional compilation")
    return "\n".join(result)


class MigrationDelayPresentationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.welcome = source("Latch/RedesignWelcomeView.swift")
        cls.offer = between(cls.welcome, "private var delaySetupOffer:",
                            "private var preservedRules:")
        cls.editor = between(source("Latch/DelayPolicyViews.swift"),
                             "struct DelayPolicySettingsView:", "\0")

    def test_optional_entry_does_not_commit_on_continue_or_finish(self):
        page = between(self.welcome, "private var navigationPage:",
                       "private var delaySetupOffer:")
        self.assertIn("delaySetupOffer", page)
        self.assertIn("If you skip this, your delay settings stay unchanged.", self.offer)
        self.assertIn("Countdowns already running keep their original deadline.", self.offer)
        # Only navigation is added to the welcome; there is no policy draft
        # committed by Continue, Done, or the existing migration waivers.
        for forbidden in (".setDelayPolicy", "model.queue", "model.state.delayPolicy =",
                          "completeInitialSetup", "model.setUp("):
            self.assertNotIn(forbidden, self.welcome)

    def test_real_route_reuses_ordinary_editor(self):
        release = configuration(self.offer, debug=False)
        self.assertIn("DelayPolicyNavigationRows()", release)
        self.assertNotIn("MigrationDelayPreviewView", release)
        rows = between(source("Latch/DelayPolicyViews.swift"),
                       "struct DelayPolicyNavigationRows:",
                       "struct DelayPolicySettingsView:")
        self.assertIn("NavigationLink { DelayPolicySettingsView() }", rows)
        self.assertIn("model.state.delayPolicy", rows)
        self.assertIn(".setDelayPolicy(policy.normalized)", self.editor)
        self.assertIn('Button(tr("Queue change"))', self.editor)
        self.assertIn("if model.queue(action) != nil { dismiss() }", self.editor)
        self.assertIn("policy = model.state.delayPolicy", self.editor)
        self.assertIn("policy.normalized != model.state.delayPolicy.normalized", self.editor)
        self.assertIn(".disabled(pending)", self.editor)

    def test_queue_uses_current_policy_and_only_appends_new_deadline(self):
        model = between(source("Latch/AppModel.swift"),
                        "func queue(_ action:", "func preview(_ action:")
        self.assertIn("ChangeEngine.queue(action)", model)
        queue = between(source("Shared/ChangeEngine.swift"),
                        "private static func queueCoordinated(",
                        "private static func isValidLimit(")
        self.assertIn("let direction = classify(action, state: state)", queue)
        self.assertIn("let delay = state.delayPolicy.delay(for: direction)", queue)
        self.assertIn("appliesAt: now.addingTimeInterval(delay)", queue)
        self.assertIn("state.pending.append(change)", queue)
        self.assertNotIn(".appliesAt =", queue)
        self.assertNotIn("state.delayPolicy =", queue)
        self.assertIn("policy.normalized != state.delayPolicy.normalized", queue)
        self.assertIn("guard !state.pending.contains", queue)

    def test_picker_exposes_all_three_modes_without_side_effects(self):
        picker = between(source("Latch/DelayPolicyViews.swift"),
                         "struct DelayPolicyPicker:",
                         "struct DelayPolicyNavigationRows:")
        self.assertIn("ForEach(DelayMode.allCases)", picker)
        modes = between(source("Shared/SharedModels.swift"),
                        "enum DelayMode:", "struct DelayPolicy:")
        self.assertIn("case separate, shared, lenientOnly", modes)
        for forbidden in ("model.", "SharedStore", "ChangeEngine", "UserDefaults",
                          "URLSession", ".task", ".onAppear"):
            self.assertNotIn(forbidden, picker)

    def test_demo_route_is_local_draft_not_live_editor(self):
        debug = configuration(self.offer, debug=True)
        demo_branch = between(debug, "if isDemo {", "} else {")
        self.assertIn("MigrationDelayPreviewView(policy: displayedState.delayPolicy)",
                      demo_branch)
        self.assertNotIn("DelayPolicyNavigationRows", demo_branch)
        self.assertNotIn("DelayPolicySettingsView", demo_branch)
        preview = between(self.welcome, "private struct MigrationDelayPreviewView:",
                          "#endif")
        self.assertIn("@State private var policy: DelayPolicy", preview)
        self.assertIn("_policy = State(initialValue: policy)", preview)
        self.assertIn("DelayPolicyPicker(policy: $policy)", preview)
        self.assertIn("DeveloperDemoNotice()", preview)
        for forbidden in ("@EnvironmentObject", "model.", "SharedStore", "ChangeEngine",
                          "UserDefaults", "URLSession", ".task", ".onAppear", "Button("):
            self.assertNotIn(forbidden, preview)
        self.assertNotIn("MigrationDelayPreviewView",
                         configuration(self.welcome, debug=False))

    def test_presentation_uses_published_or_demo_snapshot(self):
        snapshot = between(self.welcome, "private var displayedState:",
                           "private var isDemo:")
        self.assertIn("if let demoState { return demoState }", snapshot)
        self.assertIn("return model.state", snapshot)
        presentation = self.welcome.split("@MainActor private func saveDayNightIfNeeded", 1)[0]
        # The existing phrase save callback is allowed its explicit post-save
        # refresh; view getters and delay presentation must not decode storage.
        for forbidden in ("JSONDecoder", "data(forKey:", "SharedStore.save", "defaults.set"):
            self.assertNotIn(forbidden, presentation)
        self.assertNotIn("SharedStore", self.offer)


if __name__ == "__main__":
    unittest.main(verbosity=2)
