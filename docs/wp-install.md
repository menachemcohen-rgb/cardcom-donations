# WordPress plugin `org-donations` — installation (B7.15)

Requirements: PHP ≥ 8.0, WordPress ≥ 6.2, HTTPS, outgoing HTTPS to Salesforce (`wp_remote_post` / cURL).

## 1. Build or copy the plugin
- Build a zip from the repo: `scripts/build-plugin.sh` → `dist/org-donations-1.0.1.zip`.
- WordPress → Plugins → Add New → Upload Plugin → choose the zip → Install. Or copy the folder `wordpress/org-donations/` to
  `wp-content/plugins/org-donations/` over SFTP (without `tests/`, `vendor/`, `composer.*`, `phpunit.xml.dist`).

## 2. `wp-config.php` constants
Add above `/* That's all, stop editing! */`. Values are never stored in the database or in the plugin.

```php
define('ORG_SF_LOGIN_URL',       'https://<mydomain>.my.salesforce.com');   // Salesforce My Domain
define('ORG_SF_CLIENT_ID',       '<consumer key of External Client App WP_Donations>');      // Part C D27
define('ORG_SF_CLIENT_SECRET',   '<consumer secret of External Client App WP_Donations>');
define('ORG_DONATION_ORIGIN',    'https://www.<site>');                    // exact canonical origin, no trailing slash
define('ORG_CARDCOM_ORIGIN',     'https://secure.cardcom.solutions');
define('ORG_DONATION_TERMS_URL', 'https://www.<site>/terms-recurring/');  // Q8
// Optional
define('ORG_DONATION_CONTACT_PHONE', '03-0000000');                       // shown on the donor page (B13 T-Y01)
define('ORG_DONATION_CONTACT_EMAIL', 'donations@<site>');
define('ORG_BEHIND_CLOUDFLARE', true);                                     // only if the site is proxied by Cloudflare
```

If a required constant is missing, admins see a notice and the shortcodes show "הטופס אינו זמין כרגע".

## 3. Activate
Plugins → Org Donations (Cardcom + Salesforce) → Activate. This registers the `/cardcom-return/` endpoint (rewrite rules are flushed on
activation). Check: `https://www.<site>/cardcom-return/` shows a small page "פרטי הכרטיס לא נקלטו.".

## 4. Pages
- "תרומה יומית" (e.g. `/daily-donation/`) containing only `[org_donation_form]`.
- "ניהול הוראה" (e.g. `/donor/`) containing only `[org_donor_portal]`. Its full URL goes into Salesforce
  `Cardcom_Setting__mdt.Default.Donor_Portal_Base_Url__c`.

## 5. Caches and security
Follow `docs/wp-cache-exclusions.md` (WP Rocket / LiteSpeed / Cloudflare / CSP / WAF), then clear every cache.

## 6. Salesforce side
- `Cardcom_Setting__mdt.Default.Allowed_Return_Hosts__c` = the site's host (e.g. `www.<site>`), otherwise Salesforce refuses to create
  the payment page (`BAD_RETURN_URL`).
- The External Client App's IP restrictions include the web server's outgoing IP (README step 10).

## 7. Check
- Open the form page: the Cardcom iframe appears.
- Browser DevTools → Network: no request from the browser to Salesforce (only `admin-ajax.php` and `secure.cardcom.solutions`).
- View Source: no client secret, no Salesforce token, no Salesforce URL.
- Then run the manual tests in `docs/acceptance.md` (TC01, TC05–TC07, TC10, donor page).

## Uninstall
Deleting the plugin removes only its transients (cached Salesforce token, rate-limit counters). Nothing in Salesforce is affected.

## Developers
```bash
cd wordpress/org-donations && composer install && vendor/bin/phpunit
```

```bash
node --test wordpress/org-donations/tests/js/donation-form.test.mjs
```
