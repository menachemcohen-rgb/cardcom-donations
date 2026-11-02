// B9: schedules every Donations job from Charge_Settings__c. Run as the integration user (TZ Asia/Jerusalem).
// Re-run after later prompts deploy new job classes:  DonationSetup.unscheduleAll(); DonationSetup.scheduleAll();
DonationSetup.scheduleAll();
System.debug('Skipped (class not deployed yet): ' + DonationSetup.lastSkipped);
