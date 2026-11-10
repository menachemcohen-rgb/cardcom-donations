/**
 * Describe-based smoke test for the Prompt 1 data model (CLAUDE.md B2.1, B2.2 via Part C C1/C2).
 * Runs after deploy (or inside `sf project deploy validate`) and fails if a field, record type,
 * stage, contact role or custom permission is missing or has the wrong shape.
 *
 * It also records the encryption choice (Part C E15/E16): Token__c and Donor_Tax_Id__c must be
 * encrypted and NOT filterable (Classic Encrypted Text, or Shield probabilistic). If this assertion
 * fails, the org uses a filterable encryption scheme and the decision must be revisited.
 */
@IsTest
private class MetadataSmokeTest {

  private class F {
    String name;
    Schema.DisplayType type;
    Integer length;
    Integer precision;
    Integer scale;
    F(String name, Schema.DisplayType type) {
      this.name = name;
      this.type = type;
    }
    F len(Integer l) {
      this.length = l;
      return this;
    }
    F num(Integer p, Integer s) {
      this.precision = p;
      this.scale = s;
      return this;
    }
  }

  private static Map<String, Schema.SObjectField> fieldsOf(Schema.SObjectType t) {
    return t.getDescribe().fields.getMap();
  }

  private static Schema.DescribeFieldResult describe(Schema.SObjectType t, String name) {
    Schema.SObjectField f = fieldsOf(t).get(name.toLowerCase());
    Assert.isNotNull(f, t + '.' + name + ' is missing');
    return f.getDescribe();
  }

  private static void assertFields(Schema.SObjectType t, List<F> expected) {
    for (F e : expected) {
      Schema.DescribeFieldResult d = describe(t, e.name);
      String loc = t + '.' + e.name;
      if (e.type == Schema.DisplayType.ENCRYPTEDSTRING) {
        Assert.isTrue(
          d.getType() == Schema.DisplayType.ENCRYPTEDSTRING || d.isEncrypted(),
          loc + ' must be encrypted (Classic or Shield), got ' + d.getType()
        );
      } else {
        Assert.areEqual(e.type, d.getType(), loc + ' type');
      }
      if (e.length != null) {
        Assert.areEqual(e.length, d.getLength(), loc + ' length');
      }
      if (e.precision != null) {
        Assert.areEqual(e.precision, d.getPrecision(), loc + ' precision');
        Assert.areEqual(e.scale, d.getScale(), loc + ' scale');
      }
    }
  }

  private static Set<String> picklistValues(Schema.SObjectType t, String name) {
    Set<String> out = new Set<String>();
    for (Schema.PicklistEntry p : describe(t, name).getPicklistValues()) {
      if (p.isActive()) {
        out.add(p.getValue());
      }
    }
    return out;
  }

  @IsTest
  static void contactFieldsExist() {
    assertFields(
      Contact.SObjectType,
      new List<F>{
        new F('Donor_Tax_Id__c', Schema.DisplayType.ENCRYPTEDSTRING).len(9),
        new F('Tax_Id_Hash__c', Schema.DisplayType.STRING).len(64),
        new F('Email_Normalized__c', Schema.DisplayType.STRING).len(255),
        new F('Phone_Normalized__c', Schema.DisplayType.STRING).len(10),
        new F('Needs_Review__c', Schema.DisplayType.BOOLEAN),
        new F('Review_Reason__c', Schema.DisplayType.TEXTAREA).len(2000),
        new F('Donor_Source__c', Schema.DisplayType.PICKLIST)
      }
    );
    for (String n : new List<String>{ 'Tax_Id_Hash__c', 'Email_Normalized__c', 'Phone_Normalized__c' }) {
      Schema.DescribeFieldResult d = describe(Contact.SObjectType, n);
      Assert.isTrue(d.isExternalId(), 'Contact.' + n + ' must be an External Id');
      Assert.isFalse(d.isUnique(), 'Contact.' + n + ' must not be unique');
    }
    Assert.isTrue(describe(Contact.SObjectType, 'Donor_Source__c').isRestrictedPicklist(), 'Donor_Source__c restricted');
    Assert.isTrue(picklistValues(Contact.SObjectType, 'Donor_Source__c').contains('WP_Micro'), 'Donor_Source__c WP_Micro');
  }

