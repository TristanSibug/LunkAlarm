/* =========================================================
   WAKE - alarm clock (the brain of the app)

   What this file does, in order:
     1. Small helper functions
     2. Saved settings (remembered after you close the app)
     3. Getting the correct time (internet first, device clock as backup)
     4. Drawing the clock on screen
     5. The 10 built-in ringtones + the sound player
     6. The alarms: add, delete, ring until dismissed
     7. The wake-up tests (typing code, math problems)
     8. Buttons and what they do
     9. Themes (the color schemes)
    10. Start everything up

   You can have as many alarms as you like. When one rings, it keeps
   ringing until you finish the tests it was set with (or tap Stop if
   there are none). If two alarms are due together, they ring one
   after the other.
   ========================================================= */


/* ---------------------------------------------------------
   1. SMALL HELPERS
   --------------------------------------------------------- */

// Shortcut: $('abc') finds the element in the page that has id="abc".
const $ = (id) => document.getElementById(id);

// Adds a leading zero to small numbers so 7 becomes "07".
const pad = (n) => String(n).padStart(2, '0');

// A random whole number from min to max (both included).
function randomInt(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}


/* ---------------------------------------------------------
   2. SAVED SETTINGS
   localStorage is a tiny notebook the browser/app keeps for us.
   Things we write in it are still there next time we open the app.
   We use try/catch because writing can fail (for example when the
   notebook is full), and we don't want the whole app to crash.
   --------------------------------------------------------- */

// Read a saved value. If nothing is saved yet, give back "fallback".
function loadSaved(key, fallback) {
  try {
    const text = localStorage.getItem(key);
    return text === null ? fallback : JSON.parse(text);
  } catch (err) {
    return fallback;
  }
}

// Save a value. Returns true if it worked, false if it failed.
function save(key, value) {
  try {
    localStorage.setItem(key, JSON.stringify(value));
    return true;
  } catch (err) {
    return false;
  }
}

// One object that holds everything the app needs to remember.
const state = {
  use24h: loadSaved('wake.use24h', false),            // 12-hour or 24-hour clock
  mode: loadSaved('wake.mode', 'time'),               // 'time' or 'timer' tab
  ringtoneId: loadSaved('wake.ringtone', 'classic-beep'),
  customRingtone: loadSaved('wake.custom', null),     // {name, dataUrl} or null

  // The two wake-up tests. Both start switched OFF.
  typingOn: loadSaved('wake.typingOn', false),
  mathOn: loadSaved('wake.mathOn', false),
  // How many math problems (1 to 8). Keep it inside that range.
  mathCount: Math.min(8, Math.max(1, Number(loadSaved('wake.mathCount', 3)) || 3)),

  themeId: loadSaved('wake.theme', 'sunrise'),        // which color scheme

  // The list of alarms. Each one looks like:
  //   { id: 'abc123',              a unique name, to tell alarms apart
  //     targetMs: 1730000000000,   exact moment it should ring
  //     ringtoneId: 'soft-chime',
  //     typing: true,              typing test on?
  //     mathCount: 3,              how many math problems (0 = math test off)
  //     ringing: false }           has it started ringing?
  alarms: loadSaved('wake.alarms', []),

  timeOffsetMs: 0,        // how far this device's clock is from the real time
  hasSynced: false,       // did we ever get the time from the internet?
  ringing: null,          // the alarm that is ringing right now (or null)
};

// Largest audio file we allow for "Use my own file" (2 megabytes).
const MAX_CUSTOM_BYTES = 2 * 1024 * 1024;


/* ---------------------------------------------------------
   3. GETTING THE CORRECT TIME
   Idea: ask a time website what time it is. Compare its answer
   with this computer's clock. The difference is the "offset".
   Real time = device clock + offset.
   If there is no internet we just keep offset as it is
   (0 the first time, so we use the plain device clock).
   --------------------------------------------------------- */

// Several free time websites. If the first one fails we try the next.
// Each "read" function pulls the time (in milliseconds) out of that site's answer.
const TIME_SOURCES = [
  {
    url: 'https://worldtimeapi.org/api/timezone/Etc/UTC',
    read: async (response) => {
      const data = await response.json();
      // Some browsers dislike more than 3 digits after the seconds, so trim them.
      return Date.parse(data.utc_datetime.replace(/(\.\d{3})\d+/, '$1'));
    },
  },
  {
    url: 'https://timeapi.io/api/Time/current/zone?timeZone=UTC',
    read: async (response) => {
      const data = await response.json();
      return Date.parse(data.dateTime.slice(0, 23) + 'Z');
    },
  },
  {
    url: 'https://www.cloudflare.com/cdn-cgi/trace',
    read: async (response) => {
      const text = await response.text();
      const line = text.split('\n').find((l) => l.startsWith('ts='));
      return Number(line.slice(3)) * 1000; // seconds -> milliseconds
    },
  },
];

// The "real" current time in milliseconds. Use this instead of Date.now().
function trueNow() {
  return Date.now() + state.timeOffsetMs;
}

// Updates the little badge at the top of the clock.
function setSyncBadge(status) {
  const badge = $('syncBadge');
  badge.dataset.state = status; // the CSS colors the dot based on this

  if (status === 'online') {
    $('syncText').textContent = 'Synced with internet time';
    const seconds = (state.timeOffsetMs / 1000).toFixed(1);
    badge.title = 'Your device clock was off by ' + seconds + ' seconds. Fixed.';
  } else if (status === 'offline') {
    $('syncText').textContent = state.hasSynced
      ? 'Offline - using last synced time'
      : 'Offline - using this device clock';
    badge.title = '';
  } else {
    $('syncText').textContent = 'Checking time...';
  }
}

// Asks the time websites for the time. Safe to call again and again.
async function syncTime() {
  for (const source of TIME_SOURCES) {
    // This timer cancels the request if the site takes longer than 5 seconds.
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 5000);

    try {
      const startedAt = Date.now();
      const response = await fetch(source.url, { cache: 'no-store', signal: controller.signal });
      if (!response.ok) throw new Error('site said no');

      const serverMs = await source.read(response);
      const endedAt = Date.now();
      if (!Number.isFinite(serverMs)) throw new Error('could not read the time');

      // The answer took a moment to travel to us, so assume it was
      // created halfway through the trip.
      const serverTimeNow = serverMs + (endedAt - startedAt) / 2;
      state.timeOffsetMs = serverTimeNow - endedAt;
      state.hasSynced = true;
      setSyncBadge('online');
      return; // success, so stop trying other sites
    } catch (err) {
      // This site failed. The loop moves on to the next one.
    } finally {
      clearTimeout(timeout);
    }
  }
  // Every site failed (probably no internet).
  setSyncBadge('offline');
}


/* ---------------------------------------------------------
   4. DRAWING THE CLOCK
   --------------------------------------------------------- */

// Turns a Date into text pieces for the big clock.
// Example (12-hour): { hm: "7:05", sec: "09", ampm: "PM" }
function getClockParts(date) {
  const hours = date.getHours();      // 0 to 23
  const minutes = date.getMinutes();
  const seconds = date.getSeconds();

  if (state.use24h) {
    return { hm: pad(hours) + ':' + pad(minutes), sec: pad(seconds), ampm: '' };
  }
  const ampm = hours >= 12 ? 'PM' : 'AM';
  const hours12 = hours % 12 || 12;   // 0 becomes 12, 13 becomes 1, etc.
  return { hm: hours12 + ':' + pad(minutes), sec: pad(seconds), ampm: ampm };
}

// Short text version, like "7:05 PM" or "19:05".
function formatClockTime(date) {
  const parts = getClockParts(date);
  return parts.ampm ? parts.hm + ' ' + parts.ampm : parts.hm;
}

// Puts the current time on the screen.
function renderClock() {
  const now = new Date(trueNow());
  const parts = getClockParts(now);

  $('clockHM').textContent = parts.hm;
  $('clockSec').textContent = parts.sec;
  $('clockAmPm').textContent = parts.ampm;
  $('dateText').textContent = now.toLocaleDateString(undefined, {
    weekday: 'long', month: 'long', day: 'numeric',
  });
}

// Turns milliseconds into text like "2h 03m 10s".
function formatRemaining(ms) {
  const total = Math.max(0, Math.ceil(ms / 1000));
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  if (h > 0) return h + 'h ' + pad(m) + 'm ' + pad(s) + 's';
  if (m > 0) return m + 'm ' + pad(s) + 's';
  return s + 's';
}

// Says "Today", "Tomorrow", or a date like "Fri, Nov 6".
function dayLabel(targetMs) {
  const target = new Date(targetMs);
  const now = new Date(trueNow());
  // Cut a date down to midnight so we compare whole days only.
  const midnight = (d) => new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
  const days = Math.round((midnight(target) - midnight(now)) / 86400000);

  if (days === 0) return 'Today';
  if (days === 1) return 'Tomorrow';
  return target.toLocaleDateString(undefined, { weekday: 'short', month: 'short', day: 'numeric' });
}


