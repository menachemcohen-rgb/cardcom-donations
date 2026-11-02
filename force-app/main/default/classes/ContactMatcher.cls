/**
 * Match an existing donor Contact or create one (CLAUDE.md Part A 7.4א, B6.4, Part C E4/E16).
 * Keys: Email > Phone > Israeli ID (hash only — the encrypted ID is never filtered on). Fill blanks only; conflicts → Needs_Review.
 */
public without sharing class ContactMatcher {
  public class DonorInput {
    public String firstName, lastName, email, phone, taxId;
    public DonorInput(String f, String l, String e, String p, String t) {
      firstName = f;
      lastName = l;
      email = e;
      phone = p;
      taxId = t;
    }
  }
  public class Result {
    public Id contactId;
    public String method;
    public Boolean created = false;
  }

  @TestVisible
  static Boolean skipDuplicateRules = false; // tests / orgs without active rule

  // ---------- normalization ----------
  public static String normEmail(String e) {
    return String.isBlank(e) ? null : e.trim().toLowerCase();
  }

  public static String normPhone(String p) {
    if (String.isBlank(p))
      return null;
    String d = p.replaceAll('[^0-9]', '');
    if (d.startsWith('00972'))
      d = d.substring(5);
    else if (d.startsWith('972'))
      d = d.substring(3);
    if (!d.startsWith('0'))
      d = '0' + d;
    return Pattern.matches('05\\d{8}', d) ? d : null; // mobile only
  }

  public static String taxIdHash(String id) {
    if (String.isBlank(id))
      return null;
    String d = id.replaceAll('[^0-9]', '').leftPad(9, '0');
    if (d.length() != 9 || !validIlId(d))
      return null;
    return EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(d)));
  }

  /** Public check used by DonationPledgeResource (Part C E4): 9 digits (after left-padding) with a valid check digit. */
  public static Boolean validIsraeliId(String id) {
    if (String.isBlank(id))
      return false;
    String t = id.trim();
    if (!Pattern.matches('\\d{1,9}', t))
      return false;
    return validIlId(t.leftPad(9, '0'));
  }

  static Boolean validIlId(String d) {
    Integer sum = 0;
    for (Integer i = 0; i < 9; i++) {
      Integer x = Integer.valueOf(d.substring(i, i + 1)) * (Math.mod(i, 2) + 1);
      sum += x > 9 ? x - 9 : x;
    }
    return Math.mod(sum, 10) == 0;
  }

  // ---------- candidates ----------
  static Set<Id> findViaDuplicateRules(String em, String ph, String tx, DonorInput donor) {
    Set<Id> ids = new Set<Id>();
    if (skipDuplicateRules)
      return ids;
    Contact probe = new Contact(
      FirstName = donor.firstName,
      LastName = donor.lastName,
      Email = donor.email,
      MobilePhone = donor.phone,
      Email_Normalized__c = em,
      Phone_Normalized__c = ph,
      Tax_Id_Hash__c = tx
    );
    try {
      for (Datacloud.FindDuplicatesResult fdr : Datacloud.FindDuplicates.findDuplicates(new List<Contact>{ probe })) {
        for (Datacloud.DuplicateResult dr : fdr.getDuplicateResults()) {
          for (Datacloud.MatchResult mr : dr.getMatchResults()) {
            for (Datacloud.MatchRecord rec : mr.getMatchRecords())
              ids.add(rec.getRecord().Id);
          }
        }
      }
    } catch (Exception e) {
      // No active duplicate rule / limits → fall back to SOQL only
      System.debug(LoggingLevel.WARN, 'FindDuplicates failed: ' + e.getMessage());
    }
    return ids;
  }

  static final String FIELDS =
    'Id, FirstName, LastName, Email, MobilePhone, OtherPhone, Donor_Tax_Id__c, ' +
    'Email_Normalized__c, Phone_Normalized__c, Tax_Id_Hash__c, Needs_Review__c, Review_Reason__c, LastModifiedDate, CreatedDate';

  static List<Contact> loadCandidates(Set<Id> dupIds, String em, String ph, String tx) {
    // SOQL complement: union of rule hits + direct normalized-field hits (never the encrypted ID — Part C E16)
    return Database.query(
      'SELECT ' +
        FIELDS +
        ' FROM Contact WHERE Id IN :dupIds' +
        (em != null ? ' OR Email_Normalized__c = :em' : '') +
        (ph != null ? ' OR Phone_Normalized__c = :ph' : '') +
        (tx != null ? ' OR Tax_Id_Hash__c = :tx' : '') +
        ' ORDER BY LastModifiedDate DESC, CreatedDate ASC, Id ASC LIMIT 50'
    );
  }

  // 1 = Email, 2 = Phone, 3 = TaxId, 9 = matched only by an org rule on other fields
  @TestVisible
  static Integer rank(Contact c, String em, String ph, String tx) {
    if (em != null && c.Email_Normalized__c == em)
      return 1;
    if (ph != null && c.Phone_Normalized__c == ph)
      return 2;
    if (tx != null && c.Tax_Id_Hash__c == tx)
      return 3;
    return 9;
  }
  static final Map<Integer, String> METHOD = new Map<Integer, String>{ 1 => 'Email', 2 => 'Phone', 3 => 'TaxId', 9 => 'DuplicateRule' };

  // ---------- main ----------
  /** B6.4 / B8 name (spec-consistency N4). */
  public static Result match(DonorInput donor) {
    return matchOrCreate(donor);
  }

  public static Result matchOrCreate(DonorInput donor) {
    String em = normEmail(donor.email), ph = normPhone(donor.phone), tx = taxIdHash(donor.taxId);
    Set<Id> dupIds = findViaDuplicateRules(em, ph, tx, donor);
    List<Contact> cands = (em == null &&
      ph == null &&
      tx == null &&
      dupIds.isEmpty())
      ? new List<Contact>()
      : loadCandidates(dupIds, em, ph, tx);

    Database.DMLOptions o = new Database.DMLOptions();
    o.DuplicateRuleHeader.allowSave = true; // alert-only rule must never block integration
    o.DuplicateRuleHeader.runAsCurrentUser = true;

    Result r = new Result();
    if (cands.isEmpty()) {
      Contact c = new Contact(
        FirstName = donor.firstName,
        LastName = donor.lastName,
        Email = donor.email,
        MobilePhone = donor.phone,
        Donor_Tax_Id__c = donor.taxId,
        Donor_Source__c = 'WP_Micro'
      );
      Database.SaveResult sr = Database.insert(c, o);
      if (!sr.isSuccess())
        throw new CardcomService.CardcomException('Contact insert failed: ' + sr.getErrors()[0].getMessage());
      r.contactId = c.Id;
      r.method = 'New';
      r.created = true;
      return r;
    }

    // Pick by priority Email > Phone > TaxId; ties already ordered by LastModifiedDate DESC (stable)
    Contact best = null;
    Integer bestRank = 99;
    for (Contact c : cands) {
      Integer k = rank(c, em, ph, tx);
      if (k < bestRank) {
        best = c;
        bestRank = k;
      }
    }
    List<String> review = new List<String>();
    if (cands.size() > 1) {
      List<Id> ids = new List<Id>();
      for (Contact x : cands)
        ids.add(x.Id);
      review.add('נמצאו ' + cands.size() + ' תורמים מתאימים: ' + String.join(ids, ','));
    }
    mergeFields(best, donor, em, ph, tx, review);
    if (!review.isEmpty()) {
      best.Needs_Review__c = true;
      best.Review_Reason__c = appendReason(best.Review_Reason__c, String.join(review, '; '));
    }
    Database.SaveResult ur = Database.update(best, o);
    if (!ur.isSuccess())
      throw new CardcomService.CardcomException('Contact update failed: ' + ur.getErrors()[0].getMessage());
    r.contactId = best.Id;
    r.method = METHOD.get(bestRank);
    return r;
  }

  // Fill-blanks only; conflicts → review flag, never overwrite non-empty values (B6.4 table)
  @TestVisible
  static void mergeFields(Contact c, DonorInput donor, String em, String ph, String tx, List<String> review) {
    if (String.isBlank(c.FirstName))
      c.FirstName = donor.firstName;
    if (String.isBlank(c.Email))
      c.Email = donor.email;
    else if (em != null && normEmail(c.Email) != em)
      review.add('אימייל שונה: ' + em);
    if (String.isBlank(c.MobilePhone))
      c.MobilePhone = donor.phone;
    else if (ph != null && normPhone(c.MobilePhone) != ph && String.isBlank(c.OtherPhone))
      c.OtherPhone = donor.phone;
    if (String.isBlank(c.Donor_Tax_Id__c)) {
      if (tx != null)
        c.Donor_Tax_Id__c = donor.taxId;
    } else if (tx != null && c.Tax_Id_Hash__c != tx)
      review.add('ת"ז שונה');
  }

  /** B6.4: Review_Reason__c is a Long Text that accumulates "dd/MM/yyyy HH:mm reason" lines; keeps the newest 2000 chars. */
  @TestVisible
  static String appendReason(String old, String reason) {
    String line = Datetime.now().format('dd/MM/yyyy HH:mm') + ' ' + reason;
    return ((old == null ? '' : old + '\n') + line).right(2000);
  }
}
