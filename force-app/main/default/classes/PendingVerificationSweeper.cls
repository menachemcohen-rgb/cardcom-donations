/**
 * Every 15 minutes (Part A 7.7ב, B5.3, B6.13 E3): re-checks pledges and card changes still waiting for Cardcom, through the same
 * idempotent CardcomLpResultJob as the webhook. Also re-runs activation for pledges that are verified and submitted but still
 * pending — the safety net for a submit and a webhook that arrive at the same moment (spec-consistency N38).
 */
public without sharing class PendingVerificationSweeper implements Schedulable {
  @TestVisible
  static Datetime nowOverride; // tests: records can't be back-dated by LastModifiedDate

  public void execute(SchedulableContext sc) {
    sweep();
  }

  @TestVisible
  static void sweep() {
    String pledgeType = MicroPledges.TYPE;
    Datetime cutoff = (nowOverride == null ? Datetime.now() : nowOverride).addMinutes(-10);
    List<String> lpIds = new List<String>();
    for (Opportunity p : [
      SELECT LowProfileId__c
      FROM Opportunity
      WHERE Type = :pledgeType AND StageName = :MicroPledges.STAGE_PENDING AND Lp_Processed__c = FALSE AND CreatedDate <= :cutoff
      ORDER BY CreatedDate
      LIMIT 50
    ])
      lpIds.add(p.LowProfileId__c);
    for (Card_Change_Request__c c : [
      SELECT LowProfileId__c
      FROM Card_Change_Request__c
      WHERE Status__c = 'Pending' AND CreatedDate <= :cutoff
      ORDER BY CreatedDate
      LIMIT 40
    ])
      lpIds.add(c.LowProfileId__c);
    if (!lpIds.isEmpty())
      System.enqueueJob(new CardcomLpResultJob(lpIds)); // same idempotent path as the webhook

    List<Id> stuck = new List<Id>();
    for (Opportunity p : [
      SELECT Id
      FROM Opportunity
      WHERE
        Type = :pledgeType
        AND StageName = :MicroPledges.STAGE_PENDING
        AND Lp_Processed__c = TRUE
        AND Donor_Submitted__c = TRUE
        AND LastModifiedDate <= :cutoff
      LIMIT 50
    ])
      stuck.add(p.Id);
    if (!stuck.isEmpty())
      System.enqueueJob(new PledgeActivationJob(stuck));

    CardChangeService.expireStale(); // CCR Pending > 30 min → Expired (Prompt 8)
  }

  public static void scheduleAll() {
    for (Integer m : new List<Integer>{ 0, 15, 30, 45 })
      System.schedule(DonationSetup.jobName('LP Sweeper :' + m), '0 ' + m + ' * * * ?', new PendingVerificationSweeper());
  }
}
