# LunkAlarm for iPhone and iPad

A native SwiftUI implementation of the website's clock, themes, alarms, countdowns, sound picker, imports, and wake-up tests. It uses Apple's **AlarmKit on iOS 26 or later** to schedule system alarms and weekly routines. There is no WebView, JavaScript runtime, server, Supabase dependency, or sound-enable button.

The website in `web/` remains separately deployable. **Find more ringtones online** still opens the same Mixkit, Pixabay, and Zedge pages in the browser; this app does not scrape or embed their catalogues.

## What is included

- A centered large clock on launch, local date/time zone, and 12/24-hour display. Swipe down to view saved alarms; the floating + opens the editor. Swipe up at the top of the saved list or use Clock to return. Wheel/control interactions do not dismiss the page. VoiceOver exposes equivalent actions. Reduced Motion disables the transition.
- Fourteen app-owned themes (the original eight, plus Linen, Sea Glass, Forest, Ember, Amethyst, and Deep Ocean) that remain independent of the iPhone's light/dark setting.
- Apple's native heading-free time wheel with unpadded 12-hour hours and AM/PM rollover, duration wheels, and paired looping test controls: 1–8 math problems / 5–12 seconds per question, and 4–10 code characters / 15–30 seconds. Wake-up tests start expanded and collapse with their header arrow. The presets are 5 min, 10 min, 30 min, and 1 hour; trailing choices hide when space is limited.
- Ten offline PCM ringtones rendered from the existing app's synthesizer recipes; six-second previews.
- Import from Files: browser-downloadable audio smaller than 2 MB and shorter than 30 seconds, converted to mono PCM WAV in `Library/Sounds`. Each alarm remembers its selected sound and tests; importing a new sound does not change older alarms.
- AlarmKit authorization requested when the first alarm is added, absolute deadlines, cancellation, queued in-app wake-up tests, and reconciliation with the system alarm list.
- Case-sensitive typing tests with paste/multi-character insertion disabled, followed by 1–8 addition problems. Math answers submit automatically at the expected digit count; incorrect answers clear. Typing defaults to 30 seconds and eight characters; math defaults to 10 seconds per question. New alarms snapshot the chosen lengths/timers; existing alarms keep those defaults. A timeout restarts the whole configured sequence, resets math progress to zero, and enables sound again. No snooze or dismissal message.
- Tests start quietly when opened, with a sound switch fixed at the top right. The countdown uses an absolute deadline; system AlarmKit timeout/recovery alarms back it up when the app is suspended. The first timeout has a one-second grace so the foreground timer can reset the test without a duplicate system banner. Completing the tests cancels all associated timeout alarms.
- Optional sound-check sheet (never adds the configured alarm), an Alarm volume slider, optional ten-second gradual fade-in, previews, and a real five-second AlarmKit test. Each new alarm snapshots its selected relative level/fade into its system sound file. In-app playback fades once and stays at the selected level. iOS still controls overall alert/output volume; if it repeats the system sound file, the fade can repeat too.
- Local atomic JSON persistence with a previous-save backup. Corrupt/unsupported state is left untouched and alarm editing is disabled. No accounts or browser-to-iPhone data sync.

## Open and run with Xcode

Requires **Xcode 26 or later** and a Mac that can run it. macOS Monterey cannot run Xcode 26. A newer iPhone OS version can run an app with an iOS 26 minimum; test on the actual device before relying on alarms.

1. Download this repository from GitHub (**Code → Download ZIP**) and extract it.
2. Open `ios/LunkAlarm.xcodeproj` in Xcode.
3. Select the **LunkAlarm** target → **Signing & Capabilities** → select your Apple development team. Change `online.reeeserve.LunkAlarm` if that bundle identifier is unavailable for your team.
4. Select your connected iPhone or an iOS 26+ simulator and press Run. On an iPhone, enable Developer Mode when prompted.
5. Swipe down, tap +, set a short duration, optionally check the sound, allow the system's Alarms permission, and test playback with the app visible and the phone locked.

Use the Files app or Safari downloads to obtain a sound, then open **Ringtone → Use my own file**. Imported audio stays on the iPhone. Permissions, alarms, and sound volume are controlled by iOS; the website's internet-time services are not used to alter system alarm deadlines.

## If your Mac still runs Monterey

The **Native iOS app** GitHub Actions workflow builds on a newer hosted Mac with Xcode 26. Open this repository's **Actions → Native iOS app** and select a completed successful run. Its **LunkAlarm-iOS** artifact contains Xcode source, an iOS Simulator app ZIP, a simulator launch screenshot, build logs, and an **unsigned device IPA**.

