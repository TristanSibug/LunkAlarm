/* Desktop studio. Reuses the original offline sound engine and accessible time wheels. */
(() => {
  "use strict";
  const esc = (s) =>
    String(s ?? "").replace(
      /[&<>"']/g,
      (c) =>
        ({
          "&": "&amp;",
          "<": "&lt;",
          ">": "&gt;",
          '"': "&quot;",
          "'": "&#39;",
        })[c],
    );
  const defaults = () => ({
    typing: false,
    codeLength: 8,
    typingSeconds: 30,
    math: false,
    count: 3,
    mathSeconds: 10,
    ops: ["+"],
    puzzle: false,
    pieces: 8,
    puzzleSeconds: 30,
    mines: false,
    size: 5,
    mineSeconds: 30,
    sudoku: false,
    difficulty: 0,
    sudokuSeconds: 120,
  });
  function cleanTests(value) {
    const d = defaults(),
      v = value && typeof value === "object" ? value : {};
    for (const k of ["typing", "math", "puzzle", "mines", "sudoku"])
      d[k] = v[k] === true;
    for (const [k, choices] of Object.entries({
      codeLength: [4, 5, 6, 7, 8, 9, 10],
      typingSeconds: [15, 20, 25, 30],
      count: [1, 2, 3, 4, 5, 6, 7, 8],
      mathSeconds: [5, 10, 15],
      pieces: [6, 8, 10],
      puzzleSeconds: [15, 20, 25, 30, 35, 40],
      size: [5, 7, 9],
      mineSeconds: [15, 20, 25, 30, 35, 40],
      difficulty: [0, 1, 2, 3],
      sudokuSeconds: [60, 120, 180, 240],
    }))
      if (choices.includes(v[k])) d[k] = v[k];
    d.ops = Array.isArray(v.ops)
      ? [...new Set(v.ops.filter((x) => ["+", "−", "×", "÷"].includes(x)))]
      : ["+"];
    if (!d.ops.length) d.ops = ["+"];
    return d;
  }
  let settings = cleanTests({
      typing: state.typingOn,
      math: state.mathOn,
      count: state.mathCount,
      ...loadSaved("wake.studio.tests", {}),
    }),
    editing = null,
    days = [0, 1, 2, 3, 4, 5, 6];
  let level = Number(loadSaved("wake.studio.volume", 0.8)),
    gradual = loadSaved("wake.studio.gradual", false);
  let mission = null,
    selected = null,
    flagMode = false,
    dragging = null;
  const testNames = {
    typing: "Typing",
    math: "Math",
    puzzle: "Puzzle",
    mines: "Minesweeper",
    sudoku: "Sudoku",
  };
  const glyph = {
    typing: "Aa",
    math: "+=",
    puzzle:
      '<svg viewBox="0 0 24 24" width="28" height="28" fill="none" stroke="currentColor" stroke-width="1.4"><path d="M4 5h6c-3-5 7-5 4 0h6v6c-5-3-5 7 0 4v6h-6c3-5-7-5-4 0H4v-6c5 3 5-7 0-4Z"/></svg>',
    mines: "☼",
    sudoku: "▦",
  };
  function nextTime(hour, minute, repeatDays, now = trueNow()) {
    for (let i = 0; i < 8; i++) {
      const d = new Date(now);
      d.setDate(d.getDate() + i);
      d.setHours(hour, minute, 0, 0);
      if (
        d.getTime() > now &&
        (!repeatDays.length || repeatDays.includes(d.getDay()))
      )
        return d.getTime();
    }
  }
  function normalize(a) {
    const d = new Date(a.targetMs);
    return {
      ...a,
      custom:
        a.custom ||
        (a.ringtoneId === "custom"
          ? structuredClone(state.customRingtone)
          : null),
      type: a.type || "time",
      name: a.name || "",
      enabled: a.enabled !== false,
      hour: a.hour ?? d.getHours(),
      minute: a.minute ?? d.getMinutes(),
      days: a.days || [],
      volume: a.volume ?? 0.8,
      gradual: a.gradual || false,
      tests: cleanTests({
        typing: !!a.typing,
        math: a.mathCount > 0,
        count: a.mathCount || 3,
        ...a.tests,
      }),
    };
  }
  if (loadSaved("wake.studio.beforeMigration", null) === null)
    save("wake.studio.beforeMigration", state.alarms);
  state.alarms = state.alarms
    .filter((a) => a && Number.isFinite(a.targetMs))
    .map(normalize);
  let noticeTimer;
  function notify(text) {
    clearTimeout(noticeTimer);
    $("studioStatus").textContent = text;
    noticeTimer = setTimeout(() => {
      $("studioStatus").textContent = "";
    }, 6500);
  }
  function persist(change) {
    const before = JSON.stringify(state.alarms);
    change();
    if (!saveAlarms()) {
      state.alarms = JSON.parse(before);
      notify("Changes could not be saved. Your previous alarms are intact.");
      return false;
    }
    renderAlarmList();
    return true;
  }
  $("mainApp").insertAdjacentHTML(
    "afterbegin",
    '<header class="studio-brand"><span class="brand-mark">L</span><strong>LunkAlarm</strong><span class="brand-caption">A little more awake.</span><button class="chip" id="focusClock">Clock view</button></header>',
  );
  document.body.insertAdjacentHTML(
    "beforeend",
    `<div id="studioStatus" role="status" aria-live="polite"></div>
    <dialog id="testSettings" class="dialog studio-dialog"><div class="dialog-top"><h2 id="testTitle"></h2><button class="chip" id="tryTest">▷ Try it</button><button class="icon-close" id="closeTest" aria-label="Close test settings">×</button></div><div id="testControls"></div><button class="primary" id="setTest"></button></dialog>
    <dialog id="mission" class="dialog mission-dialog"><div class="dialog-top"><h2 id="missionTitle"></h2><label id="answerSoundLabel"><input type="checkbox" id="answerSound"> Sound</label><button class="icon-close" id="exitPractice" aria-label="Exit practice">×</button></div><div class="mission-meta"><span id="missionTimer"></span><span id="missionProgress"></span></div><div id="missionBody"></div><p id="missionHint" role="status"></p></dialog>
    <dialog id="sounds" class="dialog studio-dialog"><div class="dialog-top"><h2>Ringtone</h2><button class="icon-close" id="closeSounds" aria-label="Close ringtone picker">×</button></div><button class="sound-action" id="ownSound">Use my own file ↗</button><button class="sound-action" id="moreSounds">Find more ringtones online ↗</button><label class="sound-check"><input type="checkbox" id="soundChecker"> Sound checker</label><div id="soundChoices"></div></dialog>`,
  );
  $("setupCard").querySelector(".card-title").outerHTML =
    '<div class="editor-heading"><div><span class="eyebrow">MAKE TIME FOR YOURSELF</span><h2 class="card-title" id="editorTitle">New alarm</h2></div><button id="cancelEdit" class="chip" hidden>Cancel edit</button></div>';
  document.querySelector(".tabs").hidden = true;
  document
    .querySelector(".tabs")
    .insertAdjacentHTML(
      "beforebegin",
      '<div class="create-switch"><button id="newAlarm" class="chip" type="button">◷ Alarm</button><button id="newTimer" class="chip" type="button">◴ Timer</button></div><label class="field-label" for="alarmName">Alarm name <span class="optional">optional</span></label><input id="alarmName" class="text-input" maxlength="120" placeholder="What are you waking up for?"><div id="repeatControls"><div class="repeat-caption"><span class="field-label">Repeat</span><button id="daily" class="link-btn">Daily</button></div><div id="repeatDays" class="weekday-row"></div></div>',
    );
  const legacy = document.createElement("div");
  legacy.hidden = true;
  legacy.inert = true;
  document.body.append(legacy);
  for (const selector of [".wake-settings", ".sound-settings"]) {
    for (const child of [...document.querySelector(selector).childNodes])
      legacy.append(child);
  }
  document.querySelector(".wake-settings").innerHTML =
    '<span class="field-label">Wake-up tests</span><p class="section-note">Optional · try any test before setting it.</p><div id="testTiles" class="test-tiles"></div><div id="selectedTests" class="selected-tests"></div>';
  const meta = document.createElement("div");
  meta.className = "editor-meta";
  const nameBlock = document.createElement("div");
  const nameLabel = $("alarmName").previousElementSibling;
  nameBlock.append(nameLabel, $("alarmName"));
  meta.append(nameBlock, $("repeatControls"));
  document.querySelector(".create-switch").after(meta);
  document.querySelector(".sound-settings").innerHTML =
    '<label class="field-label">Ringtone</label><button id="chooseSound" class="sound-select"></button><div class="volume-caption"><label for="alarmVolume" class="field-label">Alarm volume</label><output id="volumeValue"></output></div><input id="alarmVolume" type="range" min="10" max="100" step="5"><label class="gradual-control"><span>Gradually increase volume</span><input id="gradualVolume" type="checkbox"></label><button id="checkSound" class="link-btn">Check alarm sound</button>';
  // Preserve the imported-file handler while moving its controls into the dialog.
  const file = document.createElement("input");
  file.type = "file";
  file.accept = "audio/*";
  file.hidden = true;
  file.id = "studioFile";
  document.body.append(file);
  file.onchange = async () => {
    const f = file.files[0];
    if (!f) return;
    if (f.size > 2 * 1024 * 1024)
      return notify("Choose a sound smaller than 2 MB.");
    const reader = new FileReader();
    reader.onload = () => {
      const custom = { name: f.name, dataUrl: reader.result };
      if (!save("wake.custom", custom))
        return notify("Not enough browser storage to import this sound.");
      state.customRingtone = custom;
      state.ringtoneId = "custom";
      save("wake.ringtone", "custom");
      drawSounds();
      soundLabel();
    };
    reader.readAsDataURL(f);
  };
  $("ownSound").onclick = () => file.click();
  $("moreSounds").onclick = () => $("onlineDialog").showModal();
  $("chooseSound").onclick = () => {
    drawSounds();
    $("sounds").showModal();
  };
  $("closeSounds").onclick = () => $("sounds").close();
  $("sounds").onclose = () => {
    stopSound();
    $("soundChecker").checked = false;
  };
  function drawSounds() {
    const choices = BUILT_IN_RINGTONES.map((x) => ({ id: x.id, name: x.name }));
    if (state.customRingtone)
      choices.push({ id: "custom", name: state.customRingtone.name });
    $("soundChoices").innerHTML = choices
      .map(
        (t) =>
          `<button class="sound-option" data-tone="${esc(t.id)}" aria-pressed="${state.ringtoneId === t.id}">${esc(t.name)}<span>${state.ringtoneId === t.id ? "✓" : "▷"}</span></button>`,
      )
      .join("");
    $("soundChoices")
      .querySelectorAll("button")
      .forEach(
        (b) =>
          (b.onclick = () => {
            state.ringtoneId = b.dataset.tone;
            save("wake.ringtone", state.ringtoneId);
            soundLabel();
            drawSounds();
            if ($("soundChecker").checked)
              play(state.ringtoneId, level, gradual);
          }),
      );
  }
  function soundLabel() {
    $("chooseSound").textContent =
      (state.ringtoneId === "custom"
        ? state.customRingtone?.name
        : findRingtone(state.ringtoneId).name) + "　⌄";
  }
  function play(tone, volume, fade, custom) {
    const previous = state.customRingtone;
    if (custom) state.customRingtone = custom;
    startSound(tone);
    state.customRingtone = previous;
    if (sound.master) {
      const ctx = getAudioContext();
      sound.master.gain.setValueAtTime(fade ? 0 : volume, ctx.currentTime);
      if (fade)
        sound.master.gain.linearRampToValueAtTime(volume, ctx.currentTime + 10);
    }
    if (sound.audioEl) {
      sound.audioEl.volume = fade ? 0 : volume;
      if (fade) {
        const el = sound.audioEl,
          start = performance.now();
        const ramp = setInterval(() => {
          if (sound.audioEl !== el) return clearInterval(ramp);
          el.volume = Math.min(
            volume,
            ((performance.now() - start) / 10000) * volume,
          );
          if (el.volume >= volume) clearInterval(ramp);
        }, 100);
      }
    }
  }
  $("soundChecker").onchange = () => {
    $("soundChecker").checked
      ? play(state.ringtoneId, level, gradual)
      : stopSound();
  };
  $("checkSound").onclick = () => {
    drawSounds();
    $("sounds").showModal();
    $("soundChecker").checked = true;
    play(state.ringtoneId, level, gradual);
  };
  $("alarmVolume").oninput = () => {
    level = +$("alarmVolume").value / 100;
    $("volumeValue").textContent = Math.round(level * 100) + "%";
    save("wake.studio.volume", level);
    if (sound.master)
      sound.master.gain.setValueAtTime(level, audioCtx.currentTime);
    if (sound.audioEl) sound.audioEl.volume = level;
  };
  $("gradualVolume").onchange = () => {
    gradual = $("gradualVolume").checked;
    save("wake.studio.gradual", gradual);
  };
  function repeatUI() {
    $("repeatDays").innerHTML = ["S", "M", "T", "W", "T", "F", "S"]
      .map(
        (d, i) =>
          `<button class="day-choice" data-day="${i}" aria-label="${["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][i]}" aria-pressed="${days.includes(i)}">${d}</button>`,
      )
      .join("");
    $("repeatDays")
      .querySelectorAll("button")
      .forEach(
        (b) =>
          (b.onclick = () => {
            const i = +b.dataset.day;
            days = days.includes(i)
              ? days.filter((x) => x !== i)
              : [...days, i];
            repeatUI();
          }),
      );
    $("daily").setAttribute("aria-pressed", String(days.length === 7));
  }
  $("daily").onclick = () => {
    days = days.length === 7 ? [] : [0, 1, 2, 3, 4, 5, 6];
    repeatUI();
  };
  function editor(type, id = null) {
    editing = id;
    applyMode(type);
    $("editorTitle").textContent =
      (id ? "Edit " : "New ") + (type === "timer" ? "timer" : "alarm");
    $("alarmName").previousElementSibling.innerHTML =
      (type === "timer" ? "Timer" : "Alarm") +
      ' name <span class="optional">optional</span>';
    $("repeatControls").hidden = type === "timer";
    $("setBtn").textContent = id
      ? "Save changes"
      : type === "timer"
        ? "Add timer"
        : "Add alarm";
    $("cancelEdit").hidden = !id;
    $("newAlarm").setAttribute("aria-pressed", String(type === "time"));
    $("newTimer").setAttribute("aria-pressed", String(type === "timer"));
    $("formMsg").textContent = "";
  }
  $("newAlarm").onclick = () => {
    editing = null;
    $("alarmName").value = "";
    editor("time");
  };
  $("newTimer").onclick = () => {
    editing = null;
    $("alarmName").value = "";
    editor("timer");
  };
  $("cancelEdit").onclick = () => {
    editing = null;
    $("alarmName").value = "";
    editor(state.mode);
  };
  const oldSet = $("setBtn");
  const set = oldSet.cloneNode(true);
  oldSet.replaceWith(set);
  set.onclick = () => {
    commitMobileDuration();
    if (desktopWorkspace.matches) commitTimePicker();
    const time = $("timeInput").value;
    if (state.mode === "time" && !/^\d\d:\d\d$/.test(time))
      return notify("Choose a valid time.");
    const [hour, minute] = time.split(":").map(Number);
    const duration =
      readNumber("hoursInput", 99) * 3600 +
      readNumber("minutesInput", 59) * 60 +
      readNumber("secondsInput", 59);
    if (state.mode === "timer" && !duration)
      return notify("Choose a duration greater than zero.");
    const existing = state.alarms.find((a) => a.id === editing);
    if (existing?.ringing)
      return notify("Finish the ringing alarm before editing it.");
    const record = {
      id: editing || newId(),
      type: state.mode,
      name: $("alarmName").value.trim(),
      hour,
      minute,
      days: [...days],
      duration,
      enabled: true,
      ringing: false,
      targetMs:
        state.mode === "timer"
          ? trueNow() + duration * 1000
          : nextTime(hour, minute, days),
      ringtoneId: state.ringtoneId,
      custom:
        state.ringtoneId === "custom"
          ? structuredClone(state.customRingtone)
          : null,
      typing: settings.typing,
      mathCount: settings.math ? settings.count : 0,
      tests: structuredClone(settings),
      volume: level,
      gradual,
    };
    if (
      persist(() => {
        state.alarms = state.alarms
          .filter((a) => a.id !== record.id)
          .concat(record);
      })
    ) {
      notify(
        (editing
          ? "Changes saved"
          : record.type === "timer"
            ? "Timer started"
            : "Alarm added") + (record.name ? " · " + record.name : ""),
      );
      editing = null;
      $("alarmName").value = "";
      editor(state.mode);
      setAlarmsSidebar(true);
    }
  };
  function editRecord(a) {
    if (a.ringing) return;
    settings = structuredClone(a.tests);
    days = [...a.days];
    level = a.volume;
    gradual = a.gradual;
    state.ringtoneId = a.ringtoneId;
    if (a.custom) state.customRingtone = structuredClone(a.custom);
    $("alarmName").value = a.name;
    $("timeInput").value = pad(a.hour) + ":" + pad(a.minute);
    renderTimePicker();
    const duration = a.duration || 1800;
    $("hoursInput").value = Math.floor(duration / 3600);
    $("minutesInput").value = Math.floor(duration / 60) % 60;
    $("secondsInput").value = duration % 60;
    repeatUI();
    tiles();
    soundLabel();
    volumeUI();
    editor(a.type, a.id);
    setAlarmPickerOpen(true);
  }
  renderAlarmList = () => {
    updateAlarmsSidebar();
    const list = $("alarmList");
    list.innerHTML = "";
    $("emptyText").classList.toggle("hidden", state.alarms.length > 0);
    $("emptyText").textContent =
      "Make room for a better morning. Add your first alarm.";
    for (const type of ["timer", "time"]) {
      const group = state.alarms
        .filter((a) => a.type === type)
        .sort((a, b) => a.targetMs - b.targetMs);
      if (!group.length) continue;
      const heading = document.createElement("li");
      heading.className = "list-section";
      heading.textContent = type === "timer" ? "Timers" : "Alarms";
      list.append(heading);
      for (const a of group) {
        const li = document.createElement("li");
        li.className = "routine-card" + (!a.enabled ? " is-off" : "");
        li.innerHTML = `<div class="routine-top"><button class="routine-edit" aria-label="Edit ${esc(a.name || "alarm")}"><span class="routine-name">${esc(a.name || (type === "timer" ? "Timer" : "Alarm"))}</span><span class="routine-time ${type === "timer" ? "remaining" : ""}" data-target="${a.targetMs}">${type === "timer" ? formatRemaining(a.targetMs - trueNow()) : formatClockTime(new Date(2000, 0, 1, a.hour, a.minute))}</span></button>${type === "time" ? `<button class="routine-toggle" aria-label="Enable ${esc(a.name || "alarm")}" role="switch" aria-checked="${a.enabled}" ${a.ringing ? "disabled" : ""}></button>` : ""}</div><div class="routine-footer"><span>${type === "timer" ? '<span class="remaining" data-target="' + a.targetMs + '">' + formatRemaining(a.targetMs - trueNow()) + "</span> remaining" : a.days.length === 7 ? "Daily" : a.days.length ? ["S", "M", "T", "W", "T", "F", "S"].map((d, i) => `<span class="day-dot ${a.days.includes(i) ? "chosen" : ""}">${d}</span>`).join("") : "Once"}</span><details class="routine-menu"><summary aria-label="Options for ${esc(a.name || "alarm")}">•••</summary><div><button data-action="delete" ${a.ringing ? "disabled" : ""}>Delete</button><button data-action="duplicate">Duplicate</button></div></details></div><div class="routine-tests">${
          Object.keys(testNames)
            .filter((k) => a.tests[k])
            .map((k) => esc(testNames[k]))
            .join(" · ") || "No wake-up tests"
        }</div>`;
        li.querySelector(".routine-edit").onclick = () => editRecord(a);
        li.querySelector(".routine-toggle")?.addEventListener("click", () =>
          persist(() => {
            a.enabled = !a.enabled;
            if (a.enabled) a.targetMs = nextTime(a.hour, a.minute, a.days);
          }),
        );
        li.querySelector('[data-action="delete"]').onclick = () =>
          persist(() => {
            state.alarms = state.alarms.filter((x) => x.id !== a.id);
          });
        li.querySelector('[data-action="duplicate"]').onclick = () =>
          persist(() => {
            const copy = structuredClone(a);
            copy.id = newId();
            copy.ringing = false;
            copy.targetMs =
              type === "timer"
                ? trueNow() + copy.duration * 1000
                : nextTime(copy.hour, copy.minute, copy.days);
            state.alarms.push(copy);
          });
        list.append(li);
      }
    }
  };
  dismissAlarm = () => {
    const a = state.ringing;
    if (!a) return;
    stopSound();
    if (a.type === "timer")
      state.alarms = state.alarms.filter((x) => x.id !== a.id);
    else {
      a.ringing = false;
      if (a.days.length) a.targetMs = nextTime(a.hour, a.minute, a.days);
      else a.enabled = false;
    }
    if (!saveAlarms())
      notify(
        "Alarm stopped, but browser storage could not be updated. It may reappear on reload.",
      );
    state.ringing = null;
    mission = null;
    save("wake.studio.mission", null);
    $("mission").close();
    document.title = "LunkAlarm";
    renderAlarmList();
  };
  checkAlarm = () => {
    if (state.ringing) return;
    const a =
      state.alarms.find((a) => a.ringing) ||
      state.alarms
        .filter((a) => a.enabled && a.targetMs <= trueNow())
        .sort((a, b) => a.targetMs - b.targetMs)[0];
    if (a) startRinging(a);
  };
  startRinging = (a) => {
    a.ringing = true;
    saveAlarms();
    state.ringing = a;
    const stored = loadSaved("wake.studio.mission", null);
    launch(a.tests, false, a, stored?.owner === a.id ? stored : null);
  };
  const defs = {
    typing: [
      ["codeLength", "Code length", [4, 5, 6, 7, 8, 9, 10]],
      ["typingSeconds", "Time limit", [15, 20, 25, 30]],
    ],
    math: [
      ["count", "Problems", [1, 2, 3, 4, 5, 6, 7, 8]],
      ["mathSeconds", "Time per question", [5, 10, 15]],
    ],
    puzzle: [
      ["pieces", "Pieces", [6, 8, 10]],
      ["puzzleSeconds", "Time limit", [15, 20, 25, 30, 35, 40]],
    ],
    mines: [
      ["size", "Difficulty", [5, 7, 9]],
      ["mineSeconds", "Time limit", [15, 20, 25, 30, 35, 40]],
    ],
    sudoku: [
      ["difficulty", "Difficulty", [0, 1, 2, 3]],
      ["sudokuSeconds", "Time limit", [60, 120, 180, 240]],
    ],
  };
  function tiles() {
    $("testTiles").innerHTML = Object.keys(testNames)
      .map(
        (k) =>
          `<button class="test-tile" data-test="${k}" aria-pressed="${!!settings[k]}"><span>${glyph[k]}</span>${testNames[k]}${settings[k] ? "<i>✓</i>" : ""}</button>`,
      )
      .join("");
    $("testTiles")
      .querySelectorAll("button")
      .forEach((b) => (b.onclick = () => openSettings(b.dataset.test)));
    $("selectedTests").textContent =
      Object.keys(testNames)
        .filter((k) => settings[k])
        .map((k) => testNames[k])
        .join(" + ") || "Choose a test, or simply wake up to your sound.";
  }
  function openSettings(k) {
    selected = k;
    $("testTitle").textContent = testNames[k] + " test";
    drawControls();
    $("testSettings").showModal();
  }
  function drawControls() {
    $("testControls").innerHTML =
      defs[selected]
        .map(
          ([key, label, values]) =>
            `<section class="setting-group"><h3>${label}</h3><div class="choice-row">${values.map((v) => `<button class="choice" data-setting="${key}" data-value="${v}" aria-pressed="${settings[key] === v}">${key === "size" ? v + " × " + v : key === "difficulty" ? ["4×4 Easy", "4×4 Hard", "6×6 Easy", "6×6 Hard"][v] : v + (key.endsWith("Seconds") ? "s" : "")}</button>`).join("")}</div></section>`,
        )
        .join("") +
      (selected === "math"
        ? `<section class="setting-group"><h3>Operations</h3><div class="choice-row">${["+", "−", "×", "÷"].map((op) => `<button class="choice" data-op="${op}" aria-pressed="${settings.ops.includes(op)}">${op}</button>`).join("")}</div></section>`
        : "");
    $("testControls")
      .querySelectorAll("[data-setting]")
      .forEach(
        (b) =>
          (b.onclick = () => {
            settings[b.dataset.setting] = +b.dataset.value;
            rememberTests();
            drawControls();
          }),
      );
    $("testControls")
      .querySelectorAll("[data-op]")
      .forEach(
        (b) =>
          (b.onclick = () => {
            const op = b.dataset.op;
            if (settings.ops.includes(op)) {
              if (settings.ops.length > 1)
                settings.ops = settings.ops.filter((x) => x !== op);
            } else settings.ops.push(op);
            rememberTests();
            drawControls();
          }),
      );
    $("setTest").textContent = settings[selected] ? "Unset" : "Set";
  }
  function rememberTests() {
    save("wake.studio.tests", settings);
  }
  $("setTest").onclick = () => {
    settings[selected] = !settings[selected];
    rememberTests();
    tiles();
    $("testSettings").close();
  };
  $("closeTest").onclick = () => $("testSettings").close();
  $("tryTest").onclick = () => {
    const s = { ...structuredClone(settings) };
    for (const k of Object.keys(testNames)) s[k] = k === selected;
    launch(s, true);
  };
  function launch(s, practice, alarm = null, stored = null) {
    stopSound();
    mission = stored || {
      owner: alarm?.id,
      practice,
      s: structuredClone(s),
      steps: Object.keys(testNames).filter((k) => s[k]),
      index: 0,
      done: 0,
    };
    mission.practice = practice;
    mission.alarm = alarm;
    mission.sound = false;
    mission.started = false;
    $("exitPractice").hidden = !practice;
    $("answerSoundLabel").hidden = practice;
    $("answerSound").checked = false;
    if (!stored) beginStep();
    else drawMission();
    if (!$("mission").open) $("mission").showModal();
    $("missionAnswer")?.focus();
    $("missionCode")?.focus();
    if (!practice) {
      document.title = "⏰ LunkAlarm";
      play(alarm.ringtoneId, alarm.volume, alarm.gradual, alarm.custom);
      mission.sound = true;
      $("answerSound").checked = true;
      stash();
    }
  }
  function stash() {
    if (mission && !mission.practice) {
      const data = { ...mission };
      delete data.alarm;
      save("wake.studio.mission", data);
    }
  }
  function beginStep() {
    const m = mission,
      k = m.steps[m.index];
    $("missionHint").textContent = "";
    m.done = 0;
    flagMode = false;
    if (!k) {
      m.deadline = null;
      drawMission();
      return;
    }
    m.deadline =
      trueNow() +
      m.s[
        k === "typing"
          ? "typingSeconds"
          : k === "math"
            ? "mathSeconds"
            : k === "puzzle"
              ? "puzzleSeconds"
              : k === "mines"
                ? "mineSeconds"
                : "sudokuSeconds"
      ] *
        1000;
    if (k === "typing") m.code = makeCode(m.s.codeLength);
    if (k === "math") problem();
    if (k === "puzzle") {
      m.placed = [];
      m.shapes = makeJigsaw(m.s.pieces);
      m.order = shuffle(Array.from({ length: m.s.pieces }, (_, i) => i));
    }
    if (k === "mines") m.board = makeMine(m.s.size);
    if (k === "sudoku") m.board = makeSudoku(m.s.difficulty);
    stash();
    drawMission();
  }
  function advance() {
    mission.index++;
    beginStep();
  }
  function problem() {
    const m = mission;
    let a = randomInt(1, 20),
      b = randomInt(1, 20),
      op = m.s.ops[randomInt(0, m.s.ops.length - 1)];
    if (op === "−") [a, b] = [Math.max(a, b), Math.min(a, b)];
    if (op === "×" || op === "÷") {
      a = randomInt(1, 12);
      b = randomInt(1, 12);
      if (op === "÷") a *= b;
    }
    m.a = a;
    m.b = b;
    m.op = op;
    m.answer =
      op === "+" ? a + b : op === "−" ? a - b : op === "×" ? a * b : a / b;
  }
  function shuffle(a) {
    for (let i = a.length - 1; i > 0; i--) {
      const j = randomInt(0, i);
      [a[i], a[j]] = [a[j], a[i]];
    }
    return a;
  }
  function drawMission() {
    const m = mission;
    if (!m) return;
    const k = m.steps[m.index];
    $("missionTitle").textContent = m.practice
      ? (testNames[k] || testNames[m.steps[0]]) + " practice"
      : m.alarm?.name || "Time to wake up";
    $("missionProgress").textContent = k
      ? `${m.index + 1} / ${m.steps.length} tests`
      : "";
    const body = $("missionBody");
    if (!k) {
      body.innerHTML = `<div class="mission-complete">${m.steps.length ? "Well done!" : "Good morning."}</div><button class="primary" id="finishMission">${m.practice ? "Try again" : "Stop alarm"}</button>`;
      $("finishMission").onclick = () => {
        if (m.practice) {
          m.index = 0;
          beginStep();
        } else dismissAlarm();
      };
      return;
    }
    if (k === "typing") {
      body.innerHTML = `<h3>Type this code</h3><div class="code">${esc(m.code)}</div><input class="text-input" id="missionCode" maxlength="${m.s.codeLength}" autocomplete="off" spellcheck="false" placeholder="Type the code" aria-label="Type the code"><button class="primary" id="checkCode">Check code</button>`;
      const input = $("missionCode");
      input.onpaste = (e) => e.preventDefault();
      input.ondrop = (e) => e.preventDefault();
      $("checkCode").onclick = () => {
        if (input.value === m.code) advance();
        else
          $("missionHint").textContent =
            "Match the code exactly, including capital letters.";
      };
      input.onkeydown = (e) => {
        if (e.key === "Enter") $("checkCode").click();
      };
      input.focus();
    }
    if (k === "math") {
      body.innerHTML = `<h3>${m.done} / ${m.s.count} answered</h3><div class="problem">${m.a} ${m.op} ${m.b}</div><input class="text-input math-entry" id="missionAnswer" inputmode="numeric" autocomplete="off" placeholder="Your answer" aria-label="Math answer"><p class="section-note">Use your keyboard · answers check automatically</p>`;
      const input = $("missionAnswer");
      input.oninput = () => {
        input.value = input.value.replace(/\D/g, "").slice(0, 3);
        if (input.value.length < String(m.answer).length) return;
        if (input.value === String(m.answer)) {
          m.done++;
          $("missionHint").textContent = "";
          if (m.done === m.s.count) return advance();
          problem();
          m.deadline = trueNow() + m.s.mathSeconds * 1000;
          stash();
          drawMission();
        } else {
          input.value = "";
          $("missionHint").textContent = "Try that one again.";
        }
      };
      input.focus();
    }
    if (k === "puzzle") drawPuzzle();
    if (k === "mines") drawMine();
    if (k === "sudoku") drawSudoku();
  }
  function drawPuzzle() {
    const m = mission,
      n = m.s.pieces,
      cols = n / 2;
    $("missionBody").innerHTML =
      `<h3>${m.placed.length}/${n} placed</h3><p class="section-note">Fit the solid jigsaw pieces together. Drag a piece, or select it and click its place.</p><div class="puzzle-board" style="--cols:${cols}">${Array.from({ length: n }, (_, i) => `<button class="puzzle-slot ${m.placed.includes(i) ? "placed" : ""}" data-slot="${i}" aria-label="Puzzle position ${i + 1}">${m.placed.includes(i) ? pieceShape(i) : ""}</button>`).join("")}</div><div class="puzzle-tray" style="--cols:${cols}">${m.order
        .filter((i) => !m.placed.includes(i))
        .map(
          (i) =>
            `<button draggable="true" class="puzzle-piece" data-piece="${i}" aria-label="Puzzle piece ${i + 1}">${pieceShape(i, true)}</button>`,
        )
        .join("")}</div>`;
    let choice = null;
    document.querySelectorAll("[data-piece]").forEach((b) => {
      b.onclick = () => {
        choice = +b.dataset.piece;
        document
          .querySelectorAll("[data-piece]")
          .forEach((x) => x.classList.toggle("picked", x === b));
      };
      b.ondragstart = (e) => {
        dragging = +b.dataset.piece;
        e.dataTransfer.setData("text/plain", String(dragging));
      };
    });
    document.querySelectorAll("[data-slot]").forEach((b) => {
      const put = (i) => {
        if (i !== +b.dataset.slot || m.placed.includes(i)) return;
        m.placed.push(i);
        stash();
        if (m.placed.length === n) advance();
        else drawPuzzle();
      };
      b.onclick = () => put(choice);
      b.ondragover = (e) => e.preventDefault();
      b.ondrop = (e) => {
        e.preventDefault();
        const value = e.dataTransfer.getData("text/plain");
        if (/^\d+$/.test(value)) put(Number(value));
      };
    });
  }
  // Matching seam curves are shared by adjacent pieces. Save them with the
  // challenge so a reload restores the exact same solid jigsaw.
  function makeJigsaw(n) {
    const cols = n / 2,
      seams = new Map();
    return Array.from({ length: n }, (_, i) => {
      const x = i % cols,
        y = Math.floor(i / cols),
        corners = [
          [x, y],
          [x + 1, y],
          [x + 1, y + 1],
          [x, y + 1],
        ];
      const adjacent = [y > 0, x < cols - 1, y < 1, x > 0];
      let path = "M0 0";
      for (let side = 0; side < 4; side++) {
        const a = corners[side],
          b = corners[(side + 1) % 4],
          forward = a[0] < b[0] || a[1] < b[1];
        const key = (forward ? [a, b] : [b, a])
          .map((p) => p.join(","))
          .join("-");
        if (!seams.has(key))
          seams.set(key, [
            (Math.random() < 0.5 ? -1 : 1) * (16 + Math.random() * 7),
            0.43 + Math.random() * 0.14,
          ]);
        const seam = seams.get(key),
          tab = adjacent[side] ? seam[0] * (forward ? 1 : -1) : 0,
          c = forward ? seam[1] : 1 - seam[1];
        const dx = (b[0] - a[0]) * 100,
          dy = (b[1] - a[1]) * 100;
        const point = (t, bump = 0) =>
          [
            (a[0] - x) * 100 + dx * t + (dy / 100) * tab * bump,
            (a[1] - y) * 100 + dy * t - (dx / 100) * tab * bump,
          ].join(" ");
        if (tab)
          path += ` L${point(c - 0.12)} C${point(c - 0.04)} ${point(c - 0.19, 1)} ${point(c, 1)} C${point(c + 0.19, 1)} ${point(c + 0.04)} ${point(c + 0.12)}`;
        path += ` L${point(1)}`;
      }
      return path + " Z";
    });
  }
  function pieceShape(i, tray = false) {
    mission.shapes ||= makeJigsaw(mission.s.pieces);
    return `<svg viewBox="${tray ? "-25 -25 150 150" : "0 0 100 100"}" preserveAspectRatio="none" class="jigsaw-shape" aria-hidden="true"><path d="${mission.shapes[i]}"/></svg>`;
  }
  function neighbors(i, size) {
    return Array.from({ length: size * size }, (_, j) => j).filter(
      (j) =>
        j !== i &&
        Math.abs((j % size) - (i % size)) <= 1 &&
        Math.abs(Math.floor(j / size) - Math.floor(i / size)) <= 1,
    );
  }
  function mineNumber(b, i) {
    return neighbors(i, b.size).filter((j) => b.mines.includes(j)).length;
  }
  function reveal(b, i) {
    const stack = [i];
    while (stack.length) {
      const j = stack.pop();
      if (b.open.includes(j) || b.flags.includes(j) || b.mines.includes(j))
        continue;
      b.open.push(j);
      if (!mineNumber(b, j)) stack.push(...neighbors(j, b.size));
    }
  }
  function deducible(board) {
    const b = structuredClone(board);
    for (let loops = 0; loops < b.size * b.size; loops++) {
      let changed = false;
      for (const i of b.open) {
        const near = neighbors(i, b.size),
          hidden = near.filter(
            (j) => !b.open.includes(j) && !b.flags.includes(j),
          ),
          left =
            mineNumber(b, i) - near.filter((j) => b.flags.includes(j)).length;
        if (!hidden.length) continue;
        if (!left) {
          hidden.forEach((j) => reveal(b, j));
          changed = true;
        } else if (left === hidden.length) {
          b.flags.push(...hidden);
          changed = true;
        }
      }
      const hidden = Array.from(
        { length: b.size * b.size },
        (_, i) => i,
      ).filter((i) => !b.open.includes(i) && !b.flags.includes(i));
      if (b.mines.length === b.flags.length) {
        hidden.forEach((i) => reveal(b, i));
      }
      if (b.open.length + b.mines.length === b.size * b.size) return true;
      if (!changed) return false;
    }
    return false;
  }
  function makeMine(size) {
    const count = { 5: 4, 7: 8, 9: 14 }[size];
    for (let tries = 0; tries < 250; tries++) {
      const b = {
        size,
        mines: shuffle(Array.from({ length: size * size }, (_, i) => i)).slice(
          0,
          count,
        ),
        flags: [],
        open: [],
      };
      const start = Array.from({ length: size * size }, (_, i) => i).find(
        (i) => !b.mines.includes(i) && !mineNumber(b, i),
      );
      if (start !== undefined) {
        reveal(b, start);
        if (deducible(b)) return b;
      }
    }
    const b = {
      size,
      mines: Array.from({ length: count }, (_, i) => i),
      flags: [],
      open: [],
    };
    reveal(b, size * size - 1);
    return b;
  }
  function resetTests() {
    const m = mission;
    m.index = 0;
    beginStep();
    if (!m.practice) {
      m.sound = true;
      $("answerSound").checked = true;
      play(m.alarm.ringtoneId, m.alarm.volume, m.alarm.gradual, m.alarm.custom);
    }
    $("missionHint").textContent =
      "Time or a mistake reset your tests. Start again.";
    stash();
  }
  function drawMine() {
    const b = mission.board;
    $("missionBody").innerHTML =
      `<h3>Minesweeper</h3><p class="section-note">Reveal safe squares and flag all mines.<br>Click to reveal · right-click to flag · or use Flag mode.</p><div class="game-toolbar"><span>${b.flags.length}/${b.mines.length} flags</span><button class="chip" id="flagMode" aria-pressed="${flagMode}">${flagMode ? "⚑ Flag" : "Reveal"}</button></div><div class="game-grid" style="--size:${b.size}">${Array.from({ length: b.size * b.size }, (_, i) => `<button class="mine-cell ${b.open.includes(i) ? "revealed" : ""}" data-cell="${i}" aria-label="Row ${Math.floor(i / b.size) + 1}, column ${(i % b.size) + 1}: ${b.flags.includes(i) ? "flag" : b.open.includes(i) ? mineNumber(b, i) + " adjacent mines" : "hidden"}">${b.flags.includes(i) ? "⚑" : b.open.includes(i) ? mineNumber(b, i) || "" : ""}</button>`).join("")}</div><button class="primary" id="mineDone" ${b.flags.length !== b.mines.length ? "disabled" : ""}>I'm done</button>`;
    $("flagMode").onclick = () => {
      flagMode = !flagMode;
      drawMine();
    };
    document.querySelectorAll("[data-cell]").forEach((el) => {
      const move = (flag) => {
        const i = +el.dataset.cell;
        if (b.open.includes(i)) return;
        if (flag) {
          b.flags = b.flags.includes(i)
            ? b.flags.filter((j) => j !== i)
            : b.flags.concat(i);
        } else if (!b.flags.includes(i)) {
          if (b.mines.includes(i)) return resetTests();
          reveal(b, i);
        }
        stash();
        drawMine();
      };
      el.onclick = () => move(flagMode);
      el.oncontextmenu = (e) => {
        e.preventDefault();
        move(true);
      };
    });
    $("mineDone").onclick = () => {
      if (b.flags.length !== b.mines.length) return;
      if (b.flags.every((i) => b.mines.includes(i))) advance();
      else resetTests();
    };
  }
  function sudokuPeers(size, i) {
    return Array.from({ length: size * size }, (_, j) => j).filter(
      (j) =>
        j !== i &&
        (Math.floor(j / size) === Math.floor(i / size) ||
          j % size === i % size ||
          (Math.floor(j / size / 2) === Math.floor(i / size / 2) &&
            Math.floor((j % size) / (size / 2)) ===
              Math.floor((i % size) / (size / 2)))),
    );
  }
  function solutions(size, grid) {
    const a = [...grid];
    let found = 0;
    function solve() {
      if (found > 1) return;
      let best = -1,
        options = [];
      for (let i = 0; i < a.length; i++)
        if (!a[i]) {
          const o = Array.from({ length: size }, (_, j) => j + 1).filter(
            (v) => !sudokuPeers(size, i).some((j) => a[j] === v),
          );
          if (best < 0 || o.length < options.length) {
            best = i;
            options = o;
          }
        }
      if (best < 0) {
        found++;
        return;
      }
      for (const v of options) {
        a[best] = v;
        solve();
        a[best] = 0;
        if (found > 1) break;
      }
    }
    solve();
    return found;
  }
  function makeSudoku(difficulty) {
    const size = difficulty < 2 ? 4 : 6,
      digits = shuffle(Array.from({ length: size }, (_, i) => i + 1));
    const solution = Array.from(
      { length: size * size },
      (_, i) =>
        digits[
          (Math.floor(i / size) * (size / 2) +
            Math.floor(Math.floor(i / size) / 2) +
            (i % size)) %
            size
        ],
    );
    const givens = [...solution];
    let removed = 0;
    for (const i of shuffle(Array.from({ length: size * size }, (_, i) => i))) {
      const value = givens[i];
      givens[i] = 0;
      if (solutions(size, givens) !== 1) givens[i] = value;
      else removed++;
      if (removed >= [6, 10, 14, 22][difficulty]) break;
    }
    return {
      size,
      solution,
      givens,
      values: [...givens],
      selected: givens.indexOf(0),
    };
  }
  function drawSudoku() {
    const b = mission.board;
    $("missionBody").innerHTML =
      `<h3>Sudoku</h3><p class="section-note">Use 1–${b.size} once in each row, column and box. Select a cell, then type a number or use the buttons.</p><div class="sudoku-board game-grid" style="--size:${b.size}">${b.values.map((v, i) => `<button data-sudoku="${i}" class="sudoku-cell ${b.selected === i ? "selected" : ""} ${v && sudokuPeers(b.size, i).some((j) => b.values[j] === v) ? "conflict" : ""}" style="border-top-width:${Math.floor(i / b.size) % 2 === 0 ? 2 : 1}px;border-left-width:${(i % b.size) % (b.size / 2) === 0 ? 2 : 1}px" ${b.givens[i] ? "disabled" : ""} aria-label="Row ${Math.floor(i / b.size) + 1}, column ${(i % b.size) + 1}${b.givens[i] ? ", fixed" : ""}">${v || ""}</button>`).join("")}</div><div class="choice-row">${Array.from({ length: b.size }, (_, i) => `<button class="choice" data-digit="${i + 1}">${i + 1}</button>`).join("")}<button class="choice" data-digit="0">Erase</button></div>`;
    document.querySelectorAll("[data-sudoku]").forEach(
      (el) =>
        (el.onclick = () => {
          b.selected = +el.dataset.sudoku;
          drawSudoku();
        }),
    );
    document.querySelectorAll("[data-digit]").forEach(
      (el) =>
        (el.onclick = () => {
          b.values[b.selected] = +el.dataset.digit;
          stash();
          if (b.values.every((v, i) => v === b.solution[i])) advance();
          else drawSudoku();
        }),
    );
  }
  $("missionBody").addEventListener("keydown", () => {
    if (mission && !mission.practice && !mission.started) {
      mission.started = true;
      mission.sound = false;
      $("answerSound").checked = false;
      stopSound();
      stash();
    }
  });
  $("missionBody").addEventListener("pointerdown", () => {
    if (mission && !mission.practice && !mission.started) {
      mission.started = true;
      mission.sound = false;
      $("answerSound").checked = false;
      stopSound();
      stash();
    }
  });
  $("mission").addEventListener("cancel", (e) => {
    if (!mission?.practice) e.preventDefault();
  });
  $("exitPractice").onclick = () => {
    $("mission").close();
    mission = null;
    stopSound();
  };
  $("mission").addEventListener("close", () => {
    if (mission?.practice) {
      mission = null;
      stopSound();
    }
  });
  $("answerSound").onchange = () => {
    if (!mission || mission.practice) return;
    mission.sound = $("answerSound").checked;
    if (mission.sound)
      play(
        mission.alarm.ringtoneId,
        mission.alarm.volume,
        mission.alarm.gradual,
        mission.alarm.custom,
      );
    else stopSound();
    stash();
  };
  setInterval(() => {
    if (!mission) return;
    const left = mission.deadline
      ? Math.ceil((mission.deadline - trueNow()) / 1000)
      : 0;
    $("missionTimer").textContent = mission.deadline
      ? Math.max(0, left) + "s remaining"
      : "";
    if (mission.deadline && left <= 0) resetTests();
  }, 200);
  // Desktop keyboard shortcuts complement the time-wheel and direct-entry controls.
  document.addEventListener("keydown", (e) => {
    if (e.defaultPrevented) return;
    if (
      e.target.matches("input,textarea,select") ||
      e.ctrlKey ||
      e.metaKey ||
      e.altKey
    )
      return;
    if (
      mission?.steps[mission.index] === "sudoku" &&
      e.key.startsWith("Arrow")
    ) {
      const b = mission.board,
        step = {
          ArrowLeft: -1,
          ArrowRight: 1,
          ArrowUp: -b.size,
          ArrowDown: b.size,
        }[e.key];
      if (step) {
        e.preventDefault();
        let next = b.selected;
        for (let i = 0; i < b.values.length; i++) {
          next = (next + step + b.values.length) % b.values.length;
          if (!b.givens[next]) {
            b.selected = next;
            drawSudoku();
            break;
          }
        }
      }
      return;
    }
    if (mission?.steps[mission.index] === "sudoku" && /^[0-6]$/.test(e.key)) {
      $("missionBody").querySelector(`[data-digit="${e.key}"]`)?.click();
      return;
    }
    if (document.querySelector("dialog[open]")) return;
    if (e.key.toLowerCase() === "a") {
      $("newAlarm").click();
      setAlarmPickerOpen(true);
    }
    if (e.key.toLowerCase() === "t") {
      $("newTimer").click();
      setAlarmPickerOpen(true);
    }
    if (e.key === "Escape" && !$("mission").open) setAlarmPickerOpen(false);
  });
  const clockActions = updateClockActions;
  updateClockActions = () => {
    clockActions();
    $("focusClock").textContent = alarmPickerOpen
      ? "Focus clock"
      : "Open workspace";
    $("alarmPickerText").textContent = alarmPickerOpen
      ? "Focus clock"
      : "Open workspace";
  };
  $("focusClock").onclick = () => setAlarmPickerOpen(!alarmPickerOpen);
  function volumeUI() {
    $("alarmVolume").value = Math.round(level * 100);
    $("volumeValue").textContent = Math.round(level * 100) + "%";
    $("gradualVolume").checked = gradual;
  }
  $("alarmsHeading").textContent = "Alarms & timers";
  document.querySelector(".sidebar-label").textContent = "Alarms & timers";
  $("clockAlarmsToggle").textContent = "Alarms & timers";
  $("alarmsToggle").setAttribute("aria-label", "Expand alarms and timers");
  updateClockActions();
  // Theme families mirror the mobile palette; every choice closes the picker.
  const additions = [
    [
      "eggshell-white",
      "Eggshell White",
      "#f7f3e8",
      "#fffefa",
      "#28343c",
      "#636b70",
      "#566a78",
      "#6d6252",
    ],
    [
      "linen",
      "Linen",
      "#f5efe5",
      "#fffcf6",
      "#302921",
      "#766858",
      "#986020",
      "#b34938",
    ],
    [
      "sea-glass",
      "Sea Glass",
      "#eaf3ef",
      "#f9fffc",
      "#173c37",
      "#526d67",
      "#237268",
      "#346d8e",
    ],
    [
      "heritage",
      "Heritage",
      "#f9efd4",
      "#fffdf5",
      "#032d3f",
      "#52626b",
      "#7d0500",
      "#032d3f",
    ],
    [
      "ember",
      "Ember",
      "#1b1110",
      "#2b1d1a",
      "#ffeee3",
      "#c3a49a",
      "#ffbb74",
      "#ef876d",
    ],
    [
      "midnight-cherry",
      "Midnight Cherry",
      "#260f19",
      "#fff3f6",
      "#fff2f6",
      "#caa6b5",
      "#9ecbf5",
      "#ff8d87",
    ],
    [
      "forest",
      "Forest",
      "#0b1714",
      "#142720",
      "#e4f2e9",
      "#9bb5a4",
      "#9dcc88",
      "#59c7a5",
    ],
    [
      "deep-ocean",
      "Deep Ocean",
      "#081a24",
      "#102b38",
      "#e1f5fb",
      "#99b9c6",
      "#79d2de",
      "#82b0f7",
    ],
    [
      "cobalt-coral",
      "Cobalt & Coral",
      "#101c3d",
      "#1d3057",
      "#f2f6ff",
      "#a8b8d6",
      "#92bdff",
      "#ff8a85",
    ],
    [
      "signal-blue",
      "Signal Blue",
      "#032d3f",
      "#be0d1f",
      "#f1f7fa",
      "#e8d7e1",
      "#d2e7f2",
      "#699db8",
    ],
    [
      "amethyst",
      "Amethyst",
      "#171123",
      "#251d36",
      "#f1eaff",
      "#b3a3cb",
      "#c5a2ff",
      "#f0a4ce",
    ],
  ];
  const preferredTheme = loadSaved("wake.studio.theme", state.themeId);
  for (const [id, name, bg, card, text, muted, a, b] of additions) {
    THEMES.push({ id, name, bg, text, a, b });
    const style = document.createElement("style");
    style.textContent = `:root[data-theme="${id}"]{color-scheme:${["eggshell-white", "linen", "sea-glass", "heritage"].includes(id) ? "light" : "dark"};--bg:${bg};--card:${id === "midnight-cherry" ? "#3d1c2a" : card};--text:${text};--muted:${muted};--accent:${a};--accent-2:${b};--dialog-bg:${id === "midnight-cherry" ? "#3d1c2a" : card};--field:${["eggshell-white", "linen", "sea-glass", "heritage"].includes(id) ? "#00000008" : "#00000035"};--glow-a:${a}20;--glow-b:${b}14;--on-accent:${["eggshell-white", "linen", "sea-glass", "heritage"].includes(id) ? "#ffffff" : "#160f12"};--code-bg:${card};--overlay-bg:${bg}f5;--card-border:${text}20;}`;
    document.head.append(style);
  }
  THEMES.splice(
    THEMES.findIndex((t) => t.id === "vscode-blue"),
    1,
  );
  const order = [
    "light",
    "eggshell-white",
    "linen",
    "sea-glass",
    "heritage",
    "oled",
    "dark",
    "sunrise",
    "ember",
    "midnight-cherry",
    "forest",
    "nord",
    "deep-ocean",
    "cobalt-coral",
    "signal-blue",
    "tokyo-night",
    "amethyst",
    "dracula",
  ];
  THEMES.sort((a, b) => order.indexOf(a.id) - order.indexOf(b.id));
  buildThemeGrid();
  $("themeGrid")
    .querySelectorAll("button")
    .forEach((b) =>
      b.addEventListener("click", () => {
        save("wake.studio.theme", b.dataset.theme);
        $("themeDialog").close();
      }),
    );
  applyTheme(preferredTheme === "vscode-blue" ? "deep-ocean" : preferredTheme);
  document.querySelector(
    "#themeGrid [data-theme=signal-blue] .sw-bar",
  ).style.background = "linear-gradient(135deg,#be0d1f 50%,#699db8 50%)";
  repeatUI();
  tiles();
  soundLabel();
  volumeUI();
  editor(state.mode);
  renderAlarmList();
  saveAlarms();
  // Persisted recurring routines advance after missed occurrences; expired timers are not retained indefinitely.
  persist(() => {
    for (const a of state.alarms) {
      if (!a.ringing && a.enabled && a.targetMs < trueNow() - 60000) {
        if (a.type === "time" && a.days.length)
          a.targetMs = nextTime(a.hour, a.minute, a.days);
        else if (a.type === "time") a.enabled = false;
      }
    }
    state.alarms = state.alarms.filter(
      (a) => a.type !== "timer" || a.ringing || a.targetMs >= trueNow() - 60000,
    );
  });
  // Keep test generation inspectable by the browser regression runner without changing production scheduling.
  window.LunkStudio = { nextTime, makeMine, makeSudoku, solutions };
  tick();
  startTicker();
})();
