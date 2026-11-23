/**
 * Fills Email_Normalized__c, Phone_Normalized__c and Tax_Id_Hash__c (Part A 7.7ג) so donors can be matched by SOQL and by the
 * Matching Rule. Org decision D-1 (docs/org-discovery.md): when Donor_Tax_Id__c is blank, the hash falls back to the org's existing
 * Contact.Israeli_Id__c, read dynamically so the code also deploys to orgs without that field.
 */
public without sharing class ContactNormalization {
  @TestVisible
  static final String LEGACY_ID_FIELD = 'Israeli_Id__c';
  static Boolean legacyIdExists;

  @TestVisible
  static Boolean hasLegacyIdField() {
    if (legacyIdExists == null) {
      legacyIdExists = Schema.SObjectType.Contact.fields.getMap().containsKey(LEGACY_ID_FIELD.toLowerCase());
    }
    return legacyIdExists;
  }

  static final Integer PHONE_MAX = Contact.Phone_Normalized__c.getDescribe().getLength();

  public static void apply(List<Contact> contacts) {
    Boolean legacy = hasLegacyIdField();
    for (Contact c : contacts) {
      c.Email_Normalized__c = ContactMatcher.normEmail(c.Email);
      // N124: any number, from MobilePhone or (if blank) Phone.
      String ph = ContactMatcher.normPhone(c.MobilePhone);
      if (ph == null)
        ph = ContactMatcher.normPhone(c.Phone);
      c.Phone_Normalized__c = ph != null && ph.length() <= PHONE_MAX ? ph : null;
      String id = c.Donor_Tax_Id__c;
      if (String.isBlank(id) && legacy) {
        Object v = c.get(LEGACY_ID_FIELD);
        id = v == null ? null : String.valueOf(v);
      }
      c.Tax_Id_Hash__c = ContactMatcher.taxIdHash(id);
    }
  }
}
