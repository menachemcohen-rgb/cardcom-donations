/**
 * Israeli full rest-day holidays from the Hebrew calendar (CLAUDE.md B6.6, D6). Verified against an independent Hebrew-calendar
 * library for 5700–5900 (Rosh Hashana, Pesach, Shavuot). Chol HaMoed, Purim, Chanukah, Independence Day, Tisha B'Av are not rest days (Q3).
 */
public with sharing class HebrewHolidays {
  static final Date ANCHOR_RH = Date.newInstance(2026, 9, 12); // Rosh Hashana 5787
  static final Integer ANCHOR_YEAR = 5787;
  static Map<Integer, Set<Date>> cacheByGregYear = new Map<Integer, Set<Date>>();

  static Long elapsedDays(Integer y) {
    Long months = Math.floor((235L * y - 234) / 19.0).longValue();
    Long parts = 12084L + 13753L * months;
    Long day = months * 29 + (parts / 25920);
    if (Math.mod(3 * (day + 1), 7) < 3)
      day += 1;
    return day;
  }
  static Integer newYearDelay(Integer y) {
    Long ny0 = elapsedDays(y - 1), ny1 = elapsedDays(y), ny2 = elapsedDays(y + 1);
    if (ny2 - ny1 == 356)
      return 2;
    if (ny1 - ny0 == 382)
      return 1;
    return 0;
  }
  static Long rawNewYear(Integer y) {
    return elapsedDays(y) + newYearDelay(y);
  }

  public static Date roshHashana(Integer hebrewYear) {
    return ANCHOR_RH.addDays((rawNewYear(hebrewYear) - rawNewYear(ANCHOR_YEAR)).intValue());
  }

  /** Israeli full rest-day holidays falling in Gregorian year g. */
  public static Set<Date> restDays(Integer g) {
    if (cacheByGregYear.containsKey(g))
      return cacheByGregYear.get(g);
    Set<Date> s = new Set<Date>();
    Date rh = roshHashana(g + 3761); // autumn of g
    s.add(rh);
    s.add(rh.addDays(1)); // RH 1-2
    s.add(rh.addDays(9)); // Yom Kippur
    s.add(rh.addDays(14)); // Sukkot 1
    s.add(rh.addDays(21)); // Shemini Atzeret / Simchat Torah (Israel)
    Date pesach = rh.addDays(-163); // 15 Nisan of spring g
    s.add(pesach);
    s.add(pesach.addDays(6));
    s.add(pesach.addDays(50));
    cacheByGregYear.put(g, s);
    return s;
  }
}
