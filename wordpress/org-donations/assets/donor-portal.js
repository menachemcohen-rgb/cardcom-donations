(function () {
  'use strict';
  // Pure helpers, exposed for the JS tests (tests/js) — hoisted function declarations below.
  window.OrgDonPortalUtil = { prayers: prayers, amountPayload: amountPayload };
  const cfg = window.ORGDON_PORTAL; const root = document.getElementById('orgdon-portal');
  if (!cfg || !root) return;
  const $ = (sel) => root.querySelector(sel);
  const KEY = 'orgdon_portal_token';

  // 1) token: from server-rendered config (URL) → sessionStorage; strip it from the address bar
  let token = cfg.token || sessionStorage.getItem(KEY) || '';
  if (cfg.token) { sessionStorage.setItem(KEY, cfg.token); }
  if (location.search) history.replaceState(null, '', location.pathname);
  let ctx = null; let lpId = null; let pollTimer = null; let pollUntil = 0;

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

  /** Which prayers a frequency charges (Salesforce API values). */
  function prayers(f) {
    return { shacharit: f === 'TwiceDaily' || f === 'OnceDaily', mincha: f === 'TwiceDaily' || f === 'MinchaOnly' };
  }
  /** Fields posted to org_portal_amount: only the prayers the pledge charges; Mincha = Shacharit when "אותו סכום" is checked. */
  function amountPayload(f, same, shacharit, mincha) {
    const inc = prayers(f); const out = {};
    if (inc.shacharit) out.shacharitAmount = String(shacharit);
    if (inc.mincha) out.minchaAmount = String(f === 'TwiceDaily' && same ? shacharit : mincha);
    return out;
  }

  /** Summary rows: "סכום לשחרית" / "סכום למנחה" according to the frequency. */
  function renderAmounts() {
    const inc = prayers(ctx.frequencyCode);
    ['shacharit', 'mincha'].forEach((p) => {
      const on = inc[p] && ctx[p + 'Amount'] != null;
      $('[data-role=' + p + '-row]').hidden = !on;
      if (on) $('[data-role=' + p + '-amount]').textContent = money(ctx[p + 'Amount']);
    });
  }

  function renderMain() {
    $('[data-role=first-name]').textContent = ctx.firstName || '';
    renderAmounts();
    $('[data-role=frequency]').textContent = ctx.frequency;
    $('[data-role=card]').textContent = cardText();
    $('[data-role=contact]').textContent = cfg.contactLine;
    renderPickers();
    show('main');
    tab(cfg.action || ctx.action || 'amount');
  }

  /** One picker per charged prayer, pre-selected with its current amount; "אותו סכום" for TwiceDaily (checked when equal). */
  function renderPickers() {
    const inc = prayers(ctx.frequencyCode);
    ['shacharit', 'mincha'].forEach((p) => {
      root.querySelector('[data-prayer=' + p + ']').hidden = !inc[p];
      $('[data-role=' + p + '-other-wrap]').hidden = true;
      $('[data-role=' + p + '-err]').textContent = '';
      if (!inc[p]) return;
      chips($('[data-role=' + p + '-presets]'), p + '_preset', ctx[p + 'Amount']);
      const other = $('#orgdon-' + p + '-other');
      other.min = ctx.min; other.max = ctx.max; other.placeholder = 'בין ' + ctx.min + ' ל-' + ctx.max;
    });
    const twice = ctx.frequencyCode === 'TwiceDaily';
    const same = root.querySelector('input[name=same_amount]');
    $('[data-role=same-amount]').hidden = !twice;
    same.checked = twice && ctx.shacharitAmount != null && Number(ctx.shacharitAmount) === Number(ctx.minchaAmount);
    syncSame();
  }
  function syncSame() {
    if (ctx.frequencyCode !== 'TwiceDaily') return;
    root.querySelector('[data-prayer=mincha]').hidden = root.querySelector('input[name=same_amount]').checked;
  }

  /** Amount chips (presets + the current amount if it isn't one of them, checked) and a "סכום אחר" chip. */
  function chips(box, name, current) {
    box.textContent = '';
    const values = ctx.presets.map(Number);
    if (current != null && values.indexOf(Number(current)) < 0) values.push(Number(current));   // keep the current amount selectable
    values.forEach((p) => {
      const l = document.createElement('label'); l.className = 'orgdon-chip';
      const i = document.createElement('input'); i.type = 'radio'; i.name = name; i.value = String(p);
      if (current != null && p === Number(current)) i.checked = true;
      const s = document.createElement('span'); s.textContent = money(p).replace(/\.00$/, '') + ' ₪';
      l.append(i, s); box.append(l);
    });
    const l = document.createElement('label'); l.className = 'orgdon-chip orgdon-chip-other';
    const i = document.createElement('input'); i.type = 'radio'; i.name = name; i.value = 'other';
    const s = document.createElement('span'); s.textContent = 'סכום אחר';
    l.append(i, s); box.append(l);
  }

  /** Amount chosen in a chip group: a valid string, '' if invalid (error shown), or null when nothing is selected. */
  function chosenAmount(name, otherInput, errEl) {
    const sel = root.querySelector('input[name=' + name + ']:checked');
    if (!sel) return null;
    const a = sel.value === 'other' ? otherInput.value.replace(',', '.') : sel.value;
    const n = Number(a);
    if (!a || isNaN(n) || n < ctx.min || n > ctx.max || !/^\d+(\.\d{1,2})?$/.test(a)) {
      errEl.textContent = 'נא לבחור סכום בין ' + ctx.min + ' ל-' + ctx.max + ' ₪.';
      return '';
    }
    return a;
  }

  function tab(name) {
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
    const m = /^(shacharit|mincha)_preset$/.exec(e.target.name || '');
    if (m) $('[data-role=' + m[1] + '-other-wrap]').hidden = e.target.value !== 'other';
    if (e.target.name === 'same_amount') syncSame();
  });
  root.querySelector('.orgdon-amount-form').addEventListener('submit', async (e) => {
    e.preventDefault(); msg('');
    const inc = prayers(ctx.frequencyCode);
    const same = ctx.frequencyCode === 'TwiceDaily' && root.querySelector('input[name=same_amount]').checked;
    const chosen = {}; let bad = false;
    ['shacharit', 'mincha'].forEach((p) => {
      $('[data-role=' + p + '-err]').textContent = '';
      if (!inc[p] || (p === 'mincha' && same)) return;
      const a = chosenAmount(p + '_preset', $('#orgdon-' + p + '-other'), $('[data-role=' + p + '-err]'));
      if (a === null) { $('[data-role=' + p + '-err]').textContent = 'נא לבחור סכום.'; bad = true; }
      else if (a === '') bad = true;
      else chosen[p] = a;
    });
    if (bad) return;
    const btn = e.submitter || root.querySelector('.orgdon-amount-form .orgdon-btn'); btn.disabled = true;
    const j = await post('amount', amountPayload(ctx.frequencyCode, same, chosen.shacharit, chosen.mincha));
    btn.disabled = false;
    if (j.success) {
      if (j.data.shacharitAmount != null) ctx.shacharitAmount = Number(j.data.shacharitAmount);
      if (j.data.minchaAmount != null) ctx.minchaAmount = Number(j.data.minchaAmount);
      renderAmounts(); renderPickers();
      msg(j.data.message, 'ok');
      return;
    }
    if (j.data && j.data.invalid) return invalid(j.data.message);
    msg((j.data && j.data.message) || 'אירעה שגיאה. נסו שוב.', 'error');
  });

  // 5) card replacement
  const frameWrap = $('[data-role=card-frame-wrap]'); const frame = $('[data-role=card-frame]');
  $('[data-role=card-start]').addEventListener('click', async (e) => {
    const btn = e.currentTarget; msg('');
    btn.disabled = true;
    const j = await post('card', {});
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
    if (j.success && j.data.status === 'Completed') return cardDone(j.data);
    if (j.success && (j.data.status === 'Failed' || j.data.status === 'Expired')) return cardFailed();
    if (j.data && j.data.invalid) return invalid(j.data.message);
    if (Date.now() > pollUntil) {
      $('[data-role=card-wait]').hidden = true;
      msg('הבדיקה נמשכת יותר מהרגיל. אם הכרטיס נשמר, תקבלו אישור בהמשך. אפשר לרענן את הדף בעוד מספר דקות.', 'info');
      return;
    }
    pollTimer = setTimeout(poll, 3000);
  }
  function cardDone(d) {
    const last4 = d.last4;
    $('[data-role=card-wait]').hidden = true; lpId = null;
    if (last4) { ctx.last4 = last4; ctx.exp = null; }
    $('[data-role=card]').textContent = last4 ? '****' + last4 : 'כרטיס חדש';
    // refresh the summary with the amounts Salesforce returns (unchanged by a card replacement)
    if (d.shacharitAmount != null) ctx.shacharitAmount = Number(d.shacharitAmount);
    if (d.minchaAmount != null) ctx.minchaAmount = Number(d.minchaAmount);
    renderAmounts();
    msg(last4 ? 'פרטי הכרטיס עודכנו בהצלחה. החיוב הבא יתבצע בכרטיס המסתיים ב-' + last4 + '.'
              : 'פרטי הכרטיס עודכנו בהצלחה. החיוב הבא יתבצע בכרטיס החדש.', 'ok');
    $('[data-role=card-start]').hidden = false;
  }

  function cardFailed() {
    $('[data-role=card-wait]').hidden = true; lpId = null;
    msg('פרטי הכרטיס לא נקלטו והכרטיס הקודם נשאר בתוקף. ניתן לנסות שוב.', 'error');
    $('[data-role=card-start]').hidden = false;
  }

  load();
})();
