<?php
if (!defined('ABSPATH')) exit;
final class Org_Rate_Limiter {
    public static function ip(): string {
        // CF-Connecting-IP is trusted only when wp-config.php says the site is proxied by Cloudflare (Q11); otherwise any client
        // could send the header and dodge the limits (spec-consistency N62).
        $behind_cf = defined('ORG_BEHIND_CLOUDFLARE') && ORG_BEHIND_CLOUDFLARE;
        $ip = ($behind_cf ? ($_SERVER['HTTP_CF_CONNECTING_IP'] ?? null) : null) ?? $_SERVER['REMOTE_ADDR'] ?? '0.0.0.0';
        return filter_var($ip, FILTER_VALIDATE_IP) ? $ip : '0.0.0.0';
    }
    /** true if allowed */
    public static function hit(string $bucket, int $max, int $windowSec): bool {
        $k = 'orgdon_rl_' . $bucket . '_' . md5(self::ip());
        $n = (int) get_transient($k);
        if ($n >= $max) return false;
        set_transient($k, $n + 1, $windowSec);
        return true;
    }
}
