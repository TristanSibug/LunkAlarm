// Developer check only; the deployed web/ folder needs no Node dependencies.
const { chromium } = require('playwright');
const { existsSync } = require('node:fs');
const { createServer } = require('node:http');
const { readFile, mkdir } = require('node:fs/promises');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../../web');
const output = path.resolve(__dirname, '../../artifacts/web-previews');
const mime = { '.html': 'text/html', '.css': 'text/css', '.js': 'text/javascript', '.png': 'image/png', '.woff2': 'font/woff2' };
const server = createServer(async (req, res) => {
  try {
    let file = new URL(req.url, 'http://local').pathname;
    file = file === '/' ? '/index.html' : file;
    if (!/^\/(?:[\w-]+\/)*[\w.-]+$/.test(file) || file.split('/').includes('..')) throw new Error('Bad path');
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
  await page.evaluate(() => document.fonts.ready);
  assert(await page.evaluate(() => [...document.fonts].some(font => font.family === 'Wake Clock' && font.status === 'loaded')));
  assert.equal(await page.locator('.clock-buttons #enableSoundBtn').count(), 1);
  assert(await page.locator('#clockHM').evaluate(el => !getComputedStyle(el).fontFamily.includes('Wake Clock')));
  console.log('PASS offline startup, original clock font, numeric field font, and top sound button');
  await page.locator('#enableSoundBtn').click();
  await page.waitForFunction(() => document.querySelector('#enableSoundBtn').textContent === 'Sound ready');
  console.log('PASS audio context enabled by user gesture');
  const picker = page.locator('#ringtonePicker');
  const menu = page.locator('#ringtoneMenu');
  await picker.click();
  assert.equal(await menu.getByRole('option').count(), 10);
  await picker.click();
  assert.equal(await picker.getAttribute('aria-expanded'), 'false');
  await picker.click();
  await page.keyboard.press('End'); await page.keyboard.press('Enter');
  assert.match(await picker.innerText(), /Siren/);
  assert.equal(await page.evaluate(() => localStorage.getItem('wake.ringtone')), '"siren"');
  await picker.click(); await page.keyboard.press('ArrowUp'); await page.keyboard.press('Escape');
  assert.match(await picker.innerText(), /Siren/);
  assert.equal(await picker.getAttribute('aria-expanded'), 'false');
  await picker.focus(); await page.keyboard.type('soft'); await page.keyboard.press('Enter');
  assert.match(await picker.innerText(), /Soft Chime/);
  await picker.click();
  await menu.getByRole('option', { name: 'Classic Beep', exact: true }).click();
  await picker.click(); await page.keyboard.press('Tab');
  assert.equal(await page.locator('#previewBtn').evaluate(el => el === document.activeElement), true);
  assert.equal(await picker.getAttribute('aria-expanded'), 'false');
  await picker.click(); await page.locator('#themeBtn').click();
  assert.equal(await picker.getAttribute('aria-expanded'), 'false');
  await page.locator('#closeThemeBtn').click();
  console.log('PASS custom picker keyboard navigation, type-ahead, selection, Escape, Tab and outside dismissal');

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
    await picker.click();
    assert.equal(await menu.getByRole('option', { selected: true }).count(), 1);
    assert(await menu.evaluate(el => getComputedStyle(el).backgroundColor !== 'rgba(0, 0, 0, 0)'));
    await page.keyboard.press('Escape');
  }
  console.log('PASS eight themes with both system color schemes');
  // Keep the approved form layout; the restored three-button toolbar can wrap above the clock.
  for (const width of [520, 462, 375, 320]) {
    await page.setViewportSize({ width, height: 900 });
    const layout = await page.evaluate(() => {
      const box = id => document.getElementById(id).getBoundingClientRect();
      const sound = box('enableSoundBtn'), theme = box('themeBtn');
      return {
        overflow: document.documentElement.scrollWidth > innerWidth,
        headerOffset: Math.abs(sound.y + sound.height / 2 - theme.y - theme.height / 2),
        formTop: box('setupCard').top + scrollY,
        pickerHeight: box('ringtonePicker').height,
        timeAlign: getComputedStyle(document.getElementById('timeInput')).textAlign
      };
    });
    assert.equal(layout.overflow, false);
    assert(layout.headerOffset < 2, `Toolbar buttons misaligned at ${width}px`);
    assert(layout.formTop < 355, `Form pushed down at ${width}px`);
    assert.equal(layout.pickerHeight, 36);
    assert.equal(layout.timeAlign, 'left');
    await picker.click();
    const popup = await menu.boundingBox();
    assert(popup.x >= 0 && popup.x + popup.width <= width + 1);
    assert(popup.y >= 0 && popup.y + popup.height <= 901);
    await page.keyboard.press('Escape');
  }
  console.log('PASS approved form proportions and restored toolbar at 320–520px');
  await page.setViewportSize({ width: 520, height: 900 });
  await picker.click();
  await menu.waitFor({ state: 'visible' });
  await page.screenshot({ path: path.join(output, 'ringtone-picker.png') });
  assert.equal(await picker.getAttribute('aria-expanded'), 'true');
  await page.keyboard.press('Escape');
  await page.locator('#typingToggle').check(); await page.locator('#mathToggle').check();
  await page.screenshot({ path: path.join(output, 'mac-layout.png'), fullPage: true });
  await page.locator('#typingToggle').uncheck(); await page.locator('#mathToggle').uncheck();
  await page.setViewportSize({ width: 1100, height: 1000 });
  await page.screenshot({ path: path.join(output, 'desktop.png'), fullPage: true });
  await page.setViewportSize({ width: 375, height: 812 });
  assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
  await page.screenshot({ path: path.join(output, 'phone.png'), fullPage: true });
  console.log('PASS phone layout has no horizontal overflow');
  const wave = Buffer.alloc(204);
  wave.write('RIFF', 0); wave.writeUInt32LE(196, 4); wave.write('WAVEfmt ', 8);
  wave.writeUInt32LE(16, 16); wave.writeUInt16LE(1, 20); wave.writeUInt16LE(1, 22);
  wave.writeUInt32LE(8000, 24); wave.writeUInt32LE(16000, 28); wave.writeUInt16LE(2, 32);
  wave.writeUInt16LE(16, 34); wave.write('data', 36); wave.writeUInt32LE(160, 40);
  await page.locator('#fileInput').setInputFiles({ name: 'My morning.wav', mimeType: 'audio/wav', buffer: wave });
  await page.waitForFunction(() => document.querySelector('#ringtonePickerLabel').textContent.includes('My morning.wav'));
  await page.reload();
  assert.match(await picker.innerText(), /My morning.wav/);
  await picker.click();
  assert.equal(await menu.getByRole('option').count(), 11);
  assert.match(await menu.getByRole('option', { selected: true }).innerText(), /My morning.wav/);
  await menu.getByRole('option', { name: 'Classic Beep', exact: true }).click();
  console.log('PASS imported custom sound and selected option survive reload');
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
  const fallback = await browser.newPage();
  await fallback.addInitScript(() => { delete HTMLElement.prototype.showPopover; });
  await fallback.route('https://**/*', route => route.abort());
  await fallback.goto(url);
  assert(await fallback.locator('#ringtoneSelect').isVisible());
  assert(await fallback.locator('#ringtonePicker').isHidden());
  assert(await fallback.locator('#ringtoneMenu').isHidden());
  await fallback.locator('#ringtoneSelect').selectOption('soft-chime');
  assert.equal(await fallback.evaluate(() => localStorage.getItem('wake.ringtone')), '\"soft-chime\"');
  await fallback.close();
  console.log('PASS native select fallback on browsers without popover support');
  assert.deepEqual(errors, []);
  console.log('PASS no uncaught browser errors; static website checks complete');
})().catch(error => { console.error(error); process.exitCode = 1; }).finally(async () => {
  await browser?.close(); server.close();
});
