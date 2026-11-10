<?php
if (!defined('ABSPATH')) exit;

final class Org_Validator {
    public static function phone(string $raw): ?string {
        // Same rules as Salesforce ContactMatcher.normPhone: +972 / 972 / 00972 prefixes, missing leading 0 (spec-consistency N61).
        $d = preg_replace('/\D+/', '', $raw);
        if (str_starts_with($d, '00972')) $d = substr($d, 5);
        elseif (str_starts_with($d, '972')) $d = substr($d, 3);
        if ($d !== '' && $d[0] !== '0') $d = '0' . $d;
        return preg_match('/^05\d{8}$/', $d) ? $d : null;
    }
    public static function il_id(string $raw): ?string {
        $id = preg_replace('/\D+/', '', $raw);
        if ($id === '' || strlen($id) > 9) return null;
        $id = str_pad($id, 9, '0', STR_PAD_LEFT);
        $sum = 0;
        for ($i = 0; $i < 9; $i++) { $n = (int)$id[$i] * (($i % 2) + 1); $sum += $n > 9 ? $n - 9 : $n; }
        return $sum % 10 === 0 ? $id : null;
    }
    /** Prayers charged by each frequency (Salesforce API values). */
    const PRAYERS = [
        'TwiceDaily' => ['shacharit', 'mincha'],   // שחרית ומנחה
        'OnceDaily'  => ['shacharit'],             // רק שחרית
        'MinchaOnly' => ['mincha'],                // רק מנחה
    ];

    /** Same rule for every amount: min..max, at most 2 decimals. Returns the amount rounded to 2 decimals, or null if invalid. */
    public static function amount($raw, float $min, float $max): ?float {
        $s = str_replace(',', '.', trim((string) $raw));
        if (!preg_match('/^\d+(\.\d{1,2})?$/', $s)) return null;
        $a = round((float) $s, 2);
        return ($a < $min || $a > $max) ? null : $a;
    }

    /**
     * @param bool $requireCard false for the check before the Cardcom session is created (no LowProfileId yet)
     * @return array{data:array, errors:array<string,string>}
     */
    public static function signup(array $in, float $min, float $max, bool $requireCard = true): array {
        $e = []; $d = [];
        $d['firstName'] = trim(sanitize_text_field($in['first_name'] ?? ''));
        $d['lastName']  = trim(sanitize_text_field($in['last_name'] ?? ''));
        $d['email']     = sanitize_email($in['email'] ?? '');
        $d['phone']     = self::phone($in['phone'] ?? '');
        $tax            = trim($in['tax_id'] ?? '');
        $d['taxId']     = $tax === '' ? null : self::il_id($tax);
        $freq           = is_string($in['frequency'] ?? null) && isset(self::PRAYERS[$in['frequency']]) ? $in['frequency'] : null;
        $d['frequency'] = $freq;
        $prayers        = $freq ? self::PRAYERS[$freq] : [];
        $raw = ['shacharit' => $in['shacharit_amount'] ?? '', 'mincha' => $in['mincha_amount'] ?? ''];
        if ($freq === 'TwiceDaily' && !empty($in['same_amount'])) $raw['mincha'] = $raw['shacharit'];   // "אותו סכום בשחרית ובמנחה"
        $amountMsg = sprintf('סכום לא תקין – נא לבחור סכום בין %s ל-%s ₪', $min, $max);
        foreach (['shacharit', 'mincha'] as $p) {
            $d[$p . 'Amount'] = null;
            if (!in_array($p, $prayers, true)) continue;      // not charged: sent as null
            $d[$p . 'Amount'] = self::amount($raw[$p], $min, $max);
            if ($d[$p . 'Amount'] === null) $e[$p . '_amount'] = $amountMsg;
        }
        $d['termsAccepted'] = !empty($in['terms']);
        $d['lowProfileId']  = preg_match('/^[0-9a-fA-F-]{20,64}$/', $in['lp_id'] ?? '') ? $in['lp_id'] : null;

        if ($d['firstName'] === '' || mb_strlen($d['firstName']) > 40) $e['first_name'] = 'נא להזין שם פרטי';
        if ($d['lastName'] === ''  || mb_strlen($d['lastName']) > 80)  $e['last_name']  = 'נא להזין שם משפחה';
        if (!is_email($d['email']) || strlen($d['email']) > 80)       $e['email']      = 'נא להזין כתובת אימייל תקינה';
        if (!$d['phone'])                                              $e['phone']      = 'נא להזין מספר נייד ישראלי תקין';
        if ($tax !== '' && !$d['taxId'])                               $e['tax_id']     = 'מספר תעודת הזהות אינו תקין';
        if (!$d['frequency'])                                          $e['frequency']  = 'נא לבחור תדירות';
        if (!$d['termsAccepted'])                                      $e['terms']      = 'יש לאשר את תנאי ההוראה';
        if ($requireCard && !$d['lowProfileId'])                       $e['card']       = 'נא להזין את פרטי הכרטיס ולשמור';
        return ['data' => $d, 'errors' => $e];
    }
}
