#!/usr/bin/env python3
"""Actual pure welcome routing and UI safety contracts, not interactive iOS tests."""
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
presentation = (ROOT / 'Latch/SetupPresentation.swift').read_text()
driver = r'''
import Foundation
var checks = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) {
    precondition(value(), message); checks += 1
}
for math in [false, true] {
    for dayNight in [false, true] {
        let pages = WelcomePages.make(offersMath: math, offersDayNight: dayNight)
        check(pages == (dayNight ? [.rules, .dayNight, .changes] : [.rules, .changes]), "page list")
        check(Set(pages).count == pages.count, "no duplicate page")
        check(WelcomePages.previous(before: .rules, in: pages) == nil, "no Back from first")
        check(WelcomePages.next(after: .changes, in: pages) == nil, "final completes")
        check(WelcomePages.next(after: .rules, in: pages) == (dayNight ? .dayNight : .changes), "first Continue")
        check(WelcomePages.previous(before: .changes, in: pages) == (dayNight ? .dayNight : .rules), "final Back")
    }
}
let afterSave = WelcomePages.make(offersMath: false, offersDayNight: false)
check(WelcomePages.previous(before: .dayNight, in: afterSave) == .rules, "Back after offer changes")
check(WelcomePages.next(after: .dayNight, in: afterSave) == nil, "never advance a stale index")
print("Setup/welcome presentation: \(checks) pure identity/offer/routing checks passed")
'''
with tempfile.TemporaryDirectory(prefix='demora-setup-presentation-') as directory:
    folder = Path(directory)
    (folder / 'SetupPresentation.swift').write_text(presentation)
    (folder / 'main.swift').write_text(driver)
    binary = folder / 'checks'
    subprocess.run(['swiftc', str(folder / 'SetupPresentation.swift'), str(folder / 'main.swift'),
                    '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)

setup = (ROOT / 'Latch/OnboardingView.swift').read_text().split('// MARK: - Onboarding override config sheet')[0]
welcome = (ROOT / 'Latch/RedesignWelcomeView.swift').read_text()
assert 'total: 5' in setup and 'step == 4 ? tr("Start using Demora")' in setup
assert 'case 5:' not in setup and 'case 6:' not in setup
assert setup.count('await model.requestAuthorization()') == 1
assert 'if authTried {\n                move(to: 3)' in setup
assert 'if step == 2 || step == 4 { return }' in setup, 'beta notice never shares a permission or commit tap'
for forbidden in ('openSettingsURLString', 'UIApplication.shared.open', 'model.queue(', 'beginTutorial'):
    assert forbidden not in setup
assert 'Text(tr("Permissions"))' in setup
assert 'Demora needs Screen Time access to set limits and block apps, and notifications to tell you when a pending change is ready. iOS will ask for each.' in setup
assert "That's okay. Without Screen Time access Demora can't block apps, but you can continue and turn it on later." in setup
assert '5...720, step: 5' in setup and 'wantsLimit && !hasSelection' in setup
assert 'dayNightGroups: chosenDayNight' in setup and 'overrides: chosenOverrides' in setup
assert 'if saved, let chosenEstimate { WeeklyUsageEstimate.save' in setup
assert setup.index('demo.onComplete') < setup.index('await model.completeInitialSetup')
assert 'StateChip(kind: .free, text: tr("Allowed"))' in setup
assert 'WeeklyUsageEstimateDraft(enabled: $enabled, minutes: $minutes)' in setup
assert '@State private var expanded = false' in setup and 'DisclosureGroup(isExpanded: $expanded)' in setup
assert 'WelcomePages.make(offersMath: offersMathReplacement, offersDayNight: offersDayNight)' in welcome
assert '@State private var page: WelcomePage = .rules' in welcome
assert 'if await saveDayNightIfNeeded() { page = .changes }' in welcome
assert welcome.count('\n            mathReplacementOffer\n') == 1
assert 'if page == .changes { complete(); return }' in welcome
assert 'Button(tr("Skip")) { complete() }' in welcome
assert welcome.index('guard await saveDayNightIfNeeded()') < welcome.index('onComplete()', welcome.index('private func complete()'))
assert 'model.selectedTab = 0' in welcome
assert 'defaults.set(' not in welcome and 'SharedStore.save' not in welcome
assert 'SetupEstimateDisclosure(' in welcome and 'WeeklyUsageEstimateDraft(' not in welcome
print('Setup UI contracts: five steps, unchanged permission/commit path, draft extras, optional estimate, identity-based migration and single math offer passed')

string = r'"((?:[^"\\]|\\.)*)"'
keys = set(re.findall(r'\btr\(' + string + r'\)', setup + welcome
                     + (ROOT / 'Latch/RedesignIntroView.swift').read_text()
                     + (ROOT / 'Latch/MathPhraseMigrationView.swift').read_text()))
entry = re.compile(r'(?:^|,)\s*' + string + r'\s*:\s*' + string + r'\s*(?=,|$)', re.M)
for suffix in ['', '+German', '+French', '+Portuguese', '+Polish', '+Turkish', '+Hindi']:
    pairs = entry.findall((ROOT / f'Shared/Localization{suffix}.swift').read_text())
    table = dict(pairs)
    assert len(table) == len(pairs), (suffix, 'duplicate localization key')
    assert not keys - table.keys(), (suffix, 'untranslated setup copy', keys - table.keys())
    for key in keys:
        for placeholder in ('%@', '%d'):
            assert key.count(placeholder) == table[key].count(placeholder), (suffix, key, placeholder)
print(f'Setup/intro/welcome/math localization: {len(keys)} keys × seven catalogs passed')
