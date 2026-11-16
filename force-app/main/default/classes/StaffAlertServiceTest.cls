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

  // ---- high amount per charge (> Charge_Settings__c.High_Amount_Alert__c, default 25) ----
  // The threshold is lowered to 10 here: VR_Amount_Range reads the org's own Cardcom_Setting record (its Max_Amount__c may be 25).
  static void highAmountAlerts() {
    staffEmails();
    ChargeSettings.overrideValue.High_Amount_Alert__c = 10;
  }

  @IsTest
  static void newPledgeAboveTheThresholdAlertsWhenItBecomesActive() {
    highAmountAlerts();
    Contact c = TestDataFactory.contact('Dan', 'Levi', 'dan@example.com', '0522222222');
    Opportunity low = TestDataFactory.withToken(TestDataFactory.submittedPledge('lp-high-0000000001', c.Email, c.MobilePhone));
    Opportunity high = TestDataFactory.withToken(TestDataFactory.submittedPledge('lp-high-0000000002', c.Email, c.MobilePhone));
    low.Charge_Amount__c = 10; // exactly the threshold: no alert
    high.Frequency__c = 'TwiceDaily';
    high.Charge_Amount__c = 5;
    high.Mincha_Amount__c = 12;
    insert new List<Opportunity>{ low, high };
    Assert.areEqual(0, StaffAlertService.sentCount, 'pending pledges are not alerted');
    for (Opportunity o : new List<Opportunity>{ low, high }) {
      o.StageName = MicroPledges.STAGE_ACTIVE;
      o.Donor_Contact__c = c.Id;
      o.Activated_At__c = Datetime.now();
    }
    update new List<Opportunity>{ low, high };
    Assert.areEqual(1, StaffAlertService.sentCount, 'only the pledge above the threshold per charge');
    Assert.areEqual('מנחה 12.00 ₪', StaffAlertService.highSlots(high));
    Assert.areEqual('', StaffAlertService.highSlots(low));
  }

  @IsTest
  static void amountChangesOnAnActivePledgeAlertOnlyWhenTheHighAmountChanges() {
    highAmountAlerts();
    Opportunity p = TestDataFactory.activePledges(1, 'TwiceDaily')[0]; // 3 ₪
    Assert.areEqual(0, StaffAlertService.sentCount);
    update new Opportunity(Id = p.Id, Charge_Amount__c = 15);
    Assert.areEqual(1, StaffAlertService.sentCount, 'Shacharit raised above the threshold');
    update new Opportunity(Id = p.Id, Charge_Amount__c = 15, Last4__c = '1234');
    Assert.areEqual(1, StaffAlertService.sentCount, 'same amounts: no second email');
    update new Opportunity(Id = p.Id, Mincha_Amount__c = 11);
    Assert.areEqual(2, StaffAlertService.sentCount, 'Mincha also above the threshold');
    update new Opportunity(Id = p.Id, Charge_Amount__c = 8, Mincha_Amount__c = 8);
    Assert.areEqual(2, StaffAlertService.sentCount, 'lowered: no email');
  }

  @IsTest
  static void resumeOtherSlotsAndThreshold() {
    highAmountAlerts();
    Opportunity p = TestDataFactory.activePledges(1, 'OnceDaily')[0];
    update new Opportunity(Id = p.Id, Mincha_Amount__c = 20);
    Assert.areEqual(0, StaffAlertService.sentCount, 'Shacharit-only pledge: the Mincha amount is never charged');
    update new Opportunity(Id = p.Id, Charge_Amount__c = 20);
    Assert.areEqual(1, StaffAlertService.sentCount);
    Opportunity stopped = new Opportunity(StageName = MicroPledges.STAGE_STOPPED, Frequency__c = 'OnceDaily', Charge_Amount__c = 20);
    Opportunity resumed = new Opportunity(StageName = MicroPledges.STAGE_ACTIVE, Frequency__c = 'OnceDaily', Charge_Amount__c = 20);
    Assert.isFalse(StaffAlertService.isNewHighAmount(resumed, stopped), 'a resume with the same amounts is not alerted again');
    Assert.isFalse(StaffAlertService.isNewHighAmount(stopped, resumed), 'a stopped pledge is not alerted');
    ChargeSettings.overrideValue.High_Amount_Alert__c = null;
    Assert.areEqual(25, StaffAlertService.highAmountThreshold().intValue(), 'blank threshold = 25');
    Assert.areEqual(25, ChargeSettings.defaults().High_Amount_Alert__c.intValue(), 'default 25');
  }
}
