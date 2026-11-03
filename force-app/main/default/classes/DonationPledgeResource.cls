/**
 * POST /donations/pledge (B4, B6.2), adapted to the pledge Opportunity (Part C C1/C2):
 * the pledge is an Opportunity of record type Micro_Donation_Pledge, amount per charge is Charge_Amount__c, status is StageName.
 */
@RestResource(urlMapping='/donations/pledge')
global without sharing class DonationPledgeResource {
  /** Contract: B4. Rules: B6.2. */
  @HttpPost
  global static void submit() {
    RestResponse res = RestContext.response;
    res.addHeader('Content-Type', 'application/json; charset=utf-8');
    Map<String, Object> out;
    try {
      Map<String, Object> q = (Map<String, Object>) JSON.deserializeUntyped(RestContext.request.requestBody.toString());
      List<String> bad = validate(q);
      if (!bad.isEmpty()) {
        res.statusCode = 400;
        out = new Map<String, Object>{ 'error' => 'VALIDATION', 'fields' => bad };
      } else {
        String lp = (String) q.get('lowProfileId');
        Id rt = MicroPledges.recordTypeId();
        List<Opportunity> ex = [
          SELECT Id, StageName, Donor_Submitted__c, Lp_Processed__c, Pledge_Number__c
          FROM Opportunity
          WHERE LowProfileId__c = :lp AND RecordTypeId = :rt
          FOR UPDATE
        ];
        if (!ex.isEmpty() && ex[0].Donor_Submitted__c) {
          res.statusCode = 400;
          out = new Map<String, Object>{ 'error' => 'LP_ALREADY_USED' };
        } else {
          Opportunity p = ex.isEmpty() ? MicroPledges.newPending(lp) : new Opportunity(Id = ex[0].Id);
          p.Donor_First_Name__c = s(q, 'firstName');
          p.Donor_Last_Name__c = s(q, 'lastName');
          p.Donor_Email__c = s(q, 'email').toLowerCase();
          p.Donor_Phone__c = ContactMatcher.normPhone(s(q, 'phone'));
          p.Donor_Tax_Id__c = String.isBlank(s(q, 'taxId')) ? null : s(q, 'taxId').leftPad(9, '0');
          p.Charge_Amount__c = Decimal.valueOf(String.valueOf(q.get('amount'))).setScale(2);
          p.Frequency__c = s(q, 'frequency');
          p.Donor_Submitted__c = true;
          p.Terms_Accepted_At__c = Datetime.now();
          p.Client_Ip__c = s(q, 'clientIp') == null ? null : s(q, 'clientIp').left(45);
          if (ex.isEmpty()) {
            // Two concurrent submits of one LowProfileId both see no row; the Unique LowProfileId__c rejects the second insert.
            // Answer it like any replay instead of a 500, so one LowProfileId never yields two pledges (or two Contacts).
            if (!insertUnlessDuplicate(p)) {
              res.statusCode = 400;
              res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{ 'error' => 'LP_ALREADY_USED' }));
              return;
            }
            String num = [SELECT Pledge_Number__c FROM Opportunity WHERE Id = :p.Id AND RecordTypeId = :rt].Pledge_Number__c;
            update new Opportunity(Id = p.Id, Name = MicroPledges.fullName(p.Donor_Last_Name__c, p.Donor_First_Name__c, num));
          } else {
            p.Name = MicroPledges.fullName(p.Donor_Last_Name__c, p.Donor_First_Name__c, ex[0].Pledge_Number__c);
            update p;
          }
          if (!ex.isEmpty() && ex[0].Lp_Processed__c)
            System.enqueueJob(new PledgeActivationJob(p.Id)); // webhook came first
          res.statusCode = 200;
          out = new Map<String, Object>{
            'pledgeId' => p.Id,
            'status' => [SELECT StageName FROM Opportunity WHERE Id = :p.Id AND RecordTypeId = :rt]
            .StageName
          };
        }
      }
    } catch (Exception e) {
      System.debug(LoggingLevel.ERROR, 'pledge submit ' + e.getMessage());
      res.statusCode = 500;
      out = new Map<String, Object>{ 'error' => 'INTERNAL' };
    }
    res.responseBody = Blob.valueOf(JSON.serialize(out));
  }

  /** Inserts the new pledge. false = another request already inserted this LowProfileId (Unique LowProfileId__c). */
  @TestVisible
  static Boolean insertUnlessDuplicate(Opportunity p) {
    Database.SaveResult sr = Database.insert(p, false);
    if (sr.isSuccess())
      return true;
    if (sr.getErrors()[0].getStatusCode() == StatusCode.DUPLICATE_VALUE)
      return false;
    throw new CardcomService.CardcomException('Pledge insert failed: ' + sr.getErrors()[0].getMessage());
  }

  static String s(Map<String, Object> m, String k) {
    Object v = m.get(k);
    return v == null ? null : String.valueOf(v).trim();
  }

  @TestVisible
  static List<String> validate(Map<String, Object> q) {
    List<String> bad = new List<String>();
    Cardcom_Setting__mdt st = CardcomService.settings();
    String fn = s(q, 'firstName'), ln = s(q, 'lastName'), em = s(q, 'email'), ph = s(q, 'phone'), id = s(q, 'taxId');
    if (String.isBlank(fn) || fn.length() > 40)
      bad.add('firstName');
    if (String.isBlank(ln) || ln.length() > 80)
      bad.add('lastName');
    if (String.isBlank(em) || em.length() > 80 || !Pattern.matches('^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$', em))
      bad.add('email');
    String np = ContactMatcher.normPhone(ph);
    if (np == null || !Pattern.matches('^05\\d{8}$', np))
      bad.add('phone');
    if (String.isNotBlank(id) && !ContactMatcher.validIsraeliId(id))
      bad.add('taxId');
    Decimal a;
    try {
      a = Decimal.valueOf(String.valueOf(q.get('amount')));
    } catch (Exception e) {
      a = null;
    }
    if (a == null || a < st.Min_Amount__c || a > st.Max_Amount__c || a.scale() > 2)
      bad.add('amount');
    if (!new Set<String>{ 'OnceDaily', 'TwiceDaily' }.contains(s(q, 'frequency')))
      bad.add('frequency');
    if (q.get('termsAccepted') != true)
      bad.add('termsAccepted');
    if (String.isBlank(s(q, 'lowProfileId')) || !Pattern.matches('[A-Za-z0-9-]{10,64}', s(q, 'lowProfileId')))
      bad.add('lowProfileId');
    return bad;
  }
}
