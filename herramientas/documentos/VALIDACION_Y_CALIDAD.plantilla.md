{% VD = lambda c, ind, per, col: v('validacion_diaria', col, caso=c, indicador=ind, periodo=per) %}
{% VM = lambda c, ind, col: v('validacion_modelo', col, caso=c, indicador=ind) %}
{% DESC = 'Caudal de descarga con cola (mediana)' %}
{% IGUAL = 'Caudal en las horas con cola, medido igual en el modelo y en el aforo (mediana de las medianas diarias)' %}
{% DIA_IGUAL = 'Descarga del día medida igual en el modelo y en el aforo' %}
{% P25 = '2025 (calibración)' %}
{% P26 = '2026 (validación, no usado)' %}
{% VAL = T('validacion_modelo') %}
{% FUERA = [x for x in VAL if x['dentro_2026'] != 'TRUE'] %}
{% FEN_FUERA = sorted(set((x['caso'], x['fenomeno']) for x in FUERA)) %}
{% NOMC = {'manana_hacia_santa_cruz': 'mañana', 'tarde_hacia_el_norte': 'tarde'} %}
{% FILA_TXT = lambda x: NOMC[x['caso']] + ', ' + ('parámetro de descarga' if x['indicador'] == DESC else ('descarga medida igual que el aforo' if x['indicador'] == IGUAL else x['indicador'].split(' (')[0].lower())) %}
{% OTRA_DENTRO = [x for x in FUERA if any(y['caso'] == x['caso'] and y['fenomeno'] == x['fenomeno'] and y['dentro_2026'] == 'TRUE' for y in VAL)] %}
{% FUERA_TXT = (('queda fuera de la banda de parámetros una sola fila' if len(FUERA) == 1 else 'quedan fuera de la banda de parámetros ' + str(len(FUERA)) + ' filas, de ' + str(len(FEN_FUERA)) + (' fenómeno' if len(FEN_FUERA) == 1 else ' fenómenos distintos')) + ' (' + '; '.join(FILA_TXT(x) for x in FUERA) + ')' + ('; la otra fila del mismo fenómeno queda dentro' if len(FUERA) == 1 and OTRA_DENTRO else '')) if FUERA else 'todas las filas quedan dentro de la banda de parámetros' %}
{% ESD = lambda x: es(x) if abs(x - round(x)) < 1e-9 else es(x, 1) %}
{% ELX = T('eleccion_especificacion') %}
{% ELEG = lambda c: [x for x in ELX if x['caso'] == CASOS[c] and x['elegida'] == 'TRUE'][0] %}
{% REF = lambda c: [x for x in ELX if x['caso'] == CASOS[c] and x['referencia'] == 'TRUE'][0] %}
{% describir = lambda x: (' + '.join([p for p, k in (('propagación de la cola del tramo siguiente', 'propagacion'), ('descarga dependiente de la hora', 'horario'), ('mezcla de pesados', 'pesados')) if x[k] == 'TRUE']) or 'descarga constante') + ('; descarga calibrada medida igual que en el aforo' if x['medida_descarga'] == 'como_aforo' else '; descarga calibrada como parámetro') %}
{% es_ref = lambda c: ELEG(c)['referencia'] == 'TRUE' %}
{% n_adm = lambda c: sum(1 for x in ELX if x['caso'] == CASOS[c] and x['admisible'] == 'TRUE') %}
{% n_var = lambda c: sum(1 for x in ELX if x['caso'] == CASOS[c]) - 1 %}
{% VCX = T('validacion_cruzada') %}
{% igual_spec = lambda x, e: all(x[k] == e[k] for k in ('propagacion', 'horario', 'pesados', 'medida_descarga')) %}
{% P26X = lambda c, e, ind, col: float([x for x in VCX if x['caso'] == CASOS[c] and x['prueba'] == '2026' and x['indicador'] == ind and igual_spec(x, e)][0][col]) %}
{% IND_DIA = 'Descarga del día (medida igual en el modelo y en el aforo)' %}
{% CVX = lambda c, e, ind, cal, col: float([x for x in VCX if x['caso'] == CASOS[c] and x['calibracion'] == cal and x['indicador'] == ind and igual_spec(x, e)][0][col]) %}
{% DIST = lambda c, e: (abs(CVX(c, e, IND_DIA, 'A', 'cobertura_intervalo_predictivo') - 0.8) + abs(CVX(c, e, IND_DIA, 'B', 'cobertura_intervalo_predictivo') - 0.8)) / 2 %}
{% COBTXT = lambda c: 'se acerca más al 80 %' if DIST(c, ELEG(c)) < DIST(c, REF(c)) - 0.005 else ('se aleja del 80 %' if DIST(c, ELEG(c)) > DIST(c, REF(c)) + 0.005 else 'queda a la misma distancia del 80 %') %}
{% COB26 = lambda c: (lambda e, r: ', igual que con la referencia.' if pct(e) == pct(r) else ', frente al ' + pct(r) + ' con la referencia' + (' (algo más lejos del 80 %)' if abs(e - 0.8) > abs(r - 0.8) + 0.005 else (' (más cerca del 80 %)' if abs(e - 0.8) < abs(r - 0.8) - 0.005 else '')) + '.')(P26X(c, ELEG(c), IND_DIA, 'cobertura_intervalo_predictivo'), P26X(c, REF(c), IND_DIA, 'cobertura_intervalo_predictivo')) %}
{% COB_FRASE = lambda c: f"La cobertura del intervalo predictivo del 80 % de esa descarga {COBTXT(c)} en la validación cruzada ({pct(CVX(c, ELEG(c), IND_DIA, 'A', 'cobertura_intervalo_predictivo'))} y {pct(CVX(c, ELEG(c), IND_DIA, 'B', 'cobertura_intervalo_predictivo'))} en las dos mitades con la elegida, frente a {pct(CVX(c, REF(c), IND_DIA, 'A', 'cobertura_intervalo_predictivo'))} y {pct(CVX(c, REF(c), IND_DIA, 'B', 'cobertura_intervalo_predictivo'))} con la referencia); en 2026 es del {pct(P26X(c, ELEG(c), IND_DIA, 'cobertura_intervalo_predictivo'))}" + COB26(c) + (f" Con la elegida, la banda de parámetros cubre menos días en 2026 ({pct(P26X(c, ELEG(c), IND_DIA, 'cobertura_banda_parametros'))} frente a {pct(P26X(c, REF(c), IND_DIA, 'cobertura_banda_parametros'))}): no es un fallo, porque la banda describe un día típico y no la variabilidad entre días." if P26X(c, ELEG(c), IND_DIA, 'cobertura_banda_parametros') < P26X(c, REF(c), IND_DIA, 'cobertura_banda_parametros') - 0.02 else "") %}
{% HORAS_IND = lambda c: sorted(set(x['indicador'] for x in VCX if x['caso'] == CASOS[c] and x['indicador'].startswith('Caudal de las'))) %}
{% IND_TAB = lambda c: ['Horas de cola al día', 'Inicio de la cola', 'Fin de la cola', IND_DIA] + HORAS_IND(c) %}
{% DCOB = lambda c: [100 * (abs(P26X(c, ELEG(c), ind, 'cobertura_intervalo_predictivo') - 0.8) - abs(P26X(c, REF(c), ind, 'cobertura_intervalo_predictivo') - 0.8)) for ind in IND_TAB(c)] %}
{% COB_RES = lambda c: f"De los {len(IND_TAB(c))} indicadores de la tabla, con la elegida la cobertura del intervalo predictivo en 2026 se acerca al 80 % en {sum(1 for d in DCOB(c) if d < -0.5)}, se aleja en {sum(1 for d in DCOB(c) if d > 0.5)}" + (f" (como mucho {es(max(DCOB(c)), 1)} puntos)" if max(DCOB(c)) > 0.5 else '') + f" y queda igual, a medio punto o menos, en {sum(1 for d in DCOB(c) if abs(d) <= 0.5)}." %}
{% VDH = T('validacion_diaria_por_hora') %}
{% DIAS_SEM = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes'] %}
{% FI = lambda c, r, col: v('montecarlo_filtros', col, caso=c, regla=r) %}
{% FIU = lambda c, r: s('montecarlo_filtros', 'umbral', caso=c, regla=r) %}
{% REGLAS = ['Duración de la cola (horas como el aforo)', 'Caudal de descarga', 'Inicio de la cola', 'Fin de la cola', 'La cola se disipa dentro del día', 'Todas salvo la descarga', 'Todas (calibración principal)'] %}
{% SEMS = T('montecarlo_otras_semillas') %}
{% SEM_LIST = sorted(set(x['semilla'] for x in SEMS)) %}
{% SEMV = lambda c, sem, e, col: float([x for x in SEMS if x['caso'] == CASOS[c] and x['semilla'] == sem and x['escenario'] == e][0][col]) %}
{% PRV = T('montecarlo_previas_alternativas') %}
{% PREVIAS = lambda c: sorted(set(x['previa'] for x in PRV if x['caso'] == CASOS[c])) %}
{% PRVV = lambda c, pv, e, col: float([x for x in PRV if x['caso'] == CASOS[c] and x['previa'] == pv and x['escenario'] == e][0][col]) %}
{% COR = T('montecarlo_correlaciones') %}
{% COR_TOP = lambda c, k: sorted([x for x in COR if x['caso'] == CASOS[c]], key=lambda x: -abs(float(x['cambio'])))[:k] %}
{% EST = T('estabilidad_percentiles') %}
{% ee_max = max(float(x['ee_mediana']) for x in EST) %}
{% ee_min = min(float(x['ee_mediana']) for x in EST) %}
{% PP = lambda c, p, col: v('parametros_prior_posterior', col, caso=c, parametro=p) %}
{% n_acep1 = int(PP('m', 'c_carril', 'aceptadas')) %}
{% n_sim1 = int(PP('m', 'c_carril', 'simuladas')) %}
{% n_acep2 = int(PP('t', 'c_carril', 'aceptadas')) %}
{% n_sim2 = int(PP('t', 'c_carril', 'simuladas')) %}
{% SC = lambda c, r, e, col: v('sensibilidad_calibracion_caso1' if c == 'm' else 'sensibilidad_calibracion_caso2', col, regla=r, escenario=e) %}
{% REGLAS_SC = lambda c: [x['regla'] for x in T('sensibilidad_calibracion_caso1' if c == 'm' else 'sensibilidad_calibracion_caso2') if x.get('escenario') == 'tercer_carril_corto' and not x['regla'].startswith('Sin calibrar')] %}
{% PRV_D = [(abs(PRVV(c, pv, e, 'mediana') - SC(c, 'Aforos horarios 2025 (principal)', e, 'mediana')), PRVV(c, pv, e, 'tamano_efectivo') >= 0.1 * (n_acep1 if c == 'm' else n_acep2)) for c in 'mt' for pv in PREVIAS(c) for e in ('tercer_carril_corto', 'paquete_gestion_corto')] %}
{% prv_max_ok = max([d for d, ok in PRV_D if ok] or [0.0]) %}
{% prv_max_all = max(d for d, ok in PRV_D) %}
{% UG = T('uso_de_la_geometria') %}
{% GEO = T('geometria_y_capacidad') %}
{% n_conf = sum(1 for x in GEO if x['estado'] == 'confirmado') %}
{% n_pend = sum(1 for x in GEO if x['estado'].startswith('pendiente')) %}
{% SH1 = lambda pre, e, col: v('sensibilidad_holgura_resultados_caso1', col, variante=starts(pre), escenario=e) %}
{% CM = T('comprobaciones_modelo') %}
{% CMV = lambda i: [x for x in CM if x['id'] == i][0] %}
{% CR = T('cola_remanente_aguas_abajo') %}
{% CRV = lambda L, col: float([x for x in CR if abs(float(x['longitud_km']) - L) < 1e-9][0][col]) %}
{% EAX = lambda c, sup, e, col: v('escenarios_adversos', col, caso=c, supuesto=starts(sup), escenario=e) %}
{% DEM = T('diferencias_emparejadas') %}
{% DEMV = lambda c, h, a, b: [x for x in DEM if x['caso'] == CASOS[c] and x['horizonte'] == h and x['alternativa_a'] == a and x['alternativa_b'] == b][0] %}
{% DREG = T('diferencias_emparejadas_por_regla') %}
{% CPR = T('coste_plazo_riesgo') %}
{% DA = T('dias_atipicos_resumen') %}
{% DAN = lambda et, sen, trat: sum(int(x['dias']) for x in DA if x['etiqueta'] == et and x['sentido'] == sen and x['tratamiento'].startswith(trat)) %}
{% SSA = T('sensibilidad_sin_dias_atipicos') %}
{% SSAV = lambda var, e, col: float([x for x in SSA if x['variante'].startswith(var) and x['estacion_id'] == str(e)][0][col]) %}
{% DEP = T('sensibilidad_depuracion') %}
{% dep_dh = max(abs(float(x['horas_cola_media']) - float([y for y in DEP if y['variante'].startswith('Principal') and y['estacion_id'] == x['estacion_id']][0]['horas_cola_media'])) for x in DEP) %}
{% dep_dd = max(abs(float(x['descarga_mediana']) - float([y for y in DEP if y['variante'].startswith('Principal') and y['estacion_id'] == x['estacion_id']][0]['descarga_mediana'])) for x in DEP) %}
{% ssa_dh = max(abs(float(x['horas_cola_media']) - SSAV('Todos', x['estacion_id'], 'horas_cola_media')) for x in SSA) %}
{% ssa_dd = max(abs(float(x['descarga_mediana']) - SSAV('Todos', x['estacion_id'], 'descarga_mediana')) for x in SSA) %}
{% COB = T('cobertura_e_imputacion_por_estacion_mes_hora') %}
{% n_imp_var = sum(int(float(x['imputables_en_la_variante'] or 0)) for x in COB) %}
{% PROC = T('procedencia_datos') %}
{% n_h = sum(1 for x in PROC if x['id'].startswith('H-')) %}
{% n_o = sum(1 for x in PROC if x['id'].startswith('O-')) %}
{% n_f = sum(1 for x in PROC if x['id'].startswith('F-')) %}
{% n_int = sum(1 for x in PROC if x['integridad'].startswith('Copia íntegra')) %}
{% n_coinc = sum(1 for x in PROC if x['contraste_catalogo'].startswith('Coincide')) %}
{% n_tot = sum(1 for x in PROC if x['id'].startswith('H-') and x['conservacion_totales'].startswith('Totales del extracto')) %}
{% CCAMPOS = T('correspondencia_de_campos') %}
{% CPO = T('contraste_publicacion_original') %}
{% n_cpo = sum(1 for x in CPO if x['resultado'] == 'coincide') %}
{% LAG = csvp('datos/matriz_lagunas.csv') %}
{% LIM = T('limitaciones_por_resultado') %}
{% LIMC = __import__('collections').Counter(x['categoria'] for x in LIM) %}
{% MG = T('graficos_metadatos') %}
{% RET = T('retraso_obra_tercer_carril') %}
{% RETV = lambda a, g, e, col: float([x for x in RET if x['anio'] == str(a) and abs(float(x['crecimiento_anual']) - g) < 1e-9 and x['escenario'] == e][0][col]) %}
{% g_c = float([x for x in csvp('datos/escenarios_demanda.csv') if x['escenario'] == 'Central'][0]['crecimiento_anual']) %}
{% TP = lambda c, t, col: v('transporte_publico_trasvase', col, caso=c, trasvase=lambda x: abs(float(x) - t) < 1e-9) %}
{% SDP_OK = __import__('os').path.exists(PROY + '/salidas/tablas/sensibilidad_prevision_descarga.csv') %}
{% SDPV = (lambda sup, g, a: float([x for x in T('sensibilidad_prevision_descarga') if x['supuesto'].startswith(sup) and abs(float(x['crecimiento_anual']) - g) < 1e-9 and x['anio'] == str(a)][0]['horas_cola_sin_adaptacion'])) if SDP_OK else None %}
{% PRU = csvp('salidas/resultado_pruebas.csv') %}
{% n_bloq = len(PRU) %}
{% n_comp = sum(int(x['nb']) for x in PRU) %}
{% n_fallos = sum(int(x['failed']) for x in PRU) + sum(1 for x in PRU if x['error'] == 'TRUE') %}
{% n_omit = sum(1 for x in PRU if x['skipped'] == 'TRUE') %}
{% minutos = float(re.search(r'Duración: ([0-9.]+) min', leer('salidas/registro_sesion.txt')).group(1)) %}
{% n_avisos = int(re.search(r'main.R: ([0-9]+)', leer('salidas/registro_avisos.txt')).group(1)) %}
{% AVISOS_B = re.search(r'main.R: ([0-9]+)', leer('docs/segunda_ejecucion/registro_avisos.txt')).group(1) %}
{% _chk_avisos = 1 / int(AVISOS_B == '0' and n_avisos == 0) %}
{% n_renv = len(__import__('json').loads(leer('renv.lock'))['Packages']) %}
{% CFG = {x['parametro']: x['valor'] for x in csvp('salidas/configuracion_ejecucion.csv')} %}
{% REPRO = csvp('docs/reproducibilidad_dos_ejecuciones.csv') %}
{% n_rep = sum(1 for x in REPRO if x['dentro_de_tolerancia'] in ('TRUE', 'FALSE')) %}
{% n_rep_ok = sum(1 for x in REPRO if x['dentro_de_tolerancia'] == 'TRUE') %}
{% n_rep_prop = sum(1 for x in REPRO if x['estado'].startswith('propio')) %}
{% n_rep_byte = sum(1 for x in REPRO if x['estado'] == 'igual (byte a byte)') %}
{% tol_rep = REPRO[0]['tolerancia_relativa'] %}
{% SEMT = T('montecarlo_semillas') %}
{% n_ref = len([f for f in __import__('os').listdir(PROY + '/tests/referencia') if f.endswith('.csv') and f != 'configuracion_ejecucion.csv']) %}
{% PLENA = 'Descarga en las horas de cola plena' %}
{% VD26 = [x for x in T('validacion_diaria') if x['periodo'] == P26 and x['nivel'] == 'día'] %}
{% VD26H = {x['caso']: float(x['cobertura_intervalo_predictivo']) for x in T('validacion_diaria') if x['periodo'] == P26 and x['nivel'] == 'hora'} %}
{% VD26_BAJO = [x for x in VD26 if round(100 * float(x['cobertura_intervalo_predictivo'])) < 80] %}
{% CONFIG = {x['parametro']: x['valor'] for x in csvp('salidas/configuracion_ejecucion.csv')} %}
{% N_REJ = int(CONFIG['N_REJILLA']) %}
{% ACEP_REJ = int([x for x in VCX if x['caso'] == CASOS['m'] and x['calibracion'] == 'A+B' and x['prueba'] == '2026' and igual_spec(x, ELEG('m'))][0]['aceptadas']) %}
{% SC_POCAS = lambda c: [x for x in T('sensibilidad_calibracion_caso1' if c == 'm' else 'sensibilidad_calibracion_caso2') if not x.get('escenario')] %}
{% BN = csvp('docs/comprobacion_base_nocturna_2025.csv') %}
{% BN_MOD = sum(int(x['horas_que_cambian']) for x in BN if x['papel_en_el_modelo'] != 'descriptiva') %}
{% PES_ALT = [x for x in ELX if x['caso'] == CASOS['m'] and x['admisible'] == 'TRUE' and x['elegida'] != 'TRUE' and all(x[k] == ELEG('m')[k] for k in ('propagacion', 'horario', 'medida_descarga')) and x['pesados'] != ELEG('m')['pesados']] %}
{% DGP = lambda pos, f: v('diagnostico_descarga', 'mediana', caso='m', bloque='Por posición en la cola', grupo=pos, fuente=f) %}
{% LIMC_TXT = (lambda xs: ', '.join(xs[:-1]) + ' y ' + xs[-1])([f"{n} {dict(simulado='simulados', observado='observados', estimado='estimados', supuesto='supuestos').get(k, 'asociaciones no causales' if k == 'asociación no causal' else k)}" for k, n in LIMC.most_common()]) %}
# Validación y calidad del proyecto TF-5

Este documento reúne los diez criterios de calidad del estudio, cómo se comprueba cada uno y con qué resultado. Las
cifras salen de la ejecución entregada (`salidas/tablas`) y se rellenan con `herramientas/documentos/rellenar.py`,
igual que en el `README.md`. Lo que no se ha podido resolver con datos públicos se dice en cada criterio y está
en `datos/matriz_lagunas.csv`.

## Resumen

| # | Criterio | Resultado | Evidencia principal |
|---|---|---|---|
| 1 | Calibración separada de la validación, con intervalos predictivos | 2025 calibra; una mitad de 2025 valida la otra para elegir la especificación; enero-septiembre de 2026 es la prueba final. Sesgo, MAE, RMSE y cobertura por hora, día y sentido; banda de parámetros e intervalo predictivo del 80 %, con nombres distintos | `validacion_cruzada.csv`, `eleccion_especificacion.csv`, `validacion_diaria.csv`, `validacion_diaria_por_hora.csv`, g20 |
| 2 | Descarga de la mañana | {{'Se adopta la especificación «' + describir(ELEG('m')) + '», que mejora el sesgo de la descarga fuera de muestra sin empeorar más de un 10 % ningún otro indicador; ' + ('en 2026 la cobertura del intervalo predictivo se acerca al 80 % en unos indicadores y se aleja algo en otros; la descarga de las horas de cola plena sigue sobrestimada (apartado 2)' if max(DCOB('m')) > 0.5 else 'en 2026 la cobertura del intervalo predictivo no se aleja del 80 % en ningún indicador') if not es_ref('m') else 'Ninguna variante mejora el sesgo fuera de muestra sin empeorar otros indicadores: se mantiene la referencia'}}; las bandas no se han ensanchado | `eleccion_especificacion.csv`, `diagnostico_descarga.csv`, `validacion_modelo.csv` |
| 3 | Monte Carlo auditado | Previas, dependencias, reglas y tasas por filtro; otras dos semillas; previas alternativas; correlaciones; estabilidad de los percentiles | `montecarlo_parametros.csv`, `montecarlo_filtros.csv`, `montecarlo_otras_semillas.csv`, `montecarlo_previas_alternativas.csv`, `montecarlo_correlaciones.csv` |
| 4 | Geometría y ramales con procedencia | {{len(UG)}} cálculos que dependen del número de carriles, todos con fuente o supuesto explícito; {{n_pend}} estación-sentidos pendientes de confirmación, con escenario alternativo | `uso_de_la_geometria.csv`, `geometria_y_capacidad.csv`, `datos/geometria_tramos.csv` |
| 5 | Restricción aguas abajo | El tercer carril y la regulación no añaden caudal si el tramo siguiente limita; cuellos en serie con almacenamiento finito y bloqueo de ramales; conservación en cada minuto | `comprobaciones_modelo.csv`, `cola_remanente_aguas_abajo.csv`, `escenarios_adversos.csv` |
| 6 | Sin ganador por diferencias mínimas | Diferencias emparejadas con su banda y su error; umbral de 2 puntos fijado de antemano; coste, plazo y riesgos aparte | `diferencias_emparejadas.csv`, `diferencias_emparejadas_por_regla.csv`, `coste_plazo_riesgo.csv`, g21 |
| 7 | Días atípicos y datos faltantes | Cada día con su estado (usado o excluido) y su motivo; marcas de días atípicos; cobertura e imputación por estación, mes y hora; sensibilidad sin atípicos y con dos métodos de imputación | `dias_atipicos.csv`, `dias_atipicos_resumen.csv`, `sensibilidad_sin_dias_atipicos.csv`, `sensibilidad_depuracion.csv`, `cobertura_e_imputacion_por_estacion_mes_hora.csv` |
| 8 | Fuentes originales | Procedencia por recurso (URL, organismo, fechas, licencia, identificador, SHA-256); correspondencia de {{len(CCAMPOS)}} campos; {{n_cpo}} de {{len(CPO)}} recursos contrastados con el catálogo nacional; datos no publicados con su estado | `procedencia_datos.csv`, `correspondencia_de_campos.csv`, `contraste_publicacion_original.csv`, `datos/matriz_lagunas.csv` |
| 9 | Hechos separados de escenarios | Cada resultado con su categoría (observado, estimado, supuesto, simulado o asociación no causal) y cada gráfico con su horizonte, hipótesis e incertidumbre | `datos/limitaciones_por_resultado.csv`, `graficos_metadatos.csv`, `previsiones_condicionadas.csv` |
| 10 | Reproducibilidad | Versiones fijadas, semillas, zona horaria, ejecución completa sin intervención, {{n_avisos}} avisos registrados, pruebas y dos ejecuciones completas iguales dentro de la tolerancia | `renv.lock`, `salidas/registro_*.txt`, `salidas/resultado_pruebas.csv`, `docs/reproducibilidad_dos_ejecuciones.csv` |

## Nota de control: la tabla de validación resumida

`validacion_modelo.csv` tiene **{{len(VAL)}} filas de indicadores, {{len(VAL) // 2}} por sentido**: horas de cola, inicio y fin de
la cola, y dos filas de la descarga con cola. Esas dos miden **el mismo fenómeno** de dos formas (columna
`fenomeno`): el parámetro de descarga del modelo y el caudal que sale del modelo medido igual que en el aforo
(mediana de las medianas de cada día). No son dos contrastes independientes, así que se cuentan como un solo
fenómeno. En 2026 {{FUERA_TXT}}.
La banda de parámetros describe un día típico, no la variabilidad entre días: para juzgar días concretos está el
intervalo predictivo (criterio 1).

## 1. Calibración separada de la validación

**Criterio.** Días o periodos no usados para calibrar; MAE, RMSE, sesgo y cobertura por hora, día y sentido;
intervalos predictivos que incluyan la variabilidad diaria y el error de observación, bien rotulados.

**Cómo se hace** (`R/12_validacion_predictiva.R`):
- **Tres conjuntos.** Los días laborables válidos de 2025 se reparten en dos mitades por semanas ISO alternas (A,
  impares; B, pares). Para elegir la especificación de la descarga, se calibra con una mitad y se mide el error en
  la otra, y al revés: validación cruzada. Cada calibración usa solo sus días para todo lo que se ajusta: el
  objetivo de calibración, el perfil horario de la demanda, la cuota de pesados, el factor horario de la descarga y
  la capacidad libre del tramo siguiente. Enero-septiembre de 2026 (sin agosto) no interviene en la calibración ni en
  la elección: es la prueba final. La línea base de velocidad de madrugada, con la que se decide si una hora está
  congestionada, se calcula con los 24 meses; calculada solo con 2025, {{'no cambia ninguna hora congestionada de 2025 en las estaciones que usa el modelo' if BN_MOD == 0 else 'cambian ' + es(BN_MOD) + ' horas congestionadas de 2025 en las estaciones que usa el modelo'}}
  (`docs/comprobacion_base_nocturna_2025.csv`).
- **Dos bandas con nombres distintos.** La *banda de parámetros p10-p90* es la dispersión de las combinaciones
  calibradas para un día típico: no es un intervalo predictivo ni una probabilidad. El *intervalo predictivo del
  80 %* le suma la variabilidad de un día a otro y el error de observación, con los residuos de los días de
  calibración (valor del día menos la mediana de esos días). Su cobertura se mide en días no usados.
- **Métricas** por indicador diario (horas de cola, inicio, fin y descarga), por hora de la punta, por día de la
  semana, por trimestre y por sentido (cada caso es un sentido): sesgo (mediana del modelo − media aforada), error absoluto medio
  (MAE), raíz del error cuadrático medio (RMSE) y cobertura de las dos bandas.

**Resultado: prueba final en 2026** (`validacion_diaria.csv`; especificación elegida, calibrada con todo 2025 en el Monte Carlo
principal: {{es(n_sim1)}} combinaciones, {{es(n_acep1)}} aceptadas):

| Indicador | Sentido | Sesgo | MAE | RMSE | Dentro de la banda de parámetros | Dentro del intervalo predictivo del 80 % |
|---|---|---|---|---|---|---|
{{'\n'.join(f"| {ind} | {'Mañana, hacia Santa Cruz' if c == 'm' else 'Tarde, hacia el Norte'} | {sg(VD(c, ind, P26, 'sesgo'), d)} {u} | {es(VD(c, ind, P26, 'mae'), d)} | {es(VD(c, ind, P26, 'rmse'), d)} | {pct(VD(c, ind, P26, 'cobertura_p10_p90'))} | {pct(VD(c, ind, P26, 'cobertura_intervalo_predictivo'))} |" for c in 'mt' for ind, d, u in (('Horas de cola al día', 2, 'h'), ('Inicio de la cola', 2, 'h'), ('Fin de la cola', 2, 'h'), (DIA_IGUAL, 0, 'veh/h'), (PLENA, 0, 'veh/h')))}}

La cobertura de la banda de parámetros es baja porque no está hecha para días concretos. La del intervalo
predictivo es la que debe acercarse al 80 %: en los indicadores diarios de `validacion_diaria.csv` va del
{{pct(min(float(x['cobertura_intervalo_predictivo']) for x in VD26))}} al {{pct(max(float(x['cobertura_intervalo_predictivo']) for x in VD26))}}{{('; por debajo del 80 % quedan ' + '; '.join(x['indicador'][0].lower() + x['indicador'][1:] + ' (' + NOMC[x['caso']] + ', ' + pct(float(x['cobertura_intervalo_predictivo'])) + ')' for x in VD26_BAJO)) if VD26_BAJO else ''}}. Hora a hora, cubre el
{{pct(VD26H[CASOS['m']])}} de las horas por la mañana y el {{pct(VD26H[CASOS['t']])}} por la tarde. Por debajo del 80 %, el intervalo es demasiado
estrecho para ese indicador; por encima, conservador (sobre todo en el inicio y el fin, que el aforo mide en horas
enteras). En conjunto puede pecar de ancho, porque la dispersión de las combinaciones y los residuos de los días
recogen en parte la misma variabilidad.

**Por hora** (`validacion_diaria_por_hora.csv`; 2026, caudal de cada hora de la punta):

| Hora | Sentido | Sesgo (veh/h) | RMSE (veh/h) | Dentro del intervalo predictivo |
|---|---|---|---|---|
{{'\n'.join(f"| {int(x['hora']):02d} h | {'Mañana' if x['caso'].startswith('manana') else 'Tarde'} | {sg(float(x['sesgo']))} | {es(float(x['rmse']))} | {pct(float(x['cobertura_intervalo_predictivo']))} |" for x in VDH if x['anio'] == '2026')}}

**Por día de la semana** (2026, horas de cola al día; sesgo y cobertura del intervalo predictivo):
mañana, {{'; '.join(f"{d} {sg(VD('m', 'Horas de cola al día', '2026, ' + d, 'sesgo'), 2)} h y {pct(VD('m', 'Horas de cola al día', '2026, ' + d, 'cobertura_intervalo_predictivo'))}" for d in DIAS_SEM)}};
tarde, {{'; '.join(f"{d} {sg(VD('t', 'Horas de cola al día', '2026, ' + d, 'sesgo'), 2)} h y {pct(VD('t', 'Horas de cola al día', '2026, ' + d, 'cobertura_intervalo_predictivo'))}" for d in DIAS_SEM)}}.
Por trimestre, en `validacion_diaria.csv` (periodos 2025-T1 a 2026-T3).

**Límites.** La validación compara lo que miden los aforos (colas por horas enteras y caudales horarios en un
punto). No hay tiempos de recorrido ni longitudes de cola medidas, así que la demora simulada no se valida
directamente (matriz de lagunas, D02 y D13).

## 2. Descarga de la mañana

**Criterio.** Comprobar que el detector y el modelo miden lo mismo; probar una descarga que dependa de la hora,
los incidentes, la mezcla de vehículos y la propagación de la cola; no ensanchar las bandas; aceptar el cambio solo
si mejoran el sesgo y la cobertura fuera de muestra sin empeorar otros periodos.

**Cómo se hace.**
- **Misma medida.** La descarga del aforo es la mediana del caudal de las horas que el aforo cuenta con cola (al
  menos el 60 % de los vehículos a menos de 80 km/h), en Ermita Cruz Chica. El modelo se mide igual: caudal que sale
  en las horas en que al menos el 60 % de los vehículos ha pasado por la cola, y mediana de esas horas en su día. El
  parámetro del modelo (carriles × capacidad × (1 − caída)) es otra cosa: la descarga a pleno rendimiento en la hora
  de referencia.
- **Variantes probadas** (`rejilla_especificaciones()`; 2 × 2 × 2 × 2 = 16): con o sin propagación de la cola del
  tramo siguiente (cuando no tiene capacidad libre, frena también la descarga actual); descarga constante o
  dependiente de la hora (factor medido en 2025 en las horas con cola plena o final, solo en las horas con datos
  suficientes); con o sin mezcla de pesados (capacidad en vehículos según la cuota de pesados de cada hora, con una
  equivalencia de 1,5 a 4 ligeros por pesado); y la descarga calibrada como parámetro o medida igual que en el aforo.
  Los incidentes no tienen un registro incorporado (criterio 7): se tratan como días atípicos y en el escenario
  adverso de incidente.
- **Regla fijada antes de mirar 2026.** La referencia es la variante más simple. Otra es admisible si reduce al
  menos un 20 % el sesgo absoluto de la descarga del día en la validación cruzada (media de los sesgos absolutos de
  las dos mitades, para que un sesgo positivo en una y negativo en la otra no se compensen) y no empeora más de un
  10 % el RMSE de ningún indicador. Entre las admisibles se elige la de menor RMSE relativo medio. La cobertura no
  entra en la regla: se informa aparte, más abajo, para ver si también mejora.

**Resultado** (`eleccion_especificacion.csv`, `validacion_cruzada.csv`).
- **Mañana:** {{n_adm('m')}} de las {{n_var('m')}} variantes distintas de la referencia {{'es admisible' if n_adm('m') == 1 else 'son admisibles'}}. {{('Se elige: **' + describir(ELEG('m')) + '**. Sesgo absoluto de la descarga del día en la validación cruzada: ' + es(float(ELEG('m')['sesgo_descarga'])) + ' veh/h, frente a ' + es(float(ELEG('m')['sesgo_descarga_referencia'])) + ' con la referencia (' + pct(float(ELEG('m')['mejora_sesgo_descarga'])) + ' menos); el indicador que más empeora, ' + ELEG('m')['indicador_que_mas_empeora'].lower() + ', lo hace un ' + pct(float(ELEG('m')['peor_rmse_relativo']) - 1, 1) + ' en RMSE.') if not es_ref('m') else 'Se mantiene la referencia.'}}
- **Tarde:** {{n_adm('t')}} de las {{n_var('t')}} variantes distintas de la referencia {{'es admisible' if n_adm('t') == 1 else 'son admisibles'}}. {{('Se elige: **' + describir(ELEG('t')) + '**.') if not es_ref('t') else 'Se mantiene la referencia (' + describir(ELEG('t')) + '): ninguna variante reduce el sesgo de la descarga un 20 % sin empeorar otro indicador más de un 10 %.'}}

**Prueba final en 2026** (calibrando con todo 2025; ni 2026 ni la prueba intervinieron en la elección). Las cifras salen
de la rejilla de especificaciones ({{es(N_REJ)}} combinaciones por forma; {{es(ACEP_REJ)}} aceptadas con la elegida), no del Monte Carlo
principal del criterio 1, así que difieren un poco de las de su tabla:

| Indicador (mañana) | Referencia: sesgo; RMSE; intervalo predictivo | Elegida: sesgo; RMSE; intervalo predictivo |
|---|---|---|
{{'\n'.join(f"| {ind} | {sg(P26X('m', REF('m'), ind, 'sesgo'), 0 if 'aforo' in ind or ind.startswith('Caudal') else 2)}; {es(P26X('m', REF('m'), ind, 'rmse'), 0 if 'aforo' in ind or ind.startswith('Caudal') else 2)}; {pct(P26X('m', REF('m'), ind, 'cobertura_intervalo_predictivo'))} | {sg(P26X('m', ELEG('m'), ind, 'sesgo'), 0 if 'aforo' in ind or ind.startswith('Caudal') else 2)}; {es(P26X('m', ELEG('m'), ind, 'rmse'), 0 if 'aforo' in ind or ind.startswith('Caudal') else 2)}; {pct(P26X('m', ELEG('m'), ind, 'cobertura_intervalo_predictivo'))} |" for ind in ['Horas de cola al día', 'Inicio de la cola', 'Fin de la cola', IND_DIA] + HORAS_IND('m'))}}

**¿Mejora también la cobertura?** {{COB_FRASE('m') + ' ' + COB_RES('m') if not es_ref('m') else 'Se mantiene la referencia, así que la cobertura es la suya.'}}

En la tabla resumida (`validacion_modelo.csv`), la descarga de la mañana medida igual que el aforo da en 2026
{{ESD(VM('m', IGUAL, 'observado_2026'))}} veh/h en el aforo y {{es(VM('m', IGUAL, 'simulado_mediana'))}} en el modelo ({{sg(VM('m', IGUAL, 'error_mediana_2026'))}} veh/h,
{{spct(VM('m', IGUAL, 'error_relativo_2026'), 1)}}; banda de parámetros {{es(VM('m', IGUAL, 'simulado_p10'))}}-{{es(VM('m', IGUAL, 'simulado_p90'))}}, {{'dentro' if s('validacion_modelo', 'dentro_2026', caso='m', indicador=IGUAL) == 'TRUE' else 'fuera'}}). El parámetro de
descarga ({{es(VM('m', DESC, 'simulado_mediana'))}} veh/h de mediana) no se mide igual que el aforo{{' con la especificación elegida: es la descarga de la hora de referencia, antes del factor horario y de los pesados' if ELEG('m')['horario'] == 'TRUE' or ELEG('m')['pesados'] == 'TRUE' else ''}}; por eso su
diferencia con la mediana de todas las horas con cola ({{sg(VM('m', DESC, 'error_mediana_2026'))}} veh/h) no es un error de predicción.

**La forma de la descarga dentro de la cola.** La especificación elegida cuadra la mediana del día, que es lo que se
calibra, pero no su forma: con la cola plena el modelo da {{es(DGP('plena', 'modelo (calibrado)'))}} veh/h frente a {{es(DGP('plena', 'aforo 2025'))}} en el aforo de
2025, y al final de la cola, {{es(DGP('final', 'modelo (calibrado)'))}} frente a {{es(DGP('final', 'aforo 2025'))}} (`diagnostico_descarga.csv`). En las horas de cola plena el sesgo es de
{{sg(VD('m', PLENA, P25, 'sesgo'))}} veh/h en 2025 y de {{sg(VD('m', PLENA, P26, 'sesgo'))}} en 2026 (`validacion_diaria.csv`).{{''.join(' La regla de calibración «' + x['regla'][0].lower() + x['regla'][1:] + '» solo la ' + ('cumple ' if int(x['validas_total']) == 1 else 'cumplen ') + es(int(x['validas_total'])) + ' de ' + es(n_sim1) + ' combinaciones: el modelo no reproduce a la vez la duración y el horario de la cola y ese caudal.' for x in SC_POCAS('m') if 'cola plena' in x['regla'])}}

**Empate en la mezcla de pesados.** {{(('La misma forma sin la mezcla de pesados' if ELEG('m')['pesados'] == 'TRUE' else 'La misma forma con la mezcla de pesados') + ' tiene casi el mismo RMSE relativo medio (' + es(float(PES_ALT[0]['rmse_relativo_medio']), 4) + ' frente a ' + es(float(ELEG('m')['rmse_relativo_medio']), 4) + ') y un sesgo absoluto de la descarga ' + ('menor' if float(PES_ALT[0]['sesgo_descarga']) < float(ELEG('m')['sesgo_descarga']) else 'mayor') + ' (' + es(float(PES_ALT[0]['sesgo_descarga'])) + ' frente a ' + es(float(ELEG('m')['sesgo_descarga'])) + ' veh/h). La regla, fijada de antemano, elige la de menor RMSE: la mezcla de pesados entra por un empate, no porque los datos la exijan.') if PES_ALT and abs(float(PES_ALT[0]['rmse_relativo_medio']) - float(ELEG('m')['rmse_relativo_medio'])) < 0.005 else 'No hay empates entre las formas admisibles.'}}

**Otros periodos.** La regla de la elección y la tabla de 2026 comparan la referencia y la elegida hora a hora en la
punta; por trimestre y por día de la semana solo se publica la elegida (`validacion_diaria.csv`).

**Límites.** El factor horario solo se estima en las horas con datos suficientes de 2025; fuera de ellas se
supone la descarga de referencia, y la sensibilidad de las previsiones a ese supuesto se publica (criterio 9).

## 3. Monte Carlo auditado

**Criterio.** Documentar previas, correlaciones, reglas de aceptación y tasas por filtro; repetir con otras
semillas y otras previas justificadas; comparar con calibraciones alternativas y medir la estabilidad de los
percentiles.

**Resultado.**
- **Tasas por filtro** (`montecarlo_filtros.csv`; sobre {{es(n_sim1)}} simulaciones por la mañana y {{es(n_sim2)}} por la tarde):

  | Regla | Mañana: umbral | Pasan | Tarde: umbral | Pasan |
  |---|---|---|---|---|
{{'\n'.join(f"  | {r} | {FIU('m', r) or '—'} | {es(FI('m', r, 'pasan'))} ({pct(FI('m', r, 'tasa'), 1)}) | {FIU('t', r) or '—'} | {es(FI('t', r, 'pasan'))} ({pct(FI('t', r, 'tasa'), 1)}) |" for r in REGLAS)}}

  Que se acepte una parte pequeña no es un error: la regla exige a la vez la duración, el inicio, el fin y la
  descarga medidos en 2025. Los resultados describen esa población de combinaciones, no cualquier combinación
  verosímil.
- **Previas y dependencias** (`montecarlo_parametros.csv`): triangulares con su fuente; la elasticidad a 10 años
  nunca es menor que la del primer año; la capacidad libre del tramo siguiente se muestrea con un cuantil común a
  todas las horas{{'; la equivalencia de los pesados se muestrea con su propia semilla, sin cambiar el resto de la muestra' if any(x['parametro'] == 'equivalencia_pesados' for x in T('montecarlo_parametros')) else ''}}.
- **Otras semillas** (`montecarlo_otras_semillas.csv`; misma previa y misma regla, otras combinaciones):

  | Semilla | Mañana: aceptadas; tercer carril, 1er año; regulación + escalonamiento | Tarde: aceptadas; tercer carril hipotético; regulación + escalonamiento |
  |---|---|---|
{{'\n'.join(f"  | {sem} | {es(SEMV('m', sem, 'tercer_carril_corto', 'aceptadas'))}; {pct(SEMV('m', sem, 'tercer_carril_corto', 'mediana'), 1)}; {pct(SEMV('m', sem, 'paquete_gestion_corto', 'mediana'), 1)} | {es(SEMV('t', sem, 'tercer_carril_corto', 'aceptadas'))}; {pct(SEMV('t', sem, 'tercer_carril_corto', 'mediana'), 1)}; {pct(SEMV('t', sem, 'paquete_gestion_corto', 'mediana'), 1)} |" for sem in SEM_LIST)}}

  Las medianas cambian como mucho {{es(100 * max(max(SEMV(c, a, e, 'mediana') for a in SEM_LIST) - min(SEMV(c, a, e, 'mediana') for a in SEM_LIST) for c in 'mt' for e in ('tercer_carril_corto', 'paquete_gestion_corto')), 1)}} puntos entre semillas; el error de muestreo de una mediana va de
  {{es(100 * ee_min, 1)}} a {{es(100 * ee_max, 1)}} puntos (`estabilidad_percentiles.csv`).
- **Previas alternativas** (`montecarlo_previas_alternativas.csv`; reponderación de las combinaciones aceptadas, con
  su tamaño efectivo):

  | Previa | Mañana: tamaño efectivo; tercer carril; regulación + escalonamiento | Tarde: ídem |
  |---|---|---|
{{'\n'.join(f"  | {pv} | {es(PRVV('m', pv, 'tercer_carril_corto', 'tamano_efectivo'))} de {es(n_acep1)}; {pct(PRVV('m', pv, 'tercer_carril_corto', 'mediana'), 1)}; {pct(PRVV('m', pv, 'paquete_gestion_corto', 'mediana'), 1)} | " + (f"{es(PRVV('t', pv, 'tercer_carril_corto', 'tamano_efectivo'))} de {es(n_acep2)}; {pct(PRVV('t', pv, 'tercer_carril_corto', 'mediana'), 1)}; {pct(PRVV('t', pv, 'paquete_gestion_corto', 'mediana'), 1)}" if pv in PREVIAS('t') else 'no aplica') + " |" for pv in PREVIAS('m'))}}

  Un tamaño efectivo pequeño indica que la previa alternativa se aleja de la usada y que su resultado es poco
  preciso. Con las previas cuyo tamaño efectivo es al menos el 10 % de las aceptadas, las medianas del tercer carril
  y de la regulación + escalonamiento cambian como mucho {{es(100 * prv_max_ok, 1)}} puntos frente a la previa usada{{(', y hasta ' + es(100 * prv_max_all, 1) + ' con las demás') if prv_max_all > prv_max_ok + 0.0005 else ''}}.
- **Correlaciones que crea la calibración** (`montecarlo_correlaciones.csv`; Spearman, previa frente a aceptadas):
  por la mañana, {{'; '.join(f"{x['parametro_1']}-{x['parametro_2']} {sg(float(x['rho_aceptadas']), 2)}" for x in COR_TOP('m', 3))}}; por la tarde,
  {{'; '.join(f"{x['parametro_1']}-{x['parametro_2']} {sg(float(x['rho_aceptadas']), 2)}" for x in COR_TOP('t', 3))}}. En la previa son casi nulas: la calibración
  empareja parámetros que se compensan (por ejemplo, más capacidad con más caída).
- **Calibraciones alternativas** (`sensibilidad_calibracion_caso1.csv` y `_caso2.csv`; {{len(REGLAS_SC('m'))}} reglas con al menos 20 combinaciones, más una muestra sin calibrar{{''.join('; «' + x['regla'][0].lower() + x['regla'][1:] + '» solo la ' + ('cumple ' if int(x['validas_total']) == 1 else 'cumplen ') + es(int(x['validas_total'])) + ' de ' + es(n_sim1) + ' combinaciones y no tiene resultados' for x in SC_POCAS('m'))}}). Las reglas
  distintas de la principal se resumen con una submuestra uniforme de las simulaciones, para que las combinaciones
  de la regla principal no queden sobrerrepresentadas. Tercer carril de la mañana, primer año: del
  {{pct(min(SC('m', r, 'tercer_carril_corto', 'mediana') for r in REGLAS_SC('m')))}} al {{pct(max(SC('m', r, 'tercer_carril_corto', 'mediana') for r in REGLAS_SC('m')))}} según la regla (calibración principal: {{pct(SC('m', 'Aforos horarios 2025 (principal)', 'tercer_carril_corto', 'mediana'))}}).

## 4. Geometría y ramales

**Criterio.** Catalogar para cada tramo el sentido, la fecha, los carriles continuos y auxiliares, las entradas y
salidas, la fuente y la vigencia; ninguna capacidad ni balance sin procedencia o supuesto explícito.

**Resultado.**
- `datos/geometria_tramos.csv` y `geometria_y_capacidad.csv`: para cada estación-sentido, el tramo, la sección del
  inventario, los carriles aforados (catálogo de julio de 2026), los del inventario del PTEOSVAM (2006), los del
  modelo, su papel, su estado, una explicación posible y el escenario alternativo. Coinciden en {{n_conf}} de 14; los
  otros {{n_pend}} quedan pendientes de confirmación.
- `uso_de_la_geometria.csv`: los {{len(UG)}} cálculos que dependen del número de carriles, con los carriles que usan, su
  estado, su fuente y el supuesto que los sustituye cuando no están confirmados. {{'Todos tienen fuente o supuesto explícito.' if all(x['tiene_procedencia_o_supuesto'] == 'TRUE' for x in UG) else 'ALGUNO NO TIENE FUENTE NI SUPUESTO.'}}
- **Ramales.** No hay aforos de ramales publicados. La capacidad libre del tramo siguiente no los necesita (las
  entradas netas se cancelan), pero tampoco los ve; el balance entre estaciones es descriptivo y no entra en el
  modelo. Se publican variantes con entradas un 10 % mayores y con salidas desconocidas del 5 %.
- **Escenarios geométricos ejecutados:** el k crítico con los carriles del inventario, la capacidad libre con los
  carriles del inventario en Campus Guajara y Bomberos La Laguna (tercer carril de la mañana:
  {{pct(SH1('Carriles del inventario', 'tercer_carril_corto', 'mediana'))}} el primer año, con una cola de hoy en el rango medido en el {{pct(SH1('Carriles del inventario', 'tercer_carril_corto', 'parte_cola_hoy_en_rango_medido'))}} de las
  combinaciones) y el tramo siguiente sin capacidad libre.

**Límites.** Los ficheros usados no dan el punto kilométrico de las estaciones ni el comienzo y el fin de cada
carril; la petición está preparada, sin enviar (`docs/solicitud_datos_cabildo.md`, punto 6; D05 y D16).

## 5. Restricción aguas abajo

**Criterio.** Que un tercer carril no aumente el caudal si el siguiente cuello lo limita; cola remanente,
longitud de almacenamiento y bloqueo de incorporaciones; conservación en cada intervalo; que la demanda no
desaparezca al desplazar horarios; efecto físico esperado cuando abajo no hay capacidad.

**Resultado.**
- **El tercer carril y la regulación no añaden caudal si el tramo siguiente limita** (comprobaciones M06 y M07 de
  `comprobaciones_modelo.csv`): con capacidad libre nula o negativa (−5 %), la descarga con cola es la misma con y
  sin ellos ({{'se cumple en las dos' if CMV('M06')['cumple'] == 'TRUE' and CMV('M07')['cumple'] == 'TRUE' else 'NO SE CUMPLE'}}). En el escenario adverso de tramo siguiente lleno, el tercer carril reduce la demora un
  {{pct(EAX('m', 'Tramo siguiente sin holgura', 'tercer_carril_corto', 'reduccion_mediana'))}} por la mañana (p90: {{pct(EAX('m', 'Tramo siguiente sin holgura', 'tercer_carril_corto', 'reduccion_p90'))}}).
- **Propagación de la cola.** Cuando la especificación la incluye, la capacidad libre negativa frena también la
  descarga actual: la cola de abajo remonta al cuello. La curva g15 (tercer carril con una capacidad libre fija en todas las
  horas) no aplica esa propagación: orienta sobre cuánto pesa la holgura y no sustituye al resultado principal.
- **Cuellos en serie** (`cola_remanente_aguas_abajo.csv`; `simular_tandem()`). El cuello de la mañana y el tramo
  siguiente se simulan en serie, con un almacenamiento finito entre los dos (longitud × 3 carriles × 140 veh/km) y
  las entradas de los ramales, que se bloquean en proporción cuando el almacenamiento se llena. Tercer carril, primer
  año (mediana de {{es(CRV(0, 'simulaciones'))}} combinaciones calibradas; con esas mismas, el modelo principal da {{pct(CRV(0, 'reduccion_modelo_principal'))}}):

  | Almacenamiento | Reducción de la demora | Cola remanente máxima | Minutos con rebose | Demora en los ramales (veh·h; hoy) |
  |---|---|---|---|---|
{{'\n'.join(f"  | {es(float(x['longitud_km']))} km ({es(float(x['almacenamiento_veh']))} veh) | {pct(float(x['reduccion_mediana']))} ({pr(float(x['reduccion_p10']), float(x['reduccion_p90']))}) | {es(float(x['cola_remanente_max_mediana']))} veh | {es(float(x['minutos_rebose_mediana']))} | {es(float(x['demora_ramales_tercer_carril_vh']), 1)} ({es(float(x['demora_ramales_actual_vh']), 1)}) |" for x in CR)}}

  Con almacenamiento, la cola que el tercer carril quita en Los Rodeos queda en parte entre los dos cuellos y retiene
  también a los vehículos que entran por los ramales: por eso la reducción en serie es distinta de la del modelo
  principal. Las longitudes son supuestas (no hay puntos kilométricos publicados).
- **Conservación** (`comprobaciones_modelo.csv`; se cumplen {{sum(1 for x in CM if x['cumple'] == 'TRUE')}} de {{len(CM)}} comprobaciones): en cada minuto,
  llegadas = salidas + colas, también en los dos cuellos en serie; con el perfil de cada combinación calibrada, la
  demanda simulada suma los vehículos del día; al desplazar la punta no se pierde ningún vehículo, tampoco cerca del
  borde del día; la cola y las salidas nunca son negativas y las salidas no superan la capacidad. Las pruebas
  automáticas repiten estas comprobaciones con casos extremos.

## 6. Sin ganador por diferencias mínimas

**Criterio.** Diferencias absolutas y relativas, incertidumbre de la diferencia con escenarios emparejados,
sensibilidad y condiciones de aplicabilidad; coste, plazo y riesgos por separado; ninguna recomendación basada solo
en una diferencia menor que la incertidumbre.

**Cómo se hace** (`diferencias_emparejadas()`). Cada combinación calibrada se usa para todas las alternativas, así
que la diferencia se mide combinación a combinación. Para cada pareja se dan la diferencia mediana, su banda p10-p90,
su error de muestreo (bootstrap), la diferencia relativa y la parte de las combinaciones en que gana cada una. Una
diferencia de menos de **2 puntos** (umbral fijado de antemano) no es material.

**Resultado: tercer carril frente a regulación + escalonamiento, primer año** (en puntos de reducción de la demora):

| Sentido | Diferencia mediana (p10 a p90) | Error de muestreo | Combinaciones en que el tercer carril reduce más | Lectura |
|---|---|---|---|---|
{{'\n'.join(f"| {'Mañana' if c == 'm' else 'Tarde (tercer carril hipotético)'} | {sg(100 * float(DEMV(c, 'corto', 'tercer_carril', 'paquete_gestion')['dif_mediana']), 1)} ({sg(100 * float(DEMV(c, 'corto', 'tercer_carril', 'paquete_gestion')['dif_p10']), 1)} a {sg(100 * float(DEMV(c, 'corto', 'tercer_carril', 'paquete_gestion')['dif_p90']), 1)}) | {es(100 * float(DEMV(c, 'corto', 'tercer_carril', 'paquete_gestion')['ee_dif_mediana']), 1)} | {pct(float(DEMV(c, 'corto', 'tercer_carril', 'paquete_gestion')['parte_a_mayor']))} | {DEMV(c, 'corto', 'tercer_carril', 'paquete_gestion')['lectura']} |" for c in 'mt')}}

Con cada regla de calibración (`diferencias_emparejadas_por_regla.csv`), la diferencia mediana de la mañana va de
{{sg(100 * min(float(x['dif_mediana']) for x in DREG if x['caso'] == CASOS['m'] and x['horizonte'] == 'corto'), 1)}} a {{sg(100 * max(float(x['dif_mediana']) for x in DREG if x['caso'] == CASOS['m'] and x['horizonte'] == 'corto'), 1)}} puntos. Todas las parejas, en los tres horizontes, están en
`diferencias_emparejadas.csv` y en g21. «Sin diferencia material» describe la diferencia típica (la mediana, o la mitad
de las combinaciones dentro de 2 puntos): si la banda es ancha, cuál reduce más puede cambiar según los parámetros,
y por eso cada lectura va con su banda.

**Coste, plazo y riesgos, aparte del efecto** (`coste_plazo_riesgo.csv`; dato documental y valoración cualitativa):

| Alternativa | Coste | Plazo | Riesgos principales |
|---|---|---|---|
{{'\n'.join(f"| {x['nombre']} | {x['coste']} | {x['plazo']} | {x['riesgos_principales']} |" for x in CPR)}}

**Condición de aplicabilidad.** Las reducciones son escenarios del modelo con la red y la demanda de 2025: dependen de
la capacidad libre del tramo siguiente (estimada), de la caída de capacidad (no medible con aforos horarios) y de
elasticidades y eficacias de la literatura. El estudio no recomienda una alternativa por su mediana cuando la
diferencia no es material.

## 7. Días atípicos y datos faltantes

**Criterio.** Identificar festivos, incidentes, obras, lluvia, averías de sensores y cambios de hora; marcar
observación, imputación y exclusión con motivos; repetir las estimaciones sin días atípicos y con métodos
alternativos de imputación; publicar la cobertura por estación y hora y la proporción imputada.

**Resultado.**
- **Cada día con su estado y su motivo** (`dias_atipicos.csv`, una fila por estación, sentido y día laborable). En
  los dos cuellos: Ermita Cruz Chica hacia Santa Cruz, {{DAN('Ermita Cruz Chica', 'descendente', 'excluido')}} días excluidos y {{DAN('Ermita Cruz Chica', 'descendente', 'usado')}} marcas
  en días usados; Bomberos La Laguna hacia el Norte, {{DAN('Bomberos La Laguna', 'ascendente', 'excluido')}} y {{DAN('Bomberos La Laguna', 'ascendente', 'usado')}} (`dias_atipicos_resumen.csv`, con el
  motivo de cada uno: agosto, día incompleto por avería o corte del aforador, tráfico por debajo del 85 % de la
  mediana del mes, puente, Navidad, Semana Santa y punta anómala). Los festivos autonómicos e insulares no son
  laborables. Los cambios de hora caen en domingo, así que no afectan a los días laborables; en las horas, la serie
  con banderas marca las horas que faltan o se repiten.
- **Punta anómala:** caudal de la punta más de tres desviaciones absolutas medianas por debajo de la mediana del
  mes. Es la señal de un posible incidente u obra que se puede ver en los aforos.
- **Sin días atípicos** (`sensibilidad_sin_dias_atipicos.csv`): quitando los puentes, la Navidad, la Semana Santa y
  las puntas anómalas, la media de horas de cola de los dos cuellos cambia como mucho {{es(ssa_dh, 2)}} h y la descarga
  mediana {{es(ssa_dd, 1)}} veh/h.
- **Imputación** (`sensibilidad_depuracion.csv`, `cobertura_e_imputacion_por_estacion_mes_hora.csv`). El análisis no
  imputa (tasa del 0 %): excluye. Dos métodos alternativos para las horas a las que les falta un carril (A,
  proporcional; B, mediana de la misma hora, mes y estación-sentido) afectarían a {{es(n_imp_var)}} horas del corredor y a
  ninguna de los dos cuellos, así que no cambian sus resultados. Con todas las variantes de depuración, la media de
  horas de cola de los cuellos cambia como mucho {{es(dep_dh, 2)}} h y la descarga mediana {{es(dep_dd, 1)}} veh/h. La cobertura
  por estación, mes y hora está en la misma tabla.

**Límites.** Incidentes, obras y lluvia no están vinculados a los días. El Cabildo publica un registro de
incidencias en carreteras (2010-2026, con carretera, tramo, fecha y hora de inicio y tipo) que no se ha incorporado
porque su descarga no se pudo completar en el entorno del análisis; queda como fuente identificada (D09). La lluvia
exige una clave de AEMET OpenData (D15).

## 8. Fuentes originales

**Criterio.** URL oficial, organismo, fecha de descarga, versión, licencia, identificador de estación, huella y
correspondencia de campos; comprobar una muestra contra la publicación original; para los datos no publicados,
solicitud y estado.

**Resultado.**
- `procedencia_datos.csv`: una fila por recurso ({{n_h}} horarios, {{n_o}} oficiales y {{n_f}} publicados sin usar), con
  organismo, conjunto, recurso, URL, identificador, licencia leída del catálogo, fecha de modificación en origen (la
  versión del recurso), fecha de descarga, bytes y SHA-256 del original y de la copia, cobertura, filtros y unidades.
  {{n_int}} copias íntegras; {{n_coinc}} coinciden en tamaño y fecha con la instantánea del catálogo; en {{n_tot}} de 24 extractos
  los totales coinciden con las sumas de control del TXT original. Los identificadores de estación están en
  `R/00_utilidades.R` (`ESTACIONES_TF5`) y en cada extracto.
- `correspondencia_de_campos.csv`: los {{len(CCAMPOS)}} campos de los tres ficheros oficiales, cada uno con su definición del
  diccionario oficial y su nombre en el proyecto (o «no se usa»).
- **Contraste con la publicación original, fuera del proyecto** (`contraste_publicacion_original.csv`; de metadatos, sin
  volver a descargar: el contraste con descarga directa de los 37 recursos está en `docs/contraste_fuentes/`). El
  16-10-2026 se contrastó una muestra con el catálogo nacional de datos abiertos (datos.gob.es), que federa el portal
  del Cabildo: los 12 TXT horarios de 2025 y su diccionario. Coinciden {{n_cpo}} de {{len(CPO)}} en URL, identificador, nombre
  y licencia; la fecha de modificación del conjunto difiere {{es(abs(float(CPO[0]['diferencia_modificacion_h'])), 0)}} h entre los dos catálogos
  (probablemente por la zona horaria).
- **Datos no publicados o no incorporados**, con su estado (`datos/matriz_lagunas.csv`, columna
  `estado_solicitud`):
{{'\n'.join('  - ' + x['id'] + ', ' + x['dato'][0].lower() + x['dato'][1:] + ': ' + (x['estado_solicitud'][0].lower() + x['estado_solicitud'][1:]).replace(': ', '; ') + ';' for x in LAG if x['id'] in ('D01', 'D02', 'D04', 'D09', 'D15', 'D17'))[:-1] + '.'}}

**Límites.** El contraste de valores con el original exige volver a descargar los ficheros
(`DESCARGAR_HORARIOS <- TRUE` en `main.R`, que compara el SHA-256 con el registrado); en la ejecución entregada
no se volvió a descargar nada. La huella prueba la integridad de la copia, no la autenticidad del origen.

## 9. Hechos separados de escenarios

**Criterio.** Rotular cada cifra como observación, estimación, supuesto o resultado simulado; distinguir los
escenarios a 1, 5 y 10 años de las previsiones verificadas; probar crecimiento, demanda inducida, cambios modales y
retrasos de obra; que gráficos y conclusiones digan horizonte, hipótesis e incertidumbre.

**Resultado.**
- `datos/limitaciones_por_resultado.csv`: {{len(LIM)}} resultados con su categoría ({{LIMC_TXT}}),
  origen, limitaciones e incertidumbre. Las tablas de resultados simulados repiten la categoría.
- `graficos_metadatos.csv`: los {{len(MG)}} gráficos con su tipo de resultado, horizonte, hipótesis e incertidumbre.
- **Ninguna previsión está verificada**: son escenarios condicionados. `previsiones_condicionadas.csv` separa el
  crecimiento de la demanda, los cambios de red, el trasvase al transporte público y la demanda inducida, cada uno
  con su condición de validez.
- **Pruebas de escenario:**
  - crecimiento de la demanda de 0 %, 0,5 % y 1 % anual, con y sin adaptación (`evolucion_sin_actuar.csv`);
  - demanda inducida a 1, 5 y 10 años y un escenario de demanda inducida alta (`escenarios_adversos.csv`);
  - trasvase al transporte público: un 10 % de la punta de la mañana reduciría la demora un
    {{pct(TP('m', 0.10, 'reduccion_1er_anio'))}} ({{pr(TP('m', 0.10, 'p10_1er_anio'), TP('m', 0.10, 'p90_1er_anio'))}}) el primer año (`transporte_publico_trasvase.csv`);
  - retraso de la obra del tercer carril: entrando en servicio en 2029 o en 2032, con crecimiento del
    {{es(100 * g_c, 1)}} % anual, reduciría la demora un {{pct(RETV(2029, g_c, 'tercer_carril_corto', 'reduccion_mediana'))}} y un {{pct(RETV(2032, g_c, 'tercer_carril_corto', 'reduccion_mediana'))}} el primer año (`retraso_obra_tercer_carril.csv`);
{{('  - supuesto de la descarga fuera de las horas con datos: con crecimiento del ' + es(100 * g_c, 1) + ' % anual, la cola de la mañana en 2035 sería de ' + es(SDPV('Principal', g_c, 2035), 1) + ' h con el supuesto principal y de ' + es(SDPV('Sensibilidad', g_c, 2035), 1) + ' h si la descarga reducida de las últimas horas con datos se mantuviera el resto del día (`sensibilidad_prevision_descarga.csv`).') if SDP_OK else '  - la especificación elegida no reduce la descarga por hora, así que no hay supuesto sobre la descarga fuera de las horas con datos.'}}

## 10. Reproducibilidad

**Criterio.** Versiones de R y de los paquetes, semillas y zona horaria fijadas; ejecución completa y pruebas;
hashes y métricas regeneradas iguales a las guardadas dentro de una tolerancia definida; avisos y errores
registrados.

**Resultado.**
- **Entorno:** R 4.3.3 y {{n_renv}} paquetes fijados en `renv.lock`; `main.R` compara al empezar las versiones instaladas con
  `entorno/versiones_paquetes.csv` (`entorno_versiones.csv`{{': todas coinciden' if all(x['coincide'] == 'TRUE' for x in T('entorno_versiones')) else ': ALGUNA NO COINCIDE'}}).
- **Semillas:** una por cada paso aleatorio, todas fijas y listadas en `montecarlo_semillas.csv` ({{len(SEMT)}} filas); una
  prueba comprueba que cada semilla del código está en la tabla.
- **Zona horaria:** `Atlantic/Canary`, fijada en `main.R` (`configuracion_ejecucion.csv`: {{CFG.get('zona_horaria', '—')}}).
- **Ejecución completa sin intervención:** {{es(minutos, 1)}} minutos, {{n_avisos}} avisos (`registro_avisos.txt`, que recoge todos
  los avisos del análisis) y ningún error; las salidas se borran al empezar y las entradas no cambian durante la
  ejecución (comprobado con sus huellas).
- **Pruebas:** {{n_bloq}} bloques y {{es(n_comp)}} comprobaciones, {{n_fallos}} fallos{{(' y ' + str(n_omit) + ' omitidas') if n_omit else ''}} (`salidas/resultado_pruebas.csv`).
- **Dos ejecuciones completas, en copias limpias** (`docs/reproducibilidad_dos_ejecuciones.csv`, con
  `tests/comparar_ejecuciones.R`): {{n_rep_ok}} de {{n_rep}} tablas y gráficos de salidas dentro de la tolerancia (diferencia relativa
  ≤ {{tol_rep}} en las cifras, mismas filas, columnas y textos; los gráficos, iguales byte a byte), contando la serie horaria
  comprimida y el resultado de las pruebas, ejecutadas en las dos copias; {{n_rep_byte}} son iguales byte a byte. No se comparan
  los {{n_rep_prop}} ficheros propios de cada ejecución (la configuración, con su hora de inicio, y el manifiesto de huellas) ni
  los registros de texto de la ejecución (resumen, sesión y avisos), que llevan la hora; los de la segunda copia se
  conservan en `docs/segunda_ejecucion/` y su registro de avisos también dice «{{AVISOS_B}} avisos».
- **No regresión:** {{n_ref}} tablas clave de la ejecución entregada en `tests/referencia/`, con su configuración; una
  ejecución completa nueva con la misma configuración tiene que reproducirlas con una tolerancia relativa de 1e-8.
- **Manifiestos:** `salidas/manifiesto_ejecucion.csv` (código, datos y salidas al acabar) y `manifiesto_entrega.csv`
  (todos los ficheros entregados).

**Límites.** Las dos ejecuciones se hicieron en la misma máquina: muestran que el resultado no depende de la
ejecución, no que otra persona lo reproduzca en otro equipo.
