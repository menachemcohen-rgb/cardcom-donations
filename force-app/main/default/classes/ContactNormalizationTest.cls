@IsTest
private class ContactNormalizationTest {
  @IsTest
  static void triggerFillsNormalizedFields() {
    Contact c = new Contact(
      LastName = 'Cohen',
      Email = ' Avi@Example.COM ',
      MobilePhone = '+972 52-123-4567',
      Donor_Tax_Id__c = '123456782'
    );
    insert c;
    c = [SELECT Email_Normalized__c, Phone_Normalized__c, Tax_Id_Hash__c FROM Contact WHERE Id = :c.Id];
    Assert.areEqual('avi@example.com', c.Email_Normalized__c);
    Assert.areEqual('0521234567', c.Phone_Normalized__c);
    Assert.areEqual(ContactMatcher.taxIdHash('123456782'), c.Tax_Id_Hash__c);
  }

  @IsTest
  static void phoneFallsBackToPhoneField() {
    Contact c = new Contact(LastName = 'Levi', Phone = '0547654321');
    insert c;
    Assert.areEqual('0547654321', [SELECT Phone_Normalized__c FROM Contact WHERE Id = :c.Id].Phone_Normalized__c);
  }

  @IsTest
  static void anyNumberIsNormalizedFromMobileOrPhone() {
    Contact a = new Contact(LastName = 'Abroad', MobilePhone = '+1 470 228 0495');
    Contact b = new Contact(LastName = 'Office', Phone = '03-1234567');
    insert new List<Contact>{ a, b };
    Map<Id, Contact> got = new Map<Id, Contact>([SELECT Phone_Normalized__c FROM Contact WHERE Id IN :new List<Id>{ a.Id, b.Id }]);
    Assert.areEqual('+14702280495', got.get(a.Id).Phone_Normalized__c);
    Assert.areEqual('031234567', got.get(b.Id).Phone_Normalized__c, 'Phone is used when MobilePhone is blank');
  }

  @IsTest
  static void legacyIsraeliIdIsUsedWhenDonorTaxIdIsBlank() {
    if (!ContactNormalization.hasLegacyIdField()) {
      return; // org without Contact.Israeli_Id__c (decision D-1 only applies where it exists)
    }
    Contact c = new Contact(LastName = 'Legacy');
    c.put(ContactNormalization.LEGACY_ID_FIELD, '123456782');
    insert c;
    Assert.areEqual(ContactMatcher.taxIdHash('123456782'), [SELECT Tax_Id_Hash__c FROM Contact WHERE Id = :c.Id].Tax_Id_Hash__c);
  }

  @IsTest
  static void batchRecomputesExistingContacts() {
    Contact c = new Contact(LastName = 'Batch', Email = 'Batch@Example.com');
    insert c;
    Test.startTest();
    Database.executeBatch(new ContactNormalizationBatch(), 200);
    Test.stopTest();
    Assert.areEqual('batch@example.com', [SELECT Email_Normalized__c FROM Contact WHERE Id = :c.Id].Email_Normalized__c);
  }
}
