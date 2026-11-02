@IsTest
private class CardChangeServiceTest {
  static Opportunity p;
  static Card_Change_Request__c ccr;

  static void setup() {
    TestDataFactory.chargeEngine(TestDataFactory.WED_0800);
    p = TestDataFactory.activePledges(1, 'OnceDaily')[0];
    update new Opportunity(Id = p.Id, Last4__c = '1111');
    ccr = new Card_Change_Request__c(Pledge__c = p.Id, LowProfileId__c = 'lp-card-0000000001', Status__c = 'Pending', Link_Version__c = 1);
    insert ccr;
  }

  @IsTest
  static void successfulReplacementKeepsHistory() {
    setup();
    String oldToken = [SELECT Token__c FROM Opportunity WHERE Id = :p.Id].Token__c;
    Map<String, Object> lp = CardcomMock.lpSuccess('lp-card-0000000001', 'CARD-x');
    lp.put('TranzactionInfo', new Map<String, Object>{ 'Last4CardDigitsString' => '2222' });
    Assert.areEqual('Completed', CardChangeService.complete('lp-card-0000000001', lp));
    Opportunity after = [SELECT Token__c, Last4__c, CardExpirationMMYY__c FROM Opportunity WHERE Id = :p.Id];
    Assert.areEqual('tok-lp-card-0000000001', after.Token__c);
    Assert.areEqual('2222', after.Last4__c);
    Pledge_Card_History__c h = [SELECT Token__c, Last4__c, Replaced_By_Request__c FROM Pledge_Card_History__c];
    Assert.areEqual(oldToken, h.Token__c);
    Assert.areEqual('1111', h.Last4__c);
    Assert.areEqual(ccr.Id, h.Replaced_By_Request__c);
    Pledge_Change_Log__c l = [SELECT Change_Type__c, Old_Value__c, New_Value__c FROM Pledge_Change_Log__c WHERE Change_Type__c = 'Card'];
    Assert.areEqual('****1111', l.Old_Value__c);
    Assert.areEqual('****2222', l.New_Value__c);
    Assert.areEqual('Completed', CardChangeService.complete('lp-card-0000000001', lp), 'idempotent');
    Assert.areEqual(1, [SELECT COUNT() FROM Pledge_Card_History__c]);
  }

  @IsTest
  static void failedReplacementKeepsTheOldCard() {
    // TC28
    setup();
    String oldToken = [SELECT Token__c FROM Opportunity WHERE Id = :p.Id].Token__c;
    Assert.areEqual('Pending', CardChangeService.complete('lp-card-0000000001', CardcomMock.lpPending('lp-card-0000000001')));
    Assert.areEqual('Failed', CardChangeService.complete('lp-card-0000000001', CardcomMock.lpFailed('lp-card-0000000001')));
    Assert.areEqual(oldToken, [SELECT Token__c FROM Opportunity WHERE Id = :p.Id].Token__c);
    Assert.areEqual('Failed', [SELECT Status__c FROM Card_Change_Request__c].Status__c);
    Assert.areEqual('Failed', CardChangeService.complete('no-such-lp-000', CardcomMock.lpFailed('x')));
  }

  @IsTest
  static void staleRequestsExpire() {
    setup();
    Test.setCreatedDate(ccr.Id, Datetime.now().addMinutes(-31));
    CardChangeService.expireStale();
    Assert.areEqual('Expired', [SELECT Status__c FROM Card_Change_Request__c].Status__c);
    Assert.isTrue(CardChangeService.isCardChange('CARD-abc'));
    Assert.isFalse(CardChangeService.isCardChange('SIGNUP-abc'));
  }
}
