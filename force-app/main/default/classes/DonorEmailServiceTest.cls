@IsTest
private class DonorEmailServiceTest {
  static Opportunity setup(String frequency) {
    TestDataFactory.chargeEngine(TestDataFactory.WED_0800);
    DonorLinkToken.secretOverride = 'donor-email-secret-0123456789abcdef';
    return TestDataFactory.activePledges(1, frequency)[0];
  }

  static Charge__c charge(Opportunity p, Date d, String slot, String status, Boolean finalFailure) {
    Charge__c c = TestDataFactory.charge(p, d, slot);
    c.Status__c = status;
    c.Is_Final_Failure__c = finalFailure;
    c.Executed_At__c = Datetime.newInstance(d, Time.newInstance(8, 0, 0, 0));
    if (status == 'Success') {
      c.Cardcom_Tranzaction_Id__c = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
      c.Cardcom_Deal_Number__c = c.Cardcom_Tranzaction_Id__c;
    }
    return c;
  }

  static String lastBody() {
    return DonorEmailService.lastSent[DonorEmailService.lastSent.size() - 1].getHtmlBody();
  }

  @IsTest
  static void welcomeEmailIsSentOnceWithThePermanentLinks() {
    Opportunity p = setup('TwiceDaily');
    DonorEmailService.sendWelcome(new Set<Id>{ p.Id });
    Assert.areEqual(1, DonorEmailService.sentCount);
    Messaging.SingleEmailMessage m = DonorEmailService.lastSent[0];
    Assert.isTrue(m.getSubject().contains('נקלטה'), m.getSubject());
    String body = m.getHtmlBody();
    Assert.isTrue(body.contains('שחרית ומנחה'), body);
    Assert.isTrue(body.contains('a=card&amp;t=') && body.contains('a=amount&amp;t='), 'both permanent links');
    Assert.isTrue(body.contains('להפסקת ההוראה'), 'phone to stop the pledge');
    Assert.isTrue(body.contains('סעיף 46'), 'receipt comes separately');
    Assert.isNotNull([SELECT Welcome_Email_Sent_At__c FROM Opportunity WHERE Id = :p.Id].Welcome_Email_Sent_At__c);
    DonorEmailService.sendWelcome(new Set<Id>{ p.Id });
    Assert.areEqual(1, DonorEmailService.sentCount, 'never twice');
  }

  @IsTest
  static void noEmailAddressOrNotActiveSendsNothing() {
    Opportunity p = setup('OnceDaily');
    update new Opportunity(Id = p.Id, StageName = 'Pending_Verification');
    DonorEmailService.sendWelcome(new Set<Id>{ p.Id });
    Assert.areEqual(0, DonorEmailService.sentCount);
  }

  @IsTest
  static void monthlySummaryTotalsLastMonthOncePerPledge() {
    Opportunity p = setup('TwiceDaily');
    Date oct = Date.newInstance(2026, 10, 1);
    insert new List<Charge__c>{
      charge(p, Date.newInstance(2026, 10, 5), 'AM', 'Success', false),
      charge(p, Date.newInstance(2026, 10, 5), 'PM', 'Success', false),
      charge(p, Date.newInstance(2026, 11, 2), 'AM', 'Success', false) // next month: not counted
    };
    Test.startTest();
    Assert.isTrue(DonorMonthlySummaryBatch.startIfNeeded(oct));
    Test.stopTest();
    Assert.areEqual(1, DonorEmailService.sentCount);
    String body = lastBody();
    Assert.isTrue(body.contains('6.00'), body);
    Assert.isTrue(body.contains('2 חיובים'), body);
    Assert.isTrue(body.contains('סעיף 46'), body);
    Assert.areEqual(oct, [SELECT Last_Summary_Month__c FROM Opportunity WHERE Id = :p.Id].Last_Summary_Month__c);
    Assert.isFalse(DonorMonthlySummaryBatch.startIfNeeded(oct), 'already sent for October');
  }

  @IsTest
  static void finalFailureEmailsTheDonorAtOnceAndSuccessEndsTheIssue() {
    Opportunity p = setup('OnceDaily');
    insert charge(p, Date.newInstance(2026, 11, 3), 'AM', 'Failed', true);
    Opportunity after = [SELECT Payment_Issue_Since__c, Last_Failure_Email_At__c FROM Opportunity WHERE Id = :p.Id];
    Assert.isNotNull(after.Payment_Issue_Since__c);
    Assert.isNotNull(after.Last_Failure_Email_At__c);
    Assert.areEqual(1, DonorEmailService.sentCount);
    Assert.isTrue(DonorEmailService.lastSent[0].getSubject().contains('לא הצלחנו לחייב'));
    insert charge(p, Date.newInstance(2026, 11, 4), 'AM', 'Failed', true);
    Assert.areEqual(1, DonorEmailService.sentCount, 'one immediate email per issue');
    insert charge(p, Date.newInstance(2026, 11, 5), 'AM', 'Success', false);
    Assert.isNull([SELECT Payment_Issue_Since__c FROM Opportunity WHERE Id = :p.Id].Payment_Issue_Since__c, 'resolved');
  }

