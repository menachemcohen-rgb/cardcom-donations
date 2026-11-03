/**
 * Staff alerts (Part C E11, B6.9.4). Recipients: Cardcom_Setting__mdt.Failure_Notify_Emails__c (E1); sender: the OWEA if set.
 * - failureStreak: once per streak per pledge (Failure_Alert_Sent_At__c, PledgeRollupService).
 * - configErrorOncePerDay, receiptFailures, reconciliationOpen, pendingVerificationStale, scheduleChanged: at most once a day each,
 *   tracked in Alert_State__c (E11, N30).
 * - Daily: the 09:00 schedulable (B9) running the daily alerts.
 * Email failures are caught and logged: an alert never rolls back charging.
 */
public without sharing class StaffAlertService {
  @TestVisible
  static Integer sentCount = 0;
  static final Map<String, String> FREQ_HE = new Map<String, String>{ 'OnceDaily' => 'פעם ביום', 'TwiceDaily' => 'פעמיים ביום' };

  // ---------------------------------------------------------------- B6.9.4: consecutive failures
  public static void failureStreak(Set<Id> pledgeIds) {
    Id rt = MicroPledges.recordTypeId();
    List<Messaging.SingleEmailMessage> mails = new List<Messaging.SingleEmailMessage>();
    for (Opportunity p : [
      SELECT
        Id,
        Name,
        Pledge_Number__c,
        Charge_Amount__c,
        Frequency__c,
        Consecutive_Failures__c,
        Last4__c,
        CardExpirationMMYY__c,
        Donor_First_Name__c,
        Donor_Last_Name__c,
        Donor_Contact__r.Name,
        Donor_Contact__r.Email,
        Donor_Contact__r.MobilePhone,
        (
          SELECT Scheduled_Date__c, Slot__c, Attempt_Number__c, Error_Code__c, Error_Message__c
          FROM Charges__r
          WHERE Status__c = 'Failed'
          ORDER BY Executed_At__c DESC NULLS LAST
          LIMIT 10
        )
      FROM Opportunity
      WHERE Id IN :pledgeIds AND RecordTypeId = :rt
    ]) {
      String donor = p.Donor_Contact__r != null
        ? p.Donor_Contact__r.Name
        : ((p.Donor_First_Name__c == null ? '' : p.Donor_First_Name__c) +
            ' ' +
            (p.Donor_Last_Name__c == null ? '' : p.Donor_Last_Name__c))
            .trim();
      Messaging.SingleEmailMessage m = message(
        'כישלונות חוזרים בהוראת תרומה – ' + donor + ' (' + p.Pledge_Number__c + ')',
        failureStreakBody(p, donor)
      );
      if (m != null)
        mails.add(m);
    }
    sendAll(mails); // one sendEmail call for all pledges: at most 10 calls per transaction
  }

  @TestVisible
  static String failureStreakBody(Opportunity p, String donor) {
    String rows = '';
    for (Charge__c c : p.Charges__r) {
      rows +=
        '<tr><td>' +
        EmailUtil.esc(c.Scheduled_Date__c == null ? null : c.Scheduled_Date__c.format()) +
        '</td><td>' +
        EmailUtil.esc(c.Slot__c) +
        '</td><td>' +
        EmailUtil.esc(c.Attempt_Number__c == null ? null : c.Attempt_Number__c.intValue()) +
        '</td><td>' +
        EmailUtil.esc(c.Error_Code__c) +
        '</td><td>' +
        EmailUtil.esc(c.Error_Message__c) +
        '</td></tr>';
    }
    String exp = String.isBlank(p.CardExpirationMMYY__c) || p.CardExpirationMMYY__c.length() != 4
      ? ''
      : p.CardExpirationMMYY__c.left(2) + '/' + p.CardExpirationMMYY__c.right(2);
    return '<div dir="rtl" style="font-family:Arial,sans-serif">' +
      '<p>שלום,</p>' +
      '<p>בהוראת התרומה של ' +
      EmailUtil.esc(donor) +
      ' נכשלו ' +
      EmailUtil.esc(p.Consecutive_Failures__c == null ? null : p.Consecutive_Failures__c.intValue()) +
      ' חיובים ברצף. החיובים ממשיכים לפי הלוח – לא בוצעה עצירה.</p>' +
      '<p>אם צריך, ניתן לעצור את החיובים בכפתור "הפסקת חיובים" ברשומת ההוראה.</p>' +
      '<p>פרטי התורם: ' +
      EmailUtil.esc(donor) +
      ' · ' +
      EmailUtil.esc(p.Donor_Contact__r == null ? null : p.Donor_Contact__r.Email) +
      ' · ' +
      EmailUtil.esc(p.Donor_Contact__r == null ? null : p.Donor_Contact__r.MobilePhone) +
      '</p>' +
      '<p>ההוראה: ' +
      EmailUtil.esc(p.Pledge_Number__c) +
      ' · ' +
      EmailUtil.esc(p.Charge_Amount__c) +
      ' ₪ · ' +
      EmailUtil.esc(FREQ_HE.get(p.Frequency__c)) +
      ' · כרטיס המסתיים ב-' +
      EmailUtil.esc(p.Last4__c) +
      ', תוקף ' +
      EmailUtil.esc(exp) +
      '</p>' +
      '<table border="1" cellpadding="4" style="border-collapse:collapse"><tr><th>תאריך</th><th>סבב</th><th>ניסיון</th><th>קוד</th><th>תיאור</th></tr>' +
      rows +
      '</table>' +
      '<p><a href="' +
      EmailUtil.recordUrl(p.Id) +
      '">לצפייה ברשומה</a></p></div>';
  }

  // ---------------------------------------------------------------- once-a-day alerts
  /** "תקלת הגדרות Cardcom" (B5.8 HTTP 401/400). @return true if sent now. */
  public static Boolean configErrorOncePerDay() {
    if (sentToday('Config_Error_Sent_On__c'))
      return false;
    send(
      'תקלת הגדרות Cardcom',
      wrap(
        '<p>חיובי התרומות נכשלו בגלל תקלת הגדרות מול Cardcom (למשל שם משתמש או סיסמת API שגויים, או טרמינל לא תקין).</p>' +
          '<p>לא נוצרו ניסיונות חוזרים והכישלונות לא נספרים ברצף. אחרי התיקון יש להריץ מחדש את חיובי היום ' +
          '(ChargeAdmin.requeueFailedConfig).</p>'
      )
    );
    markSent('Config_Error_Sent_On__c');
    return true;
  }

  /** "קבלות חודשיות שנכשלו" — daily until handled. @return true if sent now. */
  public static Boolean receiptFailures() {
    if (sentToday('Receipt_Failures_Sent_On__c'))
      return false;
    List<Monthly_Receipt__c> rs = [
      SELECT Id, Name, Contact__r.Name, Period_Month__c, Status__c, Total_Amount__c, Error_Code__c, Error_Message__c
      FROM Monthly_Receipt__c
      WHERE Status__c IN ('Failed', 'Needs_Verification')
      ORDER BY Period_Month__c DESC
      LIMIT 50
    ];
    if (rs.isEmpty())
      return false;
    String rows = '';
    for (Monthly_Receipt__c r : rs) {
      rows +=
        '<tr><td><a href="' +
        EmailUtil.recordUrl(r.Id) +
        '">' +
        EmailUtil.esc(r.Name) +
        '</a></td><td>' +
        EmailUtil.esc(r.Contact__r.Name) +
        '</td><td>' +
        EmailUtil.esc(r.Period_Month__c == null ? null : r.Period_Month__c.format()) +
        '</td><td>' +
        EmailUtil.esc(r.Status__c) +
        '</td><td>' +
        EmailUtil.esc(r.Total_Amount__c) +
        '</td><td>' +
        EmailUtil.esc(r.Error_Code__c) +
        ' ' +
        EmailUtil.esc(r.Error_Message__c) +
        '</td></tr>';
    }
    send(
      'קבלות חודשיות שנכשלו (' + rs.size() + ')',
      wrap(
        '<p>הקבלות הבאות לא הופקו או שתוצאתן לא ידועה. יש לבדוק ולהפעיל "ניסיון חוזר".</p>' +
        table(new List<String>{ 'קבלה', 'תורם', 'חודש', 'סטטוס', 'סכום', 'שגיאה' }, rows)
      )
    );
    markSent('Receipt_Failures_Sent_On__c');
    return true;
  }

  /** "פערי התאמה פתוחים" — daily if there are open issues. @return true if sent now. */
  public static Boolean reconciliationOpen() {
    if (sentToday('Reconciliation_Open_Sent_On__c'))
      return false;
    List<Reconciliation_Issue__c> rs = [
      SELECT Id, Name, Issue_Type__c, Business_Date__c, Cardcom_Tranzaction_Id__c, Cardcom_Amount__c, SF_Amount__c
      FROM Reconciliation_Issue__c
      WHERE Status__c = 'Open'
      ORDER BY Business_Date__c DESC
      LIMIT 50
    ];
    if (rs.isEmpty())
      return false;
    String rows = '';
    for (Reconciliation_Issue__c r : rs) {
      rows +=
        '<tr><td><a href="' +
        EmailUtil.recordUrl(r.Id) +
        '">' +
        EmailUtil.esc(r.Name) +
        '</a></td><td>' +
        EmailUtil.esc(r.Issue_Type__c) +
        '</td><td>' +
        EmailUtil.esc(r.Business_Date__c == null ? null : r.Business_Date__c.format()) +
        '</td><td>' +
        EmailUtil.esc(r.Cardcom_Tranzaction_Id__c) +
        '</td><td>' +
        EmailUtil.esc(r.Cardcom_Amount__c) +
        '</td><td>' +
        EmailUtil.esc(r.SF_Amount__c) +
        '</td></tr>';
    }
    send(
      'פערי התאמה פתוחים (' + rs.size() + ')',
      wrap(
        '<p>ההתאמה הלילית מול Cardcom מצאה פערים שעדיין פתוחים.</p>' +
        table(new List<String>{ 'פער', 'סוג', 'תאריך', 'עסקה', 'סכום Cardcom', 'סכום Salesforce' }, rows)
      )
    );
    markSent('Reconciliation_Open_Sent_On__c');
    return true;
  }

  /**
   * The nightly list from Cardcom can't be compared (N86): it has none of the day's TranzactionIds. Charges are checked one by one
   * instead. Once a day. @return true if sent now.
   */
  public static Boolean reconciliationUnavailable(Date day, Integer charges, Integer checkedNow) {
    if (sentToday('Reconciliation_Unavailable_Sent_On__c'))
      return false;
    send(
      'התאמה לילית: רשימת העסקאות מ-Cardcom לא זמינה',
      wrap(
        '<p>רשימת העסקאות שהתקבלה מ-Cardcom ליום ' +
          EmailUtil.esc(day == null ? null : day.format()) +
          ' לא כוללת אף אחד מ-' +
          EmailUtil.esc(charges) +
          ' החיובים המוצלחים של אותו יום, ולכן לא בוצעה השוואה מולה.</p>' +
          '<p>במקום זאת כל חיוב נבדק בנפרד מול Cardcom (' +
          EmailUtil.esc(checkedNow) +
          ' נבדקו בריצה הראשונה, השאר בהמשך). פער ייפתח רק לחיוב ש-Cardcom לא מצאה.</p>' +
          '<p>כדאי לבדוק את הרשאות ה-API ואת מספר הטרמינל (LimitForTerminal) מול Cardcom.</p>'
      )
    );
    markSent('Reconciliation_Unavailable_Sent_On__c');
    return true;
  }

  /** "הוראות ממתינות לאימות > 24 ש'" plus pledges that failed verification in the last day (7.7ב). @return true if sent now. */
  public static Boolean pendingVerificationStale() {
    if (sentToday('Daily_Summary_Sent_On__c'))
      return false;
    Id rt = MicroPledges.recordTypeId();
    Datetime dayAgo = Datetime.now().addHours(-24);
    List<Opportunity> ps = [
      SELECT Id, Name, StageName, CreatedDate, Donor_First_Name__c, Donor_Last_Name__c, Donor_Email__c, Lp_Check_Count__c
      FROM Opportunity
      WHERE
        RecordTypeId = :rt
        AND ((StageName = :MicroPledges.STAGE_PENDING
        AND CreatedDate <= :dayAgo)
        OR (StageName = :MicroPledges.STAGE_VERIFICATION_FAILED
        AND LastModifiedDate >= :dayAgo))
      ORDER BY CreatedDate DESC
      LIMIT 50
    ];
    if (ps.isEmpty())
      return false;
    String rows = '';
    for (Opportunity p : ps) {
      rows +=
        '<tr><td><a href="' +
        EmailUtil.recordUrl(p.Id) +
        '">' +
        EmailUtil.esc(p.Name) +
        '</a></td><td>' +
        EmailUtil.esc(p.StageName) +
        '</td><td>' +
        EmailUtil.esc(
          (p.Donor_First_Name__c == null ? '' : p.Donor_First_Name__c) + ' ' + (p.Donor_Last_Name__c == null ? '' : p.Donor_Last_Name__c)
        ) +
        '</td><td>' +
        EmailUtil.esc(p.Donor_Email__c) +
        '</td><td>' +
        EmailUtil.esc(p.CreatedDate.format('dd/MM/yyyy HH:mm')) +
        '</td></tr>';
    }
    send(
      'הוראות ממתינות או שנכשלו באימות (' + ps.size() + ')',
      wrap(
        '<p>הוראות שלא הושלם בהן אימות הכרטיס: ממתינות יותר מ-24 שעות, או שנכשלו באימות ביממה האחרונה.</p>' +
        table(new List<String>{ 'הוראה', 'סטטוס', 'שם', 'אימייל', 'נוצרה' }, rows)
      )
    );
    markSent('Daily_Summary_Sent_On__c');
    return true;
  }

  /** "זמני חיוב עודכנו" + the new values (B9.1). */
  public static void scheduleChanged(Charge_Settings__c s) {
    if (sentToday('Schedule_Changed_Sent_On__c'))
      return;
    send(
      'זמני חיוב עודכנו',
      wrap(
        '<p>זמני החיוב עודכנו והוחלו:</p>' +
          '<p>בוקר ' +
          EmailUtil.esc(s.AM_Time__c) +
          ' · ערב ' +
          EmailUtil.esc(s.PM_Time__c) +
          ' · שישי/ערב חג ' +
          EmailUtil.esc(s.Eve_AM_Time__c) +
          ' ו-' +
          EmailUtil.esc(s.Eve_PM_Time__c) +
          ' · ריצות ביום ' +
          EmailUtil.esc(s.Runs_Per_Day__c == null ? null : s.Runs_Per_Day__c.intValue()) +
          ' · קבלות ' +
          EmailUtil.esc(s.Receipt_Time__c) +
          ' · התאמה ' +
          EmailUtil.esc(s.Reconcile_Time__c) +
          '</p>' +
          '<p>עודכן ע"י ' +
          EmailUtil.esc(UserInfo.getName()) +
          '.</p>'
      )
    );
    markSent('Schedule_Changed_Sent_On__c');
  }

  /** B6.9.5: the org's daily single-email budget is almost used up — donor thank-you emails are being skipped. Once a day. */
  /** The integration user could not apply a schedule command (N42). Sent every time: it answers an admin's request. */
  public static void scheduleFailed(String command, List<String> errs) {
    String items = '';
    for (String x : errs)
      items += '<li>' + EmailUtil.esc(x) + '</li>';
    send(
      'זמני החיוב לא עודכנו',
      wrap('<p>הבקשה (' + EmailUtil.esc(command) + ') לא בוצעה. ריצות החיוב הקיימות לא השתנו.</p><ul>' + items + '</ul>')
    );
  }

  public static Boolean emailLimit(Integer left) {
    if (sentToday('Email_Limit_Sent_On__c'))
      return false;
    send(
      'מכסת המיילים היומית כמעט נגמרה',
      wrap(
        '<p>נותרו ' +
          EmailUtil.esc(left) +
          ' מיילים יומיים בארגון. מיילי התודה לתורמים לא נשלחים עד מחר ' +
          '(החיובים עצמם ממשיכים כרגיל). כדאי לבדוק את נפח המיילים (Q9).</p>'
      )
    );
    markSent('Email_Limit_Sent_On__c');
    return true;
  }

  /** 09:00 SUN-FRI (B9 "Donations Daily Alerts"). */
  public class Daily implements Schedulable {
    public Daily() {
    }
    public void execute(SchedulableContext sc) {
      receiptFailures();
      reconciliationOpen();
      pendingVerificationStale();
    }
  }

  // ---------------------------------------------------------------- helpers
  /** Part C E1: Failure_Notify_Emails__c split on , or ; — trimmed, blanks dropped. */
  @TestVisible
  static List<String> recipients() {
    List<String> out = new List<String>();
    String raw = CardcomService.settings().Failure_Notify_Emails__c;
    if (String.isBlank(raw))
      return out;
    for (String a : raw.split('[;,]'))
      if (String.isNotBlank(a))
        out.add(a.trim());
    return out;
  }

  static Boolean sentToday(String field) {
    Alert_State__c st = Alert_State__c.getOrgDefaults();
    return st != null && st.get(field) == Date.today();
  }

  static void markSent(String field) {
    Alert_State__c st = Alert_State__c.getOrgDefaults();
    if (st == null || st.Id == null)
      st = new Alert_State__c(SetupOwnerId = UserInfo.getOrganizationId());
    st.put(field, Date.today());
    upsert st;
  }

  static String wrap(String body) {
    return '<div dir="rtl" style="font-family:Arial,sans-serif"><p>שלום,</p>' + body + '</div>';
  }

  static String table(List<String> headers, String rows) {
    String h = '';
    for (String x : headers)
      h += '<th>' + EmailUtil.esc(x) + '</th>';
    return '<table border="1" cellpadding="4" style="border-collapse:collapse"><tr>' + h + '</tr>' + rows + '</table>';
  }

  static void send(String subject, String html) {
    Messaging.SingleEmailMessage m = message(subject, html);
    if (m != null)
      sendAll(new List<Messaging.SingleEmailMessage>{ m });
  }

  /** null when no recipients are configured. */
  static Messaging.SingleEmailMessage message(String subject, String html) {
    List<String> to = recipients();
    if (to.isEmpty()) {
      System.debug(LoggingLevel.WARN, 'Staff alert not sent, no Failure_Notify_Emails__c: ' + subject);
      return null;
    }
    Messaging.SingleEmailMessage m = new Messaging.SingleEmailMessage();
    m.setToAddresses(to);
    Id owea = EmailUtil.oweaId(CardcomService.settings().Org_Wide_Email_Address__c);
    if (owea != null)
      m.setOrgWideEmailAddressId(owea);
    m.setSubject(subject);
    m.setHtmlBody(html);
    m.setSaveAsActivity(false);
    return m;
  }

  static void sendAll(List<Messaging.SingleEmailMessage> mails) {
    if (mails.isEmpty())
      return;
    // The email-invocation limit throws an uncatchable LimitException; never let an alert hit it (it would roll back charges).
    if (Limits.getEmailInvocations() >= Limits.getLimitEmailInvocations()) {
      System.debug(LoggingLevel.ERROR, 'Staff alert skipped, email invocation limit reached: ' + mails.size());
      return;
    }
    sentCount += mails.size();
    try {
      Messaging.sendEmail(mails, false);
    } catch (Exception e) {
      // An alert must never roll back charge processing (e.g. Email Deliverability set to "System email only").
      System.debug(LoggingLevel.ERROR, 'Staff alert email failed: ' + e.getMessage());
    }
  }
}
