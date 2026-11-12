<?php
if (!defined('ABSPATH')) exit;

final class Org_Form {
    // Amount defaults; override in wp-config.php with ORG_DONATION_MIN_AMOUNT / _MAX_AMOUNT / ORG_DONATION_PRESETS ("1,2,3,5,10").
    // Keep them equal to Cardcom_Setting__mdt Min/Max/Amount_Presets: Salesforce re-validates the Shacharit/Mincha amounts.
    const MIN = 1; const MAX = 25;    // ATA-6: at most 25 ₪ per charge (= Cardcom_Setting__mdt.Default.Max_Amount__c)
    const PRESETS = [1, 2, 3, 5, 10];

    // Rate-limit defaults; override in wp-config.php with ORG_DONATION_RL_WINDOW / _SUBMIT_MAX / _LP_MAX.
    const RL_WINDOW = 600;      // seconds, fixed window from the first counted request
    const RL_SUBMIT_MAX = 5;    // pledge submissions per window per IP (validated, non-duplicate ones only)
    const RL_LP_MAX = 10;       // Cardcom card sessions per window per IP (created only for a valid form)

    const LOCK_TTL = 120;       // seconds a submission lock may be held before it is considered stale
    const DONE_TTL = DAY_IN_SECONDS;

    const MSG_THANKS = 'תודה! הוראת התרומה התקבלה ונמצאת באימות. החיוב הראשון יתבצע במועד החיוב הקרוב.';
    const MSG_TOO_MANY = 'בוצעו ניסיונות רבים. נסו שוב בעוד מספר דקות.';

    public static function register(): void {
        add_shortcode('org_donation_form', [self::class, 'render']);
        add_action('wp_ajax_org_donation_lp',             [self::class, 'ajax_lp']);
        add_action('wp_ajax_nopriv_org_donation_lp',      [self::class, 'ajax_lp']);
        add_action('wp_ajax_org_donation_refresh',        [self::class, 'ajax_lp']);   // older cached JS
        add_action('wp_ajax_nopriv_org_donation_refresh', [self::class, 'ajax_lp']);
        add_action('wp_ajax_org_donation_submit',         [self::class, 'ajax_submit']);
        add_action('wp_ajax_nopriv_org_donation_submit',  [self::class, 'ajax_submit']);
    }

    public static function min_amount(): float { return self::amount_cfg('ORG_DONATION_MIN_AMOUNT', self::MIN); }
    public static function max_amount(): float { return self::amount_cfg('ORG_DONATION_MAX_AMOUNT', self::MAX); }

    /** @return float[] the amount buttons, from ORG_DONATION_PRESETS ("1,2,3,5,10") or the default; values outside min..max dropped. */
    public static function presets(): array {
        $raw = orgdon_const('ORG_DONATION_PRESETS');
        $list = $raw === '' ? self::PRESETS : array_map('trim', explode(',', $raw));
        $out = [];
        foreach ($list as $v) {
            if (is_numeric($v) && (float) $v >= self::min_amount() && (float) $v <= self::max_amount()) $out[] = $v + 0;
        }
        if (!$out) foreach (self::PRESETS as $v) if ($v >= self::min_amount() && $v <= self::max_amount()) $out[] = $v;
        return $out;
    }

    // Card frame heights, ATA-6: defaults 880px / 1150px in donation-form.css; override with ORG_DONATION_FRAME_HEIGHT / ORG_DONATION_FRAME_HEIGHT_MOBILE.

    /** Inline CSS variables for the card frame heights, or '' when the defaults in donation-form.css apply. */
    public static function frame_style(): string {
        $out = [];
        foreach (['--orgdon-frame-h' => 'ORG_DONATION_FRAME_HEIGHT', '--orgdon-frame-h-mobile' => 'ORG_DONATION_FRAME_HEIGHT_MOBILE'] as $var => $c) {
            $v = orgdon_const($c);
            if (ctype_digit($v) && (int) $v >= 400 && (int) $v <= 3000) $out[] = $var . ':' . (int) $v . 'px';
        }
        return implode(';', $out);
    }

    private static function amount_cfg(string $name, float $default): float {
        $v = orgdon_const($name);
        return (is_numeric($v) && (float) $v > 0) ? (float) $v : $default;
    }

