<?php
if (!defined('ABSPATH')) exit;

final class Org_Portal {
    const TOKEN_RE = '/^[A-Za-z0-9_\-\.]{20,600}$/';
    const LP_RE    = '/^[A-Za-z0-9\-]{10,64}$/';

    public static function register(): void {
        add_shortcode('org_donor_portal', [self::class, 'render']);
        foreach (['context', 'amount', 'card', 'card_status', 'stop'] as $a) {
            add_action("wp_ajax_org_portal_$a",        [self::class, "ajax_$a"]);
            add_action("wp_ajax_nopriv_org_portal_$a", [self::class, "ajax_$a"]);
        }
    }

    public static function contact_line(): string {
        $p = orgdon_const('ORG_DONATION_CONTACT_PHONE');
        $e = orgdon_const('ORG_DONATION_CONTACT_EMAIL');
        $parts = array_filter([$p, $e]);
        return $parts ? 'לפרטים פנו אלינו: ' . implode(' · ', $parts) : 'לפרטים פנו אלינו.';
    }

    private static function invalid_msg(): string { return 'הקישור אינו תקף. ' . self::contact_line(); }

    /** Shortcode: renders the shell; data is loaded by JS via org_portal_context (so the page itself is cache-safe). */
    public static function render(): string {
        if (!orgdon_configured()) return '<p class="orgdon-error">הדף אינו זמין כרגע.</p>';
        $token  = isset($_GET['t']) ? (string) wp_unslash($_GET['t']) : '';
        $action = isset($_GET['a']) ? sanitize_key(wp_unslash($_GET['a'])) : '';
        if ($token !== '' && !preg_match(self::TOKEN_RE, $token)) $token = '';
        if (!in_array($action, ['card', 'amount'], true)) $action = '';
        wp_enqueue_style('orgdon-form', ORGDON_URL . 'assets/donation-form.css', [], ORGDON_VER);
        wp_enqueue_script('orgdon-portal', ORGDON_URL . 'assets/donor-portal.js', [], ORGDON_VER, true);
        wp_localize_script('orgdon-portal', 'ORGDON_PORTAL', [
            'ajaxUrl'       => admin_url('admin-ajax.php'),
            'nonce'         => wp_create_nonce('org_portal'),
            'token'         => $token,             // removed from the URL by JS immediately
            'action'        => $action,
            'cardcomOrigin' => orgdon_const('ORG_CARDCOM_ORIGIN', 'https://secure.cardcom.solutions'),
            'selfOrigin'    => ORG_DONATION_ORIGIN,
            'invalidMsg'    => self::invalid_msg(),
            'contactLine'   => self::contact_line(),
        ]);
        ob_start();
        include ORGDON_DIR . 'templates/portal.php';
        return ob_get_clean();
    }

    /** Common guard for every AJAX call. Returns the sanitized token. */
    private static function guard(string $bucket = 'portal', int $max = 20, int $win = 600): string {
        check_ajax_referer('org_portal', 'nonce');
        if (!Org_Rate_Limiter::hit($bucket, $max, $win)) {
            wp_send_json_error(['message' => 'בוצעו ניסיונות רבים. נסו שוב בעוד מספר דקות.'], 429);
        }
        $t = isset($_POST['token']) ? (string) wp_unslash($_POST['token']) : '';
        if (!preg_match(self::TOKEN_RE, $t)) wp_send_json_error(['message' => self::invalid_msg(), 'invalid' => true], 403);
        return $t;
    }

    private static function call(string $path, array $payload): array {
        try { return Org_SF_Client::post($path, $payload + ['clientIp' => Org_Rate_Limiter::ip()]); }
        catch (Throwable $t) { wp_send_json_error(['message' => 'אירעה שגיאה זמנית. נסו שוב בעוד מספר דקות.'], 502); }
    }

    private static function fail_generic(array $r): void {
        if ($r['code'] === 403) wp_send_json_error(['message' => self::invalid_msg(), 'invalid' => true], 403);
        if ($r['code'] === 429) wp_send_json_error(['message' => 'בוצעו ניסיונות רבים היום. נסו שוב מחר.'], 429);
        wp_send_json_error(['message' => 'אירעה שגיאה זמנית. נסו שוב בעוד מספר דקות.'], 502);
    }

    public static function ajax_context(): void {
        $t = self::guard();
        $payload = ['token' => $t];
        if (!empty($_POST['verifyCode'])) $payload['verifyCode'] = preg_replace('/\D/', '', (string) wp_unslash($_POST['verifyCode']));
        $r = self::call('/donor/context', $payload);
        if ($r['code'] === 200) {
            $b = $r['body'];
            wp_send_json_success([
                'action'    => in_array($b['action'] ?? '', ['card', 'amount'], true) ? $b['action'] : 'amount',
                'firstName' => (string) ($b['firstName'] ?? ''),
                'amount'    => (float) ($b['amount'] ?? 0),
                'frequency' => ($b['frequency'] ?? '') === 'TwiceDaily' ? 'פעמיים ביום' : 'פעם ביום',
                'last4'     => isset($b['last4']) && preg_match('/^\d{4}$/', (string) $b['last4']) ? $b['last4'] : null,
                'exp'       => isset($b['expMMYY']) && preg_match('/^\d{4}$/', (string) $b['expMMYY'])
                                 ? substr($b['expMMYY'], 0, 2) . '/' . substr($b['expMMYY'], 2, 2) : null,
                'min'       => (float) ($b['minAmount'] ?? 1),
                'max'       => (float) ($b['maxAmount'] ?? 50),
                'presets'   => array_map('floatval', (array) ($b['presets'] ?? [1, 3, 5, 10])),
            ]);
        }
        $err = $r['body']['error'] ?? '';
        if ($err === 'VERIFY_REQUIRED') wp_send_json_error(['verify' => true, 'message' => 'לאימות, נא להקליד את 4 הספרות האחרונות של הטלפון שמסרת.'], 401);
        if ($err === 'VERIFY_FAILED')   wp_send_json_error(['verify' => true, 'message' => 'הספרות אינן תואמות. נסו שוב.'], 401);
        if ($err === 'LOCKED')          wp_send_json_error(['message' => 'בוצעו ניסיונות רבים. נסו שוב בעוד שעה.'], 429);
        self::fail_generic($r);
    }