/* ---------------------------------------------------------
   5. RINGTONES
   Instead of shipping 10 audio files, each ringtone is a short
   "recipe" and the browser's built-in synthesizer (Web Audio)
   plays it. Benefits: works offline, tiny app, no copyright worries.

   Each note is:  [pitch in Hz, start time in seconds, length in seconds]
   (a siren note can have a 4th number: the pitch it slides to)

   wave   = the "sound color" of the synthesizer
   style  = 'beep' (steady, like a digital alarm) or 'ring' (fades out, like a bell)
   volume = how loud (0 to 1)
   cycle  = after this many seconds the pattern starts over
   --------------------------------------------------------- */

// Musical note names -> pitch in Hz, so the recipes are easy to read.
const N = {
  C3: 130.81, C4: 261.63, G4: 392.0, A4: 440.0,
  C5: 523.25, D5: 587.33, E5: 659.25, G5: 783.99, A5: 880.0,
  C6: 1046.5, D6: 1174.66, E6: 1318.51, G6: 1567.98,
};

// Helper: a bell strike is several pitches at once (low to high) fading out.
const bellStrike = (t) => [
  [N.C3, t, 2.4], [N.C4, t, 2.0], [314.0, t, 1.4], [N.G4, t, 1.0],
];

// Helper: a quick climbing run of 6 notes starting at time t.
const arcadeRun = (t) =>
  [N.C5, N.E5, N.G5, N.C6, N.E6, N.G6].map((pitch, i) => [pitch, t + i * 0.09, 0.07]);

const BUILT_IN_RINGTONES = [
  { id: 'classic-beep', name: 'Classic Beep', wave: 'square', style: 'beep', volume: 0.10, cycle: 1.6,
    notes: [[880, 0, 0.12], [880, 0.22, 0.12], [880, 0.44, 0.12], [880, 0.66, 0.12]] },

  { id: 'digital-watch', name: 'Digital Watch', wave: 'square', style: 'beep', volume: 0.09, cycle: 1.4,
    notes: [[N.E6, 0, 0.08], [N.C6, 0.12, 0.08], [N.E6, 0.24, 0.08], [N.C6, 0.36, 0.08]] },

  { id: 'soft-chime', name: 'Soft Chime', wave: 'sine', style: 'ring', volume: 0.22, cycle: 3.2,
    notes: [[N.C5, 0, 1.4], [N.E5, 0.4, 1.4], [N.G5, 0.8, 1.4], [N.C6, 1.2, 1.8]] },

  { id: 'xylophone', name: 'Xylophone', wave: 'triangle', style: 'ring', volume: 0.30, cycle: 2.6,
    notes: [[N.C5, 0, 0.35], [N.D5, 0.2, 0.35], [N.E5, 0.4, 0.35], [N.G5, 0.6, 0.35],
            [N.A5, 0.8, 0.35], [N.G5, 1.0, 0.35], [N.E5, 1.2, 0.35], [N.D5, 1.4, 0.35]] },

  { id: 'sonar-ping', name: 'Sonar Ping', wave: 'sine', style: 'ring', volume: 0.35, cycle: 2.2,
    notes: [[N.C6, 0, 1.6]] },

  { id: 'church-bell', name: 'Church Bell', wave: 'sine', style: 'ring', volume: 0.14, cycle: 3.6,
    notes: [...bellStrike(0), ...bellStrike(1.8)] },

  { id: 'rise-and-shine', name: 'Rise & Shine', wave: 'triangle', style: 'ring', volume: 0.25, cycle: 3.2,
    notes: [[N.G4, 0, 0.6], [N.C5, 0.3, 0.6], [N.E5, 0.6, 0.6], [N.G5, 0.9, 0.6], [N.C6, 1.2, 1.4]] },

  { id: 'retro-arcade', name: 'Retro Arcade', wave: 'square', style: 'beep', volume: 0.08, cycle: 1.8,
    notes: [...arcadeRun(0), ...arcadeRun(0.8)] },

  { id: 'wind-bells', name: 'Wind Bells', wave: 'sine', style: 'ring', volume: 0.20, cycle: 4.2,
    notes: [[N.E6, 0, 1.4], [N.C6, 0.5, 1.4], [N.G6, 0.9, 1.4],
            [N.A5, 1.5, 1.4], [N.D6, 2.0, 1.4], [N.G5, 2.6, 1.4]] },

  { id: 'siren', name: 'Siren', wave: 'sawtooth', style: 'beep', volume: 0.08, cycle: 1.4,
    notes: [[600, 0, 0.7, 1000], [1000, 0.7, 0.7, 600]] },
];

// Finds a ringtone recipe by its id (falls back to the first one).
function findRingtone(id) {
  return BUILT_IN_RINGTONES.find((t) => t.id === id) || BUILT_IN_RINGTONES[0];
}

// ----- The sound player -----

let audioCtx = null; // the browser's audio engine (created on first use)

// Gets the audio engine, making it if needed. Browsers only allow sound
// after the person has clicked something, so we also "resume" it here
// (we call this inside button clicks).
function getAudioContext() {
  if (!audioCtx) {
    const AudioContextClass = window.AudioContext || window.webkitAudioContext;
    audioCtx = new AudioContextClass();
  }
  if (audioCtx.state === 'suspended') audioCtx.resume().catch(() => {});
  return audioCtx;
}

// Plays ONE round of a ringtone recipe.
// "destination" is where the sound goes (a volume knob we can cut later).
function playCycle(tone, ctx, destination) {
  const startAt = ctx.currentTime + 0.05; // tiny delay so scheduling is safe

  tone.notes.forEach((note) => {
    const pitch = note[0];
    const offset = note[1];
    const length = note[2];
    const slideTo = note[3]; // only the siren has this

    const t0 = startAt + offset;   // when this note starts
    const t1 = t0 + length;        // when this note ends

    const osc = ctx.createOscillator(); // makes the raw tone
    const gain = ctx.createGain();      // controls how loud it is over time
    osc.type = tone.wave;
    osc.frequency.setValueAtTime(pitch, t0);
    if (slideTo) osc.frequency.linearRampToValueAtTime(slideTo, t1);

    // Volume shape: start silent, fade in very fast (stops clicking sounds)...
    gain.gain.setValueAtTime(0.0001, t0);
    gain.gain.linearRampToValueAtTime(tone.volume, t0 + 0.01);
    if (tone.style === 'beep') {
      // ...stay steady, then switch off quickly at the end.
      gain.gain.setValueAtTime(tone.volume, t1 - 0.02);
      gain.gain.linearRampToValueAtTime(0.0001, t1);
    } else {
      // ...or slowly fade away like a struck bell.
      gain.gain.exponentialRampToValueAtTime(0.0001, t1);
    }

    osc.connect(gain);
    gain.connect(destination);
    osc.start(t0);
    osc.stop(t1 + 0.05);
  });
}

// Remembers what is currently playing so we can stop it.
let sound = { loopTimer: null, stopTimer: null, master: null, audioEl: null };
let previewing = false;

// Starts a ringtone and keeps repeating it until stopSound() is called.
function startSound(ringtoneId) {
  stopSound(); // never play two things at once

  // Case 1: the person's own audio file.
  if (ringtoneId === 'custom' && state.customRingtone) {
    const audio = new Audio(state.customRingtone.dataUrl);
    audio.loop = true;
    audio.play().catch(() => {}); // the browser may refuse until a click; we retry (see wakeAudio)
    sound.audioEl = audio;
    return;
  }

  // Case 2: one of the built-in ringtones.
  const tone = findRingtone(ringtoneId);
  const ctx = getAudioContext();

  // A "master" volume knob. Everything plays through it, so on stop we
  // can silence even the notes that were already scheduled.
  const master = ctx.createGain();
  master.connect(ctx.destination);
  sound.master = master;

  // Play one round, but ONLY if the audio engine is really running.
  // (If the browser is still blocking sound, we skip instead of piling
  // up notes that would all burst out at once later.)
  const playNow = () => {
    if (sound.master === master && ctx.state === 'running') playCycle(tone, ctx, master);
  };

  if (ctx.state === 'running') playNow();
  else ctx.resume().then(playNow).catch(() => {}); // start as soon as sound is allowed

  sound.loopTimer = setInterval(playNow, tone.cycle * 1000);
}

// Stops whatever is playing.
function stopSound() {
  clearInterval(sound.loopTimer);
  clearTimeout(sound.stopTimer);
  if (sound.master) {
    sound.master.gain.setValueAtTime(0, audioCtx.currentTime); // mute now
    sound.master.disconnect();
  }
  if (sound.audioEl) sound.audioEl.pause();
  sound = { loopTimer: null, stopTimer: null, master: null, audioEl: null };
}

