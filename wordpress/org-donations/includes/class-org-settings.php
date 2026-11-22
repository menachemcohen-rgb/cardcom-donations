<?php
if (!defined('ABSPATH')) exit;

/**
 * Amount buttons and min/max per charge (N123). Salesforce is the source: GET /donations/settings returns
 * Cardcom_Setting__mdt.Default Amount_Presets__c / Min_Amount__c / Max_Amount__c.
 * Order: fresh copy (transient, 10 minutes) → Salesforce → last good copy (option, no expiry) →
 * ORG_DONATION_PRESETS / ORG_DONATION_MIN_AMOUNT / ORG_DONATION_MAX_AMOUNT → the plugin defaults.
 */
final class Org_Settings {
    const TRANSIENT = 'orgdon_sf_settings';          // fresh copy from Salesforce
    const LAST_OPTION = 'orgdon_sf_settings_last';   // last good copy, used when Salesforce can't be reached
    const RETRY = 'orgdon_sf_settings_retry';        // after a failed call, wait before asking Salesforce again
    const TTL = 600;
    const RETRY_TTL = 60;

    const MIN = 1; const MAX = 40;
    const PRESETS = [1, 2, 3, 5, 10];

    /** @var array{presets:array,min:float,max:float,source:string}|null per-request copy */
    private static ?array $memo = null;

    /** @return array{presets:array,min:float,max:float,source:string} */
    public static function get(): array {
        if (self::$memo !== null) return self::$memo;
        $v = get_transient(self::TRANSIENT);
        if (is_array($v) && self::valid($v)) return self::$memo = $v + ['source' => 'salesforce'];
        if (!get_transient(self::RETRY)) {
            $v = self::fetch();
            if ($v !== null) {
                set_transient(self::TRANSIENT, $v, self::TTL);
                update_option(self::LAST_OPTION, $v, false);
                return self::$memo = $v + ['source' => 'salesforce'];
            }
            set_transient(self::RETRY, 1, self::RETRY_TTL);
        }
        $last = get_option(self::LAST_OPTION);
        if (is_array($last) && self::valid($last)) return self::$memo = $last + ['source' => 'last'];
        return self::$memo = self::from_config();
    }

    /** "רענון הגדרות מסיילספורס": drops the fresh copy, so the next page asks Salesforce again. */
    public static function refresh(): void {
        delete_transient(self::TRANSIENT);
        delete_transient(self::RETRY);
        self::$memo = null;
    }

    /** Clears the per-request copy (tests). */
    public static function reset(): void { self::$memo = null; }

    /** @return array{presets:array,min:float,max:float}|null */
    private static function fetch(): ?array {
        try {
            $r = Org_SF_Client::get('/donations/settings');
        } catch (Throwable $t) {
            error_log('[orgdon] settings from Salesforce failed: ' . $t->getMessage());
            return null;
        }
        if (($r['code'] ?? 0) !== 200) {
            error_log('[orgdon] settings from Salesforce: HTTP ' . ($r['code'] ?? 0));
            return null;
        }
        $b = $r['body'] ?? [];
        $v = [
            'presets' => array_values(array_filter((array) ($b['presets'] ?? []), 'is_numeric')),
            'min' => is_numeric($b['minAmount'] ?? null) ? (float) $b['minAmount'] : 0.0,
            'max' => is_numeric($b['maxAmount'] ?? null) ? (float) $b['maxAmount'] : 0.0,
        ];
        if (!self::valid($v)) {
            error_log('[orgdon] settings from Salesforce: unusable answer');
            return null;
        }
        return $v;
    }

    private static function valid(array $v): bool {
        return isset($v['presets'], $v['min'], $v['max']) && is_array($v['presets'])
            && is_numeric($v['min']) && is_numeric($v['max']) && $v['min'] > 0 && $v['max'] >= $v['min'];
    }

    /** wp-config.php constants, else the defaults. */
    private static function from_config(): array {
        $num = function (string $c, float $d): float { $x = orgdon_const($c); return (is_numeric($x) && (float) $x > 0) ? (float) $x : $d; };
        $min = $num('ORG_DONATION_MIN_AMOUNT', self::MIN);
        $max = $num('ORG_DONATION_MAX_AMOUNT', self::MAX);
        if ($max < $min) { $min = self::MIN; $max = self::MAX; }
        $raw = orgdon_const('ORG_DONATION_PRESETS');
        $presets = $raw === '' ? self::PRESETS : array_map('trim', explode(',', $raw));
        $hasConst = $raw !== '' || orgdon_const('ORG_DONATION_MIN_AMOUNT') !== '' || orgdon_const('ORG_DONATION_MAX_AMOUNT') !== '';
        return ['presets' => $presets, 'min' => $min, 'max' => $max, 'source' => $hasConst ? 'config' : 'default'];
    }
}
