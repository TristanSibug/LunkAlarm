import importlib.util
import json
import os
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch
from zipfile import ZipFile
import hashlib

spec = importlib.util.spec_from_file_location("publish_release", Path(__file__).parents[1] / "publish_release.py")
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)


class ReleaseIntegrityTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        previous = Path.cwd()
        os.chdir(self.temp.name)
        self.addCleanup(os.chdir, previous)
        self.env = patch.dict(os.environ, {"RELEASE_TAG": "lunkalarm-v1.10.0", "GITHUB_SHA": "current-commit"})
        self.env.start()
        self.addCleanup(self.env.stop)
        Path("android/app").mkdir(parents=True)
        Path("ios/scripts").mkdir(parents=True)
        Path("android/app/build.gradle.kts").write_text('versionName = providers.gradleProperty("lunkVersionName").orNull ?: "1.10.0"')
        Path("ios/scripts/generate_project.py").write_text('"MARKETING_VERSION": "1.10.0"')
        Path("RELEASE_NOTES.md").write_text("# LunkAlarm 1.10.0 — Alarm Editing Fix\n")
        self.commands = []
        self.build_sha = "current-commit"
        self.bad_checksum = False
        self.ipa_version = "1.10.0"
        self.cli = patch.object(publisher, "gh", side_effect=self.gh)
        self.cli.start()
        self.addCleanup(self.cli.stop)

    def gh(self, *args):
        self.commands.append(args)
        if args[:2] == ("run", "list"):
            return json.dumps([{"databaseId": 1, "headSha": self.build_sha, "conclusion": "success"}])
        if args[:2] == ("run", "download"):
            folder = Path(args[args.index("--dir") + 1])
            folder.mkdir(parents=True)
            if "LunkAlarm-Android" in args:
                apk = folder / "LunkAlarm-Android-1.10.0.apk"
                with ZipFile(apk, "w") as archive:
                    archive.writestr("AndroidManifest.xml", b"manifest")
                    archive.writestr("classes.dex", b"classes")
                digest = "invalid" if self.bad_checksum else hashlib.sha256(apk.read_bytes()).hexdigest()
                (folder / "SHA256SUMS.txt").write_text(f"{digest}  {apk.name}\n")
            else:
                info = {"CFBundleShortVersionString": self.ipa_version, "CFBundleIdentifier": "online.reeeserve.LunkAlarm"}
                with ZipFile(folder / "LunkAlarm-iOS-1.10.0-unsigned.ipa", "w") as archive:
                    archive.writestr("Payload/LunkAlarm.app/Info.plist", plistlib.dumps(info))
            return ""
        if args[:2] == ("release", "create"):
            return "https://github.com/example/repo/releases/tag/lunkalarm-v1.10.0"
        raise AssertionError(args)

    def assert_not_published(self):
        self.assertFalse(any(c[:2] == ("release", "create") for c in self.commands))

    def test_never_uses_builds_from_a_different_commit(self):
        self.build_sha = "other-commit"
        with self.assertRaisesRegex(RuntimeError, "exact commit"):
            publisher.main()
        self.assert_not_published()

    def test_does_not_publish_when_native_versions_disagree(self):
        Path("ios/scripts/generate_project.py").write_text('"MARKETING_VERSION": "1.9.1"')
        with self.assertRaisesRegex(RuntimeError, "versions must match"):
            publisher.main()
        self.assert_not_published()

    def test_rejects_corrupt_apk(self):
        self.bad_checksum = True
        with self.assertRaisesRegex(RuntimeError, "checksum"):
            publisher.main()
        self.assert_not_published()

    def test_rejects_old_ipa_even_if_filename_matches(self):
        self.ipa_version = "1.9.1"
        with self.assertRaisesRegex(RuntimeError, "unexpected app identity or version"):
            publisher.main()
        self.assert_not_published()

    def test_publishes_two_installers_and_checksums_in_one_release(self):
        publisher.main()
        calls = [c for c in self.commands if c[:2] == ("release", "create")]
        self.assertEqual(len(calls), 1)
        files = [p for p in Path("release-assets").iterdir()]
        self.assertEqual({p.suffix for p in files}, {".apk", ".ipa", ".txt"})
        self.assertIn("--verify-tag", calls[0])
        self.assertIn("--latest", calls[0])


if __name__ == "__main__":
    unittest.main()