// A normal click or key press unlocks sound, including for saved alarms
// after a reload. No separate sound-enable control is needed.
function wakeAudio() {
  getAudioContext();
  if (sound.audioEl) {
    if (sound.audioEl.paused) sound.audioEl.play().catch(() => {});
  }
}

// Updates the Preview button text.
function setPreviewing(isOn) {
  previewing = isOn;
  $('previewBtn').textContent = isOn ? 'Stop' : 'Preview';
  $('previewBtn').dataset.playing = String(isOn);
}

// Preview button: play the chosen ringtone for up to 6 seconds.
function togglePreview() {
  if (previewing) {
    stopSound();
    setPreviewing(false);
    return;
  }
  startSound(state.ringtoneId);
  setPreviewing(true);
  sound.stopTimer = setTimeout(() => { stopSound(); setPreviewing(false); }, 6000);
}

// A select-only combobox. The native select remains the value model and fallback.
let ringtonePickerReady = false;
let activeRingtone = 0;
let ringtoneSearch = '';
let ringtoneSearchAt = 0;
function ringtoneOptions() { return Array.from($('ringtoneMenu').querySelectorAll('[role="option"]')); }
function ringtoneMenuOpen() { return ringtonePickerReady && $('ringtoneMenu').matches(':popover-open'); }

function renderRingtonePicker() {
  if (!ringtonePickerReady) return;
  const select = $('ringtoneSelect');
  $('ringtonePickerLabel').textContent = select.selectedOptions[0]?.textContent || 'Choose a ringtone';
  const menu = $('ringtoneMenu');
  menu.replaceChildren();
  const title = document.createElement('div');
  title.className = 'ringtone-menu-title'; title.setAttribute('role', 'presentation');
  title.textContent = 'Choose a ringtone'; menu.appendChild(title);
  Array.from(select.options).forEach((option, index) => {
    const row = document.createElement('div');
    row.id = 'ringtone-option-' + index; row.className = 'ringtone-option';
    row.setAttribute('role', 'option'); row.setAttribute('aria-selected', String(option.selected));
    row.dataset.value = option.value;
    const name = document.createElement('span'); name.className = 'ringtone-option-name'; name.textContent = option.textContent;
    const check = document.createElement('span'); check.className = 'ringtone-option-check';
    check.textContent = '✓'; check.setAttribute('aria-hidden', 'true');
    row.append(name, check); menu.appendChild(row);
  });
  activeRingtone = Math.max(0, select.selectedIndex);
  if (ringtoneMenuOpen()) { positionRingtoneMenu(); highlightRingtone(activeRingtone); }
}

function positionRingtoneMenu() {
  const button = $('ringtonePicker'), menu = $('ringtoneMenu');
  const rect = button.getBoundingClientRect();
  if (rect.bottom < 0 || rect.top > innerHeight) { closeRingtonePicker(); return; }
  const below = innerHeight - rect.bottom - 16, above = rect.top - 16;
  const openBelow = below >= 200 || below >= above;
  const height = Math.min(330, Math.max(80, openBelow ? below : above));
  const width = Math.min(rect.width, innerWidth - 24);
  menu.style.width = width + 'px'; menu.style.maxHeight = height + 'px';
  menu.style.left = Math.max(12, Math.min(rect.left, innerWidth - width - 12)) + 'px';
  menu.style.top = (openBelow ? rect.bottom + 7 : rect.top - menu.getBoundingClientRect().height - 7) + 'px';
}

function highlightRingtone(index) {
  const options = ringtoneOptions();
  if (!options.length) return;
  activeRingtone = Math.max(0, Math.min(index, options.length - 1));
  options.forEach((option, i) => { option.dataset.active = String(i === activeRingtone); });
  $('ringtonePicker').setAttribute('aria-activedescendant', options[activeRingtone].id);
  options[activeRingtone].scrollIntoView({ block: 'nearest' });
}
function openRingtonePicker() {
  if (!ringtonePickerReady || ringtoneMenuOpen()) return;
  ringtoneSearch = ''; ringtoneSearchAt = 0;
  $('ringtoneMenu').showPopover();
  $('ringtonePicker').setAttribute('aria-expanded', 'true');
  positionRingtoneMenu(); highlightRingtone($('ringtoneSelect').selectedIndex);
}
function closeRingtonePicker(focus = false) {
  if (!ringtonePickerReady) return;
  if (ringtoneMenuOpen()) $('ringtoneMenu').hidePopover();
  $('ringtonePicker').setAttribute('aria-expanded', 'false');
  $('ringtonePicker').removeAttribute('aria-activedescendant');
  if (focus) $('ringtonePicker').focus();
}
function chooseRingtone(index) {
  const select = $('ringtoneSelect');
  select.selectedIndex = index;
  select.dispatchEvent(new Event('change', { bubbles: true }));
  closeRingtonePicker(true);
}
function setupRingtonePicker() {
  // Older browsers retain the working native select instead of an incomplete custom menu.
  if (typeof HTMLElement.prototype.showPopover !== 'function') return;
  ringtonePickerReady = true;
  $('ringtoneSelect').hidden = true;
  $('ringtoneMenu').hidden = false;
  $('ringtonePicker').hidden = false;
  $('ringtoneLabel').htmlFor = 'ringtonePicker';
  renderRingtonePicker();
  const button = $('ringtonePicker'), menu = $('ringtoneMenu');
  button.addEventListener('click', event => {
    event.preventDefault(); // We position the associated popover and manage its active option.
    if (ringtoneMenuOpen()) closeRingtonePicker(); else openRingtonePicker();
  });
  button.addEventListener('keydown', event => {
    const open = ringtoneMenuOpen();
    if (event.key === 'Tab') { closeRingtonePicker(); return; }
    if (event.key === 'Escape') { if (open) { event.preventDefault(); closeRingtonePicker(true); } return; }
    if (['ArrowDown', 'ArrowUp', 'Home', 'End', 'Enter', ' '].includes(event.key)) {
      event.preventDefault();
      if (!open) openRingtonePicker();
      else if (event.key === 'Enter' || event.key === ' ') { chooseRingtone(activeRingtone); return; }
      else if (event.key === 'ArrowDown') highlightRingtone(activeRingtone + 1);
      else if (event.key === 'ArrowUp') highlightRingtone(activeRingtone - 1);
      if (event.key === 'Home') highlightRingtone(0);
      if (event.key === 'End') highlightRingtone(ringtoneOptions().length - 1);
    } else if (event.key.length === 1 && !event.ctrlKey && !event.metaKey && !event.altKey) {
      event.preventDefault();
      if (!open) openRingtonePicker();
      const now = performance.now();
      ringtoneSearch = now - ringtoneSearchAt < 700 ? ringtoneSearch + event.key.toLowerCase() : event.key.toLowerCase();
      ringtoneSearchAt = now;
      const options = Array.from($('ringtoneSelect').options);
      const start = ringtoneSearch.length === 1 ? activeRingtone + 1 : activeRingtone;
      for (let n = 0; n < options.length; n++) {
        const i = (start + n) % options.length;
        if (options[i].textContent.toLowerCase().startsWith(ringtoneSearch)) { highlightRingtone(i); break; }
      }
    }
  });
  menu.addEventListener('pointerdown', event => { if (event.target.closest('[role="option"]')) event.preventDefault(); });
  menu.addEventListener('pointermove', event => {
    const option = event.target.closest('[role="option"]');
    if (option) {
      // Hover updates the keyboard cursor without scrolling a menu under the pointer.
      activeRingtone = ringtoneOptions().indexOf(option);
      ringtoneOptions().forEach(row => { row.dataset.active = String(row === option); });
      button.setAttribute('aria-activedescendant', option.id);
    }
  });
  menu.addEventListener('click', event => {
    const option = event.target.closest('[role="option"]');
    if (option) chooseRingtone(ringtoneOptions().indexOf(option));
  });
  menu.addEventListener('beforetoggle', event => {
    button.setAttribute('aria-expanded', String(event.newState === 'open'));
    if (event.newState === 'closed') button.removeAttribute('aria-activedescendant');
  });
  menu.addEventListener('toggle', () => {
    const open = ringtoneMenuOpen(); button.setAttribute('aria-expanded', String(open));
    if (!open) button.removeAttribute('aria-activedescendant');
  });
  window.addEventListener('resize', () => { if (ringtoneMenuOpen()) positionRingtoneMenu(); });
  window.addEventListener('scroll', event => {
    if (ringtoneMenuOpen() && !(event.target instanceof Node && menu.contains(event.target))) positionRingtoneMenu();
  }, true);
}

