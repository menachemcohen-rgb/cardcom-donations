/**
 * Daily at Charge_Settings__c.Receipt_Time__c (B6.11, B9). Runs from Receipt_Day_Of_Month__c to the 10th, skipping rest days
 * (so a 1st on Shabbat issues on Sunday, E16 of B6.13). A run plans whenever last month still has charges waiting for a receipt
 * (not "whenever no receipt exists": one hand-made or partial receipt must not stop the whole month); otherwise it retries Failed ones.
 */
public without sharing class MonthlyReceiptScheduler implements Schedulable {
  @TestVisible
  static Date todayOverride;

  /** Scheduled by name (DonationSetup, N46). */
  public MonthlyReceiptScheduler() {
  }

  public void execute(SchedulableContext sc) {
    run(todayOverride != null ? todayOverride : Date.today());
  }

  /** @return 'planned', 'retried' or 'skipped' (for tests and logs). */
  @TestVisible
  static String run(Date today) {
    Date prev = today.toStartOfMonth().addMonths(-1);
    Decimal day = ChargeSettings.get().Receipt_Day_Of_Month__c;
    Integer targetDay = day == null ? 1 : day.intValue();
    if (today.day() > 10 || today.day() < targetDay || ChargeCalendar.isRestDay(today))
      return 'skipped'; // window: target day .. 10th
    MonthlyReceiptQueueable.resetStale();
    if (hasUnplannedCharges(prev)) {
      Database.executeBatch(new MonthlyReceiptPlanner(prev), 200); // finish() starts the queueable (Pending + Failed retries)
      return 'planned';
    }
    MonthlyReceiptQueueable.start(prev); // daily retries of Failed
    return 'retried';
  }

  /**
   * Same filter as MonthlyReceiptPlanner, minus donors whose receipt for the month already left Pending (the planner never adds
   * to those, N78) — otherwise a single late charge would re-run the planner every day.
   */
  @TestVisible
  static Boolean hasUnplannedCharges(Date period) {
    Date toD = period.addMonths(1).addDays(-1);
    return [
        SELECT Id
        FROM Charge__c
        WHERE
          Status__c = 'Success'
          AND Monthly_Receipt__c = NULL
          AND Needs_Reconciliation__c = FALSE
          AND Cardcom_Deal_Number__c != NULL
          AND Run_Date__c >= :period
          AND Run_Date__c <= :toD
          AND Contact__c != NULL
          AND Contact__c NOT IN (SELECT Contact__c FROM Monthly_Receipt__c WHERE Period_Month__c = :period AND Status__c != 'Pending')
        LIMIT 1
      ]
      .size() > 0;
  }
}
