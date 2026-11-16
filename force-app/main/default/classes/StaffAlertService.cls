/**
 * Staff alerts (Part C E11, B6.9.4). Recipients: Cardcom_Setting__mdt.Failure_Notify_Emails__c (E1); sender: the OWEA if set.
 * - failureStreak: once per streak per pledge (Failure_Alert_Sent_At__c, PledgeRollupService).
 * - configErrorOncePerDay, receiptFailures, reconciliationOpen, pendingVerificationStale, scheduleChanged: at most once a day each,
 *   tracked in Alert_State__c (E11, N30).
 * - highAmount: an Active pledge charging more than Charge_Settings__c.High_Amount_Alert__c (default 25 ₪) per Shacharit or
 *   Mincha charge — once when it becomes Active, and again whenever its above-threshold amounts change.
 * - Daily: the 09:00 schedulable (B9) running the daily alerts.
 * Email failures are caught and logged: an alert never rolls back charging.
 * Text: one Classic Email Template per alert (Staff_*, folder "Donations"), editable by admins (EmailTemplates; placeholders in
 * docs/email-templates-he.md). Tables and lists are built here and passed as {{Table}} / {{Errors}}; the defaults below are used
 * only when a template is missing or blank.
 */
public without sharing class StaffAlertService {
  @TestVisible
  static Integer sentCount = 0;

  // ---------------------------------------------------------------- B6.9.4: consecutive failures
  public static void failureStreak(Set<Id> pledgeIds) {
    String pledgeType = MicroPledges.TYPE;
    List<Messaging.SingleEmailMessage> mails = new List<Messaging.SingleEmailMessage>();
    for (Opportunity p : [
      SELECT
        Id,
        Name,
        Pledge_Number__c,
        Charge_Amount__c,
        Mincha_Amount__c,
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
      WHERE Id IN :pledgeIds AND Type = :pledgeType
    ]) {
      String donor = p.Donor_Contact__r != null
        ? p.Donor_Contact__r.Name
        : ((p.Donor_First_Name__c == null ? '' : p.Donor_First_Name__c) +
            ' ' +
            (p.Donor_Last_Name__c == null ? '' : p.Donor_Last_Name__c))
            .trim();
      EmailTemplates.Rendered r = failureStreakRendered(p, donor);
      Messaging.SingleEmailMessage m = message(r.subject, r.html);
      if (m != null)
        mails.add(m);
    }
    sendAll(mails); // one sendEmail call for all pledges: at most 10 calls per transaction
  }

  // ---------------------------------------------------------------- high amount per charge
  /** Amount per charge above which staff are emailed (Charge_Settings__c.High_Amount_Alert__c, blank = 25). */
  public static Decimal highAmountThreshold() {
    Decimal t = ChargeSettings.get().High_Amount_Alert__c;
    return t == null ? 25 : t;
  }

  /** "שחרית 30.00 ₪ · מנחה 40.00 ₪" for the slots the pledge charges above the threshold; '' when none. */
  @TestVisible
  static String highSlots(Opportunity p) {
    List<String> out = new List<String>();
    Decimal t = highAmountThreshold();
    for (String slot : new List<String>{ MicroPledges.SLOT_SHACHARIT, MicroPledges.SLOT_MINCHA }) {
      Decimal a = MicroPledges.hasSlot(p.Frequency__c, slot) ? MicroPledges.amountFor(p, slot) : null;
      if (a != null && a > t)
        out.add(MicroPledges.slotHe(slot) + ' ' + a.setScale(2) + ' ₪');
    }
    return String.join(out, ' · ');
  }

  /**
   * A pledge that is Active now with an amount above the threshold, and either just became Active from verification (a new
   * pledge) or was already Active and its above-threshold amounts changed (donor page, staff edit, new card with a new amount).
   * A resume (Stopped → Active) with the same amounts is not alerted again.
   */
  public static Boolean isNewHighAmount(Opportunity n, Opportunity o) {
    if (n.StageName != MicroPledges.STAGE_ACTIVE)
      return false;
    String now = highSlots(n);
    if (String.isBlank(now))
      return false;
    if (o.StageName == MicroPledges.STAGE_PENDING)
      return true;
    return o.StageName == MicroPledges.STAGE_ACTIVE && now != highSlots(o);
  }

  static final String HIGH_AMOUNT_SUBJECT = 'הוראת תרומה בסכום גבוה – {{Donor}} ({{PledgeNumber}})';
  static final String HIGH_AMOUNT_BODY =
    '<p>בהוראת התרומה של {{Donor}} הסכום לחיוב גבוה מ-{{Threshold}} ₪: {{HighAmounts}}.</p>' +
    '<p>פרטי התורם: {{Donor}} · {{DonorEmail}} · {{DonorPhone}}</p>' +
    '<p>ההוראה: {{PledgeNumber}} · {{Frequency}} · {{Amounts}}</p>' +
    '<p><a href="{{RecordUrl}}">לצפייה ברשומה</a></p>';

  public static void highAmount(Set<Id> pledgeIds) {
    String pledgeType = MicroPledges.TYPE;
    List<Messaging.SingleEmailMessage> mails = new List<Messaging.SingleEmailMessage>();
    for (Opportunity p : [
      SELECT
        Id,
        Pledge_Number__c,
        Charge_Amount__c,
        Mincha_Amount__c,
        Frequency__c,
        Donor_First_Name__c,
        Donor_Last_Name__c,
        Donor_Email__c,
        Donor_Phone__c,
        Donor_Contact__r.Name,
        Donor_Contact__r.Email,
        Donor_Contact__r.MobilePhone
      FROM Opportunity
      WHERE Id IN :pledgeIds AND Type = :pledgeType
    ]) {
      String donor = p.Donor_Contact__r != null
        ? p.Donor_Contact__r.Name
        : ((p.Donor_First_Name__c == null ? '' : p.Donor_First_Name__c) +
            ' ' +
            (p.Donor_Last_Name__c == null ? '' : p.Donor_Last_Name__c))
            .trim();
      String email = p.Donor_Contact__r != null && String.isNotBlank(p.Donor_Contact__r.Email)
        ? p.Donor_Contact__r.Email
        : p.Donor_Email__c;
      String phone = p.Donor_Contact__r != null && String.isNotBlank(p.Donor_Contact__r.MobilePhone)
        ? p.Donor_Contact__r.MobilePhone
        : p.Donor_Phone__c;
      EmailTemplates.Rendered r = EmailTemplates.render(
        'Staff_High_Amount',
        HIGH_AMOUNT_SUBJECT,
        wrap(HIGH_AMOUNT_BODY),
        new Map<String, String>{
          'Donor' => EmailUtil.esc(donor),
          'Threshold' => EmailUtil.esc(highAmountThreshold().setScale(2)),
          'HighAmounts' => EmailUtil.esc(highSlots(p)),
          'DonorEmail' => EmailUtil.esc(email),
          'DonorPhone' => EmailUtil.esc(phone),
          'PledgeNumber' => EmailUtil.esc(p.Pledge_Number__c),
          'Frequency' => EmailUtil.esc(MicroPledges.frequencyHe(p.Frequency__c)),
          'Amounts' => EmailUtil.esc(MicroPledges.amountsHe(p)),
          'RecordUrl' => EmailUtil.recordUrl(p.Id)
        },
        new Map<String, String>{ 'Donor' => donor, 'PledgeNumber' => p.Pledge_Number__c }
      );
      Messaging.SingleEmailMessage m = message(r.subject, r.html);
      if (m != null)
        mails.add(m);
    }
    sendAll(mails);
  }

  static final String FAILURE_STREAK_SUBJECT = 'כישלונות חוזרים בהוראת תרומה – {{Donor}} ({{PledgeNumber}})';
  static final String FAILURE_STREAK_BODY =
    '<p>בהוראת התרומה של {{Donor}} נכשלו {{Count}} חיובים ברצף. החיובים ממשיכים לפי הלוח – לא בוצעה עצירה.</p>' +
    '<p>אם צריך, ניתן לעצור את החיובים בכפתור "הפסקת חיובים" ברשומת ההוראה.</p>' +
    '<p>פרטי התורם: {{Donor}} · {{DonorEmail}} · {{DonorPhone}}</p>' +
    '<p>ההוראה: {{PledgeNumber}} · {{Frequency}} · {{Amounts}} · כרטיס המסתיים ב-{{Last4}}, תוקף {{Expiry}}</p>' +
    '{{Table}}' +
    '<p><a href="{{RecordUrl}}">לצפייה ברשומה</a></p>';

  @TestVisible
  static String failureStreakBody(Opportunity p, String donor) {
    return failureStreakRendered(p, donor).html;
  }

  static EmailTemplates.Rendered failureStreakRendered(Opportunity p, String donor) {
    String rows = '';
    for (Charge__c c : p.Charges__r) {
      rows +=
        '<tr><td>' +
        EmailUtil.esc(c.Scheduled_Date__c == null ? null : c.Scheduled_Date__c.format()) +
        '</td><td>' +
        EmailUtil.esc(MicroPledges.slotHe(c.Slot__c)) +
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
    Map<String, String> v = new Map<String, String>{
      'Donor' => EmailUtil.esc(donor),
      'Count' => EmailUtil.esc(p.Consecutive_Failures__c == null ? null : p.Consecutive_Failures__c.intValue()),
      'DonorEmail' => EmailUtil.esc(p.Donor_Contact__r == null ? null : p.Donor_Contact__r.Email),
      'DonorPhone' => EmailUtil.esc(p.Donor_Contact__r == null ? null : p.Donor_Contact__r.MobilePhone),
      'PledgeNumber' => EmailUtil.esc(p.Pledge_Number__c),
      'Frequency' => EmailUtil.esc(MicroPledges.frequencyHe(p.Frequency__c)),
      'Amounts' => EmailUtil.esc(MicroPledges.amountsHe(p)),
      'Last4' => EmailUtil.esc(p.Last4__c),
      'Expiry' => EmailUtil.esc(exp),
      'Table' => table(new List<String>{ 'תאריך', 'תפילה', 'ניסיון', 'קוד', 'תיאור' }, rows),
      'RecordUrl' => EmailUtil.recordUrl(p.Id)
    };
    return EmailTemplates.render(
      'Staff_Failure_Streak',
      FAILURE_STREAK_SUBJECT,
      wrap(FAILURE_STREAK_BODY),
      v,
      new Map<String, String>{ 'Donor' => donor, 'PledgeNumber' => p.Pledge_Number__c }
    );
  }

  // ---------------------------------------------------------------- once-a-day alerts
  /** "תקלת הגדרות Cardcom" (B5.8 HTTP 401/400). @return true if sent now. */
  public static Boolean configErrorOncePerDay() {
    if (sentToday('Config_Error_Sent_On__c'))
      return false;
    sendTemplate(
      'Staff_Config_Error',
      'תקלת הגדרות Cardcom',
      '<p>חיובי התרומות נכשלו בגלל תקלת הגדרות מול Cardcom (למשל שם משתמש או סיסמת API שגויים, או טרמינל לא תקין).</p>' +
        '<p>לא נוצרו ניסיונות חוזרים והכישלונות לא נספרים ברצף. אחרי התיקון יש להריץ מחדש את חיובי היום ' +
        '(ChargeAdmin.requeueFailedConfig).</p>',
      new Map<String, String>()
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
    sendTemplate(
      'Staff_Receipt_Failures',
      'קבלות חודשיות שנכשלו ({{Count}})',
      '<p>הקבלות הבאות לא הופקו או שתוצאתן לא ידועה. יש לבדוק ולהפעיל "ניסיון חוזר".</p>{{Table}}',
      new Map<String, String>{
        'Count' => String.valueOf(rs.size()),
        'Table' => table(new List<String>{ 'קבלה', 'תורם', 'חודש', 'סטטוס', 'סכום', 'שגיאה' }, rows)
      }
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
    sendTemplate(
      'Staff_Reconciliation_Open',
      'פערי התאמה פתוחים ({{Count}})',
      '<p>ההתאמה הלילית מול Cardcom מצאה פערים שעדיין פתוחים.</p>{{Table}}',
      new Map<String, String>{
        'Count' => String.valueOf(rs.size()),
        'Table' => table(new List<String>{ 'פער', 'סוג', 'תאריך', 'עסקה', 'סכום Cardcom', 'סכום Salesforce' }, rows)
      }
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
    sendTemplate(
      'Staff_Reconciliation_Unavailable',
      'התאמה לילית: רשימת העסקאות מ-Cardcom לא זמינה',
      '<p>רשימת העסקאות שהתקבלה מ-Cardcom ליום {{Day}} לא כוללת אף אחד מ-{{Charges}} החיובים המוצלחים של אותו יום, ' +
        'ולכן לא בוצעה השוואה מולה.</p>' +
        '<p>במקום זאת כל חיוב נבדק בנפרד מול Cardcom ({{Checked}} נבדקו בריצה הראשונה, השאר בהמשך). ' +
        'פער ייפתח רק לחיוב ש-Cardcom לא מצאה.</p>' +
        '<p>כדאי לבדוק את הרשאות ה-API ואת מספר הטרמינל (LimitForTerminal) מול Cardcom.</p>',
      new Map<String, String>{
        'Day' => EmailUtil.esc(day == null ? null : day.format()),
        'Charges' => EmailUtil.esc(charges),
        'Checked' => EmailUtil.esc(checkedNow)
      }
    );
    markSent('Reconciliation_Unavailable_Sent_On__c');
    return true;
  }

  /** "הוראות ממתינות לאימות > 24 ש'" plus pledges that failed verification in the last day (7.7ב). @return true if sent now. */
  public static Boolean pendingVerificationStale() {
    if (sentToday('Daily_Summary_Sent_On__c'))
      return false;
    String pledgeType = MicroPledges.TYPE;
    Datetime dayAgo = Datetime.now().addHours(-24);
    List<Opportunity> ps = [
      SELECT Id, Name, StageName, CreatedDate, Donor_First_Name__c, Donor_Last_Name__c, Donor_Email__c, Lp_Check_Count__c
      FROM Opportunity
      WHERE
        Type = :pledgeType
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
    sendTemplate(
      'Staff_Pending_Verification',
      'הוראות ממתינות או שנכשלו באימות ({{Count}})',
      '<p>הוראות שלא הושלם בהן אימות הכרטיס: ממתינות יותר מ-24 שעות, או שנכשלו באימות ביממה האחרונה.</p>{{Table}}',
      new Map<String, String>{
        'Count' => String.valueOf(ps.size()),
        'Table' => table(new List<String>{ 'הוראה', 'סטטוס', 'שם', 'אימייל', 'נוצרה' }, rows)
      }
    );
    markSent('Daily_Summary_Sent_On__c');
    return true;
  }

  /** "זמני חיוב עודכנו" + the new values (B9.1). */
  public static void scheduleChanged(Charge_Settings__c s) {
    if (sentToday('Schedule_Changed_Sent_On__c'))
      return;
    sendTemplate(
      'Staff_Schedule_Changed',
      'זמני חיוב עודכנו',
      '<p>זמני החיוב עודכנו והוחלו:</p>' +
        '<p>בוקר {{AmTime}} · ערב {{PmTime}} · שישי/ערב חג {{EveAmTime}} ו-{{EvePmTime}} · ריצות ביום {{RunsPerDay}} · ' +
        'קבלות {{ReceiptTime}} · התאמה {{ReconcileTime}}</p>' +
        '<p>עודכן ע"י {{ChangedBy}}.</p>',
      new Map<String, String>{
        'AmTime' => EmailUtil.esc(s.AM_Time__c),
        'PmTime' => EmailUtil.esc(s.PM_Time__c),
        'EveAmTime' => EmailUtil.esc(s.Eve_AM_Time__c),
        'EvePmTime' => EmailUtil.esc(s.Eve_PM_Time__c),
        'RunsPerDay' => EmailUtil.esc(s.Runs_Per_Day__c == null ? null : s.Runs_Per_Day__c.intValue()),
        'ReceiptTime' => EmailUtil.esc(s.Receipt_Time__c),
        'ReconcileTime' => EmailUtil.esc(s.Reconcile_Time__c),
        'ChangedBy' => EmailUtil.esc(UserInfo.getName())
      }
    );
    markSent('Schedule_Changed_Sent_On__c');
  }

  /** B6.9.5: the org's daily single-email budget is almost used up — donor thank-you emails are being skipped. Once a day. */
  /** The integration user could not apply a schedule command (N42). Sent every time: it answers an admin's request. */
  public static void scheduleFailed(String command, List<String> errs) {
    String items = '';
    for (String x : errs)
      items += '<li>' + EmailUtil.esc(x) + '</li>';
    sendTemplate(
      'Staff_Schedule_Failed',
      'זמני החיוב לא עודכנו',
      '<p>הבקשה ({{Command}}) לא בוצעה. ריצות החיוב הקיימות לא השתנו.</p><ul>{{Errors}}</ul>',
      new Map<String, String>{ 'Command' => EmailUtil.esc(command), 'Errors' => items }
    );
  }

  public static Boolean emailLimit(Integer left) {
    if (sentToday('Email_Limit_Sent_On__c'))
      return false;
    sendTemplate(
      'Staff_Email_Limit',
      'מכסת המיילים היומית כמעט נגמרה',
      '<p>נותרו {{Left}} מיילים יומיים בארגון. מיילי התודה לתורמים לא נשלחים עד מחר ' +
      '(החיובים עצמם ממשיכים כרגיל). כדאי לבדוק את נפח המיילים (Q9).</p>',
      new Map<String, String>{ 'Left' => EmailUtil.esc(left) }
    );
    markSent('Email_Limit_Sent_On__c');
    return true;
  }

  /** 09:00 SUN-FRI (B9 "Donations Daily Alerts"). */
  /**
   * D38: "charges are not going through" — sent to Failure_Notify_Emails__c (ATO admin and the developers) when, in the last 3
   * hours, at least 3 attempts were sent and half or more of them failed. At most one alert every 4 hours (Alert_State__c).
   */
  @TestVisible
  static Datetime nowOverride;
  @TestVisible
  static Boolean runFailuresInTests = false; // other tests' failed charges must not add this alert to their counts
  public static void runFailures() {
    if (Test.isRunningTest() && !runFailuresInTests)
      return;
    Datetime now = nowOverride != null ? nowOverride : Datetime.now();
    Alert_State__c st = Alert_State__c.getOrgDefaults();
    if (st != null && st.Run_Failure_Sent_At__c != null && st.Run_Failure_Sent_At__c > now.addHours(-4))
      return;
    Datetime since = now.addHours(-3);
    Integer total = 0, failed = 0;
    Map<String, Integer> byCode = new Map<String, Integer>();
    for (AggregateResult ar : [
      SELECT Status__c st, Error_Code__c code, COUNT(Id) n
      FROM Charge__c
      WHERE Executed_At__c >= :since AND Status__c IN ('Success', 'Failed')
      GROUP BY Status__c, Error_Code__c
    ]) {
      Integer n = (Integer) ar.get('n');
      total += n;
      if ((String) ar.get('st') == 'Failed') {
        failed += n;
        String code = ar.get('code') == null ? '?' : (String) ar.get('code');
        byCode.put(code, (byCode.containsKey(code) ? byCode.get(code) : 0) + n);
      }
    }
    if (total < 3 || failed * 2 < total)
      return;
    String rows = '';
    for (String code : byCode.keySet())
      rows += '<tr><td>' + EmailUtil.esc(code) + '</td><td>' + byCode.get(code) + '</td></tr>';
    sendTemplate(
      'Staff_Run_Failures',
      'תקלת סליקה: {{Failed}} מתוך {{Total}} חיובים נכשלו',
      '<p>בשלוש השעות האחרונות נשלחו ל-Cardcom {{Total}} חיובים, ו-{{Failed}} מהם נכשלו. כשרוב החיובים נכשלים יחד, ' +
        'הסיבה בדרך כלל אינה בכרטיסים של התורמים אלא בטרמינל או בהגדרות.</p>' +
        '{{Table}}' +
        '<p>מה לבדוק: הודעות במסוף Cardcom, פרטי הגישה ל-API (External Credential Cardcom_EC), ומצב הטרמינל. ' +
        'אם צריך לעצור את כל החיובים: Charge Settings → Charging Enabled.</p>' +
        '<p><a href="{{ReportsUrl}}">דוח "חיובים שלא עברו"</a></p>',
      new Map<String, String>{
        'Failed' => String.valueOf(failed),
        'Total' => String.valueOf(total),
        'Table' => table(new List<String>{ 'קוד שגיאה', 'מספר חיובים' }, rows),
        'ReportsUrl' => URL.getOrgDomainUrl().toExternalForm() + '/lightning/o/Report/home'
      }
    );
    if (st == null || st.Id == null)
      st = new Alert_State__c(SetupOwnerId = UserInfo.getOrganizationId());
    st.Run_Failure_Sent_At__c = now;
    upsert st;
  }

  /** D38: every Sunday after the donor reminders — the open payment issues, so staff can call the donors. */
  public static void weeklyFailedDigest() {
    String pledgeType = MicroPledges.TYPE;
    String active = MicroPledges.STAGE_ACTIVE;
    String rows = '';
    Integer n = 0;
    for (Opportunity p : [
      SELECT
        Id,
        Pledge_Number__c,
        Payment_Issue_Since__c,
        Consecutive_Failures__c,
        Last_Failure_Error__c,
        Failure_Reminders_Stopped__c,
        Donor_First_Name__c,
        Donor_Last_Name__c,
        Donor_Phone__c,
        Donor_Contact__r.Name,
        Donor_Contact__r.Email,
        Donor_Contact__r.MobilePhone
      FROM Opportunity
      WHERE Type = :pledgeType AND StageName = :active AND Payment_Issue_Since__c != NULL
      ORDER BY Payment_Issue_Since__c
      LIMIT 200
    ]) {
      n++;
      String name = p.Donor_Contact__r != null ? p.Donor_Contact__r.Name : (p.Donor_First_Name__c + ' ' + p.Donor_Last_Name__c);
      String phone = p.Donor_Contact__r != null && String.isNotBlank(p.Donor_Contact__r.MobilePhone)
        ? p.Donor_Contact__r.MobilePhone
        : p.Donor_Phone__c;
      rows +=
        '<tr><td><a href="' +
        EmailUtil.recordUrl(p.Id) +
        '">' +
        EmailUtil.esc(p.Pledge_Number__c) +
        '</a></td><td>' +
        EmailUtil.esc(name) +
        '</td><td>' +
        EmailUtil.esc(phone) +
        '</td><td>' +
        EmailUtil.esc(p.Donor_Contact__r == null ? null : p.Donor_Contact__r.Email) +
        '</td><td>' +
        EmailUtil.esc(p.Payment_Issue_Since__c == null ? null : p.Payment_Issue_Since__c.format('dd/MM/yyyy')) +
        '</td><td>' +
        EmailUtil.esc(p.Consecutive_Failures__c) +
        '</td><td>' +
        EmailUtil.esc(p.Last_Failure_Error__c) +
        '</td><td>' +
        (p.Failure_Reminders_Stopped__c == true ? 'עצורות' : 'נשלחות') +
        '</td></tr>';
    }
    if (n == 0)
      return;
    sendTemplate(
      'Staff_Weekly_Failed_Digest',
      'הוראות עם חיובים שלא עברו – {{Count}}',
      '<p>להוראות הבאות יש חיוב שלא עבר. התורמים מקבלים תזכורת במייל בכל יום ראשון עם קישור להחלפת כרטיס.</p>' +
        '{{Table}}' +
        '<p>מה אפשר לעשות: להתקשר לתורם ולבקש להחליף כרטיס דרך הקישור במייל; אם התורם מבקש להפסיק – "הפסקת חיובים" בהוראה; ' +
        'כדי להפסיק רק את התזכורות – לסמן "עצירת תזכורות כישלון" בהוראה.</p>',
      new Map<String, String>{
        'Count' => String.valueOf(n),
        'Table' => table(new List<String>{ 'הוראה', 'תורם', 'טלפון', 'מייל', 'מאז', 'כישלונות רצופים', 'שגיאה אחרונה', 'תזכורות' }, rows)
      }
    );
  }

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

  /** Renders the staff template devName (default subject/body below the "שלום," wrapper) and sends it. */
  static void sendTemplate(String devName, String defaultSubject, String defaultBody, Map<String, String> values) {
    EmailTemplates.Rendered r = EmailTemplates.render(devName, defaultSubject, wrap(defaultBody), values, null);
    send(r.subject, r.html);
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
