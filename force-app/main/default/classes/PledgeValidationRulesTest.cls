/**
 * Behaviour tests for the Prompt 1 validation rules (B2.1 VR_Tax_Id_Format; Part C C2 Opportunity rules).
 * Every Opportunity rule is guarded by Type = 'Daily Donation Pledge', so other Opportunities are never affected (D24, D34).
 * Messages are asserted on the Hebrew text from the spec.
 */
@IsTest
private class PledgeValidationRulesTest {

  private static Opportunity pledge(String stage, Decimal amount) {
    return new Opportunity(
      Type = MicroPledges.TYPE,
      Name = 'תרומה יומית – test',
      StageName = stage,
      CloseDate = Date.today(),
      Charge_Amount__c = amount,
      Frequency__c = 'OnceDaily',
      LowProfileId__c = 'lp-' + Crypto.getRandomInteger()
    );
  }

  private static Contact donor() {
    Contact c = new Contact(FirstName = 'Test', LastName = 'Donor', Email = 'donor@example.com');
    Database.DMLOptions o = new Database.DMLOptions();
    o.DuplicateRuleHeader.allowSave = true; // the org's standard Contact duplicate rule alerts on similar names
    Database.insert(c, o);
    return c;
  }

  private static Opportunity activePledge() {
    Opportunity o = pledge('Active', 3);
    o.Token__c = 'test-token';
    o.Donor_Contact__c = donor().Id;
    return o;
  }

  private static void assertFails(Database.SaveResult r, String expectedMessage) {
    Assert.isFalse(r.isSuccess(), 'Expected the save to fail with: ' + expectedMessage);
    Boolean found = false;
    for (Database.Error e : r.getErrors()) {
      if (e.getMessage().unescapeHtml4().contains(expectedMessage)) {
        found = true;
      }
    }
    Assert.isTrue(found, 'Expected "' + expectedMessage + '", got ' + r.getErrors());
  }

  private static void assertSucceeds(Database.SaveResult r) {
    Assert.isTrue(r.isSuccess(), 'Expected success, got ' + r.getErrors());
  }

  @IsTest
  static void contactTaxIdMustBeNineDigits() {
    assertFails(Database.insert(new Contact(LastName = 'Bad', Donor_Tax_Id__c = '12345'), false), 'ת"ז חייבת להכיל 9 ספרות');
    assertSucceeds(Database.insert(new Contact(LastName = 'Good', Donor_Tax_Id__c = '000000018'), false));
  }

  @IsTest
  static void amountMustBeWithinRange() {
    assertFails(Database.insert(pledge('Pending_Verification', 0.5), false), 'הסכום חייב להיות בין המינימום למקסימום');
    assertFails(Database.insert(pledge('Pending_Verification', 999), false), 'הסכום חייב להיות בין המינימום למקסימום');
    assertSucceeds(Database.insert(pledge('Pending_Verification', 3), false));
  }

  @IsTest
  static void otherOpportunitiesAreNotAffected() {
    Opportunity other = new Opportunity(
      Type = 'New Business',
      Name = 'Regular deal',
      StageName = 'Prospecting',
      CloseDate = Date.today(),
      Charge_Amount__c = 0.5
    );
    assertSucceeds(Database.insert(other, false));
    other.StageName = 'Closed Won';
    assertSucceeds(Database.update(other, false));
  }

  @IsTest
  static void activeRequiresTokenAndDonor() {
    assertFails(Database.insert(pledge('Active', 3), false), 'הוראה פעילה חייבת אסימון כרטיס ותורם משויך');
    assertSucceeds(Database.insert(activePledge(), false));
  }

  @IsTest
  static void stopRequiresReasonAndDetails() {
    Opportunity noReason = activePledge();
    noReason.StageName = 'Stopped';
    assertFails(Database.insert(noReason, false), 'חובה לבחור סיבת הפסקה');

    Opportunity otherNoDetails = activePledge();
    otherNoDetails.StageName = 'Stopped';
    otherNoDetails.Stop_Reason__c = 'Other';
    assertFails(Database.insert(otherNoDetails, false), 'חובה למלא פירוט');
  }

  @IsTest
  static void stoppingWithoutPermissionIsBlocked() {
    Opportunity o = activePledge();
    insert o;

    // A user with the running user's profile and no permission sets: no Stop_Pledge_Charges custom permission.
    String uniq = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
    User u = new User(
      ProfileId = UserInfo.getProfileId(),
      Username = 'no-stop-perm-' + uniq + '@example.com.test',
      Email = 'no-stop-perm@example.com',
      LastName = 'NoStopPermission',
      Alias = 'nostop',
      TimeZoneSidKey = 'Asia/Jerusalem',
      LocaleSidKey = 'iw_IL',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US'
    );
    System.runAs(u) {
      Opportunity upd = new Opportunity(Id = o.Id, StageName = 'Stopped', Stop_Reason__c = 'Donor_Request');
      assertFails(Database.update(upd, false), 'אין לך הרשאה לעצור/לחדש חיובים');
    }
  }

  @IsTest
  static void cancelledCannotBeReopened() {
    Opportunity o = activePledge();
    o.StageName = 'Cancelled';
    insert o;
    assertFails(Database.update(new Opportunity(Id = o.Id, StageName = 'Active'), false), 'הוראה שבוטלה אינה ניתנת לשינוי סטטוס');
  }

  @IsTest
  static void pledgeTypeIsLocked() {
    // D34: the Type value is what makes a record a pledge; it can't be switched on or off by hand
    Opportunity o = activePledge();
    insert o;
    assertFails(Database.update(new Opportunity(Id = o.Id, Type = 'New Business'), false), 'לא ניתן לשנות את סוג ההזדמנות');
    Opportunity other = new Opportunity(Type = 'New Business', Name = 'Regular deal', StageName = 'Prospecting', CloseDate = Date.today());
    insert other;
    assertFails(Database.update(new Opportunity(Id = other.Id, Type = MicroPledges.TYPE), false), 'לא ניתן לשנות את סוג ההזדמנות');
  }
}
