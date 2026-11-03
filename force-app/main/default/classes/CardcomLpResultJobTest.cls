@IsTest
private class CardcomLpResultJobTest {
  static final Id PLEDGE_RT = MicroPledges.recordTypeId();

  static void runJob(List<String> lps) {
    Test.startTest();
    System.enqueueJob(new CardcomLpResultJob(lps));
    Test.stopTest();
  }

  static Opportunity byLp(String lp) {
    return [
      SELECT
        Id,
        StageName,
        Lp_Processed__c,
        Lp_Check_Count__c,
        Token__c,
        Donor_Contact__c,
        Match_Method__c,
        Name,
        Verified_At__c,
        Activated_At__c
      FROM Opportunity
      WHERE LowProfileId__c = :lp AND RecordTypeId = :PLEDGE_RT
    ];
  }

  @IsTest
  static void submitThenWebhookActivatesExactlyOnce() {
    TestDataFactory.settings();
    ContactMatcher.skipDuplicateRules = true;
    insert TestDataFactory.submittedPledge('lp-0000000001', 'donor@example.com', '0521234567');
    CardcomMock.install().always('LowProfile/GetLpResult', 200, CardcomMock.lpSuccess('lp-0000000001', 'SIGNUP-x'));
    runJob(new List<String>{ 'lp-0000000001' });
    Opportunity p = byLp('lp-0000000001');
    Assert.areEqual('Active', p.StageName);
    Assert.areEqual('New', p.Match_Method__c);
    Assert.isNotNull(p.Donor_Contact__c);
    Assert.isNotNull(p.Activated_At__c);
    Assert.areEqual(1, [SELECT COUNT() FROM OpportunityContactRole WHERE OpportunityId = :p.Id]);
    Assert.areEqual(1, [SELECT COUNT() FROM Contact WHERE Email = 'donor@example.com']);
  }

  @IsTest
  static void repeatedWebhooksCallCardcomOnce() {
    TestDataFactory.settings();
    ContactMatcher.skipDuplicateRules = true;
    insert TestDataFactory.submittedPledge('lp-0000000001', 'donor@example.com', '0521234567');
    CardcomMock m = CardcomMock.install().always('LowProfile/GetLpResult', 200, CardcomMock.lpSuccess('lp-0000000001', 'SIGNUP-x'));
    Test.startTest();
    for (Integer i = 0; i < 3; i++)
      System.enqueueJob(new CardcomLpResultJob(new List<String>{ 'lp-0000000001' }));
    Test.stopTest();
    Assert.areEqual(1, m.requestsTo('LowProfile/GetLpResult').size(), 'webhook ×3 is a no-op after the first (B6.13 E1)');
    Assert.areEqual(1, [SELECT COUNT() FROM Opportunity WHERE LowProfileId__c = 'lp-0000000001']);
    Assert.areEqual(1, [SELECT COUNT() FROM OpportunityContactRole]);
    Assert.areEqual('Active', byLp('lp-0000000001').StageName);
  }

  @IsTest
  static void stillOnPaymentPageChangesNothing() {
    TestDataFactory.settings();
    insert TestDataFactory.submittedPledge('lp-0000000001', 'donor@example.com', '0521234567');
    CardcomMock.install().always('LowProfile/GetLpResult', 200, CardcomMock.lpPending('lp-0000000001'));
    runJob(new List<String>{ 'lp-0000000001' });
    Opportunity p = byLp('lp-0000000001');
    Assert.areEqual(0, p.Lp_Check_Count__c.intValue());
    Assert.isFalse(p.Lp_Processed__c);
  }

  @IsTest
  static void sixthFailedCheckMarksVerificationFailed() {
    TestDataFactory.settings();
    Opportunity five = TestDataFactory.submittedPledge('lp-0000000001', 'a@example.com', '0521234567');
    five.Lp_Check_Count__c = 5;
    Opportunity zero = TestDataFactory.submittedPledge('lp-0000000002', 'b@example.com', '0527654321');
    insert new List<Opportunity>{ five, zero };
    CardcomMock.install()
      .enqueue('LowProfile/GetLpResult', 200, CardcomMock.lpFailed('lp-0000000001'))
      .enqueue('LowProfile/GetLpResult', 200, CardcomMock.lpFailed('lp-0000000002'));
    runJob(new List<String>{ 'lp-0000000001', 'lp-0000000002' });
    Opportunity p1 = byLp('lp-0000000001');
    Assert.areEqual('Verification_Failed', p1.StageName);
    Assert.areEqual(6, p1.Lp_Check_Count__c.intValue());
    Assert.isTrue(p1.Lp_Processed__c);
    Opportunity p2 = byLp('lp-0000000002');
    Assert.areEqual('Pending_Verification', p2.StageName);
    Assert.areEqual(1, p2.Lp_Check_Count__c.intValue());
  }

