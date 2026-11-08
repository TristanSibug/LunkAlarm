# LunkAlarm for iPhone and iPad

A native SwiftUI implementation of the website's clock, themes, alarms, countdowns, sound picker, imports, and wake-up tests. It uses Apple's **AlarmKit on iOS 26 or later** to schedule one-shot system alarms. There is no WebView, JavaScript runtime, server, Supabase dependency, or sound-enable button.

The website in `web/` remains separately deployable. **Find more ringtones online** still opens the same Mixkit, Pixabay, and Zedge pages in the browser; this app does not scrape or embed their catalogues.

## What is included

- A centered large clock on launch, local date/time zone, and 12/24-hour display. Swipe up to reveal alarm settings; a fast swipe down when the page is at the top returns to the clock. Wheel/control interactions do not dismiss the page. VoiceOver exposes equivalent actions. Reduced Motion disables the transition.
- Eight app-owned themes that remain independent of the iPhone's light/dark setting.
- Apple's native heading-free time wheel with unpadded 12-hour hours and AM/PM rollover, duration wheels, and a centered looping 1–8 math count. The presets are 5 min, 10 min, 30 min, and 1 hour; trailing choices hide when space is limited.
- Ten offline PCM ringtones rendered from the existing app's synthesizer recipes; six-second previews.
- Import from Files: browser-downloadable audio smaller than 2 MB and shorter than 30 seconds, converted to mono PCM WAV in `Library/Sounds`. Each alarm remembers its selected sound and tests; importing a new sound does not change older alarms.
- AlarmKit authorization requested when the first alarm is added, absolute deadlines, cancellation, queued in-app wake-up tests, and reconciliation with the system alarm list.
- Case-sensitive typing tests with paste/multi-character insertion disabled, followed by 1–8 addition problems. Math answers submit automatically at the expected digit count; incorrect answers clear. Typing has 30 seconds, and each math question has 10 seconds. A timeout restarts the whole configured sequence, resets math progress to zero, and enables sound again. No snooze or dismissal message.
- Tests start quietly when opened, with a sound switch fixed at the top right. The countdown uses an absolute deadline; a system AlarmKit timeout alarm backs it up when the app is suspended. The backup has a one-second grace so the foreground timer can reset the test without a duplicate system banner. Completing the tests cancels all associated timeout alarms.
- First-use sound check, an Alarm volume slider, optional ten-second gradual fade-in, previews, and a real five-second AlarmKit test. Each new alarm snapshots its selected relative level/fade into its system sound file. In-app playback fades once and stays at the selected level. iOS still controls overall alert/output volume; if it repeats the system sound file, the fade can repeat too.
- Local atomic JSON persistence with a previous-save backup. Corrupt/unsupported state is left untouched and alarm editing is disabled. No accounts or browser-to-iPhone data sync.

## Open and run with Xcode

Requires **Xcode 26 or later** and a Mac that can run it. macOS Monterey cannot run Xcode 26. A newer iPhone OS version can run an app with an iOS 26 minimum; test on the actual device before relying on alarms.

1. Download this repository from GitHub (**Code → Download ZIP**) and extract it.
2. Open `ios/LunkAlarm.xcodeproj` in Xcode.
3. Select the **LunkAlarm** target → **Signing & Capabilities** → select your Apple development team. Change `online.reeeserve.LunkAlarm` if that bundle identifier is unavailable for your team.
4. Select your connected iPhone or an iOS 26+ simulator and press Run. On an iPhone, enable Developer Mode when prompted.
5. Swipe up, set a short duration, complete the sound check, allow the system's Alarms permission, and test playback with the app visible and the phone locked.

Use the Files app or Safari downloads to obtain a sound, then select **Use my own file**. Imported audio stays on the iPhone. Permissions, alarms, and sound volume are controlled by iOS; the website's internet-time services are not used to alter system alarm deadlines.

## If your Mac still runs Monterey

The **Native iOS app** GitHub Actions workflow builds on a newer hosted Mac with Xcode 26. Open this repository's **Actions → Native iOS app** and select a completed successful run. Its **LunkAlarm-iOS** artifact contains Xcode source, an iOS Simulator app ZIP, a simulator launch screenshot, build logs, and an **unsigned device IPA**.

The simulator app cannot run on an iPhone. The unsigned IPA cannot be installed directly: it still needs signing/provisioning for your device or distribution through TestFlight. Publishing a GitHub release does not replace Apple's signing requirements.

The most convenient route without a newer Mac is an **Apple Developer Program membership + a signed cloud build + TestFlight**. This repository does not include signing certificates, provisioning profiles, App Store Connect credentials, or an automated upload. Those need to be configured for your Apple account separately. Do not put signing keys or account passwords in the app, Git, or chat. The workflow performs unsigned builds only and does not publish to the App Store/TestFlight.

