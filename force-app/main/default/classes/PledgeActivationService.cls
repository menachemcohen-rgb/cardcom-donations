/**
 * Pledge activation (B6.4, Part C C1/C2): match or create the donor Contact, link it, make the pledge Active,
 * add the Donor contact role. Idempotent and safe to call from every path (submit, webhook job, sweeper).
 */
public without sharing class PledgeActivationService {
  /** B6.3 / B8 name (spec-consistency N4). */
  public static Boolean activate(Id pledgeId) {
    return tryActivate(pledgeId);
  }

  /** @return true if the pledge was activated by this call. */
  public static Boolean tryActivate(Id pledgeId) {
    Id rt = MicroPledges.recordTypeId();
    List<Opportunity> ps = [
      SELECT
        Id,
        StageName,
        Donor_Submitted__c,
        Lp_Processed__c,
        Token__c,
        Pledge_Number__c,
        Donor_First_Name__c,
        Donor_Last_Name__c,
        Donor_Email__c,
        Donor_Phone__c,
        Donor_Tax_Id__c
      FROM Opportunity
      WHERE Id = :pledgeId AND RecordTypeId = :rt
      FOR UPDATE
    ];
    if (ps.isEmpty())
      return false;
    Opportunity p = ps[0];
    if (!p.Donor_Submitted__c || !p.Lp_Processed__c || p.StageName != MicroPledges.STAGE_PENDING || String.isBlank(p.Token__c)) {
      return false;
    }
    ContactMatcher.Result m = ContactMatcher.matchOrCreate(
      new ContactMatcher.DonorInput(p.Donor_First_Name__c, p.Donor_Last_Name__c, p.Donor_Email__c, p.Donor_Phone__c, p.Donor_Tax_Id__c)
    );
    Datetime now = Datetime.now();
    update new Opportunity(
      Id = p.Id,
      Donor_Contact__c = m.contactId,
      Match_Method__c = m.method,
      StageName = MicroPledges.STAGE_ACTIVE,
      Activated_At__c = now,
      Start_Date__c = now.date(),
      CloseDate = now.date(),
      Name = MicroPledges.fullName(p.Donor_Last_Name__c, p.Donor_First_Name__c, p.Pledge_Number__c)
    );
    if ([SELECT COUNT() FROM OpportunityContactRole WHERE OpportunityId = :p.Id AND ContactId = :m.contactId] == 0) {
      insert new OpportunityContactRole(OpportunityId = p.Id, ContactId = m.contactId, Role = MicroPledges.DONOR_ROLE, IsPrimary = true);
    }
    return true;
  }

  /** Activates as many as the remaining limits allow; each pledge is isolated by a savepoint. The sweeper retries the rest. */
  public static Integer activateAll(List<Id> pledgeIds) {
    Integer n = 0;
    for (Id id : pledgeIds) {
      if (!hasHeadroom())
        break;
      Savepoint sp = Database.setSavepoint();
      try {
        if (tryActivate(id))
          n++;
      } catch (Exception e) {
        Database.rollback(sp);
        System.debug(LoggingLevel.ERROR, 'Activation failed for ' + id + ': ' + e.getMessage());
      }
    }
    return n;
  }

  /** One activation uses about 6 queries and 4 DML statements (matcher included). */
  @TestVisible
  static Boolean hasHeadroom() {
    return Limits.getQueries() + 10 <= Limits.getLimitQueries() && Limits.getDmlStatements() + 6 <= Limits.getLimitDmlStatements();
  }
}