  @IsTest
  static void weeklyReminderUntilStaffStopIt() {
    Opportunity p = setup('OnceDaily');
    update new Opportunity(
      Id = p.Id,
      Payment_Issue_Since__c = Datetime.now().addDays(-10),
      Last_Failure_Email_At__c = Datetime.now().addDays(-7)
    );
    Opportunity stopped = TestDataFactory.activePledges(1, 'OnceDaily')[0];
    update new Opportunity(Id = stopped.Id, Payment_Issue_Since__c = Datetime.now().addDays(-10), Failure_Reminders_Stopped__c = true);
    Test.startTest();
    Database.executeBatch(new DonorFailureReminderJob(), 50);
    Test.stopTest();
    Assert.areEqual(1, DonorEmailService.sentCount, 'only the pledge whose reminders were not stopped');
    Assert.isTrue(DonorEmailService.lastSent[0].getSubject().startsWith('תזכורת'));
  }

  @IsTest
  static void recentFirstEmailSkipsThisWeeksReminder() {
    Opportunity p = setup('OnceDaily');
    update new Opportunity(
      Id = p.Id,
      Payment_Issue_Since__c = Datetime.now().addDays(-1),
      Last_Failure_Email_At__c = Datetime.now().addDays(-1)
    );
    Test.startTest();
    Database.executeBatch(new DonorFailureReminderJob(), 50);
    Test.stopTest();
    Assert.areEqual(0, DonorEmailService.sentCount);
  }

  @IsTest
  static void newCardEndsThePaymentIssue() {
    Opportunity p = setup('OnceDaily');
    update new Opportunity(Id = p.Id, Payment_Issue_Since__c = Datetime.now(), Failure_Reminders_Stopped__c = true);
    insert new Card_Change_Request__c(Pledge__c = p.Id, LowProfileId__c = 'lp-card-email-0001', Status__c = 'Pending', Link_Version__c = 1);
    Assert.areEqual('Completed', CardChangeService.complete('lp-card-email-0001', CardcomMock.lpSuccess('lp-card-email-0001', 'CARD-x')));
    Opportunity after = [SELECT Payment_Issue_Since__c, Failure_Reminders_Stopped__c FROM Opportunity WHERE Id = :p.Id];
    Assert.isNull(after.Payment_Issue_Since__c);
    Assert.isFalse(after.Failure_Reminders_Stopped__c);
  }

  @IsTest
  static void scheduleEntryPointStartsTheBatch() {
    setup('OnceDaily');
    Test.startTest();
    String id = System.schedule('Test donor reminders', '0 0 10 ? * SUN', new DonorFailureReminderJob());
    Test.stopTest();
    Assert.isNotNull(id);
  }

  @IsTest
  static void signatureNamesTheOrgOnce() {
    String sig = DonorEmailService.signature();
    Assert.isTrue(sig.contains(System.Label.Donation_Org_Name));
    Assert.areEqual(sig.indexOf(System.Label.Donation_Org_Name), sig.lastIndexOf(System.Label.Donation_Org_Name));
  }

  @IsTest
  static void templateCanUseEveryCommonDonorField() {
    Opportunity p = setup('TwiceDaily');
    Id cid = [SELECT Donor_Contact__c FROM Opportunity WHERE Id = :p.Id].Donor_Contact__c;
    update new Contact(Id = cid, FirstName = 'ישראל', LastName = 'כהן & בניו');
    update new Opportunity(Id = p.Id, Last4__c = '1234', CardExpirationMMYY__c = '0928', Start_Date__c = Date.newInstance(2026, 11, 3));
    List<String> keys = new List<String>{
      'FirstName',
      'LastName',
      'FullName',
      'DonorEmail',
      'DonorPhone',
      'PledgeNumber',
      'ShacharitAmount',
      'MinchaAmount',
      'StartDate',
      'TotalCollected',
      'SuccessfulCharges',
      'LastChargeDate',
      'Last4',
      'CardExpiry',
      'PaymentIssueSince',
      'Today'
    };
    String html = '';
    for (String k : keys)
      html += '[' + k + '={{' + k + '}}]';
    EmailTemplates.byName = new Map<String, EmailTemplate>{
      'Donor_Welcome' => new EmailTemplate(Subject = '{{FullName}} {{PledgeNumber}}', HtmlValue = html)
    };
    DonorEmailService.sendWelcome(new Set<Id>{ p.Id });
    Messaging.SingleEmailMessage m = DonorEmailService.lastSent[0];
    String body = m.getHtmlBody();
    Assert.isFalse(body.contains('{{'), body);
    Assert.isTrue(body.contains('[LastName=כהן &amp; בניו]'), 'escaped in the body: ' + body);
    Assert.isTrue(m.getSubject().startsWith('ישראל כהן & בניו PLG-'), 'plain in the subject: ' + m.getSubject());
    Assert.isTrue(body.contains('[Last4=1234]') && body.contains('[CardExpiry=09/28]'), body);
    Assert.isTrue(body.contains('[StartDate=03/11/2026]'), body);
    Assert.isTrue(body.contains('[ShacharitAmount=') && !body.contains('[ShacharitAmount=]'), body);
    Assert.isTrue(body.contains('[PaymentIssueSince=]'), 'empty when there is no payment issue');
  }
}
