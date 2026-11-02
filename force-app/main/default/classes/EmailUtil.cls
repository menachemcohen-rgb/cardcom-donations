/** Small email helpers (Part A 7.8). */
public without sharing class EmailUtil {
  public static String esc(Object v) {
    return v == null ? '' : String.valueOf(v).escapeHtml4();
  }
  public static String recordUrl(Id id) {
    return URL.getOrgDomainUrl().toExternalForm() + '/' + id;
  }
  static final Map<String, Id> OWEA_CACHE = new Map<String, Id>();

  /** Cached per transaction: callers build many messages in a loop. */
  public static Id oweaId(String address) {
    if (String.isBlank(address))
      return null;
    if (!OWEA_CACHE.containsKey(address)) {
      List<OrgWideEmailAddress> o = [SELECT Id FROM OrgWideEmailAddress WHERE Address = :address LIMIT 1];
      OWEA_CACHE.put(address, o.isEmpty() ? null : o[0].Id);
    }
    return OWEA_CACHE.get(address);
  }
}
