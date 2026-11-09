# LunkAlarm for Android

A native Kotlin / Jetpack Compose counterpart to the current iOS app. Requires **Android 8.0 (API 26) or later**. It has no WebView, server, account, analytics, or Internet permission. The existing website, Windows app and iOS app remain separate.

## Install

Download `LunkAlarm-Android-1.0.0.apk` from the repository's **LunkAlarm for Android 1.0.0** GitHub release. Open it on your Android phone and allow installation from your browser/file manager when Android asks. In LunkAlarm, tap **Alarm access** and allow **Alarms & reminders**, **Notifications**, and, on Android 14+, **Full-screen alarms**. Full-screen access controls presentation; without it Android can show a ringing notification instead. Set your phone's **alarm volume**, then test a short alarm with the phone locked.

The downloadable APK is signed with a development key for personal testing, not a Google Play production release. CI caches that key for subsequent test builds. A lost cache can produce a different signing identity; production distribution needs a privately managed signing key and versioned releases. No signing keys are committed to this repository.

## Interface

- The large clock opens first, with local date, time zone, 12/24-hour format, and fourteen app-owned themes in the same order as iOS. Swipe up to Your alarms; swipe down at the top of the list or tap Clock to return. Motion follows the direction of the swipe and Android's animation setting.
- Your alarms shows both saved wall-clock routines and active In how long countdowns. Timers show remaining time and disappear when completed. At a time alarms stay until deleted. Once alarms turn off after completion; repeating routines are rearmed for the next chosen day.
- The floating + opens the editor. Names are optional. Tap an existing card to edit that same alarm. The bottom Add alarm / Save changes action stays visible while the form scrolls; × closes the editor. Editing a countdown restarts its stored duration.
- Menus contain Delete, then Duplicate. Duplication copies the entire definition, including blank names, selected days, sound, volume/fade and tests, with independent identity. Countdown copies start a new deadline. Left-swipe reveals a circular Delete button; a full swipe crosses a haptic threshold and deletes on release. Vertical movement remains scrolling/navigation. Active missions must be finished before editing or deleting their owner.
- Native looping wheels for time, duration, problem count (1–8), math timer (5–12 seconds), code length (4–10), and typing timer (15–30 seconds). Twelve-hour hours are unpadded and cross 11/12 with AM/PM rollover. Duration presets are 5 min, 10 min, 30 min, and 1 hour; trailing presets hide instead of wrapping, with equal spacing.
- Ten bundled synthesizer ringtones, previews, a relative volume slider, optional ten-second gradual fade, and a separate five-second sound check. The check creates only its temporary test timer. Imported supported audio is copied into private app storage, limited to 2 MB and 30 seconds. Use my own file and Find more ringtones online live inside Ringtone. Online links still open Mixkit, Pixabay and Zedge in the browser; no catalog scraping/API integration was added.
- Wake-up tests start expanded and collapse using their header. Math submits at the expected digit count and clears incorrect answers. Typing is case-sensitive with paste/multiple-character insertion disabled. Both keypads give haptic feedback, subject to device settings.

## Alarm delivery

Future alarms are owned by `AlarmManager`; the app does not run an idle audio loop or keep a foreground service alive just to wait. Wall-clock alarms use `setAlarmClock`, and countdowns use elapsed-realtime `setExactAndAllowWhileIdle` so changing the phone clock does not change the countdown. Exact-alarm access is checked before saving, and denied access cannot produce a false success. Weekday times use local time and handle DST gaps/overlaps.

When an alarm fires, Android starts an audible foreground playback service and an ongoing alarm notification. The service uses `USAGE_ALARM` audio, so Silent Mode's ringtone setting does not itself control the alarm. The device's **alarm volume, Do Not Disturb policy, audio routing and manufacturer battery settings** still apply. Relative volume and fade do not overwrite the system volume. Full-screen presentation uses Android's supported notification intent and requires the user's access on newer Android versions. The app does not request overlays, accessibility control or permission to change Do Not Disturb.

For alarms with tests, the notification has no Stop shortcut. If the device is locked, the full-screen page asks to unlock before starting the questions. Cancelled/failed unlocks and relocking keep the sound on and leave the question deadline unstarted. Successful unlock quiets the sound for answering, with a switch at the top right. An expired deadline resets the entire configured typing/math sequence, clears progress and starts audible playback again. Question deadlines use elapsed realtime within the current boot; saved challenge state survives process recreation. After a reboot the pending session restarts audibly and requires unlocking again.

Schedules, sound files and mission ownership persist in private direct-boot storage, and boot/time-zone/time-change/package-update events reschedule existing alarms. `START_STICKY` restores an active service when Android recreates it; removing the task does not intentionally stop playback. A partial wake lock is held only while an alarm is active, with bounded renewal. Completion releases playback/focus/wake lock, cancels the notification, removes a timer or rearms a repeating routine, and moves to any other queued ringing alarm.

**Android Force stop, uninstalling the app, or revoking exact-alarm access can disable alarms.** Reopening the app rearms its saved enabled schedules where access permits. The app cannot override Android's user controls. Test on a physical phone, including locked screen, Silent Mode, Do Not Disturb, battery saver and an overnight delay, before relying on it as your only alarm.

## Build and test

Open `android/` in Android Studio, or use Java 21 with Android SDK 36 and the checked-in Gradle 8.13 wrapper:

```sh
./gradlew :app:assembleDebug :app:assembleDebugAndroidTest :app:testDebugUnitTest :app:lintDebug
```

The APK is `app/build/outputs/apk/debug/app-debug.apk`. The wrapper distribution has a pinned SHA-256. Gradle's default development signing key stays outside the repository; local automation can select its own file with `LUNK_ANDROID_KEYSTORE`.

The **Native Android app** GitHub Actions workflow runs the same build/core/lint checks, then an Android 15 emulator. Device checks cover denied exact-alarm permission, actual alarm delivery after leaving the app and entering Doze, countdown completion/removal, optional names/edit/duplicates, fixed save positioning, swipe navigation/deletion, math auto-submit and timeout/audio restart, typing input, and an incomplete secure unlock followed by relocking. These emulator checks do not prove physical audibility, haptic feel or every manufacturer's background behavior.

Successful main builds publish a prerelease APK, source ZIP and SHA-256 checksum under the tag `android-v1.0.0`. Build logs, test reports and native screenshots are in the **LunkAlarm-Android** Actions artifact; a generated `android-build-reports` branch exposes the latest result and previews. Existing releases are never replaced by a different source commit without a version bump.
