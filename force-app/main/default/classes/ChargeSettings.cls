/** Charge_Settings__c access and validation (CLAUDE.md B9.2, Part C E9). */
public with sharing class ChargeSettings {
  @TestVisible
  static Charge_Settings__c overrideValue;
  public static Charge_Settings__c get() {
    if (overrideValue != null)
      return overrideValue;
    Charge_Settings__c s = Charge_Settings__c.getOrgDefaults();
    if (s == null || s.Id == null)
      s = defaults();
    return s;
  }
  public static Charge_Settings__c defaults() {
    return new Charge_Settings__c(
      AM_Time__c = '08:00',
      PM_Time__c = '20:00',
      Eve_AM_Time__c = '06:00',
      Eve_PM_Time__c = '11:00',
      Runs_Per_Day__c = 2,
      Retry_Minute__c = 30,
      Friday_Cutoff_Hour__c = 14,
      Max_Retries__c = 3,
      Retry_Delays_Minutes__c = '60,240',
      Max_Consecutive_Failures__c = 3,
      Receipt_Day_Of_Month__c = 1,
      Receipt_Time__c = '07:00',
      Receipt_Max_Attempts__c = 5,
      Reconcile_Time__c = '02:30',
      Charging_Enabled__c = true
    );
  }
  /** "HH:mm" → [hour, minute]; throws on bad input. */
  public static Integer[] hm(String v) {
    if (v == null || !Pattern.matches('([01]\\d|2[0-3]):[0-5]\\d', v.trim()))
      throw new SettingsException('זמן לא תקין: ' + v);
    List<String> p = v.trim().split(':');
    return new List<Integer>{ Integer.valueOf(p[0]), Integer.valueOf(p[1]) };
  }
  public static List<String> validate(Charge_Settings__c s) {
    List<String> errs = new List<String>();
    for (
      String f : new List<String>{ 'AM_Time__c', 'PM_Time__c', 'Eve_AM_Time__c', 'Eve_PM_Time__c', 'Receipt_Time__c', 'Reconcile_Time__c' }
    ) {
      try {
        hm((String) s.get(f));
      } catch (SettingsException e) {
        errs.add(f + ': ' + e.getMessage());
      }
    }
    if (!errs.isEmpty())
      return errs;
    if (mins(s.AM_Time__c) >= mins(s.PM_Time__c))
      errs.add('AM_Time__c חייב להיות לפני PM_Time__c');
    if (mins(s.Eve_AM_Time__c) >= mins(s.Eve_PM_Time__c))
      errs.add('Eve_AM_Time__c חייב להיות לפני Eve_PM_Time__c');
    if (s.Friday_Cutoff_Hour__c == null || mins(s.Eve_PM_Time__c) >= s.Friday_Cutoff_Hour__c.intValue() * 60)
      errs.add('Eve_PM_Time__c חייב להיות לפני Friday_Cutoff_Hour__c');
    if (s.Runs_Per_Day__c != 1 && s.Runs_Per_Day__c != 2)
      errs.add('Runs_Per_Day__c חייב להיות 1 או 2');
    if (s.Retry_Minute__c == null || s.Retry_Minute__c < 0 || s.Retry_Minute__c > 59)
      errs.add('Retry_Minute__c 0–59');
    if (s.Max_Retries__c == null || s.Max_Retries__c < 1 || s.Max_Retries__c > 5)
      errs.add('Max_Retries__c 1–5');
    if (s.Receipt_Day_Of_Month__c == null || s.Receipt_Day_Of_Month__c < 1 || s.Receipt_Day_Of_Month__c > 28)
      errs.add('Receipt_Day_Of_Month__c 1–28');
    return errs;
  }
  static Integer mins(String v) {
    Integer[] x = hm(v);
    return x[0] * 60 + x[1];
  }
  /** Quartz cron for a daily time; days e.g. 'SUN-FRI' or '*'. */
  public static String cron(String hhmm, String days) {
    Integer[] x = hm(hhmm);
    return '0 ' + x[1] + ' ' + x[0] + (days == '*' ? ' * * ?' : ' ? * ' + days);
  }
  public class SettingsException extends Exception {
  }
}
