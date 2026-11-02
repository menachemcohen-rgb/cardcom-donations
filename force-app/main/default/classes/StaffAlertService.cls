/**
 * Staff alerts (Part C E11, B6.9.4). Prompt 5 adds configErrorOncePerDay; Prompt 6 implements every alert and the Daily schedulable.
 * Prompt 4 only needs scheduleChanged, called by DonationSetup.reschedule().
 */
public without sharing class StaffAlertService {
  public static void scheduleChanged(Charge_Settings__c s) {
    // TODO Prompt 6: email "זמני חיוב עודכנו" with the new times to Cardcom_Setting__mdt.Failure_Notify_Emails__c (B6.9.4).
  }
}
