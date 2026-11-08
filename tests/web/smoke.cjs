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
  assert.equal(await page.title(), 'LunkAlarm');
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
  const sidebarToggle = page.locator('#alarmsToggle');
  assert.equal(await sidebarToggle.getAttribute('aria-expanded'), 'false');
  await page.setViewportSize({ width: 1440, height: 900 });
  const hourField = page.locator('#alarmHour'), minuteField = page.locator('#alarmMinute');
  assert(await page.locator('#customTimePicker').isVisible());
  assert(await page.locator('#timeInput').isHidden());
  for (const [hour, period, expected] of [['04', 'AM', 4], ['04', 'PM', 16], ['12', 'AM', 0], ['12', 'PM', 12]]) {
    await hourField.fill(hour); await minuteField.fill('00');
    await page.locator('#time' + period).click(); await page.locator('#setBtn').click();
    assert.equal(await page.evaluate(() => new Date(JSON.parse(localStorage.getItem('wake.alarms'))[0].targetMs).getHours()), expected);
    await sidebarToggle.click(); await page.locator('.delete-btn').first().click(); await sidebarToggle.click();
  }
  await hourField.fill('13'); await page.locator('#setBtn').click();
  assert.equal(await page.locator('.alarm-item').count(), 0);
  assert.match(await page.locator('#formMsg').innerText(), /01–12/);
  await hourField.fill('11'); await minuteField.fill('59'); await page.locator('#timeAM').click();
  await page.getByRole('button', { name: 'Increase minute', exact: true }).click();
  assert.equal(await page.locator('#timeInput').inputValue(), '12:00');
  assert.equal(await page.locator('#timePM').getAttribute('aria-pressed'), 'true');
  await hourField.fill('12'); await minuteField.fill('00'); await page.locator('#timeAM').click();
  await page.getByRole('button', { name: 'Decrease minute', exact: true }).click();
  assert.equal(await page.locator('#timeInput').inputValue(), '23:59');
  await page.locator('#formatBtn').click();
  assert.equal(await hourField.inputValue(), '23'); assert(await page.locator('#timePeriod').isHidden());
  await hourField.focus();
  assert.equal(await hourField.evaluate(el => getComputedStyle(el).outlineStyle), 'none');
  assert.notEqual(await hourField.evaluate(el => getComputedStyle(el.closest('.time-stepper')).borderTopColor), 'rgba(0, 0, 0, 0)');
  await page.keyboard.press('ArrowUp');
  assert.equal(await page.locator('#timeInput').inputValue(), '00:59');
  await hourField.fill('24'); await minuteField.fill('60'); await page.locator('#setBtn').click();
  assert.equal(await page.locator('.alarm-item').count(), 0);
  assert.match(await page.locator('#formMsg').innerText(), /00–23/);
  await hourField.fill('23'); await minuteField.fill('59');
  await page.getByRole('button', { name: 'Increase minute', exact: true }).click();
  assert.equal(await page.locator('#timeInput').inputValue(), '00:00');
  await page.locator('#formatBtn').click();
  assert.equal(await hourField.inputValue(), '12');
  assert.equal(await page.locator('#timeAM').getAttribute('aria-pressed'), 'true');
  // Actual mouse-wheel events adjust only the hovered field, one step per notch.
  async function wheelTo(id, delta, expected) {
    await page.locator('#' + id).hover(); await page.mouse.wheel(0, delta);
    await page.waitForFunction(({ id, expected }) => document.getElementById(id).value === expected, { id, expected });
  }
  await hourField.fill('07'); await minuteField.fill('00'); await page.locator('#timeAM').click();
  const scrollBefore = await page.locator('.setup-fields').evaluate(el => el.scrollTop);
  await wheelTo('alarmHour', -100, '08'); await wheelTo('alarmHour', 100, '07');
  assert.equal(await page.locator('.setup-fields').evaluate(el => el.scrollTop), scrollBefore);
  await minuteField.fill('59'); await wheelTo('alarmMinute', -100, '00');
  assert.equal(await page.locator('#timeInput').inputValue(), '08:00');
  await hourField.fill('11'); await minuteField.fill('59'); await page.locator('#timePM').click();
  await wheelTo('alarmMinute', -100, '00');
  assert.equal(await page.locator('#timeInput').inputValue(), '00:00');
  assert.equal(await page.locator('#timeAM').getAttribute('aria-pressed'), 'true');
  const ignoredWheel = await hourField.evaluate(el => {
    const zoom = new WheelEvent('wheel', { deltaY: -100, ctrlKey: true, bubbles: true, cancelable: true });
    const sideways = new WheelEvent('wheel', { deltaX: 100, deltaY: 1, bubbles: true, cancelable: true });
    el.dispatchEvent(zoom); el.dispatchEvent(sideways);
    return !zoom.defaultPrevented && !sideways.defaultPrevented;
  });
  assert(ignoredWheel); assert.equal(await page.locator('#timeInput').inputValue(), '00:00');
  await hourField.fill('07');
  await hourField.evaluate(el => {
    for (let i = 0; i < 3; i++) el.dispatchEvent(new WheelEvent('wheel', { deltaY: -15, bubbles: true, cancelable: true }));
  });
  assert.equal(await hourField.inputValue(), '08');
  await page.locator('#tabTimer').click();
  await page.locator('.presets [data-minutes="30"]').click();
  assert.equal(await page.locator('#minutesInput').inputValue(), '30');
  assert.equal(await page.getByRole('button', { name: '25 min', exact: true }).count(), 0);
  await page.locator('.presets [data-minutes="5"]').click();
  assert.equal(await page.locator('#minutesInput').inputValue(), '05');
  await page.locator('#minutesInput').fill('00'); await page.locator('#secondsInput').fill('59');
  await wheelTo('secondsInput', -100, '00');
  assert.equal(await page.locator('#minutesInput').inputValue(), '01');
  await wheelTo('minutesInput', -100, '02'); await wheelTo('hoursInput', -100, '01');
  for (const id of ['hoursInput', 'minutesInput', 'secondsInput']) await page.locator('#' + id).fill('0');
  await page.locator('#secondsInput').hover(); await page.mouse.wheel(0, 100);
  assert.equal(await page.locator('#secondsInput').inputValue(), '00');
  await page.locator('#hoursInput').fill('99'); await page.locator('#minutesInput').fill('59'); await page.locator('#secondsInput').fill('59');
  await page.locator('#secondsInput').hover(); await page.mouse.wheel(0, -100);
  assert.equal(await page.locator('#hoursInput').inputValue(), '99');
  assert.equal(await page.locator('#secondsInput').inputValue(), '59');
  await wheelTo('hoursInput', 100, '98');
  await page.locator('#minutesInput').focus(); await page.keyboard.press('ArrowUp');
  assert.equal(await page.locator('#hoursInput').inputValue(), '99');
  assert.equal(await page.locator('#minutesInput').inputValue(), '00');
  await page.getByRole('button', { name: 'Decrease countdown seconds', exact: true }).click();
  assert.equal(await page.locator('#secondsInput').inputValue(), '58');
  await page.locator('#hoursInput').fill('0'); await page.locator('#minutesInput').fill('0'); await page.locator('#secondsInput').fill('5');
  await wheelTo('secondsInput', -100, '06'); await wheelTo('secondsInput', -100, '07');
  await page.locator('#setBtn').click();
  const durationLeft = await page.evaluate(() => JSON.parse(localStorage.getItem('wake.alarms'))[0].targetMs - Date.now());
  assert(durationLeft > 5000 && durationLeft <= 7100);
  await sidebarToggle.click(); await page.locator('.delete-btn').first().click(); await sidebarToggle.click();
  await page.locator('#tabTime').click();
  console.log('PASS real wheel input, fine trackpad deltas, zoom/horizontal pass-through, countdown carry/limits, and scheduled wheel-selected duration');
  await page.setViewportSize({ width: 375, height: 812 });
  await page.locator('#timeInput').waitFor({ state: 'visible' });
  assert(await page.locator('#customTimePicker').isHidden());
  await page.locator('#tabTimer').click();
  assert(await page.locator('.duration-step').first().isHidden());
  assert(await page.locator('#mobileDurationPicker').isVisible());
  await page.locator('#durationEntryToggle').click();
  assert.equal(await page.locator('.timer-row').evaluate(el => getComputedStyle(el).display), 'grid');
  assert(await page.locator('#secondsInput').evaluate(el => {
    const event = new WheelEvent('wheel', { deltaY: -100, bubbles: true, cancelable: true });
    el.dispatchEvent(event); return !event.defaultPrevented;
  }));
  await page.locator('#tabTime').click();
  await page.locator('#timeInput').fill('21:45');
  await page.setViewportSize({ width: 1440, height: 900 });
  assert.equal(await hourField.inputValue(), '09'); assert.equal(await minuteField.inputValue(), '45');
  assert.equal(await page.locator('#timePM').getAttribute('aria-pressed'), 'true');
  await hourField.fill('07'); await minuteField.fill('00'); await page.locator('#timeAM').click();
  console.log('PASS typed desktop time, AM/PM, noon/midnight scheduling, steppers, rollover, 24-hour mode, validation and phone sync');
  // Desktop layouts must fit even with a five-character clock and expanded timer/tests.
  await page.locator('#formatBtn').click();
  for (const viewport of [{ width: 1440, height: 900 }, { width: 1366, height: 768 }, { width: 1280, height: 720 }, { width: 1024, height: 600 }]) {
    await page.setViewportSize(viewport);
    if (await sidebarToggle.getAttribute('aria-expanded') === 'true') await sidebarToggle.click();
    const expandedFormWidth = (await page.locator('#setupCard').boundingBox()).width;
    assert((await page.locator('#alarmsCard').boundingBox()).width <= 60);
    assert(await page.locator('#alarmsPanel').isHidden());
    if (viewport.width === 1366) await page.screenshot({ path: path.join(output, 'desktop-sidebar-closed.png') });
    await sidebarToggle.click();
    assert.equal(await sidebarToggle.getAttribute('aria-expanded'), 'true');
    assert(await page.locator('#alarmsPanel').isVisible());
    assert((await page.locator('#setupCard').boundingBox()).width < expandedFormWidth - 100);
    await page.locator('#typingToggle').check(); await page.locator('#mathToggle').check();
    for (const mode of ['#tabTime', '#tabTimer']) {
      await page.locator(mode).click();
      const desktop = await page.evaluate(() => {
        const rect = selector => document.querySelector(selector).getBoundingClientRect();
        const clock = rect('.clock-card'), setup = rect('#setupCard'), alarms = rect('#alarmsCard'), add = rect('#setBtn');
        return {
          grid: getComputedStyle(document.querySelector('.app')).display,
          clockFits: rect('.clock').width <= clock.width + 1,
          pageFits: document.documentElement.scrollHeight <= innerHeight && document.documentElement.scrollWidth <= innerWidth,
          ordered: clock.right <= setup.left && setup.right <= alarms.left,
          cardsFit: setup.top >= 0 && setup.bottom <= innerHeight && alarms.bottom <= innerHeight,
          addVisible: add.top >= setup.top && add.bottom <= setup.bottom,
          clockFont: parseFloat(getComputedStyle(document.querySelector('#clockHM')).fontSize),
          split: getComputedStyle(document.querySelector('.sound-tests')).display === 'grid',
          settingsHeight: document.querySelector('.setup-fields').clientHeight,
          settingsContent: document.querySelector('.setup-fields').scrollHeight
        };
      });
      assert.equal(desktop.grid, 'grid');
      assert(desktop.pageFits && desktop.ordered && desktop.cardsFit && desktop.addVisible && desktop.clockFits, JSON.stringify({ viewport, mode, desktop }));
      if (viewport.width >= 1366) {
        assert(desktop.clockFont > 112);
        if (desktop.split) assert(desktop.settingsContent <= desktop.settingsHeight + 2, JSON.stringify({ viewport, mode, desktop }));
      }
    }
    await picker.click();
    const popup = await menu.boundingBox();
    assert(popup.y >= 0 && popup.y + popup.height <= viewport.height + 1);
    await page.keyboard.press('Escape');
    if (viewport.width === 1024) {
      const savedHours = await page.locator('#hoursInput').inputValue();
      await page.locator('.setup-fields').evaluate(el => { el.scrollTop = 0; });
      await page.locator('.tabs').hover(); await page.mouse.wheel(0, 160);
      await page.waitForFunction(() => document.querySelector('.setup-fields').scrollTop > 0);
      assert.equal(await page.locator('#hoursInput').inputValue(), savedHours);
    }
    if (viewport.width === 1366) await page.screenshot({ path: path.join(output, 'laptop-workspace.png') });
  }
  await page.setViewportSize({ width: 1880, height: 900 });
  if (await sidebarToggle.getAttribute('aria-expanded') === 'true') await sidebarToggle.click();
  await page.locator('#tabTime').click(); await page.locator('#formatBtn').click();
  await hourField.fill('04'); await minuteField.fill('00'); await page.locator('#timeAM').click();
  assert.equal(await page.locator('.sound-tests').evaluate(el => getComputedStyle(el).display), 'grid');
  const linkRows = await page.locator('.ringtone-links').evaluate(el => {
    const upload = el.querySelector('#uploadBtn').getBoundingClientRect(), online = el.querySelector('#onlineBtn').getBoundingClientRect();
    return online.top > upload.bottom;
  });
  assert(linkRows);
  await page.locator('#setupCard').screenshot({ path: path.join(output, 'approved-design-implemented.png') });
  await page.screenshot({ path: path.join(output, 'approved-desktop.png') });
  await page.locator('#tabTimer').click();
  await page.locator('#setupCard').screenshot({ path: path.join(output, 'countdown-wheel-picker.png') });
  await page.locator('#tabTime').click();
  await page.locator('#formatBtn').click(); await sidebarToggle.click();
  await page.locator('#typingToggle').uncheck(); await page.locator('#mathToggle').uncheck();
  await page.locator('#tabTime').click();
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.evaluate(() => localStorage.setItem('wake.alarms', JSON.stringify(Array.from({ length: 30 }, (_, i) => ({
    id: 'desktop-' + i, targetMs: Date.now() + (i + 1) * 3600000, ringtoneId: 'classic-beep', typing: false, mathCount: 0, ringing: false
  })))));
  await page.reload();
  assert.equal(await page.locator('.alarm-item').count(), 30);
  assert.equal(await sidebarToggle.getAttribute('aria-expanded'), 'true');
  assert.equal(await page.locator('#alarmsCount').innerText(), '30');
  await page.locator('.delete-btn').first().click();
  assert.equal(await page.locator('#alarmsCount').innerText(), '29');
  assert(await page.evaluate(() => {
    const list = document.querySelector('#alarmList');
    return list.scrollHeight > list.clientHeight && document.documentElement.scrollHeight <= innerHeight;
  }));
  await page.locator('#alarmList').evaluate(el => { el.scrollTop = el.scrollHeight; });
  assert(await page.locator('#alarmList').evaluate(el => el.scrollTop > 0));
  await page.locator('#alarmList').evaluate(el => { el.scrollTop = 0; });
  await page.screenshot({ path: path.join(output, 'desktop-workspace.png') });
  await page.locator('.delete-btn').first().focus(); await page.keyboard.press('Escape');
  assert.equal(await sidebarToggle.getAttribute('aria-expanded'), 'false');
  assert(await sidebarToggle.evaluate(el => el === document.activeElement));
  await page.reload();
  assert.equal(await sidebarToggle.getAttribute('aria-expanded'), 'false');
  assert.equal(await page.locator('#alarmsCount').innerText(), '29');
  await page.setViewportSize({ width: 375, height: 812 });
  assert(await sidebarToggle.isHidden());
  assert.equal(await page.locator('#alarmsPanel').evaluate(el => el.inert), false);
  assert(await page.locator('.alarm-item').first().isVisible());
  await page.setViewportSize({ width: 1440, height: 900 });
  assert.equal(await sidebarToggle.getAttribute('aria-expanded'), 'false');
  await sidebarToggle.click();
  assert.equal(await page.locator('.alarm-item').count(), 29);
  await page.evaluate(() => localStorage.setItem('wake.alarms', '[]')); await page.reload();
  await page.locator('#formatBtn').click();
  const touch = await browser.newPage({ viewport: { width: 1024, height: 768 }, hasTouch: true, isMobile: true });
  await touch.route('https://**/*', route => route.abort()); await touch.goto(url);
  assert.equal(await touch.locator('.app').evaluate(el => getComputedStyle(el).display), 'flex');
  assert(await touch.evaluate(() => document.documentElement.scrollHeight > innerHeight));
  await touch.close();
  console.log('PASS expanding desktop form, collapsible alarms/count, saved preference, keyboard focus, panel scrolling and phone layout');

  // Keep the approved form layout; the restored three-button toolbar can wrap above the clock.
  for (const width of [520, 462, 375, 320]) {
    await page.setViewportSize({ width, height: 900 });
    await page.locator('#timeInput').waitFor({ state: 'visible' });
    const layout = await page.evaluate(() => {
      const box = id => document.getElementById(id).getBoundingClientRect();
      const sound = box('enableSoundBtn'), theme = box('themeBtn');
      return {
        overflow: document.documentElement.scrollWidth > innerWidth,
        headerOffset: Math.abs(sound.y + sound.height / 2 - theme.y - theme.height / 2),
        formTop: box('setupCard').top + scrollY,
        pickerHeight: box('ringtonePicker').height,
        timeAlign: getComputedStyle(document.getElementById('timeInput')).textAlign,
        timeFits: box('timeInput').right <= box('setupCard').right - 15 && box('timeInput').left >= box('setupCard').left + 15
      };
    });
    assert.equal(layout.overflow, false);
    assert(layout.headerOffset < 2, `Toolbar buttons misaligned at ${width}px`);
    assert(layout.formTop < 355, `Form pushed down at ${width}px`);
    assert.equal(layout.pickerHeight, 36);
    assert.equal(layout.timeAlign, 'left');
    assert(layout.timeFits, `Native time input overflow at ${width}px`);
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
  if (await page.locator('#nativeDurationInputs').isHidden()) await page.locator('#durationEntryToggle').click();
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
  assert.equal(await page.title(), '⏰ LunkAlarm');
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
  assert.equal(await page.title(), 'LunkAlarm');
  console.log('PASS timer rings, typing then math enforce correct answers, dismiss removes alarm, and tab branding stays correct');
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
  await page.locator('#tabTimer').click();
  if (await page.locator('#nativeDurationInputs').isHidden()) await page.locator('#durationEntryToggle').click();
  await page.locator('#minutesInput').fill('1');
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
  const mobile = await browser.newPage({ viewport: { width: 393, height: 852 }, hasTouch: true, isMobile: true, deviceScaleFactor: 2 });
  mobile.on('pageerror', error => errors.push(error.message));
  await mobile.route('https://**/*', route => route.abort()); await mobile.goto(url);
  for (const width of [320, 375, 393, 430]) {
    await mobile.setViewportSize({ width, height: 852 });
    await mobile.locator('#timeInput').fill('23:59');
    assert(await mobile.locator('#timeInput').evaluate(el => {
      const box = el.getBoundingClientRect(), card = document.querySelector('#setupCard').getBoundingClientRect();
      return el.type === 'time' && box.right <= card.right - 15 && box.left >= card.left + 15 && document.documentElement.scrollWidth <= innerWidth;
    }));
  }
  await mobile.setViewportSize({ width: 393, height: 852 });
  await mobile.locator('#tabTimer').tap();
  await mobile.locator('#mobileDurationPicker').waitFor({ state: 'visible' });
  assert(await mobile.locator('#nativeDurationInputs').isHidden());
  await mobile.waitForFunction(() => document.querySelector('#durationWheel-minutes').scrollTop === 30 * 44);
  // A real Chromium touch gesture must scroll the wheel while the surrounding page stays put.
  const minuteWheel = mobile.locator('#durationWheel-minutes');
  await minuteWheel.scrollIntoViewIfNeeded();
  const wheelBox = await minuteWheel.boundingBox();
  const pageScroll = await mobile.evaluate(() => scrollY);
  const cdp = await mobile.context().newCDPSession(mobile);
  const x = wheelBox.x + wheelBox.width / 2, y = wheelBox.y + 88;
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x, y, id: 1 }] });
  for (let step = 1; step <= 8; step++) {
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x, y: y - step * 8, id: 1 }] });
    await mobile.evaluate(() => new Promise(requestAnimationFrame));
  }
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
  await mobile.waitForFunction(() => document.querySelector('#minutesInput').value !== '30');
  assert(Math.abs(await mobile.evaluate(() => scrollY) - pageScroll) < 3);
  await cdp.detach();
  // Native scroll snapping and tapping both update the canonical duration fields.
  await mobile.locator('.presets [data-minutes="5"]').tap();
  await mobile.waitForFunction(() => document.querySelector('#durationWheel-minutes').scrollTop === 5 * 44);
  assert.equal(await mobile.locator('#durationWheel-minutes').getByRole('option', { selected: true }).getAttribute('data-value'), '5');
  await mobile.locator('#durationWheel-hours').evaluate(el => { el.scrollTop = 2 * 44; });
  await mobile.waitForFunction(() => document.querySelector('#hoursInput').value === '2');
  await mobile.locator('#durationWheel-seconds').evaluate(el => { el.scrollTop = 45 * 44; });
  await mobile.waitForFunction(() => document.querySelector('#secondsInput').value === '45');
  await minuteWheel.getByRole('option', { name: '6 minutes', exact: true }).tap();
  await mobile.waitForFunction(() => document.querySelector('#minutesInput').value === '6');
  await minuteWheel.focus(); await mobile.keyboard.press('Home');
  assert.equal(await mobile.locator('#minutesInput').inputValue(), '0');
  await mobile.keyboard.press('End'); assert.equal(await mobile.locator('#minutesInput').inputValue(), '59');
  for (const unit of ['hours', 'minutes']) await mobile.locator('#durationWheel-' + unit).evaluate(el => { el.scrollTop = 0; });
  await mobile.locator('#durationWheel-seconds').evaluate(el => { el.scrollTop = 10 * 44; });
  await mobile.waitForFunction(() => ['hoursInput', 'minutesInput', 'secondsInput'].map(id => document.getElementById(id).value).join(':') === '0:0:10');
  await mobile.locator('#setBtn').tap();
  const mobileDuration = await mobile.evaluate(() => JSON.parse(localStorage.getItem('wake.alarms'))[0].targetMs - Date.now());
  assert(mobileDuration > 8000 && mobileDuration <= 10100);
  await mobile.locator('.delete-btn').first().tap();
  await mobile.locator('#durationEntryToggle').tap();
  assert(await mobile.locator('#nativeDurationInputs').isVisible());
  await mobile.locator('#hoursInput').fill('1'); await mobile.locator('#minutesInput').fill('2'); await mobile.locator('#secondsInput').fill('3');
  await mobile.locator('#durationEntryToggle').tap();
  await mobile.waitForFunction(() => document.querySelector('#durationWheel-hours').scrollTop === 44 && document.querySelector('#durationWheel-minutes').scrollTop === 88 && document.querySelector('#durationWheel-seconds').scrollTop === 132);
  await mobile.screenshot({ path: path.join(output, 'mobile-duration-wheels.png'), fullPage: true });
  await mobile.locator('#tabTime').tap();
  await mobile.locator('#setupCard').screenshot({ path: path.join(output, 'mobile-native-time-fit.png') });
  await mobile.close();
  console.log('PASS mobile native time stays inside card; countdown touch swipes, snapping, tap/keyboard selection, presets, manual entry, and scheduled duration');
  assert.deepEqual(errors, []);
  console.log('PASS no uncaught browser errors; static website checks complete');
})().catch(error => { console.error(error); process.exitCode = 1; }).finally(async () => {
  await browser?.close(); server.close();
});
