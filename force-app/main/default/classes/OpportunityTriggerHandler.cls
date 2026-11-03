/**
 * Pledge Opportunity trigger logic (B6.8, Part C C2 rule 3). Only records of record type Micro_Donation_Pledge are touched (D24).
 * - Stage → Stopped or Cancelled: Pending Charge__c of the pledge become Skipped (STOPPED).
 * - Stopped → Active (resume, by the flow or a direct edit): Stop_Reason__c / Stop_Reason_Details__c are cleared (the Stop entry
 *   in Pledge_Change_Log__c and field history keep them), and Skipped/STOPPED charges for today or later give up their
 *   Attempt_Key__c, so the next planned run can create that slot again (N87). Nothing is re-sent: missed runs are not made up.
 * - Change log for the manual stage transitions (Stop, Resume, Cancel) and for donor-link revocation (Link_Version__c raised).
 */
public without sharing class OpportunityTriggerHandler {
  public static void beforeUpdate(List<Opportunity> news, Map<Id, Opportunity> olds) {
    Id rt = MicroPledges.recordTypeId();
    for (Opportunity n : news) {
      if (n.RecordTypeId == rt && isResume(olds.get(n.Id).StageName, n.StageName)) {
        n.Stop_Reason__c = null;
        n.Stop_Reason_Details__c = null;
      }
    }
  }

  public static void afterUpdate(List<Opportunity> news, Map<Id, Opportunity> olds) {
    Id rt = MicroPledges.recordTypeId();
    Set<Id> halted = new Set<Id>();
    Set<Id> resumed = new Set<Id>();
    List<Pledge_Change_Log__c> logs = new List<Pledge_Change_Log__c>();
    String source = isIntegrationUser() ? 'System' : 'Staff';
    for (Opportunity n : news) {
      if (n.RecordTypeId != rt)
        continue;
      Opportunity o = olds.get(n.Id);
      if (n.StageName != o.StageName) {
        if (n.StageName == MicroPledges.STAGE_STOPPED || n.StageName == MicroPledges.STAGE_CANCELLED)
          halted.add(n.Id);
        if (isResume(o.StageName, n.StageName))
          resumed.add(n.Id);
        String type = changeType(o.StageName, n.StageName);
        if (type != null)
          logs.add(log(n, type, o.StageName, stageValue(n), source));
      }
      if (n.Link_Version__c != null && o.Link_Version__c != null && n.Link_Version__c > o.Link_Version__c) {
        logs.add(log(n, 'Link_Revoke', String.valueOf(o.Link_Version__c.intValue()), String.valueOf(n.Link_Version__c.intValue()), source));
      }
    }
    if (!halted.isEmpty())
      skipPendingCharges(halted);
    if (!resumed.isEmpty())
      releaseStoppedKeys(resumed);
    if (!logs.isEmpty())
      insert logs;
  }

  /** B6.8: Pending attempts of a stopped/cancelled pledge are never sent. Charges already being sent are re-checked by ChargeQueueable. */
  static void skipPendingCharges(Set<Id> pledgeIds) {
    List<Charge__c> pending = [SELECT Id FROM Charge__c WHERE Pledge__c IN :pledgeIds AND Status__c = 'Pending'];
    Datetime now = Datetime.now();
    for (Charge__c c : pending) {
      c.Status__c = 'Skipped';
      c.Error_Code__c = 'STOPPED';
      c.Error_Message__c = 'חיובים הופסקו';
      c.Executed_At__c = now;
    }
    update pending;
  }

  static Boolean isResume(String oldStage, String newStage) {
    return oldStage == MicroPledges.STAGE_STOPPED && newStage == MicroPledges.STAGE_ACTIVE;
  }

  /**
   * N87: a charge skipped while stopped keeps its unique Attempt_Key__c, so re-planning the same slot would be silently dropped
   * (duplicate key). On resume, Skipped/STOPPED charges scheduled for today or later get a unique key suffix; they stay Skipped
   * for history. A STOPPED attempt was never sent to Cardcom, so its original key is free to use. Earlier days are left alone.
   */
  @TestVisible
  static void releaseStoppedKeys(Set<Id> pledgeIds) {
    Date today = ChargeCalendar.now().date(); // engine clock (pinned in tests)
    List<Charge__c> skipped = [
      SELECT Id, Attempt_Key__c
      FROM Charge__c
      WHERE Pledge__c IN :pledgeIds AND Status__c = 'Skipped' AND Error_Code__c = 'STOPPED' AND Scheduled_Date__c >= :today
    ];
    for (Charge__c c : skipped)
      c.Attempt_Key__c = String.join(new List<String>{ c.Attempt_Key__c, 'STOPPED', String.valueOf(c.Id) }, '-').left(110);
    if (!skipped.isEmpty())
      update skipped;
  }

  /** Change_Type__c for manual transitions; activation and verification results are system lifecycle (Stage History). */
  @TestVisible
  static String changeType(String oldStage, String newStage) {
    if (newStage == MicroPledges.STAGE_STOPPED)
      return 'Stop';
    if (newStage == MicroPledges.STAGE_CANCELLED)
      return 'Cancel';
    if (oldStage == MicroPledges.STAGE_STOPPED && newStage == MicroPledges.STAGE_ACTIVE)
      return 'Resume';
    return null;
  }

  static String stageValue(Opportunity n) {
    String v = n.StageName;
    if (n.StageName == MicroPledges.STAGE_STOPPED || n.StageName == MicroPledges.STAGE_CANCELLED) {
      String reason = n.Stop_Reason__c == null ? '' : n.Stop_Reason__c;
      if (String.isNotBlank(n.Stop_Reason_Details__c))
        reason += ': ' + n.Stop_Reason_Details__c;
      if (String.isNotBlank(reason))
        v += ' (' + reason + ')';
    }
    return v.left(255);
  }

  static Pledge_Change_Log__c log(Opportunity n, String type, String oldValue, String newValue, String source) {
    return new Pledge_Change_Log__c(
      Pledge__c = n.Id,
      Change_Type__c = type,
      Old_Value__c = oldValue == null ? null : oldValue.left(255),
      New_Value__c = newValue == null ? null : newValue.left(255),
      Source__c = source,
      Changed_By__c = UserInfo.getUserId(),
      Link_Version__c = n.Link_Version__c
    );
  }

  static Boolean isIntegrationUser() {
    String id = CardcomService.settings().Integration_User_Id__c;
    return String.isNotBlank(id) && id.left(15) == String.valueOf(UserInfo.getUserId()).left(15);
  }
}