// Fills the dropdown with the 10 built-in ringtones (+ the person's own file).
function fillRingtoneSelect() {
  const select = $('ringtoneSelect');
  select.innerHTML = '';

  BUILT_IN_RINGTONES.forEach((tone) => {
    const option = document.createElement('option');
    option.value = tone.id;
    option.textContent = tone.name;
    select.appendChild(option);
  });

  if (state.customRingtone) {
    const option = document.createElement('option');
    option.value = 'custom';
    option.textContent = 'My file: ' + state.customRingtone.name;
    select.appendChild(option);
  }

  // If the saved choice doesn't exist anymore, fall back to the first one.
  const exists = Array.from(select.options).some((o) => o.value === state.ringtoneId);
  if (!exists) state.ringtoneId = BUILT_IN_RINGTONES[0].id;
  select.value = state.ringtoneId;
  renderRingtonePicker();
}


/* ---------------------------------------------------------
   6. THE ALARMS
   --------------------------------------------------------- */

// The native HH:mm input stays the canonical alarm value and the phone control.
let selectedTimePeriod = 'AM';
let timePickerErrorShown = false;
function renderTimePicker() {
  const match = /^(\d{2}):(\d{2})$/.exec($('timeInput').value);
  const hour = match ? Number(match[1]) : null;
  const minute = match ? Number(match[2]) : null;
  selectedTimePeriod = hour !== null && hour >= 12 ? 'PM' : 'AM';
  $('alarmHour').value = hour === null ? '' : pad(state.use24h ? hour : hour % 12 || 12);
  $('alarmMinute').value = minute === null ? '' : pad(minute);
  $('alarmHour').setAttribute('aria-valuemin', state.use24h ? '0' : '1');
  $('alarmHour').setAttribute('aria-valuemax', state.use24h ? '23' : '12');
  $('timePeriod').hidden = state.use24h;
  for (const period of ['AM', 'PM']) $('time' + period).setAttribute('aria-pressed', String(period === selectedTimePeriod));
  for (const part of ['Hour', 'Minute']) {
    const input = $('alarm' + part);
    if (input.value) input.setAttribute('aria-valuenow', String(Number(input.value)));
    else input.removeAttribute('aria-valuenow');
    input.removeAttribute('aria-invalid');
  }
}
function commitTimePicker(format = false) {
  const hourText = $('alarmHour').value.trim(), minuteText = $('alarmMinute').value.trim();
  const hour = Number(hourText), minute = Number(minuteText);
  const validHour = /^\d{1,2}$/.test(hourText) && hour >= (state.use24h ? 0 : 1) && hour <= (state.use24h ? 23 : 12);
  const validMinute = /^\d{1,2}$/.test(minuteText) && minute >= 0 && minute <= 59;
  for (const [part, valid] of [['Hour', validHour], ['Minute', validMinute]]) {
    const input = $('alarm' + part);
    input.setAttribute('aria-invalid', String(!valid));
    if (valid) input.setAttribute('aria-valuenow', String(Number(input.value)));
    else input.removeAttribute('aria-valuenow');
  }
  if (!validHour || !validMinute) { $('timeInput').value = ''; return false; }
  const canonicalHour = state.use24h ? hour : hour % 12 + (selectedTimePeriod === 'PM' ? 12 : 0);
  $('timeInput').value = pad(canonicalHour) + ':' + pad(minute);
  if (timePickerErrorShown) showMessage('', false);
  if (format) { $('alarmHour').value = pad(hour); $('alarmMinute').value = pad(minute); }
  return true;
}
function stepAlarmTime(part, direction) {
  commitTimePicker();
  const match = /^(\d{2}):(\d{2})$/.exec($('timeInput').value);
  const total = match ? Number(match[1]) * 60 + Number(match[2]) : 7 * 60;
  const next = (total + (part === 'hour' ? 60 : 1) * direction + 1440) % 1440;
  $('timeInput').value = pad(Math.floor(next / 60)) + ':' + pad(next % 60);
  renderTimePicker();
}
function updateTimePickerLayout() {
  $('timeInput').hidden = desktopWorkspace.matches;
  $('customTimePicker').hidden = !desktopWorkspace.matches;
  $('ringAtLabel').htmlFor = desktopWorkspace.matches ? 'alarmHour' : 'timeInput';
  renderTimePicker();
}
function setupTimePicker() {
  updateTimePickerLayout();
  desktopWorkspace.addEventListener('change', updateTimePickerLayout);
  $('timeInput').addEventListener('input', renderTimePicker);
  $('timeInput').addEventListener('change', renderTimePicker);
  document.querySelectorAll('#customTimePicker .time-step').forEach(button => button.addEventListener('click', () => {
    stepAlarmTime(button.dataset.part, Number(button.dataset.step));
  }));
  for (const part of ['Hour', 'Minute']) {
    const input = $('alarm' + part);
    bindPickerWheel(input.closest('.time-part'), input, direction => stepAlarmTime(part.toLowerCase(), direction));
    input.addEventListener('input', () => commitTimePicker());
    input.addEventListener('blur', () => commitTimePicker(true));
    input.addEventListener('keydown', event => {
      if (event.key === 'ArrowUp' || event.key === 'ArrowDown') {
        event.preventDefault(); stepAlarmTime(part.toLowerCase(), event.key === 'ArrowUp' ? 1 : -1);
      } else if (event.key === 'Enter') {
        event.preventDefault(); if (commitTimePicker(true)) $('setBtn').focus();
      }
    });
  }
  for (const period of ['AM', 'PM']) $('time' + period).addEventListener('click', () => {
    selectedTimePeriod = period;
    for (const item of ['AM', 'PM']) $('time' + item).setAttribute('aria-pressed', String(item === period));
    commitTimePicker(true);
  });
}

// Wheel capture is limited to the hovered number. Ctrl-wheel still zooms, and
// wheel movement elsewhere continues to scroll the settings panel normally.
function bindPickerWheel(element, input, step) {
  let accumulated = 0, lastWheel = 0;
  element.title = 'Scroll up to increase; scroll down to decrease';
  element.addEventListener('wheel', event => {
    if (!desktopWorkspace.matches || event.ctrlKey || event.metaKey || !event.deltaY || Math.abs(event.deltaX) >= Math.abs(event.deltaY)) return;
    event.preventDefault();
    event.stopPropagation();
    const delta = event.deltaY * (event.deltaMode === 1 ? 16 : event.deltaMode === 2 ? 100 : 1);
    const now = performance.now();
    if (now - lastWheel > 180 || (accumulated && Math.sign(accumulated) !== Math.sign(delta))) accumulated = 0;
    lastWheel = now;
    accumulated += delta;
    if (Math.abs(accumulated) < 40) return;
    accumulated = 0; // At most one step per mouse notch; tiny trackpad events accumulate.
    input.focus({ preventScroll: true });
    step(delta < 0 ? 1 : -1);
  }, { passive: false });
}
// Touch-first countdown wheels use native scrolling and snap to the centered row.
const mobileDurationUnits = [['hours', 'hours', 99], ['minutes', 'min', 59], ['seconds', 'sec', 59]];
const durationRowHeight = 44;
let mobileDurationReady = false;
let manualMobileDuration = false;
function setMobileDurationValue(unit, value, scroll = false) {
  const wheel = $('durationWheel-' + unit);
  const max = Number(wheel.dataset.max);
  value = Math.max(0, Math.min(max, value));
  const previous = Number(wheel.dataset.selected || 0);
  $('duration-' + unit + '-' + previous)?.setAttribute('aria-selected', 'false');
  $('duration-' + unit + '-' + value).setAttribute('aria-selected', 'true');
  wheel.dataset.selected = String(value);
  wheel.setAttribute('aria-activedescendant', 'duration-' + unit + '-' + value);
  $(unit + 'Input').value = String(value);
  if (scroll && wheel.getClientRects().length) wheel.scrollTo({ top: value * durationRowHeight, behavior: 'instant' });
}
function syncMobileDurationWheels() {
  if (!mobileDurationReady || desktopWorkspace.matches) return;
  for (const [unit, , max] of mobileDurationUnits) setMobileDurationValue(unit, readNumber(unit + 'Input', max), true);
}
function commitMobileDuration() {
  if (!mobileDurationReady || desktopWorkspace.matches || manualMobileDuration || !$('mobileDurationPicker').getClientRects().length) return;
  for (const [unit] of mobileDurationUnits) {
    const wheel = $('durationWheel-' + unit);
    setMobileDurationValue(unit, Math.round(wheel.scrollTop / durationRowHeight), true);
  }
}
function updateMobileDurationLayout() {
  const desktop = desktopWorkspace.matches;
  $('nativeDurationInputs').hidden = !desktop && !manualMobileDuration;
  $('mobileDurationPicker').hidden = desktop || manualMobileDuration;
  $('durationEntryToggle').hidden = desktop;
  $('durationEntryToggle').textContent = manualMobileDuration ? 'Use scroll wheels' : 'Type instead';
  $('durationEntryToggle').setAttribute('aria-pressed', String(manualMobileDuration));
  renderCountdownFields();
}
function setupMobileDuration() {
  for (const [unit, label, max] of mobileDurationUnits) {
    const column = document.createElement('div'); column.className = 'duration-wheel-column';
    const frame = document.createElement('div'); frame.className = 'duration-wheel-frame';
    const wheel = document.createElement('div'); wheel.id = 'durationWheel-' + unit;
    wheel.className = 'duration-wheel-scroll'; wheel.setAttribute('role', 'listbox');
    wheel.setAttribute('aria-label', 'Countdown ' + unit); wheel.tabIndex = 0;
    wheel.dataset.max = String(max); wheel.dataset.selected = '0';
    for (let value = 0; value <= max; value++) {
      const row = document.createElement('div'); row.id = 'duration-' + unit + '-' + value;
      row.className = 'duration-wheel-option'; row.setAttribute('role', 'option');
      row.setAttribute('aria-selected', 'false'); row.setAttribute('aria-label', value + ' ' + unit);
      row.dataset.value = String(value); row.textContent = pad(value); wheel.appendChild(row);
    }
    wheel.addEventListener('scroll', () => {
      if (!desktopWorkspace.matches && !manualMobileDuration && wheel.getClientRects().length) setMobileDurationValue(unit, Math.round(wheel.scrollTop / durationRowHeight));
    }, { passive: true });
    wheel.addEventListener('click', event => {
      const row = event.target.closest('[role="option"]');
      if (row) setMobileDurationValue(unit, Number(row.dataset.value), true);
    });
    wheel.addEventListener('keydown', event => {
      const value = Number(wheel.dataset.selected);
      const next = { ArrowDown: value + 1, ArrowUp: value - 1, Home: 0, End: max, PageDown: value + 5, PageUp: value - 5 }[event.key];
      if (next === undefined) return;
      event.preventDefault(); setMobileDurationValue(unit, next, true);
    });
    const caption = document.createElement('span'); caption.className = 'duration-wheel-unit'; caption.textContent = label;
    frame.appendChild(wheel); column.append(frame, caption); $('mobileDurationPicker').appendChild(column);
  }
  mobileDurationReady = true;
  $('durationEntryToggle').addEventListener('click', () => {
    commitMobileDuration(); manualMobileDuration = !manualMobileDuration; updateMobileDurationLayout();
  });
  desktopWorkspace.addEventListener('change', updateMobileDurationLayout);
  updateMobileDurationLayout();
}

