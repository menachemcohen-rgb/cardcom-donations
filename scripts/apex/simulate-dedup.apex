// Live duplicate-prevention check in the org (B6.4). Paste into Developer Console → Debug → Open Execute Anonymous Window,
// tick "Open Log", Execute, then filter the log by "DEDUP". Everything is rolled back at the end: no Contact stays, no email,
// no Cardcom call. Uses random emails/phones/IDs so it never matches a real donor.

// 0) Real risk check: existing Contacts that were never normalized can't be matched (run scripts/apex/normalize-contacts.apex).
Integer notNormalized = [SELECT COUNT() FROM Contact WHERE (Email != null AND Email_Normalized__c = null)
                         OR (MobilePhone != null AND Phone_Normalized__c = null AND Phone = null)];
System.debug('DEDUP existing Contacts with email/mobile but no normalized value: ' + notNormalized
    + (notNormalized > 0 ? '  <-- run normalize-contacts.apex, otherwise these donors can be duplicated' : '  (OK)'));

String run = String.valueOf(Crypto.getRandomInteger()).replace('-', '').left(6);
String rnd8() { return String.valueOf(Math.abs(Crypto.getRandomLong())).left(8).leftPad(8, '1'); }
String validId() {
    String base = String.valueOf(Math.abs(Crypto.getRandomLong())).left(8).leftPad(8, '1');
    for (Integer d = 0; d < 10; d++) {
        String id = base + d;
        Integer sum = 0;
        for (Integer i = 0; i < 9; i++) {
            Integer x = Integer.valueOf(id.substring(i, i + 1)) * (Math.mod(i, 2) + 1);
            sum += x > 9 ? x - 9 : x;
        }
        if (Math.mod(sum, 10) == 0) return id;
    }
    return null;
}
String mA = '05' + rnd8(), mB = '05' + rnd8(), mNew = '05' + rnd8(), idC = validId();
String eA = 'avi.' + run + '@dedup-sim.invalid', eB = 'ben.' + run + '@dedup-sim.invalid', eD = 'dana.' + run + '@dedup-sim.invalid';
String eNew = 'fresh.' + run + '@dedup-sim.invalid';
String intl(String m) { return '+972-' + m.substring(1, 3) + '-' + m.substring(3); }

Savepoint sp = Database.setSavepoint();
try {
    Database.DMLOptions o = new Database.DMLOptions();
    o.DuplicateRuleHeader.allowSave = true;
    List<Contact> seeds = new List<Contact>{
        new Contact(FirstName = 'Avi', LastName = 'Sim' + run, Email = eA.toUpperCase(), MobilePhone = intl(mA)),
        new Contact(FirstName = 'Ben', LastName = 'Sim' + run, Email = eB, Phone = mB.substring(0, 3) + ' ' + mB.substring(3)),
        new Contact(LastName = 'Sim' + run, Donor_Tax_Id__c = idC),
        new Contact(FirstName = 'Dana', LastName = 'Sim' + run, Email = eD)
    };
    Database.insert(seeds, o);
    Map<String, Id> ids = new Map<String, Id>{ 'A' => seeds[0].Id, 'B' => seeds[1].Id, 'C' => seeds[2].Id, 'D' => seeds[3].Id };

    // name, email, phone, taxId, expected
    List<List<String>> sc = new List<List<String>>{
        new List<String>{ 'email case + spaces', '  ' + eA.toUpperCase() + ' ', null, null, 'A' },
        new List<String>{ 'mobile local', 'x1.' + run + '@dedup-sim.invalid', mA, null, 'A' },
        new List<String>{ 'mobile 972', 'x2.' + run + '@dedup-sim.invalid', '972' + mA.substring(1), null, 'A' },
        new List<String>{ 'mobile 00972 dashes', 'x3.' + run + '@dedup-sim.invalid', '00972-' + mA.substring(1), null, 'A' },
        new List<String>{ 'phone in Phone field', 'x4.' + run + '@dedup-sim.invalid', mB, null, 'B' },
        new List<String>{ 'ID without leading zeros', 'x5.' + run + '@dedup-sim.invalid', null, String.valueOf(Long.valueOf(idC)), 'C' },
        new List<String>{ 'ID full', 'x6.' + run + '@dedup-sim.invalid', null, idC, 'C' },
        new List<String>{ 'email upper', eD.toUpperCase(), '05' + rnd8(), null, 'D' },
        new List<String>{ 'new donor', eNew, mNew, null, 'NEW' },
        new List<String>{ 'new donor again: case', eNew.toUpperCase(), null, null, 'NEW' },
        new List<String>{ 'new donor again: phone', 'y.' + run + '@dedup-sim.invalid', intl(mNew), null, 'NEW' }
    };
    Integer ok = 0, bad = 0;
    for (List<String> s : sc) {
        ContactMatcher.Result r = ContactMatcher.matchOrCreate(new ContactMatcher.DonorInput('Sim', 'Sim' + run, s[1], s[2], s[3]));
        Boolean pass;
        if (s[4] == 'NEW' && !ids.containsKey('NEW')) { pass = r.created; ids.put('NEW', r.contactId); }
        else pass = r.contactId == ids.get(s[4]);
        if (pass) ok++; else bad++;
        System.debug('DEDUP ' + (pass ? 'PASS ' : 'FAIL ') + s[0] + ' → ' + r.method + (pass ? '' : ' (expected ' + s[4] + ', got ' + r.contactId + ')'));
    }
    Integer created = [SELECT COUNT() FROM Contact WHERE LastName = :('Sim' + run)];
    System.debug('DEDUP Contacts in the simulation: ' + created + ' (expected 5: 4 existing + 1 new) → ' + (created == 5 ? 'PASS' : 'FAIL'));
    System.debug('DEDUP SUMMARY: ' + ok + ' passed, ' + bad + ' failed' + (created == 5 ? '' : ', duplicate created!'));
} finally {
    Database.rollback(sp);
    System.debug('DEDUP rolled back — nothing was saved.');
}
