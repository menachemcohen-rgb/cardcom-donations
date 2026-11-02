// B10 step 12: fill Email_Normalized__c, Phone_Normalized__c and Tax_Id_Hash__c on existing Contacts (before activating the matching rule).
Id jobId = Database.executeBatch(new ContactNormalizationBatch(), 200);
System.debug('ContactNormalizationBatch job: ' + jobId);
