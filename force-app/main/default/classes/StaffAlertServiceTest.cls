@IsTest
private class StaffAlertServiceTest {
  static void staffEmails() {
    TestDataFactory.chargeEngine(TestDataFactory.WED_0800);
  }

  @IsTest
  static void recipientsParseCommasAndSemicolons() {
    TestDataFactory.settings().Failure_Notify_Emails__c = ' a@example.com;b@example.com, ,c@example.com ';
    Assert.areEqual(new List<String>{ 'a@example.com', 'b@example.com', 'c@example.com' }, StaffAlertService.recipients());
    TestDataFactory.settings().Failure_Notify_Emails__c = null;
    Assert.isTrue(StaffAlertService.recipients().isEmpty());
    Assert.isFalse(StaffAlertService.configErrorOncePerDay() == null);
    Assert.areEqual(0, StaffAlertService.sentCount, 'no recipients → nothing sent');
  }

  @IsTest
  static void configErrorAlertIsSentOncePerDay() {
    staffEmails();
    Assert.isTrue(StaffAlertService.configErrorOncePerDay());
    Assert.isFalse(StaffAlertService.configErrorOncePerDay());
    Assert.areEqual(1, StaffAlertService.sentCount);
  }

  @IsTest
  static void failureStreakBodyFollowsTheTemplate() {
    staffEmails();
    Opportunity p = TestDataFactory.activePledges(1, 'TwiceDaily')[0];
    Charge__c c = TestDataFactory.charge(p, Date.newInstance(2026, 11, 4), 'AM');
    c.Status__c = 'Failed';
    c.Error_Code__c = '4';
    c.Error_Message__c = 'סירוב <b>';
    insert c;
    Opportunity loaded = [
      SELECT
        Id,
        Pledge_Number__c,
        Charge_Amount__c,
        Mincha_Amount__c,
        Frequency__c,
        Consecutive_Failures__c,
        Last4__c,
        CardExpirationMMYY__c,
        Donor_Contact__r.Email,
        Donor_Contact__r.MobilePhone,
        (SELECT Scheduled_Date__c, Slot__c, Attempt_Number__c, Error_Code__c, Error_Message__c FROM Charges__r)
      FROM Opportunity
      WHERE Id = :p.Id
    ];
    String html = StaffAlertService.failureStreakBody(loaded, 'אבי כהן');
    Assert.isTrue(html.contains('החיובים ממשיכים לפי הלוח'));
    Assert.isTrue(html.contains('שחרית ומנחה'));
    Assert.isTrue(html.contains('09/28'));
    Assert.isTrue(html.contains('&lt;b&gt;'), 'values are HTML-escaped');
    StaffAlertService.failureStreak(new Set<Id>{ p.Id });
    Assert.areEqual(1, StaffAlertService.sentCount);
  }

  @IsTest
  static void manyFailureStreaksUseOneSendEmailCall() {
    // Prompt 12: 12 pledges crossing X in one charge batch must not hit the 10-sendEmail-calls limit
    staffEmails();
    Set<Id> ids = new Map<Id, Opportunity>(TestDataFactory.activePledges(12, 'OnceDaily')).keySet();
    Integer before = Limits.getEmailInvocations();
    StaffAlertService.failureStreak(ids);
    Assert.areEqual(12, StaffAlertService.sentCount);
    Assert.areEqual(before + 1, Limits.getEmailInvocations());
  }

  @IsTest
  static void dailyAlertsSendOnlyWhenThereIsSomethingToReport() {
    staffEmails();
    Assert.isFalse(StaffAlertService.receiptFailures());
    Assert.isFalse(StaffAlertService.reconciliationOpen());
    Assert.isFalse(StaffAlertService.pendingVerificationStale());

    Contact c = TestDataFactory.contact('Avi', 'Cohen', 'avi@example.com', '0521111111');
    insert new Monthly_Receipt__c(
      Contact__c = c.Id,
      Period_Month__c = Date.newInstance(2026, 10, 1),
      Receipt_Key__c = c.Id + '-202610',
      Status__c = 'Failed',
      Total_Amount__c = 90,
      Charge_Count__c = 30,
      Error_Code__c = '6311'
    );
    insert new Reconciliation_Issue__c(
      Issue_Type__c = 'Missing_In_Salesforce',
      Issue_Key__c = 'k1',
      Status__c = 'Open',
      Business_Date__c = Date.newInstance(2026, 11, 3),
      Cardcom_Amount__c = 3
    );
    Opportunity stale = TestDataFactory.submittedPledge('lp-stale-000001', 'a@example.com', '0521234567');
    insert stale;
    Test.setCreatedDate(stale.Id, Datetime.now().addDays(-2));

    Assert.isTrue(StaffAlertService.receiptFailures());
    Assert.isTrue(StaffAlertService.reconciliationOpen());
    Assert.isTrue(StaffAlertService.pendingVerificationStale());
    Assert.isFalse(StaffAlertService.receiptFailures(), 'once a day');
    Assert.areEqual(3, StaffAlertService.sentCount);
  }

  @IsTest
  static void dailySchedulableAndScheduleChanged() {
    staffEmails();
    StaffAlertService.scheduleChanged(ChargeSettings.defaults());
    StaffAlertService.scheduleChanged(ChargeSettings.defaults());
    Assert.areEqual(1, StaffAlertService.sentCount);
    Test.startTest();
    String id = System.schedule('Test daily alerts', '0 0 9 ? * SUN-FRI', new StaffAlertService.Daily());
    Test.stopTest();
    Assert.isNotNull(id);
  }
}
