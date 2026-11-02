@IsTest
private class ChargeRetryTest {
  static final Date WED = Date.newInstance(2026, 11, 4);

  @IsTest
  static void delaysAndWindows() {
    TestDataFactory.chargeEngine(TestDataFactory.WED_0800);
    Assert.areEqual(60, ChargeRetryPolicy.delayMinutes(1));
    Assert.areEqual(240, ChargeRetryPolicy.delayMinutes(2));
    Assert.areEqual(240, ChargeRetryPolicy.delayMinutes(5), 'last delay repeats');
    Assert.areEqual(TestDataFactory.WED_0800, ChargeRetryPolicy.nextWindow(TestDataFactory.WED_0800));
    Assert.areEqual(Datetime.newInstance(2026, 11, 8, 8, 0, 0), ChargeRetryPolicy.nextWindow(Datetime.newInstance(2026, 11, 7, 9, 0, 0)));
  }

  @IsTest
  static void retrySchedulerStartsTheChainOnlyWhenRetriesAreDue() {
    TestDataFactory.chargeEngine(Datetime.newInstance(2026, 11, 4, 10, 30, 0));
    Opportunity p = TestDataFactory.activePledges(1, 'OnceDaily')[0];
    Assert.isFalse(ChargeRetryScheduler.run(ChargeCalendar.now()), 'nothing due');
    Charge__c a2 = TestDataFactory.charge(p, WED, 'AM');
    a2.Attempt_Number__c = 2;
    a2.Attempt_Key__c = a2.ExternalUniqTranId__c + '-A2';
    a2.Not_Before__c = Datetime.newInstance(2026, 11, 4, 9, 0, 0);
    insert a2;
    Assert.isFalse(ChargeRetryScheduler.run(Datetime.newInstance(2026, 11, 7, 10, 30, 0)), 'Shabbat');
    Assert.isTrue(ChargeRetryScheduler.run(ChargeCalendar.now()));
    Assert.isTrue(ChargeRunLock.isChainActive(), 'dispatcher took the lock');
    Assert.isFalse(ChargeRetryScheduler.run(ChargeCalendar.now()), 'chain already running');
  }

  @IsTest
  static void dispatcherReleasesTheLockWhenDoneOrClosed() {
    TestDataFactory.chargeEngine(Datetime.newInstance(2026, 11, 7, 10, 0, 0)); // Shabbat
    ChargeRunLock.acquire();
    ChargeDispatcher.start();
    Assert.isFalse(ChargeRunLock.isChainActive(), 'closed window → released');
    ChargeCalendar.nowOverride = TestDataFactory.WED_0800;
    ChargeRunLock.acquire();
    ChargeDispatcher.start();
    Assert.isFalse(ChargeRunLock.isChainActive(), 'nothing pending → released');
    ChargeSettings.overrideValue.Charging_Enabled__c = false;
    ChargeRunLock.acquire();
    ChargeDispatcher.start();
    Assert.isFalse(ChargeRunLock.isChainActive(), 'emergency switch → nothing sent, lock released (N55)');
  }

  @IsTest
  static void scheduledRetryRuns() {
    TestDataFactory.chargeEngine(TestDataFactory.WED_0800);
    Test.startTest();
    String id = System.schedule('Test retry', '0 30 * ? * SUN-FRI', new ChargeRetryScheduler());
    Test.stopTest();
    Assert.isNotNull(id);
  }
}
