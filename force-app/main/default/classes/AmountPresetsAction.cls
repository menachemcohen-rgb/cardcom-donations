/**
 * "Amount buttons" screen (N123): admins edit the form's amount buttons (Cardcom_Setting__mdt.Default.Amount_Presets__c)
 * without Setup. One list serves the WordPress form (Shacharit and Mincha) and the donor page.
 * Rules: whole numbers, within Min_Amount__c..Max_Amount__c, no duplicates, 1–8 values.
 * The record is saved with a metadata deployment (Metadata.Operations.enqueueDeployment) that copies every field of the
 * current record and changes only Amount_Presets__c; it is enqueued from a Queueable (no mixed DML after ChargeTimesAction). Part of the "Apply charge schedule" screen; gated by Manage_Charge_Schedule.
 */
public with sharing class AmountPresetsAction {
  public static final Integer MAX_BUTTONS = 8;
  @TestVisible
  static Metadata.DeployContainer lastContainer;

  public class Request {
    @InvocableVariable(label='Amount buttons (comma separated)' required=true)
    public String presets;
  }

  public class Result {
    @InvocableVariable
    public Boolean ok;
    @InvocableVariable
    public String message;
  }

  @InvocableMethod(label='Save amount buttons' description='Validates and saves Cardcom_Setting__mdt.Default.Amount_Presets__c')
  public static List<Result> save(List<Request> requests) {
    List<Result> out = new List<Result>();
    for (Request q : requests)
      out.add(saveOne(q.presets));
    return out;
  }

  static Result saveOne(String raw) {
    Result r = new Result();
    if (!FeatureManagement.checkPermission('Manage_Charge_Schedule')) {
      r.ok = false;
      r.message = 'אין הרשאה';
      return r;
    }
    Cardcom_Setting__mdt s = CardcomService.settings();
    List<Integer> values = new List<Integer>();
    List<String> errs = validate(raw, s.Min_Amount__c, s.Max_Amount__c, values);
    if (!errs.isEmpty()) {
      r.ok = false;
      r.message = String.join(errs, '\n');
      return r;
    }
    String normalized = join(values);
    if (normalized == s.Amount_Presets__c) {
      r.ok = true;
      r.message = 'הכפתורים לא השתנו: ' + normalized;
      return r;
    }
    // The deployment runs in a Queueable: in the "Apply charge schedule" flow ChargeTimesAction has already updated
    // Charge_Settings__c, and a metadata deployment (setup DML) in the same transaction fails with MIXED_DML.
    Metadata.CustomMetadata md = record(s, normalized);
    Map<String, Object> values = new Map<String, Object>();
    for (Metadata.CustomMetadataValue v : md.values)
      values.put(v.field, v.value);
    Deployer job = new Deployer(normalized, md.label, values);
    lastContainer = job.container();
    System.enqueueJob(job);
    r.ok = true;
    r.message =
      'הכפתורים נשמרים: ' +
      normalized +
      '. השמירה נמשכת כדקה. הטופס באתר יציג אותם תוך 10 דקות, או מייד אחרי "רענון הגדרות מסיילספורס" בעמוד ההגדרות של התוסף.';
    return r;
  }

  /** Parses "1, 2,3" into values (sorted, as entered order is kept). @return error messages in Hebrew; empty = valid. */
  @TestVisible
  static List<String> validate(String raw, Decimal min, Decimal max, List<Integer> values) {
    List<String> errs = new List<String>();
    Set<Integer> seen = new Set<Integer>();
    Boolean dup = false;
    for (String x : (raw == null ? '' : raw).split('[,،;\\s]+')) {
      if (String.isBlank(x))
        continue;
      if (!Pattern.matches('\\d{1,6}', x.trim())) {
        errs.add('"' + x.trim() + '" אינו מספר שלם');
        continue;
      }
      Integer v = Integer.valueOf(x.trim());
      if ((min != null && v < min) || (max != null && v > max))
        errs.add(v + ' מחוץ לטווח ' + fmt(min) + '–' + fmt(max) + ' ₪');
      else if (seen.contains(v))
        dup = true;
      else {
        seen.add(v);
        values.add(v);
      }
    }
    if (dup)
      errs.add('יש סכום שמופיע יותר מפעם אחת');
    if (errs.isEmpty() && values.isEmpty())
      errs.add('נא להזין לפחות סכום אחד');
    if (values.size() > MAX_BUTTONS)
      errs.add('אפשר עד ' + MAX_BUTTONS + ' כפתורים');
    values.sort();
    return errs;
  }

  static String fmt(Decimal d) {
    return d == null ? '' : String.valueOf(d.stripTrailingZeros().toPlainString());
  }

  static String join(List<Integer> values) {
    List<String> s = new List<String>();
    for (Integer v : values)
      s.add(String.valueOf(v));
    return String.join(s, ',');
  }

  /** The Default record with all its current custom field values; only Amount_Presets__c changes. */
  @TestVisible
  static Metadata.CustomMetadata record(Cardcom_Setting__mdt s, String presets) {
    Metadata.CustomMetadata md = new Metadata.CustomMetadata();
    md.fullName = 'Cardcom_Setting.Default';
    md.label = String.isBlank(s.MasterLabel) ? 'Default' : s.MasterLabel;
    for (Schema.SObjectField f : Schema.SObjectType.Cardcom_Setting__mdt.fields.getMap().values()) {
      Schema.DescribeFieldResult d = f.getDescribe();
      String name = d.getName();
      if (!name.endsWith('__c') || d.isCalculated())
        continue;
      Metadata.CustomMetadataValue v = new Metadata.CustomMetadataValue();
      v.field = name;
      v.value = name == 'Amount_Presets__c' ? presets : s.get(name);
      md.values.add(v);
    }
    return md;
  }

  /** Builds and enqueues the metadata deployment outside the flow's transaction (primitives only, so it serializes). */
  public class Deployer implements Queueable {
    final String presets;
    final String label;
    final Map<String, Object> values;
    public Deployer(String presets, String label, Map<String, Object> values) {
      this.presets = presets;
      this.label = label;
      this.values = values;
    }
    public Metadata.DeployContainer container() {
      Metadata.CustomMetadata md = new Metadata.CustomMetadata();
      md.fullName = 'Cardcom_Setting.Default';
      md.label = label;
      for (String f : values.keySet()) {
        Metadata.CustomMetadataValue v = new Metadata.CustomMetadataValue();
        v.field = f;
        v.value = values.get(f);
        md.values.add(v);
      }
      Metadata.DeployContainer c = new Metadata.DeployContainer();
      c.addMetadata(md);
      return c;
    }
    public void execute(QueueableContext ctx) {
      if (!Test.isRunningTest())
        Metadata.Operations.enqueueDeployment(container(), new Callback(presets)); // metadata can't be deployed from a test
    }
  }

  public class Callback implements Metadata.DeployCallback {
    final String presets;
    public Callback(String presets) {
      this.presets = presets;
    }
    public void handleResult(Metadata.DeployResult result, Metadata.DeployCallbackContext ctx) {
      if (result != null && result.status == Metadata.DeployStatus.Succeeded)
        return;
      String err = result == null ? 'no result' : String.valueOf(result.status) + ' ' + result.errorMessage;
      if (result != null && result.details != null && result.details.componentFailures != null)
        for (Metadata.DeployMessage m : result.details.componentFailures)
          err += ' | ' + m.problem;
      StaffAlertService.amountPresetsFailed(presets, err.left(1000));
    }
  }
}
