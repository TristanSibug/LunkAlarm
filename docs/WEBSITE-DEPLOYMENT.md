# Deploy Wake to alarm.reeeserve.online

The upload-ready website is the repository's **web/** folder. It contains the original browser UI, all eight themes, generated ringtones, custom audio, alarms, timers and typing/math challenges. It needs static hosting only. Vercel hosts it; your DNS provider points the subdomain to Vercel. Namecheap registration/hosting and DNS management are separate roles.

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

Test on the final domain: click **Enable sound**, preview a ringtone, add a short timer, complete typing/math tests, change theme, and reload to confirm saved settings. Browser data on the temporary `.vercel.app` address does not automatically transfer to the custom domain because browser storage is origin-specific.

## Supabase

This version uses browser localStorage. It has no accounts or cross-device sync and makes no Supabase requests. Your existing Supabase project does not need changes. Supabase can be added later for login and synchronized alarm preferences; it does not make browser alarms ring while the page/device is asleep. Do not put a Supabase service-role key into this static website.

## Automatic layouts

Wide screens (at least 1000 CSS pixels) with a primary mouse/trackpad use a fixed-height workspace: clock on the left, expanded alarm setup in the middle, and a collapsible alarms sidebar on the right. The sidebar starts collapsed, shows the alarm count, and remembers your open/closed preference. Opening it reveals the list; closing it gives the space back to the form. Escape from inside the sidebar collapses it and returns focus to its toggle. The page itself does not scroll. Long lists and expanded settings in smaller windows can scroll inside their panels, and Add alarm stays visible.

The desktop time picker has editable hour/minute fields, arrow-key/stepper controls and an AM/PM toggle; it follows the 12/24-hour clock setting. At spacious panel widths, ringtone controls sit beside wake-up tests, with the two ringtone links on separate lines. Narrow panels stack those sections to keep everything accessible.

Touch-first devices and narrower windows retain the stacked phone layout and native time input. Switching screen size or input capabilities updates the layout automatically without resetting alarms or reloading the page. This uses responsive CSS rather than unreliable device-name guessing.

## Browser limitations

- Keep the page open, sound enabled, and your device awake. Muted tabs/site settings can prevent sound.
- Browsers can delay or suspend background tabs; a Web Worker cannot guarantee on-time background delivery.
- A website cannot wake a sleeping or shut-down computer, and closing the page stops it.
- Alarms and preferences belong to the current browser/device. Clearing site data removes them.
- On reopening, the original app resumes ringing alarms and retains alarms less than a minute overdue; older non-ringing missed alarms are discarded, matching the supplied frontend.
- Custom audio uses browser-supported codecs and localStorage (2 MB per imported clip). The original frontend has one custom ringtone slot; importing another file changes the sound used by custom-tone alarms.
- Internet time services may be unavailable or blocked by browser CORS/network rules. The clock reports the device-clock fallback. The site still runs without these services.

## Development checks

From the repository root, install Playwright locally in `tests/web` (not in the deployed `web/` directory), then run the browser checks:

```
npm install --prefix tests/web --no-save playwright
npx --prefix tests/web playwright install chromium
node tests/web/smoke.cjs
```

The runner uses system Chromium when available, otherwise Playwright's Chromium. Set `CHROMIUM_PATH` to select another compatible executable. Tests exercise offline startup, sound activation, all eight themes with both system color schemes, phone width, timers, challenge order/wrong answers, queues, reload persistence, and storage failures. Captures are written to `artifacts/web-previews/`.
