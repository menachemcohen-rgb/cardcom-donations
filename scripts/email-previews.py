# Rebuilds every email exactly as the Apex builders do (DonorEmailService, StaffAlertService, DonorChargeEmailService), with sample data.
# Run from the repo root: python3 scripts/email-previews.py  →  docs/email-previews.html
import html
esc = lambda v: '' if v is None else html.escape(str(v), quote=True)
ORG='איגוד תלמידי הישיבות - העולמי 770'; SIGNER='צוות איגוד תלמידי הישיבות - העולמי 770'
PHONE='*6358'; CEMAIL='ato770office@gmail.com'
IMPACT='הצדקה היומית שלך מחזקת את פעילות את"ה למען תלמידי הישיבות, יום אחר יום – תודה שאת/ה שותף/ה.'
SF='https://associationofyeshivastudentstoraha.lightning.force.com'
CARD='https://ato770.com/donor/?a=card&t=eyJwIjoiMDA2V2wwMDAwMEFiQ2RFIiwiYSI6ImNhcmQiLCJ2IjoxfQ.x9Qk3'
AMT='https://ato770.com/donor/?a=amount&t=eyJwIjoiMDA2V2wwMDAwMEFiQ2RFIiwiYSI6ImFtb3VudCIsInYiOjF9.p2Lm8'
FREQ='שחרית ומנחה'; AMTS='שחרית 3.00 ₪ · מנחה 5.00 ₪'
def signature():
    return SIGNER if ORG in SIGNER else SIGNER+', '+ORG
def donor_msg(body):
    return ('<div dir="rtl" style="font-family:Arial,sans-serif;font-size:15px;line-height:1.6;color:#222;max-width:600px">'
      '<p>'+esc('ישראל')+' שלום,</p>'+body+'<p><strong>רוצה לעדכן את ההוראה?</strong></p>'
      '<p><a href="'+esc(CARD)+'" style="background:#1d4ed8;color:#fff;padding:10px 18px;border-radius:6px;text-decoration:none">החלפת כרטיס אשראי</a>'
      ' &nbsp; <a href="'+esc(AMT)+'" style="background:#0f766e;color:#fff;padding:10px 18px;border-radius:6px;text-decoration:none">שינוי סכום ההוראה</a></p>'
      '<p style="font-size:13px;color:#555">הקישורים אישיים וקבועים, ואין צורך בסיסמה – שמרו את המייל ואל תעבירו אותו לאחרים.</p>'
      '<p>להפסקת ההוראה או לשאלות: '+esc(PHONE)+' · '+esc(CEMAIL)+'</p>'
      '<p>בתודה,<br>'+esc(signature())+'</p></div>')
def wrap(b): return '<div dir="rtl" style="font-family:Arial,sans-serif"><p>שלום,</p>'+b+'</div>'
def table(h,rows): return '<table border="1" cellpadding="4" style="border-collapse:collapse"><tr>'+''.join('<th>'+esc(x)+'</th>' for x in h)+'</tr>'+rows+'</table>'
def tr(*c): return '<tr>'+''.join('<td>'+x+'</td>' for x in c)+'</tr>'
def link(rid,name): return '<a href="'+SF+'/'+rid+'">'+esc(name)+'</a>'

donor=[]; staff=[]
donor.append(('ברוכים הבאים – כשהוראה נקלטה','DonorEmailService.sendWelcome','התורם',
  'הוראת התרומה היומית שלך ל'+ORG+' נקלטה',
  donor_msg('<p>תודה! הוראת התרומה היומית שלך נקלטה ותחל לפעול במועד החיוב הקרוב.</p><p><b>פרטי ההוראה:</b> '+esc(FREQ)+' · '+esc(AMTS)+'</p>'
   '<p>בשבת ובחג אין חיובים: הם מחויבים מראש בערב שבת או ערב חג, יחד עם תפילת המנחה.</p>'
   '<p>פעם בחודש נשלח אליך סיכום של התרומות. קבלה לפי סעיף 46 תישלח אליך במייל נפרד.</p>')))
