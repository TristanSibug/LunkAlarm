# LunkAlarm for iPhone and iPad

A native SwiftUI implementation of the website's clock, themes, alarms, countdowns, sound picker, imports, and wake-up tests. It uses Apple's **AlarmKit on iOS 26 or later** to schedule one-shot system alarms. There is no WebView, JavaScript runtime, server, Supabase dependency, or sound-enable button.

The website in `web/` is unchanged. **Find more ringtones online** still opens the same Mixkit, Pixabay, and Zedge pages in the browser; this app does not scrape or embed their catalogues.

## What is included

- A centered large clock on launch, local date/time zone, 12/24-hour display, and animated Add alarm / Hide alarm picker transitions. Reduced Motion disables the transition.
- Eight app-owned themes that remain independent of the iPhone's light/dark setting.
- Native wheel pickers for clock time and duration, plus a single row of duration presets that hides trailing choices when space is limited.
- Ten offline PCM ringtones rendered from the existing app's synthesizer recipes; six-second previews.
- Import from Files: browser-downloadable audio smaller than 2 MB and shorter than 30 seconds, converted to mono PCM WAV in `Library/Sounds`. Each alarm remembers its selected sound and tests; importing a new sound does not change older alarms.
- AlarmKit authorization requested when the first alarm is added, absolute deadlines, cancellation, queued in-app wake-up tests, and reconciliation with the system alarm list.
- Case-sensitive typing tests with paste/multi-character insertion disabled, followed by 1–8 addition problems. No snooze.
- Local atomic JSON persistence with a previous-save backup. Corrupt/unsupported state is left untouched and alarm editing is disabled. No accounts or browser-to-iPhone data sync.

## Open and run with Xcode

Requires **Xcode 26 or later** and a Mac that can run it. macOS Monterey cannot run Xcode 26. A newer iPhone OS version can run an app with an iOS 26 minimum; test on the actual device before relying on alarms.

1. Download this repository from GitHub (**Code → Download ZIP**) and extract it.
2. Open `ios/LunkAlarm.xcodeproj` in Xcode.
3. Select the **LunkAlarm** target → **Signing & Capabilities** → select your Apple development team. Change `online.reeeserve.LunkAlarm` if that bundle identifier is unavailable for your team.
4. Select your connected iPhone or an iOS 26+ simulator and press Run. On an iPhone, enable Developer Mode when prompted.
5. Open Add alarm, set a short duration, allow the system's Alarms permission, and test playback with the app visible and the phone locked.

Use the Files app or Safari downloads to obtain a sound, then select **Use my own file**. Imported audio stays on the iPhone. Permissions, alarms, and sound volume are controlled by iOS; the website's internet-time services are not used to alter system alarm deadlines.

## If your Mac still runs Monterey

The **Native iOS app** GitHub Actions workflow builds on a newer hosted Mac with Xcode 26. Open this repository's **Actions → Native iOS app** and select a completed successful run. Its **LunkAlarm-iOS** artifact contains Xcode source, an iOS Simulator app ZIP, build logs, and an **unsigned device IPA**.

The simulator app cannot run on an iPhone. The unsigned IPA cannot be installed directly: it still needs signing/provisioning for your device or distribution through TestFlight. Publishing a GitHub release does not replace Apple's signing requirements.

The most convenient route without a newer Mac is an **Apple Developer Program membership + a signed cloud build + TestFlight**. This repository does not include signing certificates, provisioning profiles, App Store Connect credentials, or an automated upload. Those need to be configured for your Apple account separately. Do not put signing keys or account passwords in the app, Git, or chat. The workflow performs unsigned builds only and does not publish to the App Store/TestFlight.

## iOS alarm behavior

AlarmKit schedules alerts with iOS; the app does not need to remain on screen for a scheduled alarm. It requests AlarmKit permission rather than ordinary notification permission. Both At a time and In how long resolve to one fixed system deadline, matching the website's one-shot behavior. Duration alarms use fixed schedules rather than a pausable countdown Live Activity, so no widget extension is required.

Time-of-day selection uses the next matching local time. A nonexistent daylight-saving time moves to the next valid time; a repeated time uses the first future occurrence. Alarms are not daily repeats. Changing time zones after scheduling does not move a deadline to a new local hour.

**iOS always retains control of stopping an alarm from its Lock Screen/system UI. Wake-up tests cannot prevent that.** For alarms with tests, the system Stop action opens LunkAlarm to finish them, and Open LunkAlarm is also offered as a secondary action. Tests and continued in-app playback operate while the app is active. Locking/leaving the app can suspend that in-app playback after the system alarm has already been stopped. No background-audio entitlement, critical-alert entitlement, silent keepalive, or promise of an unskippable alarm is included.

The app observes iOS alarm state instead of running a second background scheduler. A system-stopped alarm is not automatically resurrected. A future alarm missing from iOS is shown as **Not scheduled**; remove and add it again. If the system has already stopped an alarm with tests, unfinished tests remain available in LunkAlarm. On simultaneous alerts, iOS owns system presentation; the app presents the remaining tests in deadline order.

## Validation

Core scheduling, daylight-saving handling, duration bounds, challenge ordering, immutable sound snapshots, atomic persistence/backup, corrupt-data preservation, and system reconciliation are tested with Swift XCTest:

```sh
swift test --package-path ios
```

The GitHub workflow also compiles simulator and device targets with signing disabled. Linux can test the shared core and parse Swift syntax; it cannot compile SwiftUI/AlarmKit or run the iOS app. Simulator playback does not establish locked-device reliability.

Before distribution, test on a real iPhone:

- Allow/deny/revoke Alarms permission; confirm failed scheduling is reported and never claimed successful.
- Add a ten-second alarm, return Home, lock the phone, and verify it alerts. Repeat with Silent Mode and Focus enabled, using the device's intended alarm volume.
- Test all ten sounds and at least one imported WAV/MP3/M4A, including stereo input. Reject files over 2 MB or 30 seconds. Confirm old alarms retain earlier imported sounds.
- Stop/open from system UI, complete typing then math, try wrong answers and pasting, dismiss, and confirm removal. Repeat with the app initially terminated and multiple alarms due together.
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
