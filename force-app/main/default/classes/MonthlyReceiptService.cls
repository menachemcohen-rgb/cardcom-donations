/** Builds the CreateDocument body (B5.7, B6.11.1) and applies Cardcom's answer to a Monthly_Receipt__c. */
public without sharing class MonthlyReceiptService {
  static final String DEFAULT_DESCRIPTION = 'תרומות חודש {MONTH}';
  static final String CARD_LINE_DESCRIPTION = 'תרומה בכרטיס אשראי';

  public static final String MODE_CASH = 'Cash';
  public static final String MODE_CARD_LINES = 'CreditCardLines';
  public static final String MODE_DEAL_NUMBERS = 'DealNumbers';

  /** The receipt can't be built as configured (e.g. CreditCardLines without per-charge amounts). Final: no automatic retry. */
  public class ReceiptException extends Exception {
    public String code;
  }

  static ReceiptException fail(String code, String message) {
    ReceiptException e = new ReceiptException(message);
    e.code = code;
    return e;
  }

  /** One charge of the receipt, from Deal_Numbers__c. Old receipts hold plain deal numbers: sum/date/auth are then null. */
  public class ChargeLine {
    public Long deal;
    public Decimal sum;
    public Date tranDate;
    public String auth;
  }

  public static List<ChargeLine> chargeLines(String dealNumbersJson) {
    List<ChargeLine> out = new List<ChargeLine>();
    if (String.isBlank(dealNumbersJson))
      return out;
    for (Object o : (List<Object>) JSON.deserializeUntyped(dealNumbersJson)) {
      ChargeLine l = new ChargeLine();
      if (o instanceof Map<String, Object>) {
        Map<String, Object> m = (Map<String, Object>) o;
        l.deal = Long.valueOf(String.valueOf(m.get('d')));
        l.sum = m.get('sum') == null ? null : Decimal.valueOf(String.valueOf(m.get('sum')));
        l.tranDate = m.get('date') == null ? null : Date.valueOf(String.valueOf(m.get('date')));
        l.auth = m.get('auth') == null ? null : String.valueOf(m.get('auth'));
      } else {
        l.deal = Long.valueOf(String.valueOf(o));
      }
      out.add(l);
    }
    return out;
  }

  /** Receipt_Payment_Mode__c; blank → the older checkbox Receipt_Link_Deal_Numbers__c (true = DealNumbers, false = Cash). */
  public static String paymentMode(Cardcom_Setting__mdt s) {
    if (String.isNotBlank(s.Receipt_Payment_Mode__c))
      return s.Receipt_Payment_Mode__c;
    return s.Receipt_Link_Deal_Numbers__c == true ? MODE_DEAL_NUMBERS : MODE_CASH;
  }

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

  /**
   * Body per B5.7. Returns null if there is no e-mail to send to. Throws ReceiptException when the payment mode can't be honoured
   * (never falls back to Cash: Cardcom returns the first document for a known ExternalId, so a wrong first send can't be fixed).
   */
  public static Map<String, Object> buildRequest(Monthly_Receipt__c r, Donors donors) {
    Contact c = r.Contact__r;
    String email = String.isNotBlank(c.Email) ? c.Email : donors.email.get(r.Contact__c);
    if (String.isBlank(email))
      return null;
    String taxId = String.isNotBlank(c.Donor_Tax_Id__c) ? c.Donor_Tax_Id__c : donors.taxId.get(r.Contact__c);
    List<ChargeLine> charges = chargeLines(r.Deal_Numbers__c);
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
    // One product line = donor's monthly total; the payment block must equal it or Cardcom returns 6311 (U7).
    // Cash (default, D28): the only block that passed on test terminal 1001 (2.11.2026), but the receipt then shows cash.
    // CreditCardLines: CustomFields, one credit card line per charge — not yet verified with Cardcom (9996 on 2.11 with foreign
    // transactions; Q15). DealNumbers: on 1001 alone → 6311, only [0] linked (U8).
    String mode = paymentMode(s);
    if (mode == MODE_CARD_LINES)
      body.put('CustomFields', cardLines(r, charges));
    else if (mode == MODE_DEAL_NUMBERS && !charges.isEmpty()) {
      List<Object> deals = new List<Object>();
      for (ChargeLine l : charges)
        deals.add(new Map<String, Object>{ 'DealNumber' => l.deal });
      body.put('DealNumbers', deals);
    } else
      body.put('Cash', r.Total_Amount__c);
    return body;
  }

  /** One credit card payment line per charge; together they must equal Total_Amount__c exactly. */
  @TestVisible
  static List<Object> cardLines(Monthly_Receipt__c r, List<ChargeLine> charges) {
    if (charges.isEmpty())
      throw fail('NO_CHARGE_LINES', 'אין חיובים לקבלה');
    List<Object> lines = new List<Object>();
    Decimal total = 0;
    for (ChargeLine l : charges) {
      if (l.sum == null || l.tranDate == null)
        throw fail('NO_CHARGE_LINES', 'לקבלה אין פירוט סכום ותאריך לכל חיוב (תוכננה לפני השינוי)');
      Map<String, Object> line = new Map<String, Object>{
        'TransactionID' => l.deal,
        'TranDate' => Datetime.newInstance(l.tranDate, Time.newInstance(12, 0, 0, 0)).format('dd/MM/yyyy'),
        'Description' => CARD_LINE_DESCRIPTION,
        'Sum' => l.sum.setScale(2)
      };
      if (String.isNotBlank(l.auth))
        line.put('asmacta', l.auth);
      lines.add(line);
      total += l.sum;
    }
    if (total.setScale(2) != r.Total_Amount__c.setScale(2))
      throw fail('LINES_MISMATCH', ('סכום שורות האשראי ' + total.setScale(2) + ' שונה מסכום הקבלה ' + r.Total_Amount__c.setScale(2)));
    return lines;
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
