<?php
if (!defined('ABSPATH')) exit;

final class Org_SF_Client {
    const TOKEN_TRANSIENT = 'orgdon_sf_token';

    private static function token(bool $force = false): string {
        if (!$force && ($t = get_transient(self::TOKEN_TRANSIENT))) return $t;
        $res = wp_remote_post(ORG_SF_LOGIN_URL . '/services/oauth2/token', [
            'timeout' => 10,
            'body'    => [
                'grant_type'    => 'client_credentials',
                'client_id'     => ORG_SF_CLIENT_ID,
                'client_secret' => ORG_SF_CLIENT_SECRET,
            ],
        ]);
        if (is_wp_error($res) || wp_remote_retrieve_response_code($res) !== 200) {
            error_log('[orgdon] SF token failure: ' . (is_wp_error($res) ? $res->get_error_message() : wp_remote_retrieve_response_code($res)));
            throw new RuntimeException('SF_AUTH');
        }
        $j = json_decode(wp_remote_retrieve_body($res), true);
        set_transient(self::TOKEN_TRANSIENT, $j['access_token'], 50 * MINUTE_IN_SECONDS);
        if (!empty($j['instance_url'])) set_transient('orgdon_sf_instance', $j['instance_url'], DAY_IN_SECONDS);
        return $j['access_token'];
    }

    /** @return array{code:int, body:array} */
    public static function post(string $path, array $payload): array {
        $base = get_transient('orgdon_sf_instance') ?: ORG_SF_LOGIN_URL;
        for ($i = 0; $i < 2; $i++) {
            $res = wp_remote_post($base . '/services/apexrest' . $path, [
                'timeout' => 15,
                'headers' => [
                    'Authorization' => 'Bearer ' . self::token($i === 1),
                    'Content-Type'  => 'application/json; charset=utf-8',
                ],
                'body' => wp_json_encode($payload, JSON_UNESCAPED_UNICODE),
            ]);
            if (is_wp_error($res)) { error_log('[orgdon] SF ' . $path . ' WP_Error ' . $res->get_error_message()); throw new RuntimeException('SF_NETWORK'); }
            $code = wp_remote_retrieve_response_code($res);
            if ($code === 401 && $i === 0) continue;
            $body = json_decode(wp_remote_retrieve_body($res), true) ?: [];
            if ($code >= 500) error_log('[orgdon] SF ' . $path . ' HTTP ' . $code);
            return ['code' => $code, 'body' => $body];
        }
        throw new RuntimeException('SF_AUTH');
    }
}
