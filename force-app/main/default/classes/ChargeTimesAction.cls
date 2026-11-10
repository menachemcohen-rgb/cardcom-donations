/**
 * "Charge times" screen (D36): ATO admins change the Shacharit/Mincha times (and the eve times) without Setup.
 * Saves them into the Charge_Settings__c Org Default, validates (ChargeSettings.validate) and asks the integration user to
 * re-schedule the jobs (DonationSetup.request('RESCHEDULE')). Gated by Manage_Charge_Schedule.
 */
public with sharing class ChargeTimesAction {
  public class Request {
    @InvocableVariable(label='Shacharit time (HH:mm)' required=true)
    public String shacharitTime;
    @InvocableVariable(label='Mincha time (HH:mm)' required=true)
    public String minchaTime;
    @InvocableVariable(label='Eve Shacharit time (HH:mm)' required=true)
    public String eveShacharitTime;
    @InvocableVariable(label='Eve Mincha time (HH:mm)' required=true)
    public String eveMinchaTime;
  }

  public class Result {
    @InvocableVariable
    public Boolean ok;
    @InvocableVariable
    public String message;
  }

  @InvocableMethod(label='Save charge times' description='Saves Shacharit/Mincha charge times and re-schedules the Donations jobs')
  public static List<Result> save(List<Request> requests) {
    List<Result> out = new List<Result>();
    for (Request q : requests)
      out.add(saveOne(q));
    return out;
  }

  static Result saveOne(Request q) {
    Result r = new Result();
    if (!FeatureManagement.checkPermission('Manage_Charge_Schedule')) {
      r.ok = false;
      r.message = 'אין הרשאה';
      return r;
    }
    Charge_Settings__c s = Charge_Settings__c.getOrgDefaults();
    if (s == null || s.Id == null) {
      s = ChargeSettings.defaults();
      s.SetupOwnerId = UserInfo.getOrganizationId();
    }
    s.AM_Time__c = trim(q.shacharitTime);
    s.PM_Time__c = trim(q.minchaTime);
    s.Eve_AM_Time__c = trim(q.eveShacharitTime);
    s.Eve_PM_Time__c = trim(q.eveMinchaTime);
    List<String> errs = ChargeSettings.validate(s);
    if (ChargeRunLock.isChainActive())
      errs.add('חיוב פעיל כרגע — נסו שוב בעוד כמה דקות');
    if (!errs.isEmpty()) {
      r.ok = false;
      r.message = String.join(errs, '\n');
      return r;
    }
    upsert s;
    DonationSetup.request('RESCHEDULE');
    r.ok = true;
    r.message = 'השעות נשמרו. ריצות החיוב יתוזמנו מחדש תוך דקה ותישלח הודעה לצוות. חיובים שכבר תוכננו אינם משתנים.';
    return r;
  }

  static String trim(String v) {
    return v == null ? null : v.trim();
  }
}
