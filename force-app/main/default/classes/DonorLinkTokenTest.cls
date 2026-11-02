@IsTest
private class DonorLinkTokenTest {
  static Opportunity pledge() {
    TestDataFactory.chargeEngine(TestDataFactory.WED_0800);
    DonorLinkToken.secretOverride = 'current-secret-0123456789abcdef';
    return TestDataFactory.activePledges(1, 'OnceDaily')[0];
  }

  @IsTest
  static void issueAndVerifyWithoutExpiry() {
    Opportunity p = pledge();
    String t = DonorLinkToken.issue(p.Id, 'amount', 1);
    Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(
      EncodingUtil.base64Decode(
          t.substringBefore('.').replace('-', '+').replace('_', '/').rightPad(((t.substringBefore('.').length() + 3) / 4) * 4, '=')
        )
        .toString()
    );
    Assert.areEqual(new Set<String>{ 'p', 'a', 'v' }, payload.keySet(), 'no exp claim, no nonce (D15)');
    Assert.areEqual(p.Id, DonorLinkToken.verify(t, new Set<String>{ 'amount' }, '1.2.3.4').Id);
    Assert.areEqual(1, DonorLinkLog.pending());
  }

  @IsTest
  static void wrongActionVersionSignatureAndStatusAreInvalid() {
    Opportunity p = pledge();
    String amountLink = DonorLinkToken.issue(p.Id, 'amount', 1);
    assertInvalid(amountLink, new Set<String>{ 'card' }); // wrong action
    assertInvalid(amountLink.left(amountLink.length() - 2) + 'xx', new Set<String>{ 'amount' }); // signature
    assertInvalid('no-dot-token', new Set<String>{ 'amount' });
    assertInvalid('x'.repeat(601) + '.y', new Set<String>{ 'amount' });
    update new Opportunity(Id = p.Id, Link_Version__c = 2); // revoked (TC29)
    assertInvalid(amountLink, new Set<String>{ 'amount' });
    String v2 = DonorLinkToken.issue(p.Id, 'amount', 2);
    Assert.areEqual(p.Id, DonorLinkToken.verify(v2, new Set<String>{ 'amount' }, null).Id, 'new link works');
  }

  @IsTest
  static void stoppedPledgeLinkIsInvalid() {
    Opportunity p = pledge();
    String t = DonorLinkToken.issue(p.Id, 'card', 1);
    // Insert-time stage for a second pledge avoids needing the stop permission in this test.
    Opportunity stopped = TestDataFactory.withToken(TestDataFactory.submittedPledge('lp-stopped-0002', 'b@example.com', '0522222222'));
    stopped.StageName = 'Stopped';
    stopped.Stop_Reason__c = 'Donor_Request';
    stopped.Donor_Contact__c = [SELECT Donor_Contact__c FROM Opportunity WHERE Id = :p.Id].Donor_Contact__c;
    insert stopped;
    assertInvalid(DonorLinkToken.issue(stopped.Id, 'card', 1), new Set<String>{ 'card' });
    Assert.areEqual(p.Id, DonorLinkToken.verify(t, new Set<String>{ 'card' }, null).Id);
  }

  @IsTest
  static void previousSecretStillWorksAfterRotation() {
    Opportunity p = pledge();
    String old = DonorLinkToken.issue(p.Id, 'amount', 1);
    DonorLinkToken.previousOverride = 'current-secret-0123456789abcdef';
    DonorLinkToken.secretOverride = 'new-secret-fedcba9876543210';
    Assert.areEqual(p.Id, DonorLinkToken.verify(old, new Set<String>{ 'amount' }, null).Id);
    DonorLinkToken.previousOverride = '';
    assertInvalid(old, new Set<String>{ 'amount' });
  }

  @IsTest
  static void missingSecretRefusesToIssue() {
    DonorLinkToken.secretOverride = '';
    try {
      DonorLinkToken.issue('006000000000000AAA', 'card', 1);
      Assert.fail('expected LinkException');
    } catch (DonorLinkToken.LinkException e) {
      Assert.isTrue(e.getMessage().contains('Secret__c'));
    }
  }

  static void assertInvalid(String token, Set<String> actions) {
    try {
      DonorLinkToken.verify(token, actions, null);
      Assert.fail('expected LinkException for ' + token);
    } catch (DonorLinkToken.LinkException e) {
      Assert.areEqual('invalid', e.getMessage());
    }
  }
}
