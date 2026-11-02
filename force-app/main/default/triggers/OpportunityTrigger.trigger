trigger OpportunityTrigger on Opportunity(after update) {
  // Record-type guarded inside the handler: other Opportunities are never touched (Part C D24).
  OpportunityTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
}
