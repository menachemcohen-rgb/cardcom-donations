/**
 * Pledge roll-ups and the consecutive-failure staff alert (B6.7, Part A 7.8, Part C D25/D9).
 * - Total_Collected__c = SUM(Amount__c) of Success attempts; standard Amount mirrors it (D25, N10).
 * - Successful_Charge_Count__c = COUNT of Success; Last_Successful_Charge_Date__c = MAX(Scheduled_Date__c) of Success (B6.7, N14).
 * - Consecutive_Failures__c = logical charges (ExternalUniqTranId__c), newest first by Scheduled_Date__c then Slot__c, whose last attempt
 *   failed finally (Is_Final_Failure__c), up to the first Success. Logical charges still Pending are not counted; Skipped and non-final
 *   failures (Config) are neutral: they neither count nor break the streak.
 * - When the streak reaches Max_Consecutive_Failures__c: one staff alert per streak (Failure_Alert_Sent_At__c). A Success re-arms it.
 * - Never changes StageName (D9). Only pledges of record type Micro_Donation_Pledge are touched (D24).
 */
public without sharing class PledgeRollupService {
  public static void recalc(Set<Id> pledgeIds) {
    if (pledgeIds == null || pledgeIds.isEmpty())
      return;
    Id rt = MicroPledges.recordTypeId();
    Map<Id, Opportunity> pledges = new Map<Id, Opportunity>(
      [
        SELECT
          Id,
          StageName,
          Total_Collected__c,
          Amount,
          Successful_Charge_Count__c,
          Last_Successful_Charge_Date__c,
          Consecutive_Failures__c,
          Failure_Alert_Sent_At__c
        FROM Opportunity
        WHERE Id IN :pledgeIds AND RecordTypeId = :rt
        FOR UPDATE
      ]
    );
    if (pledges.isEmpty())
      return;
    Set<Id> ids = pledges.keySet();

    Map<Id, Opportunity> changes = new Map<Id, Opportunity>();
    for (Opportunity p : pledges.values()) {
      changes.put(
        p.Id,
        new Opportunity(
          Id = p.Id,
          Total_Collected__c = 0,
          Amount = 0,
          Successful_Charge_Count__c = 0,
          Last_Successful_Charge_Date__c = null
        )
      );
    }
    for (AggregateResult ar : [
      SELECT Pledge__c pid, SUM(Amount__c) total, COUNT(Id) cnt, MAX(Scheduled_Date__c) lastDate
      FROM Charge__c
      WHERE Pledge__c IN :ids AND Status__c = 'Success'
      GROUP BY Pledge__c
    ]) {
      Opportunity o = changes.get((Id) ar.get('pid'));
      Decimal total = (Decimal) ar.get('total');
      o.Total_Collected__c = total;
      o.Amount = total;
      o.Successful_Charge_Count__c = (Integer) ar.get('cnt');
      o.Last_Successful_Charge_Date__c = (Date) ar.get('lastDate');
    }

    // Only charges since the last Success matter for the streak (plus that Success itself, which ends it).
    Date since = null;
    Boolean someWithoutSuccess = false;
    for (Opportunity o : changes.values()) {
      if (o.Last_Successful_Charge_Date__c == null)
        someWithoutSuccess = true;
      else if (since == null || o.Last_Successful_Charge_Date__c < since)
        since = o.Last_Successful_Charge_Date__c;
    }
    if (someWithoutSuccess)
      since = null;
    String q =
      'SELECT Pledge__c, ExternalUniqTranId__c, Status__c, Is_Final_Failure__c, Attempt_Number__c FROM Charge__c' +
      ' WHERE Pledge__c IN :ids' +
      (since == null ? '' : ' AND Scheduled_Date__c >= :since') +
      ' ORDER BY Pledge__c, Scheduled_Date__c DESC, Slot__c DESC, Attempt_Number__c DESC LIMIT 20000';
    Map<Id, List<String>> orderByPledge = new Map<Id, List<String>>();
    Map<String, String> outcomeByLogical = new Map<String, String>(); // ext → Success | FinalFailure | Neutral | Pending
    for (Charge__c c : (List<Charge__c>) Database.query(q)) {
      String ext = c.ExternalUniqTranId__c;
      if (!orderByPledge.containsKey(c.Pledge__c))
        orderByPledge.put(c.Pledge__c, new List<String>());
      if (!outcomeByLogical.containsKey(ext)) {
        orderByPledge.get(c.Pledge__c).add(ext);
        outcomeByLogical.put(ext, outcome(c)); // newest attempt first
      } else if (c.Status__c == 'Success') {
        outcomeByLogical.put(ext, 'Success'); // any successful attempt pays the logical charge
      } else if (c.Status__c == 'Pending' && outcomeByLogical.get(ext) != 'Success') {
        outcomeByLogical.put(ext, 'Pending');
      }
    }

    Integer maxFail = ChargeSettings.get().Max_Consecutive_Failures__c == null
      ? null
      : ChargeSettings.get().Max_Consecutive_Failures__c.intValue();
    Set<Id> toAlert = new Set<Id>();
    for (Opportunity p : pledges.values()) {
      Integer n = 0;
      List<String> logical = orderByPledge.containsKey(p.Id) ? orderByPledge.get(p.Id) : new List<String>();
      for (String ext : logical) {
        String o = outcomeByLogical.get(ext);
        if (o == 'Success')
          break;
        if (o == 'FinalFailure')
          n++;
      }
      Opportunity c = changes.get(p.Id);
      c.Consecutive_Failures__c = n;
      if (n == 0) {
        c.Failure_Alert_Sent_At__c = null; // streak ended → re-arm the alert
      } else if (maxFail != null && n >= maxFail && p.Failure_Alert_Sent_At__c == null && p.StageName == MicroPledges.STAGE_ACTIVE) {
        c.Failure_Alert_Sent_At__c = Datetime.now(); // once per streak; NO stage change (D9)
        toAlert.add(p.Id);
      }
    }
    // Partial success: a pledge that can't be saved (e.g. its amount is now outside the CMDT range) must not fail the charge commit.
    List<Opportunity> rows = changes.values();
    List<Database.SaveResult> srs = Database.update(rows, false);
    for (Integer i = 0; i < srs.size(); i++) {
      if (!srs[i].isSuccess()) {
        toAlert.remove(rows[i].Id);
        System.debug(LoggingLevel.ERROR, 'Roll-up update failed for ' + rows[i].Id + ': ' + srs[i].getErrors()[0].getMessage());
      }
    }
    if (!toAlert.isEmpty())
      StaffAlertService.failureStreak(toAlert); // synchronous (N5): no extra job in the chain
  }

  static String outcome(Charge__c c) {
    if (c.Status__c == 'Success')
      return 'Success';
    if (c.Status__c == 'Pending' || c.Status__c == 'Processing')
      return 'Pending';
    if (c.Status__c == 'Failed' && c.Is_Final_Failure__c)
      return 'FinalFailure';
    return 'Neutral'; // Skipped, Duplicate, Config failure (B6.7: neither counts nor breaks)
  }
}
