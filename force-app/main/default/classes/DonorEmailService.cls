/**
 * Donor emails (D37, client 10.11.2026). No email after every charge; instead:
 * - welcome:  when a pledge becomes Active — what was set up, the permanent links (card / amount) and the phone to stop;
 * - monthly:  with the receipts run (2nd of the month) — how much was donated last month; the section 46 receipt comes
 *             separately from Cardcom;
 * - failure:  at once when a charge fails for good (Payment_Issue_Since__c set by PledgeRollupService), then every Sunday at
 *             10:00 (DonorFailureReminderJob) until a charge succeeds, the card is replaced, or staff tick
 *             Failure_Reminders_Stopped__c.
 * Every email carries the two permanent links and the phone for stopping the pledge (donors can't stop it on the web).
 * Recipient: the donor Contact's email, else the email typed in the form. Sender: Cardcom_Setting__mdt.Org_Wide_Email_Address__c.
 * One Messaging.sendEmail call per batch of messages; a send never throws back into the charge or activation transaction.
 */
public without sharing class DonorEmailService {
  @TestVisible
  static Integer sentCount = 0;
  @TestVisible
  static List<Messaging.SingleEmailMessage> lastSent = new List<Messaging.SingleEmailMessage>();
  static final Integer PER_SEND_CALL = 100;

  static final String FIELDS =
    'Id, StageName, Pledge_Number__c, Frequency__c, Charge_Amount__c, Mincha_Amount__c, Last4__c, Link_Version__c, ' +
    'Donor_First_Name__c, Donor_Email__c, Donor_Contact__r.FirstName, Donor_Contact__r.Email, Welcome_Email_Sent_At__c, ' +
    'Last_Summary_Month__c, Payment_Issue_Since__c, Last_Failure_Email_At__c, Failure_Reminders_Stopped__c';

  // ------------------------------------------------------------------ welcome
  /** Welcome email for pledges that are Active and haven't had it yet. */
  public static void sendWelcome(Set<Id> pledgeIds) {
    List<Opportunity> ps = load(pledgeIds);
    List<Opportunity> todo = new List<Opportunity>();
    for (Opportunity p : ps)
      if (p.StageName == MicroPledges.STAGE_ACTIVE && p.Welcome_Email_Sent_At__c == null)
        todo.add(p);
    if (todo.isEmpty())
      return;
    List<Messaging.SingleEmailMessage> msgs = new List<Messaging.SingleEmailMessage>();
    List<Opportunity> withMsg = new List<Opportunity>();
    for (Opportunity p : todo) {
      Messaging.SingleEmailMessage m = message(p, welcomeSubject(), welcomeBody(p));
      if (m != null) {
        msgs.add(m);
        withMsg.add(p);
      }
    }
    Set<Integer> ok = send(msgs);
    List<Opportunity> upd = new List<Opportunity>();
    for (Integer i = 0; i < withMsg.size(); i++)
      if (ok.contains(i))
        upd.add(new Opportunity(Id = withMsg[i].Id, Welcome_Email_Sent_At__c = Datetime.now()));
    Database.update(upd, false);
  }

  static String welcomeSubject() {
    return 'הוראת התרומה היומית שלך ל' + org() + ' נקלטה';
  }

  static String welcomeBody(Opportunity p) {
    return '<p>תודה! הוראת התרומה היומית שלך נקלטה ותחל לפעול במועד החיוב הקרוב.</p>' +
      '<p><b>פרטי ההוראה:</b> ' +
      EmailUtil.esc(MicroPledges.frequencyHe(p.Frequency__c)) +
      ' · ' +
      EmailUtil.esc(MicroPledges.amountsHe(p)) +
      cardPhrase(p) +
      '</p>' +
      '<p>בשבת ובחג אין חיובים: הם מחויבים מראש בערב שבת או ערב חג, יחד עם תפילת המנחה.</p>' +
      '<p>פעם בחודש נשלח אליך סיכום של התרומות. קבלה לפי סעיף 46 תישלח אליך במייל נפרד.</p>';
  }

  // ------------------------------------------------------------------ monthly summary
  /** One summary per pledge for the month starting `period`, from its Success charges sent in that month. @return emails sent. */
  public static Integer sendMonthlySummaries(List<Opportunity> pledges, Date period) {
    if (pledges.isEmpty())
      return 0;
    Date toD = period.addMonths(1).addDays(-1);
    Map<Id, Decimal> total = new Map<Id, Decimal>();
    Map<Id, Integer> count = new Map<Id, Integer>();
    Set<Id> ids = new Map<Id, Opportunity>(pledges).keySet();
    for (AggregateResult ar : [
      SELECT Pledge__c pid, SUM(Amount__c) total, COUNT(Id) cnt
      FROM Charge__c
      WHERE Pledge__c IN :ids AND Status__c = 'Success' AND Run_Date__c >= :period AND Run_Date__c <= :toD
      GROUP BY Pledge__c
    ]) {
      total.put((Id) ar.get('pid'), (Decimal) ar.get('total'));
      count.put((Id) ar.get('pid'), (Integer) ar.get('cnt'));
    }
    String month = MonthlyReceiptService.monthNameHe(period.month()) + ' ' + period.year();
    List<Messaging.SingleEmailMessage> msgs = new List<Messaging.SingleEmailMessage>();
    List<Opportunity> withMsg = new List<Opportunity>();
    for (Opportunity p : load(ids)) {
      if (!total.containsKey(p.Id) || (p.Last_Summary_Month__c != null && p.Last_Summary_Month__c >= period))
        continue;
      String body =
        '<p>בחודש ' +
        EmailUtil.esc(month) +
        ' נתרמו בהוראה שלך <b>' +
        money(total.get(p.Id)) +
        ' ₪</b> ב-' +
        count.get(p.Id) +
        ' חיובים. תודה על השותפות!</p>' +
        '<p><b>ההוראה כרגע:</b> ' +
        EmailUtil.esc(MicroPledges.frequencyHe(p.Frequency__c)) +
        ' · ' +
        EmailUtil.esc(MicroPledges.amountsHe(p)) +
        '</p>' +
        '<p>קבלה לפי סעיף 46 על תרומות החודש תישלח אליך במייל נפרד.</p>';
      Messaging.SingleEmailMessage m = message(p, 'סיכום התרומות שלך ל' + org() + ' – ' + month, body);
      if (m != null) {
        msgs.add(m);
        withMsg.add(p);
      }
    }
    Set<Integer> ok = send(msgs);
    List<Opportunity> upd = new List<Opportunity>();
    for (Integer i = 0; i < withMsg.size(); i++)
      if (ok.contains(i))
        upd.add(new Opportunity(Id = withMsg[i].Id, Last_Summary_Month__c = period));
    Database.update(upd, false);
    return upd.size();
  }

  // ------------------------------------------------------------------ failed charge
  /**
   * "We couldn't charge your card" — at once (reminder = false) or as the weekly reminder (reminder = true). Only Active pledges
   * with an open payment issue and reminders not stopped. Sets Last_Failure_Email_At__c.
   */
  public static void sendPaymentFailed(Set<Id> pledgeIds, Boolean reminder) {
    List<Messaging.SingleEmailMessage> msgs = new List<Messaging.SingleEmailMessage>();
    List<Opportunity> withMsg = new List<Opportunity>();
    for (Opportunity p : load(pledgeIds)) {
      if (p.StageName != MicroPledges.STAGE_ACTIVE || p.Payment_Issue_Since__c == null || p.Failure_Reminders_Stopped__c == true)
        continue;
      String body =
        '<p>' +
        (reminder ? 'תזכורת: ' : '') +
        'לא הצלחנו לחייב את ' +
        (String.isBlank(p.Last4__c) ? 'הכרטיס השמור' : 'הכרטיס המסתיים ב-' + EmailUtil.esc(p.Last4__c)) +
        ' עבור הוראת התרומה היומית שלך.</p>' +
        '<p>כדי שהתרומה תמשיך, אפשר לעדכן את פרטי הכרטיס בכפתור "החלפת כרטיס אשראי" כאן למטה. ' +
        'ננסה לחייב שוב במועדי החיוב הקבועים.</p>';
      String subject = (reminder ? 'תזכורת: ' : '') + 'לא הצלחנו לחייב את הכרטיס – הוראת התרומה ל' + org();
      Messaging.SingleEmailMessage m = message(p, subject, body);
      if (m != null) {
        msgs.add(m);
        withMsg.add(p);
      }
    }
    Set<Integer> ok = send(msgs);
    List<Opportunity> upd = new List<Opportunity>();
    for (Integer i = 0; i < withMsg.size(); i++)
      if (ok.contains(i))
        upd.add(new Opportunity(Id = withMsg[i].Id, Last_Failure_Email_At__c = Datetime.now()));
    Database.update(upd, false);
  }

  // ------------------------------------------------------------------ shared
  static List<Opportunity> load(Set<Id> ids) {
    if (ids == null || ids.isEmpty())
      return new List<Opportunity>();
    String pledgeType = MicroPledges.TYPE;
    return Database.query('SELECT ' + FIELDS + ' FROM Opportunity WHERE Id IN :ids AND Type = :pledgeType');
  }

  static String org() {
    return System.Label.Donation_Org_Name;
  }

  // Signer line; skips the org suffix when the signer label already names the org.
  @TestVisible
  static String signature() {
    String signer = System.Label.Donation_Signer_Name;
    String o = org();
    if (String.isBlank(signer))
      return o;
    if (String.isBlank(o) || signer.contains(o))
      return signer;
    return signer + ', ' + o;
  }

  static String cardPhrase(Opportunity p) {
    return String.isBlank(p.Last4__c) ? '' : ' · כרטיס המסתיים ב-' + EmailUtil.esc(p.Last4__c);
  }

  static String money(Decimal d) {
    return d == null ? '0.00' : d.setScale(2).toPlainString();
  }

  /** The email: greeting, body, the two permanent links, phone to stop, signature. Null when there is no address or no link secret. */
  @TestVisible
  static Messaging.SingleEmailMessage message(Opportunity p, String subject, String body) {
    String email = p.Donor_Contact__r != null && String.isNotBlank(p.Donor_Contact__r.Email) ? p.Donor_Contact__r.Email : p.Donor_Email__c;
    if (String.isBlank(email))
      return null;
    Cardcom_Setting__mdt s = CardcomService.settings();
    String cardLink, amountLink;
    try {
      String base = s.Donor_Portal_Base_Url__c == null ? '' : s.Donor_Portal_Base_Url__c;
      String sep = base.contains('?') ? '&' : '?';
      Decimal v = p.Link_Version__c == null ? 1 : p.Link_Version__c;
      cardLink = base + sep + 'a=card&t=' + EncodingUtil.urlEncode(DonorLinkToken.issue(p.Id, 'card', v), 'UTF-8');
      amountLink = base + sep + 'a=amount&t=' + EncodingUtil.urlEncode(DonorLinkToken.issue(p.Id, 'amount', v), 'UTF-8');
    } catch (Exception e) {
      System.debug(LoggingLevel.ERROR, 'Donor email not built for ' + p.Id + ': ' + e.getMessage()); // e.g. no link secret
      return null;
    }
    String firstName = p.Donor_Contact__r != null && String.isNotBlank(p.Donor_Contact__r.FirstName)
      ? p.Donor_Contact__r.FirstName
      : p.Donor_First_Name__c;
    String html =
      '<div dir="rtl" style="font-family:Arial,sans-serif;font-size:15px;line-height:1.6;color:#222;max-width:600px">' +
      '<p>' +
      EmailUtil.esc(firstName) +
      ' שלום,</p>' +
      body +
      '<p><strong>רוצה לעדכן את ההוראה?</strong></p>' +
      '<p><a href="' +
      EmailUtil.esc(cardLink) +
      '" style="background:#1d4ed8;color:#fff;padding:10px 18px;border-radius:6px;text-decoration:none">החלפת כרטיס אשראי</a>' +
      ' &nbsp; <a href="' +
      EmailUtil.esc(amountLink) +
      '" style="background:#0f766e;color:#fff;padding:10px 18px;border-radius:6px;text-decoration:none">שינוי סכום ההוראה</a></p>' +
      '<p style="font-size:13px;color:#555">הקישורים אישיים וקבועים, ואין צורך בסיסמה – שמרו את המייל ואל תעבירו אותו לאחרים.</p>' +
      '<p>להפסקת ההוראה או לשאלות: ' +
      EmailUtil.esc(System.Label.Donation_Contact_Phone) +
      (String.isBlank(System.Label.Donation_Contact_Email) ? '' : ' · ' + EmailUtil.esc(System.Label.Donation_Contact_Email)) +
      '</p>' +
      '<p>בתודה,<br>' +
      EmailUtil.esc(signature()) +
      '</p></div>';
    Messaging.SingleEmailMessage m = new Messaging.SingleEmailMessage();
    Id owea = EmailUtil.oweaId(s.Org_Wide_Email_Address__c);
    if (owea != null)
      m.setOrgWideEmailAddressId(owea);
    m.setToAddresses(new List<String>{ email });
    m.setSubject(subject);
    m.setHtmlBody(html);
    m.setSaveAsActivity(false);
    m.setCharset('UTF-8');
    return m;
  }

  /** @return indexes of the messages that went out. Never throws. */
  @TestVisible
  static Set<Integer> send(List<Messaging.SingleEmailMessage> msgs) {
    Set<Integer> ok = new Set<Integer>();
    for (Integer i = 0; i < msgs.size(); i += PER_SEND_CALL) {
      List<Messaging.SingleEmailMessage> chunk = new List<Messaging.SingleEmailMessage>();
      for (Integer j = i; j < Math.min(i + PER_SEND_CALL, msgs.size()); j++)
        chunk.add(msgs[j]);
      if (Limits.getEmailInvocations() >= Limits.getLimitEmailInvocations())
        break; // an over-limit sendEmail is an uncatchable LimitException
      if (Test.isRunningTest()) {
        for (Integer j = 0; j < chunk.size(); j++)
          ok.add(i + j);
        lastSent.addAll(chunk);
        sentCount += chunk.size();
        continue;
      }
      try {
        List<Messaging.SendEmailResult> rs = Messaging.sendEmail(chunk, false);
        for (Integer j = 0; j < rs.size(); j++)
          if (rs[j].isSuccess()) {
            ok.add(i + j);
            sentCount++;
          }
      } catch (Exception e) {
        System.debug(LoggingLevel.ERROR, 'Donor email send failed: ' + e.getMessage());
      }
    }
    return ok;
  }
}
