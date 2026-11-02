trigger ChargeSuccessTrigger on Charge_Success__e(after insert) {
  // Runs as the integration user through PlatformEventSubscriberConfig ChargeSuccessSubscriber (batch size 10, N67).
  List<Id> ids = new List<Id>();
  for (Charge_Success__e e : Trigger.new) {
    if (String.isBlank(e.Charge_Ids__c))
      continue;
    for (String s : e.Charge_Ids__c.split(','))
      if (String.isNotBlank(s))
        ids.add(Id.valueOf(s.trim()));
  }
  DonorChargeEmailService.send(ids);
}
