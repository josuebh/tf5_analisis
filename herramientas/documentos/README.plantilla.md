{% M1 = 'montecarlo_caso1_manana_hacia_santa_cruz' %}
{% M2 = 'montecarlo_caso2_regreso_hacia_el_norte' %}
{% MC = lambda c, e, col: v(M1 if c == 'm' else M2, col, escenario=e) %}
{% RR = lambda c, e: f"{pct(MC(c, e, 'mediana'))} ({pr(MC(c, e, 'p10'), MC(c, e, 'p90'))})" %}
{% FA = lambda c, a, col: v('fichas_alternativas', col, caso=c, alternativa=a) %}
{% FR = lambda c, a: f"{pct(FA(c, a, 'mediana_1er_anio'))} ({pr(FA(c, a, 'p10_1er_anio'), FA(c, a, 'p90_1er_anio'))})" %}
{% FR10 = lambda c, a: f"{pct(FA(c, a, 'mediana_10_anios'))} ({pr(FA(c, a, 'p10_10_anios'), FA(c, a, 'p90_10_anios'))})" %}
{% ALT = {'tarificacion': 'tarificación de la punta', 'paquete_gestion': 'regulación de accesos + escalonamiento', 'tercer_carril': 'tercer carril', 'ramp_metering': 'regulación de accesos', 'escalonamiento': 'escalonamiento horario'} %}
{% ALTN = {'tarificacion': 'tarificación de la punta (no la permite la ley)', 'paquete_gestion': 'regulación de accesos + escalonamiento', 'tercer_carril': 'tercer carril hipotético (no proyectado)', 'ramp_metering': 'regulación de accesos', 'escalonamiento': 'escalonamiento horario'} %}
{% NOMBRE = lambda c, a: (ALTN if c == 't' else ALT)[a] if a != 'tarificacion' else ALTN[a] %}
{% NOMBREM = lambda c, a: NOMBRE(c, a)[0].upper() + NOMBRE(c, a)[1:] %}
{% orden = lambda c: sorted(ALT, key=lambda a: -FA(c, a, 'mediana_1er_anio')) %}
{% lista = lambda c: (lambda t: t[0].upper() + t[1:])('; '.join(f"{NOMBRE(c, a)} {FR(c, a)}" for a in orden(c))) %}
{% CONF = lambda c, a: s('fichas_alternativas', 'confianza', caso=c, alternativa=a) %}
{% H = lambda h, col: v('holgura_aguas_abajo_por_hora', col, hora=h) %}
{% HM = lambda h, col: v('holgura_la_matanza_por_hora', col, hora=h) %}
{% SINH = lambda x: 'ningún día sin capacidad libre' if round(100 * x) == 0 else 'sin capacidad libre el ' + pct(x) + ' de los días' %}
{% HR = lambda h: f"{pct(H(h, 'mediana'), 1)} ({pct(H(h, 'p10'), 1)} a {pct(H(h, 'p90'), 1)}); {SINH(H(h, 'sin_holgura'))}" %}
{% HMR = lambda h: f"{pct(HM(h, 'mediana'), 1)} ({pct(HM(h, 'p10'), 1)} a {pct(HM(h, 'p90'), 1)}); {SINH(HM(h, 'sin_holgura'))}" %}
{% SH1 = lambda pre, e, col: v('sensibilidad_holgura_resultados_caso1', col, variante=starts(pre), escenario=e) %}
{% SH2 = lambda pre, e, col: v('sensibilidad_holgura_resultados_caso2', col, variante=starts(pre), escenario=e) %}
{% SHH1 = lambda pre, h, col: v('sensibilidad_holgura_caso1', col, variante=starts(pre), hora=h) %}
{% VAR1 = [x['variante'] for x in T('sensibilidad_holgura_resultados_caso1') if x['escenario'] == 'tercer_carril_corto'] %}
{% VAR2 = [x['variante'] for x in T('sensibilidad_holgura_resultados_caso2') if x['escenario'] == 'tercer_carril_corto'] %}
{% COMPAT1 = [x for x in VAR1 if not x.startswith('Holgura nula') and SH1(x, 'tercer_carril_corto', 'parte_cola_hoy_en_rango_medido') >= 0.5] %}
{% COMPAT2 = [x for x in VAR2 if not x.startswith('Holgura nula') and SH2(x, 'tercer_carril_corto', 'parte_cola_hoy_en_rango_medido') >= 0.5] %}
{% tc_min1 = min(SH1(x, 'tercer_carril_corto', 'mediana') for x in COMPAT1) %}
{% tc_max1 = max(SH1(x, 'tercer_carril_corto', 'mediana') for x in COMPAT1) %}
{% tc_min2 = min(SH2(x, 'tercer_carril_corto', 'mediana') for x in COMPAT2) %}
{% tc_max2 = max(SH2(x, 'tercer_carril_corto', 'mediana') for x in COMPAT2) %}
{% INCOMP1 = [x for x in VAR1 if not x.startswith('Holgura nula') and x not in COMPAT1] %}
{% VM = lambda c, ind, col: v('validacion_modelo', col, caso=c, indicador=ind) %}
{% DESC = 'Caudal de descarga con cola (mediana)' %}
{% IGUAL = 'Caudal en las horas con cola, medido igual en el modelo y en el aforo (mediana de las medianas diarias)' %}
{% DIA_IGUAL = 'Descarga del día medida igual en el modelo y en el aforo' %}
{% VD = lambda c, ind, per, col: v('validacion_diaria', col, caso=c, indicador=ind, periodo=per) %}
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
{% DG = lambda c, b, g, f, col: v('diagnostico_descarga', col, caso=c, bloque=b, grupo=g, fuente=f) %}
{% FI = lambda c, r, col: v('montecarlo_filtros', col, caso=c, regla=r) %}
{% FIU = lambda c, r: s('montecarlo_filtros', 'umbral', caso=c, regla=r) %}
{% REG_MIN = min(['Duración de la cola (horas como el aforo)', 'Caudal de descarga', 'Inicio de la cola', 'Fin de la cola'], key=lambda r: FI('m', r, 'tasa')) %}
{% SC = lambda c, r, e, col: v('sensibilidad_calibracion_caso1' if c == 'm' else 'sensibilidad_calibracion_caso2', col, regla=r, escenario=e) %}
{% SCR = lambda c, r, e: f"{pct(SC(c, r, e, 'mediana'))} ({pr(SC(c, r, e, 'p10'), SC(c, r, e, 'p90'))})" %}
{% RP = 'Aforos horarios 2025 (principal)' %}
{% RSC = 'Sin calibrar (muestra aleatoria con cola)' %}
{% REGLAS_SC = lambda c: [x['regla'] for x in T('sensibilidad_calibracion_caso1' if c == 'm' else 'sensibilidad_calibracion_caso2') if x.get('escenario') == 'tercer_carril_corto'] %}
{% DIM = lambda m, col: v('diferencias_interanuales_por_mes', col, estacion_id=99, variable='cola', mes=m) %}
{% NUMW = {1: 'una', 2: 'dos', 3: 'tres', 4: 'cuatro', 5: 'cinco', 6: 'seis', 7: 'siete', 8: 'ocho', 9: 'nueve', 10: 'diez', 11: 'once', 12: 'doce', 13: 'trece', 14: 'catorce'} %}
{% ID = lambda c, i, col: v('indicadores_demora', col, caso=c, indicador=i) %}
{% IDR = lambda c, i, d=0: f"{es(ID(c, i, 'simulado_mediana'), d)} ({es(ID(c, i, 'simulado_p10'), d)}-{es(ID(c, i, 'simulado_p90'), d)})" %}
{% EV = lambda c, g, y, col: v('evolucion_sin_actuar', col, caso=c, crecimiento_anual=lambda x: abs(float(x) - g) < 1e-9, anio=y) %}
{% EVR = lambda c, g, y: f"{es(EV(c, g, y, 'horas_cola_sin_adaptacion'), 1)} ({es(EV(c, g, y, 'horas_cola_sin_p10'))}-{es(EV(c, g, y, 'horas_cola_sin_p90'))})" %}
{% EVA = lambda c, g, y: f"{es(EV(c, g, y, 'horas_cola_con_adaptacion'), 1)}" %}
{% A30 = lambda c, g, e, col: v('alternativas_2030_por_crecimiento', col, caso=c, crecimiento_anual=lambda x: abs(float(x) - g) < 1e-9, escenario=e, anio=2030) %}
{% A30R = lambda c, g, e: f"{pct(A30(c, g, e, 'reduccion_mediana'))} ({pr(A30(c, g, e, 'reduccion_p10'), A30(c, g, e, 'reduccion_p90'))})" %}
{% EA = lambda c, sup, e: v('escenarios_adversos', 'reduccion_mediana', caso=c, supuesto=starts(sup), escenario=e) %}
{% EAX = lambda c, sup, e, col: v('escenarios_adversos', col, caso=c, supuesto=starts(sup), escenario=e) %}
{% EAR = lambda c, sup, e: f"{pct(EA(c, sup, e))} ({pr(EAX(c, sup, e, 'reduccion_p10'), EAX(c, sup, e, 'reduccion_p90'))})" %}
{% TP = lambda c, t, col: v('transporte_publico_trasvase', col, caso=c, trasvase=lambda x: abs(float(x) - t) < 1e-9) %}
{% GEO = T('geometria_y_capacidad') %}
{% n_conf = sum(1 for x in GEO if x['estado'] == 'confirmado') %}
{% n_pend = sum(1 for x in GEO if x['estado'].startswith('pendiente')) %}
{% UG = T('uso_de_la_geometria') %}
{% PROC = T('procedencia_datos') %}
{% n_h = sum(1 for x in PROC if x['id'].startswith('H-')) %}
{% n_o = sum(1 for x in PROC if x['id'].startswith('O-')) %}
{% n_f = sum(1 for x in PROC if x['id'].startswith('F-')) %}
{% n_int = sum(1 for x in PROC if x['integridad'].startswith('Copia íntegra')) %}
{% n_coinc = sum(1 for x in PROC if x['contraste_catalogo'].startswith('Coincide')) %}
{% n_tot = sum(1 for x in PROC if x['id'].startswith('H-') and x['conservacion_totales'].startswith('Totales del extracto')) %}
{% CPO = T('contraste_publicacion_original') %}
{% n_cpo = sum(1 for x in CPO if x['resultado'] == 'coincide') %}
{% PRU = csvp('salidas/resultado_pruebas.csv') %}
{% n_bloq = len(PRU) %}
{% n_comp = sum(int(x['nb']) for x in PRU) %}
{% n_fallos = sum(int(x['failed']) for x in PRU) + sum(1 for x in PRU if x['error'] == 'TRUE') %}
{% n_omit = sum(1 for x in PRU if x['skipped'] == 'TRUE') %}
{% minutos = float(re.search(r'Duración: ([0-9.]+) min', leer('salidas/registro_sesion.txt')).group(1)) %}
{% MESES = ['', 'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'] %}
{% INICIO = re.search(r'(\d{4})-(\d{2})-(\d{2})', [x for x in csvp('salidas/configuracion_ejecucion.csv') if x['parametro'] == 'inicio'][0]['valor']) %}
{% FECHA_EJEC = f"{int(INICIO.group(3))} de {MESES[int(INICIO.group(2))]} de {INICIO.group(1)}" %}
{% n_avisos = int(re.search(r'main.R: ([0-9]+)', leer('salidas/registro_avisos.txt')).group(1)) %}
{% _m_ent = re.search(r'Entradas sin cambios durante la ejecución: los ([0-9.]+) ficheros', leer('salidas/resumen_resultados.txt')) %}
{% n_entradas = _m_ent.group(1) if _m_ent else 'SIN DATO' %}
{% CD = lambda c, col: v('caudal_descarga_cuellos', col, caso=c) %}
{% BA = lambda tramo, col: v('balance_por_tramos', col, tramo=tramo) %}
{% KG = lambda e, sen, col: v('k_critico_geometria_alternativa', col, estacion_id=e, sentido=sen) %}
{% EVI = lambda et, col: v('evolucion_imd_2019_2025', col, etiqueta=et) %}
{% EV_MAX = max(T('evolucion_imd_2019_2025'), key=lambda x: float(x['imd_2025'])) %}
{% CORR = [x for x in T('evolucion_imd_2019_2025') if x['estacion_id'] in ('85', '93', '97', '99', '103', '111', '123')] %}
{% _chk_corr = 1 / int(len(CORR) == 7) %}
{% CORR_MIN = min(CORR, key=lambda x: float(x['var_2019_2025'])) %}
{% CORR_MAX = max(CORR, key=lambda x: float(x['var_2019_2025'])) %}
{% VEL_PA = lambda sen: (lambda r: sum(float(x['horas_velocidad']) for x in r) / sum(float(x['horas_mes']) for x in r))(rows('cobertura_y_calidad', etiqueta='Padre Anchieta', sentido=sen)) %}
{% DUP = re.findall(r'registros duplicados: (\d+) \(hora 02\)', leer('salidas/resumen_resultados.txt')) %}
{% _chk_dup = 1 / int(len(DUP) == 2) %}
{% POB = csvp('datos/poblacion_tenerife.csv') %}
{% pob_a = POB[0] %}
{% pob_b = POB[-1] %}
{% pob_g = (float(pob_b['poblacion']) / float(pob_a['poblacion'])) ** (1 / (int(pob_b['anio']) - int(pob_a['anio']))) - 1 %}
{% KC = lambda sen: v('k_critico_2025', 'imd_dir', estacion_id=103, sentido=sen) / v('k_critico_2025', 'carriles', estacion_id=103, sentido=sen) %}
{% N_REG = sum(int(x['filas_tf5']) for x in T('horarios_procedencia')) %}
{% _chk_reg = 1 / int(len(T('horarios_procedencia')) == 24) %}
{% CONTR_N = rx('salidas/resumen_resultados.txt', r'Contraste con las copias locales de los CSV oficiales [^\n]*: ([0-9.]+) valores, ([0-9.]+) diferencias', 1) %}
{% CONTR_DIF = rx('salidas/resumen_resultados.txt', r'Contraste con las copias locales de los CSV oficiales [^\n]*: ([0-9.]+) valores, ([0-9.]+) diferencias', 2) %}
{% N_DIAS_VAL = sum(int(x['dias_validos']) for x in T('cobertura_y_calidad')) %}
{% COB_PA = (lambda r: sum(float(x['horas_completas']) for x in r) / sum(float(x['horas_mes']) for x in r))(rows('cobertura_y_calidad', etiqueta='Padre Anchieta')) %}
{% ULL = lambda e, var, col: v('ull_diferencias_en_diferencias', col, estacion_id=e, sentido='descendente', variable=var, control='julio') %}
{% ULL_ON = lambda e, col: v('comparacion_ull_oct_nov_2024_2025', col, estacion_id=e, sentido='descendente') %}
{% C26 = lambda e, sen, col: v('comparacion_2025_2026_ene_sep', col, estacion_id=e, sentido=sen) %}
{% C26TXT = lambda e, sen: f"{es(C26(e, sen, 'horas_cong_a'), 2)} → {es(C26(e, sen, 'horas_cong_b'), 2)}" %}
{% PV = lambda p: ('p < 0,001' if p < 0.001 else 'p = ' + es(p, 2)) %}
{% CC = lambda col: v('parametros_usados_caso1', col, parametro='c_carril') %}
{% N_SENS_HOLG = max(int(x['simulaciones']) for x in T('sensibilidad_holgura_resultados_caso1')) %}
{% VDIA = lambda sen: sum(float(x['veh']) for x in rows('perfil_horario_laborable_2025', estacion_id=103, sentido=sen)) %}
{% VMAX = lambda sen: gz_max('salidas/tablas/horarios_corredor_con_banderas.csv.gz', 'veh', estacion_id='103', sentido=sen, usado_en_el_analisis='TRUE', dia=starts('2025')) %}
{% IMDP = csvp('salidas/panel/imd_tf5_2018_2025.csv') %}
{% IMD4 = lambda a: (lambda vv: sum(vv) / len(vv))([float(x['imd_total']) for x in IMDP if x['anio'] == a and x['estacion_id'] in ('93', '99', '103', '111')]) %}
{% _chk_imd4 = 1 / int(sum(1 for x in IMDP if x['anio'] == '2025' and x['estacion_id'] in ('93', '99', '103', '111')) == 4 and sum(1 for x in IMDP if x['anio'] == '2019' and x['estacion_id'] in ('93', '99', '103', '111')) == 4) %}
{% TPV = csvp('datos/transporte_publico_viajeros.csv') %}
{% TITSA = lambda a: float([x for x in TPV if x['operador'] == 'TITSA' and x['anio'] == a][0]['viajeros']) %}
{% DEP = lambda var, e, col: v('sensibilidad_depuracion', col, variante=starts(var), estacion_id=e) %}
{% dep_rows = T('sensibilidad_depuracion') %}
{% dep_dh = max(abs(float(x['horas_cola_media']) - DEP('Principal', x['estacion_id'], 'horas_cola_media')) for x in dep_rows) %}
{% dep_dd = max(abs(float(x['descarga_mediana']) - DEP('Principal', x['estacion_id'], 'descarga_mediana')) for x in dep_rows) %}
{% SSA = T('sensibilidad_sin_dias_atipicos') %}
{% SSAV = lambda var, e, col: float([x for x in SSA if x['variante'].startswith(var) and x['estacion_id'] == str(e)][0][col]) %}
{% ssa_dh = max(abs(float(x['horas_cola_media']) - SSAV('Todos', x['estacion_id'], 'horas_cola_media')) for x in SSA) %}
{% ssa_dd = max(abs(float(x['descarga_mediana']) - SSAV('Todos', x['estacion_id'], 'descarga_mediana')) for x in SSA) %}
{% DA = T('dias_atipicos_resumen') %}
{% DAN = lambda et, sen, trat: sum(int(x['dias']) for x in DA if x['etiqueta'] == et and x['sentido'] == sen and x['tratamiento'].startswith(trat)) %}
{% CONG = lambda e, sen, col: v('congestion_diaria_2025', col, estacion_id=e, sentido=sen) %}
{% HC = lambda cu, col: v('horario_cola', col, cuello=cu) %}
{% HC25M = 'Mañana hacia Santa Cruz (Ermita Cruz Chica), 2025' %}
{% HC26M = 'Mañana hacia Santa Cruz (Ermita Cruz Chica), 2026' %}
{% HC25T = 'Tarde hacia el Norte (Bomberos La Laguna), 2025' %}
{% HC26T = 'Tarde hacia el Norte (Bomberos La Laguna), 2026' %}
{% EST = lambda c, e, col: v('estabilidad_percentiles', col, caso=c, escenario=e) %}
{% ee_max = max(float(x['ee_mediana']) for x in T('estabilidad_percentiles')) %}
{% ee_min = min(float(x['ee_mediana']) for x in T('estabilidad_percentiles')) %}
{% PP = lambda c, p, col: v('parametros_prior_posterior', col, caso=c, parametro=p) %}
{% n_acep1 = int(PP('m', 'c_carril', 'aceptadas')) %}
{% n_sim1 = int(PP('m', 'c_carril', 'simuladas')) %}
{% n_acep2 = int(PP('t', 'c_carril', 'aceptadas')) %}
{% n_sim2 = int(PP('t', 'c_carril', 'simuladas')) %}
{% RHO_T = T('sensibilidad_tercer_carril') %}
{% RHO = lambda p: v('sensibilidad_tercer_carril', 'rho', parametro=p) %}
{% TCH = lambda h, hz, col: v('tercer_carril_segun_holgura', col, holgura=lambda x: abs(float(x) - h) < 1e-9, horizonte=hz) %}
{% TCN = lambda h, hz, col: v('tercer_carril_norte_segun_holgura', col, holgura=lambda x: abs(float(x) - h) < 1e-9, horizonte=hz) %}
{% BV = T('bus_vao_trasvase_necesario') %}
{% bv_eq = quant([float(x['equilibrio']) for x in BV], 0.5) %}
{% bv_mi = [float(x['mitad']) for x in BV] %}
{% EXT = lambda c, e, col: v('diagnostico_reducciones_extremas', col, caso=c, escenario=e) %}
{% LIM = T('limitaciones_por_resultado') %}
{% n_lim = len(LIM) %}
{% n_renv = len(__import__('json').loads(leer('renv.lock'))['Packages']) %}
{% ELX = T('eleccion_especificacion') %}
{% ELEG = lambda c: [x for x in ELX if x['caso'] == CASOS[c] and x['elegida'] == 'TRUE'][0] %}
{% REF = lambda c: [x for x in ELX if x['caso'] == CASOS[c] and x['referencia'] == 'TRUE'][0] %}
{% describir = lambda x: (' + '.join([p for p, k in (('propagación de la cola del tramo siguiente', 'propagacion'), ('descarga dependiente de la hora', 'horario'), ('mezcla de pesados', 'pesados')) if x[k] == 'TRUE']) or 'descarga constante') + ('; descarga calibrada medida igual que en el aforo' if x['medida_descarga'] == 'como_aforo' else '; descarga calibrada como parámetro') %}
{% es_ref = lambda c: ELEG(c)['referencia'] == 'TRUE' %}
{% n_adm = lambda c: sum(1 for x in ELX if x['caso'] == CASOS[c] and x['admisible'] == 'TRUE') %}
{% VCX = T('validacion_cruzada') %}
{% igual_spec = lambda x, e: all(x[k] == e[k] for k in ('propagacion', 'horario', 'pesados', 'medida_descarga')) %}
{% P26X = lambda c, e, ind, col: float([x for x in VCX if x['caso'] == CASOS[c] and x['prueba'] == '2026' and x['indicador'] == ind and igual_spec(x, e)][0][col]) %}
{% IND_DIA = 'Descarga del día (medida igual en el modelo y en el aforo)' %}
{% CVX = lambda c, e, ind, cal, col: float([x for x in VCX if x['caso'] == CASOS[c] and x['calibracion'] == cal and x['indicador'] == ind and igual_spec(x, e)][0][col]) %}
{% DIST = lambda c, e: (abs(CVX(c, e, IND_DIA, 'A', 'cobertura_intervalo_predictivo') - 0.8) + abs(CVX(c, e, IND_DIA, 'B', 'cobertura_intervalo_predictivo') - 0.8)) / 2 %}
{% COBTXT = lambda c: 'se acerca más al 80 %' if DIST(c, ELEG(c)) < DIST(c, REF(c)) - 0.005 else ('se aleja del 80 %' if DIST(c, ELEG(c)) > DIST(c, REF(c)) + 0.005 else 'queda a la misma distancia del 80 %') %}
{% COB26 = lambda c: (lambda e, r: ', igual que con la referencia.' if pct(e) == pct(r) else ', frente al ' + pct(r) + ' con la referencia' + (' (algo más lejos del 80 %)' if abs(e - 0.8) > abs(r - 0.8) + 0.005 else (' (más cerca del 80 %)' if abs(e - 0.8) < abs(r - 0.8) - 0.005 else '')) + '.')(P26X(c, ELEG(c), IND_DIA, 'cobertura_intervalo_predictivo'), P26X(c, REF(c), IND_DIA, 'cobertura_intervalo_predictivo')) %}
{% COB_FRASE = lambda c: f"La cobertura del intervalo predictivo del 80 % de esa descarga {COBTXT(c)} en la validación cruzada ({pct(CVX(c, ELEG(c), IND_DIA, 'A', 'cobertura_intervalo_predictivo'))} y {pct(CVX(c, ELEG(c), IND_DIA, 'B', 'cobertura_intervalo_predictivo'))} en las dos mitades con la elegida, frente a {pct(CVX(c, REF(c), IND_DIA, 'A', 'cobertura_intervalo_predictivo'))} y {pct(CVX(c, REF(c), IND_DIA, 'B', 'cobertura_intervalo_predictivo'))} con la referencia); en 2026 es del {pct(P26X(c, ELEG(c), IND_DIA, 'cobertura_intervalo_predictivo'))}" + COB26(c) + (f" Con la elegida, la banda de parámetros cubre menos días en 2026 ({pct(P26X(c, ELEG(c), IND_DIA, 'cobertura_banda_parametros'))} frente a {pct(P26X(c, REF(c), IND_DIA, 'cobertura_banda_parametros'))}): no es un fallo, porque la banda describe un día típico y no la variabilidad entre días." if P26X(c, ELEG(c), IND_DIA, 'cobertura_banda_parametros') < P26X(c, REF(c), IND_DIA, 'cobertura_banda_parametros') - 0.02 else "") %}
{% DEM = T('diferencias_emparejadas') %}
{% DEMV = lambda c, h, a, b: [x for x in DEM if x['caso'] == CASOS[c] and x['horizonte'] == h and x['alternativa_a'] == a and x['alternativa_b'] == b][0] %}
{% TP_PG = lambda c: DEMV(c, 'corto', 'tercer_carril', 'paquete_gestion') %}
{% ART = {'tercer_carril': 'el tercer carril', 'paquete_gestion': 'la regulación + escalonamiento', 'ramp_metering': 'la regulación de accesos', 'escalonamiento': 'el escalonamiento horario', 'tarificacion': 'la tarificación'} %}
{% LECTP = lambda c, a, b: (lambda l: 'sin diferencia material' if l.startswith('Sin diferencia material') else ('sin diferencia distinguible del error de muestreo' if l.startswith('Sin diferencia distinguible') else (ART[a] + ' reduce más en al menos el 90 % de las combinaciones' if l.startswith('A reduce') else (ART[b] + ' reduce más en al menos el 90 % de las combinaciones' if l.startswith('B reduce') else 'depende de los parámetros'))))(DEMV(c, 'corto', a, b)['lectura']) %}
{% SERIE = lambda xs: ('un ' + xs[0] + ' en todos los casos') if len(set(xs)) == 1 else ('un ' + ', '.join(xs[:-1]) + ' y ' + xs[-1] + ', respectivamente') %}
{% TIPO = lambda c: (lambda l: 'material' if l.startswith('Sin diferencia material') else ('muestreo' if l.startswith('Sin diferencia distinguible') else ('a' if l.startswith('A reduce') else ('b' if l.startswith('B reduce') else 'depende'))))(TP_PG(c)['lectura']) %}
{% LECT = lambda c: {'material': 'sin diferencia material (menos de 2 puntos)', 'muestreo': 'sin diferencia distinguible del error de muestreo', 'a': 'el tercer carril reduce más en al menos el 90 % de las combinaciones', 'b': 'la regulación + escalonamiento reduce más en al menos el 90 % de las combinaciones', 'depende': 'depende de los parámetros (la banda de la diferencia cruza el 0)'}[TIPO(c)] %}
{% LECTF = lambda c: {'material': 'no hay una diferencia material entre los dos', 'muestreo': 'la diferencia entre los dos no se distingue del error de muestreo', 'a': 'el tercer carril reduce más que la gestión en al menos el 90 % de las combinaciones', 'b': 'la gestión reduce más que el tercer carril en al menos el 90 % de las combinaciones', 'depende': 'cuál de los dos reduce más depende de los parámetros (la banda de la diferencia cruza el 0)'}[TIPO(c)] %}
{% DIFR = lambda c: f"{sg(100 * float(TP_PG(c)['dif_mediana']), 1)} puntos ({sg(100 * float(TP_PG(c)['dif_p10']), 1)} a {sg(100 * float(TP_PG(c)['dif_p90']), 1)})" %}
{% CPR = T('coste_plazo_riesgo') %}
{% CR = T('cola_remanente_aguas_abajo') %}
{% CRV = lambda L, col: float([x for x in CR if abs(float(x['longitud_km']) - L) < 1e-9][0][col]) %}
{% RET = T('retraso_obra_tercer_carril') %}
{% RETV = lambda a, g, e, col: float([x for x in RET if x['anio'] == str(a) and abs(float(x['crecimiento_anual']) - g) < 1e-9 and x['escenario'] == e][0][col]) %}
{% g_c = float([x for x in csvp('datos/escenarios_demanda.csv') if x['escenario'] == 'Central'][0]['crecimiento_anual']) %}
{% SDP_OK = __import__('os').path.exists(PROY + '/salidas/tablas/sensibilidad_prevision_descarga.csv') %}
{% SDPV = (lambda sup, g, a: float([x for x in T('sensibilidad_prevision_descarga') if x['supuesto'].startswith(sup) and abs(float(x['crecimiento_anual']) - g) < 1e-9 and x['anio'] == str(a)][0]['horas_cola_sin_adaptacion'])) if SDP_OK else None %}
{% REPRO = csvp('docs/reproducibilidad_dos_ejecuciones.csv') %}
{% n_rep = sum(1 for x in REPRO if x['dentro_de_tolerancia'] in ('TRUE', 'FALSE')) %}
{% n_rep_ok = sum(1 for x in REPRO if x['dentro_de_tolerancia'] == 'TRUE') %}
{% n_rep_prop = sum(1 for x in REPRO if x['estado'].startswith('propio')) %}
{% n_rep_byte = sum(1 for x in REPRO if x['estado'] == 'igual (byte a byte)') %}
{% tol_rep = REPRO[0]['tolerancia_relativa'] %}
{% MG = T('graficos_metadatos') %}
{% SEMS = T('montecarlo_otras_semillas') %}
{% SEM_LIST = sorted(set(x['semilla'] for x in SEMS)) %}
{% SEMV = lambda c, sem, e, col: float([x for x in SEMS if x['caso'] == CASOS[c] and x['semilla'] == sem and x['escenario'] == e][0][col]) %}
{% PRV = T('montecarlo_previas_alternativas') %}
{% PREVIAS = lambda c: sorted(set(x['previa'] for x in PRV if x['caso'] == CASOS[c])) %}
{% PRVV = lambda c, pv, e, col: float([x for x in PRV if x['caso'] == CASOS[c] and x['previa'] == pv and x['escenario'] == e][0][col]) %}
{% PRV_D = [(abs(PRVV(c, pv, e, 'mediana') - SC(c, RP, e, 'mediana')), PRVV(c, pv, e, 'tamano_efectivo') >= 0.1 * (n_acep1 if c == 'm' else n_acep2)) for c in 'mt' for pv in PREVIAS(c) for e in ('tercer_carril_corto', 'paquete_gestion_corto')] %}
{% prv_max_ok = max([d for d, ok in PRV_D if ok] or [0.0]) %}
{% prv_max_all = max(d for d, ok in PRV_D) %}
{% NULA1_OK = SH1('Holgura nula', 'tercer_carril_corto', 'parte_cola_hoy_en_rango_medido') >= 0.5 %}
{% RANGO1_TABLA = ('Con las estimaciones compatibles con las colas medidas, el tercer carril rendiría el 1er año entre nada, si no queda capacidad libre (los aforos no descartan ese caso), y un ' + pct(tc_max1) + '; con alguna capacidad libre, entre un ' + pct(tc_min1) + ' y un ' + pct(tc_max1)) if NULA1_OK else ('Con las estimaciones alternativas compatibles con las colas medidas, el tercer carril rendiría entre un ' + pct(tc_min1) + ' y un ' + pct(tc_max1) + ' el 1er año; sin capacidad libre, nada') %}
{% RANGO1_TEXTO = ('entre nada, si ese tramo está lleno, y un ' + pct(tc_max1) + ' el primer año; entre un ' + pct(tc_min1) + ' y un ' + pct(tc_max1) + ' si le queda alguna capacidad libre') if NULA1_OK else ('entre un ' + pct(tc_min1) + ' y un ' + pct(tc_max1) + ' el primer año, y nada si ese tramo está lleno') %}
{% RANGO2_TEXTO = ('la especificación no tiene propagación de la cola, así que la cola de hoy no depende de la capacidad libre y las colas medidas no descartan ninguna variante: el tercer carril hipotético va de nada, con holgura nula, al ' + pct(tc_max2) + ', y del ' + pct(tc_min2) + ' al ' + pct(tc_max2) + ' si queda alguna capacidad libre') if ELEG('t')['propagacion'] != 'TRUE' else ('el tercer carril hipotético va del ' + pct(tc_min2) + ' al ' + pct(tc_max2) + ' entre las variantes compatibles con las colas medidas') %}
{% PES_ALT = [x for x in ELX if x['caso'] == CASOS['m'] and x['admisible'] == 'TRUE' and x['elegida'] != 'TRUE' and all(x[k] == ELEG('m')[k] for k in ('propagacion', 'horario', 'medida_descarga')) and x['pesados'] != ELEG('m')['pesados']] %}
{% PES_EMPATE = (' La mezcla de pesados entra por un empate: ' + ('sin ella' if ELEG('m')['pesados'] == 'TRUE' else 'con ella') + ', el RMSE relativo medio es casi el mismo (' + es(float(PES_ALT[0]['rmse_relativo_medio']), 4) + ' frente a ' + es(float(ELEG('m')['rmse_relativo_medio']), 4) + ') y el sesgo absoluto de la descarga es ' + ('menor' if float(PES_ALT[0]['sesgo_descarga']) < float(ELEG('m')['sesgo_descarga']) else 'mayor') + ' (' + es(float(PES_ALT[0]['sesgo_descarga'])) + ' frente a ' + es(float(ELEG('m')['sesgo_descarga'])) + ' veh/h); la regla, fijada de antemano, se queda con la de menor RMSE.') if PES_ALT and abs(float(PES_ALT[0]['rmse_relativo_medio']) - float(ELEG('m')['rmse_relativo_medio'])) < 0.005 else '' %}
{% SC_POCAS = lambda c: [x for x in T('sensibilidad_calibracion_caso1' if c == 'm' else 'sensibilidad_calibracion_caso2') if not x.get('escenario')] %}
{% REGLAS_FUERA_TXT = ''.join(' La regla «' + x['regla'][0].lower() + x['regla'][1:] + '» solo la ' + ('cumple ' if int(x['validas_total']) == 1 else 'cumplen ') + es(int(x['validas_total'])) + ' de ' + es(n_sim1) + ' combinaciones y no se puede usar' + (': con la especificación elegida, el modelo no reproduce a la vez la duración y el horario de la cola y el caudal de las horas de cola plena (apartado 2.5).' if 'cola plena' in x['regla'] else '.') for x in SC_POCAS('m')) %}
{% BN = csvp('docs/comprobacion_base_nocturna_2025.csv') %}
{% BNM = lambda sen: float([x for x in BN if x['etiqueta'] == 'La Matanza' and x['sentido'] == sen][0]['base_noche_24_meses']) %}
{% BN_MOD = sum(int(x['horas_que_cambian']) for x in BN if x['papel_en_el_modelo'] != 'descriptiva') %}
{% BN_DESC = [x for x in BN if x['papel_en_el_modelo'] == 'descriptiva' and int(x['horas_que_cambian']) > 0] %}
{% BN_TXT = ('no cambia ninguna hora congestionada de 2025 en las estaciones que usa el modelo' if BN_MOD == 0 else 'cambian ' + es(BN_MOD) + ' horas congestionadas de 2025 en las estaciones que usa el modelo') + (' (cambian ' + '; '.join(es(int(x['horas_que_cambian'])) + ' de ' + es(int(x['horas_2025'])) + ' horas en ' + x['etiqueta'] + (' hacia el Norte' if x['sentido'] == 'ascendente' else ' hacia Santa Cruz') for x in BN_DESC) + (', que no interviene en él)' if len(BN_DESC) == 1 else ', que no intervienen en él)') if BN_DESC else '') %}
{% CONFIG = {x['parametro']: x['valor'] for x in csvp('salidas/configuracion_ejecucion.csv')} %}
{% N_REJ = int(CONFIG['N_REJILLA']) %}
{% ACEP_REJ = int([x for x in VCX if x['caso'] == CASOS['m'] and x['calibracion'] == 'A+B' and x['prueba'] == '2026' and igual_spec(x, ELEG('m'))][0]['aceptadas']) %}
{% VD26 = [x for x in T('validacion_diaria') if x['periodo'] == P26 and x['nivel'] == 'día'] %}
{% VD26H = {x['caso']: float(x['cobertura_intervalo_predictivo']) for x in T('validacion_diaria') if x['periodo'] == P26 and x['nivel'] == 'hora'} %}
{% VD26_BAJO = [x for x in VD26 if round(100 * float(x['cobertura_intervalo_predictivo'])) < 80] %}
{% COB_TODOS = 'En 2026 el intervalo predictivo cubre, según el indicador diario, entre el ' + pct(min(float(x['cobertura_intervalo_predictivo']) for x in VD26)) + ' y el ' + pct(max(float(x['cobertura_intervalo_predictivo']) for x in VD26)) + ' de los días' + ('; por debajo del 80 % quedan ' + '; '.join(x['indicador'][0].lower() + x['indicador'][1:] + ' (' + NOMC[x['caso']] + ', ' + pct(float(x['cobertura_intervalo_predictivo'])) + ')' for x in VD26_BAJO) if VD26_BAJO else '') + '. Hora a hora, cubre el ' + pct(VD26H[CASOS['m']]) + ' de las horas por la mañana y el ' + pct(VD26H[CASOS['t']]) + ' por la tarde.' %}
{% POS = lambda pos: (DG('m', 'Por posición en la cola', pos, 'modelo (calibrado)', 'mediana'), DG('m', 'Por posición en la cola', pos, 'aforo 2025', 'mediana')) %}
{% VERBO = lambda mo, af: 'reproduce' if abs(mo - af) <= 0.03 * af else ('sobrestima' if mo > af else 'subestima') %}
{% PLENA = 'Descarga en las horas de cola plena' %}
# Análisis integral y modelización predictiva de la congestión de la autopista TF-5 en Tenerife: diagnóstico, evolución y evaluación de alternativas de mejora

