/**
 * Issues the receipts through Cardcom Documents/CreateDocument, 10 per job, chained (B6.11.1). Each batch is marked Processing in the
 * transaction before the callouts; Document.ExternalId = Receipt_Key__c makes every re-send safe (Cardcom returns the same document).
 */
public without sharing class MonthlyReceiptQueueable implements Queueable, Database.AllowsCallouts {
  @TestVisible
  static final Integer PER_JOB = 10;
  final Date period;
  final List<Id> ids;

  @TestVisible
  MonthlyReceiptQueueable(Date period, List<Id> ids) {
    this.period = period;
    this.ids = ids;
  }

  static Integer maxAttempts() {
    Decimal m = ChargeSettings.get().Receipt_Max_Attempts__c;
    return m == null ? 5 : m.intValue();
  }

  /** Marks the next batch Processing (own transaction) and enqueues it. Nothing left → daily failure alert. */
  public static void start(Date period) {
    Integer max = maxAttempts();
    Datetime retryBefore = Datetime.now().addHours(-12);
    List<Monthly_Receipt__c> next = [
      SELECT Id
      FROM Monthly_Receipt__c
      WHERE
        Period_Month__c = :period
        AND (Status__c = 'Pending'
        OR (Status__c = 'Failed'
        AND Attempt_Count__c < :max
        AND (Last_Attempt_At__c = NULL
        OR Last_Attempt_At__c < :retryBefore)))
      ORDER BY CreatedDate
      LIMIT :PER_JOB
    ];
    if (next.isEmpty()) {
      StaffAlertService.receiptFailures();
      return;
    }
    List<Id> ids = new List<Id>();
    for (Monthly_Receipt__c r : next) {
      r.Status__c = 'Processing';
      ids.add(r.Id);
    }
    update next;
    System.enqueueJob(new MonthlyReceiptQueueable(period, ids));
  }

  /** Processing > 1h (crash) → Failed (re-send is safe: same ExternalId returns the same document). */
  @TestVisible
  static Integer staleMinutes = 60;

  public static void resetStale() {
    Datetime before = Datetime.now().addMinutes(-staleMinutes);
    List<Monthly_Receipt__c> st = [SELECT Id FROM Monthly_Receipt__c WHERE Status__c = 'Processing' AND LastModifiedDate < :before];
    for (Monthly_Receipt__c r : st) {
      r.Status__c = 'Failed';
      r.Error_Code__c = 'STALE';
    }
    update st;
  }

  public void execute(QueueableContext ctx) {
    List<Monthly_Receipt__c> rs = [
      SELECT
        Id,
        Receipt_Key__c,
        Period_Month__c,
        Total_Amount__c,
        Charge_Count__c,
        Deal_Numbers__c,
        Attempt_Count__c,
        Contact__c,
        Contact__r.FirstName,
        Contact__r.LastName,
        Contact__r.Email,
        Contact__r.MobilePhone,
        Contact__r.Donor_Tax_Id__c
      FROM Monthly_Receipt__c
      WHERE Id IN :ids AND Status__c = 'Processing'
    ];
    Integer max = maxAttempts();
    Boolean configStop = false;
    MonthlyReceiptService.Donors donors = new MonthlyReceiptService.Donors(rs); // pledge fallbacks, one query
    for (Monthly_Receipt__c r : rs) {
      r.Attempt_Count__c = (r.Attempt_Count__c == null ? 0 : r.Attempt_Count__c) + 1;
      r.Last_Attempt_At__c = Datetime.now();
      if (configStop) {
        r.Status__c = 'Failed';
        r.Attempt_Count__c -= 1; // not attempted
        continue;
      }
      Map<String, Object> req = MonthlyReceiptService.buildRequest(r, donors);
      if (req == null) {
        r.Status__c = 'Failed';
        r.Error_Code__c = 'NO_EMAIL';
        r.Error_Message__c = 'אין כתובת אימייל לתורם';
        r.Attempt_Count__c = max;
        continue;
      }
      r.Raw_Request__c = JSON.serialize(req).left(32768); // credentials are formula placeholders, not secrets
      try {
        Map<String, Object> resp = CardcomService.createDocument(req);
        r.Raw_Response__c = CardcomService.redact(resp);
        MonthlyReceiptService.apply(r, resp, max);
      } catch (CardcomService.CardcomHttpException e) {
        r.Status__c = 'Failed';
        r.Error_Code__c = 'HTTP_' + e.status;
        r.Error_Message__c = e.getMessage().left(255);
        if (e.status == 401 || e.status == 400)
          configStop = true;
      } catch (Exception e) {
        // timeout etc. → retryable thanks to ExternalId
        r.Status__c = 'Failed';
        r.Error_Code__c = 'TIMEOUT';
        r.Error_Message__c = e.getMessage().left(255);
      }
    }
    update rs;
    if (configStop)
      StaffAlertService.configErrorOncePerDay(); // stop the chain for today
    else if (!Test.isRunningTest())
      start(period); // chain
  }
}