  @IsTest
  static void webhookBeforeSubmitCreatesVerifiedPendingPledge() {
    TestDataFactory.settings();
    insert new Cardcom_Webhook_Log__c(LowProfileId__c = 'lp-0000000001', Received_At__c = Datetime.now());
    CardcomMock.install().always('LowProfile/GetLpResult', 200, CardcomMock.lpSuccess('lp-0000000001', 'SIGNUP-x'));
    runJob(new List<String>{ 'lp-0000000001' });
    Opportunity p = byLp('lp-0000000001');
    Assert.areEqual('Pending_Verification', p.StageName);
    Assert.isTrue(p.Lp_Processed__c);
    Assert.isNotNull(p.Verified_At__c);
    Assert.areEqual(MicroPledges.initialName('lp-0000000001'), p.Name);
    Assert.isTrue([SELECT Processed__c FROM Cardcom_Webhook_Log__c].Processed__c);
  }

  @IsTest
  static void otherOpportunitiesAreNeverSelectedOrModified() {
    TestDataFactory.settings();
    Opportunity other = TestDataFactory.otherOpportunity();
    if (other == null)
      return; // no non-pledge Opportunity record type for this user: nothing else to protect
    other.LowProfileId__c = 'lp-0000000009';
    update other;
    Datetime before = [SELECT LastModifiedDate FROM Opportunity WHERE Id = :other.Id].LastModifiedDate;
    CardcomMock.install().always('LowProfile/GetLpResult', 200, CardcomMock.lpSuccess('lp-0000000009', 'SIGNUP-x'));
    runJob(new List<String>{ 'lp-0000000009' });
    Opportunity after = [SELECT StageName, Token__c, Lp_Processed__c, LastModifiedDate, RecordTypeId FROM Opportunity WHERE Id = :other.Id];
    Assert.areEqual('Prospecting', after.StageName);
    Assert.isNull(after.Token__c);
    Assert.isFalse(after.Lp_Processed__c);
    Assert.areEqual(before, after.LastModifiedDate);
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM Opportunity WHERE RecordTypeId = :PLEDGE_RT],
      'the unique LowProfileId blocks a pledge copy; the insert failure is swallowed'
    );
  }

  @IsTest
  static void calloutFailureLeavesEverythingForTheSweeper() {
    TestDataFactory.settings();
    insert TestDataFactory.submittedPledge('lp-0000000001', 'donor@example.com', '0521234567');
    CardcomMock.install().always('LowProfile/GetLpResult', 200, CardcomMock.TIMEOUT);
    runJob(new List<String>{ 'lp-0000000001' });
    Opportunity p = byLp('lp-0000000001');
    Assert.areEqual(0, p.Lp_Check_Count__c.intValue());
    Assert.isFalse(p.Lp_Processed__c);
  }

  @IsTest
  static void cardChangeResultsGoToCardChangeService() {
    TestDataFactory.settings();
    Contact c = TestDataFactory.contact('Avi', 'Cohen', 'avi@example.com', '0521111111');
    Opportunity p = TestDataFactory.activePledge(c, 'lp-0000000001');
    insert new Card_Change_Request__c(Pledge__c = p.Id, LowProfileId__c = 'lp-card-000001', Status__c = 'Pending');
    CardcomMock.install()
      .enqueue('LowProfile/GetLpResult', 200, CardcomMock.lpSuccess('lp-card-000001', 'CARD-x'))
      .enqueue('LowProfile/GetLpResult', 200, CardcomMock.lpSuccess('lp-card-000002', 'CARD-y'));
    runJob(new List<String>{ 'lp-card-000001', 'lp-card-000002' });
    Assert.areEqual(1, [SELECT COUNT() FROM Opportunity], 'card-change results never create pledges');
  }
}
