// Developer check only; the deployed web/ folder needs no Node dependencies.
const { chromium } = require('playwright');
const { existsSync } = require('node:fs');
const { createServer } = require('node:http');
const { readFile, mkdir } = require('node:fs/promises');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../../web');
const output = path.resolve(__dirname, '../../artifacts/web-previews');
const mime = { '.html': 'text/html', '.css': 'text/css', '.js': 'text/javascript', '.png': 'image/png' };
const server = createServer(async (req, res) => {
  try {
    let file = new URL(req.url, 'http://local').pathname;
    file = file === '/' ? '/index.html' : file;
    if (!/^\/[\w.-]+$/.test(file)) throw new Error('Bad path');
    const data = await readFile(path.join(root, file));
    res.writeHead(200, { 'Content-Type': mime[path.extname(file)] || 'application/octet-stream' });
    res.end(data);
  } catch { res.writeHead(404); res.end('Not found'); }
});
let browser;
(async () => {
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const url = `http://127.0.0.1:${server.address().port}`;
  await mkdir(output, { recursive: true });
  browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || (existsSync('/usr/bin/chromium') ? '/usr/bin/chromium' : undefined), headless: true });
  const page = await browser.newPage({ viewport: { width: 1100, height: 1000 } });
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  // External clocks unavailable/offline must not prevent alarms working.
  await page.route('https://**/*', route => route.abort());
  await page.goto(url);
  await page.waitForFunction(() => document.querySelector('#syncText').textContent.includes('Offline'));
  assert.equal(await page.locator('#ringtoneSelect option').count(), 10);
  console.log('PASS offline startup and ten tones');
  await page.locator('#enableSoundBtn').click();
  await page.waitForFunction(() => document.querySelector('#enableSoundBtn').textContent === 'Sound ready');
  console.log('PASS audio context enabled by user gesture');
  for (const mode of ['light', 'dark']) {
    await page.emulateMedia({ colorScheme: mode });
    await page.locator('#themeBtn').click();
    for (const theme of ['sunrise', 'oled', 'dark', 'light', 'tokyo-night', 'vscode-blue', 'dracula', 'nord']) {
      await page.locator(`[data-theme="${theme}"].theme-swatch`).click();
      const colors = await page.evaluate(() => ({
        theme: document.documentElement.dataset.theme,
        foreground: getComputedStyle(document.body).color,
        background: getComputedStyle(document.body).backgroundColor
      }));
      assert.equal(colors.theme, theme);
      assert.notEqual(colors.foreground, colors.background);
    }
    await page.locator('[data-theme="sunrise"].theme-swatch').click();
    await page.locator('#closeThemeBtn').click();
  }
  console.log('PASS eight themes with both system color schemes');
  await page.screenshot({ path: path.join(output, 'desktop.png'), fullPage: true });
  await page.setViewportSize({ width: 375, height: 812 });
  assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
  await page.screenshot({ path: path.join(output, 'phone.png'), fullPage: true });
  console.log('PASS phone layout has no horizontal overflow');
  await page.locator('#tabTimer').click();
  await page.locator('#hoursInput').fill('0'); await page.locator('#minutesInput').fill('0');
  await page.locator('#secondsInput').fill('0'); await page.locator('#setBtn').click();
  assert.equal(await page.locator('.alarm-item').count(), 0);
  assert.match(await page.locator('#formMsg').innerText(), /greater than zero/);
  console.log('PASS zero duration rejected');
  await page.locator('#secondsInput').fill('2');
  await page.locator('#typingToggle').check(); await page.locator('#mathToggle').check();
  await page.locator('[data-count="2"]').click(); await page.locator('#setBtn').click();
  await page.locator('#ringOverlay').waitFor({ state: 'visible', timeout: 6000 });
  assert(await page.evaluate(() => document.querySelector('#mainApp').inert));
  const code = await page.locator('#codeText').innerText();
  await page.locator('#codeInput').fill('!!!!!!!!');
  assert.match(await page.locator('#typingMsg').innerText(), /Not quite/);
  await page.locator('#codeInput').fill(code);
  await page.locator('#stepMath').waitFor({ state: 'visible' });
  await page.keyboard.type('99'); await page.keyboard.press('Enter');
  assert.match(await page.locator('#mathMsg').innerText(), /Not right/);
  for (let n = 0; n < 2; n++) {
    const digits = (await page.locator('#mathProblem').innerText()).match(/\d+/g).map(Number);
    await page.keyboard.type(String(digits[0] + digits[1])); await page.keyboard.press('Enter');
  }
  await page.locator('#ringOverlay').waitFor({ state: 'hidden' });
  assert.equal(await page.locator('.alarm-item').count(), 0);
  console.log('PASS timer rings, typing then math enforce correct answers, dismiss removes alarm');
  await page.locator('#typingToggle').uncheck(); await page.locator('#mathToggle').uncheck();
  await page.locator('#secondsInput').fill('45'); await page.locator('#setBtn').click();
  await page.reload();
  assert.equal(await page.locator('.alarm-item').count(), 1);
  assert.equal(await page.locator('#tabTimer').getAttribute('aria-selected'), 'true');
  await page.locator('.delete-btn').click(); await page.reload();
  assert.equal(await page.locator('.alarm-item').count(), 0);
  console.log('PASS pending alarms and removal survive reload');
  // Two already-due alarms must be delivered sequentially after restoring storage.
  await page.evaluate(() => localStorage.setItem('wake.alarms', JSON.stringify([1, 2].map(i => ({
    id: String(i), targetMs: Date.now() - 1000, ringtoneId: 'classic-beep', typing: false, mathCount: 0, ringing: false
  })))));
  await page.reload();
  for (let n = 0; n < 2; n++) {
    await page.locator('#ringOverlay').waitFor({ state: 'visible' });
    await page.locator('#stopBtn').click();
    if (n === 0) await page.waitForFunction(() => JSON.parse(localStorage.getItem('wake.alarms')).length === 1);
  }
  await page.locator('#ringOverlay').waitFor({ state: 'hidden' });
  assert.equal(await page.locator('.alarm-item').count(), 0);
  console.log('PASS simultaneous alarms queue instead of disappearing');
  // Read-only storage should show a failure, not report a successful saved alarm.
  await page.evaluate(() => { Storage.prototype.setItem = () => { throw new DOMException('full', 'QuotaExceededError'); }; });
  await page.locator('#tabTimer').click(); await page.locator('#minutesInput').fill('1');
  await page.locator('#setBtn').click();
  assert.match(await page.locator('#formMsg').innerText(), /Could not save alarms/);
  assert.equal(await page.locator('.alarm-item').count(), 0);
  console.log('PASS storage failure prevents false successful add');
  assert.deepEqual(errors, []);
  console.log('PASS no uncaught browser errors; static website checks complete');
})().catch(error => { console.error(error); process.exitCode = 1; }).finally(async () => {
  await browser?.close(); server.close();
});
