/**
 * Shared helpers for the pledge Opportunity (CLAUDE.md Part C C1/C2, D23/D24; D34).
 * A pledge is an Opportunity whose standard Type field is TYPE ('Daily Donation Pledge', label "הוראת תרומה יומית"). There is
 * no pledge record type (D34): every query, insert and trigger on Opportunity filters on Type so other Opportunities are never
 * touched.
 */
public without sharing class MicroPledges {
  /** Opportunity.Type value that marks a pledge (D34). */
  public static final String TYPE = 'Daily Donation Pledge';
  public static final String STAGE_PENDING = 'Pending_Verification';
  public static final String STAGE_ACTIVE = 'Active';
  public static final String STAGE_STOPPED = 'Stopped';
  public static final String STAGE_CANCELLED = 'Cancelled';
  public static final String STAGE_VERIFICATION_FAILED = 'Verification_Failed';
  public static final String DONOR_ROLE = 'Donor';

  /** Frequency__c values (D36): Shacharit = slot AM, Mincha = slot PM. API values kept from the first version. */
  public static final String FREQ_SHACHARIT_ONLY = 'OnceDaily';
  public static final String FREQ_BOTH = 'TwiceDaily';
  public static final String FREQ_MINCHA_ONLY = 'MinchaOnly';
  public static final Set<String> FREQUENCIES = new Set<String>{ FREQ_BOTH, FREQ_SHACHARIT_ONLY, FREQ_MINCHA_ONLY };
  public static final String SLOT_SHACHARIT = 'AM';
  public static final String SLOT_MINCHA = 'PM';

  /** Whether a pledge with this frequency is charged in the slot (AM = Shacharit, PM = Mincha). */
  public static Boolean hasSlot(String frequency, String slot) {
    if (slot == SLOT_SHACHARIT)
      return frequency == FREQ_BOTH || frequency == FREQ_SHACHARIT_ONLY;
    if (slot == SLOT_MINCHA)
      return frequency == FREQ_BOTH || frequency == FREQ_MINCHA_ONLY;
    return false;
  }

  /** Amount of one charge in the slot: Shacharit = Charge_Amount__c, Mincha = Mincha_Amount__c; each falls back to the other. */
  public static Decimal amountFor(Opportunity p, String slot) {
    Decimal shacharit = p.Charge_Amount__c, mincha = p.Mincha_Amount__c;
    if (slot == SLOT_MINCHA)
      return mincha != null ? mincha : shacharit;
    return shacharit != null ? shacharit : mincha;
  }

  /** Hebrew name of the frequency (emails, alerts). */
  public static String frequencyHe(String frequency) {
    if (frequency == FREQ_BOTH)
      return 'שחרית ומנחה';
    if (frequency == FREQ_SHACHARIT_ONLY)
      return 'רק שחרית';
    if (frequency == FREQ_MINCHA_ONLY)
      return 'רק מנחה';
    return frequency == null ? '' : frequency;
  }

  /** "שחרית 3.00 ₪ · מנחה 5.00 ₪" for the slots the pledge has (emails, alerts). */
  public static String amountsHe(Opportunity p) {
    List<String> parts = new List<String>();
    if (hasSlot(p.Frequency__c, SLOT_SHACHARIT))
      parts.add('שחרית ' + money(amountFor(p, SLOT_SHACHARIT)) + ' ₪');
    if (hasSlot(p.Frequency__c, SLOT_MINCHA))
      parts.add('מנחה ' + money(amountFor(p, SLOT_MINCHA)) + ' ₪');
    return String.join(parts, ' · ');
  }

  static String money(Decimal d) {
    return d == null ? '-' : d.setScale(2).toPlainString();
  }

  /** Hebrew name of the slot. */
  public static String slotHe(String slot) {
    return slot == SLOT_MINCHA ? 'מנחה' : slot == SLOT_SHACHARIT ? 'שחרית' : (slot == null ? '' : slot);
  }
  static final String NAME_PREFIX = 'תרומה יומית';

  public static Boolean isPledge(Opportunity o) {
    return o != null && o.Type == TYPE;
  }

  /** A new pending pledge, keyed by LowProfileId (C1: Name, CloseDate, StageName, AccountId). */
  public static Opportunity newPending(String lowProfileId) {
    Opportunity o = new Opportunity(
      Type = TYPE,
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