Proyecto en R · datos hasta septiembre de 2026 · ejecución del {{FECHA_EJEC}}

Es un **estudio técnico-predictivo con simulación exploratoria**, hecho solo con datos públicos. Responde a tres
preguntas y separa siempre lo que se mide de lo que se estima:

| Pregunta | Con qué | En `main.R` |
|---|---|---|
| **Qué sabemos** | Aforos oficiales del Cabildo de Tenerife: IMD 2018-2025 y {{es(N_REG)}} registros horarios por carril de la TF-5 en 24 ficheros mensuales (septiembre de 2024 a septiembre de 2026, sin diciembre de 2024) | Secciones 1-4 y 4b |
| **Qué estimamos** | Capacidad de cada tramo, capacidad libre del tramo siguiente y balance entre estaciones, deducidos de los aforos; modelo de cola de un día laborable completo en cada cuello, calibrado con 2025, con la especificación de la descarga elegida por validación cruzada dentro de 2025 y contrastado con enero-septiembre de 2026 | Secciones 5-7 |
| **Qué prevemos** | El mismo modelo con la demanda de 2030 y 2035 (crecimiento bajo, central y alto), con cada alternativa, con retrasos de obra, en escenarios adversos y a 1, 5 y 10 años de ponerla en marcha | Sección 8 |

