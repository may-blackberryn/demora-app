#!/usr/bin/env python3
"""Structural UI/side-effect checks. Runtime setup validation is exercised by
RedesignMigrationHarness.py, not mocked here. These are not on-device UI tests.
Run: python3 Tests/OnboardingOverridesHarness.py
"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def block(source, signature):
    start = source.index(signature)
    opening = source.index("{", start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


onboarding = (ROOT / "Latch/OnboardingView.swift").read_text()
draft = (ROOT / "Latch/OnboardingOverridesDraftView.swift").read_text()
password = block((ROOT / "Latch/SettingsView.swift").read_text(), "struct PasswordPolicyEditor:")
phrase = block((ROOT / "Latch/PhraseOverrides.swift").read_text(), "struct PhrasePolicyEditor:")
contacts = block((ROOT / "Latch/ContactsOverrideViews.swift").read_text(), "struct AddContactView:")
delays = block((ROOT / "Latch/DelayPolicyViews.swift").read_text(), "struct DelayPolicyNavigationRows:")
model = block((ROOT / "Latch/AppModel.swift").read_text(), "func completeInitialSetup(")
welcome = (ROOT / "Latch/MathPhraseMigrationView.swift").read_text()

assert "total: 7" in onboarding and "case 5: overridesStep" in onboarding
assert 'step == 6 ? tr("Start using Demora")' in onboarding
assert "overrides: chosenOverrides" in onboarding
complete = block(onboarding, "private func continueSetup()")
assert complete.index("demo.onComplete") < complete.index("model.completeInitialSetup")
assert "dayNightGroups, overrides)" in complete
assert "overrides.isValidInitialSetup" in model
assert model.index("!SharedStore.loadState().isSetUp") < model.index("setup.overrides = overrides")
assert model.index("setup.overrides = overrides") < model.index("SharedStore.save(setup)")
for forbidden in ["model.queue", "SharedStore.", "ContactsRelay.", "EmailCodeService."]:
    assert forbidden not in draft, forbidden
assert "existingContacts: overrides.contacts, isDemo: isDemo" in draft
assert "accepted: false, inviteId: inviteId, allowed: allowed" in contacts
assert "let contacts = onAdd == nil ? model.state.overrides.contacts : existingContacts" in contacts
assert "guard isDemo || code != ContactsRelay.myCode" in contacts
assert "if !tutorialMode && !isDemo" in contacts
assert "if !isDemo && !tutorialMode && EmailCodeService.isConfigured" in contacts
for editor in [password, phrase]:
    assert "if let onStage {" in editor and "onStage(policy)" in editor
    assert "if let existing, onStage == nil" in editor
    assert "guard !loaded else { return }" in editor
assert "AppModel.hash(password)" in password
assert "allowsExtraTimeWhenStaging = false" in phrase
assert draft.count("allowsExtraTimeWhenStaging: true") == 2
assert "allowsExtraTimeWhenStaging: true" not in welcome
row = block(delays, "HStack(alignment: .top, spacing: 14)")
assert 'tr("More strict")' in row and 'tr("Less strict")' in row
assert row.count("NavigationLink") == 2 and row.count(".frame(maxWidth: .infinity") == 2
assert 'policy.mode != .shared' in row and 'tr("Immediately")' in row

keys = set(re.findall(r'tr\("([^"\n]+)"\)', block(onboarding, "private var overridesStep:")))
for name in ["Localization.swift", *[f"Localization+{language}.swift" for language in
             ["German", "French", "Portuguese", "Polish", "Turkish", "Hindi"]]]:
    source = (ROOT / "Shared" / name).read_text()
    for key in keys:
        assert source.count(f'"{key}":') == 1, (name, key)

print("Onboarding overrides: draft/consent/demo/secret/migration/localization and side-by-side delay source checks passed")
