@IsTest
private class DonationPledgeResourceTest {
  static Map<String, Object> body(String lp) {
    return new Map<String, Object>{
      'lowProfileId' => lp,
      'firstName' => 'ישראל',
      'lastName' => 'ישראלי',
      'email' => 'Donor@Example.com',
      'phone' => '+972-52-123-4567',
      'taxId' => '18',
      'amount' => 3,
      'frequency' => 'TwiceDaily',
      'termsAccepted' => true,
      'clientIp' => '1.2.3.4'
    };
  }

  @IsTest
  static void validationListsBadFields() {
    TestDataFactory.settings();
    TestDataFactory.rest('/services/apexrest/donations/pledge', new Map<String, Object>{ 'taxId' => '123456789', 'amount' => 3.123 });
    DonationPledgeResource.submit();
    Assert.areEqual(400, RestContext.response.statusCode);
    Map<String, Object> out = TestDataFactory.responseJson();
    Assert.areEqual('VALIDATION', out.get('error'));
    Set<String> fields = new Set<String>();
    for (Object f : (List<Object>) out.get('fields'))
      fields.add((String) f);
    Assert.isTrue(
      fields.containsAll(
        new Set<String>{ 'firstName', 'lastName', 'email', 'phone', 'taxId', 'frequency', 'termsAccepted', 'lowProfileId' }
      ),
      String.valueOf(fields)
    );
    Assert.isTrue(DonationPledgeResource.validate(body('lp-0000000001')).isEmpty());
    Map<String, Object> high = body('lp-0000000001');
    high.put('amount', 51);
    Assert.areEqual(new List<String>{ 'shacharitAmount', 'minchaAmount' }, DonationPledgeResource.validate(high), 'legacy amount');
    Map<String, Object> mincha = body('lp-0000000001');
    mincha.remove('amount');
    mincha.put('frequency', 'MinchaOnly');
    Assert.areEqual(new List<String>{ 'minchaAmount' }, DonationPledgeResource.validate(mincha));
    mincha.put('minchaAmount', 4);
    Assert.isTrue(DonationPledgeResource.validate(mincha).isEmpty());
  }

  @IsTest
  static void storesTheAmountOfEachPrayer() {
    // D36
    TestDataFactory.settings();
    Map<String, Object> b = body('lp-0000000003');
    b.remove('amount');
    b.put('shacharitAmount', 2);
    b.put('minchaAmount', 5);
    TestDataFactory.rest('/services/apexrest/donations/pledge', b);
    DonationPledgeResource.submit();
    Assert.areEqual(200, RestContext.response.statusCode, RestContext.response.responseBody.toString());
    Opportunity p = [SELECT Charge_Amount__c, Mincha_Amount__c FROM Opportunity WHERE LowProfileId__c = 'lp-0000000003'];
    Assert.areEqual(2, p.Charge_Amount__c.intValue());
    Assert.areEqual(5, p.Mincha_Amount__c.intValue());

    b = body('lp-0000000004');
    b.remove('amount');
    b.put('frequency', 'MinchaOnly');
    b.put('shacharitAmount', null);
    b.put('minchaAmount', 6);
    TestDataFactory.rest('/services/apexrest/donations/pledge', b);
    DonationPledgeResource.submit();
    p = [SELECT Charge_Amount__c, Mincha_Amount__c FROM Opportunity WHERE LowProfileId__c = 'lp-0000000004'];
    Assert.isNull(p.Charge_Amount__c, 'Mincha only: no Shacharit amount');
    Assert.areEqual(6, p.Mincha_Amount__c.intValue());
  }

  @IsTest
  static void concurrentDuplicateInsertIsAnsweredAsAlreadyUsed() {
    TestDataFactory.settings();
    // A parallel submit inserted the same LowProfileId after our SELECT: the Unique field rejects our insert.
    insert MicroPledges.newPending('lp-0000000099');
    Assert.isFalse(DonationPledgeResource.insertUnlessDuplicate(MicroPledges.newPending('LP-0000000099')), 'duplicate (case-insensitive)');
    Assert.areEqual(1, [SELECT COUNT() FROM Opportunity WHERE LowProfileId__c = 'lp-0000000099'], 'no second pledge');
    Assert.isTrue(DonationPledgeResource.insertUnlessDuplicate(MicroPledges.newPending('lp-0000000100')));
    Opportunity broken = MicroPledges.newPending('lp-0000000101');
    broken.StageName = null;
    try {
      DonationPledgeResource.insertUnlessDuplicate(broken);
      Assert.fail('other insert errors are not swallowed');
    } catch (CardcomService.CardcomException e) {
      Assert.isTrue(e.getMessage().startsWith('Pledge insert failed'));
    }
  }

