/** Queueable wrapper of PledgeActivationService (B6.2 step 4: webhook came before submit; sweeper safety net). */
public without sharing class PledgeActivationJob implements Queueable {
  final List<Id> pledgeIds;
  public PledgeActivationJob(Id pledgeId) {
    this(new List<Id>{ pledgeId });
  }
  public PledgeActivationJob(List<Id> pledgeIds) {
    this.pledgeIds = pledgeIds;
  }
  public void execute(QueueableContext ctx) {
    PledgeActivationService.activateAll(pledgeIds);
  }
}
