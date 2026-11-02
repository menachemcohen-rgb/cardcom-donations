/**
 * Shared helpers for the pledge Opportunity (CLAUDE.md Part C C1/C2, D23/D24).
 * Every query, insert and trigger on Opportunity goes through recordTypeId() so other Opportunities are never touched.
 */
public without sharing class MicroPledges {
  public static final String RECORD_TYPE = 'Micro_Donation_Pledge';
  public static final String STAGE_PENDING = 'Pending_Verification';
  public static final String STAGE_ACTIVE = 'Active';
  public static final String STAGE_STOPPED = 'Stopped';
  public static final String STAGE_CANCELLED = 'Cancelled';
  public static final String STAGE_VERIFICATION_FAILED = 'Verification_Failed';
  public static final String DONOR_ROLE = 'Donor';
  static final String NAME_PREFIX = 'תרומה יומית';

  static Id rtId;

  /** Cached Id of record type Micro_Donation_Pledge (Part C rule 1). */
  public static Id recordTypeId() {
    if (rtId == null) {
      rtId = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName().get(RECORD_TYPE).getRecordTypeId();
    }
    return rtId;
  }

  public static Boolean isPledge(Opportunity o) {
    return o != null && o.RecordTypeId == recordTypeId();
  }

  /** A new pending pledge, keyed by LowProfileId (C1: Name, CloseDate, StageName, AccountId). */
  public static Opportunity newPending(String lowProfileId) {
    Opportunity o = new Opportunity(
      RecordTypeId = recordTypeId(),
      LowProfileId__c = lowProfileId,
      StageName = STAGE_PENDING,
      CloseDate = Date.today(),
      Name = initialName(lowProfileId)
    );
    String acc = CardcomService.settings().Default_Account_Id__c;
    if (String.isNotBlank(acc)) {
      o.AccountId = acc;
    }
    return o;
  }

  /** C1: name used on insert, before the auto number exists. */
  public static String initialName(String lowProfileId) {
    return (NAME_PREFIX + ' – ' + (lowProfileId == null ? '' : lowProfileId.left(8))).left(120);
  }

  /** C1: "תרומה יומית – {Last} {First} – {Pledge_Number__c}", left 120. */
  public static String fullName(String lastName, String firstName, String pledgeNumber) {
    String who = ((lastName == null ? '' : lastName) + ' ' + (firstName == null ? '' : firstName)).trim();
    return (NAME_PREFIX + ' – ' + who + ' – ' + (pledgeNumber == null ? '' : pledgeNumber)).left(120);
  }
}
