@IsTest
private class MonthlyReceiptTest {
  static final Date OCT = Date.newInstance(2026, 10, 1);
  static final String DOC_PATH = 'Documents/CreateDocument';
  static Integer dealSeq = 7000;

  static void setup() {
    TestDataFactory.chargeEngine(TestDataFactory.WED_0800);
  }

  /** A Success charge of a pledge, sent on runDate (inserted). */
  static Charge__c success(Opportunity p, Date runDate, String slot, Decimal amount) {
    Charge__c c = TestDataFactory.charge(p, runDate, slot);
    c.Status__c = 'Success';
    c.Amount__c = amount;
    String tid = String.valueOf(dealSeq++);
    c.Cardcom_Tranzaction_Id__c = tid;
    c.Cardcom_Deal_Number__c = tid;
    c.Executed_At__c = Datetime.newInstance(runDate, Time.newInstance(8, 0, 0, 0));
    insert c;
    return c;
  }

  static Monthly_Receipt__c receipt(Id contactId, String status, Decimal total, Integer attempts) {
    Monthly_Receipt__c r = new Monthly_Receipt__c(
      Contact__c = contactId,
      Period_Month__c = OCT,
      Receipt_Key__c = contactId + '-202610',
      Status__c = status,
      Total_Amount__c = total,
      Charge_Count__c = 2,
      Deal_Numbers__c = '[7000,7001]',
      Attempt_Count__c = attempts
    );
    insert r;
    return r;
  }

  static Map<String, Object> issued(Long docNumber) {
    return new Map<String, Object>{
      'ResponseCode' => 0,
      'Description' => '',
      'DocumentType' => 'DonationReceipt',
      'DocumentNumber' => docNumber,
      'DocumentUrl' => 'https://secure.cardcom.solutions/api/v11/documents/DownloadDoc/?c=1&code=x'
    };
  }

  /** JSON numbers come back as Integer or Decimal depending on scale. */
  static Integer num(Object v) {
    return Decimal.valueOf(String.valueOf(v)).intValue();
  }

  static void issue() {
    Test.startTest();
    MonthlyReceiptQueueable.start(OCT);
    Test.stopTest();
  }

  // ---------------------------------------------------------------- planner
  @IsTest
  static void twoPledgesOfOneDonorGiveOneReceipt() {
    // TC34
    setup();
    List<Opportunity> ps = TestDataFactory.activePledges(2, 'TwiceDaily');
    Charge__c a = success(ps[0], Date.newInstance(2026, 10, 1), 'AM', 3);
    Charge__c b = success(ps[0], Date.newInstance(2026, 10, 30), 'PM', 3);
    Charge__c c = success(ps[1], Date.newInstance(2026, 10, 31), 'AM', 5);
    Charge__c nov = success(ps[0], Date.newInstance(2026, 11, 1), 'AM', 3); // next month
    Charge__c recon = success(ps[1], Date.newInstance(2026, 10, 2), 'AM', 3);
    recon.Needs_Reconciliation__c = true;
    update recon;
    Charge__c failed = TestDataFactory.charge(ps[1], Date.newInstance(2026, 10, 3), 'AM');
    failed.Status__c = 'Failed';
    insert failed;
    Opportunity other = TestDataFactory.activePledges(1, 'OnceDaily')[0];
    success(other, Date.newInstance(2026, 10, 15), 'AM', 10);

    Test.startTest();
    Database.executeBatch(new MonthlyReceiptPlanner(Date.newInstance(2026, 10, 17)), 200);
    Test.stopTest();

    Assert.areEqual(2, [SELECT COUNT() FROM Monthly_Receipt__c]);
    Monthly_Receipt__c r = [
      SELECT Id, Receipt_Key__c, Period_Month__c, Status__c, Total_Amount__c, Charge_Count__c, Deal_Numbers__c
      FROM Monthly_Receipt__c
      WHERE Contact__c = :ps[0].Donor_Contact__c
    ];
    Assert.areEqual(ps[0].Donor_Contact__c + '-202610', r.Receipt_Key__c);
    Assert.areEqual(OCT, r.Period_Month__c);
    Assert.areEqual('Pending', r.Status__c);
    Assert.areEqual(11, r.Total_Amount__c.intValue(), 'both pledges, Success, October, not flagged');
    Assert.areEqual(3, r.Charge_Count__c.intValue());
    Assert.areEqual(3, ((List<Object>) JSON.deserializeUntyped(r.Deal_Numbers__c)).size());
    Assert.areEqual(3, [SELECT COUNT() FROM Charge__c WHERE Monthly_Receipt__c = :r.Id]);
    Assert.isNull([SELECT Monthly_Receipt__c FROM Charge__c WHERE Id = :nov.Id].Monthly_Receipt__c);
    Assert.isNull([SELECT Monthly_Receipt__c FROM Charge__c WHERE Id = :recon.Id].Monthly_Receipt__c);
  }

