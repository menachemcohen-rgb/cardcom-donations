@IsTest
private class ReconciliationJobTest {
  static final Date DAY = Date.newInstance(2026, 11, 5);
  static final String LIST_PATH = 'Transactions/ListTransactions';
  static final String FIND_PATH = 'Transactions/GetTransactionByExternalUniqTran';
  static Opportunity p;

  static void setup() {
    TestDataFactory.chargeEngine(TestDataFactory.WED_0800);
    p = TestDataFactory.activePledges(1, 'TwiceDaily')[0];
  }

  /** A charge of DAY with the given slot (inserted). */
  static Charge__c charge(String slot, String status, String tid, Boolean needsRecon) {
    Charge__c c = TestDataFactory.charge(p, DAY, slot);
    c.Status__c = status;
    c.Cardcom_Tranzaction_Id__c = tid;
    c.Cardcom_Deal_Number__c = tid;
    c.Needs_Reconciliation__c = needsRecon;
    c.Executed_At__c = Datetime.newInstance(DAY, Time.newInstance(8, 0, 0, 0));
    if (status == 'Failed')
      c.Error_Category__c = 'Unknown';
    insert c;
    return c;
  }

  static Map<String, Object> row(Long tid, Decimal amount, Integer code, Boolean refund, String dealType) {
    return new Map<String, Object>{
      'TranzactionId' => tid,
      'Amount' => amount,
      'ResponseCode' => code,
      'IsRefund' => refund,
      'DealType' => dealType,
      'CreateDate' => '2026-11-05T08:00:12'
    };
  }

  static Map<String, Object> page(List<Object> rows) {
    return new Map<String, Object>{ 'ResponseCode' => 0, 'Description' => '', 'Tranzactions' => rows };
  }

  static Map<String, Reconciliation_Issue__c> issuesByType() {
    Map<String, Reconciliation_Issue__c> m = new Map<String, Reconciliation_Issue__c>();
    for (Reconciliation_Issue__c r : [
      SELECT Issue_Type__c, Issue_Key__c, Charge__c, Business_Date__c, Cardcom_Tranzaction_Id__c, Cardcom_Amount__c, SF_Amount__c, Status__c
      FROM Reconciliation_Issue__c
    ])
      m.put(r.Issue_Type__c, r);
    return m;
  }

  static void runFor(Date d) {
    Test.startTest();
    new ReconciliationJob(d).run();
    Test.stopTest();
  }

  @IsTest
  static void eachIssueTypeIsReported() {
    setup();
    Charge__c ok = charge('AM', 'Success', '100', true); // matches → flag cleared, no issue
    Charge__c missing = charge('PM', 'Success', '101', false); // not in Cardcom
    Charge__c amount = TestDataFactory.charge(p, DAY.addDays(-1), 'AM');
    amount.Run_Date__c = DAY;
    amount.Status__c = 'Success';
    amount.Cardcom_Tranzaction_Id__c = '102';
    Charge__c refunded = TestDataFactory.charge(p, DAY.addDays(-1), 'PM');
    refunded.Run_Date__c = DAY;
    refunded.Status__c = 'Success';
    refunded.Cardcom_Tranzaction_Id__c = '103';
    insert new List<Charge__c>{ amount, refunded };
    CardcomMock m = CardcomMock.install()
      .always(
        LIST_PATH,
        200,
        page(
          new List<Object>{
            row(100, 3, 0, false, 'Debit'),
            row(102, 5, 0, false, 'Debit'),
            row(103, 3, 0, false, 'Debit'),
            row(103, 3, 0, true, 'Refund'),
            row(104, 7, 0, false, 'Debit'), // not ours
            row(105, 9, 4, false, 'Debit') // declined: never "missing"
          }
        )
      );
    runFor(DAY);

    Map<String, Reconciliation_Issue__c> is = issuesByType();
    Assert.areEqual(4, [SELECT COUNT() FROM Reconciliation_Issue__c]);
    Assert.areEqual(missing.Id, is.get('Missing_In_Cardcom').Charge__c);
    Assert.areEqual('Missing_In_Cardcom-101', is.get('Missing_In_Cardcom').Issue_Key__c);
    Assert.areEqual(DAY, is.get('Missing_In_Cardcom').Business_Date__c, 'business date = the reconciled day');
    Assert.areEqual(amount.Id, is.get('Amount_Mismatch').Charge__c);
    Assert.areEqual(5, is.get('Amount_Mismatch').Cardcom_Amount__c.intValue());
    Assert.areEqual(3, is.get('Amount_Mismatch').SF_Amount__c.intValue(), 'SF_Amount__c (E2)');
    Assert.areEqual(refunded.Id, is.get('Status_Mismatch').Charge__c);
    Assert.areEqual('104', is.get('Missing_In_Salesforce').Cardcom_Tranzaction_Id__c);
    Assert.isNull(is.get('Missing_In_Salesforce').Charge__c);
    Assert.areEqual('Open', is.get('Missing_In_Salesforce').Status__c);
    Assert.isFalse([SELECT Needs_Reconciliation__c FROM Charge__c WHERE Id = :ok.Id].Needs_Reconciliation__c);

    Map<String, Object> req = m.lastBody(LIST_PATH);
    Assert.areEqual('05112026', req.get('FromDate'));
    Assert.areEqual('05112026', req.get('ToDate'));
    Assert.areEqual('All', req.get('TranStatus'));
    Assert.areEqual(1001, req.get('LimitForTerminal'));
    Assert.isFalse(req.containsKey('TerminalNumber'), 'ListTransactions has no TerminalNumber (B5.6)');
    Assert.isNotNull(Alert_State__c.getOrgDefaults().Reconciliation_Open_Sent_On__c, 'staff alerted (reconciliationOpen)');
  }

