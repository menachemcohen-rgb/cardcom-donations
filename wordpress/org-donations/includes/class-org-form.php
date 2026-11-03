<?php
if (!defined('ABSPATH')) exit;

final class Org_Form {
    const MIN = 1; const MAX = 50;               // mirror of Cardcom_Setting__mdt (Q5) — server SF re-validates
    const PRESETS = [1, 3, 5, 10];

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

    public static function window(): int     { return Org_Rate_Limiter::cfg('ORG_DONATION_RL_WINDOW', self::RL_WINDOW); }
    public static function submit_max(): int { return Org_Rate_Limiter::cfg('ORG_DONATION_RL_SUBMIT_MAX', self::RL_SUBMIT_MAX); }
    public static function lp_max(): int     { return Org_Rate_Limiter::cfg('ORG_DONATION_RL_LP_MAX', self::RL_LP_MAX); }

    private static function create_lp(): array {
        $r = Org_SF_Client::post('/donations/lowprofile', [
            'purpose' => 'signup',
            'returnUrlBase' => home_url('/cardcom-return/'),
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
            'min' => self::MIN, 'max' => self::MAX,
        ]);
        ob_start();
        $presets = self::PRESETS; $terms_url = orgdon_const('ORG_DONATION_TERMS_URL');
        include ORGDON_DIR . 'templates/form.php';
        return ob_get_clean();
    }

    /**
     * Creates (or renews) the Cardcom card session for a form that passes the same validation as the final submit, card excepted.
     * Invalid input → 422 and nothing is counted or created.
     */
    public static function ajax_lp(): void {
        check_ajax_referer('org_donation', 'nonce');
        $v = Org_Validator::signup(wp_unslash($_POST), self::MIN, self::MAX, false);
        if ($v['errors']) wp_send_json_error(['fields' => $v['errors'], 'message' => 'נא לתקן את השדות המסומנים.'], 422);
        if (!Org_Rate_Limiter::allowed('lp', self::lp_max())) wp_send_json_error(['message' => self::MSG_TOO_MANY], 429);
        Org_Rate_Limiter::count('lp', self::window());
        try { $lp = self::create_lp(); }
        catch (Throwable $t) { wp_send_json_error(['message' => 'לא ניתן לטעון כעת את טופס התשלום.'], 502); }
        wp_send_json_success(['lpId' => $lp['lowProfileId'], 'url' => $lp['url'], 'expiresAt' => $lp['expiresAt'] ?? null]);
    }

    /** Salesforce returns VALIDATION fields as a list of API names (B4); the form expects field => message (spec-consistency N63). */
    public static function sf_fields(array $fields): array {
        $map = ['firstName' => 'first_name', 'lastName' => 'last_name', 'email' => 'email', 'phone' => 'phone', 'taxId' => 'tax_id',
                'amount' => 'amount', 'frequency' => 'frequency', 'termsAccepted' => 'terms', 'lowProfileId' => 'card'];
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
        $v = Org_Validator::signup($in, self::MIN, self::MAX);
        if ($v['errors']) return [false, ['fields' => $v['errors'], 'message' => 'נא להשלים את פרטי הטופס וללחוץ "סיום".'], 422];
        Org_Rate_Limiter::count('submit', self::window());     // only real (valid) submissions are counted
        $payload = $v['data'] + ['clientIp' => Org_Rate_Limiter::ip()];
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