  @IsTest
  static void donorWithoutChargesGetsNoReceipt() {
    // TC33
    setup();
    TestDataFactory.activePledges(1, 'OnceDaily');
    Test.startTest();
    Database.executeBatch(new MonthlyReceiptPlanner(OCT), 200);
    Test.stopTest();
    Assert.areEqual(0, [SELECT COUNT() FROM Monthly_Receipt__c]);
  }

  @IsTest
  static void issuedReceiptIsNeverReplanned() {
    // TC32 / N78: a late charge after the receipt was issued stays unlinked
    setup();
    Opportunity p = TestDataFactory.activePledges(1, 'OnceDaily')[0];
    Monthly_Receipt__c r = receipt(p.Donor_Contact__c, 'Issued', 6, 0);
    Charge__c late = success(p, Date.newInstance(2026, 10, 20), 'AM', 3);
    CardcomMock m = CardcomMock.install().always(DOC_PATH, 200, issued(1));
    Test.startTest();
    Database.executeBatch(new MonthlyReceiptPlanner(OCT), 200);
    MonthlyReceiptQueueable.start(OCT);
    Test.stopTest();
    Monthly_Receipt__c after = [SELECT Status__c, Total_Amount__c FROM Monthly_Receipt__c WHERE Id = :r.Id];
    Assert.areEqual('Issued', after.Status__c);
    Assert.areEqual(6, after.Total_Amount__c.intValue());
    Assert.isNull([SELECT Monthly_Receipt__c FROM Charge__c WHERE Id = :late.Id].Monthly_Receipt__c);
    Assert.areEqual(0, m.requestsTo(DOC_PATH).size(), 'no second call to Cardcom');
  }

  // ---------------------------------------------------------------- scheduler
  @IsTest
  static void schedulerWindowAndRestDays() {
    setup();
    Assert.areEqual('skipped', MonthlyReceiptScheduler.run(Date.newInstance(2026, 8, 1)), '1st on Shabbat');
    Assert.areEqual('planned', MonthlyReceiptScheduler.run(Date.newInstance(2026, 8, 2)), 'next working day');
    Assert.areEqual('skipped', MonthlyReceiptScheduler.run(Date.newInstance(2026, 11, 11)), 'after the 10th');
    ChargeSettings.overrideValue.Receipt_Day_Of_Month__c = 3;
    Assert.areEqual('skipped', MonthlyReceiptScheduler.run(Date.newInstance(2026, 11, 2)), 'before Receipt_Day_Of_Month__c');
    Opportunity p = TestDataFactory.activePledges(1, 'OnceDaily')[0];
    receipt(p.Donor_Contact__c, 'Issued', 6, 0);
    Test.startTest();
    Assert.areEqual('retried', MonthlyReceiptScheduler.run(Date.newInstance(2026, 11, 3)), 'planned already → retries only');
    Test.stopTest();
  }

  @IsTest
  static void scheduledExecuteAndByName() {
    setup();
    MonthlyReceiptScheduler.todayOverride = Date.newInstance(2026, 11, 11);
    Object job = Type.forName('MonthlyReceiptScheduler').newInstance(); // DonationSetup schedules it by name (N46)
    Assert.isTrue(job instanceof Schedulable);
    ((Schedulable) job).execute(null);
    Assert.areEqual(0, [SELECT COUNT() FROM Monthly_Receipt__c]);
  }