  @IsTest
  static void unknownOutcomeConfirmedByCardcomIsFixedAutomatically() {
    setup();
    Charge__c a1 = charge('AM', 'Failed', null, true);
    CardcomMock m = CardcomMock.install()
      .always(LIST_PATH, 200, page(new List<Object>{ row(555, 3, 0, false, 'Debit') }))
      .always(FIND_PATH, 200, TestDataFactory.txSuccess(555, '1234'));
    runFor(DAY);

    Charge__c c = [
      SELECT
        Status__c,
        Cardcom_Tranzaction_Id__c,
        Cardcom_Deal_Number__c,
        Needs_Reconciliation__c,
        Error_Code__c,
        Error_Category__c,
        Is_Final_Failure__c
      FROM Charge__c
      WHERE Id = :a1.Id
    ];
    Assert.areEqual('Success', c.Status__c);
    Assert.areEqual('555', c.Cardcom_Tranzaction_Id__c);
    Assert.areEqual('555', c.Cardcom_Deal_Number__c, 'DealNumber for the monthly receipt');
    Assert.areEqual('RECONCILED', c.Error_Code__c);
    Assert.isNull(c.Error_Category__c);
    Assert.isFalse(c.Needs_Reconciliation__c);
    Assert.areEqual(a1.Attempt_Key__c, m.lastBody(FIND_PATH).get('ExternalUniqTranId'));
    Assert.areEqual(0, [SELECT COUNT() FROM Reconciliation_Issue__c], 'its TranzactionId is not "missing in Salesforce"');
    Assert.areEqual(3, [SELECT Total_Collected__c FROM Opportunity WHERE Id = :p.Id].Total_Collected__c.intValue(), 'roll-ups follow');
  }

  @IsTest
  static void notFoundInCardcomClearsTheFlag() {
    setup();
    Charge__c a1 = charge('AM', 'Failed', null, true);
    CardcomMock.install()
      .always(LIST_PATH, 200, page(new List<Object>()))
      .always(FIND_PATH, 200, new Map<String, Object>{ 'ResponseCode' => 5001, 'Description' => 'not found' });
    runFor(DAY);
    Charge__c c = [SELECT Status__c, Needs_Reconciliation__c FROM Charge__c WHERE Id = :a1.Id];
    Assert.areEqual('Failed', c.Status__c);
    Assert.isFalse(c.Needs_Reconciliation__c);
    Assert.areEqual(0, [SELECT COUNT() FROM Reconciliation_Issue__c]);
    Assert.isNull(Alert_State__c.getOrgDefaults().Reconciliation_Open_Sent_On__c, 'no issues → no alert');
  }

