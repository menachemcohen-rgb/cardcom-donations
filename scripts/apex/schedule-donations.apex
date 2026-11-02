// B9: schedules every Donations job from Charge_Settings__c. Any admin can run this: it publishes a Donation_Setup_Command__e and
// DonationSetupCommandTrigger, running as the integration user (subscriber config DonationSetupSubscriber), does the scheduling,
// so every job is owned by the integration user (spec-consistency N42). Staff get "זמני חיוב עודכנו" (or "...לא עודכנו" with the reason).
// Other commands: DonationSetup.request('RESCHEDULE');  DonationSetup.request('UNSCHEDULE_ALL');
DonationSetup.request('SCHEDULE_ALL');
