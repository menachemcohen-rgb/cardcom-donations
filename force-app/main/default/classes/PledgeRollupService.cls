/**
 * Pledge roll-ups and the consecutive-failure alert (B6.7, Part C D25). Prompt 6 implements it. Until then ChargeTrigger calls this
 * no-op: roll-up fields stay at their defaults and no alert is sent — nothing else depends on them yet.
 */
public without sharing class PledgeRollupService {
  public static void recalc(Set<Id> pledgeIds) {
    // TODO Prompt 6 (B6.7): Total_Collected__c (+ Amount, D25), Successful_Charge_Count__c, Last_Successful_Charge_Date__c,
    // Consecutive_Failures__c over logical charges, Failure_Alert_Sent_At__c once per streak. Never changes StageName (D9).
  }
}