donor.append(('סיכום חודשי – ב-2 לחודש','DonorEmailService.sendMonthlySummaries','התורם',
  'סיכום התרומות שלך ל'+ORG+' – אוקטובר 2026',
  donor_msg('<p>בחודש '+esc('אוקטובר 2026')+' נתרמו בהוראה שלך <b>248.00 ₪</b> ב-62 חיובים. תודה על השותפות!</p>'
   '<p><b>ההוראה כרגע:</b> '+esc(FREQ)+' · '+esc(AMTS)+'</p><p>קבלה לפי סעיף 46 על תרומות החודש תישלח אליך במייל נפרד.</p>')))
for rem in (False,True):
  donor.append((('תזכורת שבועית – כל יום ראשון 10:00' if rem else 'חיוב שלא עבר – מיד בכישלון הראשון'),
    'DonorEmailService.sendPaymentFailed','התורם',
    ('תזכורת: ' if rem else '')+'לא הצלחנו לחייב את הכרטיס – הוראת התרומה ל'+ORG,
    donor_msg('<p>'+('תזכורת: ' if rem else '')+'לא הצלחנו לחייב את הכרטיס המסתיים ב-'+esc('1234')+' עבור הוראת התרומה היומית שלך.</p>'
      '<p>כדי שהתרומה תמשיך, אפשר לעדכן את פרטי הכרטיס בכפתור "החלפת כרטיס אשראי" כאן למטה. ננסה לחייב שוב במועדי החיוב הקבועים.</p>')))
old=open('./force-app/main/default/email/Donations/Donor_Charge_Thanks.email').read()
for k,v in {'FirstName':'ישראל','ChargeLines':'היום, 10/11/2026, נתרמו 3.00 ₪','CardPhrase':'מהכרטיס המסתיים ב-1234','OrgName':esc(ORG),
  'ImpactSentence':esc(IMPACT),'CardLink':esc(CARD),'AmountLink':esc(AMT),'ContactPhone':PHONE,'ContactEmail':CEMAIL,'SignerName':esc(SIGNER)}.items():
  old=old.replace('{{'+k+'}}',v)
donor.append(('תודה אחרי כל חיוב – כבוי (D37)','DonorChargeEmailService','התורם','תודה על תרומתך ל'+ORG+' – 3.00 ₪',old))

rows=''.join(tr(esc(d),esc(s),esc(a),esc(c),esc(m)) for d,s,a,c,m in [
 ('10/11/2026','מנחה','3','4','סירוב'),('10/11/2026','מנחה','2','4','סירוב'),('10/11/2026','מנחה','1','4','סירוב'),
 ('10/11/2026','שחרית','3','4','סירוב'),('09/11/2026','מנחה','3','4','סירוב')])
staff.append(('כישלונות רצופים בהוראה – פעם אחת לרצף','StaffAlertService.failureStreak','צוות (Failure_Notify_Emails)',
 'כישלונות חוזרים בהוראת תרומה – ישראל ישראלי (PLG-000123)',
 '<div dir="rtl" style="font-family:Arial,sans-serif"><p>שלום,</p><p>בהוראת התרומה של ישראל ישראלי נכשלו 3 חיובים ברצף. החיובים ממשיכים לפי הלוח – לא בוצעה עצירה.</p>'
 '<p>אם צריך, ניתן לעצור את החיובים בכפתור "הפסקת חיובים" ברשומת ההוראה.</p><p>פרטי התורם: ישראל ישראלי · israel@example.com · 0521234567</p>'
 '<p>ההוראה: PLG-000123 · '+FREQ+' · '+AMTS+' · כרטיס המסתיים ב-1234, תוקף 09/28</p>'
 '<table border="1" cellpadding="4" style="border-collapse:collapse"><tr><th>תאריך</th><th>תפילה</th><th>ניסיון</th><th>קוד</th><th>תיאור</th></tr>'+rows+'</table>'
 '<p><a href="'+SF+'/006Wl00000AbCdE">לצפייה ברשומה</a></p></div>'))
staff.append(('תקלת סליקה כללית – רוב החיובים נכשלו (לכל היותר כל 4 שעות)','StaffAlertService.runFailures','צוות','תקלת סליקה: 41 מתוך 50 חיובים נכשלו',
 wrap('<p>בשלוש השעות האחרונות נשלחו ל-Cardcom 50 חיובים, ו-41 מהם נכשלו. כשרוב החיובים נכשלים יחד, הסיבה בדרך כלל אינה בכרטיסים של התורמים אלא בטרמינל או בהגדרות.</p>'
  +table(['קוד שגיאה','מספר חיובים'],tr('HTTP_401','38')+tr('4','3'))+
  '<p>מה לבדוק: הודעות במסוף Cardcom, פרטי הגישה ל-API (External Credential Cardcom_EC), ומצב הטרמינל. אם צריך לעצור את כל החיובים: Charge Settings → Charging Enabled.</p>'
  '<p><a href="'+SF+'/lightning/o/Report/home">דוח "חיובים שלא עברו"</a></p>')))
