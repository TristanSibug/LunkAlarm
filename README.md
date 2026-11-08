# Wake — Alarm Clock

A C# / WPF implementation of Wake, based on the supplied Tauri alarm clock. The Windows app uses native controls, Windows audio and Windows power APIs. It has **no Tauri, Rust, JavaScript, WebView or browser dependency**. The standalone website lives in `web/` and reuses the original browser UI. The native macOS version is future work.

## Native iPhone app

The native SwiftUI app is in **`ios/`**. Open `ios/LunkAlarm.xcodeproj` with Xcode 26 or later; it targets iOS 26+ and uses AlarmKit for system-scheduled alarms. It retains the website's themes, clock-first view, wheel pickers, sound previews/imports, and ringtone-site links. See [iOS setup, cloud builds, signing, and device testing](ios/README.md). macOS Monterey cannot run the required Xcode; GitHub Actions provides an unsigned cloud build, and iPhone installation still requires Apple signing/provisioning or TestFlight.

## Deploy the website with Vercel

Import this repository into a **separate Vercel project** with **Root Directory `web`** and **Framework Preset Other**. No build/install commands, database or environment variables are required. Deploy, then add `alarm.reeeserve.online` in the new project's Domains settings and enter the exact DNS record shown by Vercel at your DNS provider.

See [the Namecheap + Vercel deployment guide](docs/WEBSITE-DEPLOYMENT.md) for the full steps. Upload/deploy the contents of `web/`, not the Windows build or the whole repository. Alarms and settings are stored in each browser; Supabase integration is not included. Keep the page open and the device awake for alarms.

## Run on Windows

Extract **Wake-Windows-x64.zip** into a permanent folder, then open **Wake.exe**. This is a portable, self-contained x64 build: no separate .NET installation is required. Use a supported Windows 10/11 x64 system. Unsigned builds may show SmartScreen's unknown-publisher warning. There is no installer or code-signing certificate included.

Closing the window keeps Wake running in the notification area (possibly under the tray's hidden-icons arrow). Double-click its icon to reopen. Right-click → **Quit Wake…** stops the application after confirmation if alarms remain. Alarms cannot sound while Wake is not running. Start-at-login uses the current executable's location, so enable it after moving the app to its permanent folder.

## Features

- Clock with local date/time zone, 12/24-hour display and a Windows time-settings shortcut.
- One-shot alarms at a clock time (24-hour `HH:mm` input), or countdowns up to 99h 59m 59s; quick duration presets and custom labels.
- Multiple alarms, ordered by due time. Simultaneous alarms ring in sequence. Overdue alarms ring on resume or next launch; an interrupted ringing alarm resumes first.
- Optional, per-alarm typing challenge and 1–8 addition problems. Typing is case sensitive; pasting is blocked. Math accepts the on-screen keypad or keyboard digits/Enter/Backspace. Correct completion dismisses the alarm. There is no snooze or automatic timeout.
- Ten original offline synthesized ringtone recipes, five-second previews, custom WAV/MP3/WMA files up to 2 MB, and a ringtone-site shortcut. Imported files are copied into local app storage; each alarm keeps its own file. Custom audio codecs depend on Windows. Preview before relying on a sound.
- App-owned title bar, fields, dropdowns, switches and scrollbars stay themed independently of Windows light/dark mode. A compact centered layout, soft background glows and gradient accents follow the Tauri design.
- Eight remembered themes: Sunrise, OLED Black, Dark, Light, Tokyo Night, VS Code Blue, Dracula and Nord.
- Tray operation, a single running instance per Windows session, optional login startup, optional idle-sleep prevention and a Windows wake-timer request.
- Atomic local JSON saves with a previous-save backup. Corrupt/unsupported saved data is reported and left untouched. Save and audio failures are visible; audio playback failures trigger a repeating Windows system sound.

## Alarm reliability and data

Wake uses the **Windows system clock**, rather than an independent correction from third-party time services. Enable automatic time/time zone in Windows Settings. Timers are stored as UTC deadlines so they survive restart; manually moving the Windows clock changes their remaining duration. A time-of-day alarm is converted to a fixed UTC deadline when added, so changing your time zone later does not reschedule it.

When daylight saving skips a requested local time, Wake asks for another time. When a time occurs twice, it chooses the first occurrence still in the future. Clock alarms are one-shot, not daily repeats.

**Keep awake** blocks idle system sleep while any alarms remain, while allowing the display to sleep. It does not prevent manual Sleep, shutdown or lid-close policies. **Request wake from sleep** asks Windows to wake one minute before the next alarm. Firmware, Modern Standby, battery policies and the power plan's “Allow wake timers” setting can override this request. The app must remain running. A successful timer request does not guarantee the hardware will wake. No sound can be guaranteed with muted audio, disconnected speakers or unavailable audio devices. Test your machine before using this as your only alarm.

State and imported audio are stored under `%LOCALAPPDATA%\WakeNative\`. `state.json.bak` contains the preceding save. To recover corrupt data, quit Wake, back up this directory, and restore the backup as `state.json`. Existing Tauri/localStorage alarms are **not automatically migrated**. Removing a custom alarm does not delete imported audio files; these can be cleaned up manually while Wake is stopped.

## Develop

Install the **.NET 10 SDK** on Windows. For Visual Studio, use a version supporting .NET 10 with the **.NET desktop development** workload. Open `Wake.sln`, or run from the repository root:

```powershell
dotnet run --project src/Wake.Windows
```

Build and run the dependency-free executable test suite (the command returns nonzero on failure):

```powershell
dotnet build Wake.sln -c Release
dotnet run --project tests/Wake.Core.Tests -c Release
# Windows only: runtime theme checks and rendered PNG previews
dotnet run --project tests/Wake.Windows.Tests -c Release -- artifacts/theme-previews
```

`dotnet test` does not execute this console test suite; use the command above. The core tests also run on Linux/macOS. WPF requires Windows to run. A Linux/macOS SDK can cross-compile the WPF project with its enabled Windows targeting, but cannot validate its UI, playback, registry integration or power APIs.

Publish a self-contained portable build:

```powershell
dotnet publish src/Wake.Windows/Wake.Windows.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o artifacts/win-x64
```

Run `artifacts/win-x64/Wake.exe`. The single-file app may extract runtime files to a .NET-managed temporary directory on first launch. Do not use trimming for WPF. Login startup is intended for the published app, not `dotnet run`. Build artifacts are ignored by Git.

The GitHub Actions workflow builds/tests on Windows, runs native WPF theme checks, captures all eight themes, and uploads zipped executable/source/preview downloads plus SHA-256 files. Pushing a `v*` tag publishes those downloads as a GitHub release after the build succeeds. Branch/PR builds only upload workflow artifacts. The workflow does not install or sign the application. See [Windows acceptance checks](docs/WINDOWS-TESTING.md) before distribution.

## Structure

```text
src/Wake.Core/          Scheduling, alarm data, persistence, challenges, PCM synthesis
src/Wake.Windows/       WPF views, native audio, tray, Windows power and login integration
tests/Wake.Core.Tests/  Executable regression suite (no test-framework packages)
docs/                  Windows acceptance checks and migration notes
```

The scheduling core is independent of WPF and can support future platforms. The website uses its own JavaScript scheduler and cannot provide Windows power-management capabilities.

MIT license. The supplied app's icon and original sound recipes are reused.
