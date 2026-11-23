// node --test wordpress/org-donations/tests/js/donation-form.test.mjs — checks the pure helpers of assets/donation-form.js (estimate, Israeli ID, phone)
// and assets/donor-portal.js (amount payload).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const src = readFileSync(new URL('../../assets/donation-form.js', import.meta.url), 'utf8');
const window = {};
vm.runInNewContext(src, { window, document: { getElementById: () => null } });
const { validId, perMonth, normPhone } = window.OrgDonUtil;

test('validId: check digit, padding, length', () => {
  assert.equal(validId('123456782'), true);
  assert.equal(validId('18'), true, 'left-padded to 000000018');
  assert.equal(validId('123456789'), false, 'TC05');
  assert.equal(validId('1234567890'), false);
});

test('perMonth: ~30.4 charges per month per included prayer', () => {
  assert.equal(perMonth(1, 1, 'TwiceDaily'), 61, 'spec section 1: about 61 ₪ a month at 1 ₪ Shacharit + Mincha');
  assert.equal(perMonth(1, 9, 'OnceDaily'), 30, 'רק שחרית: Mincha ignored');
  assert.equal(perMonth(9, 2, 'MinchaOnly'), 61, 'רק מנחה: Shacharit ignored');
  assert.equal(perMonth(3, 5, 'TwiceDaily'), 243);
});

test('perWeek and prayers: 7 charges a week per prayer', () => {
  const { perWeek, prayers } = window.OrgDonUtil;
  assert.equal(perWeek('TwiceDaily'), 14);
  assert.equal(perWeek('OnceDaily'), 7);
  assert.equal(perWeek('MinchaOnly'), 7);
  assert.deepEqual({ ...prayers('MinchaOnly') }, { shacharit: false, mincha: true });
  assert.deepEqual({ ...prayers('OnceDaily') }, { shacharit: true, mincha: false });
});

test('normPhone: same rules as PHP and Salesforce', () => {
  for (const p of ['0521234567', '052-123-4567', '+972 52 123 4567', '00972521234567', '521234567']) assert.equal(normPhone(p), '0521234567', p);
  assert.equal(normPhone('03-1234567'), '031234567');
  assert.equal(normPhone('+1 (470) 228-0495'), '+14702280495');
  assert.equal(normPhone('0044 7911 123456'), '+447911123456');
  assert.equal(normPhone('14702280495'), '+14702280495');
  assert.equal(normPhone('12345'), null);
  assert.equal(normPhone('+1234567890123456'), null);
  assert.equal(normPhone(''), null);
});

test('validAmount: 1–50, at most 2 decimals (checked before the card step)', () => {
  const { validAmount } = window.OrgDonUtil;
  for (const ok of ['1', '50', '3.5', '49.99']) assert.equal(validAmount(ok, 1, 50), true, ok);
  for (const bad of ['0', '51', '0.99', '3.333', '', 'abc', '-1']) assert.equal(validAmount(bad, 1, 50), false, bad);
});

const portalSrc = readFileSync(new URL('../../assets/donor-portal.js', import.meta.url), 'utf8');
const pwin = {};
vm.runInNewContext(portalSrc, { window: pwin, document: { getElementById: () => null } });

test('portal amountPayload: only the prayers the pledge charges', () => {
  const { amountPayload } = pwin.OrgDonPortalUtil;
  assert.deepEqual({ ...amountPayload('TwiceDaily', false, '3', '5') }, { shacharitAmount: '3', minchaAmount: '5' });
  assert.deepEqual({ ...amountPayload('TwiceDaily', true, '4', undefined) }, { shacharitAmount: '4', minchaAmount: '4' }, 'אותו סכום');
  assert.deepEqual({ ...amountPayload('OnceDaily', false, '2', '9') }, { shacharitAmount: '2' });
  assert.deepEqual({ ...amountPayload('MinchaOnly', true, undefined, '6.5') }, { minchaAmount: '6.5' });
});

test('portal: no stop-charges code left', () => {
  assert.ok(!/stop/i.test(portalSrc.replace(/stopPropagation/g, '')), 'donors stop only by phone');
});

