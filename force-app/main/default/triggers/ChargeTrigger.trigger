trigger ChargeTrigger on Charge__c(after insert, after update) {
  // Roll-ups on the pledge whenever an attempt is created or its outcome changes (B6.7). PledgeRollupService is a no-op until Prompt 6.
  Set<Id> pledgeIds = new Set<Id>();
  for (Charge__c c : Trigger.new) {
    Charge__c old = Trigger.isUpdate ? Trigger.oldMap.get(c.Id) : null;
    if (old == null || old.Status__c != c.Status__c || old.Is_Final_Failure__c != c.Is_Final_Failure__c)
      pledgeIds.add(c.Pledge__c);
  }
  if (!pledgeIds.isEmpty())
    PledgeRollupService.recalc(pledgeIds);
}
