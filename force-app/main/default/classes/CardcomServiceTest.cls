@IsTest
private class CardcomServiceTest {
  @IsTest
  static void createTokenLowProfileSendsB51BodyWithCredentialPlaceholders() {
    TestDataFactory.settings();
    CardcomMock m = CardcomMock.install().enqueue('LowProfile/Create', 200, CardcomMock.lpCreated('lp-0000000001'));
    Test.startTest();
    Map<String, Object> r = CardcomService.createTokenLowProfile('SIGNUP-abc', TestDataFactory.RETURN_URL, 'הוראת תרומה יומית');
    Test.stopTest();
    Assert.areEqual('lp-0000000001', r.get('LowProfileId'));
    HttpRequest req = m.requestsTo('LowProfile/Create')[0];
    Assert.areEqual('callout:Cardcom/api/v11/LowProfile/Create', req.getEndpoint());
    Assert.isTrue(req.getBody().contains('{!$Credential.Cardcom_EC.ApiName}'), 'ApiName merge field must be sent unchanged (B3.1)');
    Map<String, Object> b = m.lastBody('LowProfile/Create');
    Assert.areEqual('CreateTokenOnly', b.get('Operation'));
    Assert.areEqual(1001, b.get('TerminalNumber'));
    Assert.areEqual(TestDataFactory.RETURN_URL + '?s=ok', b.get('SuccessRedirectUrl'));
    Assert.areEqual(CardcomService.settings().Webhook_Url__c, b.get('WebHookUrl'));
    Assert.areEqual(2, ((Map<String, Object>) b.get('AdvancedDefinition')).get('JValidateType'));
    Assert.isFalse(b.containsKey('Document'), 'No Document block when creating a token (B5.1)');
  }

  @IsTest
  static void createTokenLowProfileFailsOnNonZeroCode() {
    TestDataFactory.settings();
    CardcomMock.install().enqueue('LowProfile/Create', 200, new Map<String, Object>{ 'ResponseCode' => 5, 'Description' => 'bad' });
    try {
      CardcomService.createTokenLowProfile('SIGNUP-abc', TestDataFactory.RETURN_URL, 'x');
      Assert.fail('expected CardcomException');
    } catch (CardcomService.CardcomException e) {
      Assert.isTrue(e.getMessage().startsWith('LP_CREATE:5'), e.getMessage());
    }
  }

  @IsTest
  static void httpErrorCarriesStatus() {
    TestDataFactory.settings();
    CardcomMock.install().enqueue('LowProfile/GetLpResult', 401, '{"ResponseCode":401,"Description":"Invalid username"}');
    try {
      CardcomService.getLpResult('lp-0000000001');
      Assert.fail('expected CardcomHttpException');
    } catch (CardcomService.CardcomHttpException e) {
      Assert.areEqual(401, e.status);
    }
  }

  @IsTest
  static void cardFromParsesTokenInfo() {
    Map<String, Object> lp = CardcomMock.lpSuccess('lp-0000000001', 'SIGNUP-x');
    CardcomService.CardData d = CardcomService.cardFrom(lp);
    Assert.areEqual('tok-lp-0000000001', d.token);
    Assert.areEqual('0928', d.expMMYY);
    Assert.areEqual(Date.newInstance(2030, 12, 31), d.tokenExpiry);
    Assert.isNull(d.last4, 'CreateTokenOnly has no TranzactionInfo (B5.3)');

    lp.put('TranzactionInfo', new Map<String, Object>{ 'Last4CardDigitsString' => '1234' });
    Assert.areEqual('1234', CardcomService.cardFrom(lp).last4);
    Assert.isNull(CardcomService.cardFrom(CardcomMock.lpFailed('lp-0000000001')));
    Assert.areEqual(-1, CardcomService.code(null));
    Assert.areEqual(5117, CardcomService.code(CardcomMock.lpPending('x')));
  }

