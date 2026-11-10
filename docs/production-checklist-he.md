# צ'קליסט העלאה לפרודקשן

הפירוט המלא באנגלית: `docs/production-deployment.md`. מסומן **(שינוי באורג)** = פעולה שמשנה את הפרודקשן.

**Windows / PowerShell:** לכל סקריפט `.sh` יש גרסת `.ps1` באותה תיקייה, עם אותם פרמטרים. מריצים אותה כך:
`powershell -ExecutionPolicy Bypass -File scripts\prod\deploy-prod.ps1 prod validate`

דוגמאות:
- `scripts\org-discovery.ps1 prod`
- `scripts\prod\deploy-prod.ps1 prod quick <job-id>`
- `scripts\deploy-pe-subscriber.ps1 prod <username>`

`build-prod.py` רץ עם `python` (לא `python3`).

## א. לפני הכל (ידני)
- [ ] Discovery על הפרודקשן (`scripts/org-discovery.sh <prod>`).
  - לבדוק אוטומציות ושדות חובה על Opportunity.
  - לבדוק Record Types על Opportunity.
  - לבדוק Duplicate Rule של Contact שחוסם (Block).
- [ ] משתמש אינטגרציה.
  - רישיון Salesforce Integration + Permission Set License "Salesforce API Integration".
  - אזור זמן Asia/Jerusalem, locale he_IL.
- [ ] אם יש Record Types על Opportunity: ב-Record Type ברירת המחדל של משתמש האינטגרציה לאפשר:
  - 5 השלבים;
  - `Daily Donation Pledge` בשדה Type;
  - ערכי Frequency / Stop Reason / Match Method.
- [ ] Translation Workbench פעיל + עברית פעילה (אחרת לבנות עם `--no-translations`).
- [ ] Field History על Opportunity פעיל, עד 20 שדות (אחרת `--no-history`).
- [ ] Deployment Settings: לאפשר דיפלוי כש-Apex jobs ממתינים.
- [ ] מייל.
  - Deliverability = All email.
  - Org-Wide Email Address מאומת.
  - DKIM פעיל לדומיין.
- [ ] Cardcom: בטרמינל של הלקוח פעילים מודול Tokens ומודול מסמכים, ובחיובי Token אין חובת CVV.
- [ ] `config/prod-values.local.json`: להעתיק מ-`prod-values.example.json` ולמלא כל `<…>`.
  - מה ממלאים: טרמינל, URL של ה-Site, דומיין האתר, מיילים, Id משתמש האינטגרציה, ותוויות המייל (שם הארגון, טלפון, חתימה).
  - הקובץ לא נכנס ל-Git.

## ב. בנייה ובדיקה (בלי שינוי באורג)
- [ ] `sf project retrieve start --target-org <prod> --manifest manifest/retrieve-standard-value-sets.xml --output-dir build/prod-svs`
- [ ] `python3 scripts/prod/build-prod.py --org-svs build/prod-svs --values config/prod-values.local.json --first-install`
- [ ] בהתקנה ראשונה: `deploy-prod <prod> phase1` (שינוי באורג: רק סוגי ה-Custom Metadata והרשומות שלהם, בלי קוד).
- [ ] `scripts/prod/deploy-prod.sh <prod> validate`: אמור לעבור עם 32 מחלקות הבדיקה. לשמור את ה-Job Id.

## ג. דיפלוי (שינוי באורג)
- [ ] `scripts/prod/deploy-prod.sh <prod> quick <job-id>`

## ד. מיד אחרי הדיפלוי (ידני)
- [ ] סוד קישורי התורם.
  - איפה: Custom Metadata → Donor Link Setting → Default → Secret.
  - ערך: 64 תווי hex חדשים (`openssl rand -hex 32`).
  - לא הסוד של הסנדבוקס.
- [ ] Cardcom: External Credential `Cardcom_EC` → ApiName / ApiPassword של הלקוח.
- [ ] מסוף שני לדיינרס (D39): External Credential `Cardcom_Secondary_EC` → ApiName / ApiPassword של המסוף השני, ו-`Secondary_Terminal_Number__c` ב-Cardcom Setting → Default.
- [ ] `sf apex run --file scripts/apex/init-settings.apex` (שינוי באורג).
  - לבדוק Receipt Day = 2.
  - Charging Enabled = false עד העלייה לאוויר.
