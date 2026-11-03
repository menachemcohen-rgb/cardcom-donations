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

    /** A positive integer wp-config.php constant, or the default (missing, empty, zero or negative values are ignored). */
    public static function cfg(string $constant, int $default): int {
        if (!defined($constant)) return $default;
        $v = (int) constant($constant);
        return $v > 0 ? $v : $default;
    }

    private static function key(string $bucket): string {
        return 'orgdon_rl_' . $bucket . '_' . md5(self::ip());
    }

    /** Current window: ['n' => count, 'until' => unix time the window ends]. Expired or legacy (int) values start a new window. */
    private static function state(string $bucket): array {
        $v = get_transient(self::key($bucket));
        if (!is_array($v) || (int) ($v['until'] ?? 0) <= time()) return ['n' => 0, 'until' => 0];
        return ['n' => (int) ($v['n'] ?? 0), 'until' => (int) $v['until']];
    }

    /** true if one more request fits in the current window. Does not count anything. */
    public static function allowed(string $bucket, int $max): bool {
        return self::state($bucket)['n'] < $max;
    }

    /**
     * Counts one request. The window is fixed: it starts with the first counted request and is not extended by later ones,
     * so a blocked visitor is free again at most $windowSec after their first attempt.
     */
    public static function count(string $bucket, int $windowSec): void {
        $s = self::state($bucket);
        if ($s['until'] === 0) $s['until'] = time() + $windowSec;
        $s['n']++;
        set_transient(self::key($bucket), $s, max(1, $s['until'] - time()));
    }

    /** allowed() + count() in one step; true if allowed. */
    public static function hit(string $bucket, int $max, int $windowSec): bool {
        if (!self::allowed($bucket, $max)) return false;
        self::count($bucket, $windowSec);
        return true;
    }
}