A free personal Apple ID can also sign apps for personal use through compatible Xcode or a third-party sideloading tool. [AltStore's official repository](https://github.com/altstoreio/AltStore) documents personal Apple ID signing through AltServer and a macOS minimum older than Monterey. Check the current AltServer release's requirements and support for your exact iOS version before relying on that route. Free provisioning requires regular renewal; this app has not been verified with AltStore or on a physical iPhone. Enter account details only in the signing tool you choose, never in LunkAlarm or chat.

The workflow also updates an [`ios-build-reports` branch](https://github.com/TristanSibug/LunkAlarm/tree/ios-build-reports) with a small `build.json` and the latest simulator launch screenshot. This makes the build status and preview readable without downloading workflow logs. It contains generated reports only; source remains on `main`.

## iOS alarm behavior

AlarmKit schedules alerts with iOS; the app does not need to remain on screen for a scheduled alarm. It requests AlarmKit permission rather than ordinary notification permission. Both At a time and In how long resolve to one fixed system deadline, matching the website's one-shot behavior. Duration alarms use fixed schedules rather than a pausable countdown Live Activity, so no widget extension is required.

Time-of-day selection uses the next matching local time. A nonexistent daylight-saving time moves to the next valid time; a repeated time uses the first future occurrence. Alarms are not daily repeats. Changing time zones after scheduling does not move a deadline to a new local hour.

**iOS retains control of system alarm presentation and stopping.** LunkAlarm cannot suppress the system banner, automatically force itself over another app or the Lock Screen, or prevent force-quit. The wake-up-tests action opens LunkAlarm; entering tests pauses the system sound and starts a quiet timed answering session. Users can enable sound with the top-right switch. The timeout resets the tests and turns sound on; if the app is suspended, the separately scheduled system timeout alarm can alert instead. Returning from the background mutes sound for answering again. Finishing tests cancels the original alert and every timeout owned by that alarm. In-app answering audio uses media volume, which may differ from iOS alert volume. No public API locks these two system volume controls together.

Real, audible wake-up-test playback uses the audio background mode so simply leaving/locking the app does not intentionally stop an enabled player. Muted sessions rely on the system timeout alarm rather than background execution. Previews stop on backgrounding. No silent keepalive or continuous idle audio is used. Interruptions resume playback only when iOS permits it and the answering sound switch is on. Force-quitting or iOS stopping the app can still end its in-app playback; already scheduled system alerts remain under iOS control. Device testing is required for the exact Lock Screen, volume, timeout, and app-handoff behavior on each iOS version.

AlarmKit is designed to alert through Silent Mode and Focus after authorization. That does not let the app override the device's overall volume or guarantee audible output on every configuration. Use the built-in sound check with the phone locked and repeat after volume/settings changes.

The app observes iOS alarm state instead of running a second background scheduler. A system-stopped alarm is not automatically resurrected. A future alarm missing from iOS is shown as **Not scheduled**; remove and add it again. If the system has already stopped an alarm with tests, unfinished tests remain available in LunkAlarm. On simultaneous alerts, iOS owns system presentation; the app presents the remaining tests in deadline order.

## Validation

Core scheduling, daylight-saving handling, duration bounds, challenge ordering, immutable sound snapshots, atomic persistence/backup, corrupt-data preservation, and system reconciliation are tested with Swift XCTest:

```sh
swift test --package-path ios
```

The GitHub workflow also compiles simulator and device targets with signing disabled and runs native UI tests for swipe navigation, time/AM-PM wheels, looping counts, and automatic math entry. UI screenshots and the result bundle are included in the build artifact. Linux can test the shared core and parse Swift syntax; it cannot compile SwiftUI/AlarmKit or run the iOS app. Simulator playback does not establish locked-device reliability.

Before distribution, test on a real iPhone:

- Allow/deny/revoke Alarms permission; confirm failed scheduling is reported and never claimed successful.
- Add a ten-second alarm, return Home, lock the phone, and verify it alerts. Repeat with Silent Mode and Focus enabled, using the device's intended alarm volume.
- Test all ten sounds and at least one imported WAV/MP3/M4A, including stereo input. Reject files over 2 MB or 30 seconds. Confirm old alarms retain earlier imported sounds.
- Open from system UI, confirm tests start quietly, toggle sound, complete typing then math, try wrong answers and pasting, dismiss, and confirm removal. Let each type of test expire; confirm typing restarts, math progress returns to zero, and sound enables. Repeat with the app backgrounded/locked while muted, then confirm the system timeout alerts. Finish tests and verify no extra timeout alert remains. Repeat with the app initially terminated and multiple alarms due together.
- Check relative sound levels and gradual fade-in using both preview and a locked-device test. Confirm the ten-second rise and that old alarms retain their earlier sound/volume snapshots.
- Cancel before due, restart the app, restart the phone, and revoke/re-enable permission; compare the displayed list with actual iOS alerts.
- Check Sunrise/Light/OLED and the other themes, Dynamic Type, VoiceOver, Reduce Motion, portrait/landscape, small iPhones, and iPad.

## Maintenance

No package manager or project generator is required to open the checked-in Xcode project. After adding/removing Swift or resource files, regenerate its deterministic file references:

```sh
python3 ios/scripts/generate_project.py
```

After changing `src/Wake.Core/tones.json`, regenerate the offline sound files, then regenerate the project:

```sh
python3 ios/scripts/generate_sounds.py
python3 ios/scripts/generate_project.py
```

The app reuses the original repository's icon and sound recipes under its license. `PrivacyInfo.xcprivacy` declares app-owned UserDefaults access and no tracking/data collection. Update the privacy declaration if future account, analytics, or networking features change that behavior.