  @IsTest
  static void twoRealChargesForOneLogicalChargeIsADuplicate() {
    setup();
    Charge__c a1 = charge('AM', 'Failed', null, true); // timed out, but Cardcom charged it (555)
    Charge__c a2 = TestDataFactory.charge(p, DAY, 'AM');
    a2.Attempt_Number__c = 2;
    a2.Attempt_Key__c = a2.ExternalUniqTranId__c + '-A2';
    a2.Status__c = 'Success';
    a2.Cardcom_Tranzaction_Id__c = '600';
    insert a2;
    CardcomMock.install()
      .always(LIST_PATH, 200, page(new List<Object>{ row(555, 3, 0, false, 'Debit'), row(600, 3, 0, false, 'Debit') }))
      .always(FIND_PATH, 200, TestDataFactory.txSuccess(555, '1234'));
    runFor(DAY);
    Reconciliation_Issue__c i = [SELECT Issue_Type__c, Issue_Key__c, Charge__c FROM Reconciliation_Issue__c];
    Assert.areEqual('Duplicate_In_Cardcom', i.Issue_Type__c);
    Assert.areEqual('Duplicate_In_Cardcom-555', i.Issue_Key__c);
    Assert.areEqual(a1.Id, i.Charge__c);
    Charge__c c = [SELECT Status__c, Needs_Reconciliation__c FROM Charge__c WHERE Id = :a1.Id];
    Assert.areEqual('Failed', c.Status__c, 'never two Success records for one logical charge');
    Assert.isFalse(c.Needs_Reconciliation__c, 'tracked by the issue');
  }

  @IsTest
  static void sameTranzactionIdOnTheRetryIsNotADuplicate() {
    // N11: the retry's ALREADY_CHARGED check copied the same TranzactionId onto attempt 2
    setup();
    Charge__c a1 = charge('AM', 'Failed', null, true);
    Charge__c a2 = TestDataFactory.charge(p, DAY, 'AM');
    a2.Attempt_Number__c = 2;
    a2.Attempt_Key__c = a2.ExternalUniqTranId__c + '-A2';
    a2.Status__c = 'Success';
    a2.Cardcom_Tranzaction_Id__c = '555';
    a2.Error_Code__c = 'ALREADY_CHARGED';
    insert a2;
    CardcomMock.install()
      .always(LIST_PATH, 200, page(new List<Object>{ row(555, 3, 0, false, 'Debit') }))
      .always(FIND_PATH, 200, TestDataFactory.txSuccess(555, '1234'));
    runFor(DAY);
    Assert.areEqual(0, [SELECT COUNT() FROM Reconciliation_Issue__c]);
    Charge__c c = [SELECT Status__c, Needs_Reconciliation__c FROM Charge__c WHERE Id = :a1.Id];
    Assert.areEqual('Failed', c.Status__c);
    Assert.isFalse(c.Needs_Reconciliation__c);
  }

  @IsTest
  static void reRunUpdatesIssuesInPlaceAndKeepsStaffResolution() {
    setup();
    charge('AM', 'Success', '101', false);
    insert new Reconciliation_Issue__c(
      Issue_Type__c = 'Missing_In_Cardcom',
      Issue_Key__c = 'Missing_In_Cardcom-101',
      Status__c = 'Resolved',
      Resolution_Notes__c = 'checked'
    );
    CardcomMock.install()
      .always(LIST_PATH, 200, page(new List<Object>()))
      .always(FIND_PATH, 200, new Map<String, Object>{ 'ResponseCode' => 5001, 'Description' => 'not found' });
    runFor(DAY);
    Reconciliation_Issue__c i = [SELECT Status__c, Resolution_Notes__c, Business_Date__c, Detected_At__c FROM Reconciliation_Issue__c];
    Assert.areEqual(1, [SELECT COUNT() FROM Reconciliation_Issue__c], 'Issue_Key__c upsert: no duplicate');
    Assert.areEqual('Resolved', i.Status__c, 'a re-run never reopens a resolved issue');
    Assert.areEqual('checked', i.Resolution_Notes__c);
    Assert.areEqual(DAY, i.Business_Date__c);
    Assert.isNotNull(i.Detected_At__c);
  }

