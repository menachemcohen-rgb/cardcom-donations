<?php if (!defined('ABSPATH')) exit; ?>
<div class="orgdon" dir="rtl" lang="he">
  <form id="orgdon-form" novalidate>
    <h2 class="orgdon-title">הצטרפות להוראת תרומה יומית</h2>
    <p class="orgdon-sub">חיוב בזמן תפילת שחרית ו/או מנחה. ללא חיוב בשבת ובחגים; ביום שישי ובערב חג יבוצע חיוב כפול.</p>

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
      <legend>תדירות *</legend>
      <label class="orgdon-chip"><input type="radio" name="frequency" value="TwiceDaily" checked><span>שחרית ומנחה</span></label>
      <label class="orgdon-chip"><input type="radio" name="frequency" value="OnceDaily"><span>רק שחרית</span></label>
      <label class="orgdon-chip"><input type="radio" name="frequency" value="MinchaOnly"><span>רק מנחה</span></label>
      <span class="orgdon-err" data-for="frequency" role="alert"></span>
    </fieldset>

<?php
// One amount picker per prayer (preset chips + "סכום אחר"). Visibility follows the frequency (assets/donation-form.js).
$pickers = [
    'shacharit' => ['label' => 'סכום לשחרית *', 'hidden' => false],
    'mincha'    => ['label' => 'סכום למנחה *',  'hidden' => true],   // default: שחרית ומנחה with "אותו סכום" checked
];
foreach ($pickers as $prayer => $pk): ?>
    <fieldset class="orgdon-row" data-prayer="<?= esc_attr($prayer) ?>"<?= $pk['hidden'] ? ' hidden' : '' ?>>
      <legend><?= esc_html($pk['label']) ?></legend>
      <div class="orgdon-chips">
        <?php foreach ($presets as $i => $p): ?>
          <label class="orgdon-chip"><input type="radio" name="<?= esc_attr($prayer) ?>_preset" value="<?= esc_attr($p) ?>" <?= $i === 0 ? 'checked' : '' ?>><span><?= esc_html($p) ?> ₪</span></label>
        <?php endforeach; ?>
        <label class="orgdon-chip orgdon-chip-other"><input type="radio" name="<?= esc_attr($prayer) ?>_preset" value="other"><span>סכום אחר</span></label>
      </div>
      <input id="od-<?= esc_attr($prayer) ?>-other" name="<?= esc_attr($prayer) ?>_other" type="number" min="<?= esc_attr(Org_Form::min_amount()) ?>" max="<?= esc_attr(Org_Form::max_amount()) ?>" step="0.01" dir="ltr" hidden aria-label="<?= esc_attr($prayer === 'shacharit' ? 'סכום אחר לשחרית' : 'סכום אחר למנחה') ?>">
      <span class="orgdon-err" data-for="<?= esc_attr($prayer) ?>_amount" role="alert"></span>
    </fieldset>
<?php if ($prayer === 'shacharit'): ?>
    <div class="orgdon-row orgdon-same" data-role="same-amount">
      <label><input type="checkbox" name="same_amount" value="1" checked> <span>אותו סכום בשחרית ובמנחה</span></label>
    </div>
<?php endif; endforeach; ?>

    <p class="orgdon-estimate" aria-live="polite"></p>

    <div class="orgdon-row orgdon-terms">
      <label><input type="checkbox" name="terms" value="1" required>
        <span>אני מאשר/ת חיובים חוזרים בכרטיס האשראי לפי הסכום והתדירות שבחרתי, וידוע לי שאוכל לבטל בכל עת.<?php if ($terms_url !== ''): ?> <a href="<?= esc_url($terms_url) ?>" target="_blank" rel="noopener">תנאי ההוראה</a><?php endif; ?></span></label>
      <span class="orgdon-err" data-for="terms" role="alert"></span>
    </div>

    <div class="orgdon-card">
      <h3>פרטי כרטיס אשראי (מסגרת מאובטחת של Cardcom)</h3>
      <p class="orgdon-card-note">שמירת כרטיס בלבד – לא יתבצע חיוב עכשיו. הסכום ₪1.00 שמופיע במסגרת הוא בדיקת תקינות של הכרטיס, והחיוב יתבצע לפי הסכום והתדירות שבחרת.</p>
      <p class="orgdon-card-hint" data-role="card-hint">יש למלא את פרטי הטופס ולאשר את התנאים, ואז ללחוץ על "המשך להזנת פרטי כרטיס".</p>
      <button type="button" id="orgdon-continue" class="orgdon-btn">המשך להזנת פרטי כרטיס</button>
      <iframe id="orgdon-iframe" title="תשלום מאובטח Cardcom" hidden
              referrerpolicy="no-referrer" allow="payment" sandbox="allow-forms allow-scripts allow-same-origin allow-top-navigation-by-user-activation"></iframe>
      <span class="orgdon-err" data-for="card" role="alert"></span>
    </div>

    <button type="submit" id="orgdon-finish" class="orgdon-btn" hidden disabled>סיום</button>
    <div id="orgdon-msg" class="orgdon-msg" role="status" aria-live="polite"></div>
  </form>
</div>
