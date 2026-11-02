/** Cardcom response code → handling category (B6.5.3, B5.8). Codes come from Cardcom_Error_Code__mdt; unknown codes → Retryable. */
public without sharing class ChargeErrorClassifier {
  @TestVisible
  static Map<Integer, String> overrideMap;
  static Map<Integer, String> cache;
  public static String classify(Integer code) {
    if (cache == null) {
      cache = overrideMap != null ? overrideMap : new Map<Integer, String>();
      if (overrideMap == null)
        for (Cardcom_Error_Code__mdt m : Cardcom_Error_Code__mdt.getAll().values())
          cache.put(m.Code__c.intValue(), m.Category__c);
    }
    if (cache.containsKey(code))
      return cache.get(code);
    if (code >= 3000000 && code < 4000000)
      return 'Card_Declined'; // 3DS range (B5.3, ✔ [SW])
    if (code >= 60000000 && code < 70000000)
      return 'Card_Declined'; // issuer range (B5.3, ✔ [SW])
    return 'Retryable';
  }
}