    public static function ajax_amount(): void {
        $t = self::guard();
        $raw = isset($_POST['amount']) ? str_replace(',', '.', (string) wp_unslash($_POST['amount'])) : '';
        if (!preg_match('/^\d{1,4}(\.\d{1,2})?$/', $raw)) wp_send_json_error(['message' => 'נא להזין סכום תקין.', 'field' => 'amount'], 422);
        $r = self::call('/donor/amount', ['token' => $t, 'amount' => (float) $raw]);
        if ($r['code'] === 200) {
            $a = number_format((float) ($r['body']['amount'] ?? $raw), 2);
            $msg = !empty($r['body']['changed'])
                ? "הסכום עודכן ל-$a ₪ לכל חיוב, החל מהחיוב הבא. תודה!"
                : "הסכום נשאר $a ₪ לכל חיוב.";
            wp_send_json_success(['message' => $msg, 'amount' => (float) $a]);
        }
        if (($r['body']['error'] ?? '') === 'AMOUNT_RANGE') wp_send_json_error(['message' => 'הסכום אינו בטווח המותר.', 'field' => 'amount'], 422);
        self::fail_generic($r);
    }

    /** Card replacement; optional `amount` = new amount per charge, applied by Salesforce only once the new card is saved. */
    public static function ajax_card(): void {
        $t = self::guard('card', 5, 3600);
        $payload = ['token' => $t, 'returnUrlBase' => home_url('/cardcom-return/')];
        $raw = isset($_POST['amount']) ? str_replace(',', '.', trim((string) wp_unslash($_POST['amount']))) : '';
        if ($raw !== '') {
            if (!preg_match('/^\d{1,4}(\.\d{1,2})?$/', $raw)) wp_send_json_error(['message' => 'נא להזין סכום תקין.', 'field' => 'amount'], 422);
            $payload['amount'] = (float) $raw;
        }
        $r = self::call('/donor/card', $payload);
        if (($r['body']['error'] ?? '') === 'AMOUNT_RANGE') wp_send_json_error(['message' => 'הסכום אינו בטווח המותר.', 'field' => 'amount'], 422);
        if ($r['code'] === 200 && !empty($r['body']['url']) && preg_match(self::LP_RE, (string) ($r['body']['lowProfileId'] ?? ''))) {
            wp_send_json_success(['lpId' => $r['body']['lowProfileId'], 'url' => esc_url_raw($r['body']['url']), 'expiresAt' => $r['body']['expiresAt'] ?? null]);
        }
        self::fail_generic($r);
    }

    public static function ajax_card_status(): void {
        $t = self::guard('status', 40, 600);     // polling bucket (every 3 s × 60 s = 20 calls)
        $lp = isset($_POST['lpId']) ? (string) wp_unslash($_POST['lpId']) : '';
        if (!preg_match(self::LP_RE, $lp)) wp_send_json_error(['message' => 'שגיאה.'], 400);
        $r = self::call('/donor/card/status', ['token' => $t, 'lowProfileId' => $lp]);
        if ($r['code'] === 200) {
            $st = in_array($r['body']['status'] ?? '', ['Pending', 'Completed', 'Failed', 'Expired'], true) ? $r['body']['status'] : 'Pending';
            $l4 = isset($r['body']['last4']) && preg_match('/^\d{4}$/', (string) $r['body']['last4']) ? $r['body']['last4'] : null;
            $amount = isset($r['body']['amount']) && is_numeric($r['body']['amount']) ? (float) $r['body']['amount'] : null;
            wp_send_json_success(['status' => $st, 'last4' => $l4, 'amount' => $amount]);
        }
        self::fail_generic($r);
    }

    /** The donor stops the pledge (either link). Salesforce sets it to Stopped and emails staff; resuming is a staff action. */
    public static function ajax_stop(): void {
        $t = self::guard('stop', 5, 3600);
        if (empty($_POST['confirm'])) wp_send_json_error(['message' => 'שגיאה.'], 400);   // the page always asks first
        $r = self::call('/donor/stop', ['token' => $t]);
        if ($r['code'] === 200) {
            wp_send_json_success(['message' => 'הוראת התרומה הופסקה. לא יבוצעו חיובים נוספים. תודה רבה על תרומתך!']);
        }
        self::fail_generic($r);
    }
}
