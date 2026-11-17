/**
 * Every outgoing email (donors and staff) is a Classic Email Template in the folder "Donations", so admins edit the text in
 * Setup → Classic Email Templates without a deploy. Templates use {{Name}} placeholders that Apex fills; no Salesforce merge fields.
 * Values for the HTML body are HTML-escaped by the caller (or are HTML built in code, such as {{Table}}); subject values are plain.
 * A template that is missing or blank falls back to the default text kept in code, so an email is never lost to a bad edit.
 * Each template starts with a "<!-- FIELDS ... -->" note listing the placeholders it can use (for admins; removed before sending).
 * Salesforce merge fields ({!Contact.LastName}) offered by the template editor are not filled and are removed too.
 * The list of templates and placeholders: docs/email-templates-he.md.
 */
public without sharing class EmailTemplates {
  public class Rendered {
    public String subject;
    public String html;
  }

  @TestVisible
  static Map<String, EmailTemplate> byName;

  /** One query per template per transaction (Apex can filter on EmailTemplate.DeveloperName but not select it). */
  static EmailTemplate find(String devName) {
    if (byName == null)
      byName = new Map<String, EmailTemplate>();
    if (!byName.containsKey(devName)) {
      List<EmailTemplate> t = [SELECT Subject, HtmlValue FROM EmailTemplate WHERE DeveloperName = :devName LIMIT 1];
      byName.put(devName, t.isEmpty() ? null : t[0]);
    }
    return byName.get(devName);
  }

  /** Subject and HTML of template devName with {{Key}} replaced: html values in the body, plain values (or html ones) in the subject. */
  public static Rendered render(
    String devName,
    String defaultSubject,
    String defaultHtml,
    Map<String, String> htmlValues,
    Map<String, String> plainValues
  ) {
    EmailTemplate t = find(devName);
    String subject = t != null && String.isNotBlank(t.Subject) ? t.Subject : defaultSubject;
    String html = t != null && String.isNotBlank(t.HtmlValue) ? t.HtmlValue : defaultHtml;
    Map<String, String> forSubject = htmlValues == null ? new Map<String, String>() : htmlValues.clone();
    if (plainValues != null)
      forSubject.putAll(plainValues);
    Rendered r = new Rendered();
    r.subject = fill(subject, forSubject);
    r.html = fill(html, htmlValues);
    return r;
  }

  /**
   * {{Key}} → value. Removed so a donor never sees them: the admin FIELDS note, Salesforce merge fields ({!...}) and unknown
   * placeholders.
   */
  public static String fill(String text, Map<String, String> values) {
    if (text == null)
      return '';
    String out = text.replaceAll('(?s)<!--\\s*FIELDS.*?-->\\s*', '').replaceAll('\\{![^}]*\\}', '');
    if (values != null)
      for (String k : values.keySet())
        out = out.replace('{{' + k + '}}', values.get(k) == null ? '' : values.get(k));
    return out.replaceAll('\\{\\{[A-Za-z0-9_]+\\}\\}', '');
  }
}
