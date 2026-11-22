@IsTest
private class DonationSettingsResourceTest {
  static void get() {
    RestRequest req = new RestRequest();
    req.requestURI = '/services/apexrest/donations/settings';
    req.httpMethod = 'GET';
    RestContext.request = req;
    RestContext.response = new RestResponse();
  }

  @IsTest
  static void returnsPresetsAndRange() {
    Cardcom_Setting__mdt s = TestDataFactory.settings();
    s.Amount_Presets__c = '1, 2,3.5,10';
    s.Min_Amount__c = 1;
    s.Max_Amount__c = 40;
    get();
    DonationSettingsResource.read();
    Assert.areEqual(200, RestContext.response.statusCode);
    Map<String, Object> out = TestDataFactory.responseJson();
    List<Object> p = (List<Object>) out.get('presets');
    Assert.areEqual(4, p.size());
    Assert.areEqual(3.5, Decimal.valueOf(String.valueOf(p[2])));
    Assert.areEqual(1, Decimal.valueOf(String.valueOf(out.get('minAmount'))));
    Assert.areEqual(40, Decimal.valueOf(String.valueOf(out.get('maxAmount'))));
  }

  @IsTest
  static void dropsValuesThatAreNotNumbers() {
    Cardcom_Setting__mdt s = TestDataFactory.settings();
    s.Amount_Presets__c = '5,abc,,7';
    Map<String, Object> out = DonationSettingsResource.settings(s);
    Assert.areEqual(new List<Decimal>{ 5, 7 }, (List<Decimal>) out.get('presets'));
    s.Amount_Presets__c = null;
    Assert.areEqual(0, ((List<Decimal>) DonationSettingsResource.settings(s).get('presets')).size());
  }
}
