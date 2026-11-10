@IsTest
private class StaffFailureAlertsTest {
  static Opportunity setup() {
    TestDataFactory.chargeEngine(TestDataFactory.WED_0800);
    TestDataFactory.settings().Failure_Notify_Emails__c = 'staff@example.com';
    return TestDataFactory.activePledges(1, 'TwiceDaily')[0];
  }

  static Charge__c attempt(Opportunity p, Integer day, String slot, String status, String code) {
    Charge__c c = TestDataFactory.charge(p, Date.newInstance(2026, 11, day), slot);
    c.Status__c = status;
    c.Executed_At__c = Datetime.now().addMinutes(-30);
    c.Error_Code__c = code;
    c.Error_Message__c = code == null ? null : 'סירוב';
    c.Is_Final_Failure__c = status == 'Failed';
    return c;
  }

  @IsTest
  static void manyFailuresInOneRunAlertStaffAtMostEveryFourHours() {
    Opportunity p = setup();
    insert new List<Charge__c>{
      attempt(p, 2, 'AM', 'Failed', '4'),
      attempt(p, 2, 'PM', 'Failed', '4'),
      attempt(p, 3, 'AM', 'Success', null)
    };
    StaffAlertService.runFailuresInTests = true;
    Integer before = StaffAlertService.sentCount;
    StaffAlertService.runFailures();
    Assert.areEqual(before + 1, StaffAlertService.sentCount, '2 of 3 failed');
    Assert.isNotNull(Alert_State__c.getOrgDefaults().Run_Failure_Sent_At__c);
    StaffAlertService.runFailures();
    Assert.areEqual(before + 1, StaffAlertService.sentCount, 'not again within 4 hours');
  }

  @IsTest
  static void aFewFailuresDoNotAlert() {
    Opportunity p = setup();
    insert new List<Charge__c>{
      attempt(p, 2, 'AM', 'Failed', '4'),
      attempt(p, 2, 'PM', 'Success', null),
      attempt(p, 3, 'AM', 'Success', null)
    };
    StaffAlertService.runFailuresInTests = true;
    Integer before = StaffAlertService.sentCount;
    StaffAlertService.runFailures();
    Assert.areEqual(before, StaffAlertService.sentCount);
  }

  @IsTest
  static void weeklyDigestListsOpenPaymentIssues() {
    Opportunity p = setup();
    Integer before = StaffAlertService.sentCount;
    StaffAlertService.weeklyFailedDigest();
    Assert.areEqual(before, StaffAlertService.sentCount, 'nothing open → no email');
    update new Opportunity(Id = p.Id, Payment_Issue_Since__c = Datetime.now().addDays(-8), Last_Failure_Error__c = '4 סירוב');
    StaffAlertService.weeklyFailedDigest();
    Assert.areEqual(before + 1, StaffAlertService.sentCount);
  }

  @IsTest
  static void lastFailureIsDocumentedOnThePledge() {
    Opportunity p = setup();
    insert attempt(p, 2, 'AM', 'Failed', '36');
    Opportunity after = [SELECT Last_Failure_At__c, Last_Failure_Error__c FROM Opportunity WHERE Id = :p.Id];
    Assert.isNotNull(after.Last_Failure_At__c);
    Assert.areEqual('36 סירוב', after.Last_Failure_Error__c);
  }
}
