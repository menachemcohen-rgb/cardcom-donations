trigger DonationSetupCommandTrigger on Donation_Setup_Command__e(after insert) {
  // Runs as the integration user through PlatformEventSubscriberConfig DonationSetupSubscriber (N42):
  // System.schedule here makes the integration user the owner of every Donations job.
  DonationSetup.handleCommands(Trigger.new);
}
