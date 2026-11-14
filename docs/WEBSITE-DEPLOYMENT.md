# Deploy LunkAlarm to alarm.reeeserve.online

The upload-ready website is the repository's **web/** folder. It includes the desktop clock workspace, recurring alarms, temporary timers, eighteen themes, offline ringtones, custom audio and five wake-up tests. It needs static hosting only. Vercel hosts it; your DNS provider points the subdomain to Vercel. Namecheap registration/hosting and DNS management are separate roles.

## 1. Create a separate Vercel project

In Vercel, choose **Add New → Project** and import **TristanSibug/LunkAlarm** from GitHub. This can be a new Vercel project using the existing repository; do not change the deployment settings of your existing reeeserve.online website.

Use these settings:

| Setting | Value |
| --- | --- |
| Project name | `wake-alarm` (or your preferred name) |
| Production branch | `main` |
| Root Directory | `web` |
| Framework Preset | `Other` |
| Build Command | empty / no build |
| Install Command | empty / no install |
| Output Directory | `.` (current directory, relative to `web`) |
| Environment variables | none |

`web/vercel.json` contains the static deployment configuration. No npm install, Rust, .NET build, server process, API key or Supabase setup is needed to host this version.

Select **Deploy**. Open the new project's `.vercel.app` address first and test it. If Vercel cannot find `web`, check that the import is using the branch containing the website. Do not use the Windows project's build commands.

GitHub import is recommended. If deploying from a local computer with the Vercel CLI, download the source, open a terminal inside `web/`, then run `npx vercel` and follow the project-linking prompts. Verify the preview before deploying production with `npx vercel --prod`. The CLI uses your Vercel login; no keys need to be added to the website files.

## 2. Add the subdomain in Vercel

Open the new alarm project's **Settings → Domains** and add:

```
alarm.reeeserve.online
```

Vercel will show the DNS record required for **this project**. Use that exact destination, including any project-specific hostname. Do not guess a shared IP address or substitute a generic CNAME target from an old tutorial. If Vercel asks for a TXT ownership-verification record, add the exact host/value it provides too.

## 3. Add DNS at the provider that manages your nameservers

In Namecheap, open **Domain List → Manage** next to `reeeserve.online` and check **Nameservers**.

- With **Namecheap BasicDNS/PremiumDNS/FreeDNS**, use **Advanced DNS → Host Records → Add New Record**.
- With **Namecheap Web Hosting DNS**, use your hosting cPanel's **Zone Editor**. An editor asking for the full name should use `alarm.reeeserve.online`.
- With custom nameservers (for example, Cloudflare), edit DNS with that provider instead. Namecheap's Host Records page will not control those nameservers.

The usual subdomain record in Namecheap's Host Records editor is:

| Field | Value |
| --- | --- |
| Type | `CNAME Record` |
| Host | `alarm` |
| Value / Target | **Copy the exact destination shown by Vercel** |
| TTL | Automatic |

Remove or replace an existing conflicting record for **alarm only** if needed. A CNAME cannot coexist with other ordinary records at the same name. Keep your root (`@`), `www`, email and other application records as they are. No whole-domain nameserver change or domain transfer is required just to point this subdomain to Vercel.

## 4. Verify DNS and HTTPS

Return to Vercel's Domains screen and refresh/check the domain. DNS propagation can take time. Once Vercel reports valid configuration and finishes provisioning HTTPS, open:

```
https://alarm.reeeserve.online
```

Test on the final domain: click **Add alarm**, preview a ringtone, add a short timer, complete wake-up tests, change theme, and reload to confirm saved settings. Normal clicks and key presses activate browser audio; no separate sound button is needed. Browser data on the temporary `.vercel.app` address does not automatically transfer to the custom domain because browser storage is origin-specific.

## Supabase

This version uses browser localStorage. It has no accounts or cross-device sync and makes no Supabase requests. Your existing Supabase project does not need changes. Supabase can be added later for login and synchronized alarm preferences; it does not make browser alarms ring while the page/device is asleep. Do not put a Supabase service-role key into this static website.

## Desktop workspace

Each visit starts with a centered clock and a plain downward chevron. Click the chevron or the space below the date/time zone, or scroll downward, to open the workspace. The chevron points upward there; clicking it or scrolling upward **anywhere on the left clock side** returns to the large clock. Wheel gestures over the editor or schedule panel keep that view open. Trackpad momentum is debounced so one gesture causes one transition. The original View Transition mechanism animates the clock, date and controls separately, without competing layout/reveal animations; reduced-motion preferences are respected.

The workspace places the clock on the left, the editor in the center and a permanently expanded alarms/timers panel on the right. The large clock view lists active timers and alarms as organized text, without cards or backgrounds. Selecting an item opens its editor. Smaller windows stack the same panels; mouse/trackpad layouts at least 1000 CSS pixels wide use the available window height with scrolling inside the editor and schedule panel. Add/Save remains visible at the bottom of the editor.

The underlined tabs select **Alarm** for a time of day or **Timer** for a duration. Repeat-day buttons match the iOS editor: 12px rounded rectangles, dark field backgrounds when unset, and a solid accent fill when selected. Daily is a checkbox that selects or clears all seven days. Both support optional names. Alarms can repeat daily or on selected weekdays, remain saved after ringing, and support enable/disable, editing, deletion and exact duplication. One-time alarms switch off after completion. Timers appear first in their own section and disappear once finished. Each item remembers its own sound, volume, fade and test settings.