### Cómo leer cada cifra

Cada resultado lleva una de estas etiquetas (columna `categoria` de `datos/limitaciones_por_resultado.csv`, que
tipifica {{n_lim}} resultados; las tablas de resultados simulados la repiten, y `graficos_metadatos.csv` la da para
cada gráfico con su horizonte, su hipótesis y su incertidumbre):

- **Observado:** sale directamente de los aforos oficiales o de documentos, con las reglas de depuración
  declaradas. Ejemplo: las horas de cola de cada día.
- **Estimado:** se deduce de los aforos con un método explícito. Ejemplo: la capacidad libre del tramo siguiente.
- **Supuesto:** un valor o una regla que no sale de los datos del proyecto y se declara. Ejemplos: el crecimiento
  de la demanda, las elasticidades de la literatura o la longitud entre dos cuellos.
- **Simulado:** lo da el modelo calibrado bajo esos supuestos. Es un escenario condicionado, no una observación ni
  una previsión segura.
- **Asociación no causal:** coincidencia temporal entre una actuación y un cambio en los aforos, sin un grupo de
  control válido.

Dos bandas distintas acompañan a las cifras simuladas:
- la **banda de parámetros p10-p90** describe la población de combinaciones de parámetros compatibles con los
  aforos de 2025 para un día típico. No es una probabilidad de lo que pasará ni un intervalo predictivo;
- el **intervalo predictivo del 80 %** le suma la variabilidad de un día a otro y el error de observación, y su
  cobertura se mide en días no usados para calibrar (apartado 2.5).

Cada número lleva su fuente. La procedencia de los {{n_h + n_o}} ficheros oficiales usados está en
`salidas/tablas/procedencia_datos.csv`, y las fuentes documentales, en `datos/fuentes_documentales.csv`. Los
parámetros que usa el modelo en cada cuello, con su rango y su fuente, están en
`salidas/tablas/parametros_usados_caso1.csv` y `_caso2.csv` (los valores por defecto, en
`datos/parametros_modelo.csv`). Los datos que faltan, cómo se suplen y en qué estado está su petición, en
`datos/matriz_lagunas.csv`, con la petición preparada para el Cabildo en `docs/solicitud_datos_cabildo.md`. El método
completo está en `docs/METODOLOGIA.md`, y los diez criterios de calidad del estudio, cómo se comprueban y con qué
resultado, en `docs/VALIDACION_Y_CALIDAD.md`.

## Contraste de los originales con el portal

La madrugada del 17-10-2026 (hora canaria; `consultado_utc` en la evidencia) se volvieron a consultar por descarga directa, fuera de `main.R`, los **37 recursos oficiales** (8 CSV de IMD, 5 recursos auxiliares y 24 TXT horarios). Las 37 huellas SHA-256 coinciden con las registradas. Además, se cotejaron las **{{es(N_REG)}} filas** de los extractos horarios con los mismos campos de los TXT actuales, respetando las estaciones seleccionadas en los metadatos de cada mes; todas coinciden. Evidencia y herramienta reproducible: `docs/contraste_fuentes/contraste_37_recursos_oficiales.csv` y `herramientas/comprobaciones/contrastar_fuentes.py`.

## La respuesta en una tabla

¿Qué solución parece más eficaz, en qué tramo, en qué horario, durante cuánto tiempo y bajo qué condiciones?
Indicador: **reducción de los vehículos·hora de demora de un día laborable frente a no actuar** (simulado;
mediana y banda de parámetros p10-p90 de las combinaciones calibradas).

| | Mañana hacia Santa Cruz | Tarde hacia el Norte |
|---|---|---|
| **Dónde** (observado) | Los Rodeos-Guamasa (Ermita Cruz Chica, 2 carriles). A las 7 h se suma un segundo cuello en La Laguna | Bomberos La Laguna, justo antes de pasar de 3 a 2 carriles hacia Los Rodeos |
| **Cuándo** (observado) | De 6 a 9 h; {{es(HC(HC25M, 'dias_con_cola'))}} de {{es(HC(HC25M, 'dias'))}} días laborables de 2025 con cola entre las 3 y las 13 h. Igual en 2026 | De 13 a 18 h; {{es(HC(HC25T, 'dias_con_cola'))}} de {{es(HC(HC25T, 'dias'))}} días laborables de 2025, con cola entre las 11 y las 24 h. Igual en 2026 |
| **Reducción el primer año, por mediana** (simulado) | {{lista('m')}} | {{lista('t')}} |
| **¿Cuál reduce más?** Tercer carril frente a regulación + escalonamiento, combinación a combinación (simulado) | Diferencia de {{DIFR('m')}}; {{LECT('m')}} | Diferencia de {{DIFR('t')}}; {{LECT('t')}} |
| **Cuánto dura** (simulado; a 10 años, con la demanda inducida) | Tercer carril: {{pct(FA('m', 'tercer_carril', 'mediana_1er_anio'))}} el 1er año → {{FR10('m', 'tercer_carril')}}. Regulación + escalonamiento: {{pct(FA('m', 'paquete_gestion', 'mediana_1er_anio'))}} → {{FR10('m', 'paquete_gestion')}} | Regulación + escalonamiento: {{pct(FA('t', 'paquete_gestion', 'mediana_1er_anio'))}} → {{FR10('t', 'paquete_gestion')}}. Tercer carril hipotético: {{pct(FA('t', 'tercer_carril', 'mediana_1er_anio'))}} → {{FR10('t', 'tercer_carril')}} |
| **Con qué confianza** | Tercer carril, {{CONF('m', 'tercer_carril')}}; regulación de accesos y paquete de gestión, {{CONF('m', 'ramp_metering')}}; escalonamiento solo, {{CONF('m', 'escalonamiento')}} | Tercer carril hipotético, {{CONF('t', 'tercer_carril')}}; gestión, {{CONF('t', 'paquete_gestion')}}; escalonamiento solo, {{CONF('t', 'escalonamiento')}} |
| **Coste y plazo** (documental) | Tercer carril: 58,2 M€, contrato de 2-10-2026 con 35 meses de plazo. Regulación de accesos: 1,8-4 M€, sin fecha. Escalonamiento: sin coste de obra, en marcha en la ULL | Tercer carril: no proyectado. Gestión: la misma que por la mañana |
| **De qué depende** (estimado) | De la capacidad libre del tramo de La Laguna, que a las 7 h es de {{HR(7)}}. {{RANGO1_TABLA}} | De la caída de capacidad, que los aforos horarios no permiten medir, y de la capacidad libre de La Matanza: a las 15 h, {{HMR(15)}} |
| **Si la demanda crece un {{es(100 * g_c, 1)}} % al año** (simulado; horas de cola: media y p10-p90) | Sin actuar, la cola pasaría de {{es(EV('m', g_c, 2025, 'horas_cola_sin_adaptacion'), 1)}} h al día (hoy, en el modelo) a {{EVR('m', g_c, 2035)}} h en 2035. En 2030 el tercer carril rendiría {{A30R('m', g_c, 'tercer_carril_corto')}} | Sin actuar, de {{es(EV('t', g_c, 2025, 'horas_cola_sin_adaptacion'), 1)}} a {{EVR('t', g_c, 2035)}} h al día en 2035. En 2030 la regulación + escalonamiento rendiría {{A30R('t', g_c, 'paquete_gestion_corto')}} |

**En pocas palabras** (escenarios del modelo, no certezas). Por la mañana, el tercer carril contratado y la gestión
de la demanda (regulación de accesos + escalonamiento) reducen en el modelo la demora un {{pct(FA('m', 'tercer_carril', 'mediana_1er_anio'))}} y un
{{pct(FA('m', 'paquete_gestion', 'mediana_1er_anio'))}} el primer año (medianas), con bandas anchas. Comparadas combinación a combinación, {{LECTF('m')}}.
{{'Por eso el estudio no elige entre los dos por el efecto simulado: los distinguen sobre todo el coste, el plazo y los riesgos.' if TIPO('m') in ('material', 'muestreo', 'depende') else 'Aun así, la diferencia depende de supuestos del modelo, y el coste, el plazo y los riesgos se valoran aparte.'}}
La gestión podría funcionar años antes y cuesta una fracción, pero su efecto descansa en parámetros tomados
de la literatura; el tercer carril está contratado y su efecto depende de cuánta capacidad libre quede en el tramo de
La Laguna, que solo se puede estimar de forma indirecta (con las estimaciones compatibles con las colas medidas,
{{RANGO1_TEXTO}}). Por la tarde no hay obra prevista y
solo la gestión puede actuar a corto plazo; un tercer carril hacia el Norte entre Los Rodeos y Guamasa (no
proyectado) daría {{FR('t', 'tercer_carril')}} en el modelo, limitado por La Matanza; frente a la gestión, {{LECTF('t')}}. Si
la demanda sigue creciendo, en el modelo las colas se alargan y todas las mejoras se erosionan.

## Abrir el panel sin instalar nada

Extrae el ZIP completo y abre `panel/index.html` en tu navegador. Los datos, el código gráfico y los estilos están incluidos en `panel/assets/`; los gráficos y tablas funcionan sin conexión.

Después de una nueva ejecución de R y de las pruebas, actualiza los documentos y los datos empaquetados del panel:

```bash
python3 herramientas/documentos/rellenar.py
python3 herramientas/panel/preparar_panel.py
```

## Cómo ejecutarlo

Instala R por separado (R 4.3.3 reproduce el entorno de la ejecución original). `renv::restore()` restaura los paquetes del proyecto y no instala el intérprete de R.

```r
# Una sola vez. Versiones con las que se generaron los resultados: renv.lock
install.packages("renv")
renv::activate()  # activa el entorno de este proyecto; si R reinicia, continúa con restore
renv::restore()   # restaura paquetes; instala R 4.3.3 por separado (ver entorno/versiones_paquetes.csv)
# Sin renv: install.packages(c("dplyr", "tidyr", "readr", "ggplot2", "scales", "ggrepel",
#                              "patchwork", "jsonlite", "digest", "testthat"))
```

```bash
# Desde la carpeta del proyecto:
Rscript main.R                                                    # análisis completo: unos {{es(minutos)}} minutos
TF5_N_SIM=2000 TF5_N_REJILLA=2000 TF5_N_PREV=200 Rscript main.R   # ejecución rápida (menos simulaciones)
Rscript tests/ejecutar_pruebas.R                                  # {{n_bloq}} bloques de pruebas, {{es(n_comp)}} comprobaciones
Rscript tests/comparar_ejecuciones.R tests/referencia salidas/tablas ../informe.csv --solo-referencia   # salida 1 si detecta diferencias (informe fuera de la carpeta: verificar_entrega.py exige que todo lo que haya dentro esté en el manifiesto)
```

En RStudio: abre la carpeta como proyecto (o haz `setwd()` en ella) y pulsa *Source* en `main.R`.

Al empezar, `main.R` fija la zona horaria (`Atlantic/Canary`), compara las versiones instaladas con
`entorno/versiones_paquetes.csv` y lo anota en `salidas/tablas/entorno_versiones.csv`. Con otras versiones el
análisis corre igual, pero lo avisa. Todos los avisos de la ejecución se guardan en `salidas/registro_avisos.txt`
({{n_avisos}} en la ejecución entregada) y las opciones usadas (simulaciones, semillas y zona horaria), en
`salidas/configuracion_ejecucion.csv`.

**No hace falta Internet:** todos los datos están en `datos/` con la huella SHA-256 que se registró al
descargarlos. La huella prueba que la copia no ha cambiado desde la descarga (integridad), no que el origen sea
auténtico, y la autenticidad no se puede probar desde dentro del proyecto. Lo que hay son dos contrastes: la tabla
de procedencia compara el tamaño y la fecha de modificación de cada fichero con los de una instantánea del catálogo
del portal guardada el 16-10-2026 (`datos/oficial/catalogo_portal_2026-10-16.json`), y una muestra de recursos se
contrastó ese día con el catálogo nacional datos.gob.es (`contraste_publicacion_original.csv`). Las huellas y las
sumas de control de los TXT originales las calculó al descargarlos un script del navegador que no se conserva; queda
su registro (`datos/horarios/meta_AAAA-MM.json`). Dos opciones del principio de `main.R` permiten repetir el
contraste contra el portal:

- `DESCARGAR_HORARIOS <- TRUE`: vuelve a bajar los 24 ficheros horarios oficiales (unos 230 MB) y comprueba que su
  SHA-256 es el registrado. Para añadir un mes nuevo, agrega su enlace a `datos/fuentes_horarias.csv`.
- `CONTRASTAR_EN_LINEA <- TRUE`: contrasta además la IMD con el portal y guarda una instantánea nueva del
  catálogo, que pasa a usar la tabla de procedencia.

En la ejecución entregada no se volvió a descargar nada.

## 1. Qué sabemos: datos observados

### Aforos anuales

La estación más cargada en 2025 es {{EV_MAX['etiqueta']}} ({{es(float(EV_MAX['imd_2025']))}} veh/día). Entre 2019 y 2025 el tráfico del
corredor La Laguna-La Orotava (siete estaciones) apenas cambia (de {{spct(float(CORR_MIN['var_2019_2025']), 1)}} en {{CORR_MIN['etiqueta']}} a {{spct(float(CORR_MAX['var_2019_2025']), 1)}} en {{CORR_MAX['etiqueta']}}),
mientras la población de Tenerife crece un {{es(100 * pob_g, 2)}} % anual entre {{pob_a['anio']}} y {{pob_b['anio']}} (de {{es(float(pob_a['poblacion']))}} a {{es(float(pob_b['poblacion']))}}
habitantes, INE). En un tramo saturado el aforo mide lo que cabe, no lo que se querría circular. Por
carril, el tramo más cargado es Los Rodeos-Guamasa (Ermita Cruz Chica, 2 carriles): {{es(KC('descendente'))}} veh/día/carril
hacia Santa Cruz y {{es(KC('ascendente'))}} hacia el Norte. Su «k crítico» (parte del tráfico diario que llenaría la
capacidad en una hora) es del {{pct(KG(103, 'descendente', 'k_crit_central_aforados'), 1)}} y el {{pct(KG(103, 'ascendente', 'k_crit_central_aforados'), 1)}}, por debajo de la cuota habitual de la hora punta: se
satura casi todos los días laborables.

### Procedencia y calidad de los aforos horarios

- **Procedencia** (`procedencia_datos.csv`, una fila por recurso). Cada fila recoge el organismo, el conjunto de
  datos, la URL, el identificador, la licencia, la fecha de modificación en origen, la de descarga, el tamaño, el
  SHA-256 del original y de la copia, la cobertura, los filtros y las unidades. De los {{n_h + n_o}} ficheros
  descargados:
  - {{n_int}} copias están íntegras (mismo SHA-256 que al descargarlas);
  - {{n_coinc}} coinciden en tamaño y fecha con el recurso de la instantánea del catálogo del 16-10-2026;
  - en {{n_tot}} de 24 extractos horarios, los totales por estación y sentido son las sumas de control que se
    registraron al descargar el TXT original;
  - {{n_cpo}} de {{len(CPO)}} recursos de 2025 (los 12 TXT y su diccionario) coinciden en URL, identificador, nombre y licencia con
    el catálogo nacional datos.gob.es, consultado el 16-10-2026 (`contraste_publicacion_original.csv`).

  La correspondencia entre los campos de los ficheros oficiales y los del proyecto, con la definición de cada uno
  en el diccionario oficial, está en `correspondencia_de_campos.csv`. Quedan {{n_f}} recursos publicados sin usar,
  registrados como huecos: diciembre de 2024 y los diccionarios de datos de 2024 y 2026 (los datos de esos años se
  leen con el de 2025; la cabecera de los 24 TXT es la misma).
- **Registros:** {{es(N_REG)}} registros horarios por carril en {{len(T('horarios_procedencia'))}} meses. Se validan con 9 reglas (H1-H9,
  `validacion_horarios.csv`), y la IMD se contrasta valor a valor con las copias locales de los CSV oficiales:
  {{es(int(CONTR_N.replace('.', '')))}} valores, {{es(int(CONTR_DIF.replace('.', '')))}} diferencias.
