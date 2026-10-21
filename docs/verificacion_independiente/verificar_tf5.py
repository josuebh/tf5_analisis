# -*- coding: utf-8 -*-
"""
Independent recomputation of measured TF-5 traffic figures (Python/pandas).

Definitions mirror R/07_datos_horarios.R, R/10_validacion_escenarios.R,
R/03_saturacion.R and main.R (read only for definitions; R code not executed).
Inputs (read-only): <project>/datos/... (project folder = two levels up, or env TF5_BASE)
Outputs: results.json, results.csv, plus intermediate CSVs, in this folder.
"""
import glob
import json
import os

import numpy as np
import pandas as pd
from scipy import stats

BASE = os.environ.get("TF5_BASE", os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")))
OUT = os.path.dirname(os.path.abspath(__file__))

EST_CORREDOR = [85, 93, 97, 99, 103, 111, 123]
ESTACIONES_TF5 = [82, 83, 85, 93, 97, 99, 103, 111, 123, 131, 133, 134, 136, 138]
NOMBRES = {85: "Hospital Residencia", 93: "Campus Guajara", 97: "Padre Anchieta",
           99: "Bomberos La Laguna", 103: "Ermita Cruz Chica", 111: "La Matanza", 123: "La Orotava"}
UMBRAL_LENTO = 0.60   # share of vehicles in speed range 1 (< 80 km/h)
EXCESO_LENTO = 0.30   # ... and >= 30 points above the station-direction night baseline
RANGOS = [f"rango{i}_vehiculos" for i in range(1, 7)]

results = {}          # nested dict -> results.json
rows = []             # long table -> results.csv


def put(item, metric, value, station=None, direction=None, period=None, definition=""):
    if isinstance(value, (np.integer,)):
        value = int(value)
    elif isinstance(value, (np.floating,)):
        value = float(value)
    rows.append(dict(item=item, station=station, direction=direction, period=period,
                     metric=metric, value=value, definition=definition))
    return value


def q7(x, p):
    """R quantile type 7 (default) == numpy 'linear'. NaN-free input expected."""
    x = np.asarray(x, dtype=float)
    x = x[~np.isnan(x)]
    if len(x) == 0:
        return float("nan")
    return float(np.quantile(x, p, method="linear"))


# ---------------------------------------------------------------------------
# 1. Lane catalogue (official JSON) -> lane type and principal lanes per direction
# ---------------------------------------------------------------------------
def tipo_carril(desc):
    d = desc.lower()
    if "bus" in d:
        return "bus"
    if "acceso" in d:
        return "acceso"
    if "salida" in d:
        return "salida"
    return "principal"


js = json.load(open(f"{BASE}/datos/oficial/rango-de-velocidades-de-los-carriles.json", encoding="utf-8"))
car = pd.DataFrame([
    dict(estacion_id=int(e["estacion_id"]), carril_id=int(c["carril_id"]),
         carril_descripcion=c["carril_descripcion"].strip(), rango1_max=c["rangos"][0]["rango1_max"])
    for e in js["estaciones"] for c in e["carriles"]])
car["sentido"] = np.where(car.carril_id > 0, "ascendente", "descendente")
car["tipo"] = car.carril_descripcion.map(tipo_carril)
assert not car.duplicated(["estacion_id", "carril_id"]).any(), "duplicate lanes in catalogue"
cs = (car[car.estacion_id.isin(ESTACIONES_TF5)]
      .assign(pr=lambda d: d.tipo.eq("principal"))
      .groupby(["estacion_id", "sentido"], as_index=False)
      .agg(carriles_principales=("pr", "sum"),
           umbral_kmh=("rango1_max", "min")))
carriles_csv = pd.read_csv(f"{BASE}/datos/carriles_tf5.csv")
chk = carriles_csv.merge(cs, on=["estacion_id", "sentido"], how="left")
lane_mismatch = chk[chk.carriles != chk.carriles_principales]

# ---------------------------------------------------------------------------
# 2. Hourly records -> prepared table (preparar_horarios)
# ---------------------------------------------------------------------------
fs = sorted(glob.glob(f"{BASE}/datos/horarios/tf5_horario_*.csv.gz"))
h = pd.concat([pd.read_csv(f, dtype={"fecha": str}) for f in fs], ignore_index=True)
fest = pd.read_csv(f"{BASE}/datos/festivos_canarias.csv", dtype={"fecha": str})
festivos = set(fest.fecha)

h = h.merge(car[["estacion_id", "carril_id", "tipo", "rango1_max"]], on=["estacion_id", "carril_id"], how="left")
h["veh"] = h.ligeros + h.pesados
h["rsum"] = h[RANGOS].sum(axis=1)
h["neg"] = (h[RANGOS] < 0).any(axis=1)
h["dia"] = h.fecha.str[:10]
h["hora"] = h.fecha.str[11:13].astype(int)
h["mes"] = h.fecha.str[:7]
h["anio"] = h.fecha.str[:4].astype(int)
h["sentido"] = np.where(h.carril_id > 0, "ascendente", "descendente")
h["dow"] = pd.to_datetime(h.dia).dt.dayofweek + 1          # 1 = Monday ... 7 = Sunday (R %u)
h["festivo"] = h.dia.isin(festivos)
h["laborable"] = (h.dow <= 5) & ~h.festivo

# ---------------------------------------------------------------------------
# 3. Aggregate by station, direction, hour over principal lanes (agregar_por_sentido)
#    NB: like the R code, key-duplicates are NOT removed (they only occur on the
#    two spring DST Sundays at 02:00, which are never working days).
# ---------------------------------------------------------------------------
p = h[h.estacion_id.isin(EST_CORREDOR) & h.tipo.eq("principal")]
sd = (p.groupby(["estacion_id", "sentido", "anio", "mes", "dia", "hora", "laborable"], as_index=False)
       .agg(veh=("veh", "sum"), pesados=("pesados", "sum"), lento=("rango1_vehiculos", "sum"),
            rsum=("rsum", "sum"), ncar=("carril_id", "nunique"), neg=("neg", "any")))
sd = sd.merge(cs[["estacion_id", "sentido", "carriles_principales"]].rename(columns={"carriles_principales": "carriles"}),
              on=["estacion_id", "sentido"], how="left")
sd["completa"] = sd.ncar == sd.carriles
sd["cuota_lenta"] = np.where(~sd.neg & (sd.rsum > 0), sd.lento / sd.rsum.where(sd.rsum > 0), np.nan)

# ---------------------------------------------------------------------------
# 4. Valid days (dias_validos): working day, not holiday, every hour complete
#    (24 complete hours), daily total >= 0.85 x median of that station-direction-
#    month (median over working days with 24 complete hours), not August.
# ---------------------------------------------------------------------------
x = (sd[sd.laborable & sd.completa]
     .groupby(["estacion_id", "sentido", "anio", "mes", "dia"], as_index=False)
     .agg(horas=("hora", "size"), v=("veh", "sum")))
x = x[x.horas == 24].copy()
x["rel"] = x.v / x.groupby(["estacion_id", "sentido", "mes"]).v.transform("median")
dv = x[(x.rel >= 0.85) & (x.mes.str[5:7] != "08")][["estacion_id", "sentido", "anio", "mes", "dia", "v"]].copy()
dv.to_csv(f"{OUT}/dias_validos.csv", index=False)

# Variant without the 85 % rule and with it (diagnostics)
n_24h_workdays_noaug = int((x.mes.str[5:7] != "08").sum())

# ---------------------------------------------------------------------------
# 5. Night baseline, speed reliability, congestion flag
# ---------------------------------------------------------------------------
key3 = ["estacion_id", "sentido", "dia"]
sv = sd.merge(dv[key3], on=key3, how="inner")            # semi-join (dv is unique on key3)
assert len(sv) == 24 * len(dv)
nb = sv[(sv.hora <= 4) & sv.cuota_lenta.notna()].groupby(["estacion_id", "sentido"])[["lento", "rsum"]].sum()
base = (nb.lento / nb.rsum).rename("base_noche").reset_index()
fiab = (sv.assign(hv=sv.cuota_lenta.notna())
          .groupby(["estacion_id", "sentido"], as_index=False).agg(horas_con_velocidad=("hv", "mean"))
          .merge(base, on=["estacion_id", "sentido"], how="left"))
fiab["velocidad_fiable"] = (fiab.horas_con_velocidad >= 0.9) & fiab.base_noche.notna() & (fiab.base_noche < 0.6)
sc = sv.merge(base, on=["estacion_id", "sentido"], how="left").merge(
    fiab[["estacion_id", "sentido", "velocidad_fiable"]], on=["estacion_id", "sentido"], how="left")
cong = sc.cuota_lenta.notna() & (sc.cuota_lenta >= UMBRAL_LENTO) & ((sc.cuota_lenta - sc.base_noche) >= EXCESO_LENTO)
sc["congestionada"] = cong.fillna(False) & sc.velocidad_fiable
sc.to_csv(f"{OUT}/horas_dias_validos.csv.gz", index=False)
fiab.to_csv(f"{OUT}/fiabilidad_velocidad.csv", index=False)

# ===========================================================================
# ITEM 1: number of valid station-direction-days
# ===========================================================================
results["item1"] = dict(
    valid_station_direction_days=put("1", "valid_station_direction_days", len(dv),
                                     definition="rows of dias_validos over 7 stations x 2 directions, 24 months"),
    by_year=dv.groupby("anio").size().to_dict(),
    by_station_direction={f"{e}-{s}": int(n) for (e, s), n in dv.groupby(["estacion_id", "sentido"]).size().items()},
    workdays_24h_complete_not_august_before_85pct_rule=n_24h_workdays_noaug,
)
for (e, s), n in dv.groupby(["estacion_id", "sentido"]).size().items():
    put("1", "valid_days", int(n), e, s, "2024-09..2026-09")

results["speed_reliability"] = {
    f"{r.estacion_id}-{r.sentido}": dict(horas_con_velocidad=round(float(r.horas_con_velocidad), 4),
                                         base_noche=None if pd.isna(r.base_noche) else round(float(r.base_noche), 4),
                                         velocidad_fiable=bool(r.velocidad_fiable))
    for r in fiab.itertuples()}
for r in fiab.itertuples():
    put("aux", "night_baseline_share_lt80", None if pd.isna(r.base_noche) else float(r.base_noche), r.estacion_id, r.sentido, "all valid days")
    put("aux", "share_valid_hours_with_speed", float(r.horas_con_velocidad), r.estacion_id, r.sentido, "all valid days")
    put("aux", "speed_reliable", bool(r.velocidad_fiable), r.estacion_id, r.sentido, "all valid days")

# ===========================================================================
# ITEM 2: congested hours per valid day in 2025 (resumen_congestion)
# ===========================================================================
def resumen_congestion(sc, anios):
    d = sc[sc.anio.isin(anios)]
    g = d.groupby(["estacion_id", "sentido", "dia"])
    per_day = g.agg(horas=("congestionada", "sum")).join(
        g.cuota_lenta.apply(lambda s: s.notna().all()).rename("velocidad_valida")).reset_index()
    out = {}
    for (e, s), z in per_day.groupby(["estacion_id", "sentido"]):
        hv = z.horas[z.velocidad_valida].to_numpy(dtype=float)
        out[(e, s)] = dict(dias=len(z), dias_con_velocidad=int(z.velocidad_valida.sum()),
                           horas_media=float(np.mean(hv)) if len(hv) else float("nan"),
                           p25=q7(hv, 0.25), mediana=q7(hv, 0.5), p75=q7(hv, 0.75),
                           dias_sin_congestion=int((hv == 0).sum()))
    return out, per_day


rc, per_day_2025 = resumen_congestion(sc, [2025])
item2 = {}
for e, s in [(103, "descendente"), (99, "ascendente"), (99, "descendente"), (93, "descendente"),
             (93, "ascendente"), (103, "ascendente")]:
    r = rc[(e, s)]
    item2[f"{e}-{s}"] = r
    for k in ["dias", "dias_con_velocidad", "mediana", "p25", "p75", "dias_sin_congestion", "horas_media"]:
        put("2", k, r[k], e, s, "2025", "congested hour: share<80km/h >= 0.60 and >= base+0.30; forced FALSE if speed unreliable; stats over days with speed in all 24 h")
results["item2"] = item2
results["item2_all_station_directions"] = {f"{e}-{s}": v for (e, s), v in rc.items()}

# ===========================================================================
# ITEM 3: queue timing (horario_cola / resumen_horario)
# ===========================================================================
def horario_cola(sc, est, sen, anio, horas):
    d = sc[(sc.anio == anio) & (sc.estacion_id == est) & (sc.sentido == sen) & sc.hora.isin(horas)]
    out = []
    for dia, z in d.groupby("dia"):
        if len(z) != len(horas) or z.cuota_lenta.isna().any():
            continue
        hc = z.hora[z.congestionada]
        out.append(dict(dia=dia, horas_cola=int(z.congestionada.sum()),
                        inicio=float(hc.min()) if len(hc) else np.nan,
                        fin=float(hc.max() + 1) if len(hc) else np.nan))
    return pd.DataFrame(out)


item3 = {}
for (e, s, horas, lbl) in [(103, "descendente", list(range(3, 13)), "morning 103 desc, hours 3-12"),
                           (99, "ascendente", list(range(11, 24)), "afternoon 99 asc, hours 11-23")]:
    for anio in (2025, 2026):
        hc = horario_cola(sc, e, s, anio, horas)
        hc.to_csv(f"{OUT}/horario_cola_{e}_{s}_{anio}.csv", index=False)
        r = dict(window=lbl, dias=len(hc), dias_con_cola=int(hc.inicio.notna().sum()),
                 horas_cola_mediana=q7(hc.horas_cola, 0.5), horas_cola_media=float(hc.horas_cola.mean()),
                 inicio_mediana=q7(hc.inicio, 0.5), fin_mediana=q7(hc.fin, 0.5),
                 inicio_p10=q7(hc.inicio, 0.1), inicio_p25=q7(hc.inicio, 0.25), inicio_p75=q7(hc.inicio, 0.75), inicio_p90=q7(hc.inicio, 0.9),
                 fin_p10=q7(hc.fin, 0.1), fin_p25=q7(hc.fin, 0.25), fin_p75=q7(hc.fin, 0.75), fin_p90=q7(hc.fin, 0.9),
                 inicio_moda=float(hc.inicio.mode().min()) if hc.inicio.notna().any() else None,
                 fin_moda=float(hc.fin.mode().min()) if hc.fin.notna().any() else None)
        item3[f"{e}-{s}-{anio}"] = r
        for k in ["dias", "dias_con_cola", "inicio_mediana", "fin_mediana", "horas_cola_mediana",
                  "inicio_p10", "inicio_p90", "fin_p10", "fin_p90"]:
            put("3", k, r[k], e, s, str(anio), "valid days with speed in every hour of the window; start=min congested hour, end=max+1")
results["item3"] = item3

# ===========================================================================
# ITEM 4: discharge flows (unwindowed variant; in main.R, desc1 / desc2 are the windowed variant of validacion_modelo, 620 h)
# ===========================================================================
s25 = sc[sc.anio == 2025]
desc1 = s25[(s25.estacion_id == 103) & (s25.sentido == "descendente") & s25.congestionada].veh.to_numpy(float)
cola99 = s25[(s25.estacion_id == 99) & (s25.sentido == "ascendente") & s25.congestionada][["dia", "hora"]]
desc2 = s25[(s25.estacion_id == 103) & (s25.sentido == "ascendente")].merge(cola99, on=["dia", "hora"]).veh.to_numpy(float)
n_cola99 = len(cola99)
# windowed (validacion_modelo): queue hours restricted to the calibration window
desc1w = s25[(s25.estacion_id == 103) & (s25.sentido == "descendente") & s25.congestionada & s25.hora.between(3, 12)].veh.to_numpy(float)
cola99w = cola99[cola99.hora.between(11, 23)]
desc2w = s25[(s25.estacion_id == 103) & (s25.sentido == "ascendente")].merge(cola99w, on=["dia", "hora"]).veh.to_numpy(float)
item4 = {}
for nm, arr, dfn in [("morning_103desc_own_congested_hours", desc1, "veh/h at 103 desc in its congested hours, 2025 (all hours)"),
                     ("afternoon_103asc_when_99asc_congested", desc2, "veh/h at 103 asc in hours when 99 asc congested, 2025 (103-asc valid days only)"),
                     ("morning_windowed_3_12", desc1w, "as morning, congested hours restricted to 3-12 (validacion_modelo)"),
                     ("afternoon_windowed_11_23", desc2w, "as afternoon, 99 asc congested hours restricted to 11-23 (validacion_modelo)")]:
    r = dict(horas=len(arr), mediana=q7(arr, 0.5), p10=q7(arr, 0.1), p90=q7(arr, 0.9),
             media=float(arr.mean()) if len(arr) else None, definition=dfn)
    item4[nm] = r
    for k in ["horas", "mediana", "p10", "p90"]:
        put("4", k, r[k], None, nm, "2025", dfn)
item4["afternoon_99asc_congested_hours_2025_total"] = n_cola99
results["item4"] = item4

# ===========================================================================
# ITEM 5: ULL staggered timetables (did_ull logic, teaching months)
# ===========================================================================
ANTES = ["2024-10", "2024-11", "2025-02", "2025-03", "2025-04", "2025-05"]
DESPUES = ["2025-10", "2025-11", "2026-02", "2026-03", "2026-04", "2026-05"]
JUL_A, JUL_D = ["2025-07"], ["2026-07"]


def por_dia(sc, est, sen, horas_v=(7, 8), horas_cola=range(5, 12)):
    d = sc[(sc.estacion_id == est) & (sc.sentido == sen)]
    out = []
    for (mes, dia), z in d.groupby(["mes", "dia"]):
        v = z.veh[z.hora.isin(horas_v)].sum()
        zc = z[z.hora.isin(list(horas_cola))]
        ok = bool(z.velocidad_fiable.iloc[0]) and zc.cuota_lenta.notna().all()
        cola = float(zc.congestionada.sum()) if ok else np.nan
        out.append(dict(mes=mes, dia=dia, v=float(v), v_dia=float(z.veh.sum()), cola=cola))
    return pd.DataFrame(out)


item5 = {}
for e in (93, 99, 103):
    d = por_dia(sc, e, "descendente")
    d.to_csv(f"{OUT}/por_dia_{e}_descendente.csv", index=False)
    a = d[d.mes.isin(ANTES)]
    b = d[d.mes.isin(DESPUES)]
    ja, jd = d[d.mes.isin(JUL_A)], d[d.mes.isin(JUL_D)]
    r = dict(dias_antes=len(a), dias_despues=len(b),
             veh_7_9_antes=float(a.v.mean()), veh_7_9_despues=float(b.v.mean()),
             dif=float(b.v.mean() - a.v.mean()),
             dias_por_mes_antes=a.groupby("mes").size().to_dict(), dias_por_mes_despues=b.groupby("mes").size().to_dict(),
             # supplementary: July control and simple DiD point estimate (no bootstrap)
             veh_7_9_julio_2025=float(ja.v.mean()), veh_7_9_julio_2026=float(jd.v.mean()),
             did_veh_julio_control=float((b.v.mean() - a.v.mean()) - (jd.v.mean() - ja.v.mean())))
    ca, cb = a.cola.dropna(), b.cola.dropna()
    r.update(dias_cola_antes=len(ca), dias_cola_despues=len(cb),
             cola_5_12_antes=float(ca.mean()) if len(ca) else None,
             cola_5_12_despues=float(cb.mean()) if len(cb) else None)
    item5[f"{e}-descendente"] = r
    put("5", "mean_veh_hours_7_8_before", r["veh_7_9_antes"], e, "descendente", "teaching months 2024-25", "sum of veh in hours 7 and 8 per valid day, mean over days")
    put("5", "mean_veh_hours_7_8_after", r["veh_7_9_despues"], e, "descendente", "teaching months 2025-26", "")
    put("5", "days_before", r["dias_antes"], e, "descendente", "teaching months 2024-25", "")
    put("5", "days_after", r["dias_despues"], e, "descendente", "teaching months 2025-26", "")
    if e == 103:
        put("5", "mean_congested_hours_5_11_before", r["cola_5_12_antes"], e, "descendente", "teaching months 2024-25",
            "days with reliable speed station and speed in all hours 5-11")
        put("5", "mean_congested_hours_5_11_after", r["cola_5_12_despues"], e, "descendente", "teaching months 2025-26", "")
        put("5", "days_cola_before", r["dias_cola_antes"], e, "descendente", "teaching months 2024-25", "")
        put("5", "days_cola_after", r["dias_cola_despues"], e, "descendente", "teaching months 2025-26", "")
results["item5"] = item5

# ===========================================================================
# ITEM 6: footbridge, 99 descendente, congested hours 5-11 (dif_interanual logic)
# ===========================================================================
d99 = por_dia(sc, 99, "descendente")
item6 = {}
for m in ["2025-06", "2025-07", "2025-09", "2026-06", "2026-07", "2026-09"]:
    z = d99[d99.mes == m]
    zc = z.cola.dropna()
    item6[m] = dict(dias_validos=len(z), dias_con_velocidad=len(zc),
                    cola_media=float(zc.mean()) if len(zc) else None)
    put("6", "mean_congested_hours_5_11", item6[m]["cola_media"], 99, "descendente", m, "valid days with speed in all hours 5-11")
    put("6", "days", item6[m]["dias_con_velocidad"], 99, "descendente", m, "")
for m in ["2026-06", "2026-07", "2026-09"]:
    a = d99[d99.mes == m.replace("2026", "2025")].cola.dropna()
    b = d99[d99.mes == m].cola.dropna()
    if len(a) >= 2 and len(b) >= 2:
        t = stats.ttest_ind(b, a, equal_var=False)
        item6[m]["welch_p_vs_2025"] = float(t.pvalue)
# Same for 93 and 103 desc (supplementary, same logic)
supp6 = {}
for e in (93, 103):
    dd = por_dia(sc, e, "descendente")
    supp6[e] = {m: (None if dd[dd.mes == m].cola.dropna().empty else float(dd[dd.mes == m].cola.dropna().mean()))
                for m in ["2025-06", "2025-07", "2025-09", "2026-06", "2026-07", "2026-09"]}
results["item6"] = item6
results["item6_supplementary_93_103_desc"] = {str(k): v for k, v in supp6.items()}

# ===========================================================================
# ITEM 7: 2026 vs 2025, Jan-Sep without August (comparar_periodos logic)
# ===========================================================================
MA = [f"2025-{m:02d}" for m in (1, 2, 3, 4, 5, 6, 7, 9)]
MB = [f"2026-{m:02d}" for m in (1, 2, 3, 4, 5, 6, 7, 9)]
item7 = {}
for e, s in [(103, "descendente"), (99, "ascendente")]:
    d = sc[(sc.estacion_id == e) & (sc.sentido == s) & sc.mes.isin(MA + MB)]
    g = d.groupby(["mes", "dia"])
    pdd = g.agg(horas_cong=("congestionada", "sum")).reset_index()
    pdd["lenta_ok"] = g.apply(lambda z: z.cuota_lenta[z.hora.isin([7, 8])].notna().all()).to_numpy()
    a = pdd[pdd.mes.isin(MA)]
    b = pdd[pdd.mes.isin(MB)]
    con_vel = (a.lenta_ok.sum() >= 5) and (b.lenta_ok.sum() >= 5)
    t = stats.ttest_ind(b.horas_cong.astype(float), a.horas_cong.astype(float), equal_var=False)
    ci = t.confidence_interval(0.95)
    r = dict(dias_2025=len(a), dias_2026=len(b), horas_cong_2025=float(a.horas_cong.mean()),
             horas_cong_2026=float(b.horas_cong.mean()), dif=float(b.horas_cong.mean() - a.horas_cong.mean()),
             welch_t=float(t.statistic), welch_df=float(t.df), welch_p=float(t.pvalue),
             ic95=[float(ci.low), float(ci.high)], con_vel=bool(con_vel))
    item7[f"{e}-{s}"] = r
    for k in ["dias_2025", "dias_2026", "horas_cong_2025", "horas_cong_2026", "welch_p"]:
        put("7", k, r[k], e, s, "Jan-Sep excl. Aug", "congested hours over all 24 h per valid day; Welch two-sided")
results["item7"] = item7

# ===========================================================================
# ITEM 8: coverage of Padre Anchieta (cobertura_calidad, summed over 24 months)
# ===========================================================================
meses = sorted(sd.mes.unique())
dias_mes = {m: pd.Period(m, "M").days_in_month for m in meses}
horas_total = 24 * sum(dias_mes.values())
item8 = {"months": len(meses), "hours_in_period": horas_total}
for s in ("ascendente", "descendente"):
    z = sd[(sd.estacion_id == 97) & (sd.sentido == s)]
    hcd = len(z)
    hcomp = int(z.completa.sum())
    hvel = int((z.completa & z.cuota_lenta.notna()).sum())
    ndv = int(((dv.estacion_id == 97) & (dv.sentido == s)).sum())
    by_m = z.groupby("mes").agg(h=("hora", "size"), c=("completa", "sum"),
                                v=("cuota_lenta", lambda q: 0)).reset_index()
    vel_m = (z.completa & z.cuota_lenta.notna()).groupby(z.mes).sum()
    item8[s] = dict(horas_con_datos=hcd, pct_ausente=1 - hcd / horas_total,
                    horas_completas=hcomp, pct_horas_completas=hcomp / horas_total,
                    horas_velocidad=hvel, pct_horas_velocidad=hvel / horas_total, dias_validos=ndv,
                    pct_horas_velocidad_sobre_completas=hvel / hcomp if hcomp else None,
                    monthly_pct_completas={m: round(float(z[z.mes == m].completa.sum()) / (24 * dias_mes[m]), 4) for m in meses},
                    monthly_pct_velocidad={m: round(float(vel_m.get(m, 0)) / (24 * dias_mes[m]), 4) for m in meses})
    put("8", "pct_hours_all_lanes", hcomp / horas_total, 97, s, "24 months", "hours with every principal lane reported / all calendar hours in the 24 months")
    put("8", "pct_hours_usable_speed", hvel / horas_total, 97, s, "24 months", "complete hours with no negative speed ranges and range sum > 0 / all calendar hours")
    put("8", "valid_days", ndv, 97, s, "24 months", "")
results["item8"] = item8
# coverage of every corridor station-direction (supplementary)
cov_all = {}
for (e, s), z in sd.groupby(["estacion_id", "sentido"]):
    cov_all[f"{e}-{s}"] = dict(pct_completas=round(float(z.completa.sum()) / horas_total, 4),
                               pct_velocidad=round(float((z.completa & z.cuota_lenta.notna()).sum()) / horas_total, 4))
results["item8_supplementary_all_corridor"] = cov_all

# ===========================================================================
# ITEM 9: annual IMD
# ===========================================================================
imd = pd.read_csv(f"{BASE}/datos/imd_tf5_2018_2025.csv")
i25 = imd[imd.anio == 2025]
top = i25.loc[i25.imd_total == i25.imd_total.max()]
r103 = i25[i25.estacion_id == 103].iloc[0]
lanes103 = carriles_csv.set_index(["estacion_id", "sentido"]).carriles
item9 = dict(top_station_2025=[dict(estacion_id=int(t.estacion_id), estacion_nombre=t.estacion_nombre,
                                    imd_total=int(t.imd_total)) for t in top.itertuples()],
             st103_2025=dict(imd_ascendentes=int(r103.imd_ascendentes), imd_descendentes=int(r103.imd_descendentes),
                             carriles_asc=int(lanes103[(103, "ascendente")]), carriles_desc=int(lanes103[(103, "descendente")]),
                             veh_por_carril_asc=float(r103.imd_ascendentes / lanes103[(103, "ascendente")]),
                             veh_por_carril_desc=float(r103.imd_descendentes / lanes103[(103, "descendente")])))
# cross-check against the official 2025 CSV copy
try:
    of = pd.read_csv(f"{BASE}/datos/oficial/intensidad-media-diaria-de-trafico-2025.csv", dtype=str, encoding="utf-8-sig")
    of = of[of.carretera_codigo == "TF-5"]
    o103 = of[of.estacion_id.astype(float) == 103].iloc[0]
    item9["official_csv_103_2025"] = dict(imd_ascendentes=o103.imd_ascendentes, imd_descendentes=o103.imd_descendentes,
                                          imd_total=o103.imd_total)
    oo = of.assign(t=of.imd_total.astype(float)).sort_values("t", ascending=False).iloc[0]
    item9["official_csv_top_tf5_2025"] = dict(estacion_id=oo.estacion_id, estacion_nombre=oo.estacion_nombre, imd_total=oo.imd_total)
except Exception as ex:  # noqa
    item9["official_csv_check_error"] = str(ex)
put("9", "top_station_2025", f"{int(top.iloc[0].estacion_id)} {top.iloc[0].estacion_nombre}", None, None, "2025", "max imd_total among 2025 rows")
put("9", "top_station_2025_imd_total", int(top.iloc[0].imd_total), int(top.iloc[0].estacion_id), None, "2025", "")
put("9", "veh_per_lane_per_day", item9["st103_2025"]["veh_por_carril_asc"], 103, "ascendente", "2025", "imd_ascendentes / carriles_tf5.csv lanes")
put("9", "veh_per_lane_per_day", item9["st103_2025"]["veh_por_carril_desc"], 103, "descendente", "2025", "imd_descendentes / carriles_tf5.csv lanes")
results["item9"] = item9

# ===========================================================================
# ITEM 10: population CAGR
# ===========================================================================
pob = pd.read_csv(f"{BASE}/datos/poblacion_tenerife.csv")
a0, a1 = int(pob.anio.min()), int(pob.anio.max())
p0, p1 = float(pob.poblacion[pob.anio == a0].iloc[0]), float(pob.poblacion[pob.anio == a1].iloc[0])
cagr = (p1 / p0) ** (1 / (a1 - a0)) - 1
results["item10"] = dict(first_year=a0, last_year=a1, pop_first=p0, pop_last=p1, cagr=cagr)
put("10", "population_cagr", cagr, None, None, f"{a0}-{a1}", "(P_last/P_first)^(1/(last-first)) - 1")

# ---------------------------------------------------------------------------
# Data issues / diagnostics
# ---------------------------------------------------------------------------
c = h[h.estacion_id.isin(EST_CORREDOR)]
dup = c[c.duplicated(["estacion_id", "carril_id", "fecha"], keep=False)]
hours_per_day = h.groupby("dia").hora.nunique()
results["diagnostics"] = dict(
    files=len(fs), months=sorted(h.mes.unique()), rows_total=len(h), rows_corridor=len(c),
    na_values=int(h[["ligeros", "pesados"] + RANGOS].isna().sum().sum()),
    corridor_key_duplicates=int(c.duplicated(["estacion_id", "carril_id", "fecha"]).sum()),
    corridor_duplicate_days=sorted(dup.dia.unique().tolist()),
    days_not_24_distinct_hours={k: int(v) for k, v in hours_per_day[hours_per_day != 24].items()},
    uncatalogued_corridor_lane_rows=int(c.merge(car[["estacion_id", "carril_id"]], how="left", indicator=True)._merge.eq("left_only").sum()),
    negative_range_rows_by_station={int(k): int(v) for k, v in c.neg.groupby(c.estacion_id).sum().items()},
    lanes_json_vs_csv_mismatches=lane_mismatch[["estacion_id", "sentido", "carriles", "carriles_principales"]].to_dict("records"),
    speed_threshold_kmh_corridor=sorted(cs[cs.estacion_id.isin(EST_CORREDOR)].umbral_kmh.unique().tolist()),
    working_holidays_in_data=sorted(set(h.dia[h.festivo & (h.dow <= 5)].unique())),
    rows_veh_gt_2600=int((c.veh > 2600).sum()),
    rows_rsum_ne_veh=int((c.rsum != c.veh).sum()),
)

with open(f"{OUT}/results.json", "w", encoding="utf-8") as f:
    json.dump(results, f, ensure_ascii=False, indent=1, default=lambda o: o.item() if hasattr(o, "item") else str(o))
pd.DataFrame(rows).to_csv(f"{OUT}/results.csv", index=False)
print(json.dumps(results, ensure_ascii=False, indent=1, default=lambda o: o.item() if hasattr(o, "item") else str(o)))
