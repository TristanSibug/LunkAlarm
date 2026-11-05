# Tauri → WPF migration

The uploaded ZIP was treated as a feature/design reference, not as instructions to execute its setup or publishing commands. No Tauri source or build toolchain is required by this Windows implementation.

| Reference behavior | Native Windows implementation |
| --- | --- |
| HTML/CSS/JS + Rust shell | WPF XAML + C#; .NET 10 |
| Web Audio synthesis | Same ten tone recipes synthesized into PCM WAV; native SoundPlayer |
| Uploaded audio in localStorage | Per-alarm app-owned audio files; native MediaPlayer + fallback |
| localStorage state | Per-user JSON, atomic replacement, preceding-save backup |
| Browser/Rust alarm watchers | Dispatcher polling a persisted UTC queue; immediate overdue/restart recovery |
| Browser typing/math overlays | Native focusable challenge view, paste blocking, keyboard and touch keypad |
| Eight CSS themes | Eight WPF brush palettes |
| Keep awake / wake request | SetThreadExecutionState / waitable resume timer with checked errors |
| Autostart plugin | Per-user Windows Run entry targeting the published executable |
| Network-corrected app time | Windows system time with an explicit settings shortcut |
| Close to tray | Windows notification icon with Open/Quit menu and quit warning |

Sound synthesis uses the reference note pitches, timings, wave shapes and volumes, with native PCM rendering; the exact timbre may differ from a browser oscillator. The browser reference's 10-minute external time resync is intentionally replaced by Windows timekeeping. The app works offline and does not need time-API credentials or network access for alarms.

The UI uses the reference’s compact centered single-column layout, with large clock digits, soft theme glows, gradient accents, rounded fields, segmented time/timer tabs, toggle switches, and an app-painted title bar. All app control templates use explicit theme colors, including dropdown popups; Windows light/dark mode does not choose their colors. Additional changes include labeled alarms, an always-visible next-alarm countdown, keyboard math input, clear desktop-power status, and actionable persistence/audio errors. Existing per-alarm custom sounds are not overwritten by importing another file.

No automatic migration from the old Tauri webview's localStorage is included. Users should recreate alarms in this version. macOS, the static website, recurring alarms, an installer, signing and automatic updates are outside this first Windows implementation.

Recommended follow-ups: recurring weekday alarms; configurable volume and gradual ramp; optional missed-alarm age limit; and a signed installer with an installer-managed login entry. Prioritize real-machine sleep/wake testing before expanding features.
