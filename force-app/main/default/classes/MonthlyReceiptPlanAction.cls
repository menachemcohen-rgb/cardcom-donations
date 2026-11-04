/**
 * Admin action: plan and send the monthly receipts of a finished month for the given Contacts only (MonthlyReceiptPlanner(period,
 * contactIds)). The safe way to run the planner by hand, e.g. in the sandbox, where Anonymous Apex is blocked. Needs the custom
 * permission Manage_Charge_Schedule (Donations_Admin). The scheduled run is unchanged and still covers every donor.
 */
public without sharing class MonthlyReceiptPlanAction {
  @TestVisible
  static final Integer MAX_CONTACTS = 200;

  public class Request {
    @InvocableVariable(required=true label='Month (any day in it)')
    public Date periodMonth;
    @InvocableVariable(required=true label='Contact Ids')
    public List<Id> contactIds;
  }

  public class Result {
    @InvocableVariable
    public Boolean ok;
    @InvocableVariable
    public String message;
    @InvocableVariable
    public Id batchJobId;
  }

  @InvocableMethod(
    label='Plan monthly receipts for contacts'
    description='Plans and sends the receipts of a finished month for the given Contacts only'
  )
  public static List<Result> plan(List<Request> requests) {
    List<Result> out = new List<Result>();
    Boolean allowed = FeatureManagement.checkPermission('Manage_Charge_Schedule');
    Date thisMonth = Date.today().toStartOfMonth();
    for (Request q : requests) {
      Result res = new Result();
      res.ok = false;
      Set<Id> contacts = new Set<Id>();
      if (q.contactIds != null)
        for (Id i : q.contactIds)
          if (i != null && i.getSobjectType() == Contact.SObjectType)
            contacts.add(i);
      if (!allowed)
        res.message = 'אין הרשאה';
      else if (q.periodMonth == null || q.periodMonth.toStartOfMonth() >= thisMonth)
        res.message = 'ניתן להפיק קבלות רק לחודש שהסתיים';
      else if (contacts.isEmpty())
        res.message = 'יש לבחור לפחות איש קשר אחד';
      else if (contacts.size() > MAX_CONTACTS)
        res.message = 'ניתן לבחור עד ' + MAX_CONTACTS + ' אנשי קשר';
      else {
        res.batchJobId = Database.executeBatch(new MonthlyReceiptPlanner(q.periodMonth.toStartOfMonth(), contacts), 200);
        res.ok = true;
        res.message = 'הקבלות בתכנון ויישלחו ל-Cardcom בעוד מספר דקות.';
      }
      out.add(res);
    }
    return out;
  }
}
