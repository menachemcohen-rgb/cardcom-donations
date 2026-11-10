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
      <div data-role="shacharit-row" hidden><span class="orgdon-k">סכום לשחרית:</span> <strong data-role="shacharit-amount"></strong> ₪</div>
      <div data-role="mincha-row" hidden><span class="orgdon-k">סכום למנחה:</span> <strong data-role="mincha-amount"></strong> ₪</div>
      <div><span class="orgdon-k">תדירות:</span> <span data-role="frequency"></span></div>
      <div><span class="orgdon-k">כרטיס:</span> <span data-role="card"></span></div>
    </div>

    <nav class="orgdon-tabs" role="tablist" aria-label="פעולות">
      <button type="button" role="tab" id="orgdon-tab-amount" aria-controls="orgdon-panel-amount" data-tab="amount">שינוי סכום</button>
      <button type="button" role="tab" id="orgdon-tab-card" aria-controls="orgdon-panel-card" data-tab="card">החלפת כרטיס</button>
    </nav>

    <section id="orgdon-panel-amount" role="tabpanel" aria-labelledby="orgdon-tab-amount" data-panel="amount" hidden>
      <form class="orgdon-amount-form" novalidate>
<?php foreach (['shacharit' => 'סכום חדש לשחרית', 'mincha' => 'סכום חדש למנחה'] as $prayer => $legend): ?>
        <fieldset class="orgdon-row" data-prayer="<?= esc_attr($prayer) ?>" hidden>
          <legend><?= esc_html($legend) ?></legend>
          <div class="orgdon-chips" data-role="<?= esc_attr($prayer) ?>-presets"></div>
          <div class="orgdon-row" data-role="<?= esc_attr($prayer) ?>-other-wrap" hidden>
            <label for="orgdon-<?= esc_attr($prayer) ?>-other">סכום (₪)</label>
            <input id="orgdon-<?= esc_attr($prayer) ?>-other" name="<?= esc_attr($prayer) ?>_other" type="number" inputmode="decimal" step="0.5">
          </div>
          <div class="orgdon-err" data-role="<?= esc_attr($prayer) ?>-err" role="alert" aria-live="assertive"></div>
        </fieldset>
<?php if ($prayer === 'shacharit'): ?>
        <div class="orgdon-row orgdon-same" data-role="same-amount" hidden>
          <label><input type="checkbox" name="same_amount" value="1"> <span>אותו סכום בשחרית ובמנחה</span></label>
        </div>
<?php endif; endforeach; ?>
        <p class="orgdon-note">הסכום החדש יחול מהחיוב הבא.</p>
        <button type="submit" class="orgdon-btn">עדכון סכום</button>
      </form>
    </section>

    <section id="orgdon-panel-card" role="tabpanel" aria-labelledby="orgdon-tab-card" data-panel="card" hidden>
      <p>אפשר להחליף את הכרטיס שממנו נגבית התרומה. הכרטיס הקודם יישאר בתוקף עד שהחדש יישמר.</p>
      <div class="orgdon-row orgdon-diners" data-role="card-diners-wrap" hidden>
        <label><input type="checkbox" data-role="card-diners" value="1"> <span>הכרטיס החדש הוא דיינרס (Diners)</span></label>
      </div>
      <button type="button" class="orgdon-btn" data-role="card-start">החלפת כרטיס</button>
      <div class="orgdon-card" data-role="card-frame-wrap" hidden>
        <iframe title="טופס כרטיס אשראי מאובטח של Cardcom" data-role="card-frame" allow="payment" referrerpolicy="no-referrer"></iframe>
      </div>
      <div class="orgdon-wait" data-role="card-wait" hidden><span class="orgdon-spinner" aria-hidden="true"></span> בודקים את פרטי הכרטיס…</div>
    </section>

    <p class="orgdon-msg-box" data-role="msg" role="status" hidden></p>
    <p class="orgdon-foot" data-role="contact"></p>
  </div>
</div>
