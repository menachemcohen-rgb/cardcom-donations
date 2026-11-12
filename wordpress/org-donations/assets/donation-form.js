(function () {
  'use strict';
  // Pure helpers, exposed for the JS tests (tests/js) — hoisted function declarations below.
  window.OrgDonUtil = { validId: validId, perMonth: perMonth, perWeek: perWeek, prayers: prayers, normPhone: normPhone, validAmount: validAmount, amountError: amountError };
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

  const freq = () => (form.querySelector('input[name="frequency"]:checked') || {}).value;
  /** Amount chosen in one prayer's picker ('shacharit' | 'mincha'), as typed. */
  function pickerAmount(prayer) {
    const p = form.querySelector(`input[name="${prayer}_preset"]:checked`);
    return p && p.value === 'other' ? $(prayer + '_other').value : (p ? p.value : '');
  }
  const sameAmount = () => freq() === 'TwiceDaily' && $('same_amount').checked;
  /** Amount per prayer; '' for a prayer the frequency doesn't charge. Mincha = Shacharit when "אותו סכום" is checked. */
  function amounts() {
    const inc = prayers(freq());
    const sh = inc.shacharit ? pickerAmount('shacharit') : '';
    const mi = inc.mincha ? (sameAmount() ? sh : pickerAmount('mincha')) : '';
    return { shacharit: sh, mincha: mi };
  }
  /** Shows the pickers of the prayers the frequency charges; the Mincha picker is hidden while "אותו סכום" is checked. */
  function syncPickers() {
    const inc = prayers(freq());
    const sh = form.querySelector('[data-prayer="shacharit"]'), mi = form.querySelector('[data-prayer="mincha"]');
    const same = form.querySelector('[data-role="same-amount"]');
    if (sh) sh.hidden = !inc.shacharit;
    if (same) same.hidden = freq() !== 'TwiceDaily';
    if (mi) mi.hidden = !inc.mincha || sameAmount();
  }
  function estimate() {
    const a = amounts(); const f = freq();
    const el = form.querySelector('.orgdon-estimate');
    const sh = parseFloat(a.shacharit) || 0, mi = parseFloat(a.mincha) || 0;
    if (!f || (!sh && !mi)) { el.textContent = ''; return; }
    el.textContent = `הערכה: כ-${perMonth(sh, mi, f)} ₪ בחודש (${perWeek(f)} חיובים בשבוע).`;
  }
  /** Which prayers a frequency charges (Salesforce API values). */
  function prayers(f) {
    return { shacharit: f === 'TwiceDaily' || f === 'OnceDaily', mincha: f === 'TwiceDaily' || f === 'MinchaOnly' };
  }
  /** Every calendar day is charged (rest days in advance), so a month ≈ 30.4 charges per prayer. */
  function perMonth(shacharit, mincha, f) {
    const inc = prayers(f);
    return Math.round(((inc.shacharit ? Number(shacharit) || 0 : 0) + (inc.mincha ? Number(mincha) || 0 : 0)) * 30.4);
  }
  /** 7 charges a week per included prayer. */
  function perWeek(f) { const inc = prayers(f); return 7 * ((inc.shacharit ? 1 : 0) + (inc.mincha ? 1 : 0)); }
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

  /** Message for an amount validAmount rejected: above the maximum has its own text (ATA-6), same as the PHP validator. */
  function amountError(v, min, max) {
    const s = String(v == null ? '' : v).trim();
    if (/^\d+(\.\d{1,2})?$/.test(s) && parseFloat(s) > max) return `הסכום המקסימלי הוא ${max} ₪ ליום`;
    return `סכום לא תקין – נא לבחור סכום בין ${min} ל-${max} ₪`;
  }

  const reduceMotion = () => !!(window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches);
  /** Brings the card frame into view when it opens (ATA-6); the browser also scrolls an embedding page. */
  function scrollToCard() {
    const box = iframe && iframe.closest ? iframe.closest('.orgdon-card') || iframe : iframe;
    if (box && box.scrollIntoView) box.scrollIntoView({ behavior: reduceMotion() ? 'auto' : 'smooth', block: 'start' });
  }

  /** Shows/hides the card step. The iframe is only visible while the form is valid and a session exists. */
  function showCard(on) {
    if (!iframe) return;
    iframe.hidden = !on;
    if (continueBtn) continueBtn.hidden = on;
    if (hint) hint.hidden = on;
  }

  const dinersBox = () => $('diners');   // present only when the Diners terminal is enabled (cfg.diners)
  const isDiners = () => !!(dinersBox() && dinersBox().checked);

  form.addEventListener('change', (e) => {
    if (e.target.name === 'diners') {
      // Each terminal has its own card page: drop the open session, the donor opens the right one with "המשך".
      if (lpId && !cardSaved) {
        clearTimeout(timer); lpId = null; lpExpires = 0;
        if (iframe) iframe.src = 'about:blank';
        showCard(false); msg.textContent = '';
      }
      return;
    }
    const m = /^(shacharit|mincha)_preset$/.exec(e.target.name || '');
    if (m) $(m[1] + '_other').hidden = e.target.value !== 'other';
    syncPickers();
    estimate();
    // Edited after the card step was opened: an invalid form must not be able to save a card.
    if (lpId && !cardSaved && !validate()) {
      showCard(false);
      msg.textContent = 'נא לתקן את השדות המסומנים.';
    }
  });
  syncPickers();
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
    const inc = prayers(freq()); const a = amounts();
    if (!freq()) { setErr('frequency', 'נא לבחור תדירות'); ok = false; }
    ['shacharit', 'mincha'].forEach((p) => {
      if (inc[p] && !validAmount(a[p], cfg.min, cfg.max)) { setErr(p + '_amount', amountError(a[p], cfg.min, cfg.max)); ok = false; }
    });
    if (!$('terms').checked) { setErr('terms', 'יש לאשר את תנאי ההוראה'); ok = false; }
    return ok;
  }
  function validId(v) {
    v = v.replace(/\D/g, ''); if (v.length > 9) return false; v = v.padStart(9, '0');
    let s = 0; for (let i = 0; i < 9; i++) { let n = +v[i] * ((i % 2) + 1); s += n > 9 ? n - 9 : n; }
    return s % 10 === 0;
  }

  function fields() {
    const a = amounts();
    return {
      first_name: $('first_name').value, last_name: $('last_name').value, email: $('email').value,
      phone: $('phone').value, tax_id: $('tax_id').value,
      frequency: freq() || '', shacharit_amount: a.shacharit, mincha_amount: a.mincha, same_amount: sameAmount() ? '1' : '',
      terms: $('terms').checked ? '1' : '', diners: isDiners() ? '1' : '',
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
    if (lpId && Date.now() < lpExpires - 30000) { showCard(true); scrollToCard(); return; }   // session still fresh: just show it again
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
    showCard(true); scrollToCard(); schedule();
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
      const text = (j.data && j.data.message) || 'תודה!';
      const thanks = document.createElement('div');
      thanks.className = 'orgdon-thanks'; thanks.setAttribute('role', 'status');
      thanks.textContent = text;
      form.replaceChildren(thanks);
      notifyParent();
      showSuccessModal(text);
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

  /**
   * Tells an embedding page (Elementor iframe) that the pledge was saved, so it can scroll to the top of our frame:
   * inside an iframe, position:fixed is relative to the frame, not to the donor's screen. No data in the message.
   */
  function notifyParent() {
    if (window.parent === window) return;
    try { window.parent.postMessage({ type: 'orgdon-success' }, cfg.parentOrigin || '*'); } catch (e) { /* ignore */ }
  }

  /** Success message as a modal dialog with a close button (ATA-6); the thank-you text also stays in place of the form. */
  function showSuccessModal(text) {
    const back = document.createElement('div');
    back.className = 'orgdon-modal-back' + (window.parent !== window ? ' orgdon-modal-embedded' : '');
    const box = document.createElement('div');
    box.className = 'orgdon-modal'; box.setAttribute('role', 'dialog'); box.setAttribute('aria-modal', 'true');
    box.setAttribute('aria-labelledby', 'orgdon-modal-title'); box.dir = 'rtl'; box.lang = 'he';
    const h = document.createElement('h2'); h.id = 'orgdon-modal-title'; h.className = 'orgdon-modal-title'; h.textContent = 'תודה רבה!';
    const p = document.createElement('p'); p.className = 'orgdon-modal-text'; p.textContent = text;
    const close = document.createElement('button'); close.type = 'button'; close.className = 'orgdon-btn orgdon-modal-close'; close.textContent = 'סגירה';
    box.append(h, p, close); back.append(box);
    const prevFocus = document.activeElement;
    const done = () => { document.removeEventListener('keydown', onKey); back.remove(); if (prevFocus && prevFocus.focus && document.contains(prevFocus)) prevFocus.focus(); };
    const onKey = (e) => { if (e.key === 'Escape') done(); else if (e.key === 'Tab') { e.preventDefault(); close.focus(); } };
    close.addEventListener('click', done);
    back.addEventListener('click', (e) => { if (e.target === back) done(); });
    document.addEventListener('keydown', onKey);
    (document.querySelector('.orgdon') || document.body).append(back);
    close.focus({ preventScroll: true });
    if (back.scrollIntoView && window.parent !== window) box.scrollIntoView({ block: 'start' });
  }

  window.addEventListener('message', (ev) => {
    if (ev.origin !== cfg.selfOrigin || !iframe || ev.source !== iframe.contentWindow) return;
    const m = ev.data || {};
    if (m.type !== 'orgdon-cardcom') return;
    if (m.status === 'ok') {
      // The form is sent automatically after the card is saved; "סיום" appears only if that send fails (retry without the card).
      cardSaved = true; clearTimeout(timer);
      if (dinersBox()) dinersBox().disabled = true;   // the saved card belongs to the terminal chosen above
      finishBtn.disabled = false;
      submit();
    } else {
      msg.textContent = 'פרטי הכרטיס לא נקלטו. נסו שוב.' +
        (cfg.diners && !isDiners() ? ' אם הכרטיס הוא דיינרס, יש לסמן "הכרטיס שלי הוא דיינרס".' : '');
      lpExpires = 0; openCard();
    }
  });
  form.addEventListener('submit', (e) => {
    e.preventDefault();
    if (!cardSaved) { setErr('card', 'נא להזין את פרטי הכרטיס וללחוץ "שמור כרטיס"'); return; }
    submit();
  });
})();