- **Serie depurada con banderas** (`horarios_corredor_con_banderas.csv.gz`). Tiene una fila por estación, sentido,
  día y hora, y los extractos originales no se tocan. Las banderas marcan:
  - laborable, hora completa, velocidad utilizable, duplicado, rangos negativos, caudal implausible, agosto,
    cambio de hora y día válido;
  - el estado de la hora (observada, imputada o excluida) y el motivo de la exclusión.

  **No se imputa nada.** Las horas incompletas se excluyen: la tasa de imputación es del 0 % en todas las
  estaciones, meses y horas (`cobertura_e_imputacion_por_estacion_mes_hora.csv`, con la cobertura de cada celda).
- **Sensibilidad a la depuración** (`sensibilidad_depuracion.csv`). Se probó a quitar el filtro del tráfico diario,
  hacerlo más estricto, incluir agosto e imputar con dos métodos (proporcional y mediana de la misma hora y mes) las
  horas a las que les falta un carril. En los dos cuellos, la media de horas de cola cambia como mucho
  {{es(dep_dh, 2)}} h y la descarga mediana {{es(dep_dd, 1)}} veh/h. Las variantes de imputación no cambian nada en los cuellos,
  porque allí no hay horas así.
- **Días atípicos** (`dias_atipicos.csv`, `dias_atipicos_resumen.csv`). Cada día laborable de cada estación y
  sentido tiene su estado (usado o excluido) y su motivo. Se excluyen agosto, los días incompletos (avería o corte
  del aforador) y los de tráfico por debajo del 85 % de la mediana del mes; se marcan, y se prueba el análisis sin
  ellos, los puentes, la Navidad, la Semana Santa y los días con la punta anómala (más de tres desviaciones
  robustas por debajo de la mediana del mes: posible incidente u obra). En Ermita Cruz Chica hacia Santa Cruz quedan
  {{DAN('Ermita Cruz Chica', 'descendente', 'excluido')}} días excluidos y {{DAN('Ermita Cruz Chica', 'descendente', 'usado')}} marcas; en Bomberos La Laguna hacia el Norte, {{DAN('Bomberos La Laguna', 'ascendente', 'excluido')}} y {{DAN('Bomberos La Laguna', 'ascendente', 'usado')}}. Sin los días
  marcados, la media de horas de cola de los cuellos cambia como mucho {{es(ssa_dh, 2)}} h y la descarga mediana {{es(ssa_dd, 1)}} veh/h
  (`sensibilidad_sin_dias_atipicos.csv`). En los cambios de hora de marzo falta la marca de la 1 h y la de las 2 h sale
  duplicada ({{DUP[0]}} y {{DUP[1]}} registros); son domingos y no afectan a los días laborables. El 27 de enero de 2026 el fichero
  oficial trae una sola hora. Entran en el análisis {{es(N_DIAS_VAL)}} días laborables válidos, sumando estaciones y sentidos.
  Incidentes, obras y lluvia no están vinculados a los días (apartado 7).
- **Cobertura** (`cobertura_y_calidad.csv`, `cobertura_por_hora.csv`). En el conjunto de los 24 meses, todas las
  estaciones superan el 95 % de horas completas salvo **Padre Anchieta**, la más cargada, con un {{pct(COB_PA, 1)}} de horas
  completas y solo un {{es(100 * min(VEL_PA('ascendente'), VEL_PA('descendente')))}}-{{es(100 * max(VEL_PA('ascendente'), VEL_PA('descendente')))}} % con velocidades utilizables (rangos negativos o ausentes). Hospital Residencia no
  tiene registros en septiembre de 2026. En La Matanza el {{pct(BNM('ascendente'))}} (hacia el Norte) y el {{pct(BNM('descendente'))}} (hacia Santa Cruz) del
  tráfico va a menos de 80 km/h también de madrugada, así que el indicador de velocidad no detecta su cola.
- **Hora congestionada:** al menos el 60 % de los vehículos pasa a menos de 80 km/h, y 30 puntos más que de
  madrugada en la misma estación. Con umbrales de 50 % y +20 o de 70 % y +40, el diagnóstico de los dos cuellos
  principales apenas cambia. El segundo cuello de La Laguna hacia Santa Cruz sí depende del umbral: con el más
  estricto, su mediana pasa a 0 h (`sensibilidad_umbral_congestion.csv`).

### Dónde y cuándo hay cola (días laborables de 2025)

| Estación y sentido | Horas de cola al día (mediana; p25-p75) | Días sin cola | Empieza |
|---|---|---|---|
| Ermita Cruz Chica → Santa Cruz | {{es(CONG(103, 'descendente', 'horas_mediana'))}} ({{es(CONG(103, 'descendente', 'horas_p25'))}}-{{es(CONG(103, 'descendente', 'horas_p75'))}}) | {{es(CONG(103, 'descendente', 'dias_sin_congestion'))}} de {{es(CONG(103, 'descendente', 'dias'))}} | {{es(CONG(103, 'descendente', 'hora_inicio_tipica'))}} h |
| Bomberos La Laguna → Santa Cruz | {{es(CONG(99, 'descendente', 'horas_mediana'))}} ({{es(CONG(99, 'descendente', 'horas_p25'))}}-{{es(CONG(99, 'descendente', 'horas_p75'))}}) | {{es(CONG(99, 'descendente', 'dias_sin_congestion'))}} de {{es(CONG(99, 'descendente', 'dias'))}} | {{es(CONG(99, 'descendente', 'hora_inicio_tipica'))}} h |
| Campus Guajara → Santa Cruz | {{es(CONG(93, 'descendente', 'horas_mediana'))}} ({{es(CONG(93, 'descendente', 'horas_p25'))}}-{{es(CONG(93, 'descendente', 'horas_p75'))}}) | {{es(CONG(93, 'descendente', 'dias_sin_congestion'))}} de {{es(CONG(93, 'descendente', 'dias'))}} | {{es(CONG(93, 'descendente', 'hora_inicio_tipica'))}} h |
| Bomberos La Laguna → Norte | {{es(CONG(99, 'ascendente', 'horas_mediana'))}} ({{es(CONG(99, 'ascendente', 'horas_p25'))}}-{{es(CONG(99, 'ascendente', 'horas_p75'))}}) | **{{es(CONG(99, 'ascendente', 'dias_sin_congestion'))}} de {{es(CONG(99, 'ascendente', 'dias'))}}** | {{es(CONG(99, 'ascendente', 'hora_inicio_tipica'))}} h |
| Campus Guajara → Norte | {{es(CONG(93, 'ascendente', 'horas_mediana'))}} ({{es(CONG(93, 'ascendente', 'horas_p25'))}}-{{es(CONG(93, 'ascendente', 'horas_p75'))}}) | {{es(CONG(93, 'ascendente', 'dias_sin_congestion'))}} de {{es(CONG(93, 'ascendente', 'dias'))}} | {{es(CONG(93, 'ascendente', 'hora_inicio_tipica'))}} h |
| Ermita Cruz Chica → Norte | {{es(CONG(103, 'ascendente', 'horas_mediana'))}} ({{es(CONG(103, 'ascendente', 'horas_p25'))}}-{{es(CONG(103, 'ascendente', 'horas_p75'))}}) | {{es(CONG(103, 'ascendente', 'dias_sin_congestion'))}} de {{es(CONG(103, 'ascendente', 'dias'))}} | {{es(CONG(103, 'ascendente', 'hora_inicio_tipica'))}} h |

**Horario de la cola** (`horario_cola.csv`; primera hora congestionada y fin de la última, en la ventana de cada cuello: de 3 a 13 h por la mañana y de 11 a 24 h por la tarde; la tabla de arriba mira el día entero):

| Cuello | 2025 | 2026 (enero-septiembre, sin agosto) |
|---|---|---|
| Mañana hacia Santa Cruz (Ermita Cruz Chica) | de {{hm(HC(HC25M, 'inicio_mediana'))}} a {{hm(HC(HC25M, 'fin_mediana'))}} (fin p10-p90: {{hm(HC(HC25M, 'fin_p10'))}}-{{hm(HC(HC25M, 'fin_p90'))}}); {{es(HC(HC25M, 'dias_con_cola'))}} de {{es(HC(HC25M, 'dias'))}} días | de {{hm(HC(HC26M, 'inicio_mediana'))}} a {{hm(HC(HC26M, 'fin_mediana'))}} ({{hm(HC(HC26M, 'fin_p10'))}}-{{hm(HC(HC26M, 'fin_p90'))}}); {{es(HC(HC26M, 'dias_con_cola'))}} de {{es(HC(HC26M, 'dias'))}} días |
| Tarde hacia el Norte (Bomberos La Laguna) | de {{hm(HC(HC25T, 'inicio_mediana'))}} a {{hm(HC(HC25T, 'fin_mediana'))}} ({{hm(HC(HC25T, 'fin_p10'))}}-{{hm(HC(HC25T, 'fin_p90'))}}); {{es(HC(HC25T, 'dias_con_cola'))}} de {{es(HC(HC25T, 'dias'))}} días | de {{hm(HC(HC26T, 'inicio_mediana'))}} a {{hm(HC(HC26T, 'fin_mediana'))}} ({{hm(HC(HC26T, 'fin_p10'))}}-{{hm(HC(HC26T, 'fin_p90'))}}); {{es(HC(HC26T, 'dias_con_cola'))}} de {{es(HC(HC26T, 'dias'))}} días |

**Caudal en las horas con cola** (observado; `caudal_descarga_cuellos.csv`). Por los 2 carriles de Los Rodeos
hacia Santa Cruz pasan {{es(CD('m', 'mediana'))}} veh/h de mediana en las horas con cola de 3 a 13 h
(p10-p90: {{es(CD('m', 'p10'))}}-{{es(CD('m', 'p90'))}}; {{es(CD('m', 'horas'))}} horas). Hacia el Norte, en las horas con
cola en Bomberos La Laguna de 11 a 24 h, pasan {{es(CD('t', 'mediana'))}} ({{es(CD('t', 'p10'))}}-{{es(CD('t', 'p90'))}};
{{es(CD('t', 'horas'))}} horas).

Este caudal **no es la capacidad**: es lo que pasó en esas horas, y mezcla tres tipos de hora:
- la hora en que empieza la cola, con caudal alto: {{es(DG('m', 'Por hora del día', '06 h', 'aforo 2025', 'mediana'))}} veh/h a las 6 h;
- las horas centrales: {{es(DG('m', 'Por hora del día', '07 h', 'aforo 2025', 'mediana'))}} a las 7 h;
- las de disipación: {{es(DG('m', 'Por hora del día', '08 h', 'aforo 2025', 'mediana'))}} a las 8 h, y menos aún cuando también hay cola en La Laguna
  (apartado 2.5).

### ¿Ha cambiado algo ya? (asociaciones no causales y comparación entre años)

- **Horarios escalonados de la Universidad de La Laguna** (desde el 9-9-2025; 13 grados y unos 2.700
  estudiantes según la ULL). *Asociación no causal.* Se comparan los meses lectivos (octubre, noviembre y febrero a
  mayo) del curso 2025-26 con los del 2024-25, hacia Santa Cruz, de 7 a 9 h:
  - Campus Guajara: {{es(ULL(93, 'v', 'dif_lectivo'))}} veh/día (IC 95 %: {{es(ULL(93, 'v', 'ic_lectivo_inf'))}} a {{es(ULL(93, 'v', 'ic_lectivo_sup'))}});
  - Ermita Cruz Chica: {{es(ULL(103, 'v', 'dif_lectivo'))}} ({{es(ULL(103, 'v', 'ic_lectivo_inf'))}} a {{es(ULL(103, 'v', 'ic_lectivo_sup'))}});
  - la cola de Los Rodeos pasa de {{es(ULL(103, 'cola', 'lectivo_antes'), 1)}} a {{es(ULL(103, 'cola', 'lectivo_despues'), 1)}} h/día.

  **No se ve un cambio en los cuellos.** La bajada de octubre y noviembre de 2025 junto al campus ({{es(ULL_ON(93, 'dif'))}} veh/día) no
  se mantiene de febrero a mayo. Las diferencias en diferencias, con julio (o junio y julio) como control, no son
  válidas: esos meses de 2026 ya tienen la pasarela del Padre Anchieta, y no hay registros de obras ni de incidencias
  incorporados para controlarlas (`ull_diferencias_en_diferencias.csv`).
- **Después de abrir la pasarela del Padre Anchieta** (abierta el 18-5-2026; los 11 pasos de peatones de la
  glorieta se cerraron dos días después). *Asociación no causal.* La cola de la mañana en Bomberos La Laguna hacia
  Santa Cruz fue menor que en el mismo mes de 2025:
  - junio: {{es(DIM('2026-06', 'valor'), 2)}} h/día ({{es(DIM('2026-06', 'valor_antes'), 2)}} en 2025);
  - julio: {{es(DIM('2026-07', 'valor'), 2)}} ({{es(DIM('2026-07', 'valor_antes'), 2)}});
  - septiembre: {{es(DIM('2026-09', 'valor'), 2)}} ({{es(DIM('2026-09', 'valor_antes'), 2)}}).

  En Los Rodeos no cambia. Son tres meses, dos de verano, sin un grupo de control y sin registros de obras ni de
  incidencias incorporados: es una coincidencia temporal que hay que confirmar, no un efecto demostrado
  (`diferencias_interanuales_por_mes.csv`, g16). Como comparación de control, en noviembre de 2025, antes de la
  pasarela, la cola ya bajó tanto: de {{es(DIM('2025-11', 'valor_antes'), 2)}} a {{es(DIM('2025-11', 'valor'), 2)}} h/día (IC 95 % de la diferencia: {{es(DIM('2025-11', 'ic_inf'), 2)}} a {{es(DIM('2025-11', 'ic_sup'), 2)}}).
  Bajadas así aparecen también sin pasarela.
- **2026 frente a 2025** (enero-septiembre, sin agosto; observado). En los dos cuellos principales, las horas de
  cola no cambian de forma significativa:
  - Ermita Cruz Chica hacia Santa Cruz: {{C26TXT(103, 'descendente')}} h/día, {{PV(C26(103, 'descendente', 'p_valor_cong'))}};
  - Bomberos La Laguna hacia el Norte: {{C26TXT(99, 'ascendente')}}, {{PV(C26(99, 'ascendente', 'p_valor_cong'))}}.

  En Campus Guajara hacia Santa Cruz, parte del segundo cuello de La Laguna, suben ({{C26TXT(93, 'descendente')}} h/día, {{PV(C26(93, 'descendente', 'p_valor_cong'))}}).
  Se descartan las comparaciones en las que el reparto del tráfico entre carriles cambia más de 4 puntos (aforador
  alterado).

## 2. Qué estimamos

### 2.1 Carriles y capacidad de cada tramo (estimado)

Los carriles de cada estación y sentido salen de dos fuentes oficiales con fechas distintas:
- el catálogo de carriles de los aforos del Cabildo (julio de 2026);
- el inventario del Plan Territorial Especial de Ordenación del Sistema Viario del Área Metropolitana de Tenerife
  (PTEOSVAM, aprobado en 2006).

Coinciden en {{n_conf}} de 14 estación-sentidos. Los otros {{n_pend}} quedan **pendientes de confirmación**
(`datos/geometria_tramos.csv`, `geometria_y_capacidad.csv`): Campus Guajara en los dos sentidos (4 aforados frente
a 3 en el inventario), Padre Anchieta hacia Santa Cruz (3 frente a 2), Bomberos La Laguna hacia Santa Cruz (4
frente a 3) y La Orotava en los dos sentidos (3 frente a 2). El inventario advierte de que «en los enlaces ... se
suele disponer un carril adicional»: la diferencia puede ser un carril de enlace contado como carril, o una obra
posterior. Queda preparada una petición al Cabildo para confirmarlo (`docs/solicitud_datos_cabildo.md`,
punto 6), que no se ha enviado.

Cada capacidad del modelo está ligada a una configuración, un sentido, una fecha y una fuente
(`geometria_y_capacidad.csv`), y `uso_de_la_geometria.csv` recoge los {{len(UG)}} cálculos que dependen del número de
carriles, con su estado y el supuesto que los sustituye cuando no están confirmados: {{'todos tienen fuente o supuesto explícito' if all(x['tiene_procedencia_o_supuesto'] == 'TRUE' for x in UG) else 'ALGUNO NO TIENE FUENTE NI SUPUESTO'}}. La
capacidad por carril es la misma, {{es(CC('minimo'))}}-{{es(CC('maximo'))}} veh/h (moda {{es(CC('central'))}}), en el modelo de cola y en el «k crítico». Las
hipótesis geométricas alternativas se ejecutan como cambios de capacidad:
- **k crítico con los carriles del inventario** (`k_critico_geometria_alternativa.csv`). Por ejemplo, en Padre
  Anchieta hacia Santa Cruz, {{pct(KG(97, 'descendente', 'k_crit_central_inventario'), 1)}} con {{es(KG(97, 'descendente', 'carriles_inventario_2006'))}} carriles
  frente a {{pct(KG(97, 'descendente', 'k_crit_central_aforados'), 1)}} con {{es(KG(97, 'descendente', 'carriles_aforados'))}}. Con menos carriles, el tramo se satura con menos tráfico.
- **Capacidad libre del tramo siguiente con los carriles del inventario** en Campus Guajara y Bomberos La Laguna
  (apartado 2.2).
- **Tramo siguiente sin capacidad libre** (por ejemplo, si el paso por Padre Anchieta tuviera en la práctica 2
  carriles efectivos): ni el tercer carril ni la regulación de accesos reducirían la demora.

### 2.2 Capacidad libre del tramo siguiente y balance entre estaciones (estimado)

La **capacidad libre** (holgura) de una hora es `(C_abajo − F_abajo) / F_cuello`:
- `C_abajo` es la capacidad de la estación de abajo, que se estima como el percentil 99 de su caudal de 2025;
- `F_abajo` y `F_cuello` son los caudales de esa hora en la estación de abajo y en el cuello.

Las entradas y salidas de los ramales entre las dos estaciones se cancelan en la cuenta: no hace falta medirlas,
pero tampoco se pueden ver. Y como `C_abajo` sale de los caudales de la misma punta, la estimación es circular en
parte. Por eso se publica con rango y con variantes: {{NUMW[len(VAR1)]}} por la mañana y {{NUMW[len(VAR2)]}} por la tarde.

| Hora | Mañana: La Laguna (Bomberos y Campus Guajara), mediana (p10 a p90) | Hora | Tarde: La Matanza (2 carriles) |
|---|---|---|---|
| 6 h | {{HR(6)}} | 14 h | {{HMR(14)}} |
| 7 h | **{{HR(7)}}** | 15 h | **{{HMR(15)}}** |
| 8 h | {{HR(8)}} | 16 h | {{HMR(16)}} |

