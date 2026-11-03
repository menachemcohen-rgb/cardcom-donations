# WordPress plugin `org-donations` — installation (B7.15)

Requirements: PHP ≥ 8.0, WordPress ≥ 6.2, HTTPS, outgoing HTTPS to Salesforce (`wp_remote_post` / cURL).

## 1. Build or copy the plugin
- Build a zip from the repo: `scripts/build-plugin.sh` → `dist/org-donations-1.1.0.zip`.
- WordPress → Plugins → Add New → Upload Plugin → choose the zip → Install. Or copy the folder `wordpress/org-donations/` to
  `wp-content/plugins/org-donations/` over SFTP (without `tests/`, `vendor/`, `composer.*`, `phpunit.xml.dist`).

## 2. `wp-config.php` constants
Add above `/* That's all, stop editing! */`. Values are never stored in the database or in the plugin.

```php
define('ORG_SF_LOGIN_URL', 'https://test.salesforce.com');   // production: https://login.salesforce.com
define('ORG_SF_CLIENT_ID', '<Consumer Key of ECA WP_Donations>');
define('ORG_SF_USERNAME',  'integration.donations@ato770.com.atosandbox');
define('ORG_SF_KEY_PATH',  '/path/outside/webroot/server.key');
define('ORG_DONATION_ORIGIN',    'https://www.<site>');                    // exact canonical origin, no trailing slash
// Optional (safe defaults when missing)
define('ORG_CARDCOM_ORIGIN',     'https://secure.cardcom.solutions');     // default: this value
define('ORG_DONATION_TERMS_URL', 'https://www.<site>/terms-recurring/');  // Q8; missing → the terms text shows without the link
define('ORG_DONATION_CONTACT_PHONE', '03-0000000');                       // shown on the donor page (B13 T-Y01)
define('ORG_DONATION_CONTACT_EMAIL', 'donations@<site>');
define('ORG_BEHIND_CLOUDFLARE', true);                                     // only if the site is proxied by Cloudflare
// Rate limits per visitor IP (fixed window from the first counted request). Only counted: card sessions created for a
// valid form, and valid pledge submissions. Page loads, validation errors and retries of an accepted submission don't count.
define('ORG_DONATION_RL_WINDOW', 600);                                     // seconds (default 600)
define('ORG_DONATION_RL_SUBMIT_MAX', 5);                                   // pledge submissions per window (default 5)
define('ORG_DONATION_RL_LP_MAX', 10);                                      // card sessions per window (default 10)
```

The Cardcom card frame opens only after the donor fills a valid form and presses "המשך להזנת פרטי כרטיס": the plugin checks the
form in the browser and again on the server before it asks Salesforce for the Cardcom session, so no card token is ever created
for an invalid form. A pledge is submitted at most once per Cardcom session (LowProfileId): retries and double clicks get the
same answer.

**Cardcom page settings (not in this plugin):** the frame's title (the business name) and any extra fields under "פרטים נוספים",
such as a required "מוסד" field, come from the terminal's LowProfile page settings in the Cardcom admin, not from the request this
system sends (the request sets only the card owner name/ID/CVV options). The public test terminal 1001 has such a field; check the
production terminal and remove the field there (Cardcom admin → settings → LowProfile page / additional fields) or ask Cardcom
support. The "סה"כ ₪1.00" line is the card check amount of a token-only session; the form explains it above the frame.

If a required constant is missing, admins see a notice and the shortcodes show "הטופס אינו זמין כרגע".

Salesforce authentication is the OAuth 2.0 JWT Bearer flow (D31): the plugin signs a short JWT (RS256) with the private key at
`ORG_SF_KEY_PATH`; there is no client secret. **The private key must be outside the web root, `chmod 600` (readable only by the PHP
user), and never committed.** Its public certificate is uploaded to the External Client App `WP_Donations` (README step 10). If the
key is missing or unreadable the log shows `[orgdon] SF key unreadable` and the form shows its "not available" message.

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
