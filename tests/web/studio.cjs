const { chromium } = require("playwright");
const assert = require("node:assert/strict");
const { mkdir, readFile } = require("node:fs/promises");
const { existsSync } = require("node:fs");
const { createServer } = require("node:http");
const path = require("node:path");
const root = path.resolve(__dirname, "../../web");
const output = path.resolve(__dirname, "../../artifacts/web-previews");
const mime = {
  ".html": "text/html",
  ".css": "text/css",
  ".js": "text/javascript",
  ".png": "image/png",
  ".woff2": "font/woff2",
  ".ttf": "font/ttf",
};
const server = createServer(async (req, res) => {
  try {
    let file = new URL(req.url, "http://local").pathname;
    if (file === "/") file = "/index.html";
    if (
      !/^\/(?:[\w-]+\/)*[\w.-]+$/.test(file) ||
      file.split("/").includes("..")
    )
      throw Error("Bad path");
    const data = await readFile(path.join(root, file));
    res.writeHead(200, {
      "Content-Type": mime[path.extname(file)] || "application/octet-stream",
    });
    res.end(data);
  } catch {
    res.writeHead(404);
    res.end("Not found");
  }
});
(async () => {
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  server.unref();
  const url = `http://127.0.0.1:${server.address().port}`;
  const browser = await chromium.launch({
    executablePath:
      process.env.CHROMIUM_PATH ||
      (existsSync("/usr/bin/chromium") ? "/usr/bin/chromium" : undefined),
    headless: true,
    args: ["--no-sandbox"],
  });
  const errors = [];
  let checks = 0;
  async function fresh(
    seed = {},
    viewport = { width: 1600, height: 1000 },
    touch = false,
  ) {
    const c = await browser.newContext({
      viewport,
      isMobile: touch,
      hasTouch: touch,
    });
    const p = await c.newPage();
    p.on("pageerror", (e) => errors.push(e.message));
    await p.route("**/*", (r) =>
      r.request().url().startsWith(url) ? r.continue() : r.abort(),
    );
    await p.addInitScript((data) => {
      if (!sessionStorage.seeded) {
        for (const [k, v] of Object.entries(data))
          localStorage.setItem(k, JSON.stringify(v));
        sessionStorage.seeded = "1";
      }
    }, seed);
    await p.goto(url);
    await p.waitForSelector("#newAlarm", { state: "attached" });
    return p;
  }
  async function storage(p) {
    return p.evaluate(() => JSON.parse(localStorage.getItem("wake.alarms")));
  }
  async function workspace(p) {
    if (
      await p
        .locator("html")
        .evaluate((e) => e.classList.contains("clock-focus"))
    )
      await p.locator("#alarmPickerToggle").click();
    await p.waitForTimeout(400);
  }
  async function close(p) {
    await p.context().close();
  }
  try {
    await mkdir(output, { recursive: true });
    let p = await fresh();
    await workspace(p);
    await p.locator("#alarmName").fill("Morning");
    await p.locator("#daily").click();
    await p.getByRole("button", { name: "Wednesday", exact: true }).click();
    await p.locator("[data-test=math]").click();
    assert.equal(await p.locator("#setTest").textContent(), "Set");
    await p.locator('[data-op="×"]').click();
    await p.locator("#closeTest").click();
    assert.equal((await storage(p)).length, 0);
    assert.equal(
      await p.locator("[data-test=math]").getAttribute("aria-pressed"),
      "false",
    );
    await p.locator("[data-test=math]").click();
    await p.locator("#setTest").click();
    await p.locator("#setBtn").click();
    let a = (await storage(p))[0];
    assert.equal(a.name, "Morning");
    assert.deepEqual(a.days, [3]);
    assert(a.tests.math);
    checks++;
    await p.getByRole("button", { name: "Edit Morning", exact: true }).click();
    await p.locator("#alarmName").fill("Morning edited");
    await p.locator("#setBtn").click();
    assert.equal((await storage(p))[0].id, a.id);
    await p.locator(".routine-menu-trigger").first().click();
    await p.locator("[data-action=duplicate]").click();
    assert.equal((await storage(p)).length, 2);
    checks++;
    await p.locator("#newTimer").click();
    await p.locator("#alarmName").fill("Tea");
    await p.locator("#setBtn").click();
    assert.equal(
      (await storage(p)).filter((a) => a.type === "timer").length,
      1,
    );
    assert.equal(
      await p.locator(".list-section").first().textContent(),
      "Timers",
    );
    await p.screenshot({ path: path.join(output, "studio-desktop.png") });
    checks++;
    await p.locator("#themeBtn").click();
    await p
      .getByRole("button", { name: "Eggshell White", exact: true })
      .click();
    assert.equal(
      await p.locator("#themeDialog").evaluate((d) => d.open),
      false,
    );
    await p.reload();
    assert.equal(
      await p.locator("html").getAttribute("data-theme"),
      "eggshell-white",
    );
    assert.equal((await storage(p)).length, 3);
    await workspace(p);
    await p.screenshot({ path: path.join(output, "studio-light.png") });
    checks++;
    await p.locator("#chooseSound").click();
    await p.locator("[data-tone=digital-watch]").click();
    assert.equal(await p.locator("#sounds").evaluate((d) => d.open), true);
    await p.locator("#soundChecker").check();
    await p.waitForFunction(() => audioCtx?.state === "running");
    assert(await p.evaluate(() => !!sound.master));
    await p.locator("#closeSounds").click();
    await p.waitForFunction(() => !sound.master && !sound.audioEl);
    checks++;
    for (const size of [
      { width: 1366, height: 768 },
      { width: 1024, height: 768 },
      { width: 390, height: 844 },
      { width: 320, height: 740 },
    ]) {
      await p.setViewportSize(size);
      await p.waitForTimeout(150);
      assert(
        await p.evaluate(
          () => document.documentElement.scrollWidth <= innerWidth + 1,
        ),
        "Horizontal overflow " + JSON.stringify(size),
      );
      if (size.width >= 1000) {
        await p.locator("[data-test=mines]").scrollIntoViewIfNeeded();
        assert(
          await p.locator("[data-test=mines]").evaluate((el) => {
            const text = [...el.childNodes].find(
              (n) => n.nodeType === Node.TEXT_NODE,
            );
            const range = new Range();
            range.selectNode(text);
            return (
              range.getBoundingClientRect().width <=
              el.getBoundingClientRect().width - 8
            );
          }),
          "Test labels must fit the desktop panel",
        );
        assert(
          await p.locator("#setBtn").evaluate((el) => {
            const r = el.getBoundingClientRect();
            return r.top >= 0 && r.bottom <= innerHeight;
          }),
          "Save button stays within desktop viewport",
        );
        assert(
          await p.evaluate(
            () => document.documentElement.scrollHeight <= innerHeight + 1,
          ),
        );
      }
    }
    await p.screenshot({
      path: path.join(output, "studio-phone.png"),
      fullPage: true,
    });
    checks++;
    await close(p);
    // Legacy one-shot records stay saved and their test choices migrate.
    p = await fresh({
      "wake.alarms": [
        {
          id: "legacy",
          targetMs: Date.now() - 100000,
          ringing: false,
          typing: true,
          mathCount: 2,
          ringtoneId: "classic-beep",
        },
      ],
    });
    a = (await storage(p))[0];
    assert.equal(a.id, "legacy");
    assert.equal(a.enabled, false);
    assert(a.tests.typing && a.tests.math);
    assert.equal(a.tests.stroop, false);
    checks++;
    await close(p);
    const record = (tests) => ({
      id: "ring",
      targetMs: Date.now() - 1000,
      type: "timer",
      duration: 1,
      ringtoneId: "classic-beep",
      tests,
      enabled: true,
    });
    p = await fresh({
      "wake.alarms": [
        record({ math: true, count: 2, mathSeconds: 15, ops: ["×"] }),
      ],
    });
    await p.waitForSelector("#missionAnswer");
    const answer = async () => {
      const s = await p.locator("#missionBody .problem").textContent();
      const [a, op, b] = s.trim().split(/\s+/);
      return String(
        op === "+" ? +a + +b : op === "−" ? a - b : op === "×" ? a * b : a / b,
      );
    };
    await p.locator("#missionAnswer").fill("0".repeat((await answer()).length));
    assert.equal(await p.locator("#missionAnswer").inputValue(), "");
    for (let i = 0; i < 2; i++) {
      await p.locator("#missionAnswer").fill(await answer());
      if (i === 0) {
        assert.equal(await p.locator("#missionAnswer").inputValue(), "");
        assert(
          await p
            .locator("#missionAnswer")
            .evaluate((e) => e === document.activeElement),
        );
      }
    }
    await p.locator("#finishMission").click();
    assert.equal((await storage(p)).length, 0);
    checks++;
    await close(p);
    p = await fresh({
      "wake.alarms": [
        record({ typing: true, codeLength: 10, typingSeconds: 30 }),
      ],
    });
    await p.waitForSelector("#missionCode");
    const code = await p.locator("#missionBody .code").textContent();
    assert.equal(code.length, 10);
    await p.locator("#missionCode").fill(code);
    await p.locator("#checkCode").click();
    await p.locator("#finishMission").click();
    assert.equal((await storage(p)).length, 0);
    checks++;
    await close(p);
    p = await fresh({
      "wake.alarms": [record({ puzzle: true, pieces: 8, puzzleSeconds: 40 })],
    });
    await p.waitForSelector("[data-piece]");
    await p.screenshot({ path: path.join(output, "studio-puzzle.png") });
    for (let i = 0; i < 8; i++) {
      await p.locator(`[data-piece="${i}"]`).click();
      await p.locator(`[data-slot="${i}"]`).click();
    }
    await p.locator("#finishMission").click();
    assert.equal((await storage(p)).length, 0);
    checks++;
    await close(p);
    p = await fresh({
      "wake.alarms": [record({ mines: true, size: 9, mineSeconds: 40 })],
    });
    await p.waitForSelector("#mineDone");
    const board = await p.evaluate(
      () => JSON.parse(localStorage.getItem("wake.studio.mission")).board,
    );
    assert.equal(await p.locator(".mine-cell").count(), 81);
    assert(await p.locator("#mineDone").isDisabled());
    for (const i of board.mines)
      await p.locator(`[data-cell="${i}"]`).click({ button: "right" });
    assert(await p.locator("#mineDone").isEnabled());
    const extra = Array.from({ length: 81 }, (_, i) => i).find(
      (i) => !board.mines.includes(i) && !board.open.includes(i),
    );
    if (extra !== undefined) {
      await p.locator(`[data-cell="${extra}"]`).click({ button: "right" });
      assert(await p.locator("#mineDone").isDisabled());
      await p.locator(`[data-cell="${extra}"]`).click({ button: "right" });
    }
    await p.screenshot({ path: path.join(output, "studio-mines.png") });
    await p.locator("#mineDone").click();
    await p.locator("#finishMission").click();
    checks++;
    await close(p);
    p = await fresh({
      "wake.alarms": [
        record({ sudoku: true, difficulty: 3, sudokuSeconds: 240 }),
      ],
    });
    await p.waitForSelector("[data-sudoku]");
    const sudoku = await p.evaluate(
      () => JSON.parse(localStorage.getItem("wake.studio.mission")).board,
    );
    assert.equal(await p.locator(".sudoku-cell").count(), 36);
    await p.locator(`[data-sudoku="${sudoku.selected}"]`).click();
    await p.keyboard.press("ArrowRight");
    const selection = await p
      .locator(".sudoku-cell.selected")
      .getAttribute("data-sudoku");
    assert.notEqual(Number(selection), sudoku.selected);
    assert.equal(sudoku.givens[Number(selection)], 0);
    for (let i = 0; i < 36; i++)
      if (!sudoku.givens[i]) {
        await p.locator(`[data-sudoku="${i}"]`).click();
        await p.locator(`[data-digit="${sudoku.solution[i]}"]`).click();
      }
    await p.locator("#finishMission").click();
    checks++;
    await close(p);
    p = await fresh();
    const generated = await p.evaluate(() => {
      for (let d = 0; d < 4; d++) {
        const b = LunkStudio.makeSudoku(d);
        if (LunkStudio.solutions(b.size, b.givens) !== 1) return false;
      }
      for (const n of [5, 7, 9]) {
        const b = LunkStudio.makeMine(n);
        if (b.size !== n || !b.open.length) return false;
      }
      return true;
    });
    assert(generated);
    checks++;
    await workspace(p);
    await p.evaluate(() => {
      Storage.prototype.setItem = function (k, v) {
        if (k === "wake.alarms") throw Error("Quota");
      };
    });
    await p.locator("#setBtn").click();
    assert.equal((await storage(p)).length, 0);
    assert.match(
      await p.locator("#studioStatus").textContent(),
      /could not be saved/,
    );
    checks++;
    await close(p);
    // A once alarm stays saved but disabled; repeats advance instead of disappearing.
    for (const repeat of [[], [0, 1, 2, 3, 4, 5, 6]]) {
      const alarm = {
        ...record({}),
        type: "time",
        hour: 7,
        minute: 0,
        days: repeat,
      };
      p = await fresh({ "wake.alarms": [alarm] });
      await p.locator("#finishMission").click();
      const saved = (await storage(p))[0];
      assert.equal(saved.id, "ring");
      assert.equal(saved.enabled, repeat.length > 0);
      if (repeat.length) assert(saved.targetMs > Date.now());
      await p.reload();
      assert.equal((await storage(p)).length, 1);
      assert.equal(await p.locator("#mission").evaluate((d) => d.open), false);
      await close(p);
      checks++;
    }
    // Each operation produces valid whole-number questions and clears native entry.
    for (const op of ["+", "−", "÷"]) {
      p = await fresh({
        "wake.alarms": [
          record({ math: true, count: 1, mathSeconds: 15, ops: [op] }),
        ],
      });
      await p.waitForSelector("#missionAnswer");
      const value = await p.evaluate(
        () => JSON.parse(localStorage.getItem("wake.studio.mission")).answer,
      );
      assert(Number.isInteger(value) && value >= 0);
      await p.locator("#missionAnswer").fill(String(value));
      await p.locator("#finishMission").click();
      await close(p);
      checks++;
    }
    // Restoring a real mission keeps progress; expiry starts its whole sequence over.
    p = await fresh({
      "wake.alarms": [record({ math: true, count: 2, mathSeconds: 5 })],
    });
    await p.waitForSelector("#missionAnswer");
    let savedMission = await p.evaluate(() =>
      JSON.parse(localStorage.getItem("wake.studio.mission")),
    );
    await p.locator("#missionAnswer").fill(String(savedMission.answer));
    await p.reload();
    await p.waitForSelector("#missionAnswer");
    assert.match(await p.locator("#missionBody h3").textContent(), /1 \/ 2/);
    await p.locator("#missionAnswer").click();
    assert.equal(await p.locator("#answerSound").isChecked(), false);
    await p.waitForFunction(
      () =>
        document.querySelector("#missionBody h3")?.textContent ===
        "0 / 2 answered",
      null,
      { timeout: 8000 },
    );
    assert(await p.locator("#answerSound").isChecked());
    assert.equal(await p.locator("#missionAnswer").inputValue(), "");
    await close(p);
    checks++;
    // Practice typing remains open when focusing its input. Closing settings never enables it.
    p = await fresh();
    await workspace(p);
    await p.locator("[data-test=typing]").click();
    await p.screenshot({ path: path.join(output, "studio-test-settings.png") });
    await p.locator("#tryTest").click();
    await p.locator("#missionCode").click();
    assert(await p.locator("#mission").evaluate((d) => d.open));
    await p
      .locator("#missionCode")
      .fill(await p.locator("#missionBody .code").textContent());
    await p.locator("#checkCode").click();
    await p.locator("#exitPractice").click();
    await p.keyboard.press("Escape");
    assert.equal(
      await p.locator("[data-test=typing]").getAttribute("aria-pressed"),
      "false",
    );
    assert(await p.locator("#setupCard").isVisible());
    checks++;
    // All themes are selectable, gradients remain stable in either OS color scheme.
    for (const scheme of ["light", "dark"]) {
      await p.emulateMedia({ colorScheme: scheme });
      for (const theme of await p
        .locator(".theme-swatch")
        .evaluateAll((bs) => bs.map((b) => b.dataset.theme))) {
        await p.locator("#themeBtn").click();
        await p.locator(`#themeGrid [data-theme="${theme}"]`).click();
        assert.equal(await p.locator("html").getAttribute("data-theme"), theme);
        assert.equal(
          await p.locator("#themeDialog").evaluate((d) => d.open),
          false,
        );
      }
    }
    assert.equal(await p.locator(".theme-swatch").count(), 18);
    checks++;
    // Mouse wheel changes the selected field without scrolling the editor.
    await p.locator("#newAlarm").click();
    await p.locator("#alarmHour").fill("7");
    await p.locator("#alarmMinute").fill("59");
    await p.locator("#timeAM").click();
    await p.locator("#alarmMinute").hover();
    await p.mouse.wheel(0, -100);
    await p.waitForFunction(
      () => document.querySelector("#timeInput").value === "08:00",
    );
    assert.equal(await p.locator("#alarmHour").inputValue(), "8");
    await p.locator("#newTimer").click();
    await p.locator("#hoursInput").fill("0");
    await p.locator("#minutesInput").fill("0");
    await p.locator("#secondsInput").fill("59");
    await p.locator("#secondsInput").hover();
    await p.mouse.wheel(0, -100);
    await p.waitForFunction(
      () => document.querySelector("#minutesInput").value === "01",
    );
    assert.equal(await p.locator("#secondsInput").inputValue(), "00");
    checks++;
    await p.locator("#themeBtn").click();
    await p
      .getByRole("button", { name: "Midnight Cherry", exact: true })
      .click();
    await p.screenshot({ path: path.join(output, "studio-cherry.png") });
    await close(p);
    // Touch layout retains names and captures wheel duration when creating a timer.
    p = await fresh({}, { width: 390, height: 844 }, true);
    await workspace(p);
    await p.locator("#newTimer").click();
    await p.locator("#alarmName").fill("Touch timer");
    await p
      .locator('.presets [data-minutes="5"]')
      .filter({ hasText: "5 min" })
      .click();
    await p.locator("#setBtn").click();
    const touchTimer = (await storage(p))[0];
    assert.equal(touchTimer.duration, 300);
    assert.equal(touchTimer.name, "Touch timer");
    assert(await p.locator("#alarmName").isVisible());
    await close(p);
    checks++;
    // The uncluttered clock has a text-only upcoming schedule and chevron navigation.
    const future = Date.now() + 3600000;
    p = await fresh({
      "wake.alarms": [
        {
          id: "daily",
          type: "time",
          name: "Morning routine",
          targetMs: future,
          hour: 7,
          minute: 0,
          days: [0, 1, 2, 3, 4, 5, 6],
          enabled: true,
        },
        {
          id: "tea",
          type: "timer",
          name: "Tea break",
          targetMs: future,
          duration: 3600,
          enabled: true,
        },
        {
          id: "disabled",
          type: "time",
          name: "Disabled alarm",
          targetMs: future,
          hour: 9,
          minute: 0,
          enabled: false,
        },
      ],
      "wake.alarmsSidebarOpen": false,
    });
    assert.equal(
      await p
        .locator("#syncBadge,.brand-mark,.brand-caption,#focusClock,.eyebrow")
        .count(),
      0,
    );
    assert.equal(await p.locator("#focusAgenda .agenda-item").count(), 2);
    assert(await p.locator("#focusAgenda").isVisible());
    assert(
      await p
        .locator("#focusAgenda")
        .evaluate(
          (el) =>
            getComputedStyle(el).backgroundColor === "rgba(0, 0, 0, 0)" &&
            getComputedStyle(el).borderTopWidth === "0px",
        ),
    );
    assert.equal(await p.locator("#alarmPickerToggle").innerText(), "");
    assert.equal(
      await p.locator("#alarmPickerToggle").getAttribute("aria-expanded"),
      "false",
    );
    await p.screenshot({ path: path.join(output, "clock-with-agenda.png") });
    checks++;
    const finishMotion = async () => {
      await p.evaluate(async () => {
        if (clockViewTransition)
          await clockViewTransition.finished.catch(() => {});
      });
      await p.waitForTimeout(250);
    };
    const z = await p.locator("#zoneText").boundingBox(),
      c = await p.locator(".clock-card").boundingBox();
    await p.mouse.click(c.x + c.width / 2, z.y + z.height + 10);
    await p.waitForFunction(
      () => !document.documentElement.classList.contains("clock-focus"),
    );
    assert(
      await p.evaluate(async () => {
        if (!document.startViewTransition) return true;
        try {
          await clockViewTransition?.ready;
          return true;
        } catch {
          return false;
        }
      }),
      "Clock snapshots should animate without a skipped transition",
    );
    await finishMotion();
    assert.equal(
      await p.locator("#alarmPickerToggle").getAttribute("aria-expanded"),
      "true",
    );
    assert(await p.locator("#alarmsPanel").isVisible());
    assert(await p.locator("#alarmsToggle").isHidden());
    assert(
      await p
        .locator("#mainApp")
        .evaluate((el) => el.classList.contains("alarms-open")),
    );
    assert.equal(
      await p
        .locator("#mainApp")
        .evaluate((el) => getComputedStyle(el).transitionProperty),
      "none",
    );
    checks++;
    // Wheel-up over either panel must never collapse the workspace.
    for (const id of ["newAlarm", "alarmsHeading"]) {
      await p.locator("#" + id).hover();
      await p.mouse.wheel(0, -200);
      await p.waitForTimeout(150);
      assert.equal(
        await p.locator("#alarmPickerToggle").getAttribute("aria-expanded"),
        "true",
      );
    }
    await p.locator("#clockHM").hover();
    await p.mouse.wheel(0, -120);
    await p.waitForFunction(() =>
      document.documentElement.classList.contains("clock-focus"),
    );
    await finishMotion();
    await p.locator("#focusAgenda h2").first().hover();
    await p.mouse.wheel(0, 120);
    await p.waitForFunction(
      () => !document.documentElement.classList.contains("clock-focus"),
    );
    // Same-direction trackpad momentum must not bounce the new view back.
    await p.mouse.wheel(0, 120);
    await finishMotion();
    assert.equal(
      await p.locator("#alarmPickerToggle").getAttribute("aria-expanded"),
      "true",
    );
    checks++;
    // Day boxes stay legible across panel/window widths.
    for (const width of [1600, 1366, 1024, 390, 320]) {
      await p.setViewportSize({ width, height: 1000 });
      const sizes = await p.locator(".day-choice").evaluateAll((bs) =>
        bs.map((b) => {
          const r = b.getBoundingClientRect(),
            s = getComputedStyle(b);
          return {
            w: r.width,
            h: r.height,
            font: parseFloat(s.fontSize),
            weight: s.fontWeight,
          };
        }),
      );
      assert(
        sizes.every(
          (d) => d.w > 0 && d.h >= 40 && d.font >= 13 && d.weight === "500",
        ),
      );
      assert(
        await p.evaluate(
          () => document.documentElement.scrollWidth <= innerWidth + 1,
        ),
      );
    }
    await p.setViewportSize({ width: 1600, height: 1000 });
    checks++;
    // Preview lives beside volume, plays directly, and creates no alarm/dialog.
    const beforePreview = (await storage(p)).length;
    await p.locator("#checkSound").click();
    assert.equal(
      await p.locator("#checkSound").getAttribute("aria-pressed"),
      "true",
    );
    await p.waitForFunction(() => audioCtx?.state === "running");
    assert(await p.evaluate(() => !!sound.master));
    assert.equal(await p.locator("#sounds").evaluate((d) => d.open), false);
    await p.locator("#checkSound").click();
    assert(await p.evaluate(() => !sound.master));
    assert.equal((await storage(p)).length, beforePreview);
    await p.screenshot({ path: path.join(output, "workspace-refined.png") });
    checks++;
    await p.locator("#alarmPickerToggle").click();
    await finishMotion();
    await p
      .locator("#focusAgenda")
      .getByRole("button", { name: "Edit Morning routine", exact: true })
      .click();
    await finishMotion();
    assert.equal(await p.locator("#alarmName").inputValue(), "Morning routine");
    assert.equal(await p.locator("#editorTitle").textContent(), "Edit alarm");
    checks++;
    await close(p);
    // Same-origin HTTPS Date is automatic, cache-busted and never a UI badge.
    p = await fresh();
    await p.route("**/index.html?*", (r) =>
      r.fulfill({
        status: 200,
        headers: {
          date: new Date(Date.now() + 118000).toUTCString(),
          age: "2",
        },
      }),
    );
    await p.evaluate(() => syncTime());
    assert(
      await p.evaluate(
        () => state.hasSynced && Math.abs(state.timeOffsetMs - 120000) < 1000,
      ),
    );
    const lastGood = await p.evaluate(() => state.timeOffsetMs);
    await p.unroute("**/index.html?*");
    await p.route("**/index.html?*", (r) => r.abort());
    await p.evaluate(() => syncTime());
    assert.equal(await p.evaluate(() => state.timeOffsetMs), lastGood);
    assert.equal(await p.locator("#syncBadge").count(), 0);
    assert.notEqual(await p.locator("#clockHM").textContent(), "--:--");
    await close(p);
    checks++;

    // Backdrop clicks dismiss pickers without changing test activation.
    p = await fresh();
    await workspace(p);
    assert(
      await p.locator("#editorTitle").evaluate((el) => {
        const r = el.getBoundingClientRect();
        return r.height <= 1 && r.width <= 1;
      }),
    );
    for (const [trigger, dialog] of [
      ["#themeBtn", "#themeDialog"],
      ["#chooseSound", "#sounds"],
      ["[data-test=typing]", "#testSettings"],
    ]) {
      await p.locator(trigger).click();
      assert(await p.locator(dialog).evaluate((d) => d.open));
      await p.mouse.click(7, 7);
      await p.waitForFunction((id) => !document.querySelector(id).open, dialog);
    }
    assert.equal(
      await p.locator("[data-test=typing]").getAttribute("aria-pressed"),
      "false",
    );
    checks++;
    // The sound chevron stays at the right edge instead of following the text.
    const soundGeometry = await p.locator("#chooseSound").evaluate((el) => {
      const b = el.getBoundingClientRect(),
        arrow = el.querySelector("svg").getBoundingClientRect();
      return { right: b.right - arrow.right, size: arrow.width };
    });
    assert(soundGeometry.right >= 10 && soundGeometry.right <= 20);
    assert.equal(soundGeometry.size, 18);
    checks++;
    // Daily is a real checkbox and individual days have distinct filled states.
    assert.equal(await p.locator("#daily").getAttribute("type"), "checkbox");
    assert(await p.locator("#daily").isChecked());
    await p.locator("#daily").uncheck();
    assert.equal(await p.locator(".day-choice[aria-pressed=true]").count(), 0);
    const unset = await p
      .locator(".day-choice")
      .first()
      .evaluate((el) => getComputedStyle(el).backgroundColor);
    await p.getByRole("button", { name: "Sunday", exact: true }).click();
    const set = await p
      .locator(".day-choice")
      .first()
      .evaluate((el) => getComputedStyle(el).backgroundColor);
    assert.notEqual(set, unset);
    assert.equal(await p.locator("#daily").isChecked(), false);
    await p.locator("#daily").check();
    assert.equal(await p.locator(".day-choice[aria-pressed=true]").count(), 7);
    assert.equal(
      await p
        .locator(".day-choice")
        .first()
        .evaluate((el) => getComputedStyle(el).borderRadius),
      "12px",
    );
    checks++;
    await close(p);
    // Native palettes and corner opacity are retained with bounded desktop glow sizes.
    const nativeSource = await readFile(
      path.resolve(__dirname, "../../ios/LunkAlarm/Views/AlarmTheme.swift"),
      "utf8",
    );
    const paletteLines = nativeSource
      .split("\n")
      .filter(
        (line) => /AlarmTheme\(id: "/.test(line) && line.includes("name:"),
      );
    const paletteHex = (line, key) => {
      const m = line.match(
        new RegExp(
          key + ": (?:Color\\(hex: 0x([a-fA-F0-9]{6})\\)|\\.(white|black))",
        ),
      );
      return "#" + (m[1] || (m[2] === "white" ? "ffffff" : "000000"));
    };
    p = await fresh();
    for (const line of paletteLines) {
      const id = line.match(/id: "([^"]+)"/)[1];
      await p.locator("#themeBtn").click();
      await p.locator(`#themeGrid [data-theme="${id}"]`).click();
      const visuals = await p.evaluate(() => {
        const s = getComputedStyle(document.documentElement);
        return {
          bg: s.getPropertyValue("--bg").trim(),
          a: s.getPropertyValue("--accent").trim(),
          b: s.getPropertyValue("--accent-2").trim(),
          image: getComputedStyle(document.body).backgroundImage,
        };
      });
      assert.equal(visuals.bg, paletteHex(line, "background"));
      assert.equal(visuals.a, paletteHex(line, "accent"));
      assert.equal(visuals.b, paletteHex(line, "accent2"));
      if (["oled", "dark"].includes(id)) assert.equal(visuals.image, "none");
      else {
        assert(visuals.image.includes("radial-gradient"));
        assert(visuals.image.includes("560px"));
        assert(visuals.image.includes("/ 0.17"));
        assert(
          visuals.image.includes(
            line.includes("isLight: true") ? "/ 0.12" : "/ 0.22",
          ),
        );
      }
    }
    assert.equal(paletteLines.length, 18);
    checks++;
    await close(p);
    // Bottom-card actions escape the scroll panel and stay fully clickable.
    const alarms = Array.from({ length: 9 }, (_, i) => ({
      id: "bottom-" + i,
      type: "time",
      name: "Alarm " + i,
      targetMs: Date.now() + 3600000,
      hour: 7,
      minute: 0,
      enabled: false,
      days: [],
    }));
    p = await fresh({ "wake.alarms": alarms }, { width: 1280, height: 680 });
    await workspace(p);
    await p.locator(".routine-menu-trigger").last().scrollIntoViewIfNeeded();
    await p.waitForTimeout(100);
    await p.locator(".routine-menu-trigger").last().click();
    const menu = p.locator("#routineActions"),
      duplicate = menu.locator("[data-action=duplicate]");
    assert(await duplicate.isVisible());
    assert(
      await duplicate.evaluate((el) => {
        const r = el.getBoundingClientRect();
        return (
          r.top >= 0 &&
          r.bottom <= innerHeight &&
          document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2) ===
            el
        );
      }),
    );
    assert.equal(
      await menu.evaluate((el) => getComputedStyle(el).borderRadius),
      await p
        .locator(".routine-card")
        .last()
        .evaluate((el) => getComputedStyle(el).borderRadius),
    );
    await p.screenshot({ path: path.join(output, "bottom-card-actions.png") });
    await p.keyboard.press("Tab");
    assert(await duplicate.evaluate((el) => el === document.activeElement));
    await duplicate.click();
    assert.equal((await storage(p)).length, 10);
    checks++;
    await p.locator(".routine-menu-trigger").last().click();
    // A queued scroll event must not dismiss a newly opened menu.
    await p
      .locator("#alarmsCard")
      .evaluate((el) => el.dispatchEvent(new Event("scroll")));
    assert(await menu.isVisible());
    await p.keyboard.press("Escape");
    await p.waitForTimeout(400);
    assert.equal(
      await p.locator("#alarmPickerToggle").getAttribute("aria-expanded"),
      "true",
    );
    assert(await menu.isHidden());
    await p.locator(".routine-menu-trigger").last().click();
    await p.mouse.click(10, 10);
    assert(await menu.isHidden());
    await p.locator(".routine-menu-trigger").last().click();
    await menu.locator("[data-action=delete]").click();
    assert.equal((await storage(p)).length, 9);
    checks++;
    // Blank space under/above the left clock responds; the right side does not.
    await finishMotion();
    await p.mouse.move(8, 20);
    await p.mouse.wheel(0, -120);
    await p.waitForFunction(() =>
      document.documentElement.classList.contains("clock-focus"),
    );
    await finishMotion();
    await p.mouse.move(1268, 670);
    await p.mouse.wheel(0, 120);
    await p.waitForFunction(
      () => !document.documentElement.classList.contains("clock-focus"),
    );
    await finishMotion();
    await p.mouse.move(1268, 20);
    await p.mouse.wheel(0, -120);
    await p.waitForTimeout(200);
    assert.equal(
      await p.locator("#alarmPickerToggle").getAttribute("aria-expanded"),
      "true",
    );
    checks++;
    await close(p);

    // Font choices preserve the current default and affect only the clock display.
    p = await fresh();
    assert.equal(
      await p.locator("html").getAttribute("data-clock-font"),
      "inter",
    );
    assert.equal(
      await p
        .locator("#clockHM")
        .evaluate((el) => getComputedStyle(el).fontWeight),
      "200",
    );
    const originalBodyFont = await p
      .locator("body")
      .evaluate((el) => getComputedStyle(el).fontFamily);
    await p.setViewportSize({ width: 1919, height: 912 });
    assert(
      await p.evaluate(() =>
        getComputedStyle(document.body).backgroundImage.includes("560px"),
      ),
    );
    await p.screenshot({ path: path.join(output, "sunrise-corners-wide.png") });
    checks++;
    const expectedFonts = {
      inter: "Wake Clock",
      rounded: "Clock Rounded",
      mono: "Clock Mono",
      serif: "Georgia",
      digital: "Clock Digital",
    };
    for (const [id, family] of Object.entries(expectedFonts)) {
      await p.locator("#themeBtn").click();
      if (!(await p.locator("#clockFontGroup").evaluate((el) => el.open)))
        await p.locator("#clockFontGroup summary").click();
      await p.locator(`[data-clock-choice="${id}"]`).click();
      await p.waitForFunction(
        (id) =>
          document.documentElement.dataset.clockFont === id &&
          !document.querySelector("#themeDialog").open,
        id,
      );
      assert(
        (
          await p
            .locator("#clockHM")
            .evaluate((el) => getComputedStyle(el).fontFamily)
        ).includes(family),
      );
      assert.equal(
        await p
          .locator("body")
          .evaluate((el) => getComputedStyle(el).fontFamily),
        originalBodyFont,
      );
      for (const width of [1919, 1024, 390, 320]) {
        await p.setViewportSize({ width, height: 912 });
        assert(
          await p.locator("#clockHM").evaluate((el) => {
            el.textContent = "12:59";
            const r = el.getBoundingClientRect();
            return r.left >= 0 && r.right <= innerWidth;
          }),
          id + " clock overflow at " + width,
        );
      }
      await p.setViewportSize({ width: 1600, height: 1000 });
      if (["rounded", "digital"].includes(id))
        await p.screenshot({
          path: path.join(output, "clock-font-" + id + ".png"),
        });
    }
    await p.reload();
    await p.evaluate(() => document.fonts.ready);
    assert.equal(
      await p.locator("html").getAttribute("data-clock-font"),
      "digital",
    );
    assert.equal(
      await p.evaluate(() =>
        JSON.parse(localStorage.getItem("wake.clockFont")),
      ),
      "digital",
    );
    await p.locator("#themeBtn").click();
    if (!(await p.locator("#clockFontGroup").evaluate((el) => el.open)))
      await p.locator("#clockFontGroup summary").click();
    await p.screenshot({ path: path.join(output, "clock-font-picker.png") });
    await p.locator("[data-clock-choice=inter]").click();
    await p.waitForFunction(
      () =>
        document.documentElement.dataset.clockFont === "inter" &&
        !document.querySelector("#themeDialog").open,
    );
    assert.equal(
      await p
        .locator("#clockHM")
        .evaluate((el) => getComputedStyle(el).fontWeight),
      "200",
    );
    checks++;
    await workspace(p);
    await p.locator("#alarmName").fill("Keep this alarm");
    await p.locator("#setBtn").click();
    const savedBeforeCancel = (await storage(p))[0];
    await p
      .getByRole("button", { name: "Edit Keep this alarm", exact: true })
      .click();
    assert(await p.locator(".editor-action-row #cancelEdit").isVisible());
    assert.equal(await p.locator(".create-switch #cancelEdit").count(), 0);
    const cancelBox = await p.locator("#cancelEdit").boundingBox(),
      saveBox = await p.locator("#setBtn").boundingBox();
    assert(
      Math.abs(cancelBox.y - saveBox.y) < 1 &&
        Math.abs(cancelBox.height - saveBox.height) < 1,
    );
    await p.locator("#alarmName").fill("Discard this edit");
    await p.locator("#cancelEdit").click();
    assert.deepEqual((await storage(p))[0], savedBeforeCancel);
    assert.equal(await p.locator("#setBtn").textContent(), "Add alarm");
    assert(await p.locator("#cancelEdit").isHidden());
    await p
      .getByRole("button", { name: "Edit Keep this alarm", exact: true })
      .click();
    await p.screenshot({
      path: path.join(output, "edit-actions-integrated.png"),
    });
    checks++;
    await close(p);

    // Compact cards keep one time display, actual names, and separate controls.
    const compactRecords = [
      {
        id: "compact-alarm",
        type: "time",
        name: "",
        hour: 9,
        minute: 0,
        days: [0, 1, 2, 3, 4, 5, 6],
        enabled: false,
        targetMs: Date.now() + 3600000,
        tests: { typing: true, math: true, sudoku: true },
      },
      {
        id: "compact-timer",
        type: "timer",
        name: "",
        duration: 1800,
        enabled: true,
        targetMs: Date.now() + 1800000,
      },
      {
        id: "named-alarm",
        type: "time",
        name: "Morning routine",
        hour: 7,
        minute: 30,
        days: [1, 3, 5],
        enabled: false,
        targetMs: Date.now() + 3600000,
        tests: {
          typing: true,
          math: true,
          puzzle: true,
          mines: true,
          sudoku: true,
        },
      },
    ];
    p = await fresh(
      { "wake.alarms": compactRecords, "wake.theme": "cobalt-coral" },
      { width: 1920, height: 1080 },
    );
    await workspace(p);
    const blankAlarm = p.getByRole("button", {
      name: "Edit alarm",
      exact: true,
    });
    const blankTimer = p.getByRole("button", {
      name: "Edit timer",
      exact: true,
    });
    assert.equal(await blankAlarm.locator(".routine-name").count(), 0);
    assert.equal(await blankTimer.locator(".routine-name").count(), 0);
    assert.equal(
      await blankAlarm.locator(".routine-repeat").textContent(),
      "Daily",
    );
    assert.equal(await blankTimer.locator(".remaining").count(), 1);
    assert.equal(await p.locator(".routine-footer").count(), 0);
    assert(!(await blankTimer.textContent()).includes("remaining"));
    const countdown = await blankTimer.locator(".remaining").textContent();
    await p.waitForFunction(
      (before) =>
        document.querySelector(".routine-card.is-timer .remaining")
          .textContent !== before,
      countdown,
    );
    const split = await blankAlarm.evaluate((el) => {
      const time = el.querySelector(".routine-time").getBoundingClientRect();
      const copy = el.querySelector(".routine-copy").getBoundingClientRect();
      const card = el.closest(".routine-card").getBoundingClientRect();
      const controls = el
        .closest(".routine-card")
        .querySelector(".routine-controls")
        .getBoundingClientRect();
      return { time, copy, card, controls };
    });
    assert(split.time.right < split.copy.left);
    assert(split.copy.right <= split.controls.left);
    assert(split.card.height <= 105);
    const nameBox = await p.locator("#alarmName").boundingBox();
    const dayBox = await p.locator(".day-choice").first().boundingBox();
    assert(
      Math.abs(nameBox.y - dayBox.y) < 1,
      "Name and repeat-day tops align",
    );
    assert(Math.abs(nameBox.height - dayBox.height) < 1);
    assert.equal(await p.locator(".routine-repeat .day-dot.chosen").count(), 3);
    await p.screenshot({
      path: path.join(output, "compact-time-led-desktop.png"),
    });
    await p
      .locator("#alarmsCard")
      .screenshot({ path: path.join(output, "compact-time-led-cards.png") });
    await p
      .getByRole("button", { name: "Edit Morning routine", exact: true })
      .click();
    assert.equal(await p.locator("#alarmName").inputValue(), "Morning routine");
    checks++;
    await close(p);
    for (const width of [320, 390, 1280]) {
      p = await fresh(
        {
          "wake.alarms": [
            {
              ...compactRecords[0],
              name: "A very long saved alarm name that stays on one line",
              tests: compactRecords[2].tests,
            },
            {
              ...compactRecords[1],
              name: "A long running timer",
              targetMs: Date.now() + 359999000,
            },
          ],
        },
        { width, height: 900 },
      );
      await workspace(p);
      assert(
        await p.locator(".routine-card").evaluateAll((cards) =>
          cards.every((card) => {
            const edit = card.querySelector(".routine-edit");
            const controls = card
              .querySelector(".routine-controls")
              .getBoundingClientRect();
            return (
              edit.scrollWidth <= edit.clientWidth + 1 &&
              edit.getBoundingClientRect().right <= controls.left &&
              card.scrollWidth <= card.clientWidth + 1
            );
          }),
        ),
        `Compact cards fit at ${width}px`,
      );
      assert(
        await p.evaluate(
          () => document.documentElement.scrollWidth <= innerWidth,
        ),
      );
      checks++;
      await close(p);
    }

    // Stroop rounds always conflict with the ink, with fixed labels and decoy fills.
    p = await fresh({
      "wake.studio.tests": { stroopRounds: 99, stroopSeconds: 0 },
    });
    assert(
      await p.evaluate(() => {
        const colors = ["red", "blue", "green", "yellow"];
        let previous;
        for (let i = 0; i < 500; i++) {
          const round = LunkStudio.makeStroop(previous);
          if (
            !colors.includes(round.ink) ||
            !colors.includes(round.word) ||
            round.ink === round.word ||
            round.ink === previous ||
            new Set(round.buttonColors).size !== 4 ||
            round.buttonColors.some(
              (color, n) => !colors.includes(color) || color === colors[n],
            )
          )
            return false;
          previous = round.ink;
        }
        return true;
      }),
    );
    await workspace(p);
    assert.equal(await p.locator(".test-tile").count(), 6);
    await p.locator("[data-test=stroop]").click();
    assert.equal(
      await p
        .locator("[data-setting=stroopRounds][aria-pressed=true]")
        .getAttribute("data-value"),
      "5",
    );
    assert.equal(
      await p
        .locator("[data-setting=stroopSeconds][aria-pressed=true]")
        .getAttribute("data-value"),
      "5",
    );
    assert.deepEqual(
      await p.locator("[data-setting=stroopRounds]").allTextContents(),
      ["3", "4", "5", "6", "7", "8"],
    );
    assert.deepEqual(
      await p.locator("[data-setting=stroopSeconds]").allTextContents(),
      ["3s", "4s", "5s", "6s"],
    );
    checks++;
    await close(p);

    p = await fresh({ "wake.studio.tests": { typing: true } });
    await workspace(p);
    await p.locator("[data-test=stroop]").click();
    await p.locator('[data-setting=stroopRounds][data-value="8"]').click();
    await p.locator('[data-setting=stroopSeconds][data-value="6"]').click();
    await p.screenshot({ path: path.join(output, "stroop-settings.png") });
    await p.locator("#tryTest").click();
    assert.equal(
      await p.locator("#missionTitle").textContent(),
      "Stroop practice",
    );
    assert.deepEqual(
      await p.locator("[data-stroop-choice]").allTextContents(),
      ["Red", "Blue", "Green", "Yellow"],
    );
    let ink = await p.locator(".stroop-word").getAttribute("data-ink");
    // Picking a matching button background is wrong: the label names the answer.
    await p.locator(`[data-button-color="${ink}"]`).click();
    assert.equal(
      await p.locator("#missionBody h3").textContent(),
      "0 / 8 rounds",
    );
    assert.match(await p.locator("#missionHint").textContent(), /Try again/);
    await p.screenshot({ path: path.join(output, "stroop-practice.png") });
    for (let i = 0; i < 8; i++) {
      const word = p.locator(".stroop-word");
      ink = await word.getAttribute("data-ink");
      assert.notEqual((await word.textContent()).toLowerCase(), ink);
      const button = p.locator(`[data-stroop-choice="${ink}"]`);
      await button.focus();
      await p.keyboard.press("Enter");
      if (i < 7) {
        assert.equal(
          await p.locator("#missionBody h3").textContent(),
          `${i + 1} / 8 rounds`,
        );
        assert.notEqual(await word.getAttribute("data-ink"), ink);
        assert.equal(
          await p.locator(":focus").getAttribute("data-stroop-choice"),
          ink,
        );
        assert.deepEqual(
          await p.locator("[data-stroop-choice]").allTextContents(),
          ["Red", "Blue", "Green", "Yellow"],
        );
      }
    }
    assert.equal(await p.locator("#finishMission").textContent(), "Try again");
    await p.locator("#finishMission").click();
    assert.equal(
      await p.locator("#missionBody h3").textContent(),
      "0 / 8 rounds",
    );
    await p.locator("#exitPractice").click();
    assert.equal(await p.locator("#setTest").textContent(), "Set");
    assert.equal((await storage(p)).length, 0);
    await p.locator("#setTest").click();
    assert.equal(
      await p.locator("[data-test=typing]").getAttribute("aria-pressed"),
      "true",
    );
    await p.locator("#alarmName").fill("Stroop wake-up");
    await p.locator("#setBtn").click();
    const stroopAlarm = (await storage(p))[0];
    assert.equal(stroopAlarm.tests.stroop, true);
    assert.equal(stroopAlarm.tests.stroopRounds, 8);
    assert.equal(stroopAlarm.tests.stroopSeconds, 6);
    assert(
      (await p.locator(".routine-tests").textContent()).includes("Stroop"),
    );
    await p
      .getByRole("button", { name: "Options for Stroop wake-up", exact: true })
      .click();
    await p.locator("#routineActions [data-action=duplicate]").click();
    assert.equal((await storage(p)).length, 2);
    assert.deepEqual((await storage(p))[1].tests, stroopAlarm.tests);
    await p.reload();
    await workspace(p);
    await p.locator("[data-test=stroop]").click();
    assert.equal(await p.locator("#setTest").textContent(), "Unset");
    await p.locator("#closeTest").click();
    assert.equal(
      await p.locator("[data-test=stroop]").getAttribute("aria-pressed"),
      "true",
    );
    checks++;
    await close(p);

    // Real alarms retain rounds across reload and restart the entire sequence on expiry.
    p = await fresh({
      "wake.alarms": [
        record({
          math: true,
          count: 1,
          mathSeconds: 15,
          stroop: true,
          stroopRounds: 3,
          stroopSeconds: 3,
        }),
      ],
    });
    await p.waitForSelector("#missionAnswer");
    await p
      .locator("#missionAnswer")
      .fill(
        String(
          await p.evaluate(
            () =>
              JSON.parse(localStorage.getItem("wake.studio.mission")).answer,
          ),
        ),
      );
    await p.waitForSelector(".stroop-word");
    const firstDeadline = await p.evaluate(
      () => JSON.parse(localStorage.getItem("wake.studio.mission")).deadline,
    );
    ink = await p.locator(".stroop-word").getAttribute("data-ink");
    await p.locator(`[data-stroop-choice="${ink}"]`).click();
    savedMission = await p.evaluate(() =>
      JSON.parse(localStorage.getItem("wake.studio.mission")),
    );
    assert.equal(savedMission.done, 1);
    assert(savedMission.deadline > firstDeadline);
    await p.reload();
    await p.waitForSelector(".stroop-word");
    assert.equal(
      await p.locator("#missionBody h3").textContent(),
      "1 / 3 rounds",
    );
    assert.deepEqual(
      await p.evaluate(
        () => JSON.parse(localStorage.getItem("wake.studio.mission")).stroop,
      ),
      savedMission.stroop,
    );
    ink = await p.locator(".stroop-word").getAttribute("data-ink");
    await p.locator(`[data-button-color="${ink}"]`).click();
    assert.equal(await p.locator("#answerSound").isChecked(), false);
    await p.waitForSelector("#missionAnswer", { timeout: 7000 });
    assert.equal(
      await p.locator("#missionBody h3").textContent(),
      "0 / 1 answered",
    );
    assert(await p.locator("#answerSound").isChecked());
    await p
      .locator("#missionAnswer")
      .fill(
        String(
          await p.evaluate(
            () =>
              JSON.parse(localStorage.getItem("wake.studio.mission")).answer,
          ),
        ),
      );
    for (let i = 0; i < 3; i++) {
      ink = await p.locator(".stroop-word").getAttribute("data-ink");
      await p.locator(`[data-stroop-choice="${ink}"]`).click();
    }
    await p.locator("#finishMission").click();
    assert.equal((await storage(p)).length, 0);
    checks++;
    await close(p);

    for (const [viewport, theme] of [
      [{ width: 320, height: 740 }, "light"],
      [{ width: 390, height: 844 }, "midnight-cherry"],
      [{ width: 1600, height: 1000 }, "deep-ocean"],
    ]) {
      p = await fresh({ "wake.theme": theme }, viewport, viewport.width < 1000);
      await workspace(p);
      await p.locator("[data-test=stroop]").click();
      await p.locator('[data-setting=stroopSeconds][data-value="6"]').click();
      await p.locator("#tryTest").click();
      assert(
        await p
          .locator("#mission")
          .evaluate((el) => el.scrollWidth <= el.clientWidth + 1),
      );
      assert(
        await p
          .locator(".stroop-choices")
          .evaluate((el) => el.scrollWidth <= el.clientWidth),
      );
      assert.equal(await p.locator("[data-stroop-choice]").count(), 4);
      assert(
        await p.locator(".stroop-choice").evaluateAll((buttons) =>
          buttons.every((button) => {
            const style = getComputedStyle(button);
            const luminance = (color) => {
              const rgb = color
                .match(/[\d.]+/g)
                .slice(0, 3)
                .map((n) => Number(n) / 255)
                .map((n) =>
                  n <= 0.04045 ? n / 12.92 : ((n + 0.055) / 1.055) ** 2.4,
                );
              return rgb[0] * 0.2126 + rgb[1] * 0.7152 + rgb[2] * 0.0722;
            };
            const a = luminance(style.color),
              b = luminance(style.backgroundColor);
            return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05) >= 4.5;
          }),
        ),
        "Colored answer labels stay readable",
      );
      await p.screenshot({ path: path.join(output, `stroop-${theme}.png`) });
      checks++;
      await close(p);
    }

    assert.deepEqual(errors, []);
    console.log(
      "PASS",
      checks,
      "browser scenarios; desktop/mobile layouts, saved data, all six games, and quota handling.",
    );
  } catch (error) {
    error.testContext = `After ${checks} completed browser scenarios`;
    const failedPage = browser.contexts().at(-1)?.pages().at(-1);
    if (failedPage)
      await failedPage
        .screenshot({ path: path.join(output, "failure.png"), fullPage: true })
        .catch(() => {});
    throw error;
  } finally {
    await browser.close();
    server.close();
  }
})().catch((e) => {
  console.error(e);
  const detail = `${e.testContext || ""}\n${e.stack || e}`
    .replace(/%/g, "%25")
    .replace(/\r/g, "%0D")
    .replace(/\n/g, "%0A");
  console.error(`::error title=Website browser failure::${detail}`);
  process.exit(1);
});