  @IsTest
  static void pagingContinuesWhileAPageIsFull() {
    setup();
    CardcomService.settingsOverride.Recon_Page_Size__c = 10;
    List<Object> full = new List<Object>();
    for (Integer i = 0; i < 10; i++)
      full.add(row(1000 + i, 3, 0, false, 'Debit'));
    CardcomMock m = CardcomMock.install()
      .enqueue(LIST_PATH, 200, page(full)) // rows.size() == pageSize → ask for the next page
      .enqueue(LIST_PATH, 200, page(new List<Object>{ row(2000, 3, 0, false, 'Debit') }))
      .always(LIST_PATH, 200, page(new List<Object>()));
    runFor(DAY);
    List<HttpRequest> calls = m.requestsTo(LIST_PATH);
    Assert.areEqual(2, calls.size(), 'stops at the first partial page');
    Assert.areEqual(2, ((Map<String, Object>) JSON.deserializeUntyped(calls[1].getBody())).get('Page'));
    Assert.areEqual(10, ((Map<String, Object>) JSON.deserializeUntyped(calls[1].getBody())).get('Page_size'));
    Assert.areEqual(11, [SELECT COUNT() FROM Reconciliation_Issue__c WHERE Issue_Type__c = 'Missing_In_Salesforce']);
  }

  @IsTest
  static void exactlyFullLastPageTriggersOneEmptyRequest() {
    setup();
    CardcomService.settingsOverride.Recon_Page_Size__c = 10;
    List<Object> full = new List<Object>();
    for (Integer i = 0; i < 10; i++)
      full.add(row(1000 + i, 3, 0, false, 'Debit'));
    CardcomMock m = CardcomMock.install().enqueue(LIST_PATH, 200, page(full)).always(LIST_PATH, 200, page(new List<Object>()));
    runFor(DAY);
    Assert.areEqual(2, m.requestsTo(LIST_PATH).size());
    Assert.areEqual(10, [SELECT COUNT() FROM Reconciliation_Issue__c]);
  }

  @IsTest
  static void unknownCardcomTransactionsCanBeIgnored() {
    setup();
    CardcomService.settingsOverride.Recon_Report_Unknown__c = false;
    CardcomMock.install().always(LIST_PATH, 200, page(new List<Object>{ row(104, 7, 0, false, 'Debit') }));
    runFor(DAY);
    Assert.areEqual(0, [SELECT COUNT() FROM Reconciliation_Issue__c]);
  }

  @IsTest
  static void cardcomErrorsAbortWithoutChanges() {
    setup();
    Charge__c a1 = charge('AM', 'Failed', null, true);
    CardcomMock m = CardcomMock.install().always(LIST_PATH, 401, 'Invalid username');
    runFor(DAY);
    Assert.areEqual(0, m.requestsTo(FIND_PATH).size(), 'no lookups after a failed list');
    Assert.isTrue([SELECT Needs_Reconciliation__c FROM Charge__c WHERE Id = :a1.Id].Needs_Reconciliation__c);
    Assert.isNotNull(Alert_State__c.getOrgDefaults().Config_Error_Sent_On__c, 'config error alert');
  }

  @IsTest
  static void listErrorCodeAborts() {
    setup();
    CardcomMock.install().always(LIST_PATH, 200, new Map<String, Object>{ 'ResponseCode' => 99, 'Description' => 'x' });
    runFor(DAY);
    Assert.areEqual(0, [SELECT COUNT() FROM Reconciliation_Issue__c]);
  }

  @IsTest
  static void scheduledRunReconcilesYesterday() {
    setup();
    ReconciliationJob.dayOverride = DAY;
    CardcomMock m = CardcomMock.install().always(LIST_PATH, 200, page(new List<Object>()));
    Test.startTest();
    new ReconciliationJob().execute((SchedulableContext) null);
    Test.stopTest();
    Assert.areEqual('05112026', m.lastBody(LIST_PATH).get('FromDate'));
  }

