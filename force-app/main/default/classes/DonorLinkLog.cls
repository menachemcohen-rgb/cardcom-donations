/** Donor_Link_Use__c log (B6.10.1). Buffered and flushed at the end of the request, so no DML happens before a callout. Never blocks. */
public without sharing class DonorLinkLog {
  static List<Donor_Link_Use__c> buffer = new List<Donor_Link_Use__c>();
  public static void write(Id pledgeId, String action, Integer version, String result, String ip) {
    buffer.add(
      new Donor_Link_Use__c(
        Pledge__c = pledgeId,
        Action__c = action,
        Link_Version__c = version,
        Used_At__c = Datetime.now(),
        Client_Ip__c = ip == null ? null : ip.left(45),
        Result__c = result
      )
    );
  }
  public static void flush() {
    if (buffer.isEmpty())
      return;
    Database.insert(buffer, false); // log only — never blocks the request
    buffer.clear();
  }
  @TestVisible
  static Integer pending() {
    return buffer.size();
  }
}
