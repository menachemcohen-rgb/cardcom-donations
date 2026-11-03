(function () {
  'use strict';
  const cfg = window.ORGDON_PORTAL; const root = document.getElementById('orgdon-portal');
  if (!cfg || !root) return;
  const $ = (sel) => root.querySelector(sel);
  const KEY = 'orgdon_portal_token';

  // 1) token: from server-rendered config (URL) → sessionStorage; strip it from the address bar
  let token = cfg.token || sessionStorage.getItem(KEY) || '';
  if (cfg.token) { sessionStorage.setItem(KEY, cfg.token); }
  if (location.search) history.replaceState(null, '', location.pathname);
  let ctx = null; let lpId = null; let pollTimer = null; let pollUntil = 0; let pendingAmount = null;

  function show(view) { root.querySelectorAll('[data-view]').forEach((el) => { el.hidden = el.dataset.view !== view; }); }
  function msg(text, kind) {
    const m = $('[data-role=msg]'); m.textContent = text || ''; m.hidden = !text;
    m.className = 'orgdon-msg-box' + (kind ? ' orgdon-msg-' + kind : '');
  }
  function invalid(text) { $('[data-role=invalid-text]').textContent = text || cfg.invalidMsg; sessionStorage.removeItem(KEY); show('invalid'); }
  function money(n) { return Number(n).toFixed(2); }

  async function post(action, data) {
    const fd = new FormData(); fd.append('action', 'org_portal_' + action); fd.append('nonce', cfg.nonce); fd.append('token', token);
    Object.entries(data || {}).forEach(([k, v]) => fd.append(k, v));
    let r, j = {};
    try { r = await fetch(cfg.ajaxUrl, { method: 'POST', body: fd, credentials: 'same-origin' }); j = await r.json(); }
    catch (e) { return { success: false, data: { message: 'אירעה שגיאה בתקשורת. בדקו את החיבור ונסו שוב.' } }; }
    return j;
  }

  // 2) load context
  async function load(verifyCode) {
    if (!token) return invalid();
    const j = await post('context', verifyCode ? { verifyCode } : {});
    if (j.success) { ctx = j.data; return renderMain(); }
    const d = j.data || {};
    if (d.verify) { $('[data-role=verify-text]').textContent = d.message; show('verify'); return; }
    if (d.invalid) return invalid(d.message);
    invalid(d.message);
  }

  function cardText() {
    if (!ctx.last4) return 'כרטיס שנשמר';
    return '****' + ctx.last4 + (ctx.exp ? ', תוקף ' + ctx.exp : '');
  }

  function renderMain() {
    $('[data-role=first-name]').textContent = ctx.firstName || '';
    $('[data-role=amount]').textContent = money(ctx.amount);
    $('[data-role=frequency]').textContent = ctx.frequency;
    $('[data-role=card]').textContent = cardText();
    $('[data-role=contact]').textContent = cfg.contactLine;
    chips($('[data-role=presets]'), 'preset', false);
    chips($('[data-role=card-presets]'), 'card_preset', true);
    [$('#orgdon-other'), $('#orgdon-card-other')].forEach((other) => {
      other.min = ctx.min; other.max = ctx.max; other.placeholder = 'בין ' + ctx.min + ' ל-' + ctx.max;
    });
    show('main');
    tab(cfg.action || ctx.action || 'amount');
  }

  /** Amount chips (presets, the current amount checked). withOther: the card panel has its own "סכום אחר" chip inside the box. */
  function chips(box, name, withOther) {
    box.textContent = '';
    const values = ctx.presets.map(Number);
    if (values.indexOf(Number(ctx.amount)) < 0 && withOther) values.push(Number(ctx.amount)); // keep the current amount selectable
    values.forEach((p) => {
      const l = document.createElement('label'); l.className = 'orgdon-chip';
      const i = document.createElement('input'); i.type = 'radio'; i.name = name; i.value = String(p);
      if (p === Number(ctx.amount)) i.checked = true;
      const s = document.createElement('span'); s.textContent = money(p).replace(/\.00$/, '') + ' ₪';
      l.append(i, s); box.append(l);
    });
    if (withOther) {
      const l = document.createElement('label'); l.className = 'orgdon-chip orgdon-chip-other';
      const i = document.createElement('input'); i.type = 'radio'; i.name = name; i.value = 'other';
      const s = document.createElement('span'); s.textContent = 'סכום אחר';
      l.append(i, s); box.append(l);
    }
  }

  /** Amount chosen in a chip group: a valid string, '' if invalid (error shown), or null when nothing is selected. */
  function chosenAmount(name, otherInput, errEl) {
    const sel = root.querySelector('input[name=' + name + ']:checked');
    if (!sel) return null;
    const a = sel.value === 'other' ? otherInput.value.replace(',', '.') : sel.value;
    const n = Number(a);
    if (!a || isNaN(n) || n < ctx.min || n > ctx.max || !/^\d+(\.\d{1,2})?$/.test(a)) {
      const t = 'נא לבחור סכום בין ' + ctx.min + ' ל-' + ctx.max + ' ₪.';
      if (errEl && sel.value === 'other') errEl.textContent = t; else msg(t, 'error');
      return '';
    }
    return a;
  }

  function tab(name) {
    const confirmBox = $('[data-role=stop-confirm]'); if (confirmBox) { confirmBox.hidden = true; $('[data-role=stop-ask]').hidden = false; }
    root.querySelectorAll('[data-tab]').forEach((b) => { const on = b.dataset.tab === name; b.setAttribute('aria-selected', on); b.tabIndex = on ? 0 : -1; });
    root.querySelectorAll('[data-panel]').forEach((p) => { p.hidden = p.dataset.panel !== name; });
    msg('');
  }
  root.addEventListener('click', (e) => { const b = e.target.closest('[data-tab]'); if (b) tab(b.dataset.tab); });

  // 3) verify (optional feature B6.9.6)
  root.querySelector('.orgdon-verify').addEventListener('submit', (e) => {
    e.preventDefault(); const v = $('#orgdon-verify-code').value.replace(/\D/g, '');
    if (v.length !== 4) { $('[data-role=verify-text]').textContent = 'נא להקליד 4 ספרות.'; return; }
    load(v);
  });

  // 4) amount
  root.addEventListener('change', (e) => {
    if (e.target.name === 'preset') $('[data-role=other-wrap]').hidden = e.target.value !== 'other';
    if (e.target.name === 'card_preset') $('[data-role=card-other-wrap]').hidden = e.target.value !== 'other';
  });
  root.querySelector('.orgdon-amount-form').addEventListener('submit', async (e) => {
    e.preventDefault();
    const err = $('[data-role=amount-err]'); err.textContent = '';
    const a = chosenAmount('preset', $('#orgdon-other'), err);
    if (a === null) { msg('נא לבחור סכום.', 'error'); return; }
    if (a === '') return;
    const btn = e.submitter || root.querySelector('.orgdon-amount-form .orgdon-btn'); btn.disabled = true;
    const j = await post('amount', { amount: a });
    btn.disabled = false;
    if (j.success) { ctx.amount = j.data.amount; $('[data-role=amount]').textContent = money(ctx.amount); msg(j.data.message, 'ok'); return; }
    if (j.data && j.data.invalid) return invalid(j.data.message);
    msg((j.data && j.data.message) || 'אירעה שגיאה. נסו שוב.', 'error');
  });

  // 5) card replacement
  const frameWrap = $('[data-role=card-frame-wrap]'); const frame = $('[data-role=card-frame]');
  $('[data-role=card-start]').addEventListener('click', async (e) => {
    const btn = e.currentTarget; msg('');
    const err = $('[data-role=card-amount-err]'); err.textContent = '';
    const a = chosenAmount('card_preset', $('#orgdon-card-other'), err);
    if (a === '') return;
    // one step: the new amount (if any) goes with the card and is applied once the new card is saved
    const data = a !== null && Number(a) !== Number(ctx.amount) ? { amount: a } : {};
    pendingAmount = data.amount ? Number(data.amount) : null;
    btn.disabled = true;
    const j = await post('card', data);
    btn.disabled = false;
    if (!j.success) { if (j.data && j.data.invalid) return invalid(j.data.message); msg((j.data && j.data.message) || 'לא ניתן לטעון כעת את טופס התשלום.', 'error'); return; }
    lpId = j.data.lpId; frame.src = j.data.url; frameWrap.hidden = false; btn.hidden = true;
  });

  window.addEventListener('message', (ev) => {
    // the return page is served from our own origin inside the Cardcom iframe
    if (ev.origin !== cfg.selfOrigin || ev.source !== frame.contentWindow) return;
    const d = ev.data || {};
    if (d.type !== 'orgdon-cardcom' || !lpId) return;
    frameWrap.hidden = true; frame.src = 'about:blank';
    if (d.status !== 'ok') return cardFailed();
    $('[data-role=card-wait]').hidden = false;
    pollUntil = Date.now() + 60000; poll();
  });

  async function poll() {
    clearTimeout(pollTimer);
    const j = await post('card_status', { lpId });
    if (j.success && j.data.status === 'Completed') return cardDone(j.data.last4, j.data.amount);
    if (j.success && (j.data.status === 'Failed' || j.data.status === 'Expired')) return cardFailed();
    if (j.data && j.data.invalid) return invalid(j.data.message);
    if (Date.now() > pollUntil) {
      $('[data-role=card-wait]').hidden = true;
      msg('הבדיקה נמשכת יותר מהרגיל. אם הכרטיס נשמר, תקבלו אישור בהמשך. אפשר לרענן את הדף בעוד מספר דקות.', 'info');
      return;
    }
    pollTimer = setTimeout(poll, 3000);
  }
  function cardDone(last4, amount) {
    $('[data-role=card-wait]').hidden = true; lpId = null;
    if (last4) { ctx.last4 = last4; ctx.exp = null; }
    $('[data-role=card]').textContent = last4 ? '****' + last4 : 'כרטיס חדש';
    let text = last4 ? 'פרטי הכרטיס עודכנו בהצלחה. החיוב הבא יתבצע בכרטיס המסתיים ב-' + last4 + '.'
                     : 'פרטי הכרטיס עודכנו בהצלחה. החיוב הבא יתבצע בכרטיס החדש.';
    if (pendingAmount !== null && amount != null && Number(amount) === pendingAmount) {
      ctx.amount = Number(amount); $('[data-role=amount]').textContent = money(ctx.amount);
      text += ' הסכום עודכן ל-' + money(ctx.amount) + ' ₪ לכל חיוב.';
    }
    pendingAmount = null;
    msg(text, 'ok');
    $('[data-role=card-start]').hidden = false;
  }

  // 6) stop the pledge (asks first)
  $('[data-role=stop-ask]').addEventListener('click', () => {
    msg(''); $('[data-role=stop-ask]').hidden = true; $('[data-role=stop-confirm]').hidden = false;
    $('[data-role=stop-yes]').focus();
  });
  $('[data-role=stop-no]').addEventListener('click', () => {
    $('[data-role=stop-confirm]').hidden = true; $('[data-role=stop-ask]').hidden = false;
  });
  $('[data-role=stop-yes]').addEventListener('click', async (e) => {
    const btn = e.currentTarget; btn.disabled = true;
    const j = await post('stop', { confirm: '1' });
    btn.disabled = false;
    if (j.success) {
      sessionStorage.removeItem(KEY);
      root.querySelectorAll('.orgdon-tabs, [data-panel]').forEach((el) => { el.hidden = true; });
      msg(j.data.message, 'ok');
      return;
    }
    if (j.data && j.data.invalid) return invalid(j.data.message);
    msg((j.data && j.data.message) || 'אירעה שגיאה. נסו שוב.', 'error');
  });
  function cardFailed() {
    $('[data-role=card-wait]').hidden = true; lpId = null;
    msg('פרטי הכרטיס לא נקלטו והכרטיס הקודם נשאר בתוקף. ניתן לנסות שוב.', 'error');
    $('[data-role=card-start]').hidden = false;
  }

  load();
})();
