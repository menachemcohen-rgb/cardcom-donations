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
  assert.equal(normPhone('03-1234567'), null);
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
