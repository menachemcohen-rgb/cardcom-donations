@IsTest
private class ChargeOutcomeHandlerTest {
  static Charge__c attempt(Integer n) {
    Charge__c c = new Charge__c(
      Amount__c = 3,
      Scheduled_Date__c = Date.newInstance(2026, 11, 4),
      Slot__c = 'AM',
      Status__c = 'Pending',
      ExternalUniqTranId__c = 'PLG-x-20261104-AM',
      Attempt_Number__c = n
    );
    c.Attempt_Key__c = c.ExternalUniqTranId__c + '-A' + n;
    return c;
  }

  @IsTest
  static void successCarriesCardcomData() {
    TestDataFactory.chargeEngine(TestDataFactory.WED_0800);
    Charge__c c = attempt(1);
    ChargeOutcomeHandler.Result r = ChargeOutcomeHandler.fromResponse(c, TestDataFactory.txSuccess(123456789L, '1234'));
    Assert.areEqual('Success', c.Status__c);
    Assert.areEqual('123456789', c.Cardcom_Tranzaction_Id__c);
    Assert.areEqual('123456789', c.Cardcom_Deal_Number__c);
    Assert.areEqual('0654321', c.Cardcom_Approval_Number__c);
    Assert.isNull(c.Error_Code__c);
    Assert.isNull(r.nextAttempt);
    Assert.isFalse(c.Raw_Response__c.contains('tok-secret'), 'token never stored');
  }

  @IsTest
  static void cardDeadIsFinalForThisLogicalChargeOnly() {
    TestDataFactory.chargeEngine(TestDataFactory.WED_0800);
    ChargeErrorClassifier.overrideMap = new Map<Integer, String>{ 36 => 'Card_Dead' };
    Charge__c c = attempt(1);
    ChargeOutcomeHandler.Result r = ChargeOutcomeHandler.fromResponse(c, TestDataFactory.txFailed(36));
    Assert.areEqual('Failed', c.Status__c);
    Assert.areEqual('Card_Dead', c.Error_Category__c);
    Assert.isTrue(c.Is_Final_Failure__c);
    Assert.isNull(r.nextAttempt, 'no retry (D12)');
    Assert.isFalse(r.configError);
  }

  @IsTest
  static void configErrorHasNoRetryAndIsNotFinal() {
    TestDataFactory.chargeEngine(TestDataFactory.WED_0800);
    ChargeOutcomeHandler.Result r = ChargeOutcomeHandler.fromConfigError(attempt(1), 'HTTP_401', new CalloutException('Invalid username'));
    Assert.areEqual('Config', r.charge.Error_Category__c);
    Assert.isFalse(r.charge.Is_Final_Failure__c, 'not counted in the streak');
    Assert.isNull(r.nextAttempt);
    Assert.isTrue(r.configError);
    Assert.isTrue(ChargeOutcomeHandler.noToken(attempt(1)).configError);
  }

  @IsTest
  static void retryableGoesA1A2A3ThenFinal() {
    TestDataFactory.chargeEngine(TestDataFactory.WED_0800);
    ChargeErrorClassifier.overrideMap = new Map<Integer, String>{ 4 => 'Card_Declined' };
    ChargeOutcomeHandler.Result r1 = ChargeOutcomeHandler.fromResponse(attempt(1), TestDataFactory.txFailed(4));
    Assert.areEqual(2, r1.nextAttempt.Attempt_Number__c.intValue());
    Assert.areEqual(TestDataFactory.WED_0800.addMinutes(60), r1.nextAttempt.Not_Before__c, '+60 min');
    Assert.areEqual('PLG-x-20261104-AM-A2', r1.nextAttempt.Attempt_Key__c);
    Assert.isNull(r1.nextAttempt.Verify_Attempt_Key__c);
    Assert.isFalse(r1.charge.Is_Final_Failure__c);

    ChargeOutcomeHandler.Result r2 = ChargeOutcomeHandler.fromResponse(attempt(2), TestDataFactory.txFailed(4));
    Assert.areEqual(TestDataFactory.WED_0800.addMinutes(240), r2.nextAttempt.Not_Before__c, '+240 min');

    ChargeOutcomeHandler.Result r3 = ChargeOutcomeHandler.fromResponse(attempt(3), TestDataFactory.txFailed(4));
    Assert.isNull(r3.nextAttempt);
    Assert.isTrue(r3.charge.Is_Final_Failure__c, 'Max_Retries__c = 3');
  }

