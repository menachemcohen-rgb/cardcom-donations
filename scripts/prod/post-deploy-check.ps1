# Read-only status report of a production org after the deploy (docs/production-deployment.md).
# Only SELECT queries: changes nothing. Never prints the donor-link secret, tokens or IDs of donors.
#   powershell -ExecutionPolicy Bypass -File scripts\prod\post-deploy-check.ps1 prod > check.txt
param([Parameter(Mandatory = $true)][string]$Alias)
$ErrorActionPreference = 'Continue'

function Q([string]$title, [string]$soql, [switch]$Tooling) {
    Write-Output ''
    Write-Output "===== $title"
    $a = @('data', 'query', '--target-org', $Alias, '--query', $soql)
    if ($Tooling) { $a += '--use-tooling-api' }
    & sf @a 2>&1 | Where-Object { $_ -notmatch 'update available' }
}

Q '1. Latest pledges' "SELECT Pledge_Number__c, StageName, CreatedDate, Donor_Submitted__c, Lp_Processed__c, Lp_Check_Count__c, Verified_At__c, Activated_At__c, Match_Method__c, Donor_Contact__r.Name, Charge_Amount__c, Frequency__c, Last4__c, CardExpirationMMYY__c FROM Opportunity WHERE Type = 'Daily Donation Pledge' ORDER BY CreatedDate DESC LIMIT 5"
Q '2. Latest Cardcom webhooks' "SELECT CreatedDate, Processed__c, Content_Type__c FROM Cardcom_Webhook_Log__c ORDER BY CreatedDate DESC LIMIT 5"
Q '3. Charges' "SELECT Name, Status__c, Scheduled_Date__c, Slot__c, Amount__c, Error_Code__c, Executed_At__c FROM Charge__c ORDER BY CreatedDate DESC LIMIT 10"
Q '4. Cardcom Setting (Default)' "SELECT Terminal_Number__c, Webhook_Url__c, Allowed_Return_Hosts__c, Donor_Portal_Base_Url__c, Terms_Url__c, Org_Wide_Email_Address__c, Failure_Notify_Emails__c, Integration_User_Id__c, Send_Donor_Charge_Email__c, Receipt_Payment_Mode__c FROM Cardcom_Setting__mdt WHERE DeveloperName = 'Default'"
Q '5. Donor-link secret is set (a row = yes; the value is not shown)' "SELECT DeveloperName FROM Donor_Link_Setting__mdt WHERE DeveloperName = 'Default' AND Secret__c != null"
Q '6. Charge Settings (Org Default)' "SELECT Charging_Enabled__c, Runs_Per_Day__c, AM_Time__c, PM_Time__c, Eve_AM_Time__c, Eve_PM_Time__c, Receipt_Day_Of_Month__c, Max_Retries__c FROM Charge_Settings__c WHERE SetupOwnerId = '$((& sf org display --target-org $Alias --json | ConvertFrom-Json).result.id)'"
Q '7. Permission set assignments' "SELECT PermissionSet.Name, Assignee.Username, Assignee.IsActive FROM PermissionSetAssignment WHERE PermissionSet.Name LIKE 'Donations_%' ORDER BY PermissionSet.Name"
Q '8. Custom permissions given to users (via permission sets)' "SELECT Parent.Name, SetupEntityId FROM SetupEntityAccess WHERE SetupEntityType = 'CustomPermission' AND Parent.Name LIKE 'Donations_%'"
Q '9. Platform event subscribers (UserId must be the integration user)' "SELECT DeveloperName, UserId, BatchSize FROM PlatformEventSubscriberConfig" -Tooling
Q '10. Integration user' "SELECT Id, Username, IsActive, TimeZoneSidKey, Profile.Name FROM User WHERE Username LIKE 'integration.donations%'"
Q '11. Scheduled Donations jobs (expected 13 once scheduled, owner = integration user)' "SELECT CronJobDetail.Name, State, NextFireTime, CreatedBy.Username FROM CronTrigger WHERE CronJobDetail.Name LIKE 'Donations%' ORDER BY CronJobDetail.Name"
Q '12. Apex jobs that failed in the last 2 days' "SELECT ApexClass.Name, JobType, Status, ExtendedStatus, CreatedDate FROM AsyncApexJob WHERE Status = 'Failed' AND CreatedDate = LAST_N_DAYS:2 ORDER BY CreatedDate DESC LIMIT 20"
Q '13. Org-Wide Email Addresses' "SELECT Address, DisplayName, IsAllowAllProfiles FROM OrgWideEmailAddress"
Q '14. Donor duplicate rule (activate after normalizing Contacts)' "SELECT DeveloperName, IsActive FROM DuplicateRule WHERE SobjectType = 'Contact'"
Q '15. Layout assignment (who sees which Opportunity / Monthly Receipt layout)' "SELECT Profile.Name, Layout.Name, TableEnumOrId FROM ProfileLayout WHERE Layout.Name IN ('Micro Donation Pledge Layout', 'Monthly Receipt Layout') ORDER BY Layout.Name, Profile.Name" -Tooling
Q '16. Sites' "SELECT Name, Status, UrlPathPrefix, GuestUserId FROM Site"
Q '17. Flows (all 8 must be Active)' "SELECT DeveloperName, ActiveVersionId FROM FlowDefinition WHERE DeveloperName IN ('Stop_Pledge_Charges','Resume_Pledge_Charges','Cancel_Pledge','Revoke_Donor_Links','Retry_Receipt','Apply_Charge_Schedule','Plan_Contact_Monthly_Receipt','Plan_Monthly_Receipts_All')" -Tooling
Q '18. Opportunity field history tracking' "SELECT QualifiedApiName FROM FieldDefinition WHERE EntityDefinition.QualifiedApiName = 'Opportunity' AND IsFieldHistoryTracked = true" -Tooling
Write-Output ''
Write-Output 'Done (read-only).'
