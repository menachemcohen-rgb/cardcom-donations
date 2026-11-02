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
  private static final String RT = 'Micro_Donation_Pledge';

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
      new Set<String>{ 'OnceDaily', 'TwiceDaily' },
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
      'Contact.Donor_Tax_Id__c' => describe(Contact.SObjectType, 'Donor_Tax_Id__c')
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
  static void recordTypeAndStagesExist() {
    Schema.RecordTypeInfo info = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName().get(RT);
    Assert.isNotNull(info, 'Record type ' + RT + ' is missing');
    Assert.isTrue(info.isActive(), 'Record type ' + RT + ' must be active');

    RecordType rt = [SELECT BusinessProcessId FROM RecordType WHERE SobjectType = 'Opportunity' AND DeveloperName = :RT];
    BusinessProcess bp = [SELECT Name, IsActive FROM BusinessProcess WHERE Id = :rt.BusinessProcessId];
    Assert.areEqual('Micro_Donation_Process', bp.Name, 'Sales process of ' + RT);
    Assert.isTrue(bp.IsActive, 'Sales process must be active');

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
}
