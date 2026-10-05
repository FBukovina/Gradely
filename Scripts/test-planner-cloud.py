#!/usr/bin/env python3
"""Compile real Planner/auth sources in a temporary macOS package without resolving app UI packages."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]

def segment(path, start, end):
    text = (ROOT / path).read_text()
    if text.count(start) != 1 or text.count(end) != 1:
        raise RuntimeError(f"Source boundary changed in {path}; review the focused harness")
    return text.split(start, 1)[1].split(end, 1)[0]

if sys.platform != "darwin":
    sys.exit("Run this focused Swift suite on macOS with the Xcode command-line tools.")

with tempfile.TemporaryDirectory(prefix="gradey-planner-tests-") as directory:
    package = Path(directory)
    source = package / "Sources/Gradely"
    tests = package / "Tests/GradelyTests"
    source.mkdir(parents=True)
    tests.mkdir(parents=True)
    (package / "Package.swift").write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "Gradely", platforms: [.macOS(.v14)], targets: [
    .target(name: "Gradely"), .testTarget(name: "GradelyTests", dependencies: ["Gradely"])
], swiftLanguageModes: [.v5])
''')
    for path in ["Platform/GradeyAuthClient.swift", "Platform/PlannerCloudClient.swift", "Stores/PlannerCloudPersistence.swift",
                 "Models/PlannerModels.swift", "Stores/PlannerPersistence.swift", "Stores/PlannerStore.swift", "Support/PlannerCalendarEventData.swift"]:
        (source / Path(path).name).symlink_to(ROOT / "Gradely" / path)
    for name in ["PlannerCloudTests.swift", "GradeyAuthClientTests.swift"]:
        (tests / name).symlink_to(ROOT / "GradelyTests" / name)
    # These declarations live beside unrelated provider types; extract current production source
    # at checked boundaries rather than copying account or Keychain implementations into the harness.
    stubs = (ROOT / "scripts/planner-cloud-harness/Stubs.swift").read_text()
    stubs += "\nimport Foundation\nimport Security\n"
    stubs += segment("Gradely/Platform/GradeyAccountModels.swift", "import Foundation", "enum LinkedAccountProvider")
    stubs += "\nstruct KeychainClient" + segment("Gradely/Stores/SessionStore.swift", "struct KeychainClient", "final class InMemorySessionStore")
    stubs += "\nextension PreviewData {" + segment("Gradely/Platform/PreviewData+GradeyID.swift", "extension PreviewData {", "    static let linkedSchoolAccount") + "\n}\n"
    (source / "HarnessDependencies.swift").write_text(stubs)
    command = ["swift", "test", "--package-path", str(package)]
    if os.environ.get("GRADEY_PLANNER_TEST_SCRATCH"):
        command += ["--scratch-path", os.environ["GRADEY_PLANNER_TEST_SCRATCH"]]
    subprocess.run(command, check=True)
