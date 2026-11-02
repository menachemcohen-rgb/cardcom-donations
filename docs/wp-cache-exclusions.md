# WordPress: cache, CDN and security-plugin exclusions (B7.14)

The donation form, the donor portal and the Cardcom return page must never be served from a cache: each page load creates a new
one-time Cardcom payment page (LowProfile) and a fresh WordPress nonce. A cached copy would show every visitor the same, already-used
card iframe, and the AJAX calls would fail the nonce check.

## What to exclude

| Path | Why |
|---|---|
| The form page, e.g. `/daily-donation/` (`[org_donation_form]`) | new LowProfile and nonce on every load |
| The donor page, e.g. `/donor/` (`[org_donor_portal]`) | the signed link token arrives in the URL (`?a=…&t=…`) |
| `/cardcom-return/` | loaded inside the Cardcom iframe after the card is saved |
| `/wp-admin/admin-ajax.php` | form submit, iframe refresh, portal actions |

The plugin already sends `Cache-Control: no-store`, `DONOTCACHEPAGE` and `X-Robots-Tag: noindex` on pages that contain its shortcodes,
and `nocache_headers()` on `/cardcom-return/`. Page-cache plugins and CDNs don't always honour these headers, so set the rules below too.

### WP Rocket
- Settings → WP Rocket → Advanced Rules → **Never Cache URL(s)**: one per line
  ```
  /daily-donation/(.*)
  /donor/(.*)
  /cardcom-return/(.*)
  ```
- File Optimization: exclude `org-donations/assets/donation-form.js` and `org-donations/assets/donor-portal.js` from **Delay JavaScript
  execution** and **Load JavaScript deferred** if the form doesn't start (the iframe refresh timer and the `postMessage` listener must
  run on load).
- Clear the cache after saving.

### LiteSpeed Cache
- LiteSpeed Cache → Cache → Excludes → **Do Not Cache URIs**:
  ```
  /daily-donation/
  /donor/
  /cardcom-return/
  ```
- Page Optimization → JS Settings: add the two script names above to **JS Delayed Includes Excluded** / **JS Excludes** if needed.
- Purge All.

### Cloudflare
- Caching → Cache Rules → Create rule "Org donations bypass": *URI Path* `starts with` `/daily-donation/` **or** `/donor/` **or**
  `/cardcom-return/` → **Bypass cache**. Make sure no "Cache Everything" page rule covers these paths.
- Speed → Optimization → **Rocket Loader: Off** for these pages (it rewrites inline scripts and breaks the form). Use a Configuration
  Rule scoped to the same paths if Rocket Loader stays on elsewhere.
- If the site is proxied by Cloudflare, add `define('ORG_BEHIND_CLOUDFLARE', true);` to `wp-config.php`. The rate limiter then uses
  the visitor's real IP from `CF-Connecting-IP`. Without the constant that header is ignored, because any client could forge it
  (spec-consistency N62).

### Other caches
Hosting-level caches (Kinsta, WP Engine, SiteGround, Varnish, Nginx FastCGI cache) need the same three paths excluded in the host's panel.

## Content-Security-Policy

If the site already sends a CSP (theme, security plugin, host or Cloudflare), it must allow:

```
frame-src 'self' https://secure.cardcom.solutions;
connect-src 'self';
```

`'self'` in `frame-src` matters: after the card is saved, Cardcom redirects its iframe to the site's own `/cardcom-return/` page, which
then tells the form to submit. Without `'self'` the browser blocks that page and the donor never sees the confirmation
(spec-consistency N64; the plugin's own header includes it).

`ORG_DONATION_ORIGIN` in `wp-config.php` must be the exact origin the visitors use (`https://www.example.org.il` vs
`https://example.org.il`). The return page posts its message to that origin, and the form only accepts messages from it. Redirect the
other host name to the canonical one.

## Security plugins / WAF (Wordfence, Sucuri, iThemes, ModSecurity)
- Allow `POST /wp-admin/admin-ajax.php` with the actions `org_donation_submit`, `org_donation_refresh`, `org_portal_context`,
  `org_portal_amount`, `org_portal_card`, `org_portal_card_status`.
- Don't rate-limit those actions harder than the plugin does (10 iframe loads / 5 submits per 10 minutes per IP); the portal polls the
  card status every 3 seconds for up to a minute.
- The server must reach `https://<mydomain>.my.salesforce.com` (outgoing HTTPS). Its outgoing IP goes into the External Client App's
  IP restrictions (Q11, Part C D27).

## The `sandbox` attribute on the card iframe (B7.9)

The form's iframe has `sandbox="allow-forms allow-scripts allow-same-origin allow-top-navigation-by-user-activation"`. Cardcom may need
`allow-popups` for 3-D Secure (the bank's verification window). **Test it on the Cardcom test terminal with a card that triggers
3-D Secure.** If 3-D Secure fails or shows a blank window:
1. Add `allow-popups allow-popups-to-escape-sandbox` to the attribute in `templates/form.php`, and test again.
2. If it still fails, remove the `sandbox` attribute completely (B7.9 allows this).

The same test covers `frame-src`: if the bank's page loads in the iframe itself rather than inside Cardcom's page, a strict site CSP
would block it too. Then add the bank's host, or relax `frame-src` for the form page only.

The donor-portal iframe (`templates/portal.php`) has no `sandbox` attribute, so it isn't affected.

## HTTPS
HTTPS is required on every page above. HSTS is recommended.
