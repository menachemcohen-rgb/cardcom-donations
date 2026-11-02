@IsTest
private class DonorChargeEmailServiceTest {
  static List<Opportunity> ps;

  static void setup() {
    TestDataFactory.chargeEngine(TestDataFactory.FRI_0600);
    DonorLinkToken.secretOverride = 'email-secret-0123456789abcdef';
    DonorChargeEmailService.simulateSendForTests = true;
    ps = TestDataFactory.activePledges(2, 'OnceDaily');
  }

  static Charge__c success(Opportunity p, Date d) {
    Charge__c c = TestDataFactory.charge(p, d, 'AM');
    c.Status__c = 'Success';
    return c;
  }

  static Map<Id, String> statuses() {
    Map<Id, String> m = new Map<Id, String>();
    for (Charge__c c : [SELECT Id, Donor_Email_Status__c FROM Charge__c])
      m.put(c.Id, c.Donor_Email_Status__c);
    return m;
  }

  @IsTest
  static void groupsFridayChargesIntoOneEmailPerPledge() {
    // TC12: Friday + Shabbat → one email
    setup();
    List<Charge__c> cs = new List<Charge__c>{
      success(ps[0], Date.newInstance(2026, 11, 6)),
      success(ps[0], Date.newInstance(2026, 11, 7)),
      success(ps[1], Date.newInstance(2026, 11, 6))
    };
    insert cs;
    DonorChargeEmailService.remainingOverride = 5000;
    DonorChargeEmailService.send(new List<Id>{ cs[0].Id, cs[1].Id, cs[2].Id });
    Assert.areEqual(2, DonorChargeEmailService.messagesSent, 'one email per pledge');
    for (String s : statuses().values())
      Assert.areEqual('Sent', s);
    Assert.isNotNull([SELECT Donor_Email_Sent_At__c FROM Charge__c LIMIT 1].Donor_Email_Sent_At__c);
    DonorChargeEmailService.send(new List<Id>{ cs[0].Id });
    Assert.areEqual(2, DonorChargeEmailService.messagesSent, 'never sent twice');
  }

  @IsTest
  static void emailBodyHasLinesLinksAndNoRawHtmlFromData() {
    setup();
    List<Charge__c> cs = new List<Charge__c>{
      success(ps[0], Date.newInstance(2026, 11, 6)),
      success(ps[0], Date.newInstance(2026, 11, 7))
    };
    insert cs;
    cs = [
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
      ORDER BY Scheduled_Date__c
    ];
    Messaging.SingleEmailMessage m = DonorChargeEmailService.build(null, null, 'avi@example.com', cs, CardcomService.settings());
    String html = m.getHtmlBody();
    Assert.isTrue(html.contains('היום נתרמו 6.00 ₪ (עבור 06/11 ו-07/11)'), html);
    Assert.isTrue(html.contains('מהכרטיס השמור'), 'no Last4 yet (B5.3)');
    Assert.isTrue(html.contains('?a=card&amp;t='), 'card link');
    Assert.isTrue(html.contains('?a=amount&amp;t='), 'amount link');
    Assert.isTrue(m.getSubject().contains('6.00 ₪'));
    Assert.areEqual('היום, 06/11/2026, נתרמו 3.00 ₪', DonorChargeEmailService.chargeLines(new List<Charge__c>{ cs[0] }, 3));
  }

  @IsTest
  static void disabledNoEmailAndDailyLimit() {
    setup();
    Charge__c a = success(ps[0], Date.newInstance(2026, 11, 6));
    insert a;
    CardcomService.settingsOverride.Send_Donor_Charge_Email__c = false;
    DonorChargeEmailService.send(new List<Id>{ a.Id });
    Assert.areEqual('Disabled', statuses().get(a.Id));

    CardcomService.settingsOverride.Send_Donor_Charge_Email__c = true;
    Charge__c b = success(ps[1], Date.newInstance(2026, 11, 6));
    insert b;
    DonorChargeEmailService.remainingOverride = 150; // < 200 left today (B6.9.5)
    DonorChargeEmailService.send(new List<Id>{ b.Id });
    Assert.areEqual('Failed', statuses().get(b.Id));
    Assert.areEqual(Date.today(), Alert_State__c.getOrgDefaults().Email_Limit_Sent_On__c);

    Contact noMail = TestDataFactory.contact('No', 'Mail', null, '0523333333');
    Opportunity p3 = TestDataFactory.withToken(TestDataFactory.submittedPledge('lp-nomail-00001', null, '0523333333'));
    p3.StageName = 'Active';
    p3.Donor_Contact__c = noMail.Id;
    insert p3;
    Charge__c c = success(p3, Date.newInstance(2026, 11, 6));
    insert c;
    DonorChargeEmailService.remainingOverride = 5000;
    DonorChargeEmailService.send(new List<Id>{ c.Id });
    Assert.areEqual('No_Email', statuses().get(c.Id));
  }

  @IsTest
  static void missingLinkSecretMarksFailed() {
    setup();
    DonorLinkToken.secretOverride = '';
    Charge__c a = success(ps[0], Date.newInstance(2026, 11, 6));
    insert a;
    DonorChargeEmailService.remainingOverride = 5000;
    DonorChargeEmailService.send(new List<Id>{ a.Id });
    Assert.areEqual('Failed', statuses().get(a.Id));
  }

  @IsTest
  static void platformEventTriggersTheEmail() {
    setup();
    Charge__c a = success(ps[0], Date.newInstance(2026, 11, 6));
    insert a;
    DonorChargeEmailService.remainingOverride = 5000;
    Test.startTest();
    EventBus.publish(new Charge_Success__e(Charge_Ids__c = a.Id + ','));
    Test.getEventBus().deliver();
    Test.stopTest();
    Assert.areNotEqual(null, statuses().get(a.Id));
  }
}
