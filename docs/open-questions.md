# Open questions (B14 + Part C4), 2026-11-02

Owner: **Client** (the organisation), **Cardcom** (asked through the client), **Yosef** (project lead).
"Blocks" says what can't be finished or switched on until the answer arrives; the code always has a working default (shown).
Answered and closed: Q1 (Contact + Account per D-3; NPSP absent, D26), Q6/Q14/Q15 (D28), Q12/Q17 (removed in B14), D27 (External
Client App), D29 (reconciliation flag), D30 (scheduling as the integration user).

## Blocks go-live

| # | Owner | Question | Default in the code | Blocks |
|---|---|---|---|---|
| Q20 | Client / Yosef | Approve the scope beyond the 40-hour quote (donor page, nightly reconciliation, reports/dashboard, auto holidays — B12), or drop parts. See `docs/effort-estimate.md`. | All built. | The change-request conversation and invoicing; nothing technical. |
| Q8 | Client | Final texts: form and donor-page messages, thank-you email, terms URL, sender name and address (verified OWEA). | Spec drafts in Custom Labels / templates; placeholders in B13.0. | Production go-live (donor-facing wording); TC01, TC11 emails. |
| Q7 | Client | Staff alert addresses; who may stop/resume charges (`Donations_Admin`). | `Failure_Notify_Emails__c` blank → no alerts. | TC18 and every staff alert. |
| Q11 | Client | WordPress hosting: cache plugin/CDN/Cloudflare, fixed outbound IP (for the External Client App IP restriction), admin access. | Cache exclusions documented; IP restriction off. | WordPress install (TC01–TC10), TC38. |
| Q3 | Client | Rest days: confirm the 8 computed holidays (B6.6); add Independence Day / Tisha B'Av / Chol HaMoed? Confirm ×3/×4 charging before a 2-day holiday + Shabbat. | 8 holidays, `Charge_Holiday__mdt` overrides. | Production schedule (TC13, TC14). |
| Q4 | Client | Final charge times. | 08:00 / 20:00; eve 06:00 / 11:00 (`Charge_Settings__c`, editable). | Nothing (changeable any time with the button). |
| Q5 | Client | Min/max amount and preset buttons. | 1–50 ₪; 1, 3, 5, 10. | Nothing (CMDT + WordPress constants). |
| Q16 | Client / Cardcom | Day and time of the monthly receipt; wording of Cardcom's receipt email; section 46 set-up on the production terminal (checklist 1). | 1st of the month 07:00. | First real receipt (`docs/receipt-go-live-checklist.md`). |
| Q18 | Cardcom | Full list of response codes (B5.8 uses KB + Shva lists); does a Transaction without `Document` create any document/SMS on the client's terminal; LowProfile page lifetime. | Unknown codes → Retryable; iframe refreshed after 20 min. | TC16/TC17 on the real terminal, TC40. |
| Q22 | Cardcom / Client | Token creation check: J2 (validity check) or J5 (amount hold). | J2 (`Lp_JValidate_Type__c = 2`). | TC01 on the production terminal. |

## Does not block go-live

| # | Owner | Question | Default | Affects |
|---|---|---|---|---|
| Q2 | Client | One full-name field or first + last? | First + last. | Form layout only. |
| Q9 | Client | Thank-you email volume (up to 14 a week per donor; Friday grouped). Near the 5,000/day org limit only at ~2,500 TwiceDaily donors. | Guard: below 200 left → skip + one staff alert. | Growth beyond ~1,250 TwiceDaily donors. |
| Q10 | Client | First charge immediately on sign-up? Welcome email? | Next scheduled run; no welcome email. | — |
| Q13 | Client | Israeli ID retention policy and who may see it. | Encrypted; visible to `Donations_Admin` only. | — |
| Q19 | Client | Change frequency / self-cancel on the donor page? | Not offered (call the organisation). | — |
| Q21 | Client | Light verification when opening a donor link (last 4 phone digits)? | Off (`Optional_Verify_On_Open__c`). | — |
| — | Yosef | Confirm D29 (reconciliation flag system-managed) and D30 (schedule through the setup-command event). | As built. | — |
| — | Client (org owner) | R2: their `Log__c` flow's Opportunity queries should exclude `Micro_Donation_Pledge`. | Our reports filter the record type. | Their payments process, not ours. |

## Change requests parked by Part C4 (not built)

| Item | Owner | Note |
|---|---|---|
| Different amount on Friday / eve (client item 4) | Client → Yosef | Needs pledge fields and a planner change; estimate separately. |
| Sunrise/sunset-based or per-country charge times (items 1, 5) | Client → Yosef | Out of scope; only fixed, admin-editable times. |
| "Donor summary file" the client called redundant | Client | It is the monthly receipt (B6.11); confirm it stays. |
