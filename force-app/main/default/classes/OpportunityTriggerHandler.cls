/**
 * Pledge Opportunity trigger logic (B6.8, Part C C2 rule 3). Only records of record type Micro_Donation_Pledge are touched (D24).
 * - Stage → Stopped or Cancelled: Pending Charge__c of the pledge become Skipped (STOPPED).
 * - Change log for the manual stage transitions (Stop, Resume, Cancel) and for donor-link revocation (Link_Version__c raised).
 */
public without sharing class OpportunityTriggerHandler {
  public static void afterUpdate(List<Opportunity> news, Map<Id, Opportunity> olds) {
    Id rt = MicroPledges.recordTypeId();
    Set<Id> halted = new Set<Id>();
    List<Pledge_Change_Log__c> logs = new List<Pledge_Change_Log__c>();
    String source = isIntegrationUser() ? 'System' : 'Staff';
    for (Opportunity n : news) {
      if (n.RecordTypeId != rt)
        continue;
      Opportunity o = olds.get(n.Id);
      if (n.StageName != o.StageName) {
        if (n.StageName == MicroPledges.STAGE_STOPPED || n.StageName == MicroPledges.STAGE_CANCELLED)
          halted.add(n.Id);
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