  @IsTest
  static void isSchedulableByName() {
    // DonationSetup schedules it by class name (N46)
    Type t = Type.forName('ReconciliationJob');
    Assert.isTrue(t.newInstance() instanceof Schedulable);
  }

  // ---------------------------------------------------------------- N86: list unusable → per-charge fallback
  static Map<String, Object> found(Long tid, Decimal amount) {
    Map<String, Object> t = TestDataFactory.txSuccess(tid, '1234');
    t.put('Amount', amount);
    return t;
  }

  static final Map<String, Object> NOT_FOUND = new Map<String, Object>{ 'ResponseCode' => 5001, 'Description' => 'not found' };

  /** Three Success charges of DAY (ascending Ids = lookup order). */
  static List<Charge__c> threeSuccess() {
    Charge__c a = charge('AM', 'Success', '201', true);
    Charge__c b = charge('PM', 'Success', '202', false);
    Charge__c c = TestDataFactory.charge(p, DAY.addDays(1), 'AM'); // Shabbat charge sent on DAY
    c.Run_Date__c = DAY;
    c.Status__c = 'Success';
    c.Cardcom_Tranzaction_Id__c = '203';
    insert c;
    return new List<Charge__c>{ a, b, c };
  }

  @IsTest
  static void emptyListFallsBackToPerChargeLookup() {
    setup();
    List<Charge__c> cs = threeSuccess();
    CardcomMock m = CardcomMock.install()
      .always(LIST_PATH, 200, page(new List<Object>())) // sandbox: LimitForTerminal → 0 rows
      .enqueue(FIND_PATH, 200, found(201, 3)) // exists, same amount
      .enqueue(FIND_PATH, 200, NOT_FOUND) // really missing
      .enqueue(FIND_PATH, 200, found(203, 5)); // exists, other amount
    runFor(DAY);

    Assert.areEqual(3, m.requestsTo(FIND_PATH).size(), 'one lookup per Success charge');
    Assert.areEqual(cs[0].Attempt_Key__c, ((Map<String, Object>) JSON.deserializeUntyped(m.requestsTo(FIND_PATH)[0].getBody())).get('ExternalUniqTranId'));
    Map<String, Reconciliation_Issue__c> is = issuesByType();
    Assert.areEqual(2, [SELECT COUNT() FROM Reconciliation_Issue__c], 'not every charge is "missing" any more');
    Assert.areEqual(cs[1].Id, is.get('Missing_In_Cardcom').Charge__c);
    Assert.areEqual(cs[2].Id, is.get('Amount_Mismatch').Charge__c);
    Assert.areEqual(5, is.get('Amount_Mismatch').Cardcom_Amount__c.intValue());
    Assert.isFalse([SELECT Needs_Reconciliation__c FROM Charge__c WHERE Id = :cs[0].Id].Needs_Reconciliation__c, 'verified → flag cleared');
    Assert.isNotNull(Alert_State__c.getOrgDefaults().Reconciliation_Unavailable_Sent_On__c, '"list unavailable" staff alert');
    Assert.isNull(ReconciliationJob.chainedFallback, 'everything checked in one job');
  }

  @IsTest
  static void anotherTerminalsListIsNotCompared() {
    // Without LimitForTerminal the list held only another terminal's deals: none of ours → not "missing in Salesforce" either
    setup();
    threeSuccess();
    CardcomMock.install()
      .always(LIST_PATH, 200, page(new List<Object>{ row(900, 7, 0, false, 'Debit'), row(901, 8, 0, false, 'Debit') }))
      .always(FIND_PATH, 200, found(1, 3));
    runFor(DAY);
    Assert.areEqual(0, [SELECT COUNT() FROM Reconciliation_Issue__c]);
    Assert.isNotNull(Alert_State__c.getOrgDefaults().Reconciliation_Unavailable_Sent_On__c);
  }

