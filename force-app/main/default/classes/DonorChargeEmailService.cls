/**
 * Thank-you email after successful charges (B6.9.2, B6.9.3, B6.9.5; D14, D20). Triggered by Charge_Success__e.
 * - Only Success charges with no Donor_Email_Status__c (never sent twice).
 * - Charges of the same pledge in one call are grouped into one email (Friday ×2 → one email).
 * - Donor data comes from the pledge Opportunity: Donor_Contact__r (fallback: the form fields), Last4__c, Link_Version__c.
 * - Daily single-email budget guard: fewer than 200 left → Failed and one staff alert a day.
 */
public without sharing class DonorChargeEmailService {
  @TestVisible
  static final String TEMPLATE = 'Donor_Charge_Thanks';
  @TestVisible
  static final Integer MIN_DAILY_EMAILS_LEFT = 200;
  @TestVisible
  static Integer remainingOverride; // tests: OrgLimits can't be set
  @TestVisible
  static Integer messagesSent = 0;
  @TestVisible
  static Boolean simulateSendForTests = false; // tests: count a send as successful without Messaging (deliverability may be off)
  static final Integer PER_SEND_CALL = 100;

  public static void send(List<Id> chargeIds) {
    if (chargeIds == null || chargeIds.isEmpty())
      return;
    Id rt = MicroPledges.recordTypeId();
    List<Charge__c> charges = [
      SELECT
        Id,
        Pledge__c,
        Amount__c,
        Scheduled_Date__c,
        Slot__c,
        Run_Date__c,
        Pledge__r.Donor_Contact__r.FirstName,
        Pledge__r.Donor_Contact__r.Email,
        Pledge__r.Donor_First_Name__c,
        Pledge__r.Donor_Email__c,
        Pledge__r.Last4__c,
        Pledge__r.Link_Version__c
      FROM Charge__c
      WHERE Id IN :chargeIds AND Status__c = 'Success' AND Donor_Email_Status__c = NULL AND Pledge__r.RecordTypeId = :rt
      ORDER BY Pledge__c, Scheduled_Date__c, Slot__c
    ];
    if (charges.isEmpty())
      return;
    Datetime now = Datetime.now();

    Map<Id, List<Charge__c>> byPledge = new Map<Id, List<Charge__c>>();
    for (Charge__c c : charges) {
      if (!byPledge.containsKey(c.Pledge__c))
        byPledge.put(c.Pledge__c, new List<Charge__c>());
      byPledge.get(c.Pledge__c).add(c);
    }

    Cardcom_Setting__mdt s = CardcomService.settings();
    if (s.Send_Donor_Charge_Email__c != true) {
      mark(charges, 'Disabled', null);
      return;
    }

    Integer left = remaining();
    if (left != null && left - byPledge.size() < MIN_DAILY_EMAILS_LEFT) {
      mark(charges, 'Failed', null); // B6.9.5: DAILY_LIMIT
      StaffAlertService.emailLimit(left);
      return;
    }

    EmailTemplate tpl = template();
    Id owea = EmailUtil.oweaId(s.Org_Wide_Email_Address__c);
    List<Charge__c> noEmail = new List<Charge__c>();
    List<Charge__c> failed = new List<Charge__c>();
    List<Messaging.SingleEmailMessage> msgs = new List<Messaging.SingleEmailMessage>();
    List<List<Charge__c>> msgCharges = new List<List<Charge__c>>();
    for (List<Charge__c> grp : byPledge.values()) {
      Opportunity p = grp[0].Pledge__r;
      String email = p.Donor_Contact__r != null && String.isNotBlank(p.Donor_Contact__r.Email)
        ? p.Donor_Contact__r.Email
        : p.Donor_Email__c;
      if (String.isBlank(email)) {
        noEmail.addAll(grp);
        continue;
      }
      Messaging.SingleEmailMessage m;
      try {
        m = build(tpl, owea, email, grp, s);
      } catch (Exception e) {
        System.debug(LoggingLevel.ERROR, 'Donor email not built for ' + grp[0].Pledge__c + ': ' + e.getMessage()); // N70: e.g. no link secret
        failed.addAll(grp);
        continue;
      }
      msgs.add(m);
      msgCharges.add(grp);
    }

    List<Charge__c> sent = new List<Charge__c>();
    for (Integer i = 0; i < msgs.size(); i += PER_SEND_CALL) {
      List<Messaging.SingleEmailMessage> chunk = new List<Messaging.SingleEmailMessage>();
      for (Integer j = i; j < Math.min(i + PER_SEND_CALL, msgs.size()); j++)
        chunk.add(msgs[j]);
      List<Messaging.SendEmailResult> rs;
      if (Limits.getEmailInvocations() >= Limits.getLimitEmailInvocations()) {
        // sendEmail over the per-transaction limit is an uncatchable LimitException
        for (Integer j = 0; j < chunk.size(); j++)
          failed.addAll(msgCharges[i + j]);
        continue;
      }
      try {
        rs = (Test.isRunningTest() && simulateSendForTests) ? null : Messaging.sendEmail(chunk, false);
      } catch (Exception e) {
        System.debug(LoggingLevel.ERROR, 'Donor email send failed: ' + e.getMessage());
        rs = null;
      }
      for (Integer j = 0; j < chunk.size(); j++) {
        List<Charge__c> grp = msgCharges[i + j];
        if ((rs == null && Test.isRunningTest() && simulateSendForTests) || (rs != null && rs[j].isSuccess())) {
          sent.addAll(grp);
          messagesSent++;
        } else
          failed.addAll(grp);
      }
    }
    mark(sent, 'Sent', now);
    mark(failed, 'Failed', null);
    mark(noEmail, 'No_Email', null);
  }

  /** No automatic re-send (client spec): every charge gets a final status once. */
  static void mark(List<Charge__c> cs, String status, Datetime sentAt) {
    if (cs.isEmpty())
      return;
    List<Charge__c> upd = new List<Charge__c>();
    for (Charge__c c : cs)
      upd.add(new Charge__c(Id = c.Id, Donor_Email_Status__c = status, Donor_Email_Sent_At__c = sentAt));
    Database.update(upd, false);
  }

  static Integer remaining() {
    if (remainingOverride != null)
      return remainingOverride;
    try {
      System.OrgLimit l = OrgLimits.getMap().get('SingleEmail');
      return l == null ? null : l.getLimit() - l.getValue();
    } catch (Exception e) {
      return null;
    }
  }

  static EmailTemplate template() {
    List<EmailTemplate> t = [SELECT Subject, HtmlValue FROM EmailTemplate WHERE DeveloperName = :TEMPLATE LIMIT 1];
    return t.isEmpty() ? null : t[0];
  }

  @TestVisible
  static Messaging.SingleEmailMessage build(EmailTemplate tpl, Id owea, String email, List<Charge__c> grp, Cardcom_Setting__mdt s) {
    Opportunity p = grp[0].Pledge__r;
    Id pledgeId = grp[0].Pledge__c;
    Decimal total = 0;
    for (Charge__c c : grp)
      total += c.Amount__c;
    String base = s.Donor_Portal_Base_Url__c == null ? '' : s.Donor_Portal_Base_Url__c;
    String sep = base.contains('?') ? '&' : '?';
    String cardLink = base + sep + 'a=card&t=' + EncodingUtil.urlEncode(DonorLinkToken.issue(pledgeId, 'card', p.Link_Version__c), 'UTF-8');
    String amountLink =
      base +
      sep +
      'a=amount&t=' +
      EncodingUtil.urlEncode(DonorLinkToken.issue(pledgeId, 'amount', p.Link_Version__c), 'UTF-8');
    String firstName = p.Donor_Contact__r != null && String.isNotBlank(p.Donor_Contact__r.FirstName)
      ? p.Donor_Contact__r.FirstName
      : p.Donor_First_Name__c;

    Map<String, String> v = new Map<String, String>{
      'FirstName' => EmailUtil.esc(firstName),
      'ChargeLines' => EmailUtil.esc(chargeLines(grp, total)),
      'CardPhrase' => String.isBlank(p.Last4__c) ? 'מהכרטיס השמור' : 'מהכרטיס המסתיים ב-' + EmailUtil.esc(p.Last4__c),
      'Last4' => EmailUtil.esc(p.Last4__c),
      'OrgName' => EmailUtil.esc(System.Label.Donation_Org_Name),
      'ImpactSentence' => EmailUtil.esc(System.Label.Donation_Impact_Sentence),
      'CardLink' => EmailUtil.esc(cardLink),
      'AmountLink' => EmailUtil.esc(amountLink),
      'ContactPhone' => EmailUtil.esc(System.Label.Donation_Contact_Phone),
      'ContactEmail' => EmailUtil.esc(System.Label.Donation_Contact_Email),
      'SignerName' => EmailUtil.esc(System.Label.Donation_Signer_Name),
      'Amount' => money(total)
    };
    String subject = tpl != null && String.isNotBlank(tpl.Subject) ? tpl.Subject : 'תודה על תרומתך ל{{OrgName}} – {{Amount}} ₪';
    String html = tpl != null && String.isNotBlank(tpl.HtmlValue) ? tpl.HtmlValue : FALLBACK_HTML;
    Map<String, String> plain = v.clone();
    plain.put('OrgName', System.Label.Donation_Org_Name); // subject is plain text
    Messaging.SingleEmailMessage m = new Messaging.SingleEmailMessage();
    if (owea != null)
      m.setOrgWideEmailAddressId(owea);
    m.setToAddresses(new List<String>{ email });
    m.setSubject(fill(subject, plain));
    m.setHtmlBody(fill(html, v));
    m.setSaveAsActivity(false);
    m.setCharset('UTF-8');
    return m;
  }

  /** "היום, 06/11/2026, נתרמו 3.00 ₪" or "היום נתרמו 6.00 ₪ (עבור 06/11 ו-07/11)" (B6.9.3). */
  @TestVisible
  static String chargeLines(List<Charge__c> grp, Decimal total) {
    if (grp.size() == 1) {
      return 'היום, ' +
        Datetime.newInstance(grp[0].Scheduled_Date__c, Time.newInstance(12, 0, 0, 0)).format('dd/MM/yyyy') +
        ', נתרמו ' +
        money(total) +
        ' ₪';
    }
    List<String> days = new List<String>();
    for (Charge__c c : grp) {
      String d = Datetime.newInstance(c.Scheduled_Date__c, Time.newInstance(12, 0, 0, 0)).format('dd/MM');
      if (!days.contains(d))
        days.add(d);
    }
    String joined = days[days.size() - 1];
    if (days.size() > 1) {
      List<String> head = new List<String>();
      for (Integer i = 0; i < days.size() - 1; i++)
        head.add(days[i]);
      joined = String.join(head, ', ') + ' ו-' + joined;
    }
    return 'היום נתרמו ' + money(total) + ' ₪ (עבור ' + joined + ')';
  }

  static String money(Decimal d) {
    return d.setScale(2).toPlainString();
  }

  static String fill(String text, Map<String, String> v) {
    String out = text;
    for (String k : v.keySet())
      out = out.replace('{{' + k + '}}', v.get(k) == null ? '' : v.get(k));
    return out;
  }

  static final String FALLBACK_HTML =
    '<div dir="rtl" style="font-family:Arial,sans-serif;font-size:15px;line-height:1.6">' +
    '<p>{{FirstName}} שלום,</p><p>תודה! {{ChargeLines}} {{CardPhrase}} ל{{OrgName}}.</p><p>{{ImpactSentence}}</p>' +
    '<p><a href="{{CardLink}}">החלפת כרטיס אשראי</a> · <a href="{{AmountLink}}">שינוי סכום ההוראה</a></p>' +
    '<p>לביטול ההוראה או לשאלות: {{ContactPhone}} · {{ContactEmail}}</p><p>בתודה,<br>{{SignerName}}, {{OrgName}}</p></div>';
}
