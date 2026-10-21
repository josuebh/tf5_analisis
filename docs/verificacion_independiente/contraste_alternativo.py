# Second, structurally different implementation (dense day x hour arrays) to cross-check
import os
import glob, json
import numpy as np, pandas as pd
from scipy import stats
BASE = os.environ.get("TF5_BASE", os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")))
h = pd.concat([pd.read_csv(f, dtype={'fecha': str}) for f in sorted(glob.glob(f'{BASE}/datos/horarios/tf5_horario_*.csv.gz'))], ignore_index=True)
LANES = {(85,'a'):[1,2,3,4],(85,'d'):[-1,-2,-3],(93,'a'):[1,2,3,4],(93,'d'):[-1,-2,-3,-4],(97,'a'):[1,2,3],(97,'d'):[-1,-2,-3],
         (99,'a'):[1,2,3],(99,'d'):[-1,-2,-3,-4],(103,'a'):[1,2],(103,'d'):[-1,-2],(111,'a'):[1,2],(111,'d'):[-1,-2],(123,'a'):[1,2,3],(123,'d'):[-1,-2,-3]}
hol = set(pd.read_csv(f'{BASE}/datos/festivos_canarias.csv').fecha)
days = pd.date_range('2024-09-01', '2026-09-30', freq='D')
days = days[~((days >= '2024-12-01') & (days <= '2024-12-31'))]
dstr = days.strftime('%Y-%m-%d'); didx = {d: i for i, d in enumerate(dstr)}
h['di'] = h.fecha.str[:10].map(didx); h['hh'] = h.fecha.str[11:13].astype(int)
R = [f'rango{i}_vehiculos' for i in range(1, 7)]
work = np.array([(d.dayofweek < 5) and (d.strftime('%Y-%m-%d') not in hol) for d in days])
month = np.array(dstr.str[:7]); year = np.array(dstr.str[:4].astype(int))
res = {}
store = {}
for (e, s), lanes in LANES.items():
    z = h[(h.estacion_id == e) & h.carril_id.isin(lanes)]
    nD = len(days)
    VEH = np.zeros((nD, 24)); LEN = np.zeros((nD, 24)); RS = np.zeros((nD, 24)); NEG = np.zeros((nD, 24), bool)
    LANESEEN = np.zeros((nD, 24, len(lanes)), bool)
    li = {l: k for k, l in enumerate(lanes)}
    np.add.at(VEH, (z.di.values, z.hh.values), (z.ligeros + z.pesados).values)
    np.add.at(LEN, (z.di.values, z.hh.values), z.rango1_vehiculos.values)
    np.add.at(RS, (z.di.values, z.hh.values), z[R].sum(axis=1).values)
    negrow = (z[R] < 0).any(axis=1).values
    np.logical_or.at(NEG, (z.di.values, z.hh.values), negrow)
    LANESEEN[z.di.values, z.hh.values, z.carril_id.map(li).values] = True
    complete = LANESEEN.all(axis=2)
    present = LANESEEN.any(axis=2)
    CU = np.where(~NEG & (RS > 0), LEN / np.where(RS > 0, RS, 1), np.nan)
    full = complete.all(axis=1) & work
    tot = VEH.sum(axis=1)
    valid = np.zeros(nD, bool)
    for m in np.unique(month):
        idx = np.where((month == m) & full)[0]
        if len(idx) == 0: continue
        med = np.median(tot[idx])
        ok = idx[tot[idx] / med >= 0.85]
        if m[5:7] != '08': valid[ok] = True
    night = CU[valid][:, :5]; Ln = LEN[valid][:, :5]; Rn = RS[valid][:, :5]
    msk = ~np.isnan(night)
    base = Ln[msk].sum() / Rn[msk].sum() if msk.any() else np.nan
    hv = (~np.isnan(CU[valid])).mean() if valid.any() else np.nan
    fiable = (hv >= 0.9) and (not np.isnan(base)) and base < 0.6
    C = (~np.isnan(CU)) & (np.nan_to_num(CU, nan=-1) >= 0.6) & ((np.nan_to_num(CU, nan=-9) - base) >= 0.3) & fiable
    store[(e, s)] = dict(valid=valid, C=C, CU=CU, VEH=VEH)
    v25 = valid & (year == 2025)
    spd = ~np.isnan(CU).any(axis=1)
    hrs = C[v25 & spd].sum(axis=1)
    res[f'{e}-{s}'] = dict(valid_days=int(valid.sum()), base=round(float(base), 4), fiable=bool(fiable),
                           d2025=int(v25.sum()), med=float(np.median(hrs)) if len(hrs) else None,
                           p25=float(np.quantile(hrs, .25)) if len(hrs) else None, p75=float(np.quantile(hrs, .75)) if len(hrs) else None,
                           zero=int((hrs == 0).sum()),
                           cov_complete=round(complete.sum() / complete.size, 4), cov_speed=round((complete & ~np.isnan(CU)).sum() / complete.size, 4))
print('TOTAL valid', sum(r['valid_days'] for r in res.values()))
for k, r in res.items(): print(k, r)
# item 3
def timing(e, s, yr, hours):
    st = store[(e, s)]; v = st['valid'] & (year == yr)
    rows = []
    for i in np.where(v)[0]:
        cu = st['CU'][i, hours]
        if np.isnan(cu).any(): continue
        cc = np.array(hours)[st['C'][i, hours]]
        rows.append((len(cc), cc.min() if len(cc) else np.nan, cc.max() + 1 if len(cc) else np.nan))
    a = np.array(rows, float)
    return len(a), int((~np.isnan(a[:, 1])).sum()), np.nanmedian(a[:, 1]), np.nanmedian(a[:, 2])
for e, s, hrs in [(103, 'd', list(range(3, 13))), (99, 'a', list(range(11, 24)))]:
    for yr in (2025, 2026): print('timing', e, s, yr, timing(e, s, yr, hrs))
# item 4
st = store[(103, 'd')]; m25 = st['valid'] & (year == 2025)
d1 = st['VEH'][m25][st['C'][m25]]
print('desc1', len(d1), np.median(d1), np.quantile(d1, .1), np.quantile(d1, .9))
s99 = store[(99, 'a')]; s103 = store[(103, 'a')]
mask = (s99['C'] & (s99['valid'] & (year == 2025))[:, None]) & (s103['valid'] & (year == 2025))[:, None]
d2 = s103['VEH'][mask]
print('desc2', len(d2), np.median(d2), np.quantile(d2, .1), np.quantile(d2, .9))
# item 5
A = ["2024-10", "2024-11", "2025-02", "2025-03", "2025-04", "2025-05"]; B = ["2025-10", "2025-11", "2026-02", "2026-03", "2026-04", "2026-05"]
for e in (93, 99, 103):
    st = store[(e, 'd')]
    ia = st['valid'] & np.isin(month, A); ib = st['valid'] & np.isin(month, B)
    v = st['VEH'][:, 7] + st['VEH'][:, 8]
    cola = st['C'][:, 5:12].sum(axis=1)
    print('ULL', e, ia.sum(), ib.sum(), v[ia].mean(), v[ib].mean(), cola[ia].mean(), cola[ib].mean())
# item 6
st = store[(99, 'd')]
for m in ["2025-06", "2025-07", "2025-09", "2026-06", "2026-07", "2026-09"]:
    i = st['valid'] & (month == m)
    print('pasarela 99d', m, i.sum(), st['C'][i, 5:12].sum(axis=1).mean())
# item 7
MA = [f"2025-{m:02d}" for m in (1, 2, 3, 4, 5, 6, 7, 9)]; MB = [f"2026-{m:02d}" for m in (1, 2, 3, 4, 5, 6, 7, 9)]
for e, s in [(103, 'd'), (99, 'a')]:
    st = store[(e, s)]
    a = st['C'][st['valid'] & np.isin(month, MA)].sum(axis=1); b = st['C'][st['valid'] & np.isin(month, MB)].sum(axis=1)
    t = stats.ttest_ind(b, a, equal_var=False)
    print('2026v2025', e, s, len(a), len(b), a.mean(), b.mean(), t.pvalue)
