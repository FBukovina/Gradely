#!/usr/bin/env python3
"""Validate an Xcode-built Gradey.app's extracted Siri contracts and translations."""
import argparse
import json
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("app", type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
resources = args.app / "Contents/Resources" if (args.app / "Contents").exists() else args.app
metadata = json.loads((resources / "Metadata.appintents/extract.actionsdata").read_text())
strings = json.loads((root / "Gradely/Resources/Localizable.xcstrings").read_text())["strings"]
phrases = json.loads((root / "Gradely/Resources/AppShortcuts.xcstrings").read_text())["strings"]
expected = {"GradeyNextLessonIntent", "GradeyScheduleIntent", "GradeyGradesIntent",
            "GradeyFindPlannerIntent", "GradeyAddPlannerIntent", "GradeyOpenSubjectIntent"}
assert {s["actionIdentifier"] for s in metadata["autoShortcuts"]} == expected
for name, action in metadata["actions"].items():
    assert action["authenticationPolicy"] in (1, 2), f"Missing authentication: {name}"
    if action.get("assistantDefinedSchemas"):
        for platform in ("LNPlatformNameIOS", "LNPlatformNameMACOS"):
            assert action["availabilityAnnotations"][platform]["introducedVersion"] == "27", name
for name, entity in metadata["entities"].items():
    if entity.get("assistantDefinedSchemas"):
        for platform in ("LNPlatformNameIOS", "LNPlatformNameMACOS"):
            assert entity["availabilityAnnotations"][platform]["introducedVersion"] == "27", name
for name in ("GradeyGradeEntity", "GradeyIntelligenceGradeEntity"):
    assert not metadata["entities"][name].get("assistantDefinedSchemas"), "Grades must remain custom entities"
assert metadata["actions"]["GradeyCreateReminderIntent"]["assistantDefinedSchemas"][0]["domain"] == "reminders"

keys = set()
def visit(value):
    if isinstance(value, dict):
        for field in ("key", "formatString"):
            if isinstance(value.get(field), str):
                keys.add(value[field])
        for child in value.values():
            visit(child)
    elif isinstance(value, list):
        for child in value:
            visit(child)
visit(metadata)
for key in keys:
    if not key or key in {"%@", "%@ %@", "%@: %@"}:
        continue
    entry = phrases.get(key) or strings.get(key)
    assert entry is not None, f"Missing localized metadata: {key}"
    locales = {"en", "cs"} if key in phrases else {"en", "cs", "en-CO", "cs-US"}
    assert locales <= entry.get("localizations", {}).keys(), f"Incomplete localization: {key}"
print(f"Validated {len(metadata['actions'])} authenticated actions, six shortcuts, OS 27 schemas, and EN/CS/CO metadata.")
