/**
 * Daily at Charge_Settings__c.Receipt_Time__c (B6.11, B9). Runs from Receipt_Day_Of_Month__c to the 10th, skipping rest days
 * (so a 1st on Shabbat issues on Sunday, E16 of B6.13). First run of the month plans the receipts; later runs retry Failed ones.
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
    Boolean planned = [SELECT COUNT() FROM Monthly_Receipt__c WHERE Period_Month__c = :prev] > 0;
    if (!planned) {
      Database.executeBatch(new MonthlyReceiptPlanner(prev), 200); // finish() starts the queueable
      return 'planned';
    }
    MonthlyReceiptQueueable.resetStale();
    MonthlyReceiptQueueable.start(prev); // daily retries of Failed
    return 'retried';
  }
}
