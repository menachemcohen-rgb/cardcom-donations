/**
 * Donor-portal card change (B6.10.1). Prompt 8 implements it. Prompt 3 only needs the entry points that CardcomLpResultJob and
 * PendingVerificationSweeper call. Until Prompt 8 no Card_Change_Request__c can exist, so these are safe no-ops.
 */
public without sharing class CardChangeService {
  public static Boolean isCardChange(String returnValue) {
    return returnValue != null && returnValue.startsWith('CARD-');
  }

  public static void complete(String lowProfileId, Map<String, Object> lpResult) {
    // TODO Prompt 8 (B6.10.1): move the new token to the pledge, write Pledge_Card_History__c and the change log.
  }

  public static void expireStale() {
    // TODO Prompt 8 (B6.10.1): Card_Change_Request__c Pending for more than 30 minutes → Expired.
  }
}