r=''.join(tr(link('006Wl00000AbCdE','PLG-000123'),'ישראל ישראלי','0521234567','israel@example.com','03/11/2026','4','4 סירוב','נשלחות')
          +tr(link('006Wl00000XyZ12','PLG-000140'),'שרה כהן','0547654321','sara@example.com','08/11/2026','1','36 כרטיס פג תוקף','עצורות'))
staff.append(('סיכום שבועי של הוראות עם חיובים שלא עברו – ראשון אחרי התזכורות','StaffAlertService.weeklyFailedDigest','צוות','הוראות עם חיובים שלא עברו – 2',
 wrap('<p>להוראות הבאות יש חיוב שלא עבר. התורמים מקבלים תזכורת במייל בכל יום ראשון עם קישור להחלפת כרטיס.</p>'
  +table(['הוראה','תורם','טלפון','מייל','מאז','כישלונות רצופים','שגיאה אחרונה','תזכורות'],r)+
  '<p>מה אפשר לעשות: להתקשר לתורם ולבקש להחליף כרטיס דרך הקישור במייל; אם התורם מבקש להפסיק – "הפסקת חיובים" בהוראה; כדי להפסיק רק את התזכורות – לסמן "עצירת תזכורות כישלון" בהוראה.</p>')))
staff.append(('תקלת הגדרות Cardcom – פעם ביום','StaffAlertService.configErrorOncePerDay','צוות','תקלת הגדרות Cardcom',
 wrap('<p>חיובי התרומות נכשלו בגלל תקלת הגדרות מול Cardcom (למשל שם משתמש או סיסמת API שגויים, או טרמינל לא תקין).</p>'
  '<p>לא נוצרו ניסיונות חוזרים והכישלונות לא נספרים ברצף. אחרי התיקון יש להריץ מחדש את חיובי היום (ChargeAdmin.requeueFailedConfig).</p>')))
staff.append(('קבלות חודשיות שנכשלו – יומי 09:00','StaffAlertService.receiptFailures','צוות','קבלות חודשיות שנכשלו (1)',
 wrap('<p>הקבלות הבאות לא הופקו או שתוצאתן לא ידועה. יש לבדוק ולהפעיל "ניסיון חוזר".</p>'
  +table(['קבלה','תורם','חודש','סטטוס','סכום','שגיאה'],tr(link('a0RWl0000001','RCP-000045'),'ישראל ישראלי','01/10/2026','Failed','248.00','6311 Total items not equal to some form of payment')))))
staff.append(('פערי התאמה פתוחים – יומי','StaffAlertService.reconciliationOpen','צוות','פערי התאמה פתוחים (1)',
 wrap('<p>ההתאמה הלילית מול Cardcom מצאה פערים שעדיין פתוחים.</p>'
  +table(['פער','סוג','תאריך','עסקה','סכום Cardcom','סכום Salesforce'],tr(link('a0SWl0000001','REC-000012'),'Amount_Mismatch','09/11/2026','123456789','3.00','5.00')))))
staff.append(('התאמה לילית – רשימת Cardcom לא זמינה','StaffAlertService.reconciliationUnavailable','צוות','התאמה לילית: רשימת העסקאות מ-Cardcom לא זמינה',
 wrap('<p>רשימת העסקאות שהתקבלה מ-Cardcom ליום 09/11/2026 לא כוללת אף אחד מ-120 החיובים המוצלחים של אותו יום, ולכן לא בוצעה השוואה מולה.</p>'
  '<p>במקום זאת כל חיוב נבדק בנפרד מול Cardcom (50 נבדקו בריצה הראשונה, השאר בהמשך). פער ייפתח רק לחיוב ש-Cardcom לא מצאה.</p>'
  '<p>כדאי לבדוק את הרשאות ה-API ואת מספר הטרמינל (LimitForTerminal) מול Cardcom.</p>')))