Desktop time/duration fields support direct typing, mouse-wheel adjustments and arrow keys; the time follows the 12/24-hour display preference. Touch-first devices use native time entry and swipe-and-snap duration wheels, with a **Type instead** fallback. Duration presets occupy one row, hiding trailing choices at narrow widths and sharing available space evenly.

The theme, ringtone and individual test-settings dialogs dismiss when clicking outside their bounds. Closing test settings keeps activation unchanged; Set/Unset remains the activation control. The ringtone picker stays open when selecting a sound, and its SVG chevron sits at the right edge. Enable **Sound checker** to audition choices; closing the picker stops its preview. Import audio or open the existing online-sources window from inside the picker. The play button beside **Alarm volume** previews the selected sound directly at the chosen level, without opening the ringtone picker; click again to stop, or let its six-second preview finish. Starting a real alarm or leaving the workspace stops that preview. Browser volume is a relative playback level, separate from the operating system's volume.

The five wake-up tests match the mobile choices: typing, four-operation math, solid jigsaw puzzle, Minesweeper and Sudoku. A tile opens settings without changing activation; **Set / Unset** changes activation. **Try it** launches an isolated practice session. Real tests run in order; a timeout restarts the sequence and restores sound. Math answers clear automatically with keyboard focus retained. Minesweeper uses right-click or Flag mode, allows excess flags, and enables **I'm done** only at the exact mine count. Sudoku puzzles have one solution. Puzzle placement supports dragging or selecting a piece and clicking its position, with exactly one target per piece and no empty-piece outlines.

Delete/Duplicate uses a rounded floating menu that can extend outside the scrolling list. It opens above its button when needed to stay fully within the window, so the last alarm can always be duplicated or deleted. Outside-click and Escape close it.

The grouped eighteen-theme collection copies the iOS palette values and gradient overlay order, opacity and radii (upper-left accent at 12% for light themes or 22% for dark themes; lower-right secondary accent at 17%), including pale Midnight Cherry alarm cards, coral weekday rings, and a red Signal Blue preview. Theme selection closes its dialog. OLED Black and Dark stay flat; most other backgrounds use subtle gradients.

## Saved data and rollback

Existing `wake.alarms` records migrate in place; a pre-migration copy is stored in `wake.studio.beforeMigration`. One-time alarms more than a minute overdue are retained disabled, recurring alarms advance, and expired non-ringing timers more than a minute overdue are removed. An alarm already ringing resumes after reload, with saved challenge progress and deadline. Storage failures report an error and preserve the previous saved list when adding or editing.

New records retain the original typing/math fields for compatibility. The older website does not understand every new game or recurring schedule, so a code rollback preserves the old interface but cannot provide all new behaviors. Do not clear browser storage as part of a deployment.

The development branch is **website/desktop-studio**. The starting version is preserved on **website/rollback-before-desktop-update** at `85e08a7`. Keep both remote branches. For a production rollback, revert the website-update commit on the production branch and push it; this preserves subsequent mobile commits. Avoid resetting the entire repository to the backup branch.

## Browser limitations

- Keep the page open, sound available and your device awake. Muted tabs/site settings can prevent sound. Normal clicks and key presses activate browser audio.
- Browsers can delay or suspend background tabs; a Web Worker cannot guarantee on-time background delivery. The website cannot wake a sleeping or shut-down device, and closing the page stops it.
- Alarms and preferences belong to the current browser/device and origin. Clearing site data removes them. There is no account or cross-device synchronization.
- Audio imports use browser-supported codecs and localStorage, with a 2 MB limit per file. New alarms snapshot imported audio; multiple large imports may exhaust browser storage.
- Native lock-screen alarms, system volume control and reliable vibration belong to the mobile apps, not the website.
- Internet time sync runs automatically on load, periodically, and when connectivity returns, without a visible status badge. It first reads a fresh same-origin HTTP Date header from a cache-busted HEAD request, compensating for request latency and a small CDN Age value. HTTP Date has whole-second precision. External UTC services are fallbacks. If all sources fail, the clock silently retains its last synchronized offset or uses the device clock.

## Development checks

From the repository root:

```sh
npm ci --prefix tests/web
cd tests/web
npx playwright install chromium
cd ../..
node tests/web/studio.cjs
```

The runner starts its own local static server. It uses system Chromium when available, otherwise Playwright's Chromium. `CHROMIUM_PATH` selects another compatible executable. The older `node tests/web/smoke.cjs` command delegates to the same suite. No test dependencies are shipped in `web/`.

Checks cover clock-area wheel navigation, the always-open schedule panel, rounded weekday boxes and the Daily checkbox, direct sound previews, text-only upcoming items, automatic server-time sync and offline fallback, alarm creation/editing/duplication, timer grouping, legacy migration, theme persistence and native palette/gradient parity, picker backdrop dismissal, bottom-card action menus, ringtone selection, desktop and narrow layouts, completion of all five tests, unique Sudoku generation, Minesweeper confirmation and storage failures. Captures go to `artifacts/web-previews/`. Native Safari still requires real-device verification.

The **Website checks** GitHub Actions workflow runs on website changes and uploads screenshots. Vercel's Git integration deploys independently from its configured production branch (`main` in the settings above); this workflow validates the website but does not itself publish a Vercel deployment. Native build workflows are unaffected by website-only changes.