  @IsTest
  static void opportunityFieldsExist() {
    Schema.DisplayType S = Schema.DisplayType.STRING;
    Schema.DisplayType DT = Schema.DisplayType.DATETIME;
    Schema.DisplayType D = Schema.DisplayType.DATE;
    Schema.DisplayType N = Schema.DisplayType.DOUBLE;
    Schema.DisplayType B = Schema.DisplayType.BOOLEAN;
    Schema.DisplayType P = Schema.DisplayType.PICKLIST;
    Schema.DisplayType R = Schema.DisplayType.REFERENCE;
    Schema.DisplayType CUR = Schema.DisplayType.CURRENCY;
    assertFields(
      Opportunity.SObjectType,
      new List<F>{
        new F('Pledge_Number__c', S),
        new F('Donor_Contact__c', R),
        new F('Donor_First_Name__c', S).len(40),
        new F('Donor_Last_Name__c', S).len(80),
        new F('Donor_Email__c', Schema.DisplayType.EMAIL),
        new F('Donor_Phone__c', Schema.DisplayType.PHONE),
        new F('Donor_Tax_Id__c', Schema.DisplayType.ENCRYPTEDSTRING).len(9),
        new F('Donor_Submitted__c', B),
        new F('Terms_Accepted_At__c', DT),
        new F('Client_Ip__c', S).len(45),
        new F('Match_Method__c', P),
        new F('Frequency__c', P),
        new F('Charge_Amount__c', CUR).num(8, 2),
        new F('Mincha_Amount__c', CUR).num(8, 2),
        new F('LowProfileId__c', S).len(64),
        new F('Token__c', Schema.DisplayType.ENCRYPTEDSTRING).len(64),
        new F('CardExpirationMMYY__c', S).len(4),
        new F('Card_Expiry_Date__c', D),
        new F('Last4__c', S).len(4),
        new F('Token_Expiry_Date__c', D),
        new F('Lp_Check_Count__c', N).num(2, 0),
        new F('Lp_Processed__c', B),
        new F('Verified_At__c', DT),
        new F('Activated_At__c', DT),
        new F('Total_Collected__c', CUR).num(10, 2),
        new F('Successful_Charge_Count__c', N).num(8, 0),
        new F('Last_Successful_Charge_Date__c', D),
        new F('Consecutive_Failures__c', N).num(4, 0),
        new F('Failure_Alert_Sent_At__c', DT),
        new F('Stop_Reason__c', P),
        new F('Stop_Reason_Details__c', S).len(255),
        new F('Stopped_At__c', DT),
        new F('Stopped_By__c', R),
        new F('Resumed_At__c', DT),
        new F('Resumed_By__c', R),
        new F('Link_Version__c', N).num(4, 0),
        new F('Start_Date__c', D),
        new F('End_Date__c', D)
      }
    );

    Assert.isTrue(describe(Opportunity.SObjectType, 'Pledge_Number__c').isAutoNumber(), 'Pledge_Number__c auto number');
    Assert.isTrue(describe(Opportunity.SObjectType, 'Card_Expiry_Date__c').isCalculated(), 'Card_Expiry_Date__c formula');

    Schema.DescribeFieldResult lp = describe(Opportunity.SObjectType, 'LowProfileId__c');
    Assert.isTrue(lp.isUnique() && lp.isExternalId() && !lp.isCaseSensitive(), 'LowProfileId__c unique, ext id, case-insensitive');

    Schema.DescribeFieldResult donor = describe(Opportunity.SObjectType, 'Donor_Contact__c');
    Assert.areEqual(Contact.SObjectType, donor.getReferenceTo()[0], 'Donor_Contact__c -> Contact');
    Assert.areEqual('Donor_Contact__r', donor.getRelationshipName(), 'Donor_Contact__c relationship');
    Assert.isTrue(donor.isRestrictedDelete(), 'Donor_Contact__c delete = Restrict');
    Boolean childFound = false;
    for (Schema.ChildRelationship c : Contact.SObjectType.getDescribe().getChildRelationships()) {
      if (c.getField() == Opportunity.Donor_Contact__c) {
        childFound = true;
        Assert.areEqual('Donor_Pledges__r', c.getRelationshipName(), 'Contact child relationship name');
      }
    }
    Assert.isTrue(childFound, 'Contact.Donor_Pledges__r child relationship');

    Assert.areEqual(
      new Set<String>{ 'OnceDaily', 'TwiceDaily', 'MinchaOnly' },
      picklistValues(Opportunity.SObjectType, 'Frequency__c'),
      'Frequency__c values'
    );
    Assert.areEqual(
      new Set<String>{ 'Email', 'Phone', 'TaxId', 'DuplicateRule', 'New' },
      picklistValues(Opportunity.SObjectType, 'Match_Method__c'),
      'Match_Method__c values'
    );
    Assert.areEqual(
      new Set<String>{ 'Donor_Request', 'Card_Blocked', 'Financial_Review', 'Other' },
      picklistValues(Opportunity.SObjectType, 'Stop_Reason__c'),
      'Stop_Reason__c values'
    );
  }

