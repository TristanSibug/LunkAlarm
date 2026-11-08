#!/usr/bin/env python3
"""Start a clean CI iPhone with a visible Simulator process and bounded retries."""
import json
import os
import subprocess
import sys
import time
from pathlib import Path

def run(*args, timeout=40, capture=False):
    print("+ " + " ".join(args), flush=True)
    return subprocess.run(args, check=True, text=True, timeout=timeout,
                          stdout=subprocess.PIPE if capture else None)

def data(*args):
    return json.loads(run("xcrun", "simctl", *args, "--json", capture=True).stdout)

runtime = next(r["identifier"] for r in reversed(data("list", "runtimes")["runtimes"])
               if "iOS-26" in r["identifier"] and r.get("isAvailable", False))
types = data("list", "devicetypes")["devicetypes"]
phone_type = next((t["identifier"] for t in types if t["name"] == "iPhone 16"),
                  next(t["identifier"] for t in types if t["name"].startswith("iPhone")))
developer = run("xcode-select", "-p", capture=True).stdout.strip()
simulator = str(Path(developer) / "Applications/Simulator.app")

for attempt in range(2):
    try:
        device = run("xcrun", "simctl", "create", "LunkAlarm-CI-" + str(attempt), phone_type, runtime, capture=True).stdout.strip()
        run("open", simulator, "--args", "-CurrentDeviceUDID", device, timeout=20)
        run("xcrun", "simctl", "bootstatus", device, "-b", timeout=150)
        with open(os.environ["GITHUB_ENV"], "a") as output:
            output.write("LUNK_IOS_SIMULATOR_ID=" + device + "\n")
        print("Simulator ready: " + device, flush=True)
        sys.exit(0)
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        print("Simulator attempt failed: " + str(error), flush=True)
        # This is an isolated hosted runner; restarting its simulator service does
        # not affect a developer's local devices or the application under test.
        for process in ("Simulator", "com.apple.CoreSimulator.CoreSimulatorService"):
            subprocess.run(["killall", process], check=False, timeout=15)
        time.sleep(3)
raise SystemExit("The hosted simulator could not boot after two attempts.")
