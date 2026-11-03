@IsTest
private class ChargeQueueableTest {
  static final Date WED = Date.newInstance(2026, 11, 4);

  static void run(List<Charge__c> cs) {
    List<Id> ids = new List<Id>();
    for (Charge__c c : cs)
      ids.add(c.Id);
    Test.startTest();
    System.enqueueJob(new ChargeQueueable(ids));
    Test.stopTest();
  }

  static Charge__c reload(Id id) {
    return [
      SELECT
        Status__c,
        Error_Code__c,
        Error_Category__c,
        Is_Final_Failure__c,
        Needs_Reconciliation__c,
        Cardcom_Tranzaction_Id__c,
        Attempt_Key__c,
        Verify_Attempt_Key__c,
        Raw_Response__c
      FROM Charge__c
      WHERE Id = :id
    ];
  }

  @IsTest
  static void successfulChargeUpdatesChargeAndPledgeLast4() {
    // TC11
    TestDataFactory.chargeEngine(TestDataFactory.WED_0800);
    Opportunity p = TestDataFactory.activePledges(1, 'OnceDaily')[0];
    Charge__c c = TestDataFactory.pendingCharge(p, WED, 'AM', 1, null);
    CardcomMock m = CardcomMock.install().always('Transactions/Transaction', 200, TestDataFactory.txSuccess(987654321L, '4321'));
    run(new List<Charge__c>{ c });
    Charge__c r = reload(c.Id);
    Assert.areEqual('Success', r.Status__c);
    Assert.areEqual('987654321', r.Cardcom_Tranzaction_Id__c);
    Assert.areEqual('4321', [SELECT Last4__c FROM Opportunity WHERE Id = :p.Id].Last4__c);
    Map<String, Object> body = m.lastBody('Transactions/Transaction');
    Assert.areEqual(c.Attempt_Key__c, body.get('ExternalUniqTranId'), 'ExternalUniqTranId = Attempt_Key__c (B5.4)');
    Assert.areEqual(true, body.get('ExternalUniqUniqTranIdResponse'));
    Assert.isFalse(body.containsKey('Document'));
    Assert.areEqual(3, ((Decimal) body.get('Amount')).intValue());
  }

  @IsTest
  static void expiredCardFailsFinalAndTheNextChargeIsStillPlanned() {
    // TC16/TC17, D11/D12
    TestDataFactory.chargeEngine(TestDataFactory.WED_0800);
    Opportunity p = TestDataFactory.activePledges(1, 'OnceDaily')[0];
    Charge__c c = TestDataFactory.pendingCharge(p, WED, 'AM', 1, null);
    CardcomMock.install().always('Transactions/Transaction', 200, TestDataFactory.txFailed(36));
    run(new List<Charge__c>{ c });
    Charge__c r = reload(c.Id);
    Assert.areEqual('Card_Dead', r.Error_Category__c);
    Assert.isTrue(r.Is_Final_Failure__c);
    Assert.areEqual(1, [SELECT COUNT() FROM Charge__c], 'no retry');
    Assert.areEqual('Active', [SELECT StageName FROM Opportunity WHERE Id = :p.Id].StageName, 'never suspended (D9)');
    ChargeCalendar.nowOverride = Datetime.newInstance(2026, 11, 5, 8, 0, 0);
    Assert.areEqual(1, ChargePlanner.plan(WED.addDays(1), 'AM'), 'next day is charged as usual');
  }

  @IsTest
  static void configErrorCreatesNoRetryAndAlertsOncePerDay() {
    // B6.13 E21
    TestDataFactory.chargeEngine(TestDataFactory.WED_0800);
    List<Opportunity> ps = TestDataFactory.activePledges(2, 'OnceDaily');
    Charge__c a = TestDataFactory.pendingCharge(ps[0], WED, 'AM', 1, null);
    Charge__c b = TestDataFactory.pendingCharge(ps[1], WED, 'AM', 1, null);
    CardcomMock.install().always('Transactions/Transaction', 401, '{"ResponseCode":401,"Description":"Invalid username"}');
    run(new List<Charge__c>{ a, b });
    Assert.areEqual('HTTP_401', reload(a.Id).Error_Code__c);
    Assert.areEqual('Config', reload(b.Id).Error_Category__c);
    Assert.isFalse(reload(a.Id).Is_Final_Failure__c);
    Assert.areEqual(2, [SELECT COUNT() FROM Charge__c], 'no retries');
    Assert.areEqual(Date.today(), Alert_State__c.getOrgDefaults().Config_Error_Sent_On__c);

    Assert.areEqual(2, ChargeAdmin.requeueFailedConfig(WED), 'manual re-run after the fix');
    Assert.areEqual(0, ChargeAdmin.requeueFailedConfig(WED), 'only once');
    Assert.areEqual(2, [SELECT COUNT() FROM Charge__c WHERE Attempt_Number__c = 2 AND Status__c = 'Pending']);
  }