**Balance entre estaciones** (`balance_por_tramos.csv`; días con las 24 horas completas en las dos). Es descriptivo:
comprueba si las entradas netas por los ramales son estables, pero no entra en el modelo, que solo usa la capacidad
libre. En ningún tramo hay caudales negativos. Entre Ermita Cruz Chica y Bomberos La Laguna hacia Santa Cruz entran por los
ramales {{es(BA('Ermita Cruz Chica -> Bomberos La Laguna', 'neto_dia_mediana'))}} veh/día netos (p10-p90:
{{es(BA('Ermita Cruz Chica -> Bomberos La Laguna', 'neto_dia_p10'))}}-{{es(BA('Ermita Cruz Chica -> Bomberos La Laguna', 'neto_dia_p90'))}}).
Es un balance estable de un día a otro (coeficiente de variación {{es(BA('Ermita Cruz Chica -> Bomberos La Laguna', 'cv_neto_dia'), 2)}}),
casi igual en 2025 ({{es(BA('Ermita Cruz Chica -> Bomberos La Laguna', 'neto_dia_2025'))}}) y en 2026 ({{es(BA('Ermita Cruz Chica -> Bomberos La Laguna', 'neto_dia_2026'))}}). En cambio,
solo {{sum(1 for x in T('balance_por_tramos') if x['estable'] == 'TRUE')}} de los {{len(T('balance_por_tramos'))}} pares de estaciones dan un balance estable ({{len(T('balance_por_tramos')) - 1}} pares consecutivos y
Ermita Cruz Chica → Campus Guajara hacia Santa Cruz, que salta Bomberos La Laguna y Padre Anchieta); los que tocan
Padre Anchieta están entre los más inestables, porque su aforador falla buena parte del tiempo.
{% _chk_bal = 1 / int(sum(1 for x in T('balance_por_tramos') if x['tramo'] == 'Ermita Cruz Chica -> Campus Guajara') == 1) %}

**Sensibilidad de la capacidad libre** (`sensibilidad_holgura_caso1.csv` y `sensibilidad_holgura_resultados_caso1.csv`;
{{es(N_SENS_HOLG)}} combinaciones calibradas). La tabla da la capacidad libre a las 7 h, el tercer carril el primer año y qué parte
de las combinaciones da con esa variante una cola de hoy dentro del rango medido en 2025:

| Variante (mañana) | Capacidad libre a las 7 h (mediana) | Tercer carril, 1er año | Cola de hoy en el rango medido |
|---|---|---|---|
{{'\n'.join(f"| {x} | {pct(SHH1(x, 7, 'holgura_mediana'), 1)} | {pct(SH1(x, 'tercer_carril_corto', 'mediana'))} ({pr(SH1(x, 'tercer_carril_corto', 'p10'), SH1(x, 'tercer_carril_corto', 'p90'))}) | {pct(SH1(x, 'tercer_carril_corto', 'parte_cola_hoy_en_rango_medido'))} |" for x in VAR1)}}

Una capacidad libre negativa significa que esa hora el tramo de abajo pasó más que la capacidad supuesta.
{{('Con la propagación de la cola en la especificación de la mañana (apartado 2.3), una variante con menos capacidad abajo alarga también la cola de hoy; si con ella menos de la mitad de las combinaciones da una cola de hoy dentro del rango medido, los aforos de 2025 no son compatibles con esa variante' + (': es el caso de ' + ' y de '.join('«' + x[0].lower() + x[1:] + '»' for x in INCOMP1) if INCOMP1 else '') + '. ') if ELEG('m')['propagacion'] == 'TRUE' else 'Sin propagación de la cola en la especificación de la mañana, la capacidad libre negativa cuenta como 0 y solo limita lo que añaden el tercer carril y la regulación. '}}Es el supuesto que más pesa en el resultado del
tercer carril y de la regulación de accesos de la mañana. Con el tercer carril, la cola que queda la marca el tramo
siguiente: es un cuello que se desplaza, no una cola que desaparece (apartado 2.3, cuellos en serie). Hacia el Norte,
{{RANGO2_TEXTO}} (`sensibilidad_holgura_resultados_caso2.csv`). La
Matanza no tiene velocidad utilizable, así que allí no se puede probar la variante de cuello desplazado.

### 2.3 El modelo (simulado)

**Qué hace.** Simula minuto a minuto un día laborable completo en cada cuello:

- **Demanda híbrida.** Fuera de la ventana de la punta (6-10 h por la mañana, 13-18 h por la tarde), la
  demanda es el caudal aforado hora a hora. Dentro, donde el caudal medido está topado por la capacidad, se
  reparten los mismos vehículos con una forma de punta cuya hora y anchura se calibran. Conserva exactamente los
  vehículos del día ({{es(VDIA('descendente'))}} hacia Santa Cruz y {{es(VDIA('ascendente'))}} hacia el Norte).
- **Cola puntual** (Vickrey, 1969) con **caída de capacidad** cuando hay cola (Cassidy y Bertini, 1999), y
  esperas por cohortes con curvas acumuladas (Newell, 1993).
- **Especificación de la descarga, elegida por validación cruzada** (apartado 2.5). Se probaron 16 variantes:
  propagación de la cola del tramo siguiente (si no tiene capacidad libre, frena también la descarga actual),
  descarga que depende de la hora (medida en 2025 y aplicada solo en las horas con datos suficientes), mezcla de
  pesados y descarga calibrada como parámetro o medida igual que en el aforo. Elegidas: por la mañana,
  **{{describir(ELEG('m'))}}**; por la tarde, **{{describir(ELEG('t'))}}**.{{PES_EMPATE}}
- **Restricción aguas abajo.** El tercer carril y la regulación de accesos no pueden pasar más de lo que admite el
  tramo siguiente hora a hora (`D = descarga × (1 + capacidad libre)`); si el tramo siguiente no tiene capacidad
  libre, no añaden nada. Además, un modelo de **dos cuellos en serie** (`simular_tandem()`) comprueba qué pasa con
  un almacenamiento finito entre los dos (1, 2 o 4 km supuestos), la cola remanente y el bloqueo de las entradas de
  los ramales (apartado 2.7).
- **Alternativas:**
  - tercer carril, limitado hora a hora por la capacidad libre estimada del tramo siguiente;
  - regulación de accesos, que evita la caída de capacidad, con el mismo límite;
  - escalonamiento horario;
  - tarificación de la punta;
  - regulación + escalonamiento.

  Por la tarde, el tercer carril es hipotético.
- **Demanda inducida** a 1, 5 y 10 años, igual para todas las alternativas que reducen la demora. Usa las
  elasticidades de Goodwin y SACTRA, más bajas según Cervero, y el reparto en el tiempo de Hymel, Small y Van
  Dender. La tarificación no la lleva, porque las reducciones observadas con peaje ya son netas.

### 2.4 Monte Carlo y calibración

- **Distribuciones** (`montecarlo_parametros.csv`). Cada parámetro tiene una distribución triangular (mínimo,
  moda, máximo) con su tipo y su fuente. Son independientes entre sí, con dos excepciones:
  - la elasticidad a 10 años nunca es menor que la del primer año;
  - la capacidad libre del tramo siguiente no es triangular: se muestrea un cuantil común a todas las horas (un día
    bueno o malo aguas abajo) de su distribución estimada hora a hora.
- **Semillas** (`montecarlo_semillas.csv`): una por cada paso aleatorio, y todas fijas.
- **Calibración por rechazo** (`montecarlo_filtros.csv`). Se simulan {{es(n_sim1)}} combinaciones por la mañana y
  {{es(n_sim2)}} por la tarde, y solo se quedan las que reproducen lo medido en 2025: la duración de la cola (contada
  como en el aforo), la hora de inicio y de fin, el caudal de descarga y una cola que se disuelve dentro del día. Se
  aceptan {{es(n_acep1)}} por la mañana ({{pct(n_acep1 / n_sim1, 1)}}) y {{es(n_acep2)}} por la tarde ({{pct(n_acep2 / n_sim2, 1)}}). La regla que más
  descarta por la mañana es «{{REG_MIN.lower()}}»: solo la cumple el {{pct(FI('m', REG_MIN, 'tasa'), 1)}} de las combinaciones.
- **Auditoría del Monte Carlo** (`docs/VALIDACION_Y_CALIDAD.md`, criterio 3):
  - con otras dos semillas, las medianas del tercer carril y de la regulación + escalonamiento cambian como mucho
    {{es(100 * max(max(SEMV(c, a, e, 'mediana') for a in SEM_LIST) - min(SEMV(c, a, e, 'mediana') for a in SEM_LIST) for c in 'mt' for e in ('tercer_carril_corto', 'paquete_gestion_corto')), 1)}} puntos (`montecarlo_otras_semillas.csv`);
  - con previas alternativas (uniformes en el mismo rango, o con la moda en un extremo para la demanda inducida, la
    eficacia de la regulación, la caída de capacidad y, donde la forma de la descarga los usa, los pesados),
    reponderando las combinaciones aceptadas, esas medianas cambian como mucho {{es(100 * prv_max_ok, 1)}} puntos con las previas cuyo
    tamaño efectivo es al menos el 10 % de las aceptadas{{(', y hasta ' + es(100 * prv_max_all, 1) + ' con las demás, que por su tamaño efectivo pequeño dan un resultado poco preciso') if prv_max_all > prv_max_ok + 0.0005 else ''}}
    (`montecarlo_previas_alternativas.csv`);
  - las correlaciones que crea la calibración entre parámetros (`montecarlo_correlaciones.csv`);
  - el error típico de la mediana por el muestreo va de {{es(100 * ee_min, 1)}} a {{es(100 * ee_max, 1)}} puntos (`estabilidad_percentiles.csv`).
- **Con y sin filtro** (`sensibilidad_calibracion_caso1.csv`). Sin calibrar ({{es(SC('m', RSC, 'tercer_carril_corto', 'n_validas'))}} combinaciones al azar que dan
  cola), el tercer carril de la mañana rendiría {{SCR('m', RSC, 'tercer_carril_corto')}} el primer año, frente a
  {{SCR('m', RP, 'tercer_carril_corto')}} con la calibración. Con las {{len(REGLAS_SC('m')) - 2}} reglas alternativas de calibración va del {{pct(min(SC('m', r, 'tercer_carril_corto', 'mediana') for r in REGLAS_SC('m') if r not in (RSC, RP)))}} al
  {{pct(max(SC('m', r, 'tercer_carril_corto', 'mediana') for r in REGLAS_SC('m') if r not in (RSC, RP)))}}. Los resultados describen la población calibrada, no cualquier combinación verosímil.{{REGLAS_FUERA_TXT}}

Lo que más estrecha la calibración es la hora y la anchura de la punta (`parametros_prior_posterior.csv`). Las
elasticidades y la eficacia de cada medida no las informan los aforos: vienen de la literatura.

### 2.5 Validación: calibración, validación cruzada en 2025 y prueba final en 2026

**Tres conjuntos de días.** 2025 calibra. Para elegir la especificación de la descarga, los días de 2025 se
reparten en dos mitades por semanas alternas: se calibra con una y se mide el error en la otra, y al revés
(validación cruzada; cada calibración usa solo sus días para todo lo que se ajusta). Enero-septiembre de 2026 (sin
agosto) no interviene en la calibración ni en la elección de la especificación: es la prueba final. La excepción es la línea
base de velocidad de madrugada, con la que se decide si una hora está congestionada, que se calcula con los 24 meses;
calculada solo con 2025, {{BN_TXT}}. Detalle en `docs/comprobacion_base_nocturna_2025.csv`.

**Elección de la descarga** (`eleccion_especificacion.csv`, `validacion_cruzada.csv`, g20). Una variante solo se
adopta si reduce al menos un 20 % el sesgo absoluto de la descarga del día fuera de muestra y no empeora más de un
10 % el error (RMSE) de ningún otro indicador; la regla se fijó antes de mirar 2026. Por la mañana hay {{n_adm('m')}}
variantes admisibles{{('; la elegida reduce el sesgo absoluto de la descarga del día en la validación cruzada de ' + es(float(ELEG('m')['sesgo_descarga_referencia'])) + ' a ' + es(float(ELEG('m')['sesgo_descarga'])) + ' veh/h') if not es_ref('m') else ' y se mantiene la referencia'}}. Por la tarde, {{n_adm('t')}}{{('; la elegida reduce el sesgo de ' + es(float(ELEG('t')['sesgo_descarga_referencia'])) + ' a ' + es(float(ELEG('t')['sesgo_descarga'])) + ' veh/h') if not es_ref('t') else ': se mantiene la referencia'}}.
En la prueba final de 2026, la descarga del día de la mañana pasa de un sesgo de
{{sg(P26X('m', REF('m'), IND_DIA, 'sesgo'))}} veh/h con la referencia a {{sg(P26X('m', ELEG('m'), IND_DIA, 'sesgo'))}} con la elegida, y el RMSE, de {{es(P26X('m', REF('m'), IND_DIA, 'rmse'))}} a
{{es(P26X('m', ELEG('m'), IND_DIA, 'rmse'))}}. {{COB_FRASE('m') if not es_ref('m') else ''}} Estas cifras de la elección salen de la rejilla de
especificaciones ({{es(N_REJ)}} combinaciones por forma; {{es(ACEP_REJ)}} aceptadas con la elegida calibrada con todo 2025); las de
la tabla siguiente, del Monte Carlo principal ({{es(n_sim1)}} combinaciones; {{es(n_acep1)}} aceptadas), así que difieren un
poco ({{sg(P26X('m', ELEG('m'), IND_DIA, 'sesgo'))}} frente a {{sg(VD('m', DIA_IGUAL, P26, 'sesgo'))}} veh/h de sesgo).

**Día a día en 2026** (`validacion_diaria.csv`; sesgo = mediana del modelo − media aforada; el intervalo predictivo del 80 % es el que
debe cubrir unos 8 de cada 10 días):

| Indicador | Sentido | 2025 (calibración): sesgo; RMSE | 2026 (prueba): sesgo; MAE; RMSE | 2026: dentro del intervalo predictivo |
|---|---|---|---|---|
{{'\n'.join(f"| {ind} | {'Mañana' if c == 'm' else 'Tarde'} | {sg(VD(c, ind, P25, 'sesgo'), d)}; {es(VD(c, ind, P25, 'rmse'), d)} | {sg(VD(c, ind, P26, 'sesgo'), d)}; {es(VD(c, ind, P26, 'mae'), d)}; {es(VD(c, ind, P26, 'rmse'), d)} | {pct(VD(c, ind, P26, 'cobertura_intervalo_predictivo'))} |" for c in 'mt' for ind, d in (('Horas de cola al día', 2), ('Inicio de la cola', 2), ('Fin de la cola', 2), (DIA_IGUAL, 0), (PLENA, 0)))}}

{{COB_TODOS}} Las métricas por hora de la punta, por día de la semana y por trimestre están en `validacion_diaria.csv` y
`validacion_diaria_por_hora.csv`, y el detalle, en `docs/VALIDACION_Y_CALIDAD.md` (criterio 1).