The simulator app cannot run on an iPhone. The unsigned IPA cannot be installed directly: it still needs signing/provisioning for your device or distribution through TestFlight. Publishing a GitHub release does not replace Apple's signing requirements.

The most convenient route without a newer Mac is an **Apple Developer Program membership + a signed cloud build + TestFlight**. This repository does not include signing certificates, provisioning profiles, App Store Connect credentials, or an automated upload. Those need to be configured for your Apple account separately. Do not put signing keys or account passwords in the app, Git, or chat. The workflow performs unsigned builds only and does not publish to the App Store/TestFlight.

A free personal Apple ID can also sign apps for personal use through compatible Xcode or a third-party sideloading tool. [AltStore's official repository](https://github.com/altstoreio/AltStore) documents personal Apple ID signing through AltServer and a macOS minimum older than Monterey. Check the current AltServer release's requirements and support for your exact iOS version before relying on that route. Free provisioning requires regular renewal; this app has not been verified with AltStore or on a physical iPhone. Enter account details only in the signing tool you choose, never in LunkAlarm or chat.

The workflow also updates an [`ios-build-reports` branch](https://github.com/TristanSibug/LunkAlarm/tree/ios-build-reports) with a small `build.json` and the latest simulator launch screenshot. This makes the build status and preview readable without downloading workflow logs. It contains generated reports only; source remains on `main`.

## iOS alarm behavior

AlarmKit schedules alerts with iOS; the app does not need to remain on screen for a scheduled alarm. It requests AlarmKit permission rather than ordinary notification permission. Both At a time and In how long resolve to one fixed system deadline, matching the website's one-shot behavior. Duration alarms use fixed schedules rather than a pausable countdown Live Activity, so no widget extension is required.

Time-of-day selection uses the next matching local time. A nonexistent daylight-saving time moves to the next valid time; a repeated time uses the first future occurrence. New time alarms support daily and selected-weekday repeats. Changing time zones after scheduling does not move a deadline to a new local hour.

**iOS retains control of system alarm presentation and stopping.** LunkAlarm cannot suppress the system banner, automatically force itself over another app or the Lock Screen, or prevent force-quit. The wake-up-tests action opens LunkAlarm; entering tests pauses the system sound and starts a quiet timed answering session. Users can enable sound with the top-right switch. The timeout resets the tests and turns sound on; if the app is suspended, the separately scheduled system timeout alarm can alert instead. Returning from the background mutes sound for answering again. Finishing tests cancels the original alert and every timeout owned by that alarm. In-app answering audio uses media volume, which may differ from iOS alert volume. No public API locks these two system volume controls together.

Real, audible wake-up-test playback uses the audio background mode so simply leaving/locking the app does not intentionally stop an enabled player. Muted sessions rely on the system timeout alarm rather than background execution. Previews stop on backgrounding. No silent keepalive or continuous idle audio is used. Interruptions resume playback only when iOS permits it and the answering sound switch is on. Force-quitting or iOS stopping the app can still end its in-app playback; already scheduled system alerts remain under iOS control. Device testing is required for the exact Lock Screen, volume, timeout, and app-handoff behavior on each iOS version.

AlarmKit is designed to alert through Silent Mode and Focus after authorization. That does not let the app override the device's overall volume or guarantee audible output on every configuration. Use the built-in sound check with the phone locked and repeat after volume/settings changes.

The app observes iOS alarm state instead of running a second background scheduler. An ordinary system-stopped alarm is not automatically resurrected. Alarms with wake-up tests pre-schedule recovery alerts 20, 40, and 60 seconds after the main deadline, so dismissing a Lock Screen alert without successfully opening the app can alert again. The answering timeout also receives the same bounded recovery sequence. These alerts are scheduled in advance, not dependent on code running after Face ID/passcode fails. On active entry the sounding alert is paused, and future reminders stay armed until iOS confirms replacement guards for the current question deadline; completion/deletion cancels every owned ID. Recovery is limited to these three reminders, not an unlimited or unpreventable alarm. Re-add existing alarms to receive the new initial recovery schedule. Scheduling failure rolls back the whole set, retaining visible ownership if cancellation fails. A future alarm missing from iOS is shown as **Not scheduled**; remove and add it again. If the system has already stopped an alarm with tests, unfinished tests remain available in LunkAlarm. On simultaneous alerts, iOS owns system presentation; the app presents the remaining tests in deadline order.

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
- Trigger a challenged alarm while locked, tap Wake-up tests and deliberately fail Face ID/passcode. Wait for a recovery alert; unlock successfully and complete tests. Verify every recovery alert is cancelled. Repeat by terminating the app before the first alarm.
- Check relative sound levels and gradual fade-in using both preview and a locked-device test. The five-second test starts after five seconds, then uses the full ten-second fade when enabled. Confirm the ten-second rise and that old alarms retain their earlier sound/volume snapshots.
- Cancel before due, restart the app, restart the phone, and revoke/re-enable permission; compare the displayed list with actual iOS alerts.
- Check all 14 themes (including the two new light palettes), Dynamic Type, VoiceOver, Reduce Motion, portrait/landscape, small iPhones, and iPad.

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

## Saved routines (1.3)

Swipe up from the clock to Your alarms, then tap the floating + to create an alarm. Swipe down at the top of the list or use Clock to return. At a time alarms allow a blank name, support Once (no days), Daily or selected weekdays, and remain until deleted. A completed Once alarm turns off. Repeat schedules use native AlarmKit weekly schedules; completing wake-up tests rearms the routine. Each routine can be disabled without deleting it. Existing time alarms migrate as named “Alarm”, one-shot entries.

In how long countdowns never appear in saved routines. Only active countdown ownership is retained internally for system-alert cleanup and crash recovery; completed countdowns are removed. Active timers can be cancelled from the clock.

Recurring routines with tests use native weekly recovery alerts at +1, +2 and +3 minutes (including weekday rollover at midnight), so recovery continues on future scheduled days without requiring a background app launch. One-shot recovery remains +20/+40/+60 seconds. Question timeout alerts remain fixed absolute deadlines. Verify recurring alarms on a locked physical iPhone across successive scheduled days, completing tests, disabling, deletion and time-zone changes before relying on them.

Themes retain the same two-column tiles, now ordered as light palettes, neutral dark palettes, warm palettes, then green/blue/purple families.

## Version 1.4: editing, duplicates and continuous audio

Swipe up from the big clock to saved alarms; swipe down at the top of the list (or Clock) to return. Alarm names are optional. Tap a card to edit that exact saved alarm; saving preserves its ID and enabled state. The menu contains Delete followed by Duplicate. Duplication preserves name, blank name, time, selected days, ringtone/import, tests, volume, fade and playback mode; it assigns a fresh ID and fresh scheduled-alert ownership. Past routines get their next matching occurrence. Duplicate definitions and simultaneous alarms are allowed. Cards use about 60% of the earlier height without shrinking switch/menu touch targets.

New alarms default to the Continuous audio selection when no playback preference has been chosen; old saved records without an engine field keep System alarm mode. Editing loads the saved engine, so change it explicitly to convert an older alarm. System alarm remains available per alarm.

Continuous audio is **experimental media playback**, not a verified copy of Alarmy's internals. AVAudioSession.playback and scheduled looping AVAudioPlayer instances implement the audio path. The app does not register an AlarmKit alert, a local notification, or Now Playing metadata for these alarms. It queues audio in advance using the audio device clock. There is no silent keepalive and no idle audio loop. Once playback runs it uses media output and can sound in Silent Mode. iOS retains audio routing, volume, interruptions and process-lifetime control. Merely queueing future media does not establish a guaranteed right to execute later in the background. This mode cannot ring after a force-quit, process termination or reboot; reopening can re-arm future alarms and expose overdue alarms, not retroactively make them ring while terminated. Long-delay locked-device scheduling is unverified until tested on hardware. Do not rely on this mode as the only wake-up alarm yet.

When the app becomes active at a due alarm, test sessions start quietly. Muted question deadlines queue a fresh audio guard instead of an AlarmKit notification. Timeout resets the configured sequence and starts looping sound; the top-right switch controls answering playback. Completion, deletion, disabling, editing and engine changes cancel the corresponding queued audio. Audio sessions remain active while future players are queued, so stopping a ringtone preview cannot deactivate their shared audio session. Interruptions resume only when iOS permits. Continuous audio queues a rendered fade introduction followed by a steady looping player, so the fade happens once; in-app answering playback also fades once. System alarm sound-file repeats may still repeat their encoded fade.

Physical-device validation required: test a five-second audio alarm with Silent Mode on, lock the phone, attempt Face ID/passcode without completing unlock, then unlock and complete tests. Confirm no system alarm banner/notification was registered for the audio mode. Repeat with a delay longer than the normal background execution grace, overnight, while another app plays audio, after interruption and after returning to LunkAlarm. Force-quit/reboot must be treated as disabling continuous audio until reopening. Verify System alarm fallback separately. No simulator UI test proves overnight audibility.
