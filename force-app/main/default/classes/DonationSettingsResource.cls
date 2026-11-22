/**
 * Form settings for the WordPress plugin (N123): the amount buttons and the min/max per charge, from Cardcom_Setting__mdt.Default.
 * GET /donations/settings → {presets:[1,2,3,5,10], minAmount:1, maxAmount:40}. Called by the integration user (JWT Bearer),
 * read only. Presets that aren't numbers are dropped; the plugin also drops buttons outside min..max.
 */
@RestResource(urlMapping='/donations/settings')
global without sharing class DonationSettingsResource {
  @HttpGet
  global static void read() {
    RestResponse res = RestContext.response;
    res.addHeader('Content-Type', 'application/json; charset=utf-8');
    res.addHeader('Cache-Control', 'no-store');
    Map<String, Object> out;
    try {
      out = settings(CardcomService.settings());
      res.statusCode = 200;
    } catch (Exception e) {
      System.debug(LoggingLevel.ERROR, 'settings ' + e.getMessage());
      res.statusCode = 500;
      out = new Map<String, Object>{ 'error' => 'INTERNAL' };
    }
    res.responseBody = Blob.valueOf(JSON.serialize(out));
  }

  @TestVisible
  static Map<String, Object> settings(Cardcom_Setting__mdt s) {
    List<Decimal> presets = new List<Decimal>();
    for (String x : (s.Amount_Presets__c == null ? '' : s.Amount_Presets__c).split(',')) {
      try {
        if (String.isNotBlank(x))
          presets.add(Decimal.valueOf(x.trim()));
      } catch (TypeException e) {
        // not a number → skipped
      }
    }
    return new Map<String, Object>{ 'presets' => presets, 'minAmount' => s.Min_Amount__c, 'maxAmount' => s.Max_Amount__c };
  }
}
