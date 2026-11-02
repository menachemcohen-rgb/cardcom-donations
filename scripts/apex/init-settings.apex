// Creates the Org Default records of the hierarchy custom settings (B2.6, Part C E11).
// Custom-setting data isn't metadata, so the deploy can't create it. Safe to re-run: existing records are left as they are.
// Run as an admin after the Prompt 2 deploy:  sf apex run --target-org <alias> --file scripts/apex/init-settings.apex
Id orgId = UserInfo.getOrganizationId();

Charge_Settings__c cs = Charge_Settings__c.getOrgDefaults();
if (cs == null || cs.Id == null) {
    insert new Charge_Settings__c(
        SetupOwnerId = orgId,
        AM_Time__c = '08:00',
        PM_Time__c = '20:00',
        Eve_AM_Time__c = '06:00',
        Eve_PM_Time__c = '11:00',
        Runs_Per_Day__c = 2,
        Retry_Minute__c = 30,
        Friday_Cutoff_Hour__c = 14,
        Max_Retries__c = 3,
        Retry_Delays_Minutes__c = '60,240',
        Max_Consecutive_Failures__c = 3,
        Receipt_Day_Of_Month__c = 1,
        Receipt_Time__c = '07:00',
        Receipt_Max_Attempts__c = 5,
        Reconcile_Time__c = '02:30',
        Charging_Enabled__c = true
    );
    System.debug('Charge_Settings__c Org Default created');
} else {
    System.debug('Charge_Settings__c Org Default already exists — unchanged');
}

if (Alert_State__c.getOrgDefaults() == null || Alert_State__c.getOrgDefaults().Id == null) {
    insert new Alert_State__c(SetupOwnerId = orgId);
}
if (Charge_Run_Lock__c.getOrgDefaults() == null || Charge_Run_Lock__c.getOrgDefaults().Id == null) {
    insert new Charge_Run_Lock__c(SetupOwnerId = orgId);
}
