#!/usr/bin/env python3
"""Read-only project/entitlement and welcome-render regression checks.
Run: python3 Tests/ReleaseIsolationHarness.py
Not a signing validation or interactive iOS hang test.
"""
import json
import plistlib
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
project = json.loads(subprocess.check_output([
    "plutil", "-convert", "json", "-o", "-", str(ROOT / "Latch.xcodeproj/project.pbxproj")
]))["objects"]
targets = {item["name"]: item for item in project.values()
           if item.get("isa") == "PBXNativeTarget"}
expected = {
    "Latch": ("may.latch", "Latch/Latch"),
    "LatchMonitor": ("may.latch.monitor", "LatchMonitor/LatchMonitor"),
    "LatchShieldUI": ("may.latch.shieldui", "LatchShieldUI/LatchShieldUI"),
    "LatchReport": ("may.latch.LatchReport", "LatchReport/LatchReport"),
    "LatchWidgets": ("may.latch.widgets", "LatchWidgets/LatchWidgets"),
}
for name, (identifier, entitlement_base) in expected.items():
    configuration_ids = project[targets[name]["buildConfigurationList"]]["buildConfigurations"]
    configs = {project[item]["name"]: project[item]["buildSettings"] for item in configuration_ids}
    for configuration in ["Debug", "Release"]:
        debug = configuration == "Debug"
        settings = configs[configuration]
        bundle = identifier.replace("may.latch", "may.latch.dev", 1) if debug else identifier
        assert settings["PRODUCT_BUNDLE_IDENTIFIER"] == bundle, (name, configuration)
        entitlement = entitlement_base + ("Debug" if debug else "") + ".entitlements"
        assert settings["CODE_SIGN_ENTITLEMENTS"] == entitlement, (name, configuration)
        with (ROOT / entitlement).open("rb") as source:
            values = plistlib.load(source)
        assert values["com.apple.security.application-groups"] == [
            "group.com.may.screentimedelay" + (".dev" if debug else "")
        ], (name, configuration)
        if name == "Latch":
            assert settings["INFOPLIST_KEY_CFBundleDisplayName"] == ("dev demora" if debug else "demora")
            assert settings["ASSETCATALOG_COMPILER_APPICON_NAME"] == ("AppIconDev" if debug else "AppIcon")
    assert configs["Debug"]["PRODUCT_BUNDLE_IDENTIFIER"] != configs["Release"]["PRODUCT_BUNDLE_IDENTIFIER"]
for config in project.values():
    if config.get("isa") == "XCBuildConfiguration" and config.get("name") == "Release":
        flags = config["buildSettings"].get("SWIFT_ACTIVE_COMPILATION_CONDITIONS", "")
        assert "DEBUG" not in flags.split(), "Release compiles with dev data container"
with (ROOT / "Latch.xcodeproj/xcshareddata/xcschemes/Latch.xcscheme").open() as source:
    assert 'ArchiveAction\n      buildConfiguration = "Release"' in source.read()


def block(source, signature):
    start = source.index(signature)
    opening = source.index("{", start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


welcome = (ROOT / "Latch/RedesignWelcomeView.swift").read_text()
for name, helper in [("offersDayNight", "canSetUpInitialDayNight"),
                     ("offersMathReplacement", "canReplaceLegacyMath")]:
    getter = block(welcome, f"private var {name}:")
    assert f"{helper}(in: SharedStore.defaults," in getter
    assert "state: displayedState" in getter
    assert "loadState()" not in getter and ".set(" not in getter
assert "return model.state" in block(welcome, "private var displayedState:")
body = block(welcome, "var body:")
assert "loadState()" not in body.replace(block(body, "MathPhraseMigrationView(isDemo:"), "")
print("Release isolation: all five targets' names/IDs/groups/entitlements, archive configuration and snapshot-only welcome checks passed")
