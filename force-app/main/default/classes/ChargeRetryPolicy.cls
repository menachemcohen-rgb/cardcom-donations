public without sharing class ChargeRetryPolicy {
  /** Minutes to wait after attempt n failed (n = 1-based), from Charge_Settings__c.Retry_Delays_Minutes__c ("60,240") — N13. */
  public static Integer delayMinutes(Integer n) {
    List<String> d = ChargeSettings.get().Retry_Delays_Minutes__c.split(',');
    return Integer.valueOf(d[Math.min(n - 1, d.size() - 1)].trim());
  }
  /** First moment >= t inside the charge window (no Shabbat/holiday, no Friday/eve after cutoff). */
  public static Datetime nextWindow(Datetime t) {
    if (ChargeCalendar.isRetryWindowOpen(t))
      return t;
    return ChargeCalendar.nextWorkingMorning(t);
  }
}