    public static function window(): int     { return Org_Rate_Limiter::cfg('ORG_DONATION_RL_WINDOW', self::RL_WINDOW); }
    public static function submit_max(): int { return Org_Rate_Limiter::cfg('ORG_DONATION_RL_SUBMIT_MAX', self::RL_SUBMIT_MAX); }
    public static function lp_max(): int     { return Org_Rate_Limiter::cfg('ORG_DONATION_RL_LP_MAX', self::RL_LP_MAX); }

    /**
     * Two Cardcom terminals (D39): the main one doesn't clear Diners cards, so a donor who ticks "כרטיס דיינרס" gets the card page
     * of the second terminal. Turn the option on in wp-config.php with define('ORG_DONATION_DINERS', true) once Salesforce has
     * the second terminal (Cardcom_Setting__mdt.Secondary_Terminal_Number__c).
     */
    public static function diners_enabled(): bool {
        return in_array(strtolower(orgdon_const('ORG_DONATION_DINERS')), ['1', 'true', 'yes', 'on'], true);
    }

    /** Salesforce terminal key for this request: 'Secondary' only when the option is on and the donor ticked the Diners box. */
    public static function terminal(array $in): string {
        return self::diners_enabled() && !empty($in['diners']) ? 'Secondary' : 'Primary';
    }

    private static function create_lp(string $terminal): array {
        $r = Org_SF_Client::post('/donations/lowprofile', [
            'purpose' => 'signup',
            'returnUrlBase' => home_url('/cardcom-return/'),
            'terminal' => $terminal,
        ]);
        if ($r['code'] !== 200 || empty($r['body']['url'])) throw new RuntimeException('LP');
        return $r['body'];
    }

    /** Renders the form only. The Cardcom card session is created later, by ajax_lp, once the form is valid (no token for an invalid form). */
    public static function render(): string {
        if (!orgdon_configured()) return '<p class="orgdon-error">הטופס אינו זמין כרגע.</p>';
        wp_enqueue_style('orgdon-form', ORGDON_URL . 'assets/donation-form.css', [], ORGDON_VER);
        wp_enqueue_script('orgdon-form', ORGDON_URL . 'assets/donation-form.js', [], ORGDON_VER, true);
        wp_localize_script('orgdon-form', 'ORGDON', [
            'ajaxUrl'       => admin_url('admin-ajax.php'),
            'nonce'         => wp_create_nonce('org_donation'),
            'cardcomOrigin' => orgdon_const('ORG_CARDCOM_ORIGIN', 'https://secure.cardcom.solutions'),
            'selfOrigin'    => ORG_DONATION_ORIGIN,
            'min' => self::min_amount(), 'max' => self::max_amount(),
            'diners' => self::diners_enabled(),
            'parentOrigin' => orgdon_const('ORG_DONATION_PARENT_ORIGIN', '*'),   // page that embeds the form (Elementor iframe)
        ]);
        ob_start();
        $frame_style = self::frame_style();
        $presets = self::presets(); $terms_url = orgdon_const('ORG_DONATION_TERMS_URL'); $diners = self::diners_enabled();
        include ORGDON_DIR . 'templates/form.php';
        return ob_get_clean();
    }

    /**
     * Creates (or renews) the Cardcom card session for a form that passes the same validation as the final submit, card excepted.
     * Invalid input → 422 and nothing is counted or created.
     */
    public static function ajax_lp(): void {
        check_ajax_referer('org_donation', 'nonce');
        $in = wp_unslash($_POST);
        $v = Org_Validator::signup($in, self::min_amount(), self::max_amount(), false);
        if ($v['errors']) wp_send_json_error(['fields' => $v['errors'], 'message' => 'נא לתקן את השדות המסומנים.'], 422);
        if (!Org_Rate_Limiter::allowed('lp', self::lp_max())) wp_send_json_error(['message' => self::MSG_TOO_MANY], 429);
        Org_Rate_Limiter::count('lp', self::window());
        try { $lp = self::create_lp(self::terminal($in)); }
        catch (Throwable $t) { wp_send_json_error(['message' => 'לא ניתן לטעון כעת את טופס התשלום.'], 502); }
        wp_send_json_success(['lpId' => $lp['lowProfileId'], 'url' => $lp['url'], 'expiresAt' => $lp['expiresAt'] ?? null]);
    }

