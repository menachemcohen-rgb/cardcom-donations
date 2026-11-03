<?php
// Minimal WordPress stand-ins so the plugin's pure classes can be tested without a WordPress install.
define('ABSPATH', __DIR__ . '/');
$GLOBALS['orgdon_test_transients'] = [];

function sanitize_text_field($s) { return trim(preg_replace('/[\r\n\t ]+/', ' ', strip_tags((string) $s))); }
function sanitize_email($s) { return trim((string) $s); }
function is_email($s) { return (bool) filter_var($s, FILTER_VALIDATE_EMAIL); }
function get_transient($k) { return $GLOBALS['orgdon_test_transients'][$k] ?? false; }
function set_transient($k, $v, $ttl) { $GLOBALS['orgdon_test_transients'][$k] = $v; return true; }

require dirname(__DIR__, 2) . '/includes/class-org-validator.php';
require dirname(__DIR__, 2) . '/includes/class-org-sf-client.php';
require dirname(__DIR__, 2) . '/includes/class-org-rate-limiter.php';
require dirname(__DIR__, 2) . '/includes/class-org-form.php';