  @IsTest
  static void timeoutLeadsToAVerifiedRetry() {
    TestDataFactory.chargeEngine(TestDataFactory.WED_0800);
    Opportunity p = TestDataFactory.activePledges(1, 'OnceDaily')[0];
    Charge__c c = TestDataFactory.pendingCharge(p, WED, 'AM', 1, null);
    CardcomMock.install().always('Transactions/Transaction', 200, CardcomMock.TIMEOUT);
    run(new List<Charge__c>{ c });
    Charge__c r = reload(c.Id);
    Assert.areEqual('Unknown', r.Error_Category__c);
    Assert.isTrue(r.Needs_Reconciliation__c);
    Charge__c next = [SELECT Attempt_Number__c, Verify_Attempt_Key__c, Not_Before__c FROM Charge__c WHERE Attempt_Number__c = 2];
    Assert.areEqual(c.Attempt_Key__c, next.Verify_Attempt_Key__c);
    Assert.areEqual(TestDataFactory.WED_0800.addMinutes(60), next.Not_Before__c);
  }

  @IsTest
  static void verifiedPreviousSuccessIsNotChargedAgain() {
    // B6.13 E9
    TestDataFactory.chargeEngine(TestDataFactory.WED_0800);
    Opportunity p = TestDataFactory.activePledges(1, 'OnceDaily')[0];
    Charge__c a2 = TestDataFactory.pendingCharge(p, WED, 'AM', 2, 'PLG-prev-A1');
    CardcomMock m = CardcomMock.install()
      .always('Transactions/GetTransactionByExternalUniqTran', 200, TestDataFactory.txSuccess(555, null));
    run(new List<Charge__c>{ a2 });
    Charge__c r = reload(a2.Id);
    Assert.areEqual('Success', r.Status__c);
    Assert.areEqual('ALREADY_CHARGED', r.Error_Code__c);
    Assert.areEqual(0, m.requestsTo('Transactions/Transaction').size(), 'no second charge');
    Assert.areEqual('PLG-prev-A1', m.lastBody('Transactions/GetTransactionByExternalUniqTran').get('ExternalUniqTranId'));
  }

  @IsTest
  static void verifiedPreviousFailureIsChargedNormally() {
    TestDataFactory.chargeEngine(TestDataFactory.WED_0800);
    Opportunity p = TestDataFactory.activePledges(1, 'OnceDaily')[0];
    Charge__c a2 = TestDataFactory.pendingCharge(p, WED, 'AM', 2, 'PLG-prev-A1');
    CardcomMock m = CardcomMock.install()
      .always('Transactions/GetTransactionByExternalUniqTran', 200, TestDataFactory.txFailed(1))
      .always('Transactions/Transaction', 200, TestDataFactory.txSuccess(777, '1234'));
    run(new List<Charge__c>{ a2 });
    Assert.areEqual('Success', reload(a2.Id).Status__c);
    Assert.areEqual(1, m.requestsTo('Transactions/Transaction').size());
  }

  @IsTest
  static void stoppedPledgeIsSkipped() {
    TestDataFactory.chargeEngine(TestDataFactory.WED_0800);
    Contact c = TestDataFactory.contact('Ben', 'Levi', 'ben@example.com', '0522222222');
    Opportunity p = TestDataFactory.withToken(TestDataFactory.submittedPledge('lp-stopped-0001', c.Email, c.MobilePhone));
    p.StageName = 'Stopped';
    p.Stop_Reason__c = 'Donor_Request';
    p.Donor_Contact__c = c.Id;
    insert p;
    Charge__c ch = TestDataFactory.pendingCharge(p, WED, 'AM', 1, null);
    CardcomMock m = CardcomMock.install();
    run(new List<Charge__c>{ ch });
    Charge__c r = reload(ch.Id);
    Assert.areEqual('Skipped', r.Status__c);
    Assert.areEqual('STOPPED', r.Error_Code__c);
    Assert.isTrue(m.requests.isEmpty(), 'no Cardcom call');
  }

