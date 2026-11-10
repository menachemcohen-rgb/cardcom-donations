/**
 * Scheduled charge run (B9, Part C E6): one job per kind — AM, PM, EveAM, EvePM — all on SUN-FRI crons;
 * ChargeCalendar.shouldRun decides whether today is a run day for this kind.
 */
public with sharing class DonationChargeScheduler implements Schedulable {
  final String kind;

  public DonationChargeScheduler(String kind) {
    if (!ChargeCalendar.KINDS.contains(kind))
      throw new IllegalArgumentException('Unknown schedule kind: ' + kind);
    this.kind = kind;
  }

  public void execute(SchedulableContext sc) {
    run(Date.today());
  }

  /** @return true if a planning run was started. */
  @TestVisible
  Boolean run(Date today) {
    Charge_Settings__c s = ChargeSettings.get();
    if (s.Charging_Enabled__c != true)
      return false; // emergency switch (B2.6)
    Boolean oneRun = s.Runs_Per_Day__c == 1;
    if ((kind == 'PM' || kind == 'EvePM') && oneRun)
      return false; // one run a day: the morning run plans every slot (D36)
    if (!ChargeCalendar.shouldRun(kind, today))
      return false;
    ChargePlanner.plan(today, ChargeCalendar.slotFor(kind), oneRun);
    return true;
  }
}
