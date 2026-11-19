"""Publish only installers built successfully from this exact main commit."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
from zipfile import ZipFile


def gh(*args):
    return subprocess.check_output(["gh", *args], text=True).strip()


def successful_run(workflow):
    runs = json.loads(gh("run", "list", "--workflow", workflow, "--branch", "main",
                         "--event", "push", "--commit", os.environ["GITHUB_SHA"],
                         "--status", "success", "--limit", "10",
                         "--json", "databaseId,headSha,conclusion"))
    matches = [r for r in runs if r["headSha"] == os.environ["GITHUB_SHA"] and r["conclusion"] == "success"]
    if not matches:
        raise RuntimeError(f"Wait for {workflow} to succeed on this exact commit, then rerun this release job.")
    return str(matches[0]["databaseId"])


def single_file(folder, filename):
    matches = list(folder.rglob(filename))
    if len(matches) != 1:
        raise RuntimeError(f"Expected exactly one {filename}; found {len(matches)}")
    return matches[0]


def main():
    tag = os.environ["RELEASE_TAG"]
    match = re.fullmatch(r"lunkalarm-v(\d+\.\d+\.\d+)", tag)
    if not match:
        raise RuntimeError("Use a unified release tag such as lunkalarm-v1.10.0.")
    version = match[1]
    android_version = re.search(r'versionName\s*=.*\?:\s*"([^"]+)"', Path("android/app/build.gradle.kts").read_text())[1]
    ios_version = re.search(r'"MARKETING_VERSION": "([^"]+)"', Path("ios/scripts/generate_project.py").read_text())[1]
    if version != android_version or version != ios_version:
        raise RuntimeError("Release tag and both native app versions must match.")

    # Website checks and both native builds must have succeeded at the same SHA.
    successful_run("web.yml")
    runs = {platform: successful_run(f"{platform}.yml") for platform in ("android", "ios")}
    inputs = Path("release-input")
    for platform, run in runs.items():
        artifact = "LunkAlarm-Android" if platform == "android" else "LunkAlarm-iOS"
        gh("run", "download", run, "--name", artifact, "--dir", str(inputs / platform))

    apk = single_file(inputs / "android", f"LunkAlarm-Android-{version}.apk")
    ipa = single_file(inputs / "ios", f"LunkAlarm-iOS-{version}-unsigned.ipa")
    expected = (apk.parent / "SHA256SUMS.txt").read_text().split()
    if len(expected) != 2 or expected[1] != apk.name or hashlib.sha256(apk.read_bytes()).hexdigest() != expected[0]:
        raise RuntimeError("APK checksum does not match the signed build artifact.")
    with ZipFile(apk) as package:
        if not {"AndroidManifest.xml", "classes.dex"}.issubset(package.namelist()):
            raise RuntimeError("The Android artifact is not an app APK.")
    with ZipFile(ipa) as package:
        info = plistlib.loads(package.read("Payload/LunkAlarm.app/Info.plist"))
        if info["CFBundleShortVersionString"] != version or info["CFBundleIdentifier"] != "online.reeeserve.LunkAlarm":
            raise RuntimeError("The IPA has an unexpected app identity or version.")

    assets = Path("release-assets")
    assets.mkdir()
    files = [assets / item.name for item in (apk, ipa)]
    for source, target in zip((apk, ipa), files):
        shutil.copyfile(source, target)
    checksums = assets / "SHA256SUMS.txt"
    checksums.write_text("".join(f"{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n" for p in files))
    notes = Path("RELEASE_NOTES.md").read_text()
    if not notes.startswith(f"# LunkAlarm {version} "):
        raise RuntimeError("Release notes do not match the tagged version.")
    title = notes.splitlines()[0].removeprefix("# ")
    print(gh("release", "create", tag, *map(str, files), str(checksums), "--verify-tag",
             "--title", title, "--notes-file", "RELEASE_NOTES.md", "--latest"))


if __name__ == "__main__":
    main()
