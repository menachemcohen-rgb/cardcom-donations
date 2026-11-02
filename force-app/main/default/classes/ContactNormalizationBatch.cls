/**
 * One-off backfill of the normalized fields on existing Contacts, run BEFORE activating Matching Rule Donor_Contact_Match (B10 step 12):
 * Database.executeBatch(new ContactNormalizationBatch(), 200);
 */
public class ContactNormalizationBatch implements Database.Batchable<SObject> {
  public Database.QueryLocator start(Database.BatchableContext bc) {
    return Database.getQueryLocator('SELECT Id FROM Contact');
  }
  public void execute(Database.BatchableContext bc, List<Contact> scope) {
    Database.DMLOptions o = new Database.DMLOptions();
    o.DuplicateRuleHeader.allowSave = true;
    o.OptAllOrNone = false;
    Database.update(scope, o); // trigger recomputes normalized fields
  }
  public void finish(Database.BatchableContext bc) {
  }
}
