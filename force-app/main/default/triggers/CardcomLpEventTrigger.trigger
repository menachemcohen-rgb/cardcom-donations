trigger CardcomLpEventTrigger on Cardcom_Lp_Event__e(after insert) {
  // Runs as the integration user through PlatformEventSubscriberConfig CardcomLpSubscriber (B6.3; see docs/README.md)
  Set<String> ids = new Set<String>();
  for (Cardcom_Lp_Event__e e : Trigger.new) {
    if (String.isNotBlank(e.LowProfileId__c))
      ids.add(e.LowProfileId__c);
  }
  if (!ids.isEmpty())
    System.enqueueJob(new CardcomLpResultJob(new List<String>(ids)));
}
