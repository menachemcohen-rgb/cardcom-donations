<?php
if (!defined('ABSPATH')) exit;
final class Org_Return_Endpoint {
    /**
     * Extra sites allowed to show our pages in an iframe (N122), from ORG_DONATION_FRAME_ANCESTORS in wp-config.php,
     * e.g. 'https://crm.ato770.com https://crm-dev.ato770.com'. Only https origins (scheme + host [+ port]) are kept.
     * @return string space-separated origins, '' when not set
     */
    public static function extra_frame_ancestors(): string {
        $out = [];
        foreach (preg_split('/[\s,]+/', orgdon_const('ORG_DONATION_FRAME_ANCESTORS'), -1, PREG_SPLIT_NO_EMPTY) as $o) {
            $o = strtolower(rtrim($o, '/'));
            if (preg_match('#^https://[a-z0-9]([a-z0-9.-]*[a-z0-9])?(:\d{1,5})?$#', $o)) $out[$o] = true;
        }
        return implode(' ', array_keys($out));
    }

    /** frame-ancestors value with the extra sites appended. */
    public static function frame_ancestors(string $base): string {
        $extra = self::extra_frame_ancestors();
        return 'frame-ancestors ' . $base . ($extra === '' ? '' : ' ' . $extra);
    }

    public static function register(): void {
        add_rewrite_rule('^cardcom-return/?$', 'index.php?orgdon_return=1', 'top');
        add_filter('query_vars', fn($v) => array_merge($v, ['orgdon_return']));
        add_action('template_redirect', [self::class, 'serve'], 0);
    }
    // Every ancestor is checked, so a form shown inside the CRM needs the CRM here too (N122).
    public static function serve(): void {
        if (!get_query_var('orgdon_return')) return;
        nocache_headers();
        $self = orgdon_const('ORG_DONATION_ORIGIN');          // never fatal on a missing constant (the parent then ignores the message)
        header('Content-Type: text/html; charset=utf-8');
        header("Content-Security-Policy: default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; " . self::frame_ancestors('https://secure.cardcom.solutions ' . $self));
        $status = (($_GET['s'] ?? '') === 'ok') ? 'ok' : 'fail';
        $origin = esc_js($self);
        $text = $status === 'ok' ? 'הכרטיס נשמר. רגע...' : 'פרטי הכרטיס לא נקלטו.';
        echo "<!doctype html><html lang=\"he\" dir=\"rtl\"><meta charset=\"utf-8\"><body style=\"font-family:Arial;text-align:center;padding:24px\">"
           . esc_html($text)
           . "<script>try{window.parent.postMessage({type:'orgdon-cardcom',status:'$status'},'$origin');}catch(e){}</script></body></html>";
        exit;
    }
}