**Tabla resumida** (`validacion_modelo.csv`). Tiene **{{len(VAL)}} filas, {{len(VAL) // 2}} por sentido**: horas de cola, inicio, fin y
dos filas de la descarga. Esas dos miden el mismo fenómeno de dos formas (el parámetro de descarga y el caudal medido
igual que en el aforo) y no son dos contrastes independientes. En 2026
{{FUERA_TXT}}. La banda de parámetros es de un
día típico; para días concretos vale el intervalo predictivo. El error de esta tabla es la mediana del modelo menos la
mediana aforada; el sesgo de la tabla anterior se mide frente a la media de los días, así que pueden no coincidir.

| Indicador | Mañana: aforo 2025 / 2026 | Modelo, mediana (banda p10-p90) | Error 2026 | Tarde: aforo 2025 / 2026 | Modelo | Error 2026 |
|---|---|---|---|---|---|---|
| Horas de cola al día | {{es(VM('m', 'Horas de cola al día (mediana)', 'observado_2025'))}} / {{es(VM('m', 'Horas de cola al día (mediana)', 'observado_2026'))}} | {{es(VM('m', 'Horas de cola al día (mediana)', 'simulado_mediana'))}} ({{es(VM('m', 'Horas de cola al día (mediana)', 'simulado_p10'))}}-{{es(VM('m', 'Horas de cola al día (mediana)', 'simulado_p90'))}}) | {{sg(VM('m', 'Horas de cola al día (mediana)', 'error_mediana_2026'))}} h | {{es(VM('t', 'Horas de cola al día (mediana)', 'observado_2025'))}} / {{es(VM('t', 'Horas de cola al día (mediana)', 'observado_2026'))}} | {{es(VM('t', 'Horas de cola al día (mediana)', 'simulado_mediana'))}} ({{es(VM('t', 'Horas de cola al día (mediana)', 'simulado_p10'))}}-{{es(VM('t', 'Horas de cola al día (mediana)', 'simulado_p90'))}}) | {{sg(VM('t', 'Horas de cola al día (mediana)', 'error_mediana_2026'))}} h |
| Inicio | {{es(VM('m', 'Inicio de la cola (mediana)', 'observado_2025'))}} h / {{es(VM('m', 'Inicio de la cola (mediana)', 'observado_2026'))}} h | {{es(VM('m', 'Inicio de la cola (mediana)', 'simulado_mediana'))}} h ({{es(VM('m', 'Inicio de la cola (mediana)', 'simulado_p10'))}}-{{es(VM('m', 'Inicio de la cola (mediana)', 'simulado_p90'))}}) | {{sg(VM('m', 'Inicio de la cola (mediana)', 'error_mediana_2026'))}} h | {{es(VM('t', 'Inicio de la cola (mediana)', 'observado_2025'))}} h / {{es(VM('t', 'Inicio de la cola (mediana)', 'observado_2026'))}} h | {{es(VM('t', 'Inicio de la cola (mediana)', 'simulado_mediana'))}} h ({{es(VM('t', 'Inicio de la cola (mediana)', 'simulado_p10'))}}-{{es(VM('t', 'Inicio de la cola (mediana)', 'simulado_p90'))}}) | {{sg(VM('t', 'Inicio de la cola (mediana)', 'error_mediana_2026'))}} h |
| Fin | {{es(VM('m', 'Fin de la cola (mediana)', 'observado_2025'))}} h / {{es(VM('m', 'Fin de la cola (mediana)', 'observado_2026'))}} h | {{es(VM('m', 'Fin de la cola (mediana)', 'simulado_mediana'))}} h ({{es(VM('m', 'Fin de la cola (mediana)', 'simulado_p10'))}}-{{es(VM('m', 'Fin de la cola (mediana)', 'simulado_p90'))}}) | {{sg(VM('m', 'Fin de la cola (mediana)', 'error_mediana_2026'))}} h | {{es(VM('t', 'Fin de la cola (mediana)', 'observado_2025'))}} h / {{es(VM('t', 'Fin de la cola (mediana)', 'observado_2026'))}} h | {{es(VM('t', 'Fin de la cola (mediana)', 'simulado_mediana'))}} h ({{es(VM('t', 'Fin de la cola (mediana)', 'simulado_p10'))}}-{{es(VM('t', 'Fin de la cola (mediana)', 'simulado_p90'))}}) | {{sg(VM('t', 'Fin de la cola (mediana)', 'error_mediana_2026'))}} h |
| Descarga medida igual que el aforo (veh/h) | {{es(VM('m', IGUAL, 'observado_2025'))}} / {{ESD(VM('m', IGUAL, 'observado_2026'))}} | {{es(VM('m', IGUAL, 'simulado_mediana'))}} ({{es(VM('m', IGUAL, 'simulado_p10'))}}-{{es(VM('m', IGUAL, 'simulado_p90'))}}) | {{sg(VM('m', IGUAL, 'error_mediana_2026'))}} ({{spct(VM('m', IGUAL, 'error_relativo_2026'), 1)}}) | {{es(VM('t', IGUAL, 'observado_2025'))}} / {{ESD(VM('t', IGUAL, 'observado_2026'))}} | {{es(VM('t', IGUAL, 'simulado_mediana'))}} ({{es(VM('t', IGUAL, 'simulado_p10'))}}-{{es(VM('t', IGUAL, 'simulado_p90'))}}) | {{sg(VM('t', IGUAL, 'error_mediana_2026'))}} ({{spct(VM('t', IGUAL, 'error_relativo_2026'), 1)}}) |
| Parámetro de descarga (veh/h; no se mide igual que el aforo) | {{es(VM('m', DESC, 'observado_2025'))}} / {{ESD(VM('m', DESC, 'observado_2026'))}} | {{es(VM('m', DESC, 'simulado_mediana'))}} ({{es(VM('m', DESC, 'simulado_p10'))}}-{{es(VM('m', DESC, 'simulado_p90'))}}) | {{sg(VM('m', DESC, 'error_mediana_2026'))}} | {{es(VM('t', DESC, 'observado_2025'))}} / {{ESD(VM('t', DESC, 'observado_2026'))}} | {{es(VM('t', DESC, 'simulado_mediana'))}} ({{es(VM('t', DESC, 'simulado_p10'))}}-{{es(VM('t', DESC, 'simulado_p90'))}}) | {{sg(VM('t', DESC, 'error_mediana_2026'))}} |

**La descarga de la mañana** (`diagnostico_descarga.csv`). En el aforo, el caudal con cola cae a lo largo de la
mañana: {{es(DG('m', 'Por hora del día', '06 h', 'aforo 2025', 'mediana'))}}, {{es(DG('m', 'Por hora del día', '07 h', 'aforo 2025', 'mediana'))}} y {{es(DG('m', 'Por hora del día', '08 h', 'aforo 2025', 'mediana'))}} veh/h a las 6, 7 y 8 h en 2025 ({{es(DG('m', 'Por hora del día', '06 h', 'modelo (calibrado)', 'mediana'))}}, {{es(DG('m', 'Por hora del día', '07 h', 'modelo (calibrado)', 'mediana'))}} y {{es(DG('m', 'Por hora del día', '08 h', 'modelo (calibrado)', 'mediana'))}} en el modelo calibrado). A
las 8 h pasan {{es(DG('m', 'Según haya cola aguas abajo', '08 h, con cola abajo', 'aforo 2025', 'mediana'))}} veh/h cuando hay cola en La Laguna y
{{es(DG('m', 'Según haya cola aguas abajo', '08 h, sin cola abajo', 'aforo 2025', 'mediana'))}} cuando no la hay. Por eso se probaron la descarga dependiente de la hora, la propagación de la cola y la
mezcla de pesados, y se mide la descarga del modelo igual que la del aforo. El parámetro de descarga es la descarga
a pleno rendimiento{{' en la hora de referencia, antes del factor horario y de los pesados' if ELEG('m')['horario'] == 'TRUE' or ELEG('m')['pesados'] == 'TRUE' else ''}}: no se mide como el aforo, y su diferencia con la mediana de todas
las horas con cola no es un error de predicción. No se ha ensanchado ninguna banda. Por posición en la cola, el modelo
{{VERBO(*POS('inicio'))}} el caudal al empezar la cola ({{es(POS('inicio')[0])}} frente a {{es(POS('inicio')[1])}} veh/h en 2025), {{VERBO(*POS('plena'))}} el de la cola plena
({{es(POS('plena')[0])}} frente a {{es(POS('plena')[1])}}) y {{VERBO(*POS('final'))}} el del final ({{es(POS('final')[0])}} frente a {{es(POS('final')[1])}}): cuadra la mediana del día, que es lo
que se calibra, no la forma de la descarga dentro de la cola. En las horas de cola plena el sesgo es de
{{sg(VD('m', PLENA, P25, 'sesgo'))}} veh/h en 2025 y de {{sg(VD('m', PLENA, P26, 'sesgo'))}} en 2026.

**La tarde en 2026.** El caudal con cola de la tarde bajó de {{es(VM('t', DESC, 'observado_2025'))}} veh/h en 2025 a {{es(VM('t', DESC, 'observado_2026'))}} en 2026
(IC 95 % por días: {{es(VM('t', DESC, 'ic95_observado_2026_inf'))}}-{{es(VM('t', DESC, 'ic95_observado_2026_sup'))}}, {{'que no incluye' if not (VM('t', DESC, 'ic95_observado_2026_inf') <= VM('t', DESC, 'observado_2025') <= VM('t', DESC, 'ic95_observado_2026_sup')) else 'que incluye'}} el valor de 2025), y el sesgo diario
de la descarga pasa de {{sg(VD('t', DIA_IGUAL, P25, 'sesgo'))}} veh/h en 2025 a {{sg(VD('t', DIA_IGUAL, P26, 'sesgo'))}} en 2026. Es un cambio observado entre los dos
años cuya causa no se ha identificado.

### 2.6 Demoras: qué se mide y en qué unidades (simulado)

Ninguna demora del proyecto es observada: no hay tiempos de recorrido publicados. Valores de la situación actual
simulada (`indicadores_demora.csv`, con el método de cada uno; mediana y banda p10-p90):

| Indicador | Unidad y denominador | Horizonte | Mañana | Tarde |
|---|---|---|---|---|
| Demora total | vehículos·hora (suma de todos los vehículos del día) | día laborable de 24 h | {{IDR('m', 'Demora total')}} | {{IDR('t', 'Demora total')}} |
| Espera media en la hora punta | minutos por vehículo (vehículos que llegan en los 60 minutos de más llegadas) | hora punta | {{IDR('m', 'Espera media en la hora punta', 1)}} | {{IDR('t', 'Espera media en la hora punta', 1)}} |
| Espera máxima | minutos (el vehículo que más espera) | día laborable | {{IDR('m', 'Espera máxima', 1)}} | {{IDR('t', 'Espera máxima', 1)}} |
| Duración de la cola | horas por día (minutos con cola / 60) | día laborable | {{IDR('m', 'Duración de la cola', 1)}} | {{IDR('t', 'Duración de la cola', 1)}} |
| Horas de cola como las cuenta el aforo | horas enteras por día | día laborable | {{IDR('m', 'Horas de cola como las cuenta el aforo')}} | {{IDR('t', 'Horas de cola como las cuenta el aforo')}} |
| Cola máxima | vehículos | día laborable | {{IDR('m', 'Cola máxima')}} | {{IDR('t', 'Cola máxima')}} |
| Longitud equivalente de la cola máxima | km (140 veh/km por carril, en los carriles del tramo donde se forma la cola: 2 por la mañana y 3 por la tarde; solo orientativa) | día laborable | {{IDR('m', 'Longitud equivalente de la cola máxima', 1)}} | {{IDR('t', 'Longitud equivalente de la cola máxima', 1)}} |

**Contraste indirecto.** Las horas de cola se contrastan día a día con los aforos (apartado 2.5). La espera máxima
solo se puede comparar con una franja de 10-40 min tomada de la prensa (Atlántico Hoy, 24-11-2025, estima 20 min por la
mañana y 15 por la tarde; COPE, 20-10-2021, documenta 40 min entre El Sauzal y Guamasa en un día con accidente): por la mañana
cae en esa franja el {{re.search(r'el ([0-9]+)% de las combinaciones', s('indicadores_demora', 'contraste_independiente', caso='m', indicador='Espera máxima')).group(1)}} % de las combinaciones calibradas, y por la tarde el
{{re.search(r'el ([0-9]+)% de las combinaciones', s('indicadores_demora', 'contraste_independiente', caso='t', indicador='Espera máxima')).group(1)}} %. Es un contraste débil: estimaciones periodísticas, sin fecha ni tramo exactos. La longitud de la cola no se
puede contrastar: la cola puntual no ocupa espacio en el modelo.

### 2.7 Cada alternativa: tramo, horario, horizonte, supuesto clave, rango, diferencias, coste y limitación

`fichas_alternativas.csv` tiene una ficha por alternativa y cuello. El indicador es la reducción de los
vehículos·hora de demora del día laborable frente a no actuar (simulado). Los horizontes son el primer año, a 5 y a
10 años de ponerla en marcha (con demanda inducida), 2030 con crecimiento bajo, central y alto, y los escenarios
adversos (rango de las medianas de los cuatro supuestos desfavorables de cada cuello, sin la referencia ni la cota
favorable sin demanda inducida).

**Mañana hacia Santa Cruz** (Los Rodeos-Guamasa, 6 a 9 h):

| Alternativa | 1er año | A 10 años | 2030 (crecimiento 0-1 %) | Escenarios adversos | Confianza |
|---|---|---|---|---|---|
{{'\n'.join(f"| {NOMBREM('m', a)} | {FR('m', a)} | {FR10('m', a) if not math.isnan(FA('m', a, 'mediana_10_anios')) else 'no aplica (efecto ya neto)'} | {pr(FA('m', a, 'min_2030_crecimiento'), FA('m', a, 'max_2030_crecimiento'))} | {pr(FA('m', a, 'min_escenarios_adversos'), FA('m', a, 'max_escenarios_adversos'))} | {CONF('m', a)} |" for a in ['tercer_carril', 'paquete_gestion', 'ramp_metering', 'escalonamiento', 'tarificacion'])}}

**Tarde hacia el Norte** (Bomberos La Laguna-Los Rodeos, 13 a 18 h):

| Alternativa | 1er año | A 10 años | 2030 (crecimiento 0-1 %) | Escenarios adversos | Confianza |
|---|---|---|---|---|---|
{{'\n'.join(f"| {NOMBREM('t', a)} | {FR('t', a)} | {FR10('t', a) if not math.isnan(FA('t', a, 'mediana_10_anios')) else 'no aplica (efecto ya neto)'} | {pr(FA('t', a, 'min_2030_crecimiento'), FA('t', a, 'max_2030_crecimiento'))} | {pr(FA('t', a, 'min_escenarios_adversos'), FA('t', a, 'max_escenarios_adversos'))} | {CONF('t', a)} |" for a in ['tercer_carril', 'paquete_gestion', 'ramp_metering', 'escalonamiento', 'tarificacion'])}}

**Diferencias entre alternativas, combinación a combinación** (`diferencias_emparejadas.csv`, g21). Como cada
combinación calibrada se usa para todas las alternativas, la diferencia entre dos se mide en cada combinación. Una
diferencia de menos de 2 puntos (umbral fijado de antemano) no es material. Primer año:

| Pareja | Mañana: diferencia mediana (p10 a p90); lectura | Tarde: ídem |
|---|---|---|
{{'\n'.join(f"| {ALT[a][0].upper() + ALT[a][1:]} − {ALT[b]} | {sg(100 * float(DEMV('m', 'corto', a, b)['dif_mediana']), 1)} ({sg(100 * float(DEMV('m', 'corto', a, b)['dif_p10']), 1)} a {sg(100 * float(DEMV('m', 'corto', a, b)['dif_p90']), 1)}); {LECTP('m', a, b)} | {sg(100 * float(DEMV('t', 'corto', a, b)['dif_mediana']), 1)} ({sg(100 * float(DEMV('t', 'corto', a, b)['dif_p10']), 1)} a {sg(100 * float(DEMV('t', 'corto', a, b)['dif_p90']), 1)}); {LECTP('t', a, b)} |" for a, b in (('tercer_carril', 'paquete_gestion'), ('tercer_carril', 'ramp_metering'), ('ramp_metering', 'paquete_gestion'), ('escalonamiento', 'paquete_gestion')))}}

**Coste, plazo y riesgos, aparte del efecto simulado** (`coste_plazo_riesgo.csv`; dato documental y valoración
cualitativa):

| Alternativa | Coste | Plazo | Riesgos principales |
|---|---|---|---|
{{'\n'.join(f"| {x['nombre']} | {x['coste']} | {x['plazo']} | {x['riesgos_principales']} |" for x in CPR)}}

**Supuesto clave y limitación principal de cada una:**

{{'\n'.join(f"- **{NOMBREM('m', a)}.** {s('fichas_alternativas', 'supuesto_clave', caso='m', alternativa=a).rstrip('.')}. *Limitación:* {s('fichas_alternativas', 'limitacion_principal', caso='m', alternativa=a).rstrip('.')}." for a in ['tercer_carril', 'paquete_gestion', 'ramp_metering', 'escalonamiento', 'tarificacion'])}}
- **Tercer carril hacia el Norte (hipotético).** {{s('fichas_alternativas', 'supuesto_clave', caso='t', alternativa='tercer_carril').rstrip('.')}}. *Limitación:* {{s('fichas_alternativas', 'limitacion_principal', caso='t', alternativa='tercer_carril').rstrip('.')}}.

Una reducción del 100 % es una simulación en la que la alternativa elimina la cola
(`diagnostico_reducciones_extremas.csv`): pasa en el {{pct(EXT('m', 'tercer_carril_corto', 'elimina_cola'))}} de las del
tercer carril de la mañana. Otras medidas de la demora de cada alternativa (espera media en la punta, espera
máxima, horas y cola máxima), con su p10-p90, están en `metricas_por_alternativa.csv`.

**Qué decide el resultado.** El tercer carril de la mañana, a 10 años, depende sobre todo de
{{' y de '.join(f"`{x['parametro']}` (rho de Spearman {sg(float(x['rho']), 2)})" for x in RHO_T[:2])}}. Con capacidad libre nula no reduciría
nada; con un 15 %, {{pct(TCH(0.15, 'corto', 'mediana'))}} ({{pr(TCH(0.15, 'corto', 'p10'), TCH(0.15, 'corto', 'p90'))}}) el primer año (g15; la curva fija la capacidad libre en todas las horas y no aplica la propagación de la cola de la
especificación de la mañana, así que orienta sobre cuánto pesa la holgura, no sustituye al resultado principal). Hacia el Norte, el tercer carril hipotético entre
Los Rodeos y Guamasa lo limita La Matanza. Si continuara hasta La Orotava (en el modelo, capacidad libre del 50 % en
el tramo siguiente), la reducción sería del {{pct(TCN(0.5, 'corto', 'mediana'))}} en la mediana (g15b). Es un escenario hipotético,
no una obra proyectada.

**Cuellos en serie y cola remanente** (`cola_remanente_aguas_abajo.csv`; comprobación simulada con longitudes
supuestas). Si entre Los Rodeos y La Laguna caben los vehículos de 1, 2 o 4 km de tres carriles, el tercer carril de
la mañana reduciría la demora total {{SERIE([pct(CRV(L, 'reduccion_mediana')) for L in (1, 2, 4)])}} el primer año (el modelo principal, con las mismas {{es(CRV(0, 'simulaciones'))}} combinaciones calibradas:
{{pct(CRV(0, 'reduccion_modelo_principal'))}}). Parte de la cola que quita en Los Rodeos queda entre los dos cuellos (hasta {{es(CRV(2, 'cola_remanente_max_mediana'))}}
vehículos con 2 km) y retiene también a los que entran por los ramales; sin almacenamiento, los ramales quedan
bloqueados {{es(CRV(0, 'minutos_rebose_mediana'))}} minutos al día.

**Bus-VAO convirtiendo un carril** en Padre Anchieta hacia el Norte (3 carriles → 2 + 1 reservado; g11; simulado).
Padre Anchieta no tiene velocidades fiables, así que se usa un perfil sintético calibrado con una espera de 10-40 min,
franja supuesta a partir de la prensa (15-20 min según Atlántico Hoy, 24-11-2025; 40 min en un día con incidente según
COPE, 20-10-2021), no una observación. Para que el tráfico general no vaya
peor tiene que pasar al carril reservado el {{pct(bv_eq)}} de los vehículos, un carril de tres. Para que su espera
baje a la mitad, el {{pct(quant(bv_mi, 0.5))}} ({{pr(quant(bv_mi, 0.1), quant(bv_mi, 0.9))}}). Nadie ha publicado cuántos coches llevan 2 o más
ocupantes.

**Pasarse a la guagua o al tranvía** (`transporte_publico_trasvase.csv`; simulado). Basta con poco, porque la cola
responde a los últimos vehículos. Si un 10 % de la punta de la mañana ({{es(TP('m', 0.10, 'veh_dia_trasvasados'))}}
coches al día) deja el coche, la demora bajaría:
- {{pct(TP('m', 0.10, 'reduccion_sin_rebote'))}} ({{pr(TP('m', 0.10, 'p10_sin_rebote'), TP('m', 0.10, 'p90_sin_rebote'))}}) sin rebote;
- {{pct(TP('m', 0.10, 'reduccion_1er_anio'))}} ({{pr(TP('m', 0.10, 'p10_1er_anio'), TP('m', 0.10, 'p90_1er_anio'))}}) el primer año;
- {{pct(TP('m', 0.10, 'reduccion_10_anios'))}} ({{pr(TP('m', 0.10, 'p10_10_anios'), TP('m', 0.10, 'p90_10_anios'))}}) a 10 años, con la demanda inducida.

Hace falta una oferta y una conducta que lo permitan.

**Confianza de cada alternativa** (`confianza_alternativas.csv`). Es la media de cuatro criterios: la evidencia
local, si la cola puntual representa bien el mecanismo, si depende de que los conductores cambien de hábitos y la
robustez en los escenarios adversos.

| Alternativa | Dónde y cuándo | Confianza | Por qué |
|---|---|---|---|
| Tercer carril Guamasa-Aeropuerto Norte | Los Rodeos-Guamasa hacia Santa Cruz, 6-9 h | {{CONF('m', 'tercer_carril').capitalize()}} | Añadir capacidad en un cuello es lo que mejor representa una cola puntual. Pero la capacidad libre de La Laguna es una estimación indirecta (nula el {{pct(H(7, 'sin_holgura'))}} de los días a las 7 h), y la demanda inducida viene de la literatura |
| Tercer carril hacia el Norte (hipotético) | Los Rodeos-Guamasa hacia el Norte, 13-18 h | {{CONF('t', 'tercer_carril').capitalize()}} | Igual, limitado por la capacidad libre de La Matanza; no está proyectado |
| Regulación de accesos | Accesos situados antes de cada cuello, en las dos puntas | {{CONF('m', 'ramp_metering').capitalize()}} | Sin piloto en Tenerife: el efecto se toma de Minneapolis y Melbourne. La caída de capacidad que evita no se puede medir con aforos horarios |
| Escalonamiento horario | Todo el corredor, en las dos puntas | {{CONF('m', 'escalonamiento').capitalize()}} | Hay una experiencia local (ULL), sin un cambio visible en los cuellos (asociación no causal). Depende de que instituciones y personas cambien de horario |
| Tarificación de la punta | Todo el corredor, en las dos puntas | {{CONF('m', 'tarificacion').capitalize()}} | Evidencia internacional sólida, pero sin experiencia local, en ciudades con alternativas y con un cambio de ley pendiente |
| Regulación + escalonamiento | Accesos y corredor, en las dos puntas | {{CONF('m', 'paquete_gestion').capitalize()}} | Suma dos medidas con poca evidencia local y hereda la incertidumbre de la regulación |

## 3. Qué prevemos: escenarios condicionados (simulado)

Ninguna previsión está verificada: son escenarios condicionados a sus supuestos. Cada previsión separa cuatro
componentes (`previsiones_condicionadas.csv`, con p10-p90 y la condición de validez de cada fila):
1. el **crecimiento exógeno** de la demanda: 0 %, 0,5 % y 1 % anual, justificados en `datos/escenarios_demanda.csv`;
2. los **cambios de red**: el tercer carril en servicio hacia 2029-2030. No se combinan proyectos sin fecha, como
   Guamasa-La Orotava o la circunvalación;
3. el **transporte público**: el trasvase de una parte de la punta;
4. la **demanda inducida** por cada mejora a 1, 5 y 10 años.

**Si no se hace nada** (`evolucion_sin_actuar.csv`, g18). Horas de cola por día laborable: media de las
simulaciones calibradas, con el p10-p90 si toda la demanda nueva intenta pasar en la punta. Entre corchetes, la
media si parte de la demanda se adapta:

| Crecimiento anual de la demanda | Mañana 2030 | Mañana 2035 | Tarde 2030 | Tarde 2035 |
|---|---|---|---|---|
| 0 % | {{EVR('m', 0, 2030)}} | {{EVR('m', 0, 2035)}} | {{EVR('t', 0, 2030)}} | {{EVR('t', 0, 2035)}} |
| 0,5 % (tráfico de las estaciones con margen, 2019-2025) | {{EVR('m', 0.005, 2030)}} [{{EVA('m', 0.005, 2030)}}] | {{EVR('m', 0.005, 2035)}} [{{EVA('m', 0.005, 2035)}}] | {{EVR('t', 0.005, 2030)}} [{{EVA('t', 0.005, 2030)}}] | {{EVR('t', 0.005, 2035)}} [{{EVA('t', 0.005, 2035)}}] |
| 1 % (población, 2021-2025) | {{EVR('m', 0.01, 2030)}} [{{EVA('m', 0.01, 2030)}}] | {{EVR('m', 0.01, 2035)}} [{{EVA('m', 0.01, 2035)}}] | {{EVR('t', 0.01, 2030)}} [{{EVA('t', 0.01, 2030)}}] | {{EVR('t', 0.01, 2035)}} [{{EVA('t', 0.01, 2035)}}] |

Hoy el modelo da {{es(EV('m', 0, 2025, 'horas_cola_sin_adaptacion'), 1)}} h por la mañana y
{{es(EV('t', 0, 2025, 'horas_cola_sin_adaptacion'), 1)}} por la tarde. Los aforos dan, en los días válidos de 2025 y dentro de la ventana de cada cuello,
{{es(VD('m', 'Horas de cola al día', P25, 'observado_media'), 1)}} y {{es(VD('t', 'Horas de cola al día', P25, 'observado_media'), 1)}} h de
media{{', así que por la tarde el modelo se queda algo corto (apartado 2.5)' if VD('t', 'Horas de cola al día', P25, 'sesgo') < -0.25 else ''}}. Con un 1 % anual, en 2035 la cola de la mañana
acabaría hacia las {{es(EV('m', 0.01, 2035, 'fin_cola_sin_adaptacion'))}} h (mediana), y {{('al menos la mitad de las simulaciones da ' + es(EV('m', 0.01, 2035, 'horas_cola_sin_p90')) + ' horas de cola o más') if EV('m', 0.01, 2035, 'horas_cola_sin_mediana') >= EV('m', 0.01, 2035, 'horas_cola_sin_p90') - 1e-9 else ('en una de cada diez simulaciones duraría ' + es(EV('m', 0.01, 2035, 'horas_cola_sin_p90')) + ' horas o más')}}. Es una extrapolación a un régimen que no se ha observado.

{{('**Supuesto que pesa en estas cifras.** Por la mañana, la descarga dependiente de la hora solo se aplica en las horas con datos de 2025; después se supone la descarga de referencia. Si la descarga reducida de la última hora con datos se mantuviera el resto del día, con un ' + es(100 * g_c, 1) + ' % anual la cola de la mañana en 2035 pasaría de ' + es(SDPV('Principal', g_c, 2035), 1) + ' a ' + es(SDPV('Sensibilidad', g_c, 2035), 1) + ' h (`sensibilidad_prevision_descarga.csv`). Los aforos no pueden decidir entre los dos supuestos, porque en 2025 la cola casi nunca llega a esas horas.') if SDP_OK else ''}}

**Alternativas en 2030 según el crecimiento** (`alternativas_2030_por_crecimiento.csv`). Primer año completo del
tercer carril según el plazo del contrato, con la capacidad libre del tramo siguiente recalculada con la demanda de
ese año:

| Alternativa | Crecimiento 0 % | 0,5 % | 1 % |
|---|---|---|---|
| Tercer carril, mañana | {{A30R('m', 0, 'tercer_carril_corto')}} | {{A30R('m', 0.005, 'tercer_carril_corto')}} | {{A30R('m', 0.01, 'tercer_carril_corto')}} |
| Regulación + escalonamiento, mañana | {{A30R('m', 0, 'paquete_gestion_corto')}} | {{A30R('m', 0.005, 'paquete_gestion_corto')}} | {{A30R('m', 0.01, 'paquete_gestion_corto')}} |
| Regulación + escalonamiento, tarde | {{A30R('t', 0, 'paquete_gestion_corto')}} | {{A30R('t', 0.005, 'paquete_gestion_corto')}} | {{A30R('t', 0.01, 'paquete_gestion_corto')}} |
| Tercer carril hipotético, tarde | {{A30R('t', 0, 'tercer_carril_corto')}} | {{A30R('t', 0.005, 'tercer_carril_corto')}} | {{A30R('t', 0.01, 'tercer_carril_corto')}} |

**Retraso de la obra** (`retraso_obra_tercer_carril.csv`). Si el tercer carril entra en servicio en 2029, 2030, 2031 o
2032, con un crecimiento del {{es(100 * g_c, 1)}} % anual, el primer año reduciría la demora de la mañana
{{SERIE([pct(RETV(a, g_c, 'tercer_carril_corto', 'reduccion_mediana')) for a in (2029, 2030, 2031, 2032)])}} (mediana), sobre una situación sin actuar que empeora cada año: sin actuar, la cola de la mañana pasaría de {{es(RETV(2029, g_c, 'base', 'horas_cola_mediana'), 1)}} h en 2029 a {{es(RETV(2032, g_c, 'base', 'horas_cola_mediana'), 1)}} h en 2032.

**Escenarios adversos** (`escenarios_adversos.csv`; mediana del primer año y, entre paréntesis, p10-p90). ¿Cambia el orden si las cosas van
peor?

- **Tramo siguiente lleno** (Padre Anchieta con 2 carriles efectivos por la mañana; La Matanza llena por la
  tarde). {{'El tercer carril y la regulación de accesos no reducirían nada en ninguno de los dos cuellos (0 % de mediana, de p10 y de p90)' if max(max(EAX(c, 'Tramo siguiente sin holgura', e, 'reduccion_p10'), EAX(c, 'Tramo siguiente sin holgura', e, 'reduccion_p90')) for c in 'mt' for e in ('tercer_carril_corto', 'ramp_metering_corto')) < 0.005 else ('El tercer carril y la regulación de accesos reducirían ' + EAR('m', 'Tramo siguiente sin holgura', 'tercer_carril_corto') + ' y ' + EAR('m', 'Tramo siguiente sin holgura', 'ramp_metering_corto') + ' por la mañana, y ' + EAR('t', 'Tramo siguiente sin holgura', 'tercer_carril_corto') + ' y ' + EAR('t', 'Tramo siguiente sin holgura', 'ramp_metering_corto') + ' por la tarde')}}. Quedarían la tarificación, {{EAR('m', 'Tramo siguiente sin holgura', 'tarificacion')}} por la mañana y {{EAR('t', 'Tramo siguiente sin holgura', 'tarificacion')}} por la tarde,
  y el escalonamiento, {{EAR('m', 'Tramo siguiente sin holgura', 'escalonamiento_corto')}} y {{EAR('t', 'Tramo siguiente sin holgura', 'escalonamiento_corto')}}.
- **Demanda inducida alta** (elasticidades −0,5 el primer año y −1,0 a 10 años). Todo bajaría unos puntos salvo la
  tarificación, cuyo efecto ya es neto: tercer carril {{EAR('m', 'Demanda inducida alta', 'tercer_carril_corto')}} y
  {{EAR('t', 'Demanda inducida alta', 'tercer_carril_corto')}}; regulación + escalonamiento {{EAR('m', 'Demanda inducida alta', 'paquete_gestion_corto')}} y
  {{EAR('t', 'Demanda inducida alta', 'paquete_gestion_corto')}}.
- **Caída de capacidad pequeña** (4 %, con la misma descarga medida). La regulación de accesos bajaría al
  {{EAR('m', 'Caída de capacidad pequeña', 'ramp_metering_corto')}} por la mañana y al {{EAR('t', 'Caída de capacidad pequeña', 'ramp_metering_corto')}}
  por la tarde. El tercer carril: {{EAR('m', 'Caída de capacidad pequeña', 'tercer_carril_corto')}} y {{EAR('t', 'Caída de capacidad pequeña', 'tercer_carril_corto')}}.
- **Un carril cortado 30 minutos** en lo más alto de la punta: tercer carril {{EAR('m', 'Incidente', 'tercer_carril_corto')}} por la mañana y
  {{EAR('t', 'Incidente', 'tercer_carril_corto')}} por la tarde; regulación + escalonamiento {{EAR('m', 'Incidente', 'paquete_gestion_corto')}} y {{EAR('t', 'Incidente', 'paquete_gestion_corto')}}.
- **Sin demanda inducida** (cota favorable). Todas las alternativas rendirían más salvo la tarificación: el tercer
  carril, {{EAR('m', 'Sin demanda inducida', 'tercer_carril_corto')}} y {{EAR('t', 'Sin demanda inducida', 'tercer_carril_corto')}}; la regulación + escalonamiento,
  {{EAR('m', 'Sin demanda inducida', 'paquete_gestion_corto')}} y {{EAR('t', 'Sin demanda inducida', 'paquete_gestion_corto')}}.

En cada supuesto, las alternativas a menos de 2 puntos de la mejor se consideran empatadas
(`escenarios_adversos.csv`, columna `empate_con_la_primera`).

**Condiciones de validez.** Las previsiones suponen:
- la misma red de 2025 salvo el tercer carril contratado;
- el mismo reparto horario de la demanda;
- la eficacia y las elasticidades de la literatura;
- un tramo siguiente que se comporta como en 2025.

No incluyen obras, incidencias ni cambios de transporte público que no estén en el escenario. Fuera de estas
condiciones, sobre todo con crecimientos del 1 % hasta 2035, el modelo trabaja en un régimen que no se ha
observado.

## 4. Contexto: proyectos y transporte público

`datos/proyectos.csv` recoge cada actuación con su promotor, coste, situación a 20 de octubre de 2026 y
fuente. Lo esencial:

- **Tercer carril Guamasa-Aeropuerto Norte** (Gobierno de Canarias). Solo hacia Santa Cruz. Se adjudicó por 58,2 M€
  (IGIC incluido) a la UTE Ferrovial-Asyota y se formalizó el 2-10-2026, con 35 meses de plazo según la
  licitación (anuncio en el Diario Oficial de la UE del 24-12-2025: calzada hacia Santa Cruz entre los PK 11+400 y
  15+000). En octubre de 2024 se anunció su licitación para el primer trimestre de 2025; salió en diciembre de 2025.
- **Regulación de accesos** (Cabildo y DGT; 1,8-4 M€). Anunciada en mayo de 2025, con una prueba piloto prevista
  para octubre y noviembre de 2025; pruebas de la DGT en enero de 2026; sin implantar.
- **Bus-VAO «inteligente»** en la TF-5 (Cabildo; 6,2 M€). Información pública en junio de 2026; promete ahorros de
  tiempo con simulaciones no publicadas.
- **Tercer carril Guamasa-La Orotava** (unos 300 M€) y **circunvalación de La Laguna** (355 M€). Son proyectos sin
  fecha de obra:
  - el primero empieza en Guamasa, después del estrechamiento de la tarde, y aliviaría La Matanza;
  - el segundo descargaría el tramo de La Laguna.

  Ninguno amplía Los Rodeos-Guamasa hacia el Norte.
- **Peajes por congestión.** Son una opción del PIMSIT; exigen cambiar la ley canaria y la presidenta del Cabildo
  los descartó el 7-10-2026.

**Transporte público** (g10; asociación no causal). Con la gratuidad para los residentes que viajan con frecuencia
(desde el 1-1-2023), TITSA casi duplicó sus viajeros: índice {{es(100 * TITSA('2025') / TITSA('2019'))}} en 2025, con 2019 = 100. En el mismo periodo, el
tráfico de la TF-5 (IMD media de las cuatro estaciones de g10) se quedó en {{es(100 * IMD4('2025') / IMD4('2019'))}}. Es una coincidencia entre dos series, no una medida del efecto. No permite saber
cuántos viajes en coche se evitaron ni si el hueco lo ocupó demanda que antes no circulaba.

## 5. Verificación de los apuntes de partida

De 53 afirmaciones: **19 confirmadas, 15 parcialmente ciertas, 8 sin fuente verificable y 11 falsas o
erróneas** (`datos/afirmaciones_apuntes.csv`, g09). Los errores incluyen:
- cálculos: «+33 %» al pasar de 2 a 3 carriles, cuando es +50 %;
- unidades: densidad expresada en veh/h;
- flujos imposibles: 5.500 veh/h por dos carriles, cuando el máximo medido en Los Rodeos en 2025 es {{es(VMAX('ascendente'))}} veh/h;
- atribuciones: el −50 % es del Bus-VAO, no del tercer carril.

## 6. Reproducibilidad y pruebas

- **Entorno.** R 4.3.3 y versiones fijadas en `renv.lock` ({{n_renv}} paquetes, con sus dependencias) y en
  `entorno/versiones_paquetes.csv`, que `main.R` comprueba al empezar: R y {{len(T('entorno_versiones')) - 1}} paquetes, entre ellos los del
  dispositivo PNG de los gráficos. {{'La ejecución entregada usó exactamente esas versiones' if all(x['coincide'] == 'TRUE' for x in T('entorno_versiones')) else 'OJO: la ejecución entregada no usó todas las versiones fijadas'}}
  (`entorno_versiones.csv`). La zona horaria se fija en `Atlantic/Canary` y cada paso aleatorio tiene su semilla
  (`montecarlo_semillas.csv`).
- **Ejecución completa sin intervención.** Duró {{es(minutos, 1)}} minutos y dejó {{n_avisos}} avisos (`registro_avisos.txt` recoge todos
  los avisos del análisis). `main.R` guarda la huella de sus entradas al empezar y la vuelve a calcular al acabar: los
  {{n_entradas}} ficheros de `main.R`, `R/`, `tests/`, `entorno/`, `renv.lock` y `datos/` no cambiaron.
- **Pruebas** (`tests/`; resultado en `salidas/resultado_pruebas.csv`): {{n_bloq}} bloques y {{es(n_comp)}} comprobaciones,
  con {{n_fallos}} fallos{{(' y ' + str(n_omit) + ' omitidos') if n_omit else ''}}. Cubren:
  - **invariantes físicos:** conservación de vehículos, identidad de Little, caso analítico FIFO, cola y salidas no
    negativas y salidas por debajo de la capacidad minuto a minuto, el tercer carril nunca empeora, monotonía de
    los horizontes y cuellos en serie con almacenamiento finito;
  - **restricción aguas abajo:** con el tramo siguiente lleno, el tercer carril y la regulación no añaden caudal;
    el escalonamiento no pierde vehículos;
  - **casos extremos:** sin demanda, demanda que nunca se disipa, caída de capacidad nula o máxima, holgura nula o
    muy alta, día de cambio de hora, mes sin registros y fichero con BOM;
  - **validación:** mitades de la validación cruzada, intervalo predictivo, regla de elección de la especificación y
    tabla de validación con cinco indicadores por sentido;
  - **diferencias emparejadas:** sin ganador cuando la diferencia no es material;
  - **la procedencia:** integridad, catálogo, sumas de control de los 24 extractos y contraste con el catálogo
    nacional;
  - **la trazabilidad del Monte Carlo y de las fichas:** todas las semillas del código figuran en la tabla de
    semillas, y el rango de los escenarios adversos de cada ficha no incluye la referencia ni la cota favorable;
  - **la no regresión:** las tablas clave de la ejecución entregada están en `tests/referencia/`, con su
    configuración, y una ejecución completa nueva con la misma configuración tiene que reproducirlas.
- **Dos ejecuciones completas en copias limpias, con el código entregado** (`docs/reproducibilidad_dos_ejecuciones.csv`, generada con
  `tests/comparar_ejecuciones.R`): {{n_rep_ok}} de {{n_rep}} tablas y gráficos de salidas iguales dentro de la tolerancia (diferencia relativa
  ≤ {{tol_rep}} en las cifras, mismas filas, columnas y textos), contando la serie horaria comprimida y el resultado de las
  pruebas, ejecutadas en las dos copias; {{n_rep_byte}} son iguales byte a byte. No se comparan los {{n_rep_prop}} ficheros propios de
  cada ejecución (la configuración, con su hora de inicio, y el manifiesto de huellas) ni los registros de texto de la
  ejecución (resumen, sesión y avisos), que llevan la hora; los de la segunda copia están en `docs/segunda_ejecucion/`.
  Es la misma máquina: muestra que el resultado no depende de la ejecución, no que otra persona lo reproduzca.
- **Manifiestos.** `salidas/manifiesto_ejecucion.csv` tiene el SHA-256 de `main.R`, `R/`, `tests/` (sin las
  referencias de no regresión, que se copian de la propia ejecución), `entorno/`, `renv.lock`, `datos/` y `salidas/` al
  acabar la ejecución; `manifiesto_entrega.csv`, el de todos los ficheros
  entregados, también los que se añaden después (documentos, panel, referencia de no regresión y resultado de las
  pruebas). Prueban que los ficheros no han cambiado después, no quién los generó.
- **Reimplementación en Python** (`docs/verificacion_independiente/`). Recalcula las cifras observadas con otro
  lenguaje, a partir de los mismos datos del proyecto y de las definiciones del código R. Sirve para detectar
  errores de programación, pero **no es una verificación externa**: no la ha hecho otra persona ni parte de otras
  fuentes.

## 7. Límites y datos que faltan

- Es un modelo de **cola puntual**, no una microsimulación. Sirve para comparar alternativas con los mismos supuestos
  y ver qué decide el resultado, no para dimensionar obras. La restricción aguas abajo y los cuellos en serie con
  almacenamiento son aproximaciones con longitudes supuestas.
- La congestión se deduce de **rangos de velocidad en puntos de aforo**, no de tiempos de recorrido. No hay ninguna
  demora observada.
- La **capacidad libre del tramo siguiente** es una estimación indirecta: no hay aforos de ramales y la capacidad de
  abajo sale de los caudales de la misma punta. Es el supuesto que más pesa en el tercer carril (apartado 2.2).
- La **descarga del modelo** cuadra con la mediana del día, no con su forma dentro de la cola: por la mañana
  {{VERBO(*POS('plena'))}} el caudal de las horas de cola plena ({{sg(VD('m', PLENA, P26, 'sesgo'))}} veh/h en 2026), y el intervalo predictivo queda por
  debajo del 80 % en algunos indicadores (apartado 2.5).
- {{n_pend}} estación-sentidos tienen **carriles pendientes de confirmación** entre el catálogo de 2026 y el inventario de
  2006, y los ficheros usados no dan el punto kilométrico de las estaciones. En particular, la **posición de Ermita Cruz
  Chica (103) respecto al enlace de Guamasa** no está publicada: el catálogo de carriles la etiqueta «Los Rodeos» y la
  TF-152 tiene una estación del mismo nombre en su «Enlace TF-5», pero el CSV de IMD la asigna al tramo «El Sauzal» y
  el Cabildo cita su IMD como la del tramo Guamasa-El Sauzal (afirmación 3 de los apuntes). El estudio la sitúa entre
  Los Rodeos y Guamasa; si estuviera aguas arriba del enlace, el caudal medido con cola sería la descarga del cuello
  menos las entradas de Guamasa, y el tercer carril contratado empezaría aguas abajo del aforador. El punto
  kilométrico está pedido en `docs/solicitud_datos_cabildo.md`.
- Las **elasticidades, la eficacia de la regulación y el efecto de la tarificación** se toman de la literatura
  (columna `transferibilidad` de `parametros_modelo.csv`): los aforos no las informan.
- **Incidentes, obras y lluvia** no están vinculados a los días. El Cabildo publica un registro de «Incidencias en
  carreteras de Tenerife» (2010-2026, con carretera, tramo, fecha y hora de inicio y tipo) que se identificó pero no
  se incorporó, porque su descarga no se pudo completar en el entorno del análisis; la lluvia exige una clave de
  AEMET OpenData. Los días con la punta anómala se marcan y se prueba el análisis sin ellos.
- Los efectos de la ULL y de la pasarela son **asociaciones no causales**: sin registros de obras ni de incidencias
  incorporados y sin un grupo de control válido.
- El calendario incluye festivos autonómicos e insulares, no los municipales.
- **Diciembre de 2024** no está en el extracto horario aunque el portal lo publica. No afecta a las cifras de 2025
  ni a la validación con 2026.
- El contraste que hace `main.R` con la publicación original es de **metadatos** (URL, identificador, nombre y
  licencia) para una muestra de recursos, más las huellas y las sumas de control de las copias locales; no vuelve a
  descargar nada (`DESCARGAR_HORARIOS <- TRUE` lo haría). El contraste con descarga directa de los 37 recursos es
  un paso aparte, fuera de `main.R` (`herramientas/comprobaciones/contrastar_fuentes.py`, evidencia en
  `docs/contraste_fuentes/`), hecho la madrugada del 17-10-2026 (hora canaria).
- **Faltan datos públicos clave** (`datos/matriz_lagunas.csv`, con el estado de cada petición):
  - caudales cada 5-15 minutos;
  - tiempos de recorrido;
  - aforos de los ramales;
  - matriz origen-destino;
  - ocupación de los vehículos;
  - un aforador fiable en Padre Anchieta;
  - el inventario de carriles vigente y el punto kilométrico de las estaciones.

  Con ellos se podría pasar a un modelo de red y validar la espera.

## Documentos del proyecto

| Documento | Contenido |
|---|---|
| `docs/METODOLOGIA.md` | Método completo: datos y procedencia, calidad, geometría, capacidad libre, modelo, Monte Carlo, validación, demoras, previsiones, causalidad y reproducibilidad |
| `docs/VALIDACION_Y_CALIDAD.md` | Los diez criterios de calidad del estudio, cómo se comprueba cada uno y con qué resultado |
| `docs/solicitud_datos_cabildo.md` | Datos que habría que pedir al Cabildo |
| `docs/verificacion_independiente/` | Reimplementación en Python de las cifras observadas (no es una verificación externa) |
| `docs/reproducibilidad_dos_ejecuciones.csv` | Dos ejecuciones completas en copias limpias con el código entregado, fichero a fichero, con la tolerancia |
| `docs/contraste_fuentes/` | Contraste de los 37 recursos oficiales descargados con el portal y de la población con el INE |
| `docs/segunda_ejecucion/` | Registros de sesión y de avisos de la segunda ejecución completa |
| `docs/REVISION_2026-10-20.md` | Revisión del 20-10-2026: qué se comprobó, qué cambió (hechos, código, panel, documentación) y qué queda abierto |
| `docs/comprobacion_base_nocturna_2025.csv` | Línea base de velocidad de madrugada calculada solo con 2025: horas congestionadas de 2025 que cambiarían (`herramientas/comprobaciones/`) |

## Estructura

```text
main.R                          Ejecuta todo (secciones 1-11, con la 4b) y escribe salidas/
R/00_utilidades.R               Paquetes, rutas, estaciones, tema gráfico, formato español
R/01_datos_validacion.R         IMD: carga, 10 reglas de validación, contraste con las copias oficiales
R/02_descriptivo.R              Gráficos de aforos anuales y transporte público
R/03_saturacion.R               «k crítico»: margen de capacidad en la hora punta
R/04_modelo_cuello_botella.R    Modelo de cola de 24 h: perfil híbrido, especificación de la descarga, restricción
                                aguas abajo, cuellos en serie, esperas por cohortes, alternativas
R/05_montecarlo.R               Simulaciones, calibración, sensibilidad, auditoría del Monte Carlo, Bus-VAO
R/06_proyectos_verificacion.R   Actuaciones, verificación de los apuntes, comprobaciones aritméticas
R/07_datos_horarios.R           Aforos horarios: lectura, reglas H1-H9, colas, capacidad, holgura
R/08_comprobaciones_modelo.R    Comprobaciones numéricas del modelo en cada ejecución (conservación, límites)
R/09_trazabilidad.R             Manifiesto SHA-256 de código, datos y salidas; registro de la sesión
R/10_validacion_escenarios.R    Cobertura, cambio de hora, ULL, validación, previsión, escenarios adversos,
                                trasvase al transporte público, confianza, fuentes
R/11_validacion_y_trazabilidad.R Validación día a día, diagnóstico de la descarga, geometría, balance por tramos,
                                variantes de la holgura, demoras, diseño del Monte Carlo, procedencia, banderas
                                de calidad, previsiones condicionadas y fichas de las alternativas
R/12_validacion_predictiva.R    Validación cruzada temporal, intervalo predictivo y elección de la especificación
R/13_comparacion_y_trazabilidad.R Diferencias emparejadas, coste y plazo, retraso de obra, uso de la geometría,
                                correspondencia de campos, contraste con la publicación original, días atípicos,
                                cola remanente y metadatos de los gráficos
tests/                          Pruebas testthat, referencia de no regresión y comparador de ejecuciones
entorno/, renv.lock             Versiones fijadas de R y de los paquetes
datos/                          Entradas (cada fichero con su fuente)
docs/                           Metodología, validación y calidad, solicitud de datos, reimplementación en Python,
                                contraste de los originales con el portal y registros de la segunda ejecución
herramientas/                   Ensamblado de los ficheros horarios descargados, plantillas que rellenan los documentos
                                con las cifras de salidas/, comprobación de las cifras del panel y comprobaciones
                                aparte (no los usa main.R)
panel/index.html                Panel autónomo de resultados (abrir en un navegador)
salidas/graficos/               g01-g21 más g07b y g15b (23 PNG)
salidas/tablas/                 Tablas de resultados (CSV)
salidas/panel/                  Tablas limpias que usa el panel
salidas/resumen_resultados.txt  Todo lo que imprime la ejecución
salidas/manifiesto_ejecucion.csv  SHA-256 de código, datos y salidas
salidas/registro_sesion.txt     Versiones de R y de los paquetes, y duración
salidas/registro_avisos.txt     Avisos de la ejecución
salidas/configuracion_ejecucion.csv  Simulaciones, semillas de la auditoría del Monte Carlo y zona horaria
salidas/resultado_pruebas.csv   Resultado de las pruebas
manifiesto_entrega.csv          SHA-256 de todos los ficheros entregados, también los añadidos después de la
                                ejecución (documentos, panel, referencia de no regresión y pruebas)
```

## Datos

| Fichero | Contenido | Fuente |
|---|---|---|
| `horarios/tf5_horario_AAAA-MM.csv.gz` (24) | Registros horarios por carril de las estaciones de la TF-5 | Cabildo de Tenerife, datos.tenerife.es |
| `horarios/meta_AAAA-MM.json` (24) | URL, fecha, tamaño y SHA-256 del fichero oficial y del extracto; sumas de control | Generado al descargar |
| `oficial/` | CSV oficiales de IMD 2018-2025, catálogo de carriles, diccionarios de datos, manifiesto e instantánea del catálogo del portal | datos.tenerife.es |
| `imd_tf5_2018_2025.csv` | IMD por estación y sentido (idéntica, valor a valor, a las copias de los CSV oficiales de `oficial/`) | Ídem |
| `fuentes_horarias.csv` | Índice de los 24 ficheros horarios oficiales: enlace, tamaño, SHA-256 y extracto | datos.tenerife.es |
| `fuentes_imd.csv` | Enlaces de los CSV oficiales de IMD | datos.tenerife.es |
| `contraste_catalogo_nacional_2026-10-16.csv` | Recursos de 2025 tal como los lista el catálogo nacional (URL, nombre, licencia y fechas del conjunto) | datos.gob.es, consultado el 16-10-2026 |
| `imd_contexto_2025.csv` | IMD 2025 de la TF-1, TF-2, TF-13, TF-152, TF-217 y TF-24 | datos.tenerife.es |
| `carriles_tf5.csv` | Carriles aforados por sentido (los del catálogo oficial) | Catálogo oficial de carriles |
| `geometria_tramos.csv` | Carriles aforados, del inventario de 2006 y del modelo; estado (confirmado o pendiente) y escenario alternativo | Catálogo de carriles (2026) y PTEOSVAM (2006) |
| `festivos_canarias.csv` | Festivos autonómicos e insulares de 2024-2026 | BOC |
| `poblacion_tenerife.csv` | Población de Tenerife, 2021-2025 | INE, Censo anual de población (tabla 78749) |
| `escenarios_demanda.csv` | Ritmos de crecimiento simulados y su justificación | IMD del Cabildo e INE |
| `transporte_publico_viajeros.csv` | Viajeros de TITSA y del tranvía, 2017-2025 | Notas y memorias de TITSA y Metrotenerife, y prensa (fuente de cada fila) |
| `parametros_modelo.csv` | Rangos de los parámetros, tipo, fuente y transferibilidad | Aforos, HCM, Goodwin, Cassidy y Bertini… |
| `coste_plazo_riesgo.csv` | Coste, plazo, puesta en servicio prevista y riesgos de cada alternativa | Contratos, licitaciones y anuncios (fuente de cada fila) |
| `confianza_alternativas.csv` | Criterios de confianza, supuesto clave y limitación principal de cada alternativa | Elaboración propia |
| `limitaciones_por_resultado.csv` | Categoría (observado, estimado, supuesto, simulado o asociación no causal), origen, límites e incertidumbre de cada resultado | Elaboración propia |
| `graficos_metadatos.csv` | Tipo de resultado, horizonte, hipótesis e incertidumbre de cada gráfico | Elaboración propia |
| `matriz_lagunas.csv` | Datos que faltan, cómo se suplen, dónde pedirlos y estado de la petición | Elaboración propia |
| `fuentes_documentales.csv` | Fuentes documentales con fecha de consulta y licencia | Varias |
| `proyectos.csv` | Actuaciones: coste, situación y fuente | Gobierno de Canarias, Cabildo, prensa |
| `afirmaciones_apuntes.csv` | 53 afirmaciones de los apuntes con veredicto, dato y fuente | Varias |

## Fuentes

- Cabildo de Tenerife, portal de datos abiertos: [Intensidad media diaria de tráfico (IMD)](https://datos.tenerife.es/ckan/dataset/1717bda1-6b7b-43e0-be4e-e3ed060b8b97),
  [Rango de velocidades de los carriles](https://datos.tenerife.es/ckan/dataset/079b37ef-674e-411f-8886-f4c5a53826ae)
  e Intensidad diaria de tráfico de Tenerife por carril y hora:
  [2024](https://datos.tenerife.es/ckan/dataset/e4cf320e-dda5-4b9a-bae3-ec3d6a252c80),
  [2025](https://datos.tenerife.es/ckan/dataset/94a021a2-1dea-4526-9e17-3290b3b9add3) y
  [2026](https://datos.tenerife.es/ckan/dataset/d02ccf54-aca2-4a82-9ef0-fbd285b5f401).
- Catálogo nacional de datos abiertos: [Intensidad diaria de tráfico de Tenerife (2025)](https://datos.gob.es/es/catalogo/l03380011-intensidad-diaria-de-trafico-de-tenerife-2025)
  (contraste de la procedencia) e [Incidencias en carreteras de Tenerife](https://datos.gob.es/es/catalogo/l03380011-incidencias-en-carreteras-de-tenerife)
  (fuente identificada, no incorporada).
- Cabildo de Tenerife, [Plan Territorial Especial de Ordenación del Sistema Viario del Área Metropolitana, Anexo III-b](https://tenerife.es/documents/d/portal/sistema-viario-metropolitano-ANEXOIIIb)
  (ficha de la TF-5), aprobado el 19-7-2006 y publicado en el [BOC n.º 38 de 21-2-2007](https://www.gobiernodecanarias.org/boc/2007/038/023.html).
- INE, [Censo anual de población, tabla 78749](https://www.ine.es/jaxi/Tabla.htm?tpx=78749).
- Gobierno de Canarias y RTVC: [formalización del contrato del tercer carril (2-10-2026)](https://rtvc.es/obras-publicas-formaliza-contrato-obras-tercer-carril-tf-5-guamasa-aeropuerto-norte-2-octubre-2026/)
  y [adjudicación por 58,2 M€ (10-9-2026)](https://rtvc.es/adjudicada-la-obra-del-tercer-carril-de-la-tf-5-10-septiembre-2026/).
  Anuncio de la licitación para el primer trimestre de 2025: [RTVC, 29-10-2024](https://rtvc.es/obras-tercer-carril-guamasa-los-rodeos-se-licitaran-primer-trimestre-2025/).
  Anuncio oficial de licitación (35 meses; calzada hacia Santa Cruz, PK 11+400 a 15+000): [Diario Oficial de la UE, TED 861575-2025](https://ted.europa.eu/es/notice/861575-2025/pdf).
- Gratuidad del transporte público para residentes desde el 1-1-2023: [elDiario.es, 24-12-2022](https://www.eldiario.es/canariasahora/sociedad/guaguas-gratis-canarias-descuento-bono-1-enero_1_9821483.html).
- Regulación de accesos: [RTVC, 6-5-2025](https://rtvc.es/tenerife-instala-semaforos-inteligentes/).
- Universidad de La Laguna y prensa sobre los horarios escalonados y la pasarela del Padre Anchieta:
  enlaces fila a fila en `datos/fuentes_documentales.csv`, `datos/proyectos.csv` y `datos/afirmaciones_apuntes.csv`.
- Calendarios laborales de Canarias (BOC): enlaces en `datos/festivos_canarias.csv`.
- Modelo: Vickrey (1969), Newell (1993), Cassidy y Bertini (1999), Highway Capacity Manual, Goodwin (1996),
  SACTRA (1994), Cervero (2003), Duranton y Turner (2011), Hymel, Small y Van Dender (2010); las fuentes de
  cada parámetro están en `datos/parametros_modelo.csv`.
