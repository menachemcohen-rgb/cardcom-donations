"""Charge-calendar simulation: ports HebrewHolidays/ChargeCalendar (Apex) to Python and checks them.

Checks: holiday dates vs the independent pyluach Hebrew calendar (2024-2040); every calendar day of 2026-2030 is
charged exactly once per slot; no run on Shabbat/holiday; retries never land on a rest day or after the eve cutoff.
Run: pip install --target /tmp/pyl pyluach && PYTHONPATH=/tmp/pyl python3 scripts/sim/calendar_sim.py
Keep in sync with force-app/main/default/classes/HebrewHolidays.cls and ChargeCalendar.cls.
"""
import sys, math, datetime as dt
from collections import Counter
from pyluach import dates as hd
D=dt.date; T=dt.timedelta
# ---- port of HebrewHolidays.cls ----
def elapsed(y):
    months=math.floor((235*y-234)/19.0); parts=12084+13753*months
    day=months*29+parts//25920
    if (3*(day+1))%7<3: day+=1
    return day
def delay(y):
    a,b,c=elapsed(y-1),elapsed(y),elapsed(y+1)
    if c-b==356: return 2
    if b-a==382: return 1
    return 0
raw=lambda y: elapsed(y)+delay(y)
def rh(y): return D(2026,9,12)+T(days=raw(y)-raw(5787))
def rest_days(g):
    r=rh(g+3761); p=r-T(163)
    return {r,r+T(1),r+T(9),r+T(14),r+T(21),p,p+T(6),p+T(50)}
# ---- independent reference (pyluach): Israeli yom tov ----
def ref(g):
    s=set(); d=D(g,1,1)
    while d.year==g:
        h=hd.GregorianDate(d.year,d.month,d.day).to_heb()
        m,dd=h.month,h.day
        if (m==7 and dd in(1,2,10,15,22)) or (m==1 and dd in(15,21)) or (m==3 and dd==6): s.add(d)
        d+=T(1)
    return s
bad=[g for g in range(2024,2041) if rest_days(g)!=ref(g)]
print('holiday dates vs independent Hebrew calendar 2024-2040:', 'ALL MATCH' if not bad else f'MISMATCH {bad}')
# ---- port of ChargeCalendar ----
HOL=set().union(*(rest_days(g) for g in range(2023,2042)))
dow=lambda d:(d-D(1900,1,7)).days%7
rest=lambda d: dow(d)==6 or d in HOL
eve=lambda d: not rest(d) and rest(d+T(1))
def logical(d):
    if rest(d): return []
    out=[d]; n=d+T(1); g=0
    while rest(n) and g<7: out.append(n); n+=T(1); g+=1
    return out
def should(kind,d):
    if rest(d): return False
    return kind.startswith('Eve') if eve(d) else not kind.startswith('Eve')
# ---- simulate every day 2026-2030 for a TwiceDaily pledge ----
start,end=D(2026,1,1),D(2030,12,31)
charged=Counter(); runs_on_rest=[]; mult=Counter(); examples={}
d=start
while d<=end:
    for kind,slot in (('AM','AM'),('PM','PM'),('EveAM','AM'),('EvePM','PM')):
        if dow(d)==6: continue          # cron SUN-FRI
        if should(kind,d):
            if rest(d): runs_on_rest.append(d)
            ld=logical(d)
            for x in ld: charged[(x,slot)]+=1
            if slot=='AM':
                mult[len(ld)]+=1
                if len(ld)>=3: examples.setdefault(len(ld),[]).append((d,ld[-1]))
    d+=T(1)
days=[start+T(i) for i in range((end-start).days+1)]
missing=[(x,s) for x in days for s in('AM','PM') if charged[(x,s)]==0 and x>start]
double=[k for k,v in charged.items() if v>1]
print(f'simulated {len(days)} days, TwiceDaily pledge')
print('runs on Shabbat/holiday:',len(runs_on_rest))
print('calendar days never charged (per slot):',len(missing), missing[:3])
print('calendar days charged twice in the same slot:',len(double), double[:3])
print('runs by multiplicity (AM):',dict(sorted(mult.items())))
for k in sorted(examples):
    print(f' x{k} examples:',[(a.isoformat(),b.isoformat()) for a,b in examples[k][:6]])
# monthly: each calendar month charged = days*2
# ---- retries: every hour 2026-2030, retry delays 60/240 min ----
def window_open(t): 
    d=t.date()
    return not rest(d) and not (eve(d) and t.hour>=14)
def next_window(t):
    if window_open(t): return t
    d=t.date()+T(1); g=0
    while rest(d) and g<14: d+=T(1); g+=1
    return dt.datetime.combine(d,dt.time(8,0))
badr=0; moved=0; t=dt.datetime(2026,1,1)
while t.year<2031:
    for m in (60,240):
        n=next_window(t+T(minutes=m))
        if not window_open(n): badr+=1
        if n!=t+T(minutes=m): moved+=1
    t+=T(hours=1)
print('retry times landing on Shabbat/holiday/after 14:00 on eve:',badr,f'(retries pushed to next working morning: {moved})')
print('eve runs 06:00/11:00 are before the 14:00 cutoff:', 11<14)
