<?php if (!defined('ABSPATH')) exit; ?>
<div class="orgdon" dir="rtl" lang="he">
  <form id="orgdon-form" novalidate>
    <h2 class="orgdon-title">הצטרפות להוראת תרומה יומית</h2>
    <p class="orgdon-sub">ללא חיוב בשבת ובחגים; ביום שישי ובערב חג יבוצע חיוב כפול.</p>

    <div class="orgdon-row">
      <label for="od-first">שם פרטי *</label>
      <input id="od-first" name="first_name" autocomplete="given-name" maxlength="40" required>
      <span class="orgdon-err" data-for="first_name" role="alert"></span>
    </div>
    <div class="orgdon-row">
      <label for="od-last">שם משפחה *</label>
      <input id="od-last" name="last_name" autocomplete="family-name" maxlength="80" required>
      <span class="orgdon-err" data-for="last_name" role="alert"></span>
    </div>
    <div class="orgdon-row">
      <label for="od-email">אימייל *</label>
      <input id="od-email" name="email" type="email" dir="ltr" autocomplete="email" maxlength="80" required>
      <span class="orgdon-err" data-for="email" role="alert"></span>
    </div>
    <div class="orgdon-row">
      <label for="od-phone">טלפון נייד *</label>
      <input id="od-phone" name="phone" type="tel" dir="ltr" inputmode="tel" autocomplete="tel" placeholder="05X-XXXXXXX" required>
      <span class="orgdon-err" data-for="phone" role="alert"></span>
    </div>
    <div class="orgdon-row">
      <label for="od-id">תעודת זהות (רשות)</label>
      <input id="od-id" name="tax_id" dir="ltr" inputmode="numeric" maxlength="9">
      <span class="orgdon-err" data-for="tax_id" role="alert"></span>
    </div>

    <fieldset class="orgdon-row">
      <legend>סכום לכל חיוב *</legend>
      <div class="orgdon-chips">
        <?php foreach ($presets as $i => $p): ?>
          <label class="orgdon-chip"><input type="radio" name="amount_preset" value="<?= esc_attr($p) ?>" <?= $i === 0 ? 'checked' : '' ?>><span><?= esc_html($p) ?> ₪</span></label>
        <?php endforeach; ?>
        <label class="orgdon-chip"><input type="radio" name="amount_preset" value="other"><span>סכום אחר</span></label>
      </div>
      <input id="od-amount-other" name="amount_other" type="number" min="<?= esc_attr(Org_Form::MIN) ?>" max="<?= esc_attr(Org_Form::MAX) ?>" step="0.01" dir="ltr" hidden aria-label="סכום אחר">
      <span class="orgdon-err" data-for="amount" role="alert"></span>
    </fieldset>

    <fieldset class="orgdon-row">
      <legend>תדירות *</legend>
      <label class="orgdon-chip"><input type="radio" name="frequency" value="OnceDaily" checked><span>פעם ביום (בוקר)</span></label>
      <label class="orgdon-chip"><input type="radio" name="frequency" value="TwiceDaily"><span>פעמיים ביום (בוקר וערב)</span></label>
      <span class="orgdon-err" data-for="frequency" role="alert"></span>
    </fieldset>

    <p class="orgdon-estimate" aria-live="polite"></p>

    <div class="orgdon-row orgdon-terms">
      <label><input type="checkbox" name="terms" value="1" required>
        אני מאשר/ת חיובים חוזרים בכרטיס האשראי לפי הסכום והתדירות שבחרתי, וידוע לי שאוכל לבטל בכל עת. <a href="<?= esc_url($terms_url) ?>" target="_blank" rel="noopener">תנאי ההוראה</a></label>
      <span class="orgdon-err" data-for="terms" role="alert"></span>
    </div>

    <div class="orgdon-card">
      <h3>פרטי כרטיס אשראי (מסגרת מאובטחת של Cardcom)</h3>
      <?php if ($iframe_url): ?>
        <iframe id="orgdon-iframe" src="<?= esc_url($iframe_url) ?>" title="תשלום מאובטח Cardcom" loading="eager"
                referrerpolicy="no-referrer" allow="payment" sandbox="allow-forms allow-scripts allow-same-origin allow-top-navigation-by-user-activation"></iframe>
      <?php else: ?>
        <p class="orgdon-error"><?= esc_html($error ?? 'לא ניתן לטעון כעת את טופס התשלום.') ?></p>
      <?php endif; ?>
      <span class="orgdon-err" data-for="card" role="alert"></span>
    </div>

    <button type="submit" id="orgdon-finish" class="orgdon-btn" hidden>סיום</button>
    <div id="orgdon-msg" class="orgdon-msg" role="status" aria-live="polite"></div>
  </form>
</div>
