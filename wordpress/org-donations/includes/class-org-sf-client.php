<?php
if (!defined('ABSPATH')) exit;

final class Org_SF_Client {
    const TOKEN_TRANSIENT = 'orgdon_sf_token';
    const JWT_TTL = 180;   // seconds; Salesforce accepts up to 3 minutes

    /** OAuth 2.0 JWT Bearer flow (External Client App WP_Donations, pre-authorized integration user). */
    private static function token(bool $force = false): string {
        if (!$force && ($t = get_transient(self::TOKEN_TRANSIENT))) return $t;
        $key = self::private_key();
        $jwt = self::build_jwt(ORG_SF_CLIENT_ID, ORG_SF_USERNAME, ORG_SF_LOGIN_URL, $key, time());
        $res = wp_remote_post(ORG_SF_LOGIN_URL . '/services/oauth2/token', [
            'timeout' => 10,
            'body'    => [
                'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
                'assertion'  => $jwt,
            ],
        ]);
        if (is_wp_error($res) || wp_remote_retrieve_response_code($res) !== 200) {
            error_log('[orgdon] SF token failure: ' . (is_wp_error($res) ? $res->get_error_message() : wp_remote_retrieve_response_code($res)));
            throw new RuntimeException('SF_AUTH');
        }
        $j = json_decode(wp_remote_retrieve_body($res), true);
        if (empty($j['access_token'])) {
            error_log('[orgdon] SF token failure: no access_token');
            throw new RuntimeException('SF_AUTH');
        }
        set_transient(self::TOKEN_TRANSIENT, $j['access_token'], 50 * MINUTE_IN_SECONDS);
        if (!empty($j['instance_url'])) set_transient('orgdon_sf_instance', $j['instance_url'], DAY_IN_SECONDS);
        return $j['access_token'];
    }

    /** Loads the private key at ORG_SF_KEY_PATH. Never logs the path contents. */
    private static function private_key(): OpenSSLAsymmetricKey {
        $pem = (is_string(ORG_SF_KEY_PATH) && is_file(ORG_SF_KEY_PATH) && is_readable(ORG_SF_KEY_PATH))
            ? @file_get_contents(ORG_SF_KEY_PATH) : false;
        $key = $pem === false ? false : openssl_pkey_get_private($pem);
        unset($pem);
        if ($key === false) {
            error_log('[orgdon] SF key unreadable');
            throw new RuntimeException('SF_AUTH');
        }
        return $key;
    }

    /**
     * RS256 JWT for the Salesforce JWT Bearer flow. Public for tests only.
     * @param OpenSSLAsymmetricKey|string $key private key (resource or PEM)
     */
    public static function build_jwt(string $clientId, string $username, string $aud, $key, int $now): string {
        $header = self::b64url(json_encode(['alg' => 'RS256']));
        $claims = self::b64url(json_encode([
            'iss' => $clientId,
            'sub' => $username,
            'aud' => $aud,
            'exp' => $now + self::JWT_TTL,
        ], JSON_UNESCAPED_SLASHES));
        $input = $header . '.' . $claims;
        $sig = '';
        if (!openssl_sign($input, $sig, $key, OPENSSL_ALGO_SHA256)) {
            error_log('[orgdon] SF JWT signing failed');
            throw new RuntimeException('SF_AUTH');
        }
        return $input . '.' . self::b64url($sig);
    }

    public static function b64url(string $data): string {
        return rtrim(strtr(base64_encode($data), '+/', '-_'), '=');
    }

    /** @return array{code:int, body:array} */
    public static function post(string $path, array $payload): array {
        for ($i = 0; $i < 2; $i++) {
            // Token first: it caches instance_url (ORG_SF_LOGIN_URL is login/test.salesforce.com, not the org's domain).
            $token = self::token($i === 1);
            $base = get_transient('orgdon_sf_instance') ?: ORG_SF_LOGIN_URL;
            $res = wp_remote_post($base . '/services/apexrest' . $path, [
                'timeout' => 15,
                'headers' => [
                    'Authorization' => 'Bearer ' . $token,
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