function renderCountdownFields() {
  for (const [unit, max] of [['hours', 99], ['minutes', 59], ['seconds', 59]]) {
    const input = $(unit + 'Input');
    const value = readNumber(input.id, max);
    input.value = desktopWorkspace.matches ? pad(value) : String(value);
  }
  syncMobileDurationWheels();
}
function stepCountdown(unit, direction) {
  const total = readNumber('hoursInput', 99) * 3600 + readNumber('minutesInput', 59) * 60 + readNumber('secondsInput', 59);
  const next = Math.min(99 * 3600 + 59 * 60 + 59, Math.max(0, total + { hours: 3600, minutes: 60, seconds: 1 }[unit] * direction));
  $('hoursInput').value = Math.floor(next / 3600);
  $('minutesInput').value = Math.floor(next % 3600 / 60);
  $('secondsInput').value = next % 60;
  renderCountdownFields();
}
function setupCountdownPicker() {
  renderCountdownFields();
  desktopWorkspace.addEventListener('change', renderCountdownFields);
  for (const unit of ['hours', 'minutes', 'seconds']) {
    const input = $(unit + 'Input');
    bindPickerWheel(input.closest('.timer-box'), input, direction => stepCountdown(unit, direction));
    input.addEventListener('blur', () => { if (desktopWorkspace.matches) renderCountdownFields(); });
    input.addEventListener('keydown', event => {
      if (!desktopWorkspace.matches) return;
      if (event.key === 'ArrowUp' || event.key === 'ArrowDown') {
        event.preventDefault(); stepCountdown(unit, event.key === 'ArrowUp' ? 1 : -1);
      }
    });
  }
  document.querySelectorAll('.duration-step').forEach(button => button.addEventListener('click', () => {
    stepCountdown(button.dataset.unit, Number(button.dataset.step));
  }));
  setupMobileDuration();
}

// For "At a time": finds the next moment the clock shows that time.
// If 7:00 already passed today, it means 7:00 tomorrow.
function nextOccurrenceOf(hhmm) {
  const parts = hhmm.split(':');                 // "07:30" -> ["07", "30"]
  const target = new Date(trueNow());
  target.setHours(Number(parts[0]), Number(parts[1]), 0, 0);
  if (target.getTime() <= trueNow()) target.setDate(target.getDate() + 1);
  return target.getTime();
}

// Makes a brand-new id for an alarm, so we can tell alarms apart.
function newId() {
  return Date.now() + '-' + Math.random().toString(16).slice(2);
}

// Saves the whole list of alarms in the notebook.
function saveAlarms() {
  const saved = save('wake.alarms', state.alarms);
  if (!saved) showMessage('Could not save alarms. Check browser storage permissions or free some space.', true);
  return saved;
}

// Adds an alarm to the list. We copy the current test settings into it,
// so each alarm remembers exactly what it should ask for when it rings.
function addAlarm(targetMs) {
  const alarm = {
    id: newId(),
    targetMs: targetMs,
    ringtoneId: state.ringtoneId,
    typing: state.typingOn,
    mathCount: state.mathOn ? state.mathCount : 0,
    ringing: false,
  };
  state.alarms.push(alarm);
  state.alarms.sort((a, b) => a.targetMs - b.targetMs); // earliest first
  if (!saveAlarms()) {
    state.alarms = state.alarms.filter((a) => a !== alarm);
    return false;
  }
  renderAlarmList();
  return true;
}

// Deletes an alarm. An alarm that is ringing cannot be deleted:
// only finishing its tests can stop it.
function deleteAlarm(id) {
  if (state.ringing && state.ringing.id === id) return;
  state.alarms = state.alarms.filter((a) => a.id !== id);
  saveAlarms();
  renderAlarmList();
}

// Text under each alarm, like "Soft Chime · Typing test · Math x3".
function describeAlarm(alarm) {
  const ringtoneName = alarm.ringtoneId === 'custom' && state.customRingtone
    ? state.customRingtone.name
    : findRingtone(alarm.ringtoneId).name;

  const parts = [ringtoneName];
  if (alarm.typing) parts.push('Typing test');
  if (alarm.mathCount > 0) parts.push('Math x' + alarm.mathCount);
  if (!alarm.typing && alarm.mathCount === 0) parts.push('No test');
  return parts.join(' · ');
}

// The clock is the default view on every visit; alarm state is independent of the view.
let alarmPickerOpen = false;
let clockViewTransition = null;
let clockViewRequest = 0;
function updateClockActions() {
  $('alarmPickerToggle').setAttribute('aria-expanded', String(alarmPickerOpen));
  $('alarmPickerText').textContent = alarmPickerOpen ? 'Hide alarm picker' : 'Add alarm';
  $('alarmPickerIcon').textContent = alarmPickerOpen ? '−' : '+';
  $('footnote').textContent = alarmPickerOpen ? 'Alarms and themes are saved in this browser on this device.' : 'Keep this page open and your device awake for alarms.';
  $('clockAlarmsToggle').hidden = alarmPickerOpen || state.alarms.length === 0;
  $('clockAlarmsToggle').textContent = 'Your alarms (' + state.alarms.length + ')';
}
function applyAlarmPickerView(open) {
  if (!open) {
    commitMobileDuration(); closeRingtonePicker();
    if ($('setupCard').contains(document.activeElement) || $('alarmsCard').contains(document.activeElement)) $('alarmPickerToggle').focus({ preventScroll: true });
  }
  alarmPickerOpen = open;
  document.documentElement.classList.toggle('clock-focus', !open);
  $('mainApp').classList.toggle('picker-open', open);
  $('setupCard').inert = !open; $('alarmsCard').inert = !open;
  updateClockActions();
  if (open) { renderCountdownFields(); fitDurationPresets(); }
}
function setAlarmPickerOpen(open) {
  const request = ++clockViewRequest;
  const update = () => { if (request === clockViewRequest) applyAlarmPickerView(open); };
  if (clockViewTransition) clockViewTransition.skipTransition();
  if (!document.startViewTransition || window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
    update(); return Promise.resolve();
  }
  const transition = document.startViewTransition(update);
  clockViewTransition = transition;
  transition.ready.catch(() => {});
  return transition.finished.catch(() => {}).finally(() => { if (clockViewTransition === transition) clockViewTransition = null; });
}
function setupClockView() {
  $('alarmPickerToggle').addEventListener('click', () => setAlarmPickerOpen(!alarmPickerOpen));
  $('clockAlarmsToggle').addEventListener('click', async () => {
    setAlarmsSidebar(true);
    await setAlarmPickerOpen(true);
    if (!desktopWorkspace.matches) $('alarmsCard').scrollIntoView({ behavior: window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 'instant' : 'smooth', block: 'start' });
    $('alarmsHeading').tabIndex = -1; $('alarmsHeading').focus({ preventScroll: true });
  });
  applyAlarmPickerView(false);
}

