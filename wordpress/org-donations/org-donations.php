<?php
/**
 * Plugin Name: Org Donations (Cardcom + Salesforce)
 * Description: טופס הוראת תרומה יומית ודף אישי לתורם.
 * Version: 1.0.1
 * Requires PHP: 8.0
 * Text Domain: org-donations
 */
if (!defined('ABSPATH')) exit;

define('ORGDON_VER', '1.0.1');
define('ORGDON_DIR', plugin_dir_path(__FILE__));
define('ORGDON_URL', plugin_dir_url(__FILE__));

foreach (['sf-client','validator','rate-limiter','form','portal','return-endpoint'] as $f) {
    require_once ORGDON_DIR . "includes/class-org-$f.php";
}

function orgdon_configured(): bool {
    foreach (['ORG_SF_LOGIN_URL','ORG_SF_CLIENT_ID','ORG_SF_CLIENT_SECRET','ORG_DONATION_ORIGIN'] as $c) {
        if (!defined($c) || constant($c) === '') return false;
    }
    return true;
}

add_action('admin_notices', function () {
    if (!orgdon_configured() && current_user_can('manage_options')) {
        echo '<div class="notice notice-error"><p>Org Donations: חסרים קבועים ב-wp-config.php.</p></div>';
    }
});

add_action('init', ['Org_Return_Endpoint', 'register']);
add_action('init', ['Org_Form', 'register']);
add_action('init', ['Org_Portal', 'register']);
register_activation_hook(__FILE__, function () { Org_Return_Endpoint::register(); flush_rewrite_rules(); });
register_deactivation_hook(__FILE__, 'flush_rewrite_rules');

/** Security headers on pages that contain our shortcodes. */
add_action('template_redirect', function () {
    if (!is_singular()) return;
    $post = get_post();
    if (!$post) return;
    $has = has_shortcode($post->post_content, 'org_donation_form') || has_shortcode($post->post_content, 'org_donor_portal');
    if (!$has) return;
    nocache_headers();
    header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');
    header('Referrer-Policy: no-referrer');
    // 'self': Cardcom redirects the iframe to our own /cardcom-return/ page — without it the browser blocks that page (N64).
    header("Content-Security-Policy: frame-src 'self' https://secure.cardcom.solutions; frame-ancestors 'self'");
    header('X-Robots-Tag: noindex, nofollow');
    if (!defined('DONOTCACHEPAGE')) define('DONOTCACHEPAGE', true); // WP Rocket / W3TC / LiteSpeed honor this
}, 1);
