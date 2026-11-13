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
    await p.locator(".routine-menu summary").click();
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
    assert.deepEqual(errors, []);
    console.log(
      "PASS",
      checks,
      "browser scenarios; desktop/mobile layouts, saved data, all five games, and quota handling.",
    );
  } finally {
    await browser.close();
    server.close();
  }
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
