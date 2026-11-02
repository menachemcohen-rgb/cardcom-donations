<?php
if (!defined('ABSPATH')) exit;
final class Org_Return_Endpoint {
    public static function register(): void {
        add_rewrite_rule('^cardcom-return/?$', 'index.php?orgdon_return=1', 'top');
        add_filter('query_vars', fn($v) => array_merge($v, ['orgdon_return']));
        add_action('template_redirect', [self::class, 'serve'], 0);
    }
    public static function serve(): void {
        if (!get_query_var('orgdon_return')) return;
        nocache_headers();
        header('Content-Type: text/html; charset=utf-8');
        header("Content-Security-Policy: default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; frame-ancestors https://secure.cardcom.solutions " . ORG_DONATION_ORIGIN);
        $status = (($_GET['s'] ?? '') === 'ok') ? 'ok' : 'fail';
        $origin = esc_js(ORG_DONATION_ORIGIN);
        $text = $status === 'ok' ? 'הכרטיס נשמר. רגע...' : 'פרטי הכרטיס לא נקלטו.';
        echo "<!doctype html><html lang=\"he\" dir=\"rtl\"><meta charset=\"utf-8\"><body style=\"font-family:Arial;text-align:center;padding:24px\">"
           . esc_html($text)
           . "<script>try{window.parent.postMessage({type:'orgdon-cardcom',status:'$status'},'$origin');}catch(e){}</script></body></html>";
        exit;
    }
}
