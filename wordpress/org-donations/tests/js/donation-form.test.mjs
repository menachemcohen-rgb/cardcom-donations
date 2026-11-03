// node --test wordpress/org-donations/tests/js — checks the pure helpers of assets/donation-form.js (estimate, Israeli ID, phone).
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

test('perMonth: ~30.4 charges per month per daily slot', () => {
  assert.equal(perMonth(1, 'TwiceDaily'), 61, 'spec section 1: about 61 ₪ a month at 1 ₪ twice a day');
  assert.equal(perMonth(1, 'OnceDaily'), 30);
  assert.equal(perMonth(3, 'TwiceDaily'), 182);
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