  @IsTest
  static void encryptedFieldsAreNotFilterable() {
    Map<String, Schema.DescribeFieldResult> enc = new Map<String, Schema.DescribeFieldResult>{
      'Opportunity.Token__c' => describe(Opportunity.SObjectType, 'Token__c'),
      'Opportunity.Donor_Tax_Id__c' => describe(Opportunity.SObjectType, 'Donor_Tax_Id__c'),
      'Contact.Donor_Tax_Id__c' => describe(Contact.SObjectType, 'Donor_Tax_Id__c'),
      'Pledge_Card_History__c.Token__c' => describe(Pledge_Card_History__c.SObjectType, 'Token__c')
    };
    for (String k : enc.keySet()) {
      Schema.DescribeFieldResult d = enc.get(k);
      String scheme = d.getType() == Schema.DisplayType.ENCRYPTEDSTRING
        ? 'Classic Encrypted Text'
        : (d.isEncrypted() ? 'Shield Platform Encryption' : 'NOT ENCRYPTED');
      String report = k + ': encryption=' + scheme + ', isFilterable=' + d.isFilterable();
      System.debug(LoggingLevel.INFO, 'Encryption choice — ' + report);
      Assert.isFalse(d.isFilterable(), report + '. Part C E15/E16 assume encrypted fields are not filterable.');
    }
  }

  @IsTest
  static void pledgeTypeAndStagesExist() {
    // D34: a pledge is Opportunity.Type = MicroPledges.TYPE (no record type)
    Boolean typeFound = false;
    for (Schema.PicklistEntry e : Opportunity.Type.getDescribe().getPicklistValues())
      if (e.getValue() == MicroPledges.TYPE && e.isActive())
        typeFound = true;
    Assert.isTrue(typeFound, 'Opportunity.Type value ' + MicroPledges.TYPE + ' is missing (StandardValueSet OpportunityType)');

    // value => IsClosed, IsWon, probability (Part C C1)
    Map<String, List<Object>> expected = new Map<String, List<Object>>{
      'Pending_Verification' => new List<Object>{ false, false, 10 },
      'Active' => new List<Object>{ true, true, 100 },
      'Stopped' => new List<Object>{ true, true, 100 },
      'Cancelled' => new List<Object>{ true, false, 0 },
      'Verification_Failed' => new List<Object>{ true, false, 0 }
    };
    Map<String, OpportunityStage> stages = new Map<String, OpportunityStage>();
    for (OpportunityStage s : [
      SELECT ApiName, IsActive, IsClosed, IsWon, DefaultProbability
      FROM OpportunityStage
      WHERE ApiName IN :expected.keySet()
    ]) {
      stages.put(s.ApiName, s);
    }
    for (String v : expected.keySet()) {
      OpportunityStage s = stages.get(v);
      Assert.isNotNull(s, 'Stage ' + v + ' is missing');
      Assert.isTrue(s.IsActive, 'Stage ' + v + ' active');
      Assert.areEqual(expected.get(v)[0], s.IsClosed, 'Stage ' + v + ' IsClosed');
      Assert.areEqual(expected.get(v)[1], s.IsWon, 'Stage ' + v + ' IsWon');
      Assert.areEqual((Integer) expected.get(v)[2], s.DefaultProbability.intValue(), 'Stage ' + v + ' probability');
    }

    // E14: the org's existing stages must still be there
    Assert.areEqual(
      2,
      [SELECT COUNT() FROM OpportunityStage WHERE ApiName IN ('Closed Won', 'Closed Lost') AND IsActive = TRUE],
      'Existing stages were removed or deactivated (E14)'
    );
  }

