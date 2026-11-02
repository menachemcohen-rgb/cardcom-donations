/** Invocable behind the "Retry_Receipt" action (B6.11.1): re-arms a Failed / Needs_Verification receipt and starts the chain. */
public without sharing class MonthlyReceiptRetryAction {
  public class Request {
    @InvocableVariable(required=true label='Receipt Id')
    public Id receiptId;
  }

  public class Result {
    @InvocableVariable
    public Boolean ok;
    @InvocableVariable
    public String message;
  }

  @InvocableMethod(label='Retry monthly receipt' description='Resets attempts and re-sends the receipt to Cardcom (same ExternalId)')
  public static List<Result> retry(List<Request> requests) {
    List<Id> receiptIds = new List<Id>();
    for (Request q : requests)
      receiptIds.add(q.receiptId);
    List<Result> out = new List<Result>();
    Map<Id, Monthly_Receipt__c> rs = new Map<Id, Monthly_Receipt__c>(
      [SELECT Id, Status__c, Period_Month__c FROM Monthly_Receipt__c WHERE Id IN :receiptIds]
    );
    List<Monthly_Receipt__c> rearm = new List<Monthly_Receipt__c>();
    Set<Date> periods = new Set<Date>();
    for (Id rid : receiptIds) {
      Result res = new Result();
      Monthly_Receipt__c r = rs.get(rid);
      if (r == null || (r.Status__c != 'Failed' && r.Status__c != 'Needs_Verification')) {
        res.ok = false;
        res.message = 'ניתן לשלוח שוב רק קבלה שנכשלה או שממתינה לבדיקה';
      } else {
        rearm.add(new Monthly_Receipt__c(Id = r.Id, Status__c = 'Failed', Attempt_Count__c = 0, Last_Attempt_At__c = null));
        periods.add(r.Period_Month__c);
        res.ok = true;
        res.message = 'הקבלה נשלחת שוב ל-Cardcom. הסטטוס יתעדכן בעוד מספר דקות.';
      }
      out.add(res);
    }
    if (!rearm.isEmpty()) {
      update rearm;
      for (Date p : periods)
        MonthlyReceiptQueueable.start(p);
    }
    return out;
  }
}
