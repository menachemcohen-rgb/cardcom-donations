<?php
if (!defined('ABSPATH')) exit;

final class Org_Form {
    const MIN = 1; const MAX = 50;               // mirror of Cardcom_Setting__mdt (Q5) — server SF re-validates
    const PRESETS = [1, 3, 5, 10];

    public static function register(): void {
        add_shortcode('org_donation_form', [self::class, 'render']);
        foreach (['org_donation_submit', 'org_donation_refresh'] as $a) {
            add_action("wp_ajax_$a",        [self::class, str_replace('org_donation_', 'ajax_', $a)]);
            add_action("wp_ajax_nopriv_$a", [self::class, str_replace('org_donation_', 'ajax_', $a)]);
        }
    }

    private static function create_lp(): array {
        $r = Org_SF_Client::post('/donations/lowprofile', [
            'purpose' => 'signup',
            'returnUrlBase' => home_url('/cardcom-return/'),
        ]);
        if ($r['code'] !== 200 || empty($r['body']['url'])) throw new RuntimeException('LP');
        return $r['body'];
    }

    public static function render(): string {
        if (!orgdon_configured()) return '<p class="orgdon-error">הטופס אינו זמין כרגע.</p>';
        wp_enqueue_style('orgdon-form', ORGDON_URL . 'assets/donation-form.css', [], ORGDON_VER);
        wp_enqueue_script('orgdon-form', ORGDON_URL . 'assets/donation-form.js', [], ORGDON_VER, true);
        $lp = null; $error = null;
        if (!Org_Rate_Limiter::hit('lp', 10, 600)) {
            $error = 'בוצעו ניסיונות רבים. נסו שוב בעוד מספר דקות.';
        } else {
            try { $lp = self::create_lp(); }
            catch (Throwable $t) { $error = 'לא ניתן לטעון כעת את טופס התשלום. אנא רעננו את העמוד או נסו מאוחר יותר.'; }
        }
        wp_localize_script('orgdon-form', 'ORGDON', [
            'ajaxUrl'       => admin_url('admin-ajax.php'),
            'nonce'         => wp_create_nonce('org_donation'),
            'lpId'          => $lp['lowProfileId'] ?? null,
            'expiresAt'     => $lp['expiresAt'] ?? null,
            'cardcomOrigin' => ORG_CARDCOM_ORIGIN,
            'selfOrigin'    => ORG_DONATION_ORIGIN,
            'min' => self::MIN, 'max' => self::MAX,
        ]);
        ob_start();
        $presets = self::PRESETS; $iframe_url = $lp['url'] ?? null; $terms_url = ORG_DONATION_TERMS_URL;
        include ORGDON_DIR . 'templates/form.php';
        return ob_get_clean();
    }

    public static function ajax_refresh(): void {
        check_ajax_referer('org_donation', 'nonce');
        if (!Org_Rate_Limiter::hit('lp', 10, 600)) wp_send_json_error(['message' => 'בוצעו ניסיונות רבים. נסו שוב בעוד מספר דקות.'], 429);
        try { $lp = self::create_lp(); }
        catch (Throwable $t) { wp_send_json_error(['message' => 'לא ניתן לטעון כעת את טופס התשלום.'], 502); }
        wp_send_json_success(['lpId' => $lp['lowProfileId'], 'url' => $lp['url'], 'expiresAt' => $lp['expiresAt']]);
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

    public static function ajax_submit(): void {
        check_ajax_referer('org_donation', 'nonce');
        if (!Org_Rate_Limiter::hit('submit', 5, 600)) wp_send_json_error(['message' => 'בוצעו ניסיונות רבים. נסו שוב מאוחר יותר.'], 429);
        $v = Org_Validator::signup(wp_unslash($_POST), self::MIN, self::MAX);
        if ($v['errors']) wp_send_json_error(['fields' => $v['errors'], 'message' => 'נא להשלים את פרטי הטופס וללחוץ "סיום".'], 422);
        $payload = $v['data'] + ['clientIp' => Org_Rate_Limiter::ip()];
        try { $r = Org_SF_Client::post('/donations/pledge', $payload); }
        catch (Throwable $t) { wp_send_json_error(['message' => 'אירעה שגיאה בשמירה. נסו שוב. אם הבעיה חוזרת – פנו אלינו.'], 502); }
        if ($r['code'] === 200) wp_send_json_success(['message' => 'תודה! הוראת התרומה התקבלה ונמצאת באימות. החיוב הראשון יתבצע במועד החיוב הקרוב.']);
        $err = $r['body']['error'] ?? '';
        if ($err === 'VALIDATION')      wp_send_json_error(['fields' => self::sf_fields($r['body']['fields'] ?? []), 'message' => 'נא לתקן את השדות המסומנים.'], 422);
        if ($err === 'LP_ALREADY_USED') wp_send_json_error(['message' => 'ההוראה כבר נקלטה. תודה!', 'done' => true], 409);
        wp_send_json_error(['message' => 'אירעה שגיאה בשמירה. נסו שוב. אם הבעיה חוזרת – פנו אלינו.'], 502);
    }
}
