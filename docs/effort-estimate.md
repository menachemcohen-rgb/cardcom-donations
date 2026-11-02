# Effort vs the 40-hour quote (B1, B13) — for the change-request conversation

Hours are the **equivalent hand-built effort** a Salesforce + WordPress developer would need for what is in the repo, including
tests and documentation. They are estimates, not a time log. The build was generated with AI assistance, so calendar time was
shorter, but the org work below (deploy, configuration, sandbox acceptance) still has to be done by a person and is not in the quote.

## Quoted components

| Quote component (B1) | Quoted | What was built | Estimate | Why it differs |
|---|---|---|---|---|
| 1 Data model | 2 | Opportunity override (record type, sales process, 5 stages merged into the org's set, 37 fields), 8 custom objects, 4 CMDT types + 17 error codes, 3 custom settings, 8 validation rules, 4 permission sets | 6–8 | Part C moved the pledge onto Opportunity (merge-safe stages, record-type guards everywhere) and the support objects grew from the quote. |
| 2 Form on the site | 10 | WordPress plugin: form, Salesforce client, validation, rate limits, return page, CSP/cache headers, PHPUnit + JS tests, install guide | 10–14 | Close to the quote; tests and the cache/CSP hardening add a little. |
| 3 Intake to Salesforce | 5 | LowProfile + pledge REST APIs, webhook site + platform event, GetLpResult job, sweeper, donor matching (email/phone/ID + duplicate rules), activation | 10–12 | Matching without overwriting data, idempotent webhook (7 retries), and the sweeper safety net. |
| 4 Charging run | 15 | Hebrew calendar (auto holidays) + eves ×N, 4 daily runs, planner (+batch), queueable chain with callout budget, retries outside Shabbat/holidays, double-charge protection (per-attempt keys + verify), error classification | 18–24 | Auto holiday detection (Q20) and the unknown-outcome verification were not in the quote. |
| 5 Failures and investigation | 5 | Roll-ups, consecutive-failure streak + one alert per streak, all staff alerts, stop/resume/cancel/revoke flows, quick actions, record page | 6–8 | — |
| 6 Emails (incl. monthly receipt and donor page) | 3 | Thank-you email with grouped Friday charges and signed links, daily-limit guard | 3–5 | Only the thank-you email fits in 3 h; the receipt and the donor page are below. |
| **Subtotal (quoted scope)** | **40** | | **53–71** | |

## Built beyond the quote (B12 — needs approval, Q20)

| Package | Estimate |
|---|---|
| Donor page: card replacement + amount change (Salesforce REST, HMAC links, WordPress portal) | 7–9 |
| Monthly receipt through Cardcom (planner, queueable, retry action, go-live checklist) | 4–6 |
| Nightly reconciliation + log clean-up | 3–4 |
| Reports (13), report types (4) and the dashboard | 2–3 |
| **Subtotal (extensions)** | **16–22** |

## Not in the quote at all

| Work | Estimate |
|---|---|
| First deploy, org configuration (README steps 1–25), External Client App, Site, Cardcom test terminal | 4–6 |
| Sandbox acceptance TC01–TC40 with the test terminal and fixing what the first deploy finds | 4–6 |
| **Subtotal** | **8–12** |

## Total

| | Hours |
|---|---|
| Quoted | 40 |
| Built (quoted scope + extensions) | 69–93 |
| Plus deploy and acceptance | 77–105 |

Ways to bring it closer to the quote if the client won't extend: drop the reports/dashboard (use list views) and the reconciliation
(manual monthly check in Cardcom) → about −6 h; replace the donor page with "call us" → about −8 h. The monthly receipt is part of
component 6 in the client's own spec, so it is better kept.
