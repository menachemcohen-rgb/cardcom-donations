/** Builds the CreateDocument body (B5.7, B6.11.1) and applies Cardcom's answer to a Monthly_Receipt__c. */
public without sharing class MonthlyReceiptService {
  static final String DEFAULT_DESCRIPTION = 'תרומות חודש {MONTH}';

  /**
   * Fallback donor data from the donor's pledges (record-type guarded, newest activation first) for receipts whose Contact lacks
   * an email or Israeli ID. E16: Donor_Tax_Id__c is selected, never filtered — the first non-blank value is picked in Apex.
   */
  public class Donors {
    final Map<Id, String> email = new Map<Id, String>();
    final Map<Id, String> taxId = new Map<Id, String>();

    public Donors(List<Monthly_Receipt__c> rs) {
      Set<Id> need = new Set<Id>();
      for (Monthly_Receipt__c r : rs)
        if (String.isBlank(r.Contact__r.Email) || String.isBlank(r.Contact__r.Donor_Tax_Id__c))
          need.add(r.Contact__c);
      if (need.isEmpty())
        return;
      Id rt = MicroPledges.recordTypeId();
      for (Opportunity p : [
        SELECT Donor_Contact__c, Donor_Email__c, Donor_Tax_Id__c
        FROM Opportunity
        WHERE RecordTypeId = :rt AND Donor_Contact__c IN :need
        ORDER BY Activated_At__c DESC NULLS LAST
      ]) {
        if (!email.containsKey(p.Donor_Contact__c) && String.isNotBlank(p.Donor_Email__c))
          email.put(p.Donor_Contact__c, p.Donor_Email__c);
        if (!taxId.containsKey(p.Donor_Contact__c) && String.isNotBlank(p.Donor_Tax_Id__c))
          taxId.put(p.Donor_Contact__c, p.Donor_Tax_Id__c);
      }
    }
  }

  /** Single receipt (loads its own fallbacks). */
  public static Map<String, Object> buildRequest(Monthly_Receipt__c r) {
    return buildRequest(r, new Donors(new List<Monthly_Receipt__c>{ r }));
  }

  /** Body per B5.7. Returns null if there is no e-mail to send to. */
  public static Map<String, Object> buildRequest(Monthly_Receipt__c r, Donors donors) {
    Contact c = r.Contact__r;
    String email = String.isNotBlank(c.Email) ? c.Email : donors.email.get(r.Contact__c);
    if (String.isBlank(email))
      return null;
    String taxId = String.isNotBlank(c.Donor_Tax_Id__c) ? c.Donor_Tax_Id__c : donors.taxId.get(r.Contact__c);
    List<Object> deals = new List<Object>();
    if (String.isNotBlank(r.Deal_Numbers__c))
      for (Object d : (List<Object>) JSON.deserializeUntyped(r.Deal_Numbers__c))
        deals.add(new Map<String, Object>{ 'DealNumber' => Long.valueOf(String.valueOf(d)) });
    String monthHe = monthNameHe(r.Period_Month__c.month()) + ' ' + r.Period_Month__c.year();
    Cardcom_Setting__mdt s = CardcomService.settings();
    String description = String.isBlank(s.Receipt_Product_Description__c) ? DEFAULT_DESCRIPTION : s.Receipt_Product_Description__c;
    Map<String, Object> doc = new Map<String, Object>{
      'DocumentTypeToCreate' => String.isBlank(s.Receipt_Document_Type__c) ? 'DonationReceipt' : s.Receipt_Document_Type__c,
      'Name' => ((c.FirstName == null ? '' : c.FirstName) + ' ' + c.LastName).trim(),
      'Email' => email,
      'IsSendByEmail' => true,
      'Comments' => ('קבלה מרוכזת על תרומות ' + monthHe + ' (' + r.Charge_Count__c.intValue() + ' חיובים)').left(250),
      'ExternalId' => r.Receipt_Key__c,
      'ISOCoinID' => 1,
      'Languge' => 'he',
      'Products' => new List<Object>{
        new Map<String, Object>{
          'Description' => description.replace('{MONTH}', monthHe),
          'Quantity' => 1,
          'UnitCost' => r.Total_Amount__c,
          'TotalLineCost' => r.Total_Amount__c
        }
      }
    };
    if (String.isNotBlank(c.MobilePhone))
      doc.put('Mobile', c.MobilePhone);
    if (String.isNotBlank(taxId))
      doc.put('TaxId', taxId);
    r.Email_Sent_To__c = email;
    Map<String, Object> body = new Map<String, Object>{ 'Document' => doc }; // ApiName/ApiPassword added by CardcomService
    // One line = donor's monthly total; the payment block must equal it or Cardcom returns 6311 (U7).
    // Default: Cash = total (only block that passed on test terminal 1001, 2.11.2026).
    // Optional (flag on, verify in production first): DealNumbers instead (on 1001: alone → 6311; only [0] linked — U8).
    if (s.Receipt_Link_Deal_Numbers__c == true && !deals.isEmpty())
      body.put('DealNumbers', deals);
    else
      body.put('Cash', r.Total_Amount__c);
    return body;
  }

  public static void apply(Monthly_Receipt__c r, Map<String, Object> resp, Integer max) {
    Integer code = CardcomService.code(resp);
    Object num = resp.get('DocumentNumber');
    r.Error_Code__c = String.valueOf(code);
    r.Error_Message__c = resp.get('Description') == null ? null : String.valueOf(resp.get('Description')).left(255);
    if (code == 0 && num != null && Long.valueOf(String.valueOf(num)) > 0) {
      r.Status__c = 'Issued';
      r.Issued_At__c = Datetime.now();
      r.Cardcom_Document_Number__c = String.valueOf(num);
      r.Cardcom_Document_Type__c = resp.get('DocumentType') == null ? null : String.valueOf(resp.get('DocumentType'));
      r.Cardcom_Document_Url__c = resp.get('DocumentUrl') == null ? null : String.valueOf(resp.get('DocumentUrl')).left(255);
      r.Error_Code__c = null;
      r.Error_Message__c = null;
    } else if (code == 0) {
      r.Status__c = 'Needs_Verification';
    } else {
      r.Status__c = 'Failed';
      r.Attempt_Count__c = max; // validation error: no automatic retry
    }
  }

  public static String monthNameHe(Integer m) {
    return new List<String>{ 'ינואר', 'פברואר', 'מרץ', 'אפריל', 'מאי', 'יוני', 'יולי', 'אוגוסט', 'ספטמבר', 'אוקטובר', 'נובמבר', 'דצמבר' }[
      m - 1
    ];
  }
}