  // ---------------------------------------------------------------- queueable / service
  @IsTest
  static void issuesReceiptWithCashByDefault() {
    // TC31
    setup();
    Opportunity p = TestDataFactory.activePledges(1, 'OnceDaily')[0];
    update new Contact(Id = p.Donor_Contact__c, Donor_Tax_Id__c = '123456782');
    Monthly_Receipt__c r = receipt(p.Donor_Contact__c, 'Pending', 6, 0);
    CardcomMock m = CardcomMock.install().always(DOC_PATH, 200, issued(50123));
    issue();

    Monthly_Receipt__c after = [
      SELECT
        Status__c,
        Cardcom_Document_Number__c,
        Cardcom_Document_Type__c,
        Cardcom_Document_Url__c,
        Issued_At__c,
        Attempt_Count__c,
        Email_Sent_To__c,
        Raw_Request__c,
        Error_Code__c
      FROM Monthly_Receipt__c
      WHERE Id = :r.Id
    ];
    Assert.areEqual('Issued', after.Status__c);
    Assert.areEqual('50123', after.Cardcom_Document_Number__c);
    Assert.areEqual('DonationReceipt', after.Cardcom_Document_Type__c);
    Assert.isNotNull(after.Cardcom_Document_Url__c);
    Assert.isNotNull(after.Issued_At__c);
    Assert.areEqual(1, after.Attempt_Count__c.intValue());
    Assert.isNull(after.Error_Code__c);
    Assert.isNotNull(after.Email_Sent_To__c);

    Map<String, Object> body = m.lastBody(DOC_PATH);
    Map<String, Object> doc = (Map<String, Object>) body.get('Document');
    Assert.areEqual(6, num(body.get('Cash')), 'Cash = total (B5.10 default)');
    Assert.isFalse(body.containsKey('DealNumbers'));
    Assert.isFalse(body.containsKey('TerminalNumber'), 'CreateDocument has no TerminalNumber (B5.7)');
    Assert.areEqual('{!$Credential.Cardcom_EC.ApiName}', body.get('ApiName'));
    Assert.areEqual('{!$Credential.Cardcom_EC.ApiPassword}', body.get('ApiPassword'));
    Assert.areEqual('DonationReceipt', doc.get('DocumentTypeToCreate'));
    Assert.areEqual(p.Donor_Contact__c + '-202610', doc.get('ExternalId'));
    Assert.areEqual('he', doc.get('Languge'));
    Assert.areEqual(1, doc.get('ISOCoinID'));
    Assert.areEqual(true, doc.get('IsSendByEmail'));
    Assert.areEqual('Avi Cohen', doc.get('Name'));
    Assert.areEqual('123456782', doc.get('TaxId'));
    Assert.areEqual('0521111111', doc.get('Mobile'));
    Assert.areEqual('קבלה מרוכזת על תרומות אוקטובר 2026 (2 חיובים)', doc.get('Comments'));
    List<Object> products = (List<Object>) doc.get('Products');
    Assert.areEqual(1, products.size(), 'one line = the monthly total');
    Map<String, Object> line = (Map<String, Object>) products[0];
    Assert.areEqual('תרומות חודש אוקטובר 2026', line.get('Description'));
    Assert.areEqual(1, line.get('Quantity'));
    Assert.areEqual(6, num(line.get('UnitCost')));
    Assert.areEqual(6, num(line.get('TotalLineCost')));
    Assert.isFalse(after.Raw_Request__c.contains('cardcom26'), 'no secrets stored');
  }

  @IsTest
  static void dealNumbersReplaceCashWhenTheFlagIsOn() {
    setup();
    CardcomService.settingsOverride.Receipt_Link_Deal_Numbers__c = true;
    Opportunity p = TestDataFactory.activePledges(1, 'OnceDaily')[0];
    receipt(p.Donor_Contact__c, 'Pending', 6, 0);
    CardcomMock m = CardcomMock.install().always(DOC_PATH, 200, issued(50124));
    issue();
    Map<String, Object> body = m.lastBody(DOC_PATH);
    Assert.isFalse(body.containsKey('Cash'));
    List<Object> deals = (List<Object>) body.get('DealNumbers');
    Assert.areEqual(2, deals.size());
    Assert.areEqual(7000, ((Map<String, Object>) deals[0]).get('DealNumber'));
    Assert.isFalse(((Map<String, Object>) body.get('Document')).containsKey('DealNumbers'), 'top level, not inside Document');
  }

