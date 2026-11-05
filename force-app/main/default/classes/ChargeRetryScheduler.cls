/**
 * Hourly retry sweep at Charge_Settings__c.Retry_Minute__c on SUN-FRI (Part A 7.7א, Part C E7). Starts the chain when retries are
 * due, or when a first attempt has been stuck Pending for 30 minutes. Shabbat/holiday/after the eve cutoff: nothing.
 */
public with sharing class ChargeRetryScheduler implements Schedulable {
  public ChargeRetryScheduler() {
  }

  public void execute(SchedulableContext sc) {
    run(ChargeCalendar.now());
  }

  @TestVisible
  static Boolean run(Datetime now) {
    if (!ChargeCalendar.isRetryWindowOpen(now))
      return false; // Shabbat / holiday / Friday after cutoff
    if (ChargeRunLock.isChainActive())
      return false; // overlapping run guard
    String pledgeType = MicroPledges.TYPE;
    Datetime stuck = now.addMinutes(-30);
    Integer due = [
      SELECT COUNT()
      FROM Charge__c
      WHERE
        Status__c = 'Pending'
        AND Pledge__r.StageName = :MicroPledges.STAGE_ACTIVE
        AND Pledge__r.Type = :pledgeType
        AND ((Attempt_Number__c > 1
        AND Not_Before__c <= :now)
        OR (Attempt_Number__c = 1
        AND CreatedDate <= :stuck))
    ];
    if (due == 0)
      return false;
    ChargeDispatcher.start();
    return true;
  }
}
