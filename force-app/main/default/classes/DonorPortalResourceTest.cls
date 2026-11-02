@IsTest
private class DonorPortalResourceTest {
  static Opportunity p;

  static void setup() {
    TestDataFactory.chargeEngine(TestDataFactory.WED_0800);
    DonorLinkToken.secretOverride = 'portal-secret-0123456789abcdef';
    p = TestDataFactory.activePledges(1, 'TwiceDaily')[0];
  }

  static Map<String, Object> call(String path, Map<String, Object> body) {
    TestDataFactory.rest('/services/apexrest/donor/' + path, body);
    DonorPortalResource.handle();
    return TestDataFactory.responseJson();
  }

  static String link(String action) {
    return DonorLinkToken.issue(p.Id, action, 1);
  }

  @IsTest
  static void contextShowsThePledgeWithoutPersonalData() {
    setup();
    Map<String, Object> r = call('context', new Map<String, Object>{ 'token' => link('card'), 'clientIp' => '1.2.3.4' });
    Assert.areEqual(200, RestContext.response.statusCode);
    Assert.areEqual('card', r.get('action'));
    Assert.areEqual('Avi', r.get('firstName'));
    Assert.areEqual('TwiceDaily', r.get('frequency'));
    Assert.areEqual('Active', r.get('status'));
    Assert.areEqual(4, ((List<Object>) r.get('presets')).size());
    Assert.isFalse(r.containsKey('email') || r.containsKey('phone'), 'no email/phone/ID on the page (B6.10)');
    Assert.areEqual(1, [SELECT COUNT() FROM Donor_Link_Use__c WHERE Result__c = 'OK'], 'use is logged');
  }

  @IsTest
  static void amountChangeAppliesFromTheNextChargeOnly() {
    // TC25, D16
    setup();
    Charge__c pending = TestDataFactory.charge(p, Date.newInstance(2026, 11, 4), 'AM');
    insert pending;
    Map<String, Object> r = call('amount', new Map<String, Object>{ 'token' => link('amount'), 'amount' => 5, 'clientIp' => '1.2.3.4' });
    Assert.areEqual(true, r.get('changed'));
    Assert.areEqual(5, [SELECT Charge_Amount__c FROM Opportunity WHERE Id = :p.Id].Charge_Amount__c.intValue());
    Assert.areEqual(
      3,
      [SELECT Amount__c FROM Charge__c WHERE Id = :pending.Id].Amount__c.intValue(),
      'existing Pending keeps its snapshot'
    );
    Pledge_Change_Log__c l = [SELECT Change_Type__c, Old_Value__c, New_Value__c, Source__c FROM Pledge_Change_Log__c];
    Assert.areEqual('Amount', l.Change_Type__c);
    Assert.areEqual('Donor_Portal', l.Source__c);
    Assert.areEqual('5.00', l.New_Value__c);

    r = call('amount', new Map<String, Object>{ 'token' => link('amount'), 'amount' => '5.00' });
    Assert.areEqual(false, r.get('changed'), 'same amount: no change, no log');
    Assert.areEqual(1, [SELECT COUNT() FROM Pledge_Change_Log__c]);
  }

  @IsTest
  static void amountOutOfRangeOrWrongLinkIsRefused() {
    // TC26
    setup();
    for (Object a : new List<Object>{ 0.5, 100, 'abc' }) {
      Map<String, Object> r = call('amount', new Map<String, Object>{ 'token' => link('amount'), 'amount' => a });
      Assert.areEqual(400, RestContext.response.statusCode, String.valueOf(a));
      Assert.areEqual('AMOUNT_RANGE', r.get('error'));
    }
    Assert.areEqual(3, [SELECT Charge_Amount__c FROM Opportunity WHERE Id = :p.Id].Charge_Amount__c.intValue());
    Map<String, Object> r = call('amount', new Map<String, Object>{ 'token' => link('card'), 'amount' => 5 });
    Assert.areEqual(403, RestContext.response.statusCode, 'a card link cannot change the amount');
    Assert.areEqual('LINK_INVALID', r.get('error'));
    call('nope', new Map<String, Object>{ 'token' => link('card') });
    Assert.areEqual(404, RestContext.response.statusCode);
  }

  @IsTest
  static void cardReplacementStartsALowProfile() {
    // TC27, step 1
    setup();
    CardcomMock m = CardcomMock.install().always('LowProfile/Create', 200, CardcomMock.lpCreated('lp-card-0000000001'));
    Test.startTest();
    Map<String, Object> r = call('card', new Map<String, Object>{ 'token' => link('card'), 'returnUrlBase' => TestDataFactory.RETURN_URL });
    Test.stopTest();
    Assert.areEqual('lp-card-0000000001', r.get('lowProfileId'));
    Assert.isTrue(((String) m.lastBody('LowProfile/Create').get('ReturnValue')).startsWith('CARD-'));
    Assert.areEqual('Pending', [SELECT Status__c FROM Card_Change_Request__c].Status__c);
  }