  @IsTest
  static void taxIdAndEmailFallBackToThePledge() {
    // E16: the Contact's values are blank → newest pledge's values, picked in Apex
    setup();
    Opportunity p = TestDataFactory.activePledges(1, 'OnceDaily')[0];
    update new Contact(Id = p.Donor_Contact__c, Email = null);
    update new Opportunity(Id = p.Id, Donor_Tax_Id__c = '123456782', Donor_Email__c = 'pledge@example.com');
    receipt(p.Donor_Contact__c, 'Pending', 6, 0);
    CardcomMock m = CardcomMock.install().always(DOC_PATH, 200, issued(50125));
    issue();
    Map<String, Object> doc = (Map<String, Object>) m.lastBody(DOC_PATH).get('Document');
    Assert.areEqual('123456782', doc.get('TaxId'));
    Assert.areEqual('pledge@example.com', doc.get('Email'));
  }

  @IsTest
  static void noEmailAnywhereFailsWithoutCallingCardcom() {
    setup();
    Opportunity p = TestDataFactory.activePledges(1, 'OnceDaily')[0];
    update new Contact(Id = p.Donor_Contact__c, Email = null);
    update new Opportunity(Id = p.Id, Donor_Email__c = null);
    Monthly_Receipt__c r = receipt(p.Donor_Contact__c, 'Pending', 6, 0);
    CardcomMock m = CardcomMock.install().always(DOC_PATH, 200, issued(1));
    issue();
    Monthly_Receipt__c after = [SELECT Status__c, Error_Code__c, Attempt_Count__c FROM Monthly_Receipt__c WHERE Id = :r.Id];
    Assert.areEqual('Failed', after.Status__c);
    Assert.areEqual('NO_EMAIL', after.Error_Code__c);
    Assert.areEqual(5, after.Attempt_Count__c.intValue(), 'final');
    Assert.areEqual(0, m.requestsTo(DOC_PATH).size());
  }

  @IsTest
  static void validationErrorIsFinal() {
    // TC35
    setup();
    Opportunity p = TestDataFactory.activePledges(1, 'OnceDaily')[0];
    Monthly_Receipt__c r = receipt(p.Donor_Contact__c, 'Pending', 6, 0);
    CardcomMock.install()
      .always(
        DOC_PATH,
        200,
        new Map<String, Object>{ 'ResponseCode' => 6311, 'Description' => 'Total items not equal to some form of payment' }
      );
    issue();
    Monthly_Receipt__c after = [
      SELECT Status__c, Error_Code__c, Error_Message__c, Attempt_Count__c
      FROM Monthly_Receipt__c
      WHERE Id = :r.Id
    ];
    Assert.areEqual('Failed', after.Status__c);
    Assert.areEqual('6311', after.Error_Code__c);
    Assert.areEqual(5, after.Attempt_Count__c.intValue(), 'no automatic retry');
  }

  @IsTest
  static void zeroWithoutDocumentNumberNeedsVerification() {
    setup();
    Opportunity p = TestDataFactory.activePledges(1, 'OnceDaily')[0];
    Monthly_Receipt__c r = receipt(p.Donor_Contact__c, 'Pending', 6, 0);
    CardcomMock.install().always(DOC_PATH, 200, new Map<String, Object>{ 'ResponseCode' => 0, 'DocumentNumber' => 0 });
    issue();
    Assert.areEqual('Needs_Verification', [SELECT Status__c FROM Monthly_Receipt__c WHERE Id = :r.Id].Status__c);
  }

  @IsTest
  static void timeoutIsRetryableButNotWithin12Hours() {
    setup();
    Opportunity p = TestDataFactory.activePledges(1, 'OnceDaily')[0];
    Monthly_Receipt__c r = receipt(p.Donor_Contact__c, 'Pending', 6, 0);
    CardcomMock.install().always(DOC_PATH, 200, CardcomMock.TIMEOUT);
    issue();
    Monthly_Receipt__c after = [
      SELECT Status__c, Error_Code__c, Attempt_Count__c, Last_Attempt_At__c
      FROM Monthly_Receipt__c
      WHERE Id = :r.Id
    ];
    Assert.areEqual('Failed', after.Status__c);
    Assert.areEqual('TIMEOUT', after.Error_Code__c);
    Assert.areEqual(1, after.Attempt_Count__c.intValue(), 'retryable: ExternalId makes the re-send safe');
    MonthlyReceiptQueueable.start(OCT); // same day: not picked again
    Assert.areEqual('Failed', [SELECT Status__c FROM Monthly_Receipt__c WHERE Id = :r.Id].Status__c);
  }

