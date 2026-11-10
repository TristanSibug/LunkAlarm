# LunkAlarm

LunkAlarm is an alarm clock available as a **website**, a **native Android app**, and a **native iOS app**. It combines a large clock, custom themes, ringtones, and optional wake-up tests.

**[Open the website → alarm.reeeserve.online](https://alarm.reeeserve.online)** · **[Download mobile builds](https://github.com/TristanSibug/LunkAlarm/releases)**

## Platforms

| Platform | Get started | Requirements | Source and setup |
| --- | --- | --- | --- |
| Website | [alarm.reeeserve.online](https://alarm.reeeserve.online) | A modern browser | [`web/`](web/) · [Deployment guide](docs/WEBSITE-DEPLOYMENT.md) |
| Android | [Download the APK](https://github.com/TristanSibug/LunkAlarm/releases) | Android 8.0 or later | [`android/`](android/) · [Android guide](android/README.md) |
| iOS | [Releases](https://github.com/TristanSibug/LunkAlarm/releases) · [IPA builds](https://github.com/TristanSibug/LunkAlarm/actions/workflows/ios.yml) | iOS 26 or later; Apple signing/provisioning | [`ios/`](ios/) · [iOS guide](ios/README.md) |

The Android app uses **Kotlin and Jetpack Compose**. The iOS app uses **SwiftUI and AlarmKit**. Both are native apps with their own system alarm integration. The standalone website runs directly in a browser.

The repository also retains the earlier native C# / WPF Windows implementation in `src/`. A native macOS app remains future work.

## Mobile app features

- A large clock-first screen with local date, time zone, and 12/24-hour display. Swipe up to view alarms and down to return to the clock.
- Saved alarms with optional names, daily or selected-weekday repeats, editing, duplication, and swipe-to-delete with haptic feedback.
- Active countdowns alongside saved alarms. Completed countdowns disappear; At a time alarms stay until deleted.
- Floating Add alarm / Save changes buttons, looping time controls, and collapsible wake-up test settings.
- Nineteen app-owned themes, ten offline ringtones, sound previews, audio-file imports, a volume slider, and optional gradual fade-in.
- Configurable timed typing and math tests (plus Android jigsaw puzzles), automatic math answer submission, an answering sound switch, and progress resets when a test times out.
- Native alarm scheduling so a scheduled alarm does not depend on keeping the clock screen open.

Android 1.1 adds readable dark-theme controls, the iOS 1.6 theme/repeat-day updates, keyboard entry for time wheels, an optional native math keypad, and solid-color jigsaw tests with 6–10 randomized pieces. Wake-up test timers use five-second steps: math 5/10/15, typing 15/20/25/30, and puzzle 15/20/25/30/35/40 seconds.

Alarms, themes, and imported sounds are saved locally on each device. There is no account requirement or cross-device synchronization. The website and mobile apps have separate saved data, and some features differ by platform.

## Install the mobile apps

**Android:** Download the `.apk` from [Releases](https://github.com/TristanSibug/LunkAlarm/releases), open it on your phone, and allow installation from your browser or file manager if Android asks. In LunkAlarm, open **Alarm access** and enable alarms, notifications, and full-screen alarms where available. Overall sound level uses your device's alarm volume.

**iOS:** Download the `.ipa` from [Releases](https://github.com/TristanSibug/LunkAlarm/releases) when attached, or extract it from a successful **Native iOS app** Actions build. The cloud-generated IPA is unsigned and needs signing/provisioning through AltStore Classic/AltServer or another compatible signing tool before installation. GitHub hosting does not replace Apple's signing requirements. See the [iOS guide](ios/README.md) for setup and build instructions.

These are development/test builds, separate from App Store or Google Play distribution. Test a short alarm with the phone locked before relying on it overnight. System permissions, volume, Focus/Do Not Disturb, force-stop behavior, and device battery settings affect alarm behavior; the platform guides explain the differences.

## Use and deploy the website

Use **[alarm.reeeserve.online](https://alarm.reeeserve.online)** directly, without installing an app. Keep the page open, sound available, and the device awake: browsers can delay background tabs, and the website cannot wake a sleeping device.

To deploy your own copy with Vercel, use **Root Directory `web`** and **Framework Preset Other**. No build/install command, database, Supabase connection, or environment variables are required. Add your domain in Vercel and configure the DNS records Vercel provides. See the [Namecheap + Vercel deployment guide](docs/WEBSITE-DEPLOYMENT.md).

## Source, builds, and tests

| Directory | Contents |
| --- | --- |
| [`web/`](web/) | Browser app and Vercel configuration |
| [`ios/`](ios/) | Native SwiftUI app, AlarmKit integration, core/UI tests, and Xcode project |
| [`android/`](android/) | Native Compose app, Android alarm service, core/UI tests, and Gradle project |
| [`src/Wake.Core/`](src/Wake.Core/) | Earlier Windows scheduling, persistence, challenges, and sound synthesis |
| [`src/Wake.Windows/`](src/Wake.Windows/) | Earlier native WPF Windows app |
| [`docs/`](docs/) | Deployment and Windows documentation |

The **Native iOS app** workflow builds simulator/device targets, runs core and native UI tests, and uploads an unsigned IPA. The **Native Android app** workflow builds a signed development APK, runs core tests, Android lint, and emulator checks, and packages successful builds in its **LunkAlarm-Android** Actions artifact. GitHub Releases are uploaded manually by the maintainer. Each platform guide includes local build commands and installation details.

MIT license. The supplied app's icon and original sound recipes are reused.