  @IsTest
  static void donorContactRoleExists() {
    Assert.isTrue(picklistValues(OpportunityContactRole.SObjectType, 'Role').contains('Donor'), 'OpportunityContactRole.Role Donor');
  }

  @IsTest
  static void customPermissionsAndSettingsExist() {
    Set<String> names = new Set<String>();
    for (CustomPermission cp : [
      SELECT DeveloperName
      FROM CustomPermission
      WHERE DeveloperName IN ('Stop_Pledge_Charges', 'Manage_Charge_Schedule')
    ]) {
      names.add(cp.DeveloperName);
    }
    Assert.areEqual(new Set<String>{ 'Stop_Pledge_Charges', 'Manage_Charge_Schedule' }, names, 'Custom permissions');

    Cardcom_Setting__mdt s = Cardcom_Setting__mdt.getInstance('Default');
    Assert.isNotNull(s, 'Cardcom_Setting__mdt.Default is missing');
    Assert.isNotNull(s.Min_Amount__c, 'Min_Amount__c');
    Assert.isNotNull(s.Max_Amount__c, 'Max_Amount__c');
  }

  // ---------------------------------------------------------------- Prompt 2 (B2.3-B2.7, Part C)

  @IsTest
  static void chargeAndReceiptFieldsExist() {
    Schema.DisplayType S = Schema.DisplayType.STRING;
    Schema.DisplayType P = Schema.DisplayType.PICKLIST;
    Schema.DisplayType R = Schema.DisplayType.REFERENCE;
    Schema.DisplayType DT = Schema.DisplayType.DATETIME;
    Schema.DisplayType D = Schema.DisplayType.DATE;
    Schema.DisplayType N = Schema.DisplayType.DOUBLE;
    Schema.DisplayType B = Schema.DisplayType.BOOLEAN;
    Schema.DisplayType CUR = Schema.DisplayType.CURRENCY;
    Schema.DisplayType TA = Schema.DisplayType.TEXTAREA;
    assertFields(
      Charge__c.SObjectType,
      new List<F>{
        new F('Pledge__c', R),
        new F('Contact__c', R),
        new F('Monthly_Receipt__c', R),
        new F('Amount__c', CUR).num(8, 2),
        new F('Scheduled_Date__c', D),
        new F('Run_Date__c', D),
        new F('Slot__c', P),
        new F('Status__c', P),
        new F('Is_Final_Failure__c', B),
        new F('Executed_At__c', DT),
        new F('ExternalUniqTranId__c', S).len(100),
        new F('Attempt_Number__c', N).num(2, 0),
        new F('Attempt_Key__c', S).len(110),
        new F('Verify_Attempt_Key__c', S).len(110),
        new F('Not_Before__c', DT),
        new F('Cardcom_Tranzaction_Id__c', S).len(50),
        new F('Cardcom_Deal_Number__c', S).len(50),
        new F('Cardcom_Approval_Number__c', S).len(20),
        new F('Error_Code__c', S).len(20),
        new F('Error_Message__c', S).len(255),
        new F('Error_Category__c', P),
        new F('Needs_Reconciliation__c', B),
        new F('Donor_Email_Status__c', P),
        new F('Donor_Email_Sent_At__c', DT),
        new F('Raw_Response__c', TA).len(32768)
      }
    );
    Schema.DescribeFieldResult key = describe(Charge__c.SObjectType, 'Attempt_Key__c');
    Assert.isTrue(key.isUnique() && key.isExternalId(), 'Charge__c.Attempt_Key__c unique external id');
    Assert.isTrue(describe(Charge__c.SObjectType, 'ExternalUniqTranId__c').isExternalId(), 'ExternalUniqTranId__c indexed');
    Assert.areEqual(
      new Set<String>{ 'Pending', 'Processing', 'Success', 'Failed', 'Skipped' },
      picklistValues(Charge__c.SObjectType, 'Status__c'),
      'Charge__c.Status__c values'
    );
    Assert.areEqual(
      new Set<String>{ 'Retryable', 'Card_Declined', 'Card_Dead', 'Config', 'Duplicate', 'Unknown' },
      picklistValues(Charge__c.SObjectType, 'Error_Category__c'),
      'Charge__c.Error_Category__c values'
    );

    assertFields(
      Monthly_Receipt__c.SObjectType,
      new List<F>{
        new F('Contact__c', R),
        new F('Period_Month__c', D),
        new F('Receipt_Key__c', S).len(40),
        new F('Status__c', P),
        new F('Total_Amount__c', CUR).num(10, 2),
        new F('Charge_Count__c', N).num(6, 0),
        new F('Deal_Numbers__c', TA).len(131072),
        new F('Cardcom_Document_Number__c', S).len(30),
        new F('Cardcom_Document_Type__c', S).len(40),
        new F('Cardcom_Document_Url__c', Schema.DisplayType.URL),
        new F('Attempt_Count__c', N).num(2, 0),
        new F('Last_Attempt_At__c', DT),
        new F('Issued_At__c', DT),
        new F('Error_Code__c', S).len(20),
        new F('Error_Message__c', S).len(255),
        new F('Email_Sent_To__c', Schema.DisplayType.EMAIL),
        new F('Raw_Request__c', TA).len(32768),
        new F('Raw_Response__c', TA).len(32768)
      }
    );
    Assert.isTrue(describe(Monthly_Receipt__c.SObjectType, 'Receipt_Key__c').isUnique(), 'Receipt_Key__c unique');
  }

