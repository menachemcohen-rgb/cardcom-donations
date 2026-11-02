@IsTest
private class StaffAlertServiceTest {
  @IsTest
  static void recipientsParseCommasAndSemicolons() {
    TestDataFactory.settings().Failure_Notify_Emails__c = ' a@example.com;b@example.com, ,c@example.com ';
    Assert.areEqual(new List<String>{ 'a@example.com', 'b@example.com', 'c@example.com' }, StaffAlertService.recipients());
    TestDataFactory.settings().Failure_Notify_Emails__c = null;
    Assert.isTrue(StaffAlertService.recipients().isEmpty());
  }

  @IsTest
  static void configErrorAlertIsSentOncePerDay() {
    TestDataFactory.settings().Failure_Notify_Emails__c = 'staff@example.com';
    Assert.isTrue(StaffAlertService.configErrorOncePerDay());
    Assert.isFalse(StaffAlertService.configErrorOncePerDay());
    Assert.areEqual(1, StaffAlertService.sentCount);
    StaffAlertService.scheduleChanged(ChargeSettings.defaults());
  }
}
