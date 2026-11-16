@IsTest
private class EmailTemplatesTest {
  static final List<String> TEMPLATES = new List<String>{
    'Donor_Welcome',
    'Donor_Monthly_Summary',
    'Donor_Payment_Failed',
    'Donor_Payment_Failed_Reminder',
    'Staff_Failure_Streak',
    'Staff_Config_Error',
    'Staff_Receipt_Failures',
    'Staff_Reconciliation_Open',
    'Staff_Reconciliation_Unavailable',
    'Staff_Pending_Verification',
    'Staff_Schedule_Changed',
    'Staff_Schedule_Failed',
    'Staff_Email_Limit',
    'Staff_Run_Failures',
    'Staff_Weekly_Failed_Digest',
    'Staff_High_Amount'
  };

  @IsTest
  static void everyEmailHasATemplateInTheDonationsFolder() {
    Set<String> found = new Set<String>();
    for (EmailTemplate t : [SELECT DeveloperName FROM EmailTemplate WHERE Folder.DeveloperName = 'Donations'])
      found.add(t.DeveloperName);
    for (String n : TEMPLATES)
      Assert.isTrue(found.contains(n), 'missing Classic Email Template ' + n + ' (folder Donations)');
  }

  @IsTest
  static void editedTemplateWinsAndPlaceholdersAreFilled() {
    EmailTemplates.byName = new Map<String, EmailTemplate>{
      'X' => new EmailTemplate(Subject = 'שלום {{Name}}', HtmlValue = '<p>{{Name}} {{Html}} {{Typo}}</p>')
    };
    EmailTemplates.Rendered r = EmailTemplates.render(
      'X',
      'default',
      'default',
      new Map<String, String>{ 'Name' => 'A &amp; B', 'Html' => '<b>x</b>' },
      new Map<String, String>{ 'Name' => 'A & B' }
    );
    Assert.areEqual('שלום A & B', r.subject, 'subject takes the plain value');
    Assert.areEqual('<p>A &amp; B <b>x</b> </p>', r.html, 'unknown placeholders are removed');
  }

  @IsTest
  static void missingOrBlankTemplateFallsBackToTheDefault() {
    EmailTemplates.byName = new Map<String, EmailTemplate>{ 'Blank' => new EmailTemplate(Subject = ' ', HtmlValue = '') };
    for (String n : new List<String>{ 'Blank', 'Missing' }) {
      EmailTemplates.Rendered r = EmailTemplates.render(n, 'S {{A}}', '<p>{{A}}</p>', new Map<String, String>{ 'A' => '1' }, null);
      Assert.areEqual('S 1', r.subject, n);
      Assert.areEqual('<p>1</p>', r.html, n);
    }
  }

  @IsTest
  static void donorEmailUsesTheEditedTemplate() {
    TestDataFactory.chargeEngine(TestDataFactory.WED_0800);
    DonorLinkToken.secretOverride = 'tpl-secret-0123456789abcdef';
    Opportunity p = TestDataFactory.activePledges(1, 'TwiceDaily')[0];
    EmailTemplates.byName = new Map<String, EmailTemplate>{
      'Donor_Welcome' => new EmailTemplate(
        Subject = 'ברוך הבא {{FirstName}}',
        HtmlValue = '<p>טקסט חדש: {{Amounts}}</p><a href="{{CardLink}}">כרטיס</a>'
      )
    };
    DonorEmailService.sendWelcome(new Set<Id>{ p.Id });
    Messaging.SingleEmailMessage m = DonorEmailService.lastSent[0];
    Assert.areEqual('ברוך הבא Avi', m.getSubject());
    Assert.isTrue(m.getHtmlBody().startsWith('<p>טקסט חדש: שחרית 3.00 ₪'), m.getHtmlBody());
    Assert.isTrue(m.getHtmlBody().contains('a=card&amp;t='), 'the permanent card link is filled');
  }
}
