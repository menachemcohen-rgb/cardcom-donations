/**
 * Covers EmailUtil on its own, so its coverage doesn't depend on the org having an Org-Wide Email Address
 * configured in Cardcom_Setting__mdt (production validate N104: 66% when the address was still empty).
 */
@IsTest
private class EmailUtilTest {
  @IsTest
  static void escapesHtmlAndNull() {
    Assert.areEqual('', EmailUtil.esc(null), 'null -> empty');
    Assert.areEqual('&lt;b&gt;x&lt;/b&gt;', EmailUtil.esc('<b>x</b>'), 'html escaped');
    Assert.areEqual('5', EmailUtil.esc(5), 'non-string value');
  }

  @IsTest
  static void buildsRecordUrl() {
    Id uid = UserInfo.getUserId();
    String u = EmailUtil.recordUrl(uid);
    Assert.isTrue(u.endsWith('/' + uid), u);
    Assert.isTrue(u.startsWith('https://'), u);
  }

  @IsTest
  static void oweaIdBlankUnknownAndCached() {
    Assert.isNull(EmailUtil.oweaId(null), 'blank address');
    Assert.isNull(EmailUtil.oweaId(''), 'blank address');
    String nobody = 'no-such-owea-' + Crypto.getRandomInteger() + '@example.invalid';
    Assert.isNull(EmailUtil.oweaId(nobody), 'unknown address');
    Integer before = Limits.getQueries();
    Assert.isNull(EmailUtil.oweaId(nobody), 'cached result');
    Assert.areEqual(before, Limits.getQueries(), 'second lookup of the same address uses the cache');
  }
}
