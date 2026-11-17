# עריכת המיילים היוצאים

כל המיילים שהמערכת שולחת, לתורמים ולצוות, הם תבניות שאפשר לערוך ב-Salesforce בלי מפתח ובלי פריסה.

## איך עורכים

1. Setup → בתיבת החיפוש: **Classic Email Templates**.
2. בתיקייה **Donations** לבחור את התבנית (רשימה למטה).
3. **Edit Template**: אפשר לשנות את השורה **Subject** (נושא) ואת **HTML Body** (גוף המייל). לשמור.
4. השינוי חל מהמייל הבא שנשלח.

הרשאה: מי שיש לו את Permission Set **Donations_Admin** (או מנהל מערכת) יכול לערוך. ההרשאה נקראת "Manage Public Classic Email Templates", ו-Salesforce דורש איתה גם View Setup and Configuration ו-View Roles (צפייה בלבד).

### כללים

- מילים בסוגריים כפולים, למשל `{{FirstName}}`, הן **שדות שהמערכת ממלאת**. אפשר להזיז אותן או למחוק אותן, אבל לא לשנות את האיות. שדה שלא קיים בתבנית פשוט לא יופיע.
- אין להשתמש בשדות המיזוג של Salesforce (`{!Contact.Name}` וכו') — הם לא ימולאו. המייל נבנה בקוד מתוך הוראת התרומה (Opportunity) ואיש הקשר שלה, ורק השדות שבטבלאות כאן זמינים. שדה חדש דורש שינוי קוד קטן ב-`DonorEmailService.common`.
- אם תבנית נמחקה או רוקנה, המערכת שולחת את הנוסח המקורי, כך שמייל לא הולך לאיבוד.
- כדאי לבדוק כל שינוי ב-sandbox לפני הייצור, או לשלוח לעצמך מייל ניסיון.

### פרטים שמופיעים בכמה מיילים (לא בתבנית)

שם הארגון, טלפון ומייל ליצירת קשר וחתימה נלקחים מ-Setup → **Custom Labels**:
`Donation_Org_Name`, `Donation_Contact_Phone`, `Donation_Contact_Email`, `Donation_Signer_Name`.

## מיילים לתורם

שדות שקיימים בכל המיילים לתורם:

| שדה | מה מופיע |
|---|---|
| `{{FirstName}}` | השם הפרטי של התורם |
| `{{LastName}}` | שם המשפחה |
| `{{FullName}}` | שם פרטי ושם משפחה |
| `{{DonorEmail}}` | כתובת המייל של התורם (זו שהמייל נשלח אליה) |
| `{{DonorPhone}}` | הנייד של התורם |
| `{{PledgeNumber}}` | מספר ההוראה, למשל PLG-000123 |
| `{{OrgName}}` | שם הארגון |
| `{{Frequency}}` | "שחרית ומנחה" / "שחרית" / "מנחה" |
| `{{Amounts}}` | הסכומים, למשל "שחרית 3.00 ₪ · מנחה 5.00 ₪" |
| `{{ShacharitAmount}}` / `{{MinchaAmount}}` | הסכום לכל חיוב בשחרית / במנחה, למשל 3.00 (ריק אם התפילה לא בהוראה) |
| `{{StartDate}}` | תאריך תחילת ההוראה (dd/MM/yyyy) |
| `{{TotalCollected}}` | סה"כ נגבה מתחילת ההוראה, למשל 186.00 |
| `{{SuccessfulCharges}}` | מספר החיובים המוצלחים מתחילת ההוראה |
| `{{LastChargeDate}}` | תאריך החיוב המוצלח האחרון |
| `{{Last4}}` | 4 הספרות האחרונות של הכרטיס (ריק אם לא ידוע) |
| `{{CardExpiry}}` | תוקף הכרטיס, למשל 09/28 |
| `{{PaymentIssueSince}}` | מתי התחילה בעיית החיוב (ריק אם אין) |
| `{{Today}}` | התאריך של היום |
| `{{Card}}` | "הכרטיס המסתיים ב-1234" (או "הכרטיס השמור") |
| `{{CardPhrase}}` | " · כרטיס המסתיים ב-1234" (ריק אם לא ידוע) |
| `{{CardLink}}` | הקישור הקבוע להחלפת כרטיס (לשים ב-`href`) |
| `{{AmountLink}}` | הקישור הקבוע לשינוי סכום (לשים ב-`href`) |
| `{{ContactPhone}}` | טלפון ליצירת קשר |
| `{{ContactEmailPart}}` | " · " ומייל ליצירת קשר (ריק אם לא הוגדר) |
| `{{Signature}}` | החתימה |

שם, מייל וטלפון נלקחים מאיש הקשר של התורם, ואם חסרים — ממה שהתורם הקליד בטופס. מספר תעודת הזהות לא זמין בתבניות בכוונה.

| תבנית | מתי נשלח | שדות נוספים |
|---|---|---|
| **Donor_Welcome** | כשההוראה נקלטה והפכה לפעילה | — |
| **Donor_Monthly_Summary** | פעם בחודש, עם הפקת הקבלות | `{{Month}}` (למשל "נובמבר 2026"), `{{MonthTotal}}`, `{{ChargeCount}}` |
| **Donor_Payment_Failed** | בפעם הראשונה שחיוב נכשל סופית | — |
| **Donor_Payment_Failed_Reminder** | בכל יום ראשון עד שהבעיה נפתרת | — |

הקבלה לפי סעיף 46 נשלחת מ-Cardcom ונוסחה נקבע בהגדרות המסמכים במסוף Cardcom, לא כאן.

## מיילים לצוות

נשלחים לכתובות שב-`Failure_Notify_Emails__c` (Setup → Custom Metadata Types → Cardcom Setting → Default).
`{{Table}}` היא הטבלה שהמערכת בונה (אפשר להזיז אותה, לא לערוך את תוכנה).

| תבנית | מתי נשלח | שדות |
|---|---|---|
| **Staff_Failure_Streak** | כישלונות רצופים בהוראה | `{{Donor}}`, `{{Count}}`, `{{DonorEmail}}`, `{{DonorPhone}}`, `{{PledgeNumber}}`, `{{Frequency}}`, `{{Amounts}}`, `{{Last4}}`, `{{Expiry}}`, `{{Table}}`, `{{RecordUrl}}` |
| **Staff_High_Amount** | הוראה עם סכום לחיוב מעל הסף (ברירת מחדל 25 ₪) | `{{Donor}}`, `{{Threshold}}`, `{{HighAmounts}}`, `{{DonorEmail}}`, `{{DonorPhone}}`, `{{PledgeNumber}}`, `{{Frequency}}`, `{{Amounts}}`, `{{RecordUrl}}` |
| **Staff_Run_Failures** | רוב החיובים בשלוש השעות האחרונות נכשלו | `{{Failed}}`, `{{Total}}`, `{{Table}}`, `{{ReportsUrl}}` |
| **Staff_Weekly_Failed_Digest** | כל יום ראשון: הוראות עם חיוב שלא עבר | `{{Count}}`, `{{Table}}` |
| **Staff_Config_Error** | תקלת הגדרות מול Cardcom (פעם ביום) | — |
| **Staff_Receipt_Failures** | קבלות חודשיות שנכשלו (יומי) | `{{Count}}`, `{{Table}}` |
| **Staff_Reconciliation_Open** | פערי התאמה פתוחים (יומי) | `{{Count}}`, `{{Table}}` |
| **Staff_Reconciliation_Unavailable** | רשימת העסקאות מ-Cardcom לא זמינה | `{{Day}}`, `{{Charges}}`, `{{Checked}}` |
| **Staff_Pending_Verification** | הוראות שממתינות או נכשלו באימות (יומי) | `{{Count}}`, `{{Table}}` |
| **Staff_Schedule_Changed** | זמני החיוב עודכנו | `{{AmTime}}`, `{{PmTime}}`, `{{EveAmTime}}`, `{{EvePmTime}}`, `{{RunsPerDay}}`, `{{ReceiptTime}}`, `{{ReconcileTime}}`, `{{ChangedBy}}` |
| **Staff_Schedule_Failed** | עדכון זמני החיוב לא בוצע | `{{Command}}`, `{{Errors}}` |
| **Staff_Email_Limit** | מכסת המיילים היומית כמעט נגמרה | `{{Left}}` |

התבנית **Donor_Charge_Thanks** (מייל תודה אחרי כל חיוב) קיימת אבל המייל כבוי (D37).