  @IsTest
  static void createsPendingPledgeOpportunity() {
    TestDataFactory.settings();
    TestDataFactory.rest('/services/apexrest/donations/pledge', body('lp-0000000001'));
    DonationPledgeResource.submit();
    Assert.areEqual(200, RestContext.response.statusCode, RestContext.response.responseBody.toString());
    Map<String, Object> out = TestDataFactory.responseJson();
    Assert.areEqual('Pending_Verification', out.get('status'));
    Id pledgeId = (Id) out.get('pledgeId');
    Opportunity p = [
      SELECT
        Type,
        Name,
        StageName,
        CloseDate,
        Charge_Amount__c,
        Frequency__c,
        Donor_Email__c,
        Donor_Phone__c,
        Donor_Tax_Id__c,
        Donor_Submitted__c,
        Pledge_Number__c,
        Client_Ip__c
      FROM Opportunity
      WHERE Id = :pledgeId
    ];
    Assert.areEqual(MicroPledges.TYPE, p.Type);
    Assert.areEqual(3.00, p.Charge_Amount__c);
    Assert.areEqual('TwiceDaily', p.Frequency__c);
    Assert.areEqual('donor@example.com', p.Donor_Email__c);
    Assert.areEqual('0521234567', p.Donor_Phone__c);
    Assert.areEqual('000000018', p.Donor_Tax_Id__c);
    Assert.isTrue(p.Donor_Submitted__c);
    Assert.areEqual(Date.today(), p.CloseDate);
    Assert.areEqual(MicroPledges.fullName('ישראלי', 'ישראל', p.Pledge_Number__c), p.Name);
    Assert.isTrue(p.Pledge_Number__c.startsWith('PLG-'));
  }

  @IsTest
  static void replayIsRejected() {
    TestDataFactory.settings();
    TestDataFactory.rest('/services/apexrest/donations/pledge', body('lp-0000000001'));
    DonationPledgeResource.submit();
    TestDataFactory.rest('/services/apexrest/donations/pledge', body('lp-0000000001'));
    DonationPledgeResource.submit();
    Assert.areEqual(400, RestContext.response.statusCode);
    Assert.areEqual('LP_ALREADY_USED', TestDataFactory.responseJson().get('error'));
    Assert.areEqual(1, [SELECT COUNT() FROM Opportunity WHERE LowProfileId__c = 'lp-0000000001']);
  }

  @IsTest
  static void webhookFirstThenSubmitActivatesOnce() {
    TestDataFactory.settings();
    ContactMatcher.skipDuplicateRules = true;
    Opportunity verified = TestDataFactory.withToken(TestDataFactory.pledge('lp-0000000002'));
    insert verified;
    TestDataFactory.rest('/services/apexrest/donations/pledge', body('lp-0000000002'));
    Test.startTest();
    DonationPledgeResource.submit();
    Test.stopTest(); // runs PledgeActivationJob
    Opportunity p = [
      SELECT StageName, Donor_Contact__c, Match_Method__c, Activated_At__c, Start_Date__c
      FROM Opportunity
      WHERE Id = :verified.Id
    ];
    Assert.areEqual('Active', p.StageName);
    Assert.isNotNull(p.Donor_Contact__c);
    Assert.areEqual('New', p.Match_Method__c);
    Assert.areEqual(Date.today(), p.Start_Date__c);
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM OpportunityContactRole WHERE OpportunityId = :verified.Id AND Role = 'Donor' AND IsPrimary = TRUE]
    );
    Assert.isFalse(PledgeActivationService.tryActivate(verified.Id), 'second activation is a no-op');
  }

  @IsTest
  static void unexpectedErrorReturnsInternal() {
    TestDataFactory.settings();
    TestDataFactory.rest('/services/apexrest/donations/pledge', 'not json');
    DonationPledgeResource.submit();
    Assert.areEqual(500, RestContext.response.statusCode);
    Assert.areEqual('INTERNAL', TestDataFactory.responseJson().get('error'));
  }

  @IsTest
  static void storesTheTerminalTheCardPageWasOpenedOn() {
    // D39
    TestDataFactory.settings().Secondary_Terminal_Number__c = 2002;
    Map<String, Object> diners = body('lp-0000000001');
    diners.put('terminal', 'Secondary');
    TestDataFactory.rest('/services/apexrest/donations/pledge', diners);
    DonationPledgeResource.submit();
    Assert.areEqual(200, RestContext.response.statusCode, RestContext.response.responseBody.toString());
    TestDataFactory.rest('/services/apexrest/donations/pledge', body('lp-0000000002'));
    DonationPledgeResource.submit();
    Map<String, String> byLp = new Map<String, String>();
    for (Opportunity o : [SELECT LowProfileId__c, Cardcom_Terminal__c FROM Opportunity])
      byLp.put(o.LowProfileId__c, o.Cardcom_Terminal__c);
    Assert.areEqual('Secondary', byLp.get('lp-0000000001'));
    Assert.areEqual('Primary', byLp.get('lp-0000000002'));

    CardcomService.settings().Secondary_Terminal_Number__c = null; // one terminal: the request can't choose another
    Map<String, Object> ignored = body('lp-0000000003');
    ignored.put('terminal', 'Secondary');
    TestDataFactory.rest('/services/apexrest/donations/pledge', ignored);
    DonationPledgeResource.submit();
    Assert.areEqual('Primary', [SELECT Cardcom_Terminal__c FROM Opportunity WHERE LowProfileId__c = 'lp-0000000003'].Cardcom_Terminal__c);
  }
}
