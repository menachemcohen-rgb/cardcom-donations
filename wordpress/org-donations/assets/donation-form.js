(function () {
  'use strict';
  // Pure helpers, exposed for the JS tests (tests/js) — hoisted function declarations below.
  window.OrgDonUtil = { validId: validId, perMonth: perMonth, normPhone: normPhone };
  const cfg = window.ORGDON || {};
  const form = document.getElementById('orgdon-form');
  if (!form) return;
  const iframe = document.getElementById('orgdon-iframe');
  const msg = document.getElementById('orgdon-msg');
  const finishBtn = document.getElementById('orgdon-finish');
  let lpId = cfg.lpId, cardSaved = false, submitting = false, timer;

  const $ = (n) => form.elements[n];
  const setErr = (k, t) => { const el = form.querySelector(`.orgdon-err[data-for="${k}"]`); if (el) el.textContent = t || ''; };
  const clearErrs = () => form.querySelectorAll('.orgdon-err').forEach((e) => (e.textContent = ''));

  function amount() {
    const p = form.querySelector('input[name="amount_preset"]:checked');
    return p && p.value === 'other' ? $('amount_other').value : (p ? p.value : '');
  }
  function estimate() {
    const a = parseFloat(amount()); const f = form.querySelector('input[name="frequency"]:checked')?.value;
    const el = form.querySelector('.orgdon-estimate');
    if (!a || !f) { el.textContent = ''; return; }
    el.textContent = `הערכה: כ-${perMonth(a, f)} ₪ בחודש (${f === 'TwiceDaily' ? '14' : '7'} חיובים בשבוע).`;
  }
  /** Every calendar day is charged (rest days in advance), so a month ≈ 30.4 charges per daily slot. */
  function perMonth(a, f) { return Math.round(a * (f === 'TwiceDaily' ? 2 : 1) * 30.4); }
  /** Same rules as the PHP validator and Salesforce (N61). */
  function normPhone(v) {
    let d = String(v || '').replace(/\D/g, '');
    if (d.startsWith('00972')) d = d.slice(5); else if (d.startsWith('972')) d = d.slice(3);
    if (d && d[0] !== '0') d = '0' + d;
    return /^05\d{8}$/.test(d) ? d : null;
  }
  form.addEventListener('change', (e) => {
    if (e.target.name === 'amount_preset') $('amount_other').hidden = e.target.value !== 'other';
    estimate();
  });
  estimate();

  function validate() {
    clearErrs(); let ok = true;
    const req = (n, t, test) => { if (!test($(n).value.trim())) { setErr(n, t); ok = false; } };
    req('first_name', 'נא להזין שם פרטי', (v) => v.length > 0);
    req('last_name', 'נא להזין שם משפחה', (v) => v.length > 0);
    req('email', 'נא להזין כתובת אימייל תקינה', (v) => /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(v));
    req('phone', 'נא להזין מספר נייד ישראלי תקין', (v) => normPhone(v) !== null);
    const id = $('tax_id').value.trim();
    if (id && !validId(id)) { setErr('tax_id', 'מספר תעודת הזהות אינו תקין'); ok = false; }
    const a = parseFloat(amount());
    if (!(a >= cfg.min && a <= cfg.max) || !/^\d+(\.\d{1,2})?$/.test(amount())) { setErr('amount', `סכום לא תקין – נא לבחור סכום בין ${cfg.min} ל-${cfg.max} ₪`); ok = false; }
    if (!$('terms').checked) { setErr('terms', 'יש לאשר את תנאי ההוראה'); ok = false; }
    return ok;
  }
  function validId(v) {
    v = v.replace(/\D/g, ''); if (v.length > 9) return false; v = v.padStart(9, '0');
    let s = 0; for (let i = 0; i < 9; i++) { let n = +v[i] * ((i % 2) + 1); s += n > 9 ? n - 9 : n; }
    return s % 10 === 0;
  }

  async function post(action, data) {
    const fd = new FormData(); fd.append('action', action); fd.append('nonce', cfg.nonce);
    Object.entries(data).forEach(([k, v]) => fd.append(k, v));
    const r = await fetch(cfg.ajaxUrl, { method: 'POST', body: fd, credentials: 'same-origin' });
    let j = {}; try { j = await r.json(); } catch (e) {}
    return j;
  }

  async function refreshIframe() {
    if (cardSaved || !iframe) return;
    const j = await post('org_donation_refresh', {});
    if (j.success) { lpId = j.data.lpId; iframe.src = j.data.url; schedule(j.data.expiresAt); }
    else msg.textContent = (j.data && j.data.message) || 'לא ניתן לטעון כעת את טופס התשלום.';
  }
  function schedule(exp) {
    clearTimeout(timer); if (!exp) return;
    timer = setTimeout(refreshIframe, Math.max(new Date(exp).getTime() - Date.now() - 30000, 5000));
  }
  schedule(cfg.expiresAt);

  async function submit() {
    if (submitting) return;
    if (!validate()) { msg.textContent = 'נא להשלים את פרטי הטופס וללחוץ "סיום".'; finishBtn.hidden = false; return; }
    submitting = true; msg.textContent = 'שומרים...';
    const data = {
      first_name: $('first_name').value, last_name: $('last_name').value, email: $('email').value,
      phone: $('phone').value, tax_id: $('tax_id').value, amount: amount(),
      frequency: form.querySelector('input[name="frequency"]:checked').value, terms: $('terms').checked ? '1' : '', lp_id: lpId,
    };
    const j = await post('org_donation_submit', data);
    submitting = false;
    if (j.success || (j.data && j.data.done)) {
      const thanks = document.createElement('div');
      thanks.className = 'orgdon-thanks'; thanks.setAttribute('role', 'status');
      thanks.textContent = (j.data && j.data.message) || 'תודה!';
      form.replaceChildren(thanks);
      return;
    }
    const d = j.data || {};
    if (d.fields) Object.entries(d.fields).forEach(([k, t]) => setErr(k.replace(/([A-Z])/g, '_$1').toLowerCase(), t));
    msg.textContent = d.message || 'אירעה שגיאה בשמירה. נסו שוב.';
    finishBtn.hidden = false;
  }

  window.addEventListener('message', (ev) => {
    if (ev.origin !== cfg.selfOrigin || !iframe || ev.source !== iframe.contentWindow) return;
    const m = ev.data || {};
    if (m.type !== 'orgdon-cardcom') return;
    if (m.status === 'ok') { cardSaved = true; clearTimeout(timer); submit(); }
    else { msg.textContent = 'פרטי הכרטיס לא נקלטו. נסו שוב.'; refreshIframe(); }
  });
  form.addEventListener('submit', (e) => { e.preventDefault(); if (!cardSaved) { setErr('card', 'נא להזין את פרטי הכרטיס וללחוץ "שמור כרטיס"'); return; } submit(); });
})();
