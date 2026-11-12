#!/usr/bin/env python3
"""Publish only non-sensitive build status and a simulator screenshot, never signing data."""
import json
import os
import shutil
import sys
from pathlib import Path

output = Path(sys.argv[1])
errors = []
for filename in ("ios-build.log", "ios-device-build.log", "ios-ui-test.log"):
    path = Path(filename)
    if path.exists():
        errors.extend(line for line in path.read_text().splitlines() if "error:" in line)
screenshot = Path("artifacts/ios-clock.png")
previous = output / "ios-clock.png"
if previous.exists():
    previous.unlink()
if screenshot.exists():
    shutil.copyfile(screenshot, previous)
report = {
    "commit": os.environ["GITHUB_SHA"],
    "run": f'https://github.com/{os.environ["GITHUB_REPOSITORY"]}/actions/runs/{os.environ["GITHUB_RUN_ID"]}',
    "status": os.environ["BUILD_STATUS"],
    "simulator": os.environ.get("SIMULATOR_STATUS"),
    "device": os.environ.get("DEVICE_STATUS"),
    "launch": os.environ.get("LAUNCH_STATUS"),
    "uiTests": os.environ.get("UI_TEST_STATUS"),
    "errors": errors[:40],
    "screenshot": "ios-clock.png" if screenshot.exists() else None,
}
for filename in ("ios-launch.log", "ios-ui-test.log"):
    path = Path(filename)
    if path.exists() and report["status"] != "success":
        report[filename] = path.read_text().splitlines()[-70:]
        if filename == "ios-ui-test.log":
            lines = path.read_text().splitlines()
            report["uiFailureContexts"] = [lines[max(0, i - 18):i + 55] for i, line in enumerate(lines) if "error:" in line][:10]
ui_log = Path("ios-ui-test.log")
if ui_log.exists():
    report["uiTestSummary"] = [line for line in ui_log.read_text().splitlines()
                               if line.startswith("Test Case ") or ("Executed " in line and "tests" in line)]
previews = []
for index, path in enumerate(sorted(Path("artifacts/ios-ui-previews").rglob("*.png"))[:60]):
    name = f"ios-ui-preview-{index + 1}.png"
    shutil.copyfile(path, output / name)
    previews.append(name)
report["uiPreviews"] = previews
(output / "build.json").write_text(json.dumps(report, indent=2) + "\n")
(output / "README.md").write_text(
    "# LunkAlarm native iOS build\n\n"
    f'Commit: `{report["commit"]}`  \nStatus: **{report["status"]}**  \n'
    f'[Build and downloads]({report["run"]})\n\n'
    + ("![Native simulator launch](ios-clock.png)\n\n" if screenshot.exists() else "")
    + "This branch contains generated build reports only. Source lives on main under ios/. "
      "Device builds are unsigned and need provisioning before installation.\n"
)
