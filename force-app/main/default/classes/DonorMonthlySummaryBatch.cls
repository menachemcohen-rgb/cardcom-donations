/**
 * Monthly summary email to donors (D37): one per pledge that had successful charges in the month, sent with the receipts run
 * (MonthlyReceiptScheduler, from Receipt_Day_Of_Month__c — the 2nd). Idempotent: a pledge whose Last_Summary_Month__c is already
 * the month is skipped, so the daily runs of the receipt window only send what is still missing. 50 pledges per execute.
 */
public without sharing class DonorMonthlySummaryBatch implements Database.Batchable<SObject> {
  final Date period;

  public DonorMonthlySummaryBatch(Date periodStart) {
    period = periodStart.toStartOfMonth();
  }

  /** Starts the batch if a pledge still waits for this month's summary. @return true if started. */
  public static Boolean startIfNeeded(Date periodStart) {
    Date p = periodStart.toStartOfMonth();
    if (Database.query(query(p) + ' LIMIT 1').isEmpty())
      return false;
    Database.executeBatch(new DonorMonthlySummaryBatch(p), 50);
    return true;
  }

  static String query(Date p) {
    return 'SELECT Id FROM Opportunity WHERE Type = \'' +
      String.escapeSingleQuotes(MicroPledges.TYPE) +
      '\' AND (Last_Summary_Month__c = NULL OR Last_Summary_Month__c < ' +
      String.valueOf(p) +
      ') AND Id IN (SELECT Pledge__c FROM Charge__c WHERE Status__c = \'Success\' AND Run_Date__c >= ' +
      String.valueOf(p) +
      ' AND Run_Date__c <= ' +
      String.valueOf(p.addMonths(1).addDays(-1)) +
      ')';
  }

  public Database.QueryLocator start(Database.BatchableContext bc) {
    return Database.getQueryLocator(query(period));
  }

  public void execute(Database.BatchableContext bc, List<Opportunity> scope) {
    DonorEmailService.sendMonthlySummaries(scope, period);
  }

  public void finish(Database.BatchableContext bc) {
  }
}
