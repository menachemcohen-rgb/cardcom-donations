/**
 * Charge calendar (Part A 7.6 + B6.6 + Part C E5/E10). Running user TZ must be Asia/Jerusalem, so Date.today() is the Israeli date.
 * Rest day = Shabbat or an Israeli holiday (automatic, plus Charge_Holiday__mdt overrides). Eve = working day followed by a rest day.
 */
public with sharing class ChargeCalendar {
  public static final Set<String> KINDS = new Set<String>{ 'AM', 'PM', 'EveAM', 'EvePM' };

  @TestVisible
  static Set<Date> holidaysOverride;
  @TestVisible
  static List<Charge_Holiday__mdt> manualOverridesForTest; // CMDT rows can't be inserted in tests
  @TestVisible
  static Date todayOverride; // pins the auto-detect window in tests

  /** B6.6: automatic holidays for last/this/next year, then manual overrides (Add_Rest_Day / Remove_Rest_Day). */
  public static Set<Date> holidays() {
    if (holidaysOverride != null)
      return holidaysOverride;
    Integer y = (todayOverride == null ? Date.today() : todayOverride).year();
    Set<Date> s = new Set<Date>();
    if (CardcomService.settings().Holiday_Auto_Detect__c) {
      s.addAll(HebrewHolidays.restDays(y - 1));
      s.addAll(HebrewHolidays.restDays(y));
      s.addAll(HebrewHolidays.restDays(y + 1));
    }
    List<Charge_Holiday__mdt> manual = manualOverridesForTest != null ? manualOverridesForTest : Charge_Holiday__mdt.getAll().values();
    for (Charge_Holiday__mdt h : manual) {
      if (h.Date__c == null)
        continue;
      if (h.Mode__c == 'Remove_Rest_Day')
        s.remove(h.Date__c);
      else
        s.add(h.Date__c);
    }
    return s;
  }

  public static Integer dow(Date d) {
    // 0=Sunday .. 6=Saturday
    return Math.mod(Date.newInstance(1900, 1, 7).daysBetween(d), 7); // 1900-01-07 was Sunday
  }

  public static Boolean isRestDay(Date d) {
    return dow(d) == 6 || holidays().contains(d);
  }

  /** Eve = working day followed by a rest day (Friday, Erev Chag). */
  public static Boolean isEve(Date d) {
    return !isRestDay(d) && isRestDay(d.addDays(1));
  }

  /** Logical dates charged by a run on `runDate`. Empty = no charge (rest day). */
  public static List<Date> logicalDatesFor(Date runDate) {
    List<Date> out = new List<Date>();
    if (isRestDay(runDate))
      return out;
    out.add(runDate);
    Date next = runDate.addDays(1);
    Integer guard = 0;
    while (isRestDay(next) && guard++ < 7) {
      // cover the whole rest-day streak (Shabbat, 1-2 day Chag, Chag+Shabbat)
      out.add(next);
      next = next.addDays(1);
    }
    return out;
  }

  /**
   * E5: whether a scheduler of this kind charges on date d. Rest day → never; eve → only EveAM/EvePM; other days → only AM/PM.
   * (Runs_Per_Day__c and Charging_Enabled__c are checked by DonationChargeScheduler.)
   */
  public static Boolean shouldRun(String kind, Date d) {
    if (!KINDS.contains(kind) || isRestDay(d))
      return false;
    Boolean eveKind = kind.startsWith('Eve');
    return isEve(d) ? eveKind : !eveKind;
  }

  /** E5: AM/EveAM → slot AM, PM/EvePM → slot PM. */
  public static String slotFor(String kind) {
    if (!KINDS.contains(kind))
      throw new IllegalArgumentException('Unknown schedule kind: ' + kind);
    return kind.endsWith('AM') ? 'AM' : 'PM';
  }

  public static Integer fridayCutoffHour() {
    Decimal h = ChargeSettings.get().Friday_Cutoff_Hour__c;
    return h == null ? 14 : h.intValue();
  }

  /** True if a charge/retry may be sent at `t` (Asia/Jerusalem). */
  public static Boolean isRetryWindowOpen(Datetime t) {
    Date d = t.date();
    if (isRestDay(d))
      return false; // Shabbat / Chag
    if (isEve(d) && t.hour() >= fridayCutoffHour())
      return false; // Friday / Erev Chag after cutoff
    return true;
  }

  /**
   * E5: if the retry window is open at t → t. Otherwise the first non-rest day strictly after t's date, at AM_Time__c.
   */
  public static Datetime nextWorkingMorning(Datetime t) {
    if (isRetryWindowOpen(t))
      return t;
    Integer[] am = ChargeSettings.hm(ChargeSettings.get().AM_Time__c);
    Date d = t.date().addDays(1);
    Integer guard = 0;
    while (isRestDay(d) && guard++ < 14)
      d = d.addDays(1);
    return Datetime.newInstance(d, Time.newInstance(am[0], am[1], 0, 0));
  }
}
