# פריטים פתוחים – העלאה לפרודקשן (מעודכן 9.11.2026)

**המצב:** המערכת בפרודקשן ופועלת. ההוראה הראשונה (PLG-000001) אומתה ושויכה לאיש קשר. החיובים הודלקו, והחיוב הראשון מתוכנן ל-10.11 ב-08:00.

## 10.11–11.11: החיוב הראשון
- [ ] **08:00, חיוב ראשון של PLG-000001:** לבדוק שה-Charge ב-`Success`, שיש מספר עסקה, ושמייל התודה נשלח.
  ```
  sf data query --target-org prod --query "SELECT Name, Status__c, Amount__c, Error_Code__c, Error_Message__c, Cardcom_Tranzaction_Id__c, Executed_At__c, Donor_Email_Status__c FROM Charge__c ORDER BY CreatedDate DESC LIMIT 5"
  ```
- [ ] **הקישורים במייל:** לבדוק שהם פותחים את דף התורם (`ato770.com/donor/`), ושאפשר לשנות בו סכום.
- [ ] **20:00, חיוב שני:** אותה בדיקה.
- [ ] **11.11 בבוקר, ההתאמה הלילית:** לבדוק ש-`ReconciliationJob` הסתיים, ושבדוח "Open Reconciliation Issues" אין פערים.
- **עצירת חירום:** להוריד את Charging Enabled ב-Charge Settings.

## אצל יוסי
- [ ] **`check.txt`:** להריץ את הבדיקה הכללית (`scripts\prod\post-deploy-check.ps1`) ולעבור על התוצאה.
- [ ] **Stage History:** להוסיף ל-Micro Donation Pledge Layout, אם עוד לא נוסף. בלעדיו טאב History בהוראה ריק.
- [ ] **Utility Bar:** להוסיף לאפליקציית המנהלים את `Apply_Charge_Schedule` ואת `Plan_Monthly_Receipts_All`.
- [ ] **דוחות:** לשתף את תיקיית Donations עם הצוות.
- [ ] **הרשאות לצוות:** לשייך Donations_Admin או Donations_Staff לאנשי הצוות שצריכים גישה.
- [ ] **ניקיון בפרודקשן (לא דחוף):**
  - לכבות את ה-Site הישן `Cardcom_Webhook`.
  - אולי לשנות את שם הרשימה `Opportunities__r` ל"תשלומים" (Child Relationship Label של `Contact__c`).
- [ ] **ניקיון בסנדבוקס:**
  - Remote Site `Tmp_Self_Metadata_Deploy`.
  - הוראות הבדיקה הישנות, שיש להן טוקנים של טרמינל הבדיקות.

## מחכה לאת"ה (טופס ערכי ההגדרה)
- [ ] **ערכים מהטופס.** כשהם מגיעים, מעדכנים אותם בשני מקומות:
  - **Custom Labels בסיילספורס:** שם הארגון, טלפון, מייל וחתימה.
  - **`wp-config.php`:** `ORG_DONATION_CONTACT_PHONE`, `ORG_DONATION_CONTACT_EMAIL` ו-`ORG_DONATION_TERMS_URL`.
- [ ] **כתובת התקנון:** גם ב-`Terms_Url__c` (Cardcom Setting). עד אז לוודא שהקישור "תנאי ההוראה" באתר לא שבור.
- [ ] **DKIM:**
  1. את"ה מוסיפים ב-DNS של `ato770.com` שתי רשומות CNAME: `sf1._domainkey` ו-`sf2._domainkey`.
  2. את"ה מעדכנים את רשומת ה-SPF.
  3. יוסי מפעיל את המפתח ב-Setup → DKIM Keys.
- [ ] **כתובת שולח ב-`ato770.com`** (למשל `donations@`): לאמת אותה כ-Org-Wide Address ולהכניס ל-`Org_Wide_Email_Address__c`. עד אז המיילים יוצאים בשם משתמש האינטגרציה.
- [ ] **דפי הבדיקה 2823 ו-2825 באתר:** להוריד מפרסום.
- [ ] **החלטה על ת"ז:** האם לאחד את `Donor_Tax_Id__c` לתוך `Israeli_Id__c` (אפשרות ב'). כרגע שני השדות קיימים, והזיהוי עובד לפי שניהם.

## לפני 2.12 (הקבלה החודשית הראשונה)
- [ ] **קבלה עם שורות אשראי (`CreditCardLines`):** לוודא שהיא עובדת בטרמינל 48648. זה עוד לא נבדק בפרודקשן. עוברים על `docs/receipt-go-live-checklist.md`, ובפרט על בדיקה 6.
- [ ] **מודול מסמכים ב-Cardcom:** לוודא שהוא פעיל, ושקבלת תרומה לפי סעיף 46 מוגדרת.
- [ ] **אפשר להקדים:** אחרי החיובים של 10.11, להפיק קבלה ידנית לאיש הקשר של יוסי עם הכפתור "Create Monthly Receipt".

## שאלות פתוחות מול Cardcom (לא חוסמות)
- [ ] **הטרמינל הוא טרמינל הוראות קבע?** התשובה קובעת את `Is_Recurring_Terminal__c`, שכרגע false.
- [ ] **J2 או J5 בשמירת כרטיס?** כרגע J2 (`Lp_JValidate_Type__c`).

## מה כבר הושלם בפרודקשן
- דיפלוי מלא:
  - קוד, אובייקטים ושדות;
  - Permission Sets, Flows ופעולות;
  - Layouts ו-Record Page;
  - דוחות ולוח בקרה;
  - תרגומים.
- **משתמש אינטגרציה ו-JWT:** האתר מחובר לפרודקשן.
- **Site `cardcom` ו-Webhook:** פעילים.
- **Subscribers:** שלושתם רצים כמשתמש האינטגרציה.
- **Jobs מתוזמנים:** 13, בבעלות משתמש האינטגרציה.
- **סוד קישורי התורם:** הוזן.
- **הגדרות Cardcom:** טרמינל 48648, Webhook, Return Hosts, Donor Portal.
- **Flows:** 8 פעילים.
- **אנשי קשר:** נורמלו, וכללי הזיהוי (Matching Rule ו-Duplicate Rule) הופעלו.
- **Layouts:**
  - ההוראה: משויך, וה-Record Page פעיל.
  - איש קשר: סקשן, Related Lists וכפתור הקבלה.
- **דף התורם:** פורסם באתר.