  @IsTest
  static void chargeTokenBodyFollowsB54() {
    TestDataFactory.settings();
    CardcomMock m = CardcomMock.install().enqueue('Transactions/Transaction', 200, new Map<String, Object>{ 'ResponseCode' => 0 });
    CardcomService.chargeToken('tok', '0928', 3, 'PLG-x-20261104-AM-A1');
    Map<String, Object> b = m.lastBody('Transactions/Transaction');
    Assert.areEqual('PLG-x-20261104-AM-A1', b.get('ExternalUniqTranId'));
    Assert.areEqual(true, b.get('ExternalUniqUniqTranIdResponse'));
    Assert.areEqual(false, ((Map<String, Object>) b.get('Advanced')).get('SendNote'));
    Assert.isFalse(b.containsKey('Document'), 'No Document block in a charge (B5.4)');
  }

  @IsTest
  static void findSuccessByExternalIdOnlyReturnsRealTransactions() {
    TestDataFactory.settings();
    CardcomMock.install()
      .enqueue('Transactions/GetTransactionByExternalUniqTran', 200, new Map<String, Object>{ 'ResponseCode' => 0, 'TranzactionId' => 987 })
      .enqueue('Transactions/GetTransactionByExternalUniqTran', 200, new Map<String, Object>{ 'ResponseCode' => 0, 'TranzactionId' => 0 });
    Assert.isNotNull(CardcomService.findSuccessByExternalId('k1'));
    Assert.isNull(CardcomService.findSuccessByExternalId('k2'));
  }

  @IsTest
  static void listTransactionsParsesRows() {
    TestDataFactory.settings();
    CardcomMock m = CardcomMock.install()
      .enqueue(
        'Transactions/ListTransactions',
        200,
        new Map<String, Object>{
          'ResponseCode' => 0,
          'Tranzactions' => new List<Object>{
            new Map<String, Object>{ 'TranzactionId' => 11, 'Amount' => 3, 'ResponseCode' => 0, 'DealType' => 'Regular' },
            new Map<String, Object>{ 'TranzactionId' => 12, 'Amount' => 3, 'ResponseCode' => 4, 'IsRefund' => true }
          }
        }
      )
      .enqueue('Transactions/ListTransactions', 200, new Map<String, Object>{ 'ResponseCode' => 1, 'Description' => 'err' });
    List<CardcomService.TxnSummary> rows = CardcomService.listTransactions(Date.newInstance(2026, 11, 4), 1, 1000);
    Assert.areEqual(2, rows.size());
    Assert.isTrue(rows[0].isSuccess);
    Assert.isTrue(rows[1].isRefundOrCancel);
    Assert.areEqual('04112026', m.lastBody('Transactions/ListTransactions').get('FromDate'));
    try {
      CardcomService.listTransactions(Date.today(), 1, 1000);
      Assert.fail('expected CardcomException');
    } catch (CardcomService.CardcomException e) {
      Assert.isTrue(e.getMessage().startsWith('LIST:1'));
    }
  }

  @IsTest
  static void createDocumentAddsCredentialPlaceholders() {
    TestDataFactory.settings();
    CardcomMock m = CardcomMock.install().enqueue('Documents/CreateDocument', 200, new Map<String, Object>{ 'ResponseCode' => 0 });
    CardcomService.createDocument(new Map<String, Object>{ 'Document' => new Map<String, Object>() });
    Map<String, Object> b = m.lastBody('Documents/CreateDocument');
    Assert.areEqual('{!$Credential.Cardcom_EC.ApiPassword}', b.get('ApiPassword'));
  }

  @IsTest
  static void redactRemovesSecrets() {
    Map<String, Object> lp = CardcomMock.lpSuccess('lp-0000000001', 'SIGNUP-x');
    lp.put('ApiPassword', 'secret');
    String s = CardcomService.redact(lp);
    Assert.isFalse(s.contains('tok-lp-0000000001'), 'token must be removed');
    Assert.isFalse(s.contains('secret'), 'password must be removed');
    Assert.isNull(CardcomService.redact(null));
  }
}
