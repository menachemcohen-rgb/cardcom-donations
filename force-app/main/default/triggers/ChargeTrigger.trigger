trigger ChargeTrigger on Charge__c(after insert, after update) {
  // Roll-ups on the pledge when an attempt's outcome changes (B6.7). Pending attempts and Pending → Skipped (pledge stopped) don't change
  // any roll-up, so planning and stopping don't recalculate — and stopping doesn't re-update the pledge inside its own trigger.
  Set<Id> pledgeIds = new Set<Id>();
  for (Charge__c c : Trigger.new) {
    Charge__c old = Trigger.isUpdate ? Trigger.oldMap.get(c.Id) : null;
    Boolean changed;
    if (old == null) {
      changed = c.Status__c != 'Pending';
    } else {
      Boolean statusChanged = old.Status__c != c.Status__c && !(old.Status__c == 'Pending' && c.Status__c == 'Skipped');
      changed = statusChanged || old.Is_Final_Failure__c != c.Is_Final_Failure__c;
    }
    if (changed)
      pledgeIds.add(c.Pledge__c);
  }
  if (!pledgeIds.isEmpty())
    PledgeRollupService.recalc(pledgeIds);
}