- [ ] External Client App `WP_Donations`.
  - JWT Bearer עם התעודה של הפרודקשן.
  - משתמש האינטגרציה pre-authorized.
  - הגבלת IP לשרת ה-WP.
- [ ] Site `cardcom`.
  - Permission Set לגסט.
  - הדומיין של ה-Site נכנס ל-Webhook URL.
- [ ] שיוך Permission Sets.
  - Integration → משתמש האינטגרציה.
  - Admin → כספים/נתונים.
  - Staff → צוות גיוס.
  - Site_Guest → משתמש הגסט.
  - Internal_Read → צפייה בלבד (אופציונלי).
- [ ] `scripts/deploy-pe-subscriber.sh <prod> <integration-username>` (שינוי באורג).
  - לבדוק ש-Charge Success מוגדר Publish After Commit.
  - **להפעיל מחדש את ה-Subscriptions.** בשלושת האירועים (Cardcom Lp Event, Charge Success, Donation Setup Command) עושים Manage → Suspend ואחר כך Resume. בלי זה ה-Jobs המתוזמנים נוצרים בשם משתמש המערכת (autoproc) ולא מצליחים לפנות ל-Cardcom.
  - **אחרי התזמון,** לבדוק ש-`OwnerId` של ה-Jobs שמתחילים ב-`Donations` הוא ה-Id של משתמש האינטגרציה.

## ה. Layouts, דפים, כפתורים (ידני)
- [ ] Opportunity Layout.
  - או לשייך את `Micro Donation Pledge Layout`,
  - או להוסיף ל-Layout הקיים סקשן הוראה + 4 הפעולות (הפסקה / חידוש / ביטול / ביטול קישורים).
- [ ] להפעיל את `Pledge_Record_Page` (Lightning App Builder → Activation).
- [ ] Contact Layout.
  - סקשן "תורם מיקרו".
  - Related list "הוראות תרומה יומית".
  - כפתור "הפקת קבלה חודשית".
- [ ] Monthly Receipt Layout (כולל כפתור "ניסיון חוזר").
- [ ] Utility Bar באפליקציית המנהלים: "החלת זמני חיוב" + "הפקת קבלות חודשיות לכל התורמים".
- [ ] שיתוף List Views ותיקיית הדוחות `Donations` לצוות.

## ו. נתונים ו-Jobs (שינוי באורג)
- [ ] `scripts/apex/normalize-contacts.apex`.
  - לחכות לסיום ה-Batch.
  - להפעיל את Matching Rule `Donor_Contact_Match` ואת Duplicate Rule `Donor_Contact_Duplicate`.
- [ ] `scripts/apex/schedule-donations.apex`.
  - לוודא 14 Jobs בשם משתמש האינטגרציה.
  - לוודא שהגיע המייל "זמני חיוב עודכנו".

## ז. וורדפרס
- [ ] התוסף, `wp-config.php` (`ORG_SF_LOGIN_URL=https://login.salesforce.com`, Client ID, משתמש, מפתח של הפרודקשן).
- [ ] החרגות Cache, ועמודים עם `[org_donation_form]` ו-`[org_donor_portal]`.

## ח. עלייה לאוויר
- [ ] שאלות פתוחות שחוסמות עלייה (`docs/open-questions.md`) נסגרו.
- [ ] צ'קליסט קבלות (`docs/receipt-go-live-checklist.md`) עבר על הטרמינל של הלקוח.
- [ ] הוראה ראשונה מבוקרת של איש צוות בסכום קטן.
- [ ] `Charging_Enabled__c = true` לפני ריצת בוקר רגילה (לא ערב שבת/חג).
- [ ] לעקוב אחרי הריצה הראשונה: חיובים, מייל תודה, והתאמה לילית למחרת.

## מה לא מעבירים מהסנדבוקס
- Remote Site `Tmp_Self_Metadata_Deploy`.
- הוראות הבדיקה והטוקנים שלהן.
- אנשי קשר של בדיקות.
- ערכי Cardcom Setting של הסנדבוקס.
- Profiles: לא נפרסים בכלל. ההרשאות מגיעות מה-Permission Sets, וכל השיוכים (Layout / דף / Utility Bar) נעשים ידנית.
