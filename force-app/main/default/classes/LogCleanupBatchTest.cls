@IsTest
private class LogCleanupBatchTest {
  @IsTest
  static void removesOldLogsAndRawPayloads() {
    TestDataFactory.chargeEngine(TestDataFactory.WED_0800);
    Opportunity p = TestDataFactory.activePledges(1, 'OnceDaily')[0];
    Cardcom_Webhook_Log__c oldLog = new Cardcom_Webhook_Log__c(LowProfileId__c = 'lp-old-0000000001', Raw_Body__c = '{}');
    Cardcom_Webhook_Log__c newLog = new Cardcom_Webhook_Log__c(LowProfileId__c = 'lp-new-0000000001', Raw_Body__c = '{}');
    insert new List<Cardcom_Webhook_Log__c>{ oldLog, newLog };
    Charge__c oldCharge = TestDataFactory.charge(p, Date.newInstance(2026, 7, 1), 'AM');
    Charge__c newCharge = TestDataFactory.charge(p, Date.newInstance(2026, 11, 1), 'AM');
    oldCharge.Raw_Response__c = '{"ResponseCode":0}';
    newCharge.Raw_Response__c = '{"ResponseCode":0}';
    insert new List<Charge__c>{ oldCharge, newCharge };
    Monthly_Receipt__c oldReceipt = new Monthly_Receipt__c(
      Contact__c = p.Donor_Contact__c,
      Period_Month__c = Date.newInstance(2026, 6, 1),
      Receipt_Key__c = p.Donor_Contact__c + '-202606',
      Status__c = 'Issued',
      Total_Amount__c = 90,
      Charge_Count__c = 30,
      Raw_Request__c = '{"Document":{}}',
      Raw_Response__c = '{"ResponseCode":0}'
    );
    insert oldReceipt;
    Datetime past = Datetime.now().addDays(-100);
    Test.setCreatedDate(oldLog.Id, past);
    Test.setCreatedDate(oldCharge.Id, past);
    Test.setCreatedDate(oldReceipt.Id, past);

    Test.startTest();
    Database.executeBatch(new LogCleanupBatch(), 500);
    Database.executeBatch(new LogCleanupBatch(1), 500);
    Database.executeBatch(new LogCleanupBatch(2), 500);
    Test.stopTest();

    Assert.areEqual(1, [SELECT COUNT() FROM Cardcom_Webhook_Log__c]);
    Assert.areEqual(newLog.Id, [SELECT Id FROM Cardcom_Webhook_Log__c].Id);
    Assert.isNull([SELECT Raw_Response__c FROM Charge__c WHERE Id = :oldCharge.Id].Raw_Response__c);
    Assert.isNotNull([SELECT Raw_Response__c FROM Charge__c WHERE Id = :newCharge.Id].Raw_Response__c, 'recent payloads stay');
    Monthly_Receipt__c r = [SELECT Raw_Request__c, Raw_Response__c, Status__c FROM Monthly_Receipt__c WHERE Id = :oldReceipt.Id];
    Assert.isNull(r.Raw_Request__c);
    Assert.isNull(r.Raw_Response__c);
    Assert.areEqual('Issued', r.Status__c, 'only the raw fields are cleared');
  }

  @IsTest
  static void isSchedulableByName() {
    // DonationSetup schedules it by class name (N46)
    Object job = Type.forName('LogCleanupBatch').newInstance();
    Assert.isTrue(job instanceof Schedulable);
    Test.startTest();
    Id cronId = System.schedule('Donations Log Cleanup test', '0 0 3 ? * SUN', (Schedulable) job);
    Test.stopTest();
    Assert.areEqual(1, [SELECT COUNT() FROM CronTrigger WHERE Id = :cronId]);
  }
}