// Keep the largest leading set of presets that fits at its natural readable size.
function fitDurationPresets() {
  const row = document.querySelector('.presets');
  const width = row.clientWidth;
  if (!width) return;
  const buttons = Array.from(row.querySelectorAll('.chip'));
  const gap = parseFloat(getComputedStyle(row).columnGap) || 0;
  const widths = buttons.map(button => {
    button.hidden = false;
    const oldWidth = button.style.width, oldFlex = button.style.flex;
    button.style.width = 'max-content'; button.style.flex = '0 0 auto';
    const measured = button.getBoundingClientRect().width;
    button.style.width = oldWidth; button.style.flex = oldFlex;
    return measured;
  });
  let used = 0, visible = 0;
  for (const natural of widths) {
    const next = used + (visible ? gap : 0) + natural;
    if (next > width + .5) break;
    used = next; visible++;
  }
  visible = Math.max(1, visible);
  const focus = document.activeElement;
  buttons.forEach((button, index) => { button.hidden = index >= visible; });
  if (buttons.indexOf(focus) >= visible) buttons[visible - 1].focus({ preventScroll: true });
}
function setupDurationPresets() {
  const row = document.querySelector('.presets');
  if (window.ResizeObserver) new ResizeObserver(fitDurationPresets).observe(row);
  window.addEventListener('resize', fitDurationPresets);
  document.fonts?.ready.then(fitDurationPresets);
  fitDurationPresets();
}

// The alarms rail is desktop-only; the full list always remains visible on phones.
const desktopWorkspace = window.matchMedia('(min-width: 1000px) and (hover: hover) and (pointer: fine)');
let alarmsSidebarOpen = loadSaved('wake.alarmsSidebarOpen', false) === true;
function updateAlarmsSidebar() {
  const desktop = desktopWorkspace.matches;
  const open = desktop && alarmsSidebarOpen;
  const button = $('alarmsToggle'), panel = $('alarmsPanel');
  if (desktop && !open && panel.contains(document.activeElement)) button.focus();
  $('mainApp').classList.toggle('alarms-open', open);
  $('alarmsCount').textContent = String(state.alarms.length);
  button.setAttribute('aria-expanded', String(open));
  button.setAttribute('aria-label', (open ? 'Collapse your alarms' : 'Show your alarms') + ' (' + state.alarms.length + ')');
  button.title = open ? 'Collapse alarms sidebar' : 'Show your alarms';
  updateClockActions();
  panel.inert = desktop && !open;
  if (desktop && !open) panel.setAttribute('aria-hidden', 'true');
  else panel.removeAttribute('aria-hidden');
}
function setAlarmsSidebar(open) {
  alarmsSidebarOpen = open;
  save('wake.alarmsSidebarOpen', open);
  updateAlarmsSidebar();
}
$('alarmsToggle').addEventListener('click', () => setAlarmsSidebar(!alarmsSidebarOpen));
$('alarmsCard').addEventListener('keydown', event => {
  if (event.key === 'Escape' && desktopWorkspace.matches && alarmsSidebarOpen) {
    event.preventDefault(); setAlarmsSidebar(false); $('alarmsToggle').focus();
  }
});
desktopWorkspace.addEventListener('change', updateAlarmsSidebar);

// Draws the list of alarms.
function renderAlarmList() {
  updateAlarmsSidebar();
  const list = $('alarmList');
  list.innerHTML = '';
  $('emptyText').classList.toggle('hidden', state.alarms.length > 0);

  state.alarms.forEach((alarm) => {
    const item = document.createElement('li');
    item.className = 'alarm-item';

    // Left side: big time, then small lines with day, countdown and tests.
    const info = document.createElement('div');

    const time = document.createElement('div');
    time.className = 'alarm-time';
    time.textContent = formatClockTime(new Date(alarm.targetMs));

    const meta = document.createElement('div');
    meta.className = 'alarm-meta';
    meta.appendChild(document.createTextNode(dayLabel(alarm.targetMs) + ' · rings in '));
    // This span is refreshed every tick (see updateCountdowns).
    const remaining = document.createElement('span');
    remaining.className = 'remaining';
    remaining.dataset.target = alarm.targetMs;
    remaining.textContent = formatRemaining(alarm.targetMs - trueNow());
    meta.appendChild(remaining);

    const tests = document.createElement('div');
    tests.className = 'alarm-tests';
    tests.textContent = describeAlarm(alarm);

    info.appendChild(time);
    info.appendChild(meta);
    info.appendChild(tests);

    // Right side: delete button.
    const del = document.createElement('button');
    del.type = 'button';
    del.className = 'delete-btn';
    del.setAttribute('aria-label', 'Delete alarm');
    del.textContent = '×';
    del.addEventListener('click', () => deleteAlarm(alarm.id));

    item.appendChild(info);
    item.appendChild(del);
    list.appendChild(item);
  });
}

// Refreshes every "rings in ..." text without rebuilding the whole list.
function updateCountdowns() {
  document.querySelectorAll('.remaining').forEach((span) => {
    const msLeft = Number(span.dataset.target) - trueNow();
    // An alarm that is due but waiting for another alarm to finish says "next".
    span.textContent = msLeft <= 0 ? 'next' : formatRemaining(msLeft);
  });
}

// Called many times a second: has an alarm's time arrived?
function checkAlarm() {
  if (state.ringing) return; // one at a time: wait until this one is dismissed
  const now = trueNow();
  // An alarm that was already ringing (before a reload) goes first,
  // then any alarm whose time has come.
  const due = state.alarms.find((a) => a.ringing) || state.alarms.find((a) => a.targetMs <= now);
  if (due) startRinging(due);
}

// Makes an alarm ring: full screen, sound, and the first test.
function startRinging(alarm) {
  closeRingtonePicker();
  // Remember that it is ringing, so if the page is reloaded
  // the alarm picks up ringing again instead of vanishing.
  alarm.ringing = true;
  saveAlarms();
  state.ringing = alarm;
  setPreviewing(false);

  // Build the list of steps the person must finish, in order.
  const steps = [];
  if (alarm.typing) steps.push('typing');
  if (alarm.mathCount > 0) steps.push('math');
  if (steps.length === 0) steps.push('stop'); // no tests: just a Stop button

  challenge = {
    steps: steps, stepIndex: 0,
    code: '',
    mathTotal: alarm.mathCount, mathDone: 0, a: 0, b: 0, answer: '',
  };

  $('ringTime').textContent = formatClockTime(new Date(alarm.targetMs));
  $('ringOverlay').classList.remove('hidden');
  // "inert" switches off the whole page behind the ringing screen, so
  // nobody can Tab over to a Delete button and sneak around the tests.
  $('mainApp').inert = true;
  document.title = '⏰ LunkAlarm';

  startSound(alarm.ringtoneId);
  showStep();
}

// The alarm is finished: stop sound, close the screen, remove it from the list.
function dismissAlarm() {
  const finished = state.ringing;
  stopSound();
  state.ringing = null;
  state.alarms = state.alarms.filter((a) => a !== finished);
  saveAlarms();

  $('ringOverlay').classList.add('hidden');
  $('mainApp').inert = false;
  document.title = 'LunkAlarm';
  renderAlarmList();
  // If another alarm is already due, tick() will start it a moment later.
}


/* ---------------------------------------------------------
   7. THE WAKE-UP TESTS
   While ringing, the person goes through "steps":
     typing -> math   (only the ones that were switched on)
     stop             (only when no test is on)
   --------------------------------------------------------- */

// Everything about the test currently in progress.
let challenge = { steps: [], stepIndex: 0, code: '', mathTotal: 0, mathDone: 0, a: 0, b: 0, answer: '' };

// Makes a quick shake animation on an element (used for wrong answers).
function shake(element) {
  element.classList.remove('shake');
  void element.offsetWidth;          // forces the browser to restart the animation
  element.classList.add('shake');
}

// Shows the screen for the current step and hides the others.
function showStep() {
  const step = challenge.steps[challenge.stepIndex];

  $('stepStop').classList.toggle('hidden', step !== 'stop');
  $('stepTyping').classList.toggle('hidden', step !== 'typing');
  $('stepMath').classList.toggle('hidden', step !== 'math');

  // "Step 1 of 2" only makes sense when there is more than one step.
  $('stepInfo').textContent = challenge.steps.length > 1
    ? 'Step ' + (challenge.stepIndex + 1) + ' of ' + challenge.steps.length
    : '';

  if (step === 'stop') {
    $('stopBtn').focus();
  } else if (step === 'typing') {
    challenge.code = makeCode(8);
    $('codeText').textContent = challenge.code;
    $('codeInput').value = '';
    $('typingMsg').textContent = '';
    $('codeInput').focus();
  } else if (step === 'math') {
    challenge.mathDone = 0;
    $('mathMsg').textContent = '';
    newProblem();
  }
}

