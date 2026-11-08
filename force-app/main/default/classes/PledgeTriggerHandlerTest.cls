@IsTest
private class PledgeTriggerHandlerTest {
  static User staff(Boolean withPermission) {
    User u;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      String uniq = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
      u = new User(
        ProfileId = UserInfo.getProfileId(),
        Username = 'pledge-staff-' + uniq + '@example.com.test',
        Email = 'staff@example.com',
        LastName = 'Staff',
        Alias = 'pstaff',
        TimeZoneSidKey = 'Asia/Jerusalem',
        LocaleSidKey = 'iw_IL',
        EmailEncodingKey = 'UTF-8',
        LanguageLocaleKey = 'en_US'
      );
      insert u;
      if (withPermission) {
        PermissionSet ps = new PermissionSet(Name = 'Test_Stop_' + uniq, Label = 'Test Stop ' + uniq);
        insert ps;
        CustomPermission cp = [SELECT Id FROM CustomPermission WHERE DeveloperName = 'Stop_Pledge_Charges'];
        insert new SetupEntityAccess(ParentId = ps.Id, SetupEntityId = cp.Id);
        insert new PermissionSetAssignment(PermissionSetId = ps.Id, AssigneeId = u.Id);
      }
    }
    return u;
  }

  static Opportunity pledgeWithPendingCharges() {
    TestDataFactory.chargeEngine(TestDataFactory.WED_0800);
    Opportunity p = TestDataFactory.activePledges(1, 'OnceDaily')[0];
    insert new List<Charge__c>{
      TestDataFactory.charge(p, Date.newInstance(2026, 11, 4), 'AM'),
      TestDataFactory.charge(p, Date.newInstance(2026, 11, 5), 'AM')
    };
    return p;
  }

  static List<Pledge_Change_Log__c> logs(Id pledgeId) {
    return [
      SELECT Change_Type__c, Old_Value__c, New_Value__c, Source__c, Changed_By__c
      FROM Pledge_Change_Log__c
      WHERE Pledge__c = :pledgeId
      ORDER BY CreatedDate, Id
    ];
  }

  @IsTest
  static void stopSkipsPendingChargesAndLogs() {
    Opportunity p = pledgeWithPendingCharges();
    User u = staff(true);
    System.runAs(u) {
      update new Opportunity(
        Id = p.Id,
        StageName = 'Stopped',
        Stop_Reason__c = 'Other',
        Stop_Reason_Details__c = 'בקשה טלפונית',
        Stopped_At__c = Datetime.now(),
        Stopped_By__c = u.Id
      );
    }
    for (Charge__c c : [SELECT Status__c, Error_Code__c FROM Charge__c WHERE Pledge__c = :p.Id]) {
      Assert.areEqual('Skipped', c.Status__c);
      Assert.areEqual('STOPPED', c.Error_Code__c);
    }
    List<Pledge_Change_Log__c> l = logs(p.Id);
    Assert.areEqual(1, l.size());
    Assert.areEqual('Stop', l[0].Change_Type__c);
    Assert.areEqual('Active', l[0].Old_Value__c);
    Assert.areEqual('Stopped (Other: בקשה טלפונית)', l[0].New_Value__c);
    Assert.areEqual('Staff', l[0].Source__c);
    Assert.areEqual(u.Id, l[0].Changed_By__c);
  }

  @IsTest
  static void resumeAndCancelAreLoggedAndCancelIsFinal() {
    Opportunity p = pledgeWithPendingCharges();
    System.runAs(staff(true)) {
      update new Opportunity(Id = p.Id, StageName = 'Stopped', Stop_Reason__c = 'Donor_Request');
      update new Opportunity(Id = p.Id, StageName = 'Active', Resumed_At__c = Datetime.now());
      update new Opportunity(Id = p.Id, StageName = 'Cancelled', End_Date__c = Date.today());
      Database.SaveResult r = Database.update(new Opportunity(Id = p.Id, StageName = 'Active'), false);
      Assert.isFalse(r.isSuccess(), 'Cancelled cannot be reopened (VR_No_Reactivate_Cancelled)');
    }
    List<String> types = new List<String>();
    for (Pledge_Change_Log__c l : logs(p.Id))
      types.add(l.Change_Type__c);
    Assert.areEqual(new List<String>{ 'Stop', 'Resume', 'Cancel' }, types);
  }

  @IsTest
  static void userWithoutPermissionIsBlocked() {
    Opportunity p = pledgeWithPendingCharges();
    System.runAs(staff(false)) {
      Database.SaveResult r = Database.update(new Opportunity(Id = p.Id, StageName = 'Stopped', Stop_Reason__c = 'Donor_Request'), false);
      Assert.isFalse(r.isSuccess());
      String msg = r.getErrors()[0].getMessage();
      Assert.isTrue(msg.contains('You don\'t have permission') || msg.contains('אין לך הרשאה'), msg); // iw translation for Hebrew users
    }
    Assert.areEqual(2, [SELECT COUNT() FROM Charge__c WHERE Pledge__c = :p.Id AND Status__c = 'Pending']);
  }

  @IsTest
  static void revokingLinksIsLogged() {
    Opportunity p = pledgeWithPendingCharges();
    update new Opportunity(Id = p.Id, Link_Version__c = 5);
    update new Opportunity(Id = p.Id, Link_Version__c = 6);
    List<Pledge_Change_Log__c> l = logs(p.Id);
    Pledge_Change_Log__c last = l[l.size() - 1];
    Assert.areEqual('Link_Revoke', last.Change_Type__c);
    Assert.areEqual('5', last.Old_Value__c);
    Assert.areEqual('6', last.New_Value__c);
  }

  @IsTest
  static void otherOpportunitiesAreUnaffected() {
    TestDataFactory.chargeEngine(TestDataFactory.WED_0800);
    Opportunity other = TestDataFactory.otherOpportunity();
    if (other != null) {
      update new Opportunity(Id = other.Id, StageName = 'Closed Lost');
      Assert.areEqual(0, [SELECT COUNT() FROM Pledge_Change_Log__c]);
    }
    Assert.isNull(OpportunityTriggerHandler.changeType('Pending_Verification', 'Active'), 'activation is not a manual change');
  }

  @IsTest
  static void resumeClearsTheReasonAndFreesTodaysAndLaterStoppedSlots() {
    // N87. Engine clock = Wed 2026-11-04 08:00; the pledge has Pending charges for Nov 4 and Nov 5 (+ one for Nov 3 here)
    Opportunity p = pledgeWithPendingCharges();
    Charge__c past = TestDataFactory.charge(p, Date.newInstance(2026, 11, 3), 'AM');
    insert past;
    System.runAs(staff(true)) {
      update new Opportunity(Id = p.Id, StageName = 'Stopped', Stop_Reason__c = 'Other', Stop_Reason_Details__c = 'בדיקה');
    }
    Assert.areEqual(3, [SELECT COUNT() FROM Charge__c WHERE Pledge__c = :p.Id AND Status__c = 'Skipped' AND Error_Code__c = 'STOPPED']);

    System.runAs(staff(true)) {
      update new Opportunity(Id = p.Id, StageName = 'Active'); // a direct edit, not only the flow
    }
    Opportunity after = [SELECT Stop_Reason__c, Stop_Reason_Details__c FROM Opportunity WHERE Id = :p.Id];
    Assert.isNull(after.Stop_Reason__c, 'cleared on resume');
    Assert.isNull(after.Stop_Reason_Details__c);
    Assert.isTrue(logs(p.Id)[0].New_Value__c.contains('Other'), 'the reason stays in the Stop log entry');

    for (Charge__c c : [SELECT Scheduled_Date__c, Status__c, Attempt_Key__c, ExternalUniqTranId__c FROM Charge__c WHERE Pledge__c = :p.Id]) {
      Assert.areEqual('Skipped', c.Status__c, 'history kept');
      if (c.Scheduled_Date__c < Date.newInstance(2026, 11, 4))
        Assert.areEqual(c.ExternalUniqTranId__c + '-A1', c.Attempt_Key__c, 'past slot untouched');
      else
        Assert.isTrue(c.Attempt_Key__c.contains('-STOPPED-'), 'key released: ' + c.Attempt_Key__c);
    }

    // The next run plans the slot again with the normal key; the missed past slot is not made up
    Assert.areEqual(1, ChargePlanner.plan(Date.newInstance(2026, 11, 4), 'AM'));
    Charge__c planned = [SELECT Attempt_Key__c, Scheduled_Date__c FROM Charge__c WHERE Pledge__c = :p.Id AND Status__c = 'Pending'];
    Assert.areEqual(Date.newInstance(2026, 11, 4), planned.Scheduled_Date__c);
    Assert.isTrue(planned.Attempt_Key__c.endsWith('-20261104-AM-A1'));
  }

  @IsTest
  static void reasonIsKeptWhileStillStopped() {
    Opportunity p = pledgeWithPendingCharges();
    System.runAs(staff(true)) {
      update new Opportunity(Id = p.Id, StageName = 'Stopped', Stop_Reason__c = 'Donor_Request');
      update new Opportunity(Id = p.Id, Stop_Reason__c = 'Financial_Review'); // still Stopped
    }
    Assert.areEqual('Financial_Review', [SELECT Stop_Reason__c FROM Opportunity WHERE Id = :p.Id].Stop_Reason__c);
  }
}
