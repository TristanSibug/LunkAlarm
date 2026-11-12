# LunkAlarm for Android

A native Kotlin / Jetpack Compose counterpart to the current iOS app. Requires **Android 8.0 (API 26) or later**. It has no WebView, server, account, analytics, or Internet permission. The existing website, Windows app and iOS app remain separate.

## Install

Download the APK from a maintainer-published [GitHub release](https://github.com/TristanSibug/LunkAlarm/releases), or get `LunkAlarm-Android-1.3.0.apk` from the **LunkAlarm-Android** artifact of a successful **Native Android app** Actions run. Open it on your Android phone and allow installation from your browser/file manager when Android asks. In LunkAlarm, tap **Alarm access** and allow **Alarms & reminders**, **Notifications**, and, on Android 14+, **Full-screen alarms**. Full-screen access controls presentation; without it Android can show a ringing notification instead. Set your phone's **alarm volume**, then test a short alarm with the phone locked.

The downloadable APK is signed with a development key for personal testing, not a Google Play production release. CI caches that key for subsequent test builds. A lost cache can produce a different signing identity; production distribution needs a privately managed signing key and versioned releases. No signing keys are committed to this repository.

## Interface

- The large clock opens first, with local date, time zone, 12/24-hour format, and eighteen app-owned themes in the same order as iOS. Swipe up to Your alarms; swipe down at the top of the list or tap Clock to return. Motion follows the direction of the swipe and Android's animation setting.
- Your alarms shows both saved wall-clock routines and active In how long countdowns. Timers show remaining time and disappear when completed. At a time alarms stay until deleted. Once alarms turn off after completion; repeating routines are rearmed for the next chosen day.
- The floating + offers Alarm and Timer, opening the corresponding editor. Timers appear first under Timers; saved alarms appear under Alarms, with empty sections hidden. Names are optional. Tap an existing card to edit that same alarm. The bottom Add alarm / Save changes action stays visible while the form scrolls; × closes the editor. Editing a countdown restarts its stored duration.
- Menus contain Delete, then Duplicate. Duplication copies the entire definition, including blank names, selected days, sound, volume/fade and tests, with independent identity. Countdown copies start a new deadline. Left-swipe reveals a circular Delete button; a full swipe crosses a haptic threshold and deletes on release. Vertical movement remains scrolling/navigation. Active missions must be finished before editing or deleting their owner.
- Native looping wheels for time and duration; wake-up tests use finite buttons and bounded −/+ steppers instead. Tap the selected time hour/minute to enter a value with the keyboard. Twelve-hour hours are unpadded and cross 11/12 with AM/PM rollover. Duration presets are 5 min, 10 min, 30 min, and 1 hour; trailing presets hide instead of wrapping, with equal spacing.
- Ten bundled synthesizer ringtones, previews, a relative volume slider, optional ten-second gradual fade, and a separate five-second sound check. The check creates only its temporary test timer. Imported supported audio is copied into private app storage, limited to 2 MB and 30 seconds. Use my own file and Find more ringtones online live inside Ringtone. Online links still open Mixkit, Pixabay and Zedge in the browser; no catalog scraping/API integration was added.
- Wake-up tests are always shown. Tapping any of the five icon tiles opens settings. Only Set / Unset changes whether that test is enabled; closing the sheet preserves activation. Each settings title has an isolated, cancellable Try mode. The available finite controls and game rules are listed below. Math auto-submits at the expected digit count; typing remains case-sensitive with paste disabled. Built-in keys and accepted typing input give haptic feedback, subject to device settings.

## Alarm delivery

Future alarms are owned by `AlarmManager`; the app does not run an idle audio loop or keep a foreground service alive just to wait. Wall-clock alarms use `setAlarmClock`, and countdowns use elapsed-realtime `setExactAndAllowWhileIdle` so changing the phone clock does not change the countdown. Exact-alarm access is checked before saving, and denied access cannot produce a false success. Weekday times use local time and handle DST gaps/overlaps.

When an alarm fires, Android starts an audible foreground playback service and an ongoing alarm notification. The service uses `USAGE_ALARM` audio, so Silent Mode's ringtone setting does not itself control the alarm. The device's **alarm volume, Do Not Disturb policy, audio routing and manufacturer battery settings** still apply. Relative volume and fade do not overwrite the system volume. Full-screen presentation uses Android's supported notification intent and requires the user's access on newer Android versions. The app does not request overlays, accessibility control or permission to change Do Not Disturb.

For alarms with tests, the notification has no Stop shortcut. If the device is locked, the full-screen page asks to unlock before starting the questions. Cancelled/failed unlocks and relocking keep the sound on and leave the question deadline unstarted. Successful unlock quiets the sound for answering, with a switch at the top right. An expired deadline resets the entire configured wake-up test sequence, clears progress and starts audible playback again. Question deadlines use elapsed realtime within the current boot; saved challenge state survives process recreation. After a reboot the pending session restarts audibly and requires unlocking again.

Schedules, sound files and mission ownership persist in private direct-boot storage, and boot/time-zone/time-change/package-update events reschedule existing alarms. `START_STICKY` restores an active service when Android recreates it; removing the task does not intentionally stop playback. A partial wake lock is held only while an alarm is active, with bounded renewal. Completion releases playback/focus/wake lock, cancels the notification, removes a timer or rearms a repeating routine, and moves to any other queued ringing alarm.

**Android Force stop, uninstalling the app, or revoking exact-alarm access can disable alarms.** Reopening the app rearms its saved enabled schedules where access permits. The app cannot override Android's user controls. Test on a physical phone, including locked screen, Silent Mode, Do Not Disturb, battery saver and an overnight delay, before relying on it as your only alarm.

## Build and test

Open `android/` in Android Studio, or use Java 21 with Android SDK 36 and the checked-in Gradle 8.13 wrapper:

```sh
./gradlew :app:assembleDebug :app:assembleDebugAndroidTest :app:testDebugUnitTest :app:lintDebug
```

The APK is `app/build/outputs/apk/debug/app-debug.apk`. The wrapper distribution has a pinned SHA-256. Gradle's default development signing key stays outside the repository; local automation can select its own file with `LUNK_ANDROID_KEYSTORE`.

The **Native Android app** GitHub Actions workflow runs the same build/core/lint checks, then an Android 15 emulator. Device checks cover denied exact-alarm permission, actual alarm delivery after leaving the app and entering Doze, countdown completion/removal, optional names/edit/duplicates, fixed save positioning, swipe navigation/deletion, math auto-submit and timeout/audio restart, typing input, and an incomplete secure unlock followed by relocking. These emulator checks do not prove physical audibility, haptic feel or every manufacturer's background behavior.

Successful builds package `LunkAlarm-Android-1.3.0.apk`, `LunkAlarm-Android-source.zip` and `SHA256SUMS.txt` in the **LunkAlarm-Android** Actions artifact, alongside build logs, test reports and native screenshots. A generated `android-build-reports` branch exposes the latest result and previews. The workflow does not create, upload or replace GitHub Releases.

To publish manually, download the artifact from a successful run, extract the APK/source ZIP/checksum from its `artifacts/` folder, and attach them to a release tagged `android-v1.3.0` at that run’s commit. Use **LunkAlarm for Android 1.3.0** as the title and [`RELEASE_NOTES.md`](RELEASE_NOTES.md) as the description.

## Version 1.1

Ports the iOS 1.6 repeat-day card badges and five additional palettes. Daily cards show one Daily footer; custom schedules circle selected weekdays with accessibility descriptions and no repeated day summary below the time. Inherited labels now follow each app palette, fixing black text in dark themes, including ringtone names, duration presets, fade/test labels and math keys.

## Version 1.2: wake-up tests

Only the wake-up test controls and answering views change in this update. The clock, time/duration pickers, ringtone controls, themes and navigation retain their existing designs.

Five icon tiles replace the long list of switches and wheels. Tapping an off tile enables its test and opens a settings sheet; tapping it again disables that test without opening a sheet. Other enabled tiles stay selected. Each sheet has a Try button beside its title, finite controls, and Done/close actions. To change an already-enabled test's settings, toggle it off and back on; toggling preserves its selected values, including the last math count during that editor session. There are no tile-operation help paragraphs or dismissal captions in the typing, math or puzzle settings.

Try opens an isolated practice run using the same input, board and deadline logic as the alarm. It never schedules an alarm, starts audio, persists trial progress or changes a live session. Back or × exits immediately, even after an incorrect answer/timeout. Real incoming alarms still take priority.

- Typing: code length 4–10 using −/+, time buttons 15/20/25/30 seconds. The code answer field has a faint themed border and placeholder.
- Math: 1–8 problems using −/+, time buttons 5/10/15 seconds. The native keyboard option remains, without its extra Android keyboard sentence.
- Puzzle: 6/8/10 pieces and 15/20/25/30/35/40 seconds. Progress (for example, 0/8 placed) replaces the old heading; instructions follow underneath. Empty-piece outlines are hidden. A board has exactly one position per piece, accessible through drag/snap or tap placement. Existing odd counts migrate to the nearest even choice (ties use the lower count); an in-progress odd board clears its placed pieces when migrated.
- Minesweeper: Easy 5×5 with four mines, Medium 7×7 with eight mines, Hard 9×9 with fourteen mines; timers 15/20/25/30/35/40 seconds. Boards start with a safe revealed opening and are accepted only if visible clues and the mine count allow deduction without guessing. Reveal all safe squares and flag all mines. Tap reveals; hold flags; the Reveal/Flag button provides an alternative to holding. Flags are reversible. Hitting a mine resets the entire wake-up sequence and restores alarm audio.
- Sudoku: Easy = 4×4 easy, Medium = 4×4 hard, Hard = 6×6 easy, Difficult = 6×6 hard. Time buttons 60/120/180/240 seconds fit in one row. Generated puzzles have one solution; 4×4 uses 2×2 boxes and 6×6 uses 2×3 boxes. Select a blank, enter a digit, or erase; fixed clues cannot be changed. Conflicts are highlighted. Easy/hard select fewer/more blank cells, with removals constrained to preserve uniqueness.

The real alarm sequence is typing → math → puzzle → Minesweeper → Sudoku, skipping disabled tests. Each game has one deadline; individual moves never extend it. Any timeout restarts the whole configured sequence and restores audio. New options, board state, reversible flags and Sudoku entries persist across process recreation and copy with an alarm definition. A reboot retains the previous policy of starting the active sequence audibly from the beginning.


## Android 1.3.0 parity update

Matches the current iOS alarm/timer menus, explicit Set/Unset wake-up tests, wider Try buttons, four math operations, 5×5/7×7/9×9 Minesweeper and 60/120/180/240-second Sudoku. Ringtone selection stays open with an internal Sound checker. Native math answers clear synchronously without losing keyboard focus. Holding a revealed Minesweeper number has no action; hidden-square holds flag/unflag, and I'm done validates exactly the required flags. Existing saved alarms, custom sounds and active legacy game boards remain readable.

Theme selection closes the picker, VS Code Blue migrates to Deep Ocean, and theme gradients/card contrast match iOS. A subtle vibration checkbox beside volume controls preview and active alarm-service vibration, subject to device settings. Android's supported system alarm/notification delivery is retained.
