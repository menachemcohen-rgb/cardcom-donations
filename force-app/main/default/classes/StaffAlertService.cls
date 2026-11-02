/**
 * Staff alerts (Part C E11, B6.9.4). Prompt 5: configErrorOncePerDay (minimal). Prompt 6 implements every alert, the HTML templates
 * and the Daily schedulable. Each alert is sent at most once per day, tracked in Alert_State__c (E11, spec-consistency N30).
 */
public without sharing class StaffAlertService {
  @TestVisible
  static Integer sentCount = 0;

  /** "תקלת הגדרות Cardcom" (B5.8 HTTP 401/400, B6.9.4): at most once per day. @return true if sent now. */
  public static Boolean configErrorOncePerDay() {
    Alert_State__c st = Alert_State__c.getOrgDefaults();
    Date today = Date.today();
    if (st != null && st.Config_Error_Sent_On__c == today)
      return false;
    send(
      'תקלת הגדרות Cardcom',
      '<div dir="rtl" style="font-family:Arial,sans-serif"><p>שלום,</p>' +
        '<p>חיובי התרומות נכשלו בגלל תקלת הגדרות מול Cardcom (למשל שם משתמש או סיסמת API שגויים, או טרמינל לא תקין).</p>' +
        '<p>לא נוצרו ניסיונות חוזרים והכישלונות לא נספרים ברצף. יש לתקן את ההגדרות ולהריץ מחדש את החיובים של היום.</p></div>'
    );
    if (st == null || st.Id == null)
      st = new Alert_State__c(SetupOwnerId = UserInfo.getOrganizationId());
    st.Config_Error_Sent_On__c = today;
    upsert st;
    return true;
  }

  public static void scheduleChanged(Charge_Settings__c s) {
    // TODO Prompt 6: email "זמני חיוב עודכנו" with the new times (B6.9.4).
  }

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

  static void send(String subject, String html) {
    List<String> to = recipients();
    if (to.isEmpty()) {
      System.debug(LoggingLevel.WARN, 'Staff alert not sent, no Failure_Notify_Emails__c: ' + subject);
      return;
    }
    Messaging.SingleEmailMessage m = new Messaging.SingleEmailMessage();
    m.setToAddresses(to);
    String owea = CardcomService.settings().Org_Wide_Email_Address__c;
    if (String.isNotBlank(owea)) {
      List<OrgWideEmailAddress> o = [SELECT Id FROM OrgWideEmailAddress WHERE Address = :owea LIMIT 1];
      if (!o.isEmpty())
        m.setOrgWideEmailAddressId(o[0].Id);
    }
    m.setSubject(subject);
    m.setHtmlBody(html);
    sentCount++;
    try {
      Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ m }, false);
    } catch (Exception e) {
      // An alert must never roll back charge processing (e.g. Email Deliverability set to "System email only").
      System.debug(LoggingLevel.ERROR, 'Staff alert email failed: ' + e.getMessage());
    }
  }
}
