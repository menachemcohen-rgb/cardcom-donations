/**
 * Charge planning (B6.5 rules 1–3, Part C C2 rule 2, E15). For every Active pledge (record type Micro_Donation_Pledge) and every
 * logical date of the run, one Pending Charge__c (attempt 1) with the pledge's Charge_Amount__c snapshot (D16).
 * Token__c is never in the SOQL filter; a blank token is skipped in Apex (E15).
 * Up to SYNC_MAX pledges are planned in this transaction; above that a ChargePlannerBatch plans in chunks (spec-consistency N50).
 */
public with sharing class ChargePlanner {
  @TestVisible
  static Integer SYNC_MAX = 1000; // 1,000 pledges × up to 4 dates = 4,000 rows, well under 10,000 DML rows

  /** @return number of Charge__c attempts created now (0 when the work went to the batch). */
  public static Integer plan(Date runDate, String slot) {
    List<Date> dates = ChargeCalendar.logicalDatesFor(runDate);
    if (dates.isEmpty())
      return 0; // rest day: no records at all
    Id rt = MicroPledges.recordTypeId();
    Integer pledges = [
      SELECT COUNT()
      FROM Opportunity
      WHERE RecordTypeId = :rt AND StageName = :MicroPledges.STAGE_ACTIVE AND (End_Date__c = NULL OR End_Date__c >= :runDate)
    ];
    if (pledges > SYNC_MAX) {
      Database.executeBatch(new ChargePlannerBatch(runDate, slot), 200); // its finish() starts the dispatcher
      return 0;
    }
    Integer created = insertAttempts(buildAll(queryPledges(runDate, null), dates, slot, runDate));
    if (!ChargeRunLock.isChainActive())
      ChargeDispatcher.start(); // else picked up by the running chain
    return created;
  }

  /** Active pledges of the record type (C2 rule 2). No Token__c condition (E15). */
  public static List<Opportunity> queryPledges(Date runDate, Set<Id> onlyIds) {
    Id rt = MicroPledges.recordTypeId();
    String q =
      'SELECT Id, Donor_Contact__c, Charge_Amount__c, Frequency__c, Token__c FROM Opportunity' +
      ' WHERE RecordTypeId = :rt AND StageName = \'' +
      MicroPledges.STAGE_ACTIVE +
      '\'' +
      ' AND (End_Date__c = null OR End_Date__c >= :runDate)' +
      (onlyIds == null ? '' : ' AND Id IN :onlyIds');
    return Database.query(q);
  }

  /** One attempt per pledge × date; PM only for TwiceDaily; blank token skipped and logged (E15). */
  @TestVisible
  static List<Charge__c> buildAll(List<Opportunity> pledges, List<Date> dates, String slot, Date runDate) {
    List<Charge__c> out = new List<Charge__c>();
    Datetime now = ChargeCalendar.now();
    for (Opportunity p : pledges) {
      if (slot == 'PM' && p.Frequency__c != 'TwiceDaily')
        continue;
      if (String.isBlank(p.Token__c)) {
        System.debug(LoggingLevel.ERROR, 'Active pledge without token skipped: ' + p.Id); // VR_Active_Requires_Token should prevent it
        continue;
      }
      for (Date d : dates)
        out.add(buildAttempt(p, d, slot, 1, now, runDate)); // no skip on failures/expiry (D11)
    }
    return out;
  }

  /** Inserts with allOrNone=false: a duplicate Attempt_Key__c on re-run is silently skipped (B6.13 E8). */
  public static Integer insertAttempts(List<Charge__c> attempts) {
    Integer ok = 0;
    if (attempts.isEmpty())
      return ok;
    for (Database.SaveResult sr : Database.insert(attempts, false))
      if (sr.isSuccess())
        ok++;
    return ok;
  }

  /** PLG-{pledgeId15}-{yyyyMMdd}-{slot} (B2.3; spec-consistency N15: 15-character Id). */
  public static String extId(Id pledgeId, Date d, String slot) {
    return 'PLG-' +
      String.valueOf(pledgeId).left(15) +
      '-' +
      Datetime.newInstance(d, Time.newInstance(12, 0, 0, 0)).format('yyyyMMdd') +
      '-' +
      slot;
  }

  public static Charge__c buildAttempt(Opportunity p, Date d, String slot, Integer attempt, Datetime notBefore, Date runDate) {
    String ext = extId(p.Id, d, slot);
    return new Charge__c(
      Pledge__c = p.Id,
      Contact__c = p.Donor_Contact__c,
      Amount__c = p.Charge_Amount__c,
      Scheduled_Date__c = d,
      Slot__c = slot,
      ExternalUniqTranId__c = ext,
      Attempt_Number__c = attempt,
      Attempt_Key__c = ext + '-A' + attempt,
      Run_Date__c = runDate, // day the charge is sent (receipt month, B6.11)
      Status__c = 'Pending',
      Not_Before__c = notBefore
    );
  }
}