test('amountError: above the maximum has its own message (ATA-6)', () => {
  const { amountError } = window.OrgDonUtil;
  assert.equal(amountError('26', 1, 25), 'הסכום המקסימלי הוא 25 ₪ ליום');
  assert.equal(amountError('0.5', 1, 25), 'סכום לא תקין – נא לבחור סכום בין 1 ל-25 ₪');
  assert.equal(amountError('abc', 1, 25), 'סכום לא תקין – נא לבחור סכום בין 1 ל-25 ₪');
});

test('normTaxId: same normalization as the server, so an unchanged ID never reopens the card page', () => {
  const { normTaxId } = window.OrgDonUtil;
  assert.equal(normTaxId('18'), '000000018');
  assert.equal(normTaxId(' 123-456-782 '), '123456782');
  assert.equal(normTaxId(''), '');
  assert.equal(normTaxId(undefined), '');
});

// --- Form behaviour with a minimal fake DOM (items 6 and 7): ID changed after the card page opened ---
function fakeForm() {
  const listeners = {};
  const el = (props = {}) => {
    const l = {};
    return Object.assign({ value: '', checked: false, hidden: false, disabled: false, textContent: '',
      addEventListener: (t, f) => { (l[t] = l[t] || []).push(f); }, fire: (t) => (l[t] || []).forEach((f) => f({ target: el })),
      setAttribute() {}, scrollIntoView() {}, closest: () => null }, props);
  };
  const inputs = {
    first_name: el({ value: 'ישראל' }), last_name: el({ value: 'ישראלי' }), email: el({ value: 'a@example.com' }),
    phone: el({ value: '0521234567' }), tax_id: el({ value: '123456782' }), terms: el({ checked: true }), same_amount: el(),
  };
  const taxListeners = [];
  inputs.tax_id.addEventListener = (t, f) => { if (t === 'input') taxListeners.push(f); };
  const freq = el({ value: 'OnceDaily' }), preset = el({ value: '3' });
  const form = {
    elements: inputs,
    querySelector: (q) => (q.includes('frequency') ? freq : q.includes('shacharit_preset') ? preset : q.includes('mincha_preset') ? null : el()),
    querySelectorAll: () => [],
    addEventListener: (t, f) => { listeners[t] = f; },
  };
  const nodes = { 'orgdon-form': form, 'orgdon-iframe': el({ src: '', contentWindow: {} }), 'orgdon-msg': el(),
    'orgdon-finish': el(), 'orgdon-continue': el() };
  return { form, inputs, nodes, typeTax: (v) => { inputs.tax_id.value = v; taxListeners.forEach((f) => f()); } };
}

async function runForm(t) {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  const dom = fakeForm();
  const posts = [];
  let lpN = 0;
  const win = { ORGDON: { ajaxUrl: '/ajax', nonce: 'n', min: 1, max: 25, selfOrigin: 'https://www.example.org.il' },
    addEventListener: (t2, f) => { if (t2 === 'message') win.onMsg = f; }, matchMedia: () => ({ matches: false }) };
  win.parent = win;
  class FD { constructor() { this.m = {}; } append(k, v) { this.m[k] = v; } }
  const fetch = async (url, o) => {
    posts.push(o.body.m);
    if (o.body.m.action === 'org_donation_lp') { lpN++; return { json: async () => ({ success: true, data: { lpId: 'lp-' + lpN, url: 'https://cardcom/' + lpN, expiresAt: new Date(Date.now() + 20 * 60000).toISOString() } }) }; }
    return { json: async () => win.submitReply };
  };
  vm.runInNewContext(src, { window: win, document: { getElementById: (id) => dom.nodes[id] || null, querySelector: () => null },
    FormData: FD, fetch, Event: class {}, Date, setTimeout, clearTimeout, console });
  const flush = async () => { for (let i = 0; i < 30; i++) await Promise.resolve(); };
  const lpPosts = () => posts.filter((p) => p.action === 'org_donation_lp');
  // open the card page with the ID 123456782
  dom.nodes['orgdon-continue'].fire('click');
  await flush();
  return { dom, win, posts, lpPosts, flush };
}