  @IsTest
  static void supportObjectFieldsExist() {
    Schema.DisplayType S = Schema.DisplayType.STRING;
    Schema.DisplayType P = Schema.DisplayType.PICKLIST;
    Schema.DisplayType R = Schema.DisplayType.REFERENCE;
    Schema.DisplayType DT = Schema.DisplayType.DATETIME;
    Schema.DisplayType N = Schema.DisplayType.DOUBLE;
    Schema.DisplayType CUR = Schema.DisplayType.CURRENCY;
    assertFields(
      Card_Change_Request__c.SObjectType,
      new List<F>{
        new F('Pledge__c', R),
        new F('LowProfileId__c', S).len(64),
        new F('Status__c', P),
        new F('Link_Version__c', N).num(4, 0),
        new F('Client_Ip__c', S).len(45),
        new F('Completed_At__c', DT),
        new F('Error_Message__c', S).len(255)
      }
    );
    Assert.isTrue(describe(Card_Change_Request__c.SObjectType, 'LowProfileId__c').isUnique(), 'CCR LowProfileId__c unique');
    assertFields(
      Pledge_Card_History__c.SObjectType,
      new List<F>{
        new F('Pledge__c', R),
        new F('Token__c', Schema.DisplayType.ENCRYPTEDSTRING).len(64),
        new F('CardExpirationMMYY__c', S).len(4),
        new F('Last4__c', S).len(4),
        new F('Replaced_At__c', DT),
        new F('Replaced_By_Request__c', R)
      }
    );
    assertFields(
      Pledge_Change_Log__c.SObjectType,
      new List<F>{
        new F('Pledge__c', R),
        new F('Change_Type__c', P),
        new F('Old_Value__c', S).len(255),
        new F('New_Value__c', S).len(255),
        new F('Source__c', P),
        new F('Changed_By__c', R),
        new F('Client_Ip__c', S).len(45),
        new F('Link_Version__c', N).num(4, 0)
      }
    );
    assertFields(
      Donor_Link_Use__c.SObjectType,
      new List<F>{
        new F('Pledge__c', R),
        new F('Action__c', P),
        new F('Link_Version__c', N).num(4, 0),
        new F('Used_At__c', DT),
        new F('Client_Ip__c', S).len(45),
        new F('Result__c', P)
      }
    );
    Assert.isTrue(picklistValues(Donor_Link_Use__c.SObjectType, 'Result__c').contains('Bad_Verify'), 'Result__c Bad_Verify (N3)');
    assertFields(
      Reconciliation_Issue__c.SObjectType,
      new List<F>{
        new F('Issue_Type__c', P),
        new F('Issue_Key__c', S).len(120),
        new F('Charge__c', R),
        new F('Business_Date__c', Schema.DisplayType.DATE),
        new F('ExternalUniqTranId__c', S).len(100),
        new F('Cardcom_Tranzaction_Id__c', S).len(50),
        new F('Cardcom_Amount__c', CUR),
        new F('SF_Amount__c', CUR),
        new F('Status__c', P),
        new F('Resolution_Notes__c', Schema.DisplayType.TEXTAREA).len(2000),
        new F('Detected_At__c', DT)
      }
    );
    assertFields(
      Cardcom_Webhook_Log__c.SObjectType,
      new List<F>{
        new F('LowProfileId__c', S).len(64),
        new F('Raw_Body__c', Schema.DisplayType.TEXTAREA).len(32768),
        new F('Content_Type__c', S).len(100),
        new F('Source_Ip__c', S).len(45),
        new F('Processed__c', Schema.DisplayType.BOOLEAN),
        new F('Received_At__c', DT)
      }
    );
  }

