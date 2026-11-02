/** Small email helpers (Part A 7.8). */
public without sharing class EmailUtil {
  public static String esc(Object v) {
    return v == null ? '' : String.valueOf(v).escapeHtml4();
  }
  public static String recordUrl(Id id) {
    return URL.getOrgDomainUrl().toExternalForm() + '/' + id;
  }
  public static Id oweaId(String address) {
    if (String.isBlank(address))
      return null;
    List<OrgWideEmailAddress> o = [SELECT Id FROM OrgWideEmailAddress WHERE Address = :address LIMIT 1];
    return o.isEmpty() ? null : o[0].Id;
  }
}
