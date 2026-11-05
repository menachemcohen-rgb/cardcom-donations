/** Test data for the donations project (B8). Pledges are Opportunities with Type = MicroPledges.TYPE (Part C, D34). */
@IsTest
public class TestDataFactory {
  public static final String HOST = 'www.example.org.il';
  public static final String RETURN_URL = 'https://' + HOST + '/cardcom-return/';

  /** In-memory Cardcom_Setting__mdt with the B2.6 defaults and test URLs; installed as CardcomService.settingsOverride. */
  public static Cardcom_Setting__mdt settings() {
    Cardcom_Setting__mdt s = new Cardcom_Setting__mdt(
      Terminal_Number__c = 1001,
      Api_Base__c = 'callout:Cardcom/api/v11',
      Currency_Iso__c = 1,
      Min_Amount__c = 1,
      Max_Amount__c = 50,
      Amount_Presets__c = '1,3,5,10',
      Send_Donor_Charge_Email__c = true,
      Donor_Portal_Base_Url__c = 'https://' + HOST + '/donor',
      Receipt_Document_Type__c = 'DonationReceipt',
      Receipt_Link_Deal_Numbers__c = false,
      Batch_Size__c = 30,
      Lp_JValidate_Type__c = 2,
      Is_Recurring_Terminal__c = false,
      Recon_Page_Size__c = 1000,
      Recon_Report_Unknown__c = true,
      Holiday_Auto_Detect__c = true,
      Optional_Verify_On_Open__c = false,
      Webhook_Url__c = 'https://example.my.salesforce-sites.com/cardcom/services/apexrest/cardcom/webhook',
      Allowed_Return_Hosts__c = HOST + ', other.example.org.il'
    );
    CardcomService.settingsOverride = s;
    return s;
  }

  static Database.DMLOptions allowDuplicates() {
    Database.DMLOptions o = new Database.DMLOptions();
    o.DuplicateRuleHeader.allowSave = true;
    return o;
  }

  public static Contact contact(String firstName, String lastName, String email, String mobile) {
    Contact c = new Contact(FirstName = firstName, LastName = lastName, Email = email, MobilePhone = mobile);
    Database.insert(c, allowDuplicates());
    return c;
  }

  /** A pending pledge (not inserted). */
  public static Opportunity pledge(String lowProfileId) {
    Opportunity o = MicroPledges.newPending(lowProfileId);
    o.Charge_Amount__c = 3;
    o.Frequency__c = 'OnceDaily';
    return o;
  }

  /** A pending pledge with the donor's form data (not inserted). */
  public static Opportunity submittedPledge(String lowProfileId, String email, String phone) {
    Opportunity o = pledge(lowProfileId);
    o.Donor_First_Name__c = 'ישראל';
    o.Donor_Last_Name__c = 'ישראלי';
    o.Donor_Email__c = email;
    o.Donor_Phone__c = phone;
    o.Donor_Submitted__c = true;
    o.Terms_Accepted_At__c = Datetime.now();
    return o;
  }

  /** Marks a pledge as verified by GetLpResult (not saved). */
  public static Opportunity withToken(Opportunity o) {
    o.Token__c = 'tok-' + o.LowProfileId__c;
    o.CardExpirationMMYY__c = '0928';
    o.Lp_Processed__c = true;
    o.Verified_At__c = Datetime.now();
    return o;
  }

  /** An Active pledge of the given Contact (inserted). */
  public static Opportunity activePledge(Contact c, String lowProfileId) {
    Opportunity o = withToken(submittedPledge(lowProfileId, c.Email, c.MobilePhone));
    o.StageName = MicroPledges.STAGE_ACTIVE;
    o.Donor_Contact__c = c.Id;
    o.Activated_At__c = Datetime.now();
    o.Start_Date__c = Date.today();
    insert o;
    return o;
  }

