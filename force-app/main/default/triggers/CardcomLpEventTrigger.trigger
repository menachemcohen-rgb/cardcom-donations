trigger CardcomLpEventTrigger on Cardcom_Lp_Event__e(after insert) {
  // Runs as the integration user through PlatformEventSubscriberConfig CardcomLpSubscriber (B6.3; see docs/README.md)
  Set<String> ids = new Set<String>();
  Map<String, String> hints = new Map<String, String>(); // D39: terminal named on the webhook URL
  for (Cardcom_Lp_Event__e e : Trigger.new) {
    if (String.isBlank(e.LowProfileId__c))
      continue;
    ids.add(e.LowProfileId__c);
    if (String.isNotBlank(e.Terminal__c))
      hints.put(e.LowProfileId__c.toLowerCase(), e.Terminal__c);
  }
  if (!ids.isEmpty())
    System.enqueueJob(new CardcomLpResultJob(new List<String>(ids), hints));
}
