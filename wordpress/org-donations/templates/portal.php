<?php if (!defined('ABSPATH')) exit; ?>
<div class="orgdon orgdon-portal" id="orgdon-portal" dir="rtl" lang="he" aria-live="polite">
  <div class="orgdon-loading" data-view="loading">טוען…</div>

  <div class="orgdon-invalid" data-view="invalid" hidden>
    <p class="orgdon-msg-box orgdon-msg-error" data-role="invalid-text"></p>
  </div>

  <form class="orgdon-verify" data-view="verify" hidden novalidate>
    <p data-role="verify-text">לאימות, נא להקליד את 4 הספרות האחרונות של הטלפון שמסרת.</p>
    <div class="orgdon-row">
      <label for="orgdon-verify-code">4 ספרות אחרונות של הטלפון</label>
      <input id="orgdon-verify-code" name="verifyCode" inputmode="numeric" pattern="\d{4}" maxlength="4" autocomplete="off" required>
    </div>
    <button type="submit" class="orgdon-btn">המשך</button>
  </form>

  <div data-view="main" hidden>
    <h2 class="orgdon-hello">שלום <span data-role="first-name"></span>,</h2>
    <div class="orgdon-summary">
      <div><span class="orgdon-k">סכום לכל חיוב:</span> <strong data-role="amount"></strong> ₪</div>
      <div><span class="orgdon-k">תדירות:</span> <span data-role="frequency"></span></div>
      <div><span class="orgdon-k">כרטיס:</span> <span data-role="card"></span></div>
    </div>

    <nav class="orgdon-tabs" role="tablist" aria-label="פעולות">
      <button type="button" role="tab" id="orgdon-tab-amount" aria-controls="orgdon-panel-amount" data-tab="amount">שינוי סכום</button>
      <button type="button" role="tab" id="orgdon-tab-card" aria-controls="orgdon-panel-card" data-tab="card">החלפת כרטיס</button>
      <button type="button" role="tab" id="orgdon-tab-stop" aria-controls="orgdon-panel-stop" data-tab="stop">הפסקת חיובים</button>
    </nav>

    <section id="orgdon-panel-amount" role="tabpanel" aria-labelledby="orgdon-tab-amount" data-panel="amount" hidden>
      <form class="orgdon-amount-form" novalidate>
        <fieldset class="orgdon-row">
          <legend>סכום חדש לכל חיוב</legend>
          <div class="orgdon-chips" data-role="presets"></div>
          <label class="orgdon-chip"><input type="radio" name="preset" value="other"><span>סכום אחר</span></label>
        </fieldset>
        <div class="orgdon-row" data-role="other-wrap" hidden>
          <label for="orgdon-other">סכום (₪)</label>
          <input id="orgdon-other" name="other" type="number" inputmode="decimal" step="0.5">
          <div class="orgdon-err" data-role="amount-err" aria-live="assertive"></div>
        </div>
        <p class="orgdon-note">הסכום החדש יחול מהחיוב הבא.</p>
        <button type="submit" class="orgdon-btn">עדכון סכום</button>
      </form>
    </section>

    <section id="orgdon-panel-card" role="tabpanel" aria-labelledby="orgdon-tab-card" data-panel="card" hidden>
      <p>אפשר להחליף את הכרטיס שממנו נגבית התרומה. הכרטיס הקודם יישאר בתוקף עד שהחדש יישמר.</p>
      <fieldset class="orgdon-row" data-role="card-amount">
        <legend>סכום לכל חיוב (אפשר לשנות יחד עם הכרטיס)</legend>
        <div class="orgdon-chips" data-role="card-presets"></div>
        <div class="orgdon-row" data-role="card-other-wrap" hidden>
          <label for="orgdon-card-other">סכום (₪)</label>
          <input id="orgdon-card-other" name="card_other" type="number" inputmode="decimal" step="0.5">
        </div>
        <div class="orgdon-err" data-role="card-amount-err" aria-live="assertive"></div>
        <p class="orgdon-note">סכום חדש יחול מהחיוב הבא, רק לאחר שהכרטיס החדש יישמר.</p>
      </fieldset>
      <button type="button" class="orgdon-btn" data-role="card-start">החלפת כרטיס</button>
      <div class="orgdon-card" data-role="card-frame-wrap" hidden>
        <iframe title="טופס כרטיס אשראי מאובטח של Cardcom" data-role="card-frame" allow="payment" referrerpolicy="no-referrer"></iframe>
      </div>
      <div class="orgdon-wait" data-role="card-wait" hidden><span class="orgdon-spinner" aria-hidden="true"></span> בודקים את פרטי הכרטיס…</div>
    </section>

    <section id="orgdon-panel-stop" role="tabpanel" aria-labelledby="orgdon-tab-stop" data-panel="stop" hidden>
      <p>אפשר להפסיק את הוראת התרומה. לאחר ההפסקה לא יבוצעו חיובים נוספים. לחידוש ההוראה יש לפנות אלינו.</p>
      <button type="button" class="orgdon-btn orgdon-btn-danger" data-role="stop-ask">הפסקת החיובים</button>
      <div class="orgdon-confirm" data-role="stop-confirm" hidden>
        <p><strong>בטוח/ה? לאחר ההפסקה לא יבוצעו חיובים נוספים.</strong></p>
        <button type="button" class="orgdon-btn orgdon-btn-danger" data-role="stop-yes">כן, להפסיק</button>
        <button type="button" class="orgdon-btn orgdon-btn-secondary" data-role="stop-no">חזרה</button>
      </div>
    </section>

    <p class="orgdon-msg-box" data-role="msg" role="status" hidden></p>
    <p class="orgdon-foot" data-role="contact"></p>
  </div>
</div>
