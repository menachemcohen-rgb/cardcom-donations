<?php
/** B7.2: uninstall deletes this plugin's transients only. No Salesforce data lives in WordPress. */
if (!defined('WP_UNINSTALL_PLUGIN')) exit;

global $wpdb;
delete_transient('orgdon_sf_token');
delete_transient('orgdon_sf_instance');
// Rate-limit buckets: orgdon_rl_{bucket}_{md5(ip)}
$wpdb->query("DELETE FROM {$wpdb->options} WHERE option_name LIKE '\\_transient\\_orgdon\\_rl\\_%' OR option_name LIKE '\\_transient\\_timeout\\_orgdon\\_rl\\_%'");
