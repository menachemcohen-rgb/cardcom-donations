@IsTest
private class HebrewHolidaysTest {
  static Set<Date> dates(List<String> isoDates) {
    Set<Date> s = new Set<Date>();
    for (String d : isoDates)
      s.add(Date.valueOf(d));
    return s;
  }

  @IsTest
  static void roshHashana5785To5790() {
    Assert.areEqual(Date.newInstance(2024, 10, 3), HebrewHolidays.roshHashana(5785));
    Assert.areEqual(Date.newInstance(2025, 9, 23), HebrewHolidays.roshHashana(5786));
    Assert.areEqual(Date.newInstance(2026, 9, 12), HebrewHolidays.roshHashana(5787));
    Assert.areEqual(Date.newInstance(2027, 10, 2), HebrewHolidays.roshHashana(5788));
    Assert.areEqual(Date.newInstance(2028, 9, 21), HebrewHolidays.roshHashana(5789));
    Assert.areEqual(Date.newInstance(2029, 9, 10), HebrewHolidays.roshHashana(5790));
  }

  @IsTest
  static void restDays2026() {
    Assert.areEqual(
      dates(
        new List<String>{ '2026-04-02', '2026-04-08', '2026-05-22', '2026-09-12', '2026-09-13', '2026-09-21', '2026-09-26', '2026-10-03' }
      ),
      HebrewHolidays.restDays(2026)
    );
  }

  @IsTest
  static void restDays2027() {
    Assert.areEqual(
      dates(
        new List<String>{ '2027-04-22', '2027-04-28', '2027-06-11', '2027-10-02', '2027-10-03', '2027-10-11', '2027-10-16', '2027-10-23' }
      ),
      HebrewHolidays.restDays(2027)
    );
  }

  @IsTest
  static void restDaysAreCached() {
    Set<Date> first = HebrewHolidays.restDays(2028);
    Assert.areEqual(8, first.size());
    Assert.areEqual(first, HebrewHolidays.restDays(2028), 'second call returns the same set');
    Assert.isTrue(first.contains(Date.newInstance(2028, 4, 11)), 'Pesach 2028');
  }
}