test('ID changed after the card page opened: one new card page after ~1 s, with a short notice', async (t) => {
  const { dom, lpPosts, flush } = await runForm(t);
  assert.equal(lpPosts().length, 1);
  assert.equal(lpPosts()[0].tax_id, '123456782');
  dom.typeTax('1'); dom.typeTax('18');                 // typing: debounced
  t.mock.timers.tick(500);
  assert.equal(lpPosts().length, 1, 'nothing before the debounce ends');
  dom.typeTax('000000018');
  t.mock.timers.tick(999);
  assert.equal(lpPosts().length, 1);
  t.mock.timers.tick(1);
  assert.equal(dom.nodes['orgdon-msg'].textContent, 'מעדכנים את דף התשלום…');
  await flush();
  assert.equal(lpPosts().length, 2, 'new card page through ajax_lp');
  assert.equal(lpPosts()[1].tax_id, '000000018');
  assert.equal(dom.nodes['orgdon-iframe'].src, 'https://cardcom/2');
  assert.equal(dom.nodes['orgdon-msg'].textContent, '', 'notice cleared once loaded');
});

test('ID changed to an invalid value, or back to the same ID: no new card page', async (t) => {
  const { dom, lpPosts, flush } = await runForm(t);
  dom.typeTax('123456789');                            // bad check digit
  t.mock.timers.tick(1500); await flush();
  dom.typeTax('0123456782');                           // same ID once normalized
  t.mock.timers.tick(1500); await flush();
  assert.equal(lpPosts().length, 1);
  dom.typeTax('');                                     // cleared: Cardcom must show its own ID field again
  t.mock.timers.tick(1000); await flush();
  assert.equal(lpPosts().length, 2);
  assert.equal(lpPosts()[1].tax_id, '');
});

test('the Israeli ID is optional on the form', () => {
  assert.doesNotMatch(src, /נא להזין תעודת זהות/);
  assert.match(src, /if \(id && !validId\(id\)\) \{ setErr\('tax_id', 'מספר תעודת הזהות אינו תקין'\)/);
  const tpl = readFileSync(new URL('../../templates/form.php', import.meta.url), 'utf8');
  assert.match(tpl, /<label for="od-id">תעודת זהות<\/label>/);
  assert.doesNotMatch(tpl, /name="tax_id"[^>]*required/);
  assert.match(tpl, /קראתי ואני מסכים\/ה ל/);
  assert.match(tpl, /לא יתבצע חיוב עכשיו\. החיוב יתבצע לפי הסכום והתדירות שבחרת\./);
});

test('server says the ID no longer matches the card page: a new card page and "נא לאשר שוב את פרטי הכרטיס"', async (t) => {
  const { dom, win, posts, lpPosts, flush } = await runForm(t);
  win.submitReply = { success: false, data: { message: 'נא לאשר שוב את פרטי הכרטיס', renewCard: true, fields: { card: 'נא לאשר שוב את פרטי הכרטיס' } } };
  win.onMsg({ origin: 'https://www.example.org.il', source: dom.nodes['orgdon-iframe'].contentWindow, data: { type: 'orgdon-cardcom', status: 'ok' } });
  await flush();
  assert.equal(posts.filter((p) => p.action === 'org_donation_submit').length, 1);
  assert.equal(lpPosts().length, 2, 'new card page opened');
  assert.equal(dom.nodes['orgdon-iframe'].src, 'https://cardcom/2');
  assert.equal(dom.nodes['orgdon-msg'].textContent, 'נא לאשר שוב את פרטי הכרטיס');
});

test('the monthly estimate is not shown on the form', () => {
  const tpl = readFileSync(new URL('../../templates/form.php', import.meta.url), 'utf8');
  assert.ok(!tpl.includes('orgdon-estimate'), 'no estimate element in the template');
  assert.match(src, /if \(!el\) return;/, 'estimate() is a no-op without the element');
});