staff.append(('הוראות ממתינות / נכשלו באימות – יומי','StaffAlertService.pendingVerificationStale','צוות','הוראות ממתינות או שנכשלו באימות (1)',
 wrap('<p>הוראות שלא הושלם בהן אימות הכרטיס: ממתינות יותר מ-24 שעות, או שנכשלו באימות ביממה האחרונה.</p>'
  +table(['הוראה','סטטוס','שם','אימייל','נוצרה'],tr(link('006Wl00000QwE','תרומה יומית – כהן משה – PLG-000150'),'Verification_Failed','משה כהן','moshe@example.com','09/11/2026 21:14')))))
staff.append(('זמני חיוב עודכנו','StaffAlertService.scheduleChanged','צוות','זמני חיוב עודכנו',
 wrap('<p>זמני החיוב עודכנו והוחלו:</p><p>בוקר 08:00 · ערב 20:00 · שישי/ערב חג 06:00 ו-11:00 · ריצות ביום 2 · קבלות 07:00 · התאמה 02:30</p><p>עודכן ע"י יוסי נוטיק.</p>')))
staff.append(('זמני חיוב לא עודכנו','StaffAlertService.scheduleFailed','צוות','זמני החיוב לא עודכנו',
 wrap('<p>הבקשה (RESCHEDULE) לא בוצעה. ריצות החיוב הקיימות לא השתנו.</p><ul><li>חיוב פעיל כרגע — נסו שוב בעוד כמה דקות</li></ul>')))
staff.append(('מכסת מיילים יומית כמעט נגמרה','StaffAlertService.emailLimit','צוות','מכסת המיילים היומית כמעט נגמרה',
 wrap('<p>נותרו 150 מיילים יומיים בארגון. מיילי התודה לתורמים לא נשלחים עד מחר (החיובים עצמם ממשיכים כרגיל). כדאי לבדוק את נפח המיילים (Q9).</p>')))

def card(i,t):
  title,src,to,subj,body=t
  return ('<section class="mail"><div class="meta"><span class="n">'+str(i)+'</span><h3>'+esc(title)+'</h3>'
    '<div class="row"><b>אל:</b> '+esc(to)+' &nbsp; <b>נבנה ב:</b> <code>'+esc(src)+'</code></div>'
    '<div class="row"><b>נושא:</b> '+esc(subj)+'</div></div><div class="client">'+body+'</div></section>')
page=('<!doctype html><html lang="he" dir="rtl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
 '<title>תצוגת מיילים</title><style>body{background:#eef0f3;margin:0;padding:16px;font-family:Arial,sans-serif;color:#111}'
 'h1{font-size:22px;margin:0 0 4px}h2{font-size:18px;margin:28px 0 10px}.note{color:#555;font-size:14px;max-width:900px}'
 '.mail{background:#fff;border:1px solid #d5d9e0;border-radius:10px;margin:0 0 18px;max-width:900px;overflow:hidden}'
 '.meta{background:#f6f7f9;border-bottom:1px solid #e3e6ea;padding:10px 14px;font-size:13px}.meta h3{display:inline;font-size:15px;margin:0 6px}'
 '.n{display:inline-block;background:#334155;color:#fff;border-radius:50%;width:22px;height:22px;text-align:center;line-height:22px;font-size:12px}'
 '.row{margin-top:4px}.client{padding:14px;overflow-x:auto;background:#fff}code{font-size:12px}</style></head><body>'
 '<h1>כל המיילים שהמערכת שולחת</h1><p class="note">כל מייל נבנה כאן בדיוק כמו בקוד ב-main (אותו HTML), עם נתוני דוגמה. '
 'המסגרת האפורה היא רק כותרת התצוגה; מה שמתחתיה הוא גוף המייל כפי שהוא יגיע. קבלת סעיף 46 עצמה נשלחת מ-Cardcom ולא מופיעה כאן.</p>'
 '<h2>לתורמים</h2>'+''.join(card(i+1,t) for i,t in enumerate(donor))+
 '<h2>לצוות</h2>'+''.join(card(i+1+len(donor),t) for i,t in enumerate(staff))+'</body></html>')
open('./docs/email-previews.html','w').write(page)
print(len(donor),len(staff))
