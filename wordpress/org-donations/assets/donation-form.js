(function () {
  'use strict';
  // Pure helpers, exposed for the JS tests (tests/js) — hoisted function declarations below.
  window.OrgDonUtil = { validId: validId, perMonth: perMonth, normPhone: normPhone, validAmount: validAmount };
  const cfg = window.ORGDON || {};
  const form = document.getElementById('orgdon-form');
  if (!form) return;
  const iframe = document.getElementById('orgdon-iframe');
  const msg = document.getElementById('orgdon-msg');
  const finishBtn = document.getElementById('orgdon-finish');
  const continueBtn = document.getElementById('orgdon-continue');
  const hint = form.querySelector('[data-role="card-hint"]');
  // lpId: the Cardcom card session, created only once the form is valid (server checks it again before creating it).
  let lpId = null, lpExpires = 0, cardSaved = false, submitting = false, opening = false, timer, pendingTries = 0;

  // Phones (portrait or landscape): the Cardcom frame is tall (CSS) and doesn't scroll itself, so only the page scrolls.
  // Set before the frame gets its src: browsers apply `scrolling` when the document loads.
  const phone = window.matchMedia ? window.matchMedia('(max-width: 640px), (max-height: 500px)') : null;
  function frameScrolling() { if (iframe) iframe.setAttribute('scrolling', phone && phone.matches ? 'no' : 'auto'); }
  frameScrolling();
  if (phone && phone.addEventListener) phone.addEventListener('change', frameScrolling);

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
  /** Same rule as the PHP validator: min..max, at most 2 decimals. */
  function validAmount(v, min, max) {
    const s = String(v == null ? '' : v).trim();
    if (!/^\d+(\.\d{1,2})?$/.test(s)) return false;
    const a = parseFloat(s);
    return a >= min && a <= max;
  }

  /** Shows/hides the card step. The iframe is only visible while the form is valid and a session exists. */
  function showCard(on) {
    if (!iframe) return;
    iframe.hidden = !on;
    if (continueBtn) continueBtn.hidden = on;
    if (hint) hint.hidden = on;
  }

  form.addEventListener('change', (e) => {
    if (e.target.name === 'amount_preset') $('amount_other').hidden = e.target.value !== 'other';
    estimate();
    // Edited after the card step was opened: an invalid form must not be able to save a card.
    if (lpId && !cardSaved && !validate()) {
      showCard(false);
      msg.textContent = 'נא לתקן את השדות המסומנים.';
    }
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
    if (!validAmount(amount(), cfg.min, cfg.max)) { setErr('amount', `סכום לא תקין – נא לבחור סכום בין ${cfg.min} ל-${cfg.max} ₪`); ok = false; }
    if (!$('terms').checked) { setErr('terms', 'יש לאשר את תנאי ההוראה'); ok = false; }
    return ok;
  }
  function validId(v) {
    v = v.replace(/\D/g, ''); if (v.length > 9) return false; v = v.padStart(9, '0');
    let s = 0; for (let i = 0; i < 9; i++) { let n = +v[i] * ((i % 2) + 1); s += n > 9 ? n - 9 : n; }
    return s % 10 === 0;
  }

  function fields() {
    return {
      first_name: $('first_name').value, last_name: $('last_name').value, email: $('email').value,
      phone: $('phone').value, tax_id: $('tax_id').value, amount: amount(),
      frequency: form.querySelector('input[name="frequency"]:checked').value, terms: $('terms').checked ? '1' : '',
    };
  }

  /** Never throws: a network error returns {} so the UI is never left waiting. */
  async function post(action, data) {
    const fd = new FormData(); fd.append('action', action); fd.append('nonce', cfg.nonce);
    Object.entries(data).forEach(([k, v]) => fd.append(k, v));
    try {
      const r = await fetch(cfg.ajaxUrl, { method: 'POST', body: fd, credentials: 'same-origin' });
      try { return await r.json(); } catch (e) { return {}; }
    } catch (e) { return {}; }
  }

  function showServerErrors(d) {
    if (d.fields) Object.entries(d.fields).forEach(([k, t]) => setErr(k.replace(/([A-Z])/g, '_$1').toLowerCase(), t));
  }

  /** Opens the card step: validates here, then the server validates again before it creates the Cardcom session. */
  async function openCard() {
    if (opening || cardSaved || !iframe) return;
    msg.textContent = '';
    if (!validate()) { msg.textContent = 'נא לתקן את השדות המסומנים.'; return; }
    if (lpId && Date.now() < lpExpires - 30000) { showCard(true); return; }   // session still fresh: just show it again
    opening = true; if (continueBtn) continueBtn.disabled = true;
    const j = await post('org_donation_lp', fields());
    opening = false; if (continueBtn) continueBtn.disabled = false;
    if (!j.success) {
      const d = j.data || {};
      showServerErrors(d);
      msg.textContent = d.message || 'לא ניתן לטעון כעת את טופס התשלום.';
      return;
    }
    lpId = j.data.lpId; iframe.src = j.data.url;
    lpExpires = j.data.expiresAt ? new Date(j.data.expiresAt).getTime() : Date.now() + 20 * 60000;
    showCard(true); schedule();
  }
  if (continueBtn) continueBtn.addEventListener('click', openCard);

  /** The LowProfile page expires: renew it shortly before (only for a still-valid form). */
  function schedule() {
    clearTimeout(timer);
    timer = setTimeout(() => {
      if (cardSaved) return;
      lpExpires = 0;
      if (!validate()) { showCard(false); return; }
      openCard();
    }, Math.max(lpExpires - Date.now() - 30000, 5000));
  }

  async function submit() {
    if (submitting) return;
    if (!validate()) { msg.textContent = 'נא להשלים את פרטי הטופס וללחוץ "סיום".'; finishBtn.hidden = false; finishBtn.disabled = !cardSaved; return; }
    submitting = true; finishBtn.disabled = true; msg.textContent = 'שומרים...';
    const j = await post('org_donation_submit', Object.assign(fields(), { lp_id: lpId }));
    submitting = false;
    if (j.success || (j.data && j.data.done)) {
      const thanks = document.createElement('div');
      thanks.className = 'orgdon-thanks'; thanks.setAttribute('role', 'status');
      thanks.textContent = (j.data && j.data.message) || 'תודה!';
      form.replaceChildren(thanks);
      return;
    }
    const d = j.data || {};
    if (d.pending && pendingTries < 5) {                 // the same submission is still being saved: ask again shortly
      pendingTries++; msg.textContent = d.message || 'שומרים...';
      setTimeout(submit, 2000);
      return;
    }
    showServerErrors(d);
    msg.textContent = d.message || 'אירעה שגיאה בשמירה. נסו שוב.';
    finishBtn.hidden = false; finishBtn.disabled = !cardSaved;
  }

  window.addEventListener('message', (ev) => {
    if (ev.origin !== cfg.selfOrigin || !iframe || ev.source !== iframe.contentWindow) return;
    const m = ev.data || {};
    if (m.type !== 'orgdon-cardcom') return;
    if (m.status === 'ok') {
      // The form is sent automatically after the card is saved; "סיום" appears only if that send fails (retry without the card).
      cardSaved = true; clearTimeout(timer);
      finishBtn.disabled = false;
      submit();
    } else {
      msg.textContent = 'פרטי הכרטיס לא נקלטו. נסו שוב.';
      lpExpires = 0; openCard();
    }
  });
  form.addEventListener('submit', (e) => {
    e.preventDefault();
    if (!cardSaved) { setErr('card', 'נא להזין את פרטי הכרטיס וללחוץ "שמור כרטיס"'); return; }
    submit();
  });
})();
