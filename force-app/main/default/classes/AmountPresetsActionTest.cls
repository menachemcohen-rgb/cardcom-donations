@IsTest
private class AmountPresetsActionTest {
  static User user(Boolean withPermission) {
    User u;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      String uniq = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
      u = new User(
        ProfileId = UserInfo.getProfileId(),
        Username = 'presets-' + uniq + '@example.com.test',
        Email = 'presets@example.com',
        LastName = 'Presets',
        Alias = 'presets',
        TimeZoneSidKey = 'Asia/Jerusalem',
        LocaleSidKey = 'iw_IL',
        EmailEncodingKey = 'UTF-8',
        LanguageLocaleKey = 'en_US'
      );
      insert u;
      if (withPermission) {
        PermissionSet ps = new PermissionSet(Name = 'Test_Presets_' + uniq, Label = 'Test Presets ' + uniq);
        insert ps;
        CustomPermission cp = [SELECT Id FROM CustomPermission WHERE DeveloperName = 'Manage_Charge_Schedule'];
        insert new SetupEntityAccess(ParentId = ps.Id, SetupEntityId = cp.Id);
        insert new PermissionSetAssignment(PermissionSetId = ps.Id, AssigneeId = u.Id);
      }
    }
    return u;
  }

  static AmountPresetsAction.Result save(String presets) {
    AmountPresetsAction.Request q = new AmountPresetsAction.Request();
    q.presets = presets;
    return AmountPresetsAction.save(new List<AmountPresetsAction.Request>{ q })[0];
  }

  static List<String> errors(String raw) {
    return AmountPresetsAction.validate(raw, 1, 40, new List<Integer>());
  }

  @IsTest
  static void validListIsNormalized() {
    List<Integer> v = new List<Integer>();
    Assert.areEqual(0, AmountPresetsAction.validate(' 10, 1,2 ,3 5', 1, 40, v).size());
    Assert.areEqual(new List<Integer>{ 1, 2, 3, 5, 10 }, v);
  }

  @IsTest
  static void rulesAreChecked() {
    Assert.isFalse(errors('1,2.5').isEmpty(), 'whole numbers only');
    Assert.isFalse(errors('1,abc').isEmpty(), 'not a number');
    Assert.isFalse(errors('0,5').isEmpty(), 'below the minimum');
    Assert.isFalse(errors('5,41').isEmpty(), 'above the maximum');
    Assert.isFalse(errors('5,5').isEmpty(), 'duplicate');
    Assert.isFalse(errors('').isEmpty(), 'empty');
    Assert.isFalse(errors(' , ').isEmpty(), 'only separators');
    Assert.isFalse(errors('1,2,3,4,5,6,7,8,9').isEmpty(), 'more than 8');
    Assert.isTrue(errors('1,2,3,4,5,6,7,8').isEmpty(), '8 is allowed');
    Assert.isTrue(errors('1').isEmpty(), '1 is allowed');
    Assert.isTrue(errors('40').isEmpty(), 'the maximum itself is allowed');
  }

  @IsTest
  static void withoutPermissionNothingIsSaved() {
    TestDataFactory.settings();
    System.runAs(user(false)) {
      AmountPresetsAction.Result r = save('1,2,3');
      Assert.isFalse(r.ok);
      Assert.isNull(AmountPresetsAction.lastContainer);
    }
  }

  @IsTest
  static void invalidListIsRefused() {
    TestDataFactory.settings();
    System.runAs(user(true)) {
      AmountPresetsAction.Result r = save('1,2,2,100');
      Assert.isFalse(r.ok);
      Assert.isTrue(r.message.contains('100'), r.message);
      Assert.isNull(AmountPresetsAction.lastContainer);
    }
  }

  @IsTest
  static void validListBuildsTheDeploymentWithAllFields() {
    Cardcom_Setting__mdt s = TestDataFactory.settings();
    System.runAs(user(true)) {
      AmountPresetsAction.Result r = save('10,2,1,3,5');
      Assert.isTrue(r.ok, r.message);
      Assert.areEqual(1, Limits.getQueueableJobs(), 'the deployment runs in a Queueable (no mixed DML in the flow)');
    }
    Metadata.CustomMetadata md = (Metadata.CustomMetadata) AmountPresetsAction.lastContainer.getMetadata()[0];
    Assert.areEqual('Cardcom_Setting.Default', md.fullName);
    Map<String, Object> vals = new Map<String, Object>();
    for (Metadata.CustomMetadataValue v : md.values)
      vals.put(v.field, v.value);
    Assert.areEqual('1,2,3,5,10', vals.get('Amount_Presets__c'));
    Assert.areEqual(s.Max_Amount__c, vals.get('Max_Amount__c'), 'other fields keep their values');
    Assert.areEqual(s.Terminal_Number__c, vals.get('Terminal_Number__c'));
  }

  @IsTest
  static void sameListIsNotRedeployed() {
    Cardcom_Setting__mdt s = TestDataFactory.settings();
    s.Amount_Presets__c = '1,3,5,10';
    System.runAs(user(true)) {
      AmountPresetsAction.Result r = save('10, 5, 3, 1');
      Assert.isTrue(r.ok);
      Assert.isNull(AmountPresetsAction.lastContainer);
    }
  }

  @IsTest
  static void failedDeploymentEmailsStaff() {
    Cardcom_Setting__mdt s = TestDataFactory.settings();
    s.Failure_Notify_Emails__c = 'staff@example.com';
    Metadata.DeployResult res = new Metadata.DeployResult();
    res.status = Metadata.DeployStatus.Failed;
    res.errorMessage = 'boom';
    Test.startTest();
    new AmountPresetsAction.Callback('1,2').handleResult(res, null);
    Integer sent = Limits.getEmailInvocations();
    Test.stopTest();
    Assert.areEqual(1, sent);
  }

  @IsTest
  static void deployerRunsAfterOtherDml() {
    Cardcom_Setting__mdt s = TestDataFactory.settings();
    insert new Charge_Settings__c(SetupOwnerId = UserInfo.getOrganizationId()); // what ChargeTimesAction does first
    AmountPresetsAction.Deployer job = new AmountPresetsAction.Deployer(
      '1,2',
      'Default',
      new Map<String, Object>{ 'Amount_Presets__c' => '1,2' }
    );
    Test.startTest();
    System.enqueueJob(job);
    Test.stopTest();
    Assert.areEqual(1, job.container().getMetadata().size());
  }
}