  @IsTest
  static void serverErrorAndDuplicateResponses() {
    TestDataFactory.chargeEngine(TestDataFactory.WED_0800);
    List<Opportunity> ps = TestDataFactory.activePledges(2, 'OnceDaily');
    Charge__c a = TestDataFactory.pendingCharge(ps[0], WED, 'AM', 1, null);
    Charge__c b = TestDataFactory.pendingCharge(ps[1], WED, 'AM', 1, null);
    CardcomMock.install()
      .enqueue('Transactions/Transaction', 503, 'unavailable')
      .enqueue('Transactions/Transaction', 200, TestDataFactory.txFailed(608));
    run(new List<Charge__c>{ a, b });
    Charge__c ra = reload(a.Id), rb = reload(b.Id);
    Assert.areEqual('HTTP_503', (ra.Error_Code__c == 'HTTP_503' ? ra : rb).Error_Code__c);
    Charge__c dup = ra.Status__c == 'Skipped' ? ra : rb;
    Assert.areEqual('Duplicate', dup.Error_Category__c);
  }

  @IsTest
  static void calloutBudgetLeavesTheRestPending() {
    // N51: past the time budget nothing more is sent; the next link picks the charges up.
    TestDataFactory.chargeEngine(TestDataFactory.WED_0800);
    Opportunity p = TestDataFactory.activePledges(1, 'OnceDaily')[0];
    Charge__c c = TestDataFactory.pendingCharge(p, WED, 'AM', 1, null);
    CardcomMock m = CardcomMock.install();
    ChargeQueueable.CALLOUT_BUDGET_MS = -1;
    run(new List<Charge__c>{ c });
    Assert.areEqual('Pending', reload(c.Id).Status__c);
    Assert.isTrue(m.requests.isEmpty());
  }

  @IsTest
  static void credentialErrorIsAConfigErrorWithoutRetry() {
    TestDataFactory.chargeEngine(TestDataFactory.WED_0800);
    Opportunity p = TestDataFactory.activePledges(1, 'OnceDaily')[0];
    Charge__c c = TestDataFactory.pendingCharge(p, WED, 'AM', 1, null);
    CardcomMock.install().always('Transactions/Transaction', 200, CardcomMock.CREDENTIAL_ERROR);
    run(new List<Charge__c>{ c });
    Charge__c r = reload(c.Id);
    Assert.areEqual('Failed', r.Status__c);
    Assert.areEqual('CONFIG_ERROR', r.Error_Code__c);
    Assert.areEqual('Config', r.Error_Category__c);
    Assert.isFalse(r.Needs_Reconciliation__c, 'nothing reached Cardcom');
    Assert.isFalse(r.Is_Final_Failure__c, 'not counted in the failure streak');
    Assert.areEqual(1, [SELECT COUNT() FROM Charge__c], 'no automatic retry');
    Assert.areEqual(Date.today(), Alert_State__c.getOrgDefaults().Config_Error_Sent_On__c, 'staff alert');
    Assert.areEqual(1, ChargeAdmin.requeueFailedConfig(WED), 'can be re-run after the fix');
  }

  @IsTest
  static void credentialErrorWhileVerifyingIsAlsoConfig() {
    TestDataFactory.chargeEngine(TestDataFactory.WED_0800);
    Opportunity p = TestDataFactory.activePledges(1, 'OnceDaily')[0];
    Charge__c c = TestDataFactory.pendingCharge(p, WED, 'AM', 2, 'PLG-x-A1');
    CardcomMock.install().always('Transactions/GetTransactionByExternalUniqTran', 200, CardcomMock.CREDENTIAL_ERROR);
    run(new List<Charge__c>{ c });
    Assert.areEqual('CONFIG_ERROR', reload(c.Id).Error_Code__c);
    Assert.areEqual(1, [SELECT COUNT() FROM Charge__c], 'no automatic retry');
  }

  @IsTest
  static void timeoutIsNotMistakenForACredentialError() {
    Assert.isFalse(ChargeQueueable.isCredentialError(new CalloutException('Read timed out')));
    Assert.isTrue(ChargeQueueable.isCredentialError(new CalloutException(CardcomMock.CREDENTIAL_MESSAGE)));
    Assert.isTrue(ChargeQueueable.isCredentialError(new CalloutException('Unauthorized endpoint, please check Setup')));
  }
}
