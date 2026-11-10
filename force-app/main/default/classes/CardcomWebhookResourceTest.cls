@IsTest
private class CardcomWebhookResourceTest {
  static void call(String body, Map<String, String> params) {
    RestRequest req = new RestRequest();
    req.requestURI = '/services/apexrest/cardcom/webhook';
    req.httpMethod = 'POST';
    req.requestBody = Blob.valueOf(body);
    req.addHeader('Content-Type', 'application/json');
    if (params != null)
      for (String k : params.keySet())
        req.addParameter(k, params.get(k));
    RestContext.request = req;
    RestContext.response = new RestResponse();
    CardcomWebhookResource.receive();
  }

  @IsTest
  static void webhookLogsPublishesAndCreatesVerifiedPledge() {
    TestDataFactory.settings();
    CardcomMock m = CardcomMock.install().always('LowProfile/GetLpResult', 200, CardcomMock.lpSuccess('lp-0000000001', 'SIGNUP-x'));
    Test.startTest();
    call(JSON.serialize(new Map<String, Object>{ 'LowProfileId' => 'lp-0000000001', 'ResponseCode' => 0 }), null);
    Test.getEventBus().deliver();
    Test.stopTest();
    Assert.areEqual(200, RestContext.response.statusCode);
    Cardcom_Webhook_Log__c log = [SELECT LowProfileId__c, Content_Type__c, Processed__c FROM Cardcom_Webhook_Log__c];
    Assert.areEqual('lp-0000000001', log.LowProfileId__c);
    Assert.areEqual('application/json', log.Content_Type__c);
    Assert.isTrue(log.Processed__c);
    Opportunity p = [
      SELECT StageName, Lp_Processed__c, Token__c, CardExpirationMMYY__c, Token_Expiry_Date__c, Type
      FROM Opportunity
      WHERE LowProfileId__c = 'lp-0000000001'
    ];
    Assert.areEqual(MicroPledges.TYPE, p.Type);
    Assert.areEqual('Pending_Verification', p.StageName, 'not active until the donor submits the form');
    Assert.isTrue(p.Lp_Processed__c);
    Assert.areEqual('tok-lp-0000000001', p.Token__c);
    Assert.areEqual('0928', p.CardExpirationMMYY__c);
    Assert.areEqual(1, m.requestsTo('LowProfile/GetLpResult').size());
  }

  @IsTest
  static void extractsLowProfileIdFromEveryShape() {
    RestRequest req = new RestRequest();
    Assert.areEqual('lp-0000000001', CardcomWebhookResource.extractLowProfileId(req, '{"LowProfileCode":"lp-0000000001"}'));
    Assert.areEqual('lp-0000000002', CardcomWebhookResource.extractLowProfileId(req, 'a=1&lowprofileid=lp-0000000002'));
    Assert.isNull(CardcomWebhookResource.extractLowProfileId(req, '{bad json'));
    Assert.isNull(CardcomWebhookResource.extractLowProfileId(req, ''));
    req.addParameter('lowprofilecode', 'lp-0000000003');
    Assert.areEqual('lp-0000000003', CardcomWebhookResource.extractLowProfileId(req, ''));
  }

  @IsTest
  static void invalidOrMissingIdIsLoggedButNotPublished() {
    Test.startTest();
    call('{bad json', null);
    call('{"LowProfileId":"bad id!"}', null);
    Test.stopTest();
    Assert.areEqual(2, [SELECT COUNT() FROM Cardcom_Webhook_Log__c]);
    Assert.areEqual(0, [SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = 'CardcomLpResultJob']);
    Assert.areEqual(200, RestContext.response.statusCode);
  }

  @IsTest
  static void terminalOnTheWebhookUrlIsAskedFirst() {
    // D39: the secondary terminal's WebHookUrl ends with ?terminal=Secondary
    TestDataFactory.settings().Secondary_Terminal_Number__c = 2002;
    CardcomMock m = CardcomMock.install().always('LowProfile/GetLpResult', 200, CardcomMock.lpSuccess('lp-0000000001', 'SIGNUP-x'));
    Test.startTest();
    call(
      JSON.serialize(new Map<String, Object>{ 'LowProfileId' => 'lp-0000000001', 'ResponseCode' => 0 }),
      new Map<String, String>{ 'terminal' => 'Secondary' }
    );
    Test.getEventBus().deliver();
    Test.stopTest();
    Assert.areEqual(1, m.requestsTo('LowProfile/GetLpResult').size());
    Assert.areEqual('callout:Cardcom_Secondary/api/v11/LowProfile/GetLpResult', m.requestsTo('LowProfile/GetLpResult')[0].getEndpoint());
    Assert.areEqual('Secondary', [SELECT Cardcom_Terminal__c FROM Opportunity WHERE LowProfileId__c = 'lp-0000000001'].Cardcom_Terminal__c);
  }
}
