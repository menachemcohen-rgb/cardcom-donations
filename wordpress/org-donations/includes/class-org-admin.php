<?php
if (!defined('ABSPATH')) exit;

/** Settings → Org Donations: one button, "רענון הגדרות מסיילספורס" (N123). Used after changing the amounts in Salesforce. */
final class Org_Admin {
    const SLUG = 'org-donations';
    const ACTION = 'orgdon_refresh_settings';

    public static function register(): void {
        add_action('admin_menu', [self::class, 'menu']);
        add_action('admin_post_' . self::ACTION, [self::class, 'handle_refresh']);
    }

    public static function menu(): void {
        add_options_page('Org Donations', 'Org Donations', 'manage_options', self::SLUG, [self::class, 'page']);
    }

    public static function page(): void {
        if (!current_user_can('manage_options')) return;
        $s = Org_Settings::get();
        $labels = ['salesforce' => 'סיילספורס', 'last' => 'עותק אחרון מסיילספורס (סיילספורס לא זמין כרגע)',
                   'config' => 'wp-config.php (גיבוי)', 'default' => 'ברירת המחדל של התוסף (גיבוי)'];
        echo '<div class="wrap" dir="rtl"><h1>Org Donations</h1>';
        if (!empty($_GET['orgdon_refreshed'])) {
            echo '<div class="notice notice-success"><p>ההגדרות רועננו מסיילספורס.</p></div>';
        }
        echo '<p>כפתורי הסכום: ' . esc_html(implode(', ', Org_Form::presets())) . ' ₪ · מינימום ' . esc_html((string) $s['min'])
           . ' · מקסימום ' . esc_html((string) $s['max']) . ' · מקור: ' . esc_html($labels[$s['source']] ?? $s['source']) . '</p>';
        echo '<form method="post" action="' . esc_url(admin_url('admin-post.php')) . '">';
        echo '<input type="hidden" name="action" value="' . esc_attr(self::ACTION) . '">';
        wp_nonce_field(self::ACTION);
        submit_button('רענון הגדרות מסיילספורס', 'primary', 'submit', false);
        echo '</form></div>';
    }

    public static function handle_refresh(): void {
        if (!current_user_can('manage_options')) wp_die('אין הרשאה', 403);
        check_admin_referer(self::ACTION);
        Org_Settings::refresh();
        Org_Settings::get();      // ask Salesforce now, so the page shows the new values
        wp_safe_redirect(admin_url('options-general.php?page=' . self::SLUG . '&orgdon_refreshed=1'));
        exit;
    }
}
