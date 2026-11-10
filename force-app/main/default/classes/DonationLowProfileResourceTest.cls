@IsTest
private class DonationLowProfileResourceTest {
  @IsTest
  static void returnsIframeUrl() {
    TestDataFactory.settings();
    CardcomMock m = CardcomMock.install().enqueue('LowProfile/Create', 200, CardcomMock.lpCreated('lp-0000000001'));
    TestDataFactory.rest(
      '/services/apexrest/donations/lowprofile',
      new Map<String, Object>{ 'purpose' => 'signup', 'returnUrlBase' => TestDataFactory.RETURN_URL }
    );
    Test.startTest();
    DonationLowProfileResource.create();
    Test.stopTest();
    Assert.areEqual(200, RestContext.response.statusCode);
    Map<String, Object> out = TestDataFactory.responseJson();
    Assert.areEqual('lp-0000000001', out.get('lowProfileId'));
    Assert.isTrue(((String) out.get('url')).startsWith('https://secure.cardcom.solutions/'));
    Assert.isNotNull(out.get('expiresAt'));
    Assert.isTrue(((String) m.lastBody('LowProfile/Create').get('ReturnValue')).startsWith('SIGNUP-'));
    Assert.areEqual(0, [SELECT COUNT() FROM Opportunity], 'no record on page load (7.3)');
  }

  @IsTest
  static void rejectsReturnUrlOutsideAllowedHosts() {
    TestDataFactory.settings();
    for (String bad : new List<String>{ 'http://' + TestDataFactory.HOST + '/x', 'https://evil.example.com/x', null }) {
      TestDataFactory.rest('/services/apexrest/donations/lowprofile', new Map<String, Object>{ 'returnUrlBase' => bad });
      DonationLowProfileResource.create();
      Assert.areEqual(400, RestContext.response.statusCode);
      Assert.areEqual('BAD_RETURN_URL', TestDataFactory.responseJson().get('error'));
    }
  }

  @IsTest
  static void cardcomErrorBecomesCardcomError() {
    TestDataFactory.settings();
    CardcomMock.install().enqueue('LowProfile/Create', 200, new Map<String, Object>{ 'ResponseCode' => 5, 'Description' => 'x' });
    TestDataFactory.rest(
      '/services/apexrest/donations/lowprofile',
      new Map<String, Object>{ 'returnUrlBase' => TestDataFactory.RETURN_URL }
    );
    DonationLowProfileResource.create();
    Assert.areEqual(400, RestContext.response.statusCode);
    Assert.areEqual('CARDCOM_ERROR', TestDataFactory.responseJson().get('error'));
  }

  @IsTest
  static void dinersCardOpensOnTheSecondaryTerminal() {
    // D39
    TestDataFactory.settings().Secondary_Terminal_Number__c = 2002;
    CardcomMock m = CardcomMock.install().enqueue('LowProfile/Create', 200, CardcomMock.lpCreated('lp-0000000001'));
    TestDataFactory.rest(
      '/services/apexrest/donations/lowprofile',
      new Map<String, Object>{ 'purpose' => 'signup', 'returnUrlBase' => TestDataFactory.RETURN_URL, 'terminal' => 'Secondary' }
    );
    Test.startTest();
    DonationLowProfileResource.create();
    Test.stopTest();
    Assert.areEqual(200, RestContext.response.statusCode);
    Assert.areEqual('Secondary', TestDataFactory.responseJson().get('terminal'));
    Assert.areEqual('callout:Cardcom_Secondary/api/v11/LowProfile/Create', m.requestsTo('LowProfile/Create')[0].getEndpoint());
    Assert.areEqual(2002, m.lastBody('LowProfile/Create').get('TerminalNumber'));
  }

  @IsTest
  static void secondaryTerminalNotConfiguredIsRejected() {
    TestDataFactory.settings();
    TestDataFactory.rest(
      '/services/apexrest/donations/lowprofile',
      new Map<String, Object>{ 'returnUrlBase' => TestDataFactory.RETURN_URL, 'terminal' => 'Secondary' }
    );
    DonationLowProfileResource.create();
    Assert.areEqual(400, RestContext.response.statusCode);
    Assert.areEqual('TERMINAL_NOT_CONFIGURED', TestDataFactory.responseJson().get('error'));
  }
}
