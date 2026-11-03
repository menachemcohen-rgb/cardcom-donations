trigger OpportunityTrigger on Opportunity(before update, after update) {
  // Record-type guarded inside the handler: other Opportunities are never touched (Part C D24).
  if (Trigger.isBefore)
    OpportunityTriggerHandler.beforeUpdate(Trigger.new, Trigger.oldMap);
  else
    OpportunityTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
}