  @IsTest
  static void maxAttemptsReachedMeansNoSendAndAnAlert() {
    setup();
    Opportunity p = TestDataFactory.activePledges(1, 'OnceDaily')[0];
    Monthly_Receipt__c r = receipt(p.Donor_Contact__c, 'Failed', 6, 5);
    CardcomMock m = CardcomMock.install().always(DOC_PATH, 200, issued(1));
    issue();
    Assert.areEqual('Failed', [SELECT Status__c FROM Monthly_Receipt__c WHERE Id = :r.Id].Status__c);
    Assert.areEqual(0, m.requestsTo(DOC_PATH).size());
    Assert.isNotNull(Alert_State__c.getOrgDefaults().Receipt_Failures_Sent_On__c, 'receiptFailures() alert sent');
  }

  @IsTest
  static void configErrorStopsTheBatch() {
    setup();
    Opportunity a = TestDataFactory.activePledges(1, 'OnceDaily')[0];
    Opportunity b = TestDataFactory.activePledges(1, 'OnceDaily')[0];
    receipt(a.Donor_Contact__c, 'Pending', 6, 0);
    receipt(b.Donor_Contact__c, 'Pending', 6, 0);
    CardcomMock m = CardcomMock.install().always(DOC_PATH, 401, 'Invalid username');
    issue();
    Assert.areEqual(1, m.requestsTo(DOC_PATH).size(), 'the second receipt is not attempted');
    Assert.areEqual(2, [SELECT COUNT() FROM Monthly_Receipt__c WHERE Status__c = 'Failed']);
    Assert.areEqual(1, [SELECT COUNT() FROM Monthly_Receipt__c WHERE Error_Code__c = 'HTTP_401' AND Attempt_Count__c = 1]);
    Assert.isNotNull(Alert_State__c.getOrgDefaults().Config_Error_Sent_On__c);
  }

  @IsTest
  static void staleProcessingBecomesFailed() {
    setup();
    Opportunity p = TestDataFactory.activePledges(1, 'OnceDaily')[0];
    Monthly_Receipt__c r = receipt(p.Donor_Contact__c, 'Processing', 6, 1);
    MonthlyReceiptQueueable.staleMinutes = -1;
    MonthlyReceiptQueueable.resetStale();
    Monthly_Receipt__c after = [SELECT Status__c, Error_Code__c FROM Monthly_Receipt__c WHERE Id = :r.Id];
    Assert.areEqual('Failed', after.Status__c);
    Assert.areEqual('STALE', after.Error_Code__c);
  }

  static MonthlyReceiptRetryAction.Request request(Id receiptId) {
    MonthlyReceiptRetryAction.Request q = new MonthlyReceiptRetryAction.Request();
    q.receiptId = receiptId;
    return q;
  }

  @IsTest
  static void retryActionReArmsAndResends() {
    setup();
    Opportunity p = TestDataFactory.activePledges(1, 'OnceDaily')[0];
    Opportunity q = TestDataFactory.activePledges(1, 'OnceDaily')[0];
    Monthly_Receipt__c failed = receipt(p.Donor_Contact__c, 'Failed', 6, 5);
    Monthly_Receipt__c done = receipt(q.Donor_Contact__c, 'Issued', 6, 1);
    CardcomMock.install().always(DOC_PATH, 200, issued(50126));
    Test.startTest();
    List<MonthlyReceiptRetryAction.Result> res = MonthlyReceiptRetryAction.retry(
      new List<MonthlyReceiptRetryAction.Request>{ request(failed.Id), request(done.Id) }
    );
    Test.stopTest();
    Assert.isTrue(res[0].ok);
    Assert.isFalse(res[1].ok, 'only Failed / Needs_Verification');
    Monthly_Receipt__c after = [
      SELECT Status__c, Attempt_Count__c, Cardcom_Document_Number__c
      FROM Monthly_Receipt__c
      WHERE Id = :failed.Id
    ];
    Assert.areEqual('Issued', after.Status__c);
    Assert.areEqual('50126', after.Cardcom_Document_Number__c);
    Assert.areEqual(1, after.Attempt_Count__c.intValue());
  }

  @IsTest
  static void hebrewMonthNames() {
    Assert.areEqual('ינואר', MonthlyReceiptService.monthNameHe(1));
    Assert.areEqual('דצמבר', MonthlyReceiptService.monthNameHe(12));
  }
}
