# LunkAlarm for iPhone and iPad

A native SwiftUI implementation of the website's clock, themes, alarms, countdowns, sound picker, imports, and wake-up tests. It uses Apple's **AlarmKit on iOS 26 or later** to schedule system alarms and weekly routines. There is no WebView, JavaScript runtime, server, Supabase dependency, or sound-enable button.

The website in `web/` remains separately deployable. **Find more ringtones online** still opens the same Mixkit, Pixabay, and Zedge pages in the browser; this app does not scrape or embed their catalogues.

## What is included

- A centered large clock on launch, local date/time zone, and 12/24-hour display. Swipe up to view alarms; the floating + opens the editor. Swipe down at the top of the alarm list or use Clock to return. Wheel/control interactions do not dismiss the page. VoiceOver exposes equivalent actions. Reduced Motion disables the transition.
- Nineteen app-owned themes (the original fourteen, plus Eggshell White, Heritage, Signal Blue, Cobalt & Coral, and Midnight Cherry) that remain independent of the iPhone's light/dark setting.
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
5. Swipe up, tap +, set a short duration, optionally check the sound, allow the system's Alarms permission, and test playback with the app visible and the phone locked.

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
- Check all 19 themes (including Eggshell White and the four new blue/red palettes), Dynamic Type, VoiceOver, Reduce Motion, portrait/landscape, small iPhones, and iPad.

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

Active In how long countdowns appear beside saved routines in Your alarms, with their remaining time and deadline. They retain ownership for system-alert cleanup and crash recovery while active, then are removed after dismissal/completion. At a time alarms remain until deleted. Tap either type to edit; a countdown edit/duplicate starts a new deadline from its stored duration.

Recurring routines with tests use native weekly recovery alerts at +1, +2 and +3 minutes (including weekday rollover at midnight), so recovery continues on future scheduled days without requiring a background app launch. One-shot recovery remains +20/+40/+60 seconds. Question timeout alerts remain fixed absolute deadlines. Verify recurring alarms on a locked physical iPhone across successive scheduled days, completing tests, disabling, deletion and time-zone changes before relying on them.

Themes retain the same two-column tiles, now ordered as light palettes, neutral dark palettes, warm palettes, then green/blue/purple families.

## Version 1.5: system alarms, countdowns and gestures

All alarms use AlarmKit; the experimental Continuous audio scheduler and playback chooser have been removed. Existing system records and their primary/recovery schedules are retained. On first launch, enabled legacy audio records are scheduled with AlarmKit under their existing IDs; disabled records stay disabled. Migration failures retain the original definition and report the error. The legacy engine string is decoded only for migration. Real audible in-app answering playback remains, with the same mute switch and system question-timeout guards.

Swipe up from the big clock: Your alarms enters from below while the clock leaves above. Swipe down at the top of the list: the clock enters from above as the list leaves below. Reduced Motion disables movement. Empty and populated lists share the same full-width leading frame, 20-point phone inset and 680-point tablet cap.

The editor has an × close control and a floating Add alarm / Save changes action fixed above the bottom safe area while the form scrolls. Alarm names remain optional. Tap a card to edit that exact alarm; saving retains its ID and enabled state. The menu contains Delete followed by Duplicate. Duplicates preserve every definition field, with fresh identity and system-alert ownership. Timers restart from their stored original duration; legacy timers use their remaining duration. Duplicate definitions and simultaneous alarms are allowed.

Swipe a card left to reveal a circular Delete action. A full swipe past 65% of the card width gives medium impact feedback and deletes on release; a deliberate fast full swipe also commits. Short swipes reveal the action, and right swipes close it. Vertical movement continues scrolling/navigation. Delete is also available to VoiceOver. A failed cancellation/save restores the card and displays the error. Calculator keys and accepted typing-keyboard insertions/deletions give light haptic feedback; physical-device testing is required to feel the haptics.

Validation covers scheduling/persistence/recovery, optional names, exact duplicates, countdown editing/lifecycle, header alignment, a fixed editor action, partial/full swipe deletion, native wheels, keypad entry and question timers. Simulator tests cannot verify physical haptics or locked-iPhone alarm behavior. On a real iPhone, test a system alarm with wake-up tests, attempt an incomplete unlock at the Lock Screen stop action, relock, confirm a recovery alert, then unlock and complete the tests. Recovery alerts remain bounded as described above; this build does not promise an indefinite or undismissable alarm.

## Version 1.6: repeat-day badges and five more themes

Saved alarm cards no longer repeat a weekday summary such as Tue below the time. For a custom repeat schedule, the selected weekday letters have an outlined circle with a subtle tint; other letters remain plain. Choosing all seven days replaces the letters with one Daily label in the card footer. Countdown labels and sound/test icons stay in their existing positions. VoiceOver announces each visible weekday and whether it is selected. Editing the alarm updates the same card's badges immediately after saving.

Five iOS-only palettes bring the theme count to nineteen. Eggshell White is a warm off-white neutral; Heritage uses the reference's stripes 1/3/4 (oxblood, ivory and navy); Signal Blue uses stripes 2/4/5 (crimson, navy and steel blue) with lighter foregrounds for readability. Cobalt & Coral and Midnight Cherry offer blue-dominant and red-dominant alternatives. Existing themes and the two-column picker are retained, with the additions inserted into the existing light/warm/blue color groups. Android and the website are unchanged.
