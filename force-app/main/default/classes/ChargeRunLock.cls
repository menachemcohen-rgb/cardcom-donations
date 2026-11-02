/** Guard against overlapping charge chains (Part A 7.7א, Part C E12: no-arg acquire/release). Used by DonationSetup now, by the charge engine in Prompt 5. */
public without sharing class ChargeRunLock {
  static final Integer LOCK_MINUTES = 20;

  public static Boolean isChainActive() {
    Integer running = [
      SELECT COUNT()
      FROM AsyncApexJob
      WHERE ApexClass.Name = 'ChargeQueueable' AND Status IN ('Queued', 'Preparing', 'Processing', 'Holding')
    ];
    if (running > 0)
      return true;
    Charge_Run_Lock__c l = Charge_Run_Lock__c.getOrgDefaults();
    return l != null && l.Locked_Until__c != null && l.Locked_Until__c > Datetime.now();
  }

  public static void acquire() {
    Charge_Run_Lock__c l = Charge_Run_Lock__c.getOrgDefaults();
    if (l == null || l.Id == null)
      l = new Charge_Run_Lock__c(SetupOwnerId = UserInfo.getOrganizationId());
    l.Locked_Until__c = Datetime.now().addMinutes(LOCK_MINUTES);
    upsert l;
  }

  public static void release() {
    Charge_Run_Lock__c l = Charge_Run_Lock__c.getOrgDefaults();
    if (l != null && l.Id != null) {
      l.Locked_Until__c = null;
      update l;
    }
  }
}
