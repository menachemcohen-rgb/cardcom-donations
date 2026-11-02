/**
 * Signed donor links (B6.9.1, D15): token = base64url(payload) + '.' + base64url(HMAC-SHA256(secret, base64url(payload))).
 * Payload {"p": pledge Id, "a": "card"|"amount", "v": Link_Version__c} — no expiry, no nonce. Revocation = Link_Version__c + 1;
 * secret rotation keeps Previous_Secret__c valid until it is cleared.
 */
public without sharing class DonorLinkToken {
  public class Claims {
    public Id pledgeId;
    public String action;
    public Integer version;
  }
  public class LinkException extends Exception {
  }
  @TestVisible
  static String secretOverride,
    previousOverride;

  static Donor_Link_Setting__mdt cfg() {
    return Donor_Link_Setting__mdt.getInstance('Default');
  }
  static String secret() {
    return secretOverride != null ? secretOverride : (cfg() == null ? null : cfg().Secret__c);
  }
  static String previous() {
    return previousOverride != null ? previousOverride : (cfg() == null ? null : cfg().Previous_Secret__c);
  }

  static String b64url(Blob b) {
    return EncodingUtil.base64Encode(b).replace('+', '-').replace('/', '_').replace('=', '');
  }
  static Blob fromB64url(String s) {
    String t = s.replace('-', '+').replace('_', '/');
    while (Math.mod(t.length(), 4) != 0)
      t += '=';
    return EncodingUtil.base64Decode(t);
  }
  static String sign(String body, String key) {
    return b64url(Crypto.generateMac('hmacSHA256', Blob.valueOf(body), Blob.valueOf(key)));
  }

  public static String issue(Id pledgeId, String action, Decimal version) {
    String key = secret();
    if (String.isBlank(key))
      throw new LinkException('Donor_Link_Setting__mdt.Default.Secret__c is empty'); // manual Setup step 8
    String body = b64url(
      Blob.valueOf(
        JSON.serialize(new Map<String, Object>{ 'p' => pledgeId, 'a' => action, 'v' => version == null ? 1 : version.intValue() })
      )
    );
    return body + '.' + sign(body, key);
  }

  /** Signature + structure only. Version/status checked by caller against the DB. */
  public static Claims parse(String token) {
    if (String.isBlank(token) || token.length() > 600 || !token.contains('.'))
      throw new LinkException('format');
    String key = secret();
    if (String.isBlank(key))
      throw new LinkException('no secret');
    String body = token.substringBefore('.'), sig = token.substringAfter('.');
    Boolean ok = constantTimeEquals(sig, sign(body, key));
    if (!ok && String.isNotBlank(previous()))
      ok = constantTimeEquals(sig, sign(body, previous()));
    if (!ok)
      throw new LinkException('signature');
    Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(fromB64url(body).toString());
    Claims c = new Claims();
    c.pledgeId = (Id) (String) m.get('p');
    c.action = (String) m.get('a');
    c.version = (Integer) m.get('v');
    return c;
  }

  static Boolean constantTimeEquals(String a, String b) {
    if (a == null || b == null || a.length() != b.length())
      return false;
    Integer r = 0;
    for (Integer i = 0; i < a.length(); i++)
      r |= a.charAt(i) ^ b.charAt(i);
    return r == 0;
  }

  /** Full check used by DonorPortalResource. Only pledges of record type Micro_Donation_Pledge (D24), Active only. */
  public static Opportunity verify(String token, Set<String> allowedActions, String clientIp) {
    Claims c;
    try {
      c = parse(token);
    } catch (Exception e) {
      DonorLinkLog.write(null, null, null, 'Bad_Signature', clientIp);
      throw new LinkException('invalid');
    }
    if (!allowedActions.contains(c.action)) {
      DonorLinkLog.write(c.pledgeId, c.action, c.version, 'Bad_Signature', clientIp);
      throw new LinkException('invalid');
    }
    Id rt = MicroPledges.recordTypeId();
    List<Opportunity> ps = [
      SELECT
        Id,
        StageName,
        Link_Version__c,
        Charge_Amount__c,
        Frequency__c,
        Last4__c,
        CardExpirationMMYY__c,
        Donor_Contact__r.FirstName,
        Donor_First_Name__c,
        Donor_Contact__r.Email,
        Donor_Phone__c
      FROM Opportunity
      WHERE Id = :c.pledgeId AND RecordTypeId = :rt
    ];
    if (ps.isEmpty())
      throw new LinkException('invalid');
    Opportunity p = ps[0];
    Integer current = p.Link_Version__c == null ? 1 : p.Link_Version__c.intValue();
    if (current != c.version) {
      DonorLinkLog.write(p.Id, c.action, c.version, 'Revoked', clientIp);
      throw new LinkException('invalid');
    }
    if (p.StageName != MicroPledges.STAGE_ACTIVE) {
      DonorLinkLog.write(p.Id, c.action, c.version, 'Inactive', clientIp);
      throw new LinkException('invalid');
    }
    DonorLinkLog.write(p.Id, c.action, c.version, 'OK', clientIp);
    return p;
  }
}
