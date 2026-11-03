<?php
// Minimal WordPress stand-ins so the plugin's pure classes can be tested without a WordPress install.
define('ABSPATH', __DIR__ . '/');
$GLOBALS['orgdon_test_transients'] = [];

function sanitize_text_field($s) { return trim(preg_replace('/[\r\n\t ]+/', ' ', strip_tags((string) $s))); }
function sanitize_email($s) { return trim((string) $s); }
function is_email($s) { return (bool) filter_var($s, FILTER_VALIDATE_EMAIL); }
function get_transient($k) { return $GLOBALS['orgdon_test_transients'][$k] ?? false; }
function set_transient($k, $v, $ttl) { $GLOBALS['orgdon_test_transients'][$k] = $v; return true; }

if (!defined('MINUTE_IN_SECONDS')) define('MINUTE_IN_SECONDS', 60);
if (!defined('DAY_IN_SECONDS')) define('DAY_IN_SECONDS', 86400);

// ---- stand-ins used by the form AJAX tests (FormAjaxTest) ----
$GLOBALS['orgdon_test_options'] = [];
$GLOBALS['orgdon_test_http'] = [];          // recorded wp_remote_post calls
$GLOBALS['orgdon_test_http_reply'] = null;  // callable(url, args) => ['code' => int, 'body' => string]
final class OrgdonTestJson extends Exception {
    public function __construct(public bool $ok, public array $data, public int $status) { parent::__construct('json'); }
}
function add_option($k, $v, $d = '', $a = null) { if (array_key_exists($k, $GLOBALS['orgdon_test_options'])) return false; $GLOBALS['orgdon_test_options'][$k] = $v; return true; }
function get_option($k, $d = false) { return $GLOBALS['orgdon_test_options'][$k] ?? $d; }
function delete_option($k) { unset($GLOBALS['orgdon_test_options'][$k]); return true; }
function check_ajax_referer($a, $q = false) { return true; }
function wp_unslash($v) { return $v; }
function wp_send_json_success($d = null, $s = 200) { throw new OrgdonTestJson(true, (array) $d, $s); }
function wp_send_json_error($d = null, $s = 400) { throw new OrgdonTestJson(false, (array) $d, $s); }
function home_url($p = '') { return 'https://www.example.org.il' . $p; }
function is_wp_error($x) { return false; }
function wp_json_encode($d, $f = 0) { return json_encode($d, $f); }
function wp_remote_post($url, $args) {
    $GLOBALS['orgdon_test_http'][] = $url;
    return ($GLOBALS['orgdon_test_http_reply'])($url, $args);
}
function wp_remote_retrieve_response_code($r) { return $r['code']; }
function wp_remote_retrieve_body($r) { return $r['body']; }
if (!function_exists('orgdon_const')) {
    function orgdon_const(string $name, string $default = ''): string { return defined($name) ? (string) constant($name) : $default; }
}
if (!defined('ORG_SF_LOGIN_URL')) define('ORG_SF_LOGIN_URL', 'https://test.salesforce.com');

require dirname(__DIR__, 2) . '/includes/class-org-validator.php';
require dirname(__DIR__, 2) . '/includes/class-org-sf-client.php';
require dirname(__DIR__, 2) . '/includes/class-org-rate-limiter.php';
require dirname(__DIR__, 2) . '/includes/class-org-form.php';
if (!function_exists('esc_url_raw')) { function esc_url_raw($u) { return (string) $u; } }
require dirname(__DIR__, 2) . '/includes/class-org-portal.php';