  @IsTest
  static void retryThatWouldFallAfterTheFridayCutoffMovesToSunday() {
    TestDataFactory.chargeEngine(Datetime.newInstance(2026, 11, 6, 13, 30, 0)); // Friday 13:30, +60 → 14:30 (closed)
    ChargeOutcomeHandler.Result r = ChargeOutcomeHandler.fromResponse(attempt(1), TestDataFactory.txFailed(4));
    Assert.areEqual(Datetime.newInstance(2026, 11, 8, 8, 0, 0), r.nextAttempt.Not_Before__c, 'next working morning');
    Assert.areEqual(Date.newInstance(2026, 11, 8), r.nextAttempt.Run_Date__c, 'Run_Date = the day it is sent');
  }

  @IsTest
  static void unknownOutcomeVerifiesTheKeyNextTime() {
    TestDataFactory.chargeEngine(TestDataFactory.WED_0800);
    ChargeOutcomeHandler.Result r = ChargeOutcomeHandler.fromException(attempt(1), 'TIMEOUT', new CalloutException('Read timed out'));
    Assert.areEqual('Unknown', r.charge.Error_Category__c);
    Assert.isTrue(r.charge.Needs_Reconciliation__c);
    Assert.areEqual('PLG-x-20261104-AM-A1', r.nextAttempt.Verify_Attempt_Key__c);
  }

  @IsTest
  static void alreadyChargedAndDuplicateAndPendingCodes() {
    TestDataFactory.chargeEngine(TestDataFactory.WED_0800);
    Charge__c a2 = attempt(2);
    a2.Verify_Attempt_Key__c = 'PLG-x-20261104-AM-A1';
    ChargeOutcomeHandler.alreadyCharged(a2, TestDataFactory.txSuccess(555, null));
    Assert.areEqual('Success', a2.Status__c);
    Assert.areEqual('ALREADY_CHARGED', a2.Error_Code__c);
    Assert.areEqual('555', a2.Cardcom_Tranzaction_Id__c);

    Charge__c dup = attempt(1);
    ChargeOutcomeHandler.fromResponse(dup, TestDataFactory.txFailed(608));
    Assert.areEqual('Skipped', dup.Status__c);
    Assert.areEqual('Duplicate', dup.Error_Category__c);
    Assert.isTrue(dup.Needs_Reconciliation__c);

    ChargeErrorClassifier.overrideMap = new Map<Integer, String>{ 5117 => 'Pending' };
    Charge__c pend = attempt(1);
    ChargeOutcomeHandler.Result r = ChargeOutcomeHandler.fromResponse(pend, TestDataFactory.txFailed(5117));
    Assert.areEqual('Retryable', pend.Error_Category__c, 'Pending is not a Charge category (N12)');
    Assert.isNotNull(r.nextAttempt);

    Assert.areEqual('Skipped', ChargeOutcomeHandler.stopped(attempt(1)).charge.Status__c);
  }

  @IsTest
  static void classifierUsesMetadataAndRanges() {
    Assert.areEqual('Card_Dead', ChargeErrorClassifier.classify(36), 'Cardcom_Error_Code__mdt C36');
    Assert.areEqual('Card_Declined', ChargeErrorClassifier.classify(3000123), '3DS range');
    Assert.areEqual('Card_Declined', ChargeErrorClassifier.classify(60000099), 'issuer range');
    Assert.areEqual('Retryable', ChargeErrorClassifier.classify(999), 'unknown code');
  }
}