// A step was completed. Go to the next one, or finish the alarm.
function finishStep() {
  challenge.stepIndex += 1;
  if (challenge.stepIndex >= challenge.steps.length) {
    dismissAlarm();
  } else {
    showStep();
  }
}

// ----- Typing test -----

const CODE_CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

// Makes a random code like "Xa01krlD".
// crypto.getRandomValues gives better random numbers than Math.random.
// We keep re-rolling until the code has at least one capital letter,
// one small letter and one digit, so it always looks like a real mixed code.
function makeCode(length) {
  let code = '';
  do {
    const randoms = new Uint32Array(length);
    crypto.getRandomValues(randoms);
    code = '';
    for (let i = 0; i < length; i++) {
      code += CODE_CHARS[randoms[i] % CODE_CHARS.length];
    }
  } while (!/[A-Z]/.test(code) || !/[a-z]/.test(code) || !/[0-9]/.test(code));
  return code;
}

// Runs every time the person types in the code box.
function onCodeTyped() {
  const typed = $('codeInput').value;
  if (typed.length < challenge.code.length) return; // keep waiting

  if (typed === challenge.code) {         // capital letters matter!
    finishStep();
  } else {
    $('typingMsg').textContent = 'Not quite - check the code and try again';
    shake($('codeText'));
    $('codeInput').value = '';
  }
}

// ----- Math test -----

// Makes a new addition problem with both numbers from 1 to 20.
function newProblem() {
  challenge.a = randomInt(1, 20);
  challenge.b = randomInt(1, 20);
  challenge.answer = '';

  $('mathProgress').textContent = 'Problem ' + (challenge.mathDone + 1) + ' of ' + challenge.mathTotal;
  $('mathProblem').textContent = challenge.a + ' + ' + challenge.b + ' = ?';
  $('mathAnswer').textContent = '';
}

// A keypad button (or keyboard key) was pressed: a digit, 'del' or 'ok'.
function pressKey(key) {
  if (key === 'ok') {
    submitAnswer();
    return;
  }
  if (key === 'del') {
    challenge.answer = challenge.answer.slice(0, -1);
  } else if (challenge.answer.length < 2) {   // answers are at most 40, so 2 digits
    challenge.answer += key;
  }
  $('mathAnswer').textContent = challenge.answer;
}

// Checks the typed answer.
function submitAnswer() {
  if (challenge.answer === '') return;

  if (Number(challenge.answer) === challenge.a + challenge.b) {
    challenge.mathDone += 1;
    $('mathMsg').textContent = '';
    if (challenge.mathDone >= challenge.mathTotal) {
      finishStep();      // all problems solved
    } else {
      newProblem();      // next one
    }
  } else {
    $('mathMsg').textContent = 'Not right - try again';
    shake($('mathProblem'));
    challenge.answer = '';
    $('mathAnswer').textContent = '';
  }
}


/* ---------------------------------------------------------
   8. BUTTONS AND WHAT THEY DO
   --------------------------------------------------------- */

// A small message under the Set button. isError = true makes it red.
let msgTimer = null;
function showMessage(text, isError) {
  timePickerErrorShown = false;
  const el = $('formMsg');
  el.textContent = text;
  el.classList.toggle('error', Boolean(isError));
  clearTimeout(msgTimer);
  msgTimer = setTimeout(() => { el.textContent = ''; }, 5000);
}

// Shows the right tab: "At a time" or "In how long".
function applyMode(mode) {
  state.mode = mode;
  save('wake.mode', mode);
  $('panelTime').classList.toggle('hidden', mode !== 'time');
  $('panelTimer').classList.toggle('hidden', mode !== 'timer');
  $('tabTime').setAttribute('aria-selected', String(mode === 'time'));
  $('tabTimer').setAttribute('aria-selected', String(mode === 'timer'));
  if (mode === 'timer') { renderCountdownFields(); fitDurationPresets(); }
}

// Updates the 12h/24h button text to show which mode is on.
function applyFormatButton() {
  $('formatBtn').textContent = state.use24h ? '24h' : '12h';
  renderTimePicker();
}

// Shows the saved test settings: switch positions, the 1-8 row, etc.
function applyTestSettings() {
  $('typingToggle').checked = state.typingOn;
  $('mathToggle').checked = state.mathOn;
  $('mathCountWrap').classList.toggle('hidden', !state.mathOn);

  document.querySelectorAll('.count-btn').forEach((button) => {
    button.setAttribute('aria-pressed', String(Number(button.dataset.count) === state.mathCount));
  });
}

// Reads a number box safely: blank or silly values become 0, and
// the result is kept between 0 and "max".
function readNumber(id, max) {
  const value = parseInt($(id).value, 10);
  if (Number.isNaN(value)) return 0;
  return Math.min(Math.max(value, 0), max);
}

// Tabs.
$('tabTime').addEventListener('click', () => applyMode('time'));
$('tabTimer').addEventListener('click', () => applyMode('timer'));

// 12h / 24h switch.
$('formatBtn').addEventListener('click', () => {
  state.use24h = !state.use24h;
  save('wake.use24h', state.use24h);
  applyFormatButton();
  renderClock();
  renderAlarmList();
  if (state.ringing) $('ringTime').textContent = formatClockTime(new Date(state.ringing.targetMs));
});

// Quick buttons (5 min, 10 min, ...) fill the hours/minutes/seconds boxes.
document.querySelectorAll('.presets .chip').forEach((button) => {
  button.addEventListener('click', () => {
    const totalMinutes = Number(button.dataset.minutes);
    $('hoursInput').value = Math.floor(totalMinutes / 60);
    $('minutesInput').value = totalMinutes % 60;
    $('secondsInput').value = 0;
    renderCountdownFields();
  });
});

// Choosing a different ringtone.
$('ringtoneSelect').addEventListener('change', () => {
  state.ringtoneId = $('ringtoneSelect').value;
  save('wake.ringtone', state.ringtoneId);
  renderRingtonePicker();
  if (previewing) { stopSound(); setPreviewing(false); }
});
$('previewBtn').addEventListener('click', togglePreview);

// "Use my own file": open the hidden file picker.
$('uploadBtn').addEventListener('click', () => $('fileInput').click());

$('fileInput').addEventListener('change', () => {
  const file = $('fileInput').files[0];
  if (!file) return;

  if (!file.type.startsWith('audio/')) {
    showMessage('Please choose an audio file (mp3, wav, m4a, ogg).', true);
    return;
  }
  if (file.size > MAX_CUSTOM_BYTES) {
    showMessage('That file is too big. Pick a clip under 2 MB.', true);
    return;
  }

  // Read the file into text form so it can be saved in the notebook.
  const reader = new FileReader();
  reader.onload = () => {
    state.customRingtone = { name: file.name, dataUrl: reader.result };
    if (!save('wake.custom', state.customRingtone)) {
      state.customRingtone = null;
      showMessage('Could not save that file. Try a shorter clip.', true);
      return;
    }
    state.ringtoneId = 'custom';
    save('wake.ringtone', 'custom');
    fillRingtoneSelect();
    showMessage('Ringtone added: ' + file.name);
  };
  reader.readAsDataURL(file);
  $('fileInput').value = ''; // so picking the same file again still works
});

// "Find more ringtones online": open the pop-up with website buttons.
$('onlineBtn').addEventListener('click', () => $('onlineDialog').showModal());
$('closeDialogBtn').addEventListener('click', () => $('onlineDialog').close());

// Each ringtone website opens in a separate tab.
document.querySelectorAll('.site-btn').forEach((button) => {
  button.addEventListener('click', () => {
    openLink(button.dataset.url);
  });
});

// The two test switches.
$('typingToggle').addEventListener('change', () => {
  state.typingOn = $('typingToggle').checked;
  save('wake.typingOn', state.typingOn);
});
$('mathToggle').addEventListener('change', () => {
  state.mathOn = $('mathToggle').checked;
  save('wake.mathOn', state.mathOn);
  applyTestSettings(); // shows or hides the 1-8 row
});

// The 1-8 buttons: how many math problems.
document.querySelectorAll('.count-btn').forEach((button) => {
  button.addEventListener('click', () => {
    state.mathCount = Number(button.dataset.count);
    save('wake.mathCount', state.mathCount);
    applyTestSettings();
  });
});

