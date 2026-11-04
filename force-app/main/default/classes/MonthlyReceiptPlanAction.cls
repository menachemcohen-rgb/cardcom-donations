/**
 * Admin action: plan and send the monthly receipts of a finished month (MonthlyReceiptPlanner). Two uses:
 *  - given Contacts only (allDonors = false): the Contact button "הפקת קבלה חודשית", REST, safe sandbox runs (N96);
 *  - every donor (allDonors = true): the general button "הפקת קבלות חודשיות לכל התורמים". Receipts only cover Charge__c records,
 *    which exist only for daily-donation pledges (record type Micro_Donation_Pledge), so "every donor" = every micro-pledge donor.
 * Only donors with a charge of that month still waiting for a receipt are counted and planned; a donor whose receipt already left
 * Pending is skipped (N78; use "שליחה חוזרת" on a Failed receipt). Needs the custom permission Manage_Charge_Schedule.
 * The scheduled run (MonthlyReceiptScheduler) is unchanged.
 */
public without sharing class MonthlyReceiptPlanAction {
  @TestVisible
  static final Integer MAX_CONTACTS = 200;

  public class Request {
    @InvocableVariable(required=true label='Month (any day in it)')
    public Date periodMonth;
    @InvocableVariable(label='Contact Ids (ignored when All donors is true)')
    public List<Id> contactIds;
    @InvocableVariable(label='All donors')
    public Boolean allDonors;
  }

  public class Result {
    @InvocableVariable
    public Boolean ok;
    @InvocableVariable
    public String message;
    @InvocableVariable
    public Integer donorCount;
    @InvocableVariable
    public Id batchJobId;
  }

  @InvocableMethod(
    label='Plan monthly receipts'
    description='Plans and sends the receipts of a finished month, for the given Contacts or for every donor'
  )
  public static List<Result> plan(List<Request> requests) {
    List<Result> out = new List<Result>();
    Boolean allowed = FeatureManagement.checkPermission('Manage_Charge_Schedule');
    Date thisMonth = Date.today().toStartOfMonth();
    for (Request q : requests) {
      Result res = new Result();
      res.ok = false;
      res.donorCount = 0;
      Boolean all = q.allDonors == true;
      Set<Id> contacts = new Set<Id>();
      if (!all && q.contactIds != null)
        for (Id i : q.contactIds)
          if (i != null && i.getSobjectType() == Contact.SObjectType)
            contacts.add(i);
      if (!allowed)
        res.message = 'אין הרשאה';
      else if (q.periodMonth == null || q.periodMonth.toStartOfMonth() >= thisMonth)
        res.message = 'ניתן להפיק קבלות רק לחודש שהסתיים';
      else if (!all && contacts.isEmpty())
        res.message = 'יש לבחור לפחות איש קשר אחד';
      else if (!all && contacts.size() > MAX_CONTACTS)
        res.message = 'ניתן לבחור עד ' + MAX_CONTACTS + ' אנשי קשר';
      else {
        Date period = q.periodMonth.toStartOfMonth();
        Set<Id> only = all ? null : contacts;
        res.donorCount = donorsWaiting(period, only);
        String month = MonthlyReceiptService.monthNameHe(period.month()) + ' ' + period.year();
        if (res.donorCount == 0)
          res.message = 'אין חיובים של ' + month + ' שממתינים לקבלה' + (all ? '' : ' עבור איש הקשר שנבחר');
        else {
          res.batchJobId = Database.executeBatch(new MonthlyReceiptPlanner(period, only), 200);
          res.ok = true;
          res.message =
            'הקבלות של ' + month + ' עבור ' + res.donorCount + (res.donorCount == 1 ? ' תורם' : ' תורמים') +
            ' בהכנה ויישלחו ל-Cardcom בדקות הקרובות. המצב מתעדכן ברשומות הקבלה החודשית.';
        }
      }
      out.add(res);
    }
    return out;
  }

  /** Donors the planner would take: same filter as MonthlyReceiptPlanner / MonthlyReceiptScheduler.hasUnplannedCharges. */
  @TestVisible
  static Integer donorsWaiting(Date period, Set<Id> only) {
    Date toD = period.addMonths(1).addDays(-1);
    String soql =
      'SELECT COUNT_DISTINCT(Contact__c) n FROM Charge__c WHERE Status__c = \'Success\' AND Monthly_Receipt__c = NULL' +
      ' AND Needs_Reconciliation__c = FALSE AND Cardcom_Deal_Number__c != NULL AND Run_Date__c >= :period AND Run_Date__c <= :toD' +
      ' AND Contact__c != NULL AND Contact__c NOT IN (SELECT Contact__c FROM Monthly_Receipt__c WHERE Period_Month__c = :period' +
      ' AND Status__c != \'Pending\')' +
      (only == null ? '' : ' AND Contact__c IN :only');
    AggregateResult ar = (AggregateResult) Database.query(soql)[0];
    return (Integer) ar.get('n');
  }
}