  /** A Pending charge attempt for a pledge (not inserted). */
  public static Charge__c charge(Opportunity p, Date scheduled, String slot) {
    String ext =
      'PLG-' +
      String.valueOf(p.Id) +
      '-' +
      Datetime.newInstance(scheduled, Time.newInstance(12, 0, 0, 0)).format('yyyyMMdd') +
      '-' +
      slot;
    return new Charge__c(
      Pledge__c = p.Id,
      Contact__c = p.Donor_Contact__c,
      Amount__c = p.Charge_Amount__c,
      Scheduled_Date__c = scheduled,
      Run_Date__c = scheduled,
      Slot__c = slot,
      Status__c = 'Pending',
      ExternalUniqTranId__c = ext,
      Attempt_Number__c = 1,
      Attempt_Key__c = ext + '-A1'
    );
  }

  /** A regular (non-pledge) Opportunity: Type is not the pledge value, so pledge logic must never touch it (D24, D34). */
  public static Opportunity otherOpportunity() {
    Opportunity o = new Opportunity(Name = 'Regular deal', Type = 'New Business', StageName = 'Prospecting', CloseDate = Date.today().addDays(30));
    insert o;
    return o;
  }

  /** A REST context with a JSON body. */
  public static void rest(String uri, Object body) {
    RestRequest req = new RestRequest();
    req.requestURI = uri;
    req.httpMethod = 'POST';
    req.requestBody = Blob.valueOf(body instanceof String ? (String) body : JSON.serialize(body));
    RestContext.request = req;
    RestContext.response = new RestResponse();
  }

  public static Map<String, Object> responseJson() {
    return (Map<String, Object>) JSON.deserializeUntyped(RestContext.response.responseBody.toString());
  }

  // ---- charge engine (Prompt 5) ----
  public static final Datetime WED_0800 = Datetime.newInstance(2026, 11, 4, 8, 0, 0); // regular Wednesday
  public static final Datetime FRI_0600 = Datetime.newInstance(2026, 11, 6, 6, 0, 0); // regular Friday (eve)

  /** Pins settings, the holiday calendar (2026, auto-detect, no manual overrides) and the engine clock. */
  public static void chargeEngine(Datetime now) {
    Cardcom_Setting__mdt s = settings();
    s.Failure_Notify_Emails__c = 'staff@example.com; finance@example.com';
    ChargeCalendar.todayOverride = Date.newInstance(2026, 11, 1);
    ChargeCalendar.manualOverridesForTest = new List<Charge_Holiday__mdt>();
    ChargeCalendar.nowOverride = now;
    ChargeSettings.overrideValue = ChargeSettings.defaults();
  }

  /** n Active pledges of one donor (inserted). */
  public static List<Opportunity> activePledges(Integer n, String frequency) {
    Contact c = contact('Avi', 'Cohen', 'avi' + Crypto.getRandomInteger() + '@example.com', '0521111111');
    List<Opportunity> ps = new List<Opportunity>();
    for (Integer i = 0; i < n; i++) {
      Opportunity o = withToken(submittedPledge('lp-' + frequency + '-' + i + '-' + Crypto.getRandomInteger(), c.Email, c.MobilePhone));
      o.StageName = MicroPledges.STAGE_ACTIVE;
      o.Frequency__c = frequency;
      o.Donor_Contact__c = c.Id;
      o.Activated_At__c = Datetime.now().addDays(-1);
      ps.add(o);
    }
    insert ps;
    return ps;
  }

  /** Pending attempt n of a logical charge (inserted). */
  public static Charge__c pendingCharge(Opportunity p, Date scheduled, String slot, Integer attempt, String verifyKey) {
    Charge__c c = charge(p, scheduled, slot);
    c.Attempt_Number__c = attempt;
    c.Attempt_Key__c = c.ExternalUniqTranId__c + '-A' + attempt;
    c.Verify_Attempt_Key__c = verifyKey;
    insert c;
    return c;
  }

  public static Map<String, Object> txSuccess(Long tranzactionId, String last4) {
    return new Map<String, Object>{
      'ResponseCode' => 0,
      'Description' => '',
      'TranzactionId' => tranzactionId,
      'ApprovalNumber' => '0654321',
      'Last4CardDigitsString' => last4,
      'Token' => 'tok-secret',
      'Amount' => 3
    };
  }

  public static Map<String, Object> txFailed(Integer code) {
    return new Map<String, Object>{ 'ResponseCode' => code, 'Description' => 'declined ' + code, 'TranzactionId' => 0 };
  }
}