  @IsTest
  static void failedLookupsOpenNoIssue() {
    setup();
    threeSuccess();
    CardcomMock.install().always(LIST_PATH, 200, page(new List<Object>())).always(FIND_PATH, 200, CardcomMock.TIMEOUT);
    runFor(DAY);
    Assert.areEqual(0, [SELECT COUNT() FROM Reconciliation_Issue__c], 'unverified is not missing');
  }

  @IsTest
  static void usableListIsComparedWithoutLookups() {
    setup();
    charge('AM', 'Success', '201', false);
    CardcomMock m = CardcomMock.install().always(LIST_PATH, 200, page(new List<Object>{ row(201, 3, 0, false, 'Debit') }));
    runFor(DAY);
    Assert.areEqual(0, m.requestsTo(FIND_PATH).size());
    Assert.areEqual(0, [SELECT COUNT() FROM Reconciliation_Issue__c]);
    Assert.isNull(Alert_State__c.getOrgDefaults().Reconciliation_Unavailable_Sent_On__c);
  }

  // Apex refuses a callout after uncommitted DML in the same transaction, so run() (which ends with DML) and fallback() can't be
  // chained inside one test transaction. In production every FallbackJob is its own Queueable transaction. One path per test:
  @IsTest
  static void runDefersWhatTheBudgetCantCover() {
    setup();
    List<Charge__c> cs = threeSuccess();
    ReconciliationJob.FALLBACK_PER_JOB = 1;
    CardcomMock m = CardcomMock.install().always(LIST_PATH, 200, page(new List<Object>())).always(FIND_PATH, 200, NOT_FOUND);
    runFor(DAY);
    Assert.areEqual(1, m.requestsTo(FIND_PATH).size(), 'budget = 1 lookup in this job');
    Assert.areEqual(new List<Id>{ cs[1].Id, cs[2].Id }, ReconciliationJob.chainedFallback, 'the rest goes to FallbackJob');
    Assert.areEqual(cs[0].Id, [SELECT Charge__c FROM Reconciliation_Issue__c].Charge__c);
  }

  @IsTest
  static void fallbackSlicesAndChainsTheRest() {
    setup();
    List<Charge__c> cs = threeSuccess();
    ReconciliationJob.FALLBACK_PER_JOB = 1;
    CardcomMock m = CardcomMock.install().always(FIND_PATH, 200, NOT_FOUND);
    Test.startTest();
    new ReconciliationJob(DAY).fallback(new List<Id>{ cs[1].Id, cs[2].Id }); // what one FallbackJob runs
    Test.stopTest();
    Assert.areEqual(1, m.requestsTo(FIND_PATH).size());
    Assert.areEqual(new List<Id>{ cs[2].Id }, ReconciliationJob.chainedFallback, 'chained again for the last charge');
    Assert.areEqual(cs[1].Id, [SELECT Charge__c FROM Reconciliation_Issue__c].Charge__c);
  }

  @IsTest
  static void fallbackJobChecksEveryChargeItIsGiven() {
    setup();
    List<Charge__c> cs = threeSuccess();
    CardcomMock m = CardcomMock.install().enqueue(FIND_PATH, 200, found(202, 3)).always(FIND_PATH, 200, NOT_FOUND);
    Test.startTest();
    System.enqueueJob(new ReconciliationJob.FallbackJob(DAY, new List<Id>{ cs[1].Id, cs[2].Id }));
    Test.stopTest(); // runs the queueable in its own transaction
    Assert.areEqual(2, m.requestsTo(FIND_PATH).size());
    Assert.areEqual(1, [SELECT COUNT() FROM Reconciliation_Issue__c]);
    Assert.areEqual(cs[2].Id, [SELECT Charge__c FROM Reconciliation_Issue__c].Charge__c, 'only the charge Cardcom did not find');
  }

  @IsTest
  static void alreadyChargedIsLookedUpByTheChargedKey() {
    Charge__c c = new Charge__c(Attempt_Key__c = 'X-A2', Verify_Attempt_Key__c = 'X-A1', Error_Code__c = 'ALREADY_CHARGED');
    Assert.areEqual('X-A1', ReconciliationJob.chargedKey(c));
    c.Error_Code__c = null;
    Assert.areEqual('X-A2', ReconciliationJob.chargedKey(c));
  }
}