// THE main button: Set alarm.
$('setBtn').addEventListener('click', () => {
  getAudioContext(); // this click "unlocks" sound so the alarm can ring later

  let targetMs;

  if (state.mode === 'time') {
    if (desktopWorkspace.matches && !commitTimePicker(true)) {
      showMessage(state.use24h ? 'Enter an hour from 00–23 and minutes from 00–59.' : 'Enter an hour from 01–12 and minutes from 00–59, then choose AM or PM.', true);
      timePickerErrorShown = true;
      return;
    }
    const value = $('timeInput').value;
    if (!value) {
      showMessage('Please pick a time first.', true);
      return;
    }
    targetMs = nextOccurrenceOf(value);
  } else {
    commitMobileDuration();
    const totalSeconds =
      readNumber('hoursInput', 99) * 3600 +
      readNumber('minutesInput', 59) * 60 +
      readNumber('secondsInput', 59);
    if (totalSeconds <= 0) {
      showMessage('Pick a length of time greater than zero.', true);
      return;
    }
    targetMs = trueNow() + totalSeconds * 1000;
  }

  if (!addAlarm(targetMs)) return;
  showMessage(
    'Alarm added for ' + formatClockTime(new Date(targetMs)) +
    ' (' + dayLabel(targetMs) + ') · rings in ' + formatRemaining(targetMs - trueNow())
  );
});

// The Stop button (only shown when no test is switched on).
$('stopBtn').addEventListener('click', finishStep);

// Typing test box. We also block pasting, so the code has to be typed by hand.
$('codeInput').addEventListener('input', onCodeTyped);
$('codeInput').addEventListener('paste', (event) => event.preventDefault());
$('codeInput').addEventListener('drop', (event) => event.preventDefault());

// Math keypad buttons.
document.querySelectorAll('.key').forEach((button) => {
  button.addEventListener('click', () => pressKey(button.dataset.key));
});

// Keyboard support for the math test: digits, Backspace and Enter work too.
// (There is NO Escape shortcut on purpose: nothing skips the tests.)
document.addEventListener('keydown', (event) => {
  wakeAudio();
  if (!state.ringing || challenge.steps[challenge.stepIndex] !== 'math') return;
  if (event.metaKey || event.ctrlKey || event.altKey) return;

  if (/^[0-9]$/.test(event.key)) {
    pressKey(event.key);
    event.preventDefault();
  } else if (event.key === 'Backspace') {
    pressKey('del');
    event.preventDefault();
  } else if (event.key === 'Enter') {
    pressKey('ok');
    event.preventDefault();
  }
});
document.addEventListener('click', wakeAudio);


// Open ringtone sources without giving the destination access to this tab.
function openLink(url) { window.open(url, '_blank', 'noopener,noreferrer'); }

// Browsers may pause background work; catch up immediately on return.
document.addEventListener('visibilitychange', () => {
  if (!document.hidden) tick();
});

/* ---------------------------------------------------------
   9. THEMES
   A theme is a set of colors defined in style.css. Here we only keep
   a list (for the picker) and switch the data-theme attribute on the
   <html> tag. The small preview in the picker uses these colors:
     bg = background, text = text color, a and b = the two accent colors
   --------------------------------------------------------- */

const THEMES = [
  { id: 'sunrise',     name: 'Sunrise (default)', bg: '#0a0c16', text: '#f4f2ff', a: '#ffa94d', b: '#ff6b7a' },
  { id: 'oled',        name: 'OLED Black',        bg: '#000000', text: '#f2f2f5', a: '#ffa94d', b: '#ff6b7a' },
  { id: 'dark',        name: 'Dark',              bg: '#1a1b1f', text: '#ececf1', a: '#ffa94d', b: '#ff6b7a' },
  { id: 'light',       name: 'Light',             bg: '#f3f2f8', text: '#1c1b2e', a: '#e8801c', b: '#e2505f' },
  { id: 'tokyo-night', name: 'Tokyo Night',       bg: '#1a1b26', text: '#c0caf5', a: '#7aa2f7', b: '#bb9af7' },
  { id: 'vscode-blue', name: 'VS Code Blue',      bg: '#002451', text: '#e8f0ff', a: '#5db0ff', b: '#3a86ff' },
  { id: 'dracula',     name: 'Dracula',           bg: '#282a36', text: '#f8f8f2', a: '#bd93f9', b: '#ff79c6' },
  { id: 'nord',        name: 'Nord',              bg: '#2e3440', text: '#eceff4', a: '#88c0d0', b: '#81a1c1' },
];

// Switches to a theme and remembers the choice.
function applyTheme(id) {
  // If the saved id is not in the list (for example, an old version), use the default.
  if (!THEMES.some((t) => t.id === id)) id = 'sunrise';
  state.themeId = id;
  document.documentElement.setAttribute('data-theme', id);
  save('wake.theme', id);

  // Highlight the matching swatch in the picker.
  document.querySelectorAll('.theme-swatch').forEach((button) => {
    button.setAttribute('aria-pressed', String(button.dataset.theme === id));
  });
}

// Builds one small preview button for every theme in the list.
function buildThemeGrid() {
  const grid = $('themeGrid');
  grid.innerHTML = '';

  THEMES.forEach((theme) => {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'theme-swatch';
    button.dataset.theme = theme.id;

    // The little picture: a background with a "time" bar and a button bar.
    const preview = document.createElement('div');
    preview.className = 'sw-preview';
    preview.style.background = theme.bg;

    const timeBar = document.createElement('div');
    timeBar.className = 'sw-time';
    timeBar.style.background = theme.text;

    const buttonBar = document.createElement('div');
    buttonBar.className = 'sw-bar';
    buttonBar.style.background = 'linear-gradient(135deg, ' + theme.a + ', ' + theme.b + ')';

    preview.appendChild(timeBar);
    preview.appendChild(buttonBar);

    const label = document.createElement('span');
    label.textContent = theme.name;

    button.appendChild(preview);
    button.appendChild(label);
    button.addEventListener('click', () => applyTheme(theme.id));
    grid.appendChild(button);
  });
}

$('themeBtn').addEventListener('click', () => $('themeDialog').showModal());
$('closeThemeBtn').addEventListener('click', () => $('themeDialog').close());


/* ---------------------------------------------------------
  10. START EVERYTHING UP
   --------------------------------------------------------- */

// This runs several times per second: redraw the clock, update the
// countdown, and see if the alarm is due.
function tick() {
  renderClock();
  updateCountdowns();
  checkAlarm();
}

// A worker reduces main-thread timer delays but browsers can still throttle
// or suspend the whole page. This cannot guarantee background delivery.
// If workers are not available we fall back to a plain setInterval.
function startTicker() {
  let fallbackStarted = false;
  function useFallback() {
    if (fallbackStarted) return;
    fallbackStarted = true;
    setInterval(tick, 250);
  }

  try {
    const workerCode = 'setInterval(function () { postMessage(1); }, 250);';
    const blob = new Blob([workerCode], { type: 'application/javascript' });
    const worker = new Worker(URL.createObjectURL(blob));
    worker.onmessage = tick;
    worker.onerror = () => { worker.terminate(); useFallback(); };
  } catch (err) {
    useFallback();
  }
}

function init() {
  // Show which time zone the clock is in, e.g. "Asia/Manila".
  $('zoneText').textContent = Intl.DateTimeFormat().resolvedOptions().timeZone;

  setupClockView();
  fillRingtoneSelect();
  setupRingtonePicker();
  setupTimePicker();
  setupCountdownPicker();
  setupDurationPresets();
  applyMode(state.mode);
  applyFormatButton();
  applyTestSettings();

  buildThemeGrid();
  applyTheme(state.themeId);

  // Older versions kept ONE alarm under the name 'wake.alarm'.
  // If one is saved, move it into the new list so it is not lost.
  const legacy = loadSaved('wake.alarm', null);
  if (legacy && legacy.targetMs) {
    legacy.id = newId();
    state.alarms.push(legacy);
  }
  save('wake.alarm', null);

  // When the app is opened:
  //   - an alarm that was ringing when the page closed keeps ringing
  //   - an alarm whose time passed more than a minute ago while the app
  //     was closed is forgotten (it would be silly to ring late)
  //   - the others are just waiting for their time
  state.alarms = state.alarms.filter((a) => a.ringing || a.targetMs >= trueNow() - 60000);
  state.alarms.sort((a, b) => a.targetMs - b.targetMs);
  saveAlarms();
  renderAlarmList();
  // (checkAlarm, called by tick below, restarts the ringing alarm.)

  // Get the correct time now, then re-check every 10 minutes
  // and whenever the internet comes back.
  setSyncBadge('checking');
  syncTime();
  setInterval(syncTime, 10 * 60 * 1000);
  window.addEventListener('online', syncTime);
  window.addEventListener('offline', () => setSyncBadge('offline'));

  tick();
  startTicker();
}

init();
