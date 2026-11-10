/**
 * Charge planning (B6.5 rules 1–3, Part C C2 rule 2, E15; D36). Slots: AM = Shacharit, PM = Mincha.
 * A run plans (date, slot) pairs (runSlots): on a regular day only today's slot; on an eve the Shacharit run plans only today's
 * Shacharit and the Mincha run plans today's Mincha plus both slots of every rest day that follows (Shabbat/Chag go with Mincha);
 * with one run a day (Runs_Per_Day__c = 1) the morning run plans every slot of every logical date.
 * For every Active pledge (Type = Daily Donation Pledge) and every pair whose slot the pledge's frequency includes, one Pending
 * Charge__c (attempt 1) with the slot's amount snapshot (MicroPledges.amountFor, D16).
 * Token__c is never in the SOQL filter; a blank token is skipped in Apex (E15).
 * Up to SYNC_MAX pledges are planned in this transaction; above that a ChargePlannerBatch plans in chunks (spec-consistency N50).
 */
public with sharing class ChargePlanner {
  @TestVisible
  static Integer SYNC_MAX = 1000; // 1,000 pledges × up to 4 dates = 4,000 rows, well under 10,000 DML rows

  /** @return number of Charge__c attempts created now (0 when the work went to the batch). */
  public static Integer plan(Date runDate, String slot) {
    return plan(runDate, slot, false);
  }

  /** @param oneRun true when only one run a day is scheduled: it plans every slot (Runs_Per_Day__c = 1). */
  public static Integer plan(Date runDate, String slot, Boolean oneRun) {
    List<RunSlot> pairs = runSlots(runDate, slot, oneRun);
    if (pairs.isEmpty())
      return 0; // rest day: no records at all
    String pledgeType = MicroPledges.TYPE;
    Integer pledges = [
      SELECT COUNT()
      FROM Opportunity
      WHERE Type = :pledgeType AND StageName = :MicroPledges.STAGE_ACTIVE AND (End_Date__c = NULL OR End_Date__c >= :runDate)
    ];
    if (pledges > SYNC_MAX) {
      Database.executeBatch(new ChargePlannerBatch(runDate, slot, oneRun), 200); // its finish() starts the dispatcher
      return 0;
    }
    Integer created = insertAttempts(buildAll(queryPledges(runDate, null), pairs, runDate));
    if (!ChargeRunLock.isChainActive())
      ChargeDispatcher.start(); // else picked up by the running chain
    return created;
  }

  /** One logical charge slot of a run. */
  public class RunSlot {
    public Date d;
    public String slot;
    public RunSlot(Date d, String slot) {
      this.d = d;
      this.slot = slot;
    }
  }

  /** The (date, slot) pairs a run plans (D36). Empty on a rest day. */
  public static List<RunSlot> runSlots(Date runDate, String slot, Boolean oneRun) {
    List<RunSlot> out = new List<RunSlot>();
    List<Date> dates = ChargeCalendar.logicalDatesFor(runDate); // today + the rest days that follow
    if (dates.isEmpty())
      return out;
    for (Integer i = 0; i < dates.size(); i++) {
      Boolean today = i == 0;
      if (oneRun == true) {
        out.add(new RunSlot(dates[i], MicroPledges.SLOT_SHACHARIT));
        out.add(new RunSlot(dates[i], MicroPledges.SLOT_MINCHA));
      } else if (today) {
        out.add(new RunSlot(dates[i], slot));
      } else if (slot == MicroPledges.SLOT_MINCHA) {
        out.add(new RunSlot(dates[i], MicroPledges.SLOT_SHACHARIT)); // rest days go with the eve's Mincha run
        out.add(new RunSlot(dates[i], MicroPledges.SLOT_MINCHA));
      }
    }
    return out;
  }

  /** Active pledges of the record type (C2 rule 2). No Token__c condition (E15). */
  public static List<Opportunity> queryPledges(Date runDate, Set<Id> onlyIds) {
    String pledgeType = MicroPledges.TYPE;
    String q =
      'SELECT Id, Donor_Contact__c, Charge_Amount__c, Mincha_Amount__c, Frequency__c, Token__c FROM Opportunity' +
      ' WHERE Type = :pledgeType AND StageName = \'' +
      MicroPledges.STAGE_ACTIVE +
      '\'' +
      ' AND (End_Date__c = null OR End_Date__c >= :runDate)' +
      (onlyIds == null ? '' : ' AND Id IN :onlyIds');
    return Database.query(q);
  }

  /** One attempt per pledge × (date, slot) the pledge's frequency includes; blank token skipped and logged (E15). */
  @TestVisible
  public static List<Charge__c> buildAll(List<Opportunity> pledges, List<RunSlot> pairs, Date runDate) {
    List<Charge__c> out = new List<Charge__c>();
    Datetime now = ChargeCalendar.now();
    for (Opportunity p : pledges) {
      if (String.isBlank(p.Token__c)) {
        System.debug(LoggingLevel.ERROR, 'Active pledge without token skipped: ' + p.Id); // VR_Active_Requires_Token should prevent it
        continue;
      }
      for (RunSlot rs : pairs)
        if (MicroPledges.hasSlot(p.Frequency__c, rs.slot) && MicroPledges.amountFor(p, rs.slot) != null)
          out.add(buildAttempt(p, rs.d, rs.slot, 1, now, runDate)); // no skip on failures/expiry (D11)
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

  /** PLG-{pledgeId18}-{yyyyMMdd}-{slot} (spec-consistency N85: 18-character Id — 15-character Ids differ only by case). */
  public static String extId(Id pledgeId, Date d, String slot) {
    return 'PLG-' +
      String.valueOf(pledgeId) +
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
      Amount__c = MicroPledges.amountFor(p, slot),
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