    /** Salesforce returns VALIDATION fields as a list of API names (B4); the form expects field => message (spec-consistency N63). */
    public static function sf_fields(array $fields): array {
        $map = ['firstName' => 'first_name', 'lastName' => 'last_name', 'email' => 'email', 'phone' => 'phone', 'taxId' => 'tax_id',
                'shacharitAmount' => 'shacharit_amount', 'minchaAmount' => 'mincha_amount', 'frequency' => 'frequency', 'termsAccepted' => 'terms', 'lowProfileId' => 'card'];
        $out = [];
        foreach ($fields as $f) {
            if (is_string($f) && isset($map[$f])) $out[$map[$f]] = 'נא לבדוק שדה זה';
        }
        return $out;
    }

    private static function done_key(string $lp): string { return 'orgdon_done_' . md5(strtolower($lp)); }
    private static function lock_key(string $lp): string { return 'orgdon_lock_' . md5(strtolower($lp)); }

    /** One submission per LowProfileId at a time. add_option is a single INSERT on a unique key, so only one request wins. */
    private static function lock(string $lp): bool {
        $k = self::lock_key($lp);
        if (add_option($k, time(), '', false)) return true;
        if ((int) get_option($k) < time() - self::LOCK_TTL) {      // left behind by a crashed request
            delete_option($k);
            return add_option($k, time(), '', false);
        }
        return false;
    }

    public static function ajax_submit(): void {
        check_ajax_referer('org_donation', 'nonce');
        $in = wp_unslash($_POST);
        $lp = is_string($in['lp_id'] ?? null) && preg_match('/^[0-9a-fA-F-]{20,64}$/', $in['lp_id']) ? $in['lp_id'] : null;

        // Idempotency: a retry or double click for a LowProfileId already accepted gets the same answer, without a new call.
        if ($lp && get_transient(self::done_key($lp))) wp_send_json_success(['message' => self::MSG_THANKS]);
        if ($lp && !self::lock($lp)) wp_send_json_error(['message' => 'שומרים...', 'pending' => true], 409);

        [$ok, $data, $status] = self::submit_once($in, $lp);
        if ($lp) delete_option(self::lock_key($lp));          // before sending: wp_send_json_* ends the request
        if ($ok) wp_send_json_success($data);
        wp_send_json_error($data, $status);
    }

    /** @return array{0:bool,1:array,2:int} */
    private static function submit_once(array $in, ?string $lp): array {
        if (!Org_Rate_Limiter::allowed('submit', self::submit_max())) return [false, ['message' => 'בוצעו ניסיונות רבים. נסו שוב מאוחר יותר.'], 429];
        $v = Org_Validator::signup($in, self::min_amount(), self::max_amount());
        if ($v['errors']) return [false, ['fields' => $v['errors'], 'message' => 'נא להשלים את פרטי הטופס וללחוץ "סיום".'], 422];
        Org_Rate_Limiter::count('submit', self::window());     // only real (valid) submissions are counted
        $payload = $v['data'] + ['clientIp' => Org_Rate_Limiter::ip(), 'terminal' => self::terminal($in)];
        try { $r = Org_SF_Client::post('/donations/pledge', $payload); }
        catch (Throwable $t) { return [false, ['message' => 'אירעה שגיאה בשמירה. נסו שוב. אם הבעיה חוזרת – פנו אלינו.'], 502]; }
        $err = $r['body']['error'] ?? '';
        if ($r['code'] === 200 || $err === 'LP_ALREADY_USED') {
            set_transient(self::done_key($v['data']['lowProfileId']), 1, self::DONE_TTL);
            return $r['code'] === 200
                ? [true, ['message' => self::MSG_THANKS], 200]
                : [false, ['message' => 'ההוראה כבר נקלטה. תודה!', 'done' => true], 409];
        }
        if ($err === 'VALIDATION') return [false, ['fields' => self::sf_fields($r['body']['fields'] ?? []), 'message' => 'נא לתקן את השדות המסומנים.'], 422];
        return [false, ['message' => 'אירעה שגיאה בשמירה. נסו שוב. אם הבעיה חוזרת – פנו אלינו.'], 502];
    }
}