  @IsTest
  static void pledgeLookupsPointToOpportunityWithRestrictDelete() {
    Map<Schema.SObjectField, String> lookups = new Map<Schema.SObjectField, String>{
      Charge__c.Pledge__c => 'Charges__r',
      Card_Change_Request__c.Pledge__c => 'Card_Change_Requests__r',
      Pledge_Card_History__c.Pledge__c => 'Pledge_Card_Histories__r',
      Pledge_Change_Log__c.Pledge__c => 'Pledge_Change_Logs__r',
      Donor_Link_Use__c.Pledge__c => 'Donor_Link_Uses__r'
    };
    Map<Schema.SObjectField, String> children = new Map<Schema.SObjectField, String>();
    for (Schema.ChildRelationship c : Opportunity.SObjectType.getDescribe().getChildRelationships()) {
      if (lookups.containsKey(c.getField())) {
        children.put(c.getField(), c.getRelationshipName());
      }
    }
    for (Schema.SObjectField f : lookups.keySet()) {
      Schema.DescribeFieldResult d = f.getDescribe();
      Assert.areEqual(Opportunity.SObjectType, d.getReferenceTo()[0], f + ' must point to Opportunity (Part C C2)');
      Assert.isTrue(d.isRestrictedDelete(), f + ' delete = Restrict');
      Assert.areEqual(lookups.get(f), children.get(f), f + ' child relationship name');
    }
  }

  @IsTest
  static void platformEventsExist() {
    Assert.areEqual(
      Schema.DisplayType.STRING,
      describe(Cardcom_Lp_Event__e.SObjectType, 'LowProfileId__c').getType(),
      'Cardcom_Lp_Event__e.LowProfileId__c'
    );
    Assert.areEqual(
      Schema.DisplayType.TEXTAREA,
      describe(Charge_Success__e.SObjectType, 'Charge_Ids__c').getType(),
      'Charge_Success__e.Charge_Ids__c'
    );
  }