  @IsTest
  static void cardStatusWaitsThenPullsTheResult() {
    // TC27, step 2: within 10 s wait for the webhook; after that Salesforce pulls GetLpResult itself
    setup();
    Card_Change_Request__c fresh = new Card_Change_Request__c(
      Pledge__c = p.Id,
      LowProfileId__c = 'lp-card-0000000001',
      Status__c = 'Pending',
      Link_Version__c = 1
    );
    Card_Change_Request__c late = new Card_Change_Request__c(
      Pledge__c = p.Id,
      LowProfileId__c = 'lp-card-0000000002',
      Status__c = 'Pending',
      Link_Version__c = 1
    );
    insert new List<Card_Change_Request__c>{ fresh, late };
    Test.setCreatedDate(late.Id, Datetime.now().addMinutes(-1));
    CardcomMock.install().always('LowProfile/GetLpResult', 200, CardcomMock.lpSuccess('lp-card-0000000002', 'CARD-x'));
    // No callout here; its log insert must happen before startTest so the next call can call out.
    Map<String, Object> r1 = call(
      'card/status',
      new Map<String, Object>{ 'token' => link('card'), 'lowProfileId' => 'lp-card-0000000001' }
    );
    Test.startTest();
    Map<String, Object> r2 = call(
      'card/status',
      new Map<String, Object>{ 'token' => link('card'), 'lowProfileId' => 'lp-card-0000000002' }
    );
    Test.stopTest();
    Assert.areEqual('Pending', r1.get('status'));
    Assert.areEqual('Completed', r2.get('status'));
    Assert.areEqual('tok-lp-card-0000000002', [SELECT Token__c FROM Opportunity WHERE Id = :p.Id].Token__c);
  }

  @IsTest
  static void cardLimitsAndBadReturnUrl() {
    setup();
    CardcomMock.install().always('LowProfile/Create', 200, CardcomMock.lpCreated('lp-card-0000000009'));
    List<Card_Change_Request__c> five = new List<Card_Change_Request__c>();
    for (Integer i = 0; i < 5; i++)
      five.add(new Card_Change_Request__c(Pledge__c = p.Id, LowProfileId__c = 'lp-old-' + i, Status__c = 'Failed'));
    insert five;
    Map<String, Object> r = call('card', new Map<String, Object>{ 'token' => link('card'), 'returnUrlBase' => TestDataFactory.RETURN_URL });
    Assert.areEqual(429, RestContext.response.statusCode);
    Assert.areEqual('TOO_MANY', r.get('error'));
    delete five;
    r = call('card', new Map<String, Object>{ 'token' => link('card'), 'returnUrlBase' => 'https://evil.example.com/x' });
    Assert.areEqual(400, RestContext.response.statusCode);
    Assert.areEqual('BAD_RETURN_URL', r.get('error'));
    call('card/status', new Map<String, Object>{ 'token' => link('card'), 'lowProfileId' => 'unknown-lp-000' });
    Assert.areEqual(404, RestContext.response.statusCode);
  }

  @IsTest
  static void optionalVerifyOnOpen() {
    // B6.9.6
    setup();
    CardcomService.settingsOverride.Optional_Verify_On_Open__c = true;
    Map<String, Object> r = call('context', new Map<String, Object>{ 'token' => link('amount') });
    Assert.areEqual('VERIFY_REQUIRED', r.get('error'));
    r = call('context', new Map<String, Object>{ 'token' => link('amount'), 'verifyCode' => '0000' });
    Assert.areEqual('VERIFY_FAILED', r.get('error'));
    r = call('context', new Map<String, Object>{ 'token' => link('amount'), 'verifyCode' => '1111' }); // donor phone 0521111111
    Assert.areEqual(200, RestContext.response.statusCode);
    List<Donor_Link_Use__c> bad = new List<Donor_Link_Use__c>();
    for (Integer i = 0; i < 5; i++)
      bad.add(new Donor_Link_Use__c(Pledge__c = p.Id, Result__c = 'Bad_Verify', Used_At__c = Datetime.now()));
    insert bad;
    r = call('context', new Map<String, Object>{ 'token' => link('amount'), 'verifyCode' => '1111' });
    Assert.areEqual('LOCKED', r.get('error'));
  }

  @IsTest
  static void unexpectedErrorsAreInternal() {
    setup();
    TestDataFactory.rest('/services/apexrest/donor/context', 'not json');
    DonorPortalResource.handle();
    Assert.areEqual(500, RestContext.response.statusCode);
  }
}