  @IsTest
  static void customMetadataRecordsExist() {
    Cardcom_Setting__mdt s = Cardcom_Setting__mdt.getInstance('Default');
    Assert.areEqual('callout:Cardcom/api/v11', s.Api_Base__c, 'Api_Base__c');
    Assert.areEqual(1, s.Currency_Iso__c.intValue(), 'Currency_Iso__c (ILS)');
    Assert.areEqual(30, s.Batch_Size__c.intValue(), 'Batch_Size__c');
    Assert.isFalse(s.Receipt_Link_Deal_Numbers__c, 'Receipt_Link_Deal_Numbers__c defaults to false (B5.10)');
    Assert.isNotNull(Donor_Link_Setting__mdt.getInstance('Default'), 'Donor_Link_Setting__mdt.Default');

    Map<String, Cardcom_Error_Code__mdt> codes = Cardcom_Error_Code__mdt.getAll();
    Assert.isTrue(codes.size() >= 17, 'Cardcom_Error_Code__mdt has ' + codes.size() + ' records, expected the 17 from B5.8');
    Assert.areEqual('Card_Dead', codes.get('C36').Category__c, 'C36 expired card');
    Assert.areEqual('Duplicate', codes.get('C608').Category__c, 'C608 duplicate');
    Assert.areEqual('Pending', codes.get('C5117').Category__c, 'C5117 pending');
    Assert.areEqual(60000010, codes.get('C60000010').Code__c.intValue(), 'C60000010 code');
  }

  @IsTest
  static void customSettingsExist() {
    for (
      String f : new List<String>{
        'AM_Time__c',
        'PM_Time__c',
        'Eve_AM_Time__c',
        'Eve_PM_Time__c',
        'Runs_Per_Day__c',
        'Retry_Minute__c',
        'Friday_Cutoff_Hour__c',
        'Max_Retries__c',
        'Retry_Delays_Minutes__c',
        'Max_Consecutive_Failures__c',
        'Receipt_Day_Of_Month__c',
        'Receipt_Time__c',
        'Receipt_Max_Attempts__c',
        'Reconcile_Time__c',
        'Charging_Enabled__c',
        'Schedule_Applied_At__c'
      }
    ) {
      describe(Charge_Settings__c.SObjectType, f);
    }
    describe(Charge_Run_Lock__c.SObjectType, 'Locked_Until__c');
    describe(Charge_Run_Lock__c.SObjectType, 'Run_Id__c');
    describe(Alert_State__c.SObjectType, 'Config_Error_Sent_On__c');
  }

  @IsTest
  static void permissionSetsAndCredentialsExist() {
    Set<String> names = new Set<String>();
    for (PermissionSet p : [
      SELECT Name
      FROM PermissionSet
      WHERE Name IN ('Donations_Integration', 'Donations_Admin', 'Donations_Staff', 'Donations_Site_Guest')
    ]) {
      names.add(p.Name);
    }
    Assert.areEqual(4, names.size(), 'Permission sets found: ' + names);
    Assert.areEqual(1, [SELECT COUNT() FROM NamedCredential WHERE DeveloperName = 'Cardcom'], 'Named Credential Cardcom');
  }

  @IsTest
  static void internalReadSetHasNoSensitiveFieldAndNoEdit() {
    List<PermissionSet> ps = [SELECT Id FROM PermissionSet WHERE Name = 'Donations_Internal_Read'];
    Assert.areEqual(1, ps.size(), 'Donations_Internal_Read deployed');
    Set<String> sensitive = new Set<String>{
      'Opportunity.Token__c',
      'Pledge_Card_History__c.Token__c',
      'Opportunity.Donor_Tax_Id__c',
      'Contact.Donor_Tax_Id__c',
      'Contact.Tax_Id_Hash__c'
    };
    Assert.areEqual(0, [SELECT COUNT() FROM FieldPermissions WHERE ParentId = :ps[0].Id AND Field IN :sensitive], 'no token / ID');
    Assert.areEqual(0, [SELECT COUNT() FROM FieldPermissions WHERE ParentId = :ps[0].Id AND PermissionsEdit = TRUE], 'read only');
    Assert.areEqual(
      0,
      [
        SELECT COUNT()
        FROM ObjectPermissions
        WHERE ParentId = :ps[0].Id AND (PermissionsCreate = TRUE OR PermissionsEdit = TRUE OR PermissionsDelete = TRUE)
      ],
      'no create/edit/delete'
    );
    Assert.isTrue([SELECT COUNT() FROM FieldPermissions WHERE ParentId = :ps[0].Id AND Field = 'Charge__c.Error_Code__c'] == 1);
  }
}
