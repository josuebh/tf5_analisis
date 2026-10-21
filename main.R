# =============================================================================
#  ANÁLISIS INTEGRAL Y MODELIZACIÓN PREDICTIVA DE LA CONGESTIÓN DE LA AUTOPISTA
#  TF-5 EN TENERIFE: DIAGNÓSTICO, EVOLUCIÓN Y EVALUACIÓN DE ALTERNATIVAS
#  Script principal: ejecuta todo el análisis y genera gráficos y tablas.
#
#  Uso (desde la carpeta del proyecto):   Rscript main.R      (alrededor de una hora)
#  Prueba rápida:                        TF5_N_SIM=2000 TF5_N_REJILLA=2000 TF5_N_PREV=200 Rscript main.R
#  Pruebas automáticas:                  Rscript tests/ejecutar_pruebas.R
#  En RStudio: abrir esta carpeta como proyecto (o setwd() aquí) y «Source».
#
#  Requisitos: R >= 4.1 y los paquetes dplyr, tidyr, readr, ggplot2, scales,
#  ggrepel, patchwork y jsonlite (digest y testthat, recomendados). Versiones con
#  las que se generaron los resultados: entorno/versiones_paquetes.csv y renv.lock
#  (renv::restore() las instala); con otras, el análisis corre igual y avisa.
#    install.packages(c("dplyr","tidyr","readr","ggplot2","scales","ggrepel",
#                       "patchwork","jsonlite","digest","testthat"))
#
#  Datos: todo lo necesario está en datos/ (extractos y copias de los ficheros
#  oficiales del Cabildo, con la huella SHA-256 que se registró al descargarlos);
#  no hace falta Internet. Las huellas prueban que las copias no han cambiado
#  desde la descarga (integridad), no la autenticidad del origen.
#  Organización de los resultados (tres preguntas):
#    · Qué sabemos (secciones 1-4): aforos oficiales, calidad, días atípicos, colas
#      medidas y asociación (no causal) con los horarios de la ULL y la pasarela.
#    · Qué estimamos (secciones 5-7): especificación de la descarga elegida por
#      validación cruzada, modelo de cola calibrado, validación fuera de muestra y
#      alternativas hoy, con diferencias emparejadas y auditoría del Monte Carlo.
#    · Qué prevemos (sección 8): evolución sin actuar, alternativas en 2030,
#      retrasos de obra, escenarios adversos y duración de la mejora.
#  Salidas: salidas/graficos/*.png, salidas/tablas/*.csv, salidas/panel/*.csv,
#           salidas/resumen_resultados.txt, salidas/manifiesto_ejecucion.csv,
#           salidas/registro_sesion.txt
# =============================================================================

options(warn = 1)
invisible(Sys.setlocale("LC_CTYPE", "C.UTF-8"))
Sys.setenv(TZ = "Atlantic/Canary")   # zona horaria fija (solo afecta a las horas de los registros de la ejecución)
inicio <- Sys.time()
faltan <- setdiff(c("dplyr", "tidyr", "readr", "ggplot2", "scales", "ggrepel", "patchwork", "jsonlite"),
                  rownames(installed.packages()))
if (length(faltan)) stop("Faltan paquetes: ", paste(faltan, collapse = ", "), ". Instálalos con install.packages().")
# Registro de avisos: todos los avisos del análisis se guardan en salidas/registro_avisos.txt.
# Se recogen con withCallingHandlers() alrededor de todo el análisis (hasta la comprobación
# final de las entradas), que funciona igual con Rscript que con source().
avisos <- character()
registrar_aviso <- function(w) avisos <<- c(avisos, paste0(format(Sys.time(), "%H:%M:%S"), " ", conditionMessage(w)))
withCallingHandlers({
for (f in sort(list.files("R", pattern = "\\.R$", full.names = TRUE))) source(f, encoding = "UTF-8")
# Huellas de las entradas al empezar: al acabar se comprueba que nada ha cambiado durante la ejecución
ENTRADAS <- c("main.R", "R", "tests", "entorno", "renv.lock", "datos")
huellas_inicio <- manifiesto(ENTRADAS)

# Opciones que requieren Internet (no son necesarias: los datos ya están en datos/)
DESCARGAR_HORARIOS  <- FALSE   # TRUE: vuelve a bajar los 24 TXT horarios oficiales y comprueba su SHA-256
CONTRASTAR_EN_LINEA <- FALSE   # TRUE: contrasta además la IMD con el portal en línea y guarda una nueva instantánea del catálogo
# Combinaciones por caso (se calibran después): 20.000 por la mañana (su regla de calibración
# acepta menos) y 10.000 por la tarde; TF5_N_SIM fija el mismo número en los dos
N_SIMULACIONES      <- if (nzchar(Sys.getenv("TF5_N_SIM"))) rep(entero_positivo_entorno("TF5_N_SIM", 20000L), 2) else c(20000L, 10000L)
N_REJILLA           <- entero_positivo_entorno("TF5_N_REJILLA", 10000L)   # combinaciones para elegir la especificación de la descarga
N_PREVISION         <- entero_positivo_entorno("TF5_N_PREV", 100000L)   # simulaciones calibradas para previsiones y escenarios (por defecto, todas)
SEMILLAS_AUDITORIA  <- c(2027L, 2028L)                                  # repetición del Monte Carlo con otras semillas

limpiar_salidas()
log_txt <- character()
anotar <- function(...) { linea <- paste0(...); message(linea); log_txt <<- c(log_txt, linea) }
rellenar <- function(x, n) paste0(x, strrep(" ", pmax(0, n - nchar(x))))   # ancho en caracteres, no en bytes
anotar("Ejecución: ", format(Sys.time(), "%Y-%m-%d %H:%M"), " · R ", getRversion())
vers <- comprobar_versiones()
guardar_tabla(vers, "entorno_versiones")
if (nrow(vers) && !all(vers$coincide))
  anotar("Aviso: versiones distintas de las fijadas en entorno/versiones_paquetes.csv: ",
         paste(sprintf("%s %s (fijada %s)", vers$paquete, vers$instalada, vers$fijada)[!vers$coincide], collapse = "; "),
         ". Los resultados pueden cambiar en algún decimal.") else
  anotar("Versiones de R y de los paquetes: las fijadas en entorno/versiones_paquetes.csv.")
readr::write_csv(tibble(parametro = c("N_SIMULACIONES_MANANA", "N_SIMULACIONES_TARDE", "N_REJILLA", "N_PREVISION", "SEMILLAS_AUDITORIA", "zona_horaria", "inicio"),
                        valor = c(N_SIMULACIONES[1], N_SIMULACIONES[2], N_REJILLA, N_PREVISION, paste(SEMILLAS_AUDITORIA, collapse = " "),
                                  Sys.getenv("TZ"), format(inicio, "%Y-%m-%d %H:%M:%S %Z"))),
                 file.path("salidas", "configuracion_ejecucion.csv"))

# =============================================================================
# QUÉ SABEMOS
# =============================================================================

# ---- 1. IMD oficial y validación -----------------------------------------------
anotar("== 1. IMD oficial y validación ==")
imd_raw <- cargar_imd()
flags   <- validar_imd(imd_raw)
guardar_tabla(flags, "validacion_datos")
anotar(sprintf("Filas TF-5: %d (%d estaciones, %d-%d).", nrow(imd_raw),
               n_distinct(imd_raw$estacion_id), min(imd_raw$anio), max(imd_raw$anio)))
anotar(sprintf("Errores de coherencia (ascendentes + descendentes != total): %d",
               sum(grepl("^R1 ", flags$regla))))
resumen_flags <- flags |> count(regla, gravedad, name = "filas")
for (i in seq_len(nrow(resumen_flags)))
  anotar(sprintf("  %-40s %-6s %2d filas", resumen_flags$regla[i], resumen_flags$gravedad[i], resumen_flags$filas[i]))
contraste <- contrastar_con_fuente(imd_raw, leer_imd_oficial_local())
anotar(sprintf("Contraste con las copias locales de los CSV oficiales (datos/oficial; huellas en manifiesto_oficiales.json): %d valores, %d diferencias.",
               nrow(contraste), sum(!contraste$coincide)))
if (CONTRASTAR_EN_LINEA) {
  contrastar_con_fuente(imd_raw)
  anotar("Nueva instantánea del catálogo del portal (la usa la tabla de procedencia): ", consultar_catalogo_portal())
}

imd <- limpiar_imd(imd_raw)
ctx <- readr::read_csv(file.path(DIR_DATOS, "imd_contexto_2025.csv"), show_col_types = FALSE)
par <- readr::read_csv(file.path(DIR_DATOS, "parametros_modelo.csv"), show_col_types = FALSE)
carriles <- readr::read_csv(file.path(DIR_DATOS, "carriles_tf5.csv"), show_col_types = FALSE)
tp  <- readr::read_csv(file.path(DIR_DATOS, "transporte_publico_viajeros.csv"), show_col_types = FALSE)
pob <- readr::read_csv(file.path(DIR_DATOS, "poblacion_tenerife.csv"), show_col_types = FALSE)
esc_dem <- readr::read_csv(file.path(DIR_DATOS, "escenarios_demanda.csv"), show_col_types = FALSE)

# ---- 2. Descriptivo -----------------------------------------------------------
anotar("== 2. Qué dicen los aforos anuales ==")
ev <- resumen_evolucion(imd)
guardar_tabla(ev, "evolucion_imd_2019_2025")
top <- imd |> filter(anio == 2025) |> slice_max(imd_total, n = 1)
anotar(sprintf("Máximo 2025: %s, %s veh/día.", top$etiqueta, num_es(top$imd_total)))
for (i in seq_len(nrow(ev))) if (ev$estacion_id[i] %in% c(93, 97, 99, 103, 111, 123))
  anotar(sprintf("  %-20s 2019: %7s  2025: %7s  (%s%s; %s%s anual)", ev$etiqueta[i], num_es(ev$imd_2019[i]),
                 num_es(ev$imd_2025[i]), ifelse(ev$var_2019_2025[i] >= 0, "+", ""),
                 pct_es(ev$var_2019_2025[i], 0.1), ifelse(ev$tcam_2019_2025[i] >= 0, "+", ""), pct_es(ev$tcam_2019_2025[i], 0.01)))
crec_pob <- (pob$poblacion[pob$anio == max(pob$anio)] / pob$poblacion[pob$anio == min(pob$anio)])^(1 / (max(pob$anio) - min(pob$anio))) - 1
anotar(sprintf("Población de Tenerife (INE, Censo anual, 1 de enero): %s (%d) -> %s (%d): %s anual.",
               num_es(pob$poblacion[pob$anio == min(pob$anio)]), min(pob$anio), num_es(pob$poblacion[pob$anio == max(pob$anio)]),
               max(pob$anio), pct_es(crec_pob, 0.01)))
pos <- which(rev(ESTACIONES_TF5$etiqueta) == "Ermita Cruz Chica")
tramo_obra <- list(ymin = pos - 0.5, ymax = pos + 0.5,
                   texto = "Tramo de la obra del tercer carril\n(solo hacia Santa Cruz)")
guardar_grafico(grafico_perfil_corredor(imd, 2025, tramo_obra), "g01_perfil_corredor_2025", 9, 6.4)
guardar_grafico(grafico_evolucion(imd), "g02_evolucion_imd", 9, 7.6)
guardar_grafico(grafico_alternativas(imd, ctx), "g03_tf5_vs_alternativas", 9, 6.2)
guardar_grafico(grafico_calidad(imd, flags), "g04_calidad_datos", 9, 6.6)
guardar_grafico(grafico_tp_vs_tf5(imd, tp), "g10_transporte_publico_vs_tf5", 9, 5.8)
idx_titsa <- with(tp[tp$operador == "TITSA", ], viajeros[anio == 2025] / viajeros[anio == 2019])
anotar(sprintf("Viajeros TITSA 2025 vs 2019: +%s (x%s).", pct_es(idx_titsa - 1), num_es(idx_titsa, 0.01)))

# ---- 3. Carriles (catálogo oficial) y margen de capacidad --------------------
anotar("== 3. Carriles y margen de capacidad (k crítico) ==")
car <- leer_carriles_json()
cs  <- carriles_por_sentido(car)
cc  <- contrastar_carriles(cs, carriles)
guardar_tabla(cs, "carriles_desde_json")
guardar_tabla(cc, "contraste_carriles_json_csv")
anotar(sprintf("Catálogo oficial de carriles (JSON, %d estaciones, %d carriles): coincide con carriles_tf5.csv en %d de %d sentidos.",
               n_distinct(car$estacion_id), nrow(car), sum(cc$coincide, na.rm = TRUE), sum(!is.na(cc$coincide))))
c82 <- cs |> filter(estacion_id == 82, sentido == "descendente")
anotar(sprintf("  Túnel 3 de Mayo hacia Santa Cruz solo afora carriles bus (%s): explica su asimetría extrema (regla R9).", c82$descripcion))
kc <- calcular_k_critico(imd, carriles, par)
guardar_tabla(kc, "k_critico_2025")
carga <- kc |> mutate(imd_por_carril = imd_dir / carriles) |>
  select(estacion_id, etiqueta, orden, sentido, carriles, imd_dir, imd_por_carril,
         k_crit_min, k_crit_cen, k_crit_max) |>
  arrange(sentido, orden)
guardar_tabla(carga, "carga_por_carril_2025")
for (i in seq_len(nrow(carga)))
  anotar(sprintf("  %-20s %-11s %d carriles  IMD %7s  por carril %6s  k_crit %s",
                 carga$etiqueta[i], carga$sentido[i], carga$carriles[i], num_es(carga$imd_dir[i]),
                 num_es(carga$imd_por_carril[i]), pct_es(carga$k_crit_cen[i], 0.1)))
guardar_grafico(grafico_k_critico(kc, par), "g05_k_critico", 9, 6.4)

# ---- 4. Aforos horarios oficiales (2024-2026) ---------------------------------
anotar("== 4. Aforos horarios por carril ==")
if (DESCARGAR_HORARIOS) guardar_tabla(descargar_horarios_oficiales(), "descarga_horarios_oficiales")
fest <- readr::read_csv(file.path(DIR_DATOS, "festivos_canarias.csv"), show_col_types = FALSE)
meta_h <- metadatos_horarios()
guardar_tabla(meta_h, "horarios_procedencia")
hp <- preparar_horarios(leer_horarios(), car, fest)
anotar(sprintf("Registros horarios TF-5: %s filas, %d meses (%s a %s), de los extractos de los TXT oficiales (huella SHA-256 de cada TXT registrada al descargarlo).",
               num_es(nrow(hp)), n_distinct(hp$mes), min(hp$mes), max(hp$mes)))
val_h <- validar_horarios(hp, cs, imd_raw)
guardar_tabla(val_h, "validacion_horarios")
res_val_h <- val_h |> group_by(regla, gravedad) |> summarise(casos = n(), filas = sum(filas), .groups = "drop")
for (i in seq_len(nrow(res_val_h)))
  anotar(sprintf("  %-42s %-6s %3d casos, %s filas", res_val_h$regla[i], res_val_h$gravedad[i], res_val_h$casos[i], num_es(res_val_h$filas[i])))

sd <- agregar_por_sentido(hp, cs)
dv <- dias_validos(sd)
base_n <- base_nocturna(sd, dv)
fiab <- fiabilidad_velocidad(sd, dv, base_n)
guardar_tabla(fiab, "fiabilidad_velocidad")
sc <- marcar_congestion(sd, dv, base_n) |>
  left_join(fiab |> select(estacion_id, sentido, velocidad_fiable), by = c("estacion_id", "sentido")) |>
  mutate(congestionada = congestionada & velocidad_fiable)
anotar(sprintf("Días laborables válidos (24 h completas, no festivos, sin agosto, total >= 85 %% de la mediana del mes): %s estación-sentido-días.",
               num_es(nrow(dv))))
for (i in which(!fiab$velocidad_fiable))
  anotar(sprintf("  Velocidad no utilizable en %s (%s): %s.",
                 ESTACIONES_TF5$etiqueta[match(fiab$estacion_id[i], ESTACIONES_TF5$estacion_id)], fiab$sentido[i], fiab$motivo[i]))

# Cobertura y calidad por estación, sentido, mes y hora; días atípicos y cambio de hora
cob <- cobertura_calidad(sd, dv)
guardar_tabla(cob, "cobertura_y_calidad")
cob_h <- cobertura_por_hora(sd)
guardar_tabla(cob_h, "cobertura_por_hora")
cob_res <- cob |> group_by(estacion_id, etiqueta, sentido) |>
  summarise(meses = n(), pct_ausente = sum(horas_mes - horas_con_datos) / sum(horas_mes),
            pct_horas_completas = sum(horas_completas) / sum(horas_mes),
            pct_horas_velocidad = sum(horas_velocidad) / sum(horas_mes), dias_validos = sum(dias_validos), .groups = "drop")
anotar("Cobertura de los aforos horarios (24 meses; horas con todos los carriles y con velocidades utilizables):")
for (i in seq_len(nrow(cob_res)))
  anotar(sprintf("  %-20s %-11s %s de horas completas, %s con velocidad, %d días laborables válidos",
                 cob_res$etiqueta[i], cob_res$sentido[i], pct_es(cob_res$pct_horas_completas[i], 0.1),
                 pct_es(cob_res$pct_horas_velocidad[i], 0.1), cob_res$dias_validos[i]))
ch <- cambio_hora(hp)
guardar_tabla(ch, "dias_atipicos_y_cambio_de_hora")
for (i in seq_len(nrow(ch)))
  anotar(sprintf("  %s (%s): marcas horarias distintas: %d; registros duplicados: %d%s%s", format(ch$dia[i], "%d-%m-%Y"),
                 ifelse(ch$laborable[i], "laborable", "fin de semana"), ch$horas_distintas[i], ch$registros_duplicados[i],
                 ifelse(is.na(ch$horas_duplicadas[i]), "", paste0(" (hora ", ch$horas_duplicadas[i], ")")),
                 ifelse(ch$cambio_de_hora[i] == "", "", paste0("; cambio de hora de ", ch$cambio_de_hora[i]))))

perf <- perfil_laborable(sc, 2025)
guardar_tabla(perf, "perfil_horario_laborable_2025")
rc <- resumen_congestion(sc, 2025, fiab)
guardar_tabla(rc, "congestion_diaria_2025")
anotar("Horas congestionadas por día laborable de 2025, en todo el día (>= 60 % de vehículos a menos de 80 km/h y 30 puntos más que de madrugada):")
for (i in which(rc$horas_media > 0.3))
  anotar(sprintf("  %-20s %-11s media %s h, mediana %s (p25-p75 %s-%s); %d de %d días sin cola; suele empezar a las %02d h",
                 rc$etiqueta[i], rc$sentido[i], num_es(rc$horas_media[i], 0.1), num_es(rc$horas_mediana[i]),
                 num_es(rc$horas_p25[i]), num_es(rc$horas_p75[i]), rc$dias_sin_congestion[i], rc$dias_con_velocidad[i],
                 rc$hora_inicio_tipica[i]))
su <- sensibilidad_umbrales(sd, dv, base_n, 2025, fiab = fiab)
guardar_tabla(su, "sensibilidad_umbral_congestion")
anotar("Sensibilidad a la definición de hora congestionada (mediana de horas de cola por día laborable; vehículos lentos >= umbral y + puntos sobre la madrugada):")
for (cs_i in list(c(103, "descendente"), c(99, "ascendente"))) {
  x <- su |> filter(estacion_id == as.numeric(cs_i[1]), sentido == cs_i[2])
  anotar(sprintf("  %-20s %-11s %s", x$etiqueta[1], cs_i[2],
                 paste(sprintf("%s y +%s: %s h, %d %s sin cola", pct_es(x$umbral, 1), num_es(100 * x$exceso),
                               num_es(x$horas_mediana, 0.1), x$dias_sin_congestion,
                               ifelse(x$dias_sin_congestion == 1, "día", "días")), collapse = " · ")))
}
cap <- capacidad_observada(sc, 2025)
guardar_tabla(cap, "capacidad_observada_2025")

# Caudal de descarga de cada cuello (vehículos/hora que pasan cuando hay cola), solo en
# la ventana horaria de cada cola (la misma del horario de la cola y de la validación):
# las horas con cola de otras horas del día son otro fenómeno
HORAS_CASO1 <- 3:12; HORAS_CASO2 <- 11:23
d1_todas <- sc |> filter(anio == 2025, estacion_id == 103, sentido == "descendente", congestionada)
d2_todas <- descarga_en_horas_de_cola(sc, 99, "ascendente", 103)
desc1 <- d1_todas |> filter(hora %in% HORAS_CASO1) |> pull(veh)
desc2 <- d2_todas |> filter(hora %in% HORAS_CASO2) |> pull(veh)
anotar(sprintf("Horas con cola fuera de la ventana de cada caso (no cuentan para la descarga): mañana %d (mediana %s veh/h); tarde %d.",
               sum(!d1_todas$hora %in% HORAS_CASO1), num_es(median(d1_todas$veh[!d1_todas$hora %in% HORAS_CASO1])),
               sum(!d2_todas$hora %in% HORAS_CASO2)))
guardar_tabla(tibble(caso = c("manana_hacia_santa_cruz", "tarde_hacia_el_norte"),
                     medido_en = c("Ermita Cruz Chica hacia Santa Cruz, en sus horas con cola de 3 a 13 h",
                                   "Ermita Cruz Chica hacia el Norte, en las horas con cola en Bomberos La Laguna de 11 a 24 h"),
                     horas = c(length(desc1), length(desc2)),
                     p10 = c(quantile(desc1, 0.1), quantile(desc2, 0.1)), mediana = c(median(desc1), median(desc2)),
                     p90 = c(quantile(desc1, 0.9), quantile(desc2, 0.9))), "caudal_descarga_cuellos")
anotar(sprintf("Descarga con cola: mañana hacia Santa Cruz %s veh/h (p10-p90 %s-%s); tarde hacia el Norte %s (%s-%s).",
               num_es(median(desc1)), num_es(quantile(desc1, 0.1)), num_es(quantile(desc1, 0.9)),
               num_es(median(desc2)), num_es(quantile(desc2, 0.1)), num_es(quantile(desc2, 0.9))))

guardar_grafico(grafico_mapa_congestion(perf, fiab), "g12_mapa_congestion_2025", 9, 8.2)
casos_cuello <- tibble(estacion_id = c(103, 99, 103), sentido = c("descendente", "ascendente", "ascendente"),
                       caso = c("Ermita Cruz Chica, hacia Santa Cruz (2 carriles): cola de mañana",
                                "Bomberos La Laguna, hacia el Norte (3 carriles): cola de tarde",
                                "Ermita Cruz Chica, hacia el Norte (2 carriles): descarga de esa cola"),
                       capacidad = c(median(desc1), NA, median(desc2)))
guardar_grafico(grafico_perfiles_cuello(perf, casos_cuello), "g13_perfiles_cuellos_2025", 9, 8)

# Horario de la cola en cada cuello (2025 y 2026): objetivo de calibración y validación
hc1_25 <- horario_cola(sc, 103, "descendente", 2025, HORAS_CASO1); hc1_26 <- horario_cola(sc, 103, "descendente", 2026, HORAS_CASO1)
hc2_25 <- horario_cola(sc, 99, "ascendente", 2025, HORAS_CASO2);  hc2_26 <- horario_cola(sc, 99, "ascendente", 2026, HORAS_CASO2)
hcol <- bind_rows(resumen_horario(hc1_25, "Mañana hacia Santa Cruz (Ermita Cruz Chica), 2025"),
                  resumen_horario(hc1_26, "Mañana hacia Santa Cruz (Ermita Cruz Chica), 2026"),
                  resumen_horario(hc2_25, "Tarde hacia el Norte (Bomberos La Laguna), 2025"),
                  resumen_horario(hc2_26, "Tarde hacia el Norte (Bomberos La Laguna), 2026"))
guardar_tabla(hcol, "horario_cola")
anotar("Horario de la cola por día laborable (hora en que empieza la primera hora congestionada y acaba la última):")
for (i in seq_len(nrow(hcol)))
  anotar(sprintf("  %s: empieza a las %s (p10-p90 %s-%s) y acaba a las %s (%s-%s); %d de %d días con cola",
                 hcol$cuello[i], hora_txt(hcol$inicio_mediana[i]), hora_txt(hcol$inicio_p10[i]), hora_txt(hcol$inicio_p90[i]),
                 hora_txt(hcol$fin_mediana[i]), hora_txt(hcol$fin_p10[i]), hora_txt(hcol$fin_p90[i]), hcol$dias_con_cola[i], hcol$dias[i]))

# Verificación de afirmaciones de los apuntes con los aforos horarios
hp_ver <- verificar_horas_punta(perf)
guardar_tabla(hp_ver, "verificacion_horas_punta")
dsem <- bind_rows(perfil_por_dia_semana(sc, 99, "ascendente"), perfil_por_dia_semana(sc, 103, "ascendente"))
guardar_tabla(dsem, "verificacion_dia_semana")

# Antes y después: escalonamiento de la ULL (curso 2025-26) y 2026 frente a 2025
est_cmp <- setdiff(EST_CORREDOR, 97)   # Padre Anchieta: sin datos suficientes en 2024-2025
cmp_ull <- comparar_periodos(sc, c("2024-10", "2024-11"), c("2025-10", "2025-11"), estaciones = est_cmp, hp = hp)
meses_comunes <- sprintf("%02d", c(1:7, 9))
cmp_26 <- comparar_periodos(sc, paste0("2025-", meses_comunes), paste0("2026-", meses_comunes), estaciones = est_cmp, hp = hp)
guardar_tabla(cmp_ull, "comparacion_ull_oct_nov_2024_2025")
guardar_tabla(cmp_26, "comparacion_2025_2026_ene_sep")
anotar("Punta de 7 a 9 h, oct-nov 2025 frente a oct-nov 2024 (primeros meses de los horarios escalonados de la ULL):")
for (i in seq_len(nrow(cmp_ull)))
  anotar(sprintf("  %-20s %-11s %+6s veh/día (IC 95 %%: %s a %s; %s)%s", cmp_ull$etiqueta[i], cmp_ull$sentido[i],
                 num_es(cmp_ull$dif[i]), num_es(cmp_ull$ic_inf[i]), num_es(cmp_ull$ic_sup[i]), p_txt(cmp_ull$p_valor[i]),
                 ifelse(cmp_ull$comparable[i], "", sprintf(" · NO COMPARABLE: el reparto entre carriles cambia %s puntos",
                                                           num_es(100 * cmp_ull$cambio_reparto[i], 0.1)))))
anotar("Ene-sep 2026 frente a ene-sep 2025 (sin agosto), horas congestionadas por día:")
for (i in which(!is.na(cmp_26$horas_cong_a) & (cmp_26$horas_cong_a > 0.3 | cmp_26$horas_cong_b > 0.3)))
  anotar(sprintf("  %-20s %-11s %s -> %s h/día (%s); punta 7-9 h %+s veh/día%s",
                 cmp_26$etiqueta[i], cmp_26$sentido[i], num_es(cmp_26$horas_cong_a[i], 0.01), num_es(cmp_26$horas_cong_b[i], 0.01),
                 p_txt(cmp_26$p_valor_cong[i]), num_es(cmp_26$dif[i]), ifelse(cmp_26$comparable[i], "", " · aforador alterado")))
guardar_grafico(grafico_comparacion(cmp_ull, cmp_26), "g14_antes_despues", 10, 6.6)
r93 <- reparto_carriles(hp, 93, "ascendente")
guardar_tabla(r93, "reparto_carriles_campus_guajara_norte")

# Horarios escalonados de la ULL: curso completo (meses lectivos) con julio como control
did <- bind_rows(did_ull(sc, hp) |> mutate(control = "julio"),
                 did_ull(sc, hp, control = list(antes = c("2025-06", "2025-07"), despues = c("2026-06", "2026-07"))) |>
                   mutate(control = "junio y julio"))
guardar_tabla(did, "ull_diferencias_en_diferencias")
did_jj <- did |> filter(control == "junio y julio")
did <- did |> filter(control == "julio")
anotar("Horarios escalonados de la ULL, meses lectivos (oct-nov y feb-may) del curso 2025-26 frente al 2024-25, hacia Santa Cruz:")
for (i in seq_len(nrow(did))) {
  acc <- c(v = 1, cuota = 0.001, cola = 0.01)[[did$variable[i]]]
  anotar(sprintf("  %-20s %-46s antes %s, después %s (%s; IC 95 %% %s a %s); con julio como control: %s (IC 95 %% %s a %s)%s",
                 did$etiqueta[i], did$indicador[i], num_es(did$lectivo_antes[i], acc), num_es(did$lectivo_despues[i], acc),
                 num_es(did$dif_lectivo[i], acc), num_es(did$ic_lectivo_inf[i], acc), num_es(did$ic_lectivo_sup[i], acc),
                 num_es(did$efecto_did[i], acc), num_es(did$ic_inf[i], acc),
                 num_es(did$ic_sup[i], acc), ifelse(isFALSE(did$comparable[i]), " · aforador alterado", "")))
}
anotar(sprintf("  Con junio y julio como control: %s.", paste(sprintf("%s, %s: %s (IC 95 %% %s a %s)", did_jj$etiqueta, did_jj$variable,
                                                                       num_es(did_jj$efecto_did, 0.01), num_es(did_jj$ic_inf, 0.01),
                                                                       num_es(did_jj$ic_sup, 0.01))[did_jj$variable != "cuota"], collapse = "; ")))
anotar("  Aviso: junio y julio de 2026 son posteriores al cierre de los pasos de peatones de la glorieta del Padre Anchieta (20-05-2026), así que no son un control limpio.")
di <- dif_interanual(sc)
guardar_tabla(di, "diferencias_interanuales_por_mes")
guardar_grafico(grafico_dif_interanual(di), "g16_ull_y_pasarela_interanual", 10, 7.6)
pas <- di |> filter(variable == "cola", mes %in% c("2026-06", "2026-07", "2026-09"))
anotar("Horas de cola de la mañana hacia Santa Cruz después de abrir la pasarela del Padre Anchieta (mismo mes de 2025 entre paréntesis; asociación temporal, no un efecto demostrado):")
for (e in unique(pas$etiqueta)) {
  x <- pas |> filter(etiqueta == e)
  anotar(sprintf("  %-20s %s", e, paste(sprintf("%s: %s h (%s)", x$mes, num_es(x$valor, 0.01), num_es(x$valor_antes, 0.01)), collapse = " · ")))
}

# ---- 4b. Procedencia, calidad de las series, balance por tramos y geometría -------
anotar("== 4b. Procedencia de los datos, calidad de las series, balance por tramos y geometría ==")
proc <- procedencia_datos()
guardar_tabla(proc, "procedencia_datos")
ph <- proc |> filter(grepl("^H-", id)); po <- proc |> filter(grepl("^O-", id)); pf <- proc |> filter(grepl("^F-", id))
anotar(sprintf("Procedencia: %d ficheros horarios y %d ficheros oficiales. Iguales (tamaño y fecha) al recurso de la instantánea del catálogo del portal del 16-10-2026: %d y %d; copias íntegras (SHA-256): %d y %d; totales de cada extracto = sumas de control registradas del TXT original: %d de %d meses.",
               nrow(ph), nrow(po), sum(grepl("^Coincide", ph$contraste_catalogo)), sum(grepl("^Coincide", po$contraste_catalogo)),
               sum(grepl("^Copia íntegra", ph$integridad)), sum(grepl("^Copia íntegra", po$integridad)),
               sum(grepl("^Totales", ph$conservacion_totales)), nrow(ph)))
for (i in which(!grepl("^Coincide", c(ph$contraste_catalogo, po$contraste_catalogo))))
  anotar(sprintf("  Distinto o ausente en el catálogo: %s", c(ph$recurso, po$recurso)[i]))
for (i in seq_len(nrow(pf))) anotar(sprintf("  Hueco registrado: %s (%s). %s", pf$recurso[i], pf$conjunto[i], pf$contraste_catalogo[i]))
anotar(sprintf("  Cabecera de los TXT horarios: %s.", if (isTRUE(attr(proc, "cabecera_unica"))) "la misma en todos los meses" else "CAMBIA entre meses"))
anotar("  Las huellas prueban que las copias no han cambiado desde la descarga (integridad), no la autenticidad del origen. Esta ejecución de main.R no vuelve a descargar los originales; el contraste de los originales descargados con el portal está en docs/contraste_fuentes/.")
cons <- sum(hp$veh[hp$estacion_id %in% EST_CORREDOR & hp$tipo %in% "principal"]) - sum(sd$veh)
anotar(sprintf("Conservación al sumar los carriles principales por estación, sentido y hora: diferencia de %s vehículos.", num_es(cons)))
ser <- series_con_banderas(hp, sd, dv, ch)
readr::write_csv(ser, file.path(DIR_TABLAS, "horarios_corredor_con_banderas.csv.gz"), na = "")
anotar(sprintf("Serie depurada con banderas de calidad (horarios_corredor_con_banderas.csv.gz; los extractos originales no se tocan): %s horas de estación y sentido; usadas en el análisis %s (%s); imputadas: 0.",
               num_es(nrow(ser)), num_es(sum(ser$usado_en_el_analisis)), pct_es(mean(ser$usado_en_el_analisis), 0.1)))
rban <- resumen_banderas(ser)
guardar_tabla(rban, "banderas_resumen")
with(rban[is.na(rban$estacion_id), ], anotar(sprintf("Banderas de calidad en el corredor (horas marcadas de %s; se solapan): %s.", num_es(horas_totales[1]),
     paste(sprintf("%s %s (%s)", bandera, num_es(horas_marcadas), pct_es(parte, 0.1)), collapse = "; "))))
ti <- tasa_imputacion(sd)
guardar_tabla(ti, "cobertura_e_imputacion_por_estacion_mes_hora")
sdep <- sensibilidad_depuracion(sd, fiab, list(c(103, "descendente", HORAS_CASO1), c(99, "ascendente", HORAS_CASO2)))
guardar_tabla(sdep, "sensibilidad_depuracion")
anotar(sprintf("Sensibilidad a la depuración de los días (2025; horas de cola por día laborable en la ventana del caso, de %d a %d h hacia Santa Cruz y de %d a %d h hacia el Norte, y descarga mediana):",
               min(HORAS_CASO1), max(HORAS_CASO1) + 1, min(HORAS_CASO2), max(HORAS_CASO2) + 1))
for (i in seq_len(nrow(sdep)))
  anotar(sprintf("  %s · %s (%s): %d días, mediana %s h (media %s), descarga %s veh/h; horas imputadas %s",
                 sdep$variante[i], sdep$etiqueta[i], sdep$sentido[i], sdep$dias[i], num_es(sdep$horas_cola_mediana[i], 0.1),
                 num_es(sdep$horas_cola_media[i], 0.01), num_es(sdep$descarga_mediana[i]), pct_es(sdep$tasa_imputacion[i], 0.1)))
bt <- balance_tramos(sc)
guardar_tabla(bt$resumen, "balance_por_tramos")
guardar_tabla(bt$por_hora, "balance_por_tramos_hora")
anotar("Balance entre estaciones (pares consecutivos y Ermita Cruz Chica -> Campus Guajara; días laborables con las 24 h en las dos; diferencia de caudal = entradas - salidas por los ramales):")
for (i in seq_len(nrow(bt$resumen))) with(bt$resumen[i, ],
  anotar(sprintf("  %-11s %s: %s veh/día (p10-p90 %s a %s; CV %s; %s días; caudales negativos: %d). %s", sentido, tramo,
                 num_es(neto_dia_mediana), num_es(neto_dia_p10), num_es(neto_dia_p90),
                 ifelse(is.na(cv_neto_dia), "no aplica", num_es(cv_neto_dia, 0.01)),
                 ifelse(is.na(dias_completos), "0", as.character(dias_completos)), flujos_negativos, lectura)))
geo <- readr::read_csv(file.path(DIR_DATOS, "geometria_tramos.csv"), show_col_types = FALSE)
geo_cap <- geometria_capacidades(geo, cs, cap, val_h, "2026-07-02")
guardar_tabla(geo_cap, "geometria_y_capacidad")
pend <- geo_cap |> filter(estado != "confirmado")
anotar(sprintf("Geometría (catálogo de carriles de 2026 frente al inventario del PTEOSVAM de 2006): %d estación-sentidos confirmados y %d pendientes de confirmación: %s.",
               sum(geo_cap$estado == "confirmado"), nrow(pend),
               paste(sprintf("%s hacia %s (%d aforados, %d en el inventario)", pend$etiqueta, ifelse(pend$sentido == "ascendente", "el Norte", "Santa Cruz"),
                             pend$carriles_aforados, pend$carriles_inventario_2006), collapse = "; ")))
kc_geo <- calcular_k_critico(imd, geo |> select(estacion_id, sentido, carriles = carriles_inventario_2006), par) |>
  select(estacion_id, etiqueta, sentido, carriles_inventario_2006 = carriles, k_crit_central_inventario = k_crit_cen) |>
  left_join(kc |> select(estacion_id, sentido, carriles_aforados = carriles, k_crit_central_aforados = k_crit_cen), by = c("estacion_id", "sentido"))
guardar_tabla(kc_geo, "k_critico_geometria_alternativa")
ug <- uso_geometria(geo_cap)
guardar_tabla(ug, "uso_de_la_geometria")
anotar(sprintf("Uso de la geometría: %d cálculos que dependen del número de carriles, todos con fuente o supuesto explícito: %s.",
               nrow(ug), ifelse(all(ug$tiene_procedencia_o_supuesto), "sí", "NO")))
cc_campos <- correspondencia_campos()
guardar_tabla(cc_campos, "correspondencia_de_campos")
anotar(sprintf("Correspondencia de campos: %d campos de los tres ficheros oficiales, cada uno con su definición del diccionario oficial y su nombre en el proyecto.",
               nrow(cc_campos)))
cpo <- contraste_publicacion_original()
guardar_tabla(cpo, "contraste_publicacion_original")
anotar(sprintf("Contraste con la publicación original (catálogo nacional datos.gob.es, consultado el %s): %d de %d recursos de 2025 coinciden en URL, identificador, nombre y licencia; la fecha de modificación del conjunto difiere %s h entre los dos catálogos.",
               format(as.Date(cpo$consultado[1]), "%d-%m-%Y"), sum(cpo$resultado == "coincide"), nrow(cpo), num_es(cpo$diferencia_modificacion_h[1], 0.1)))
# Días atípicos: motivo de cada exclusión y marcas de días usados que pueden ser atípicos
da <- dias_atipicos(sd, dv, fest, ch)
guardar_tabla(da, "dias_atipicos")
rda <- resumen_dias_atipicos(da)
guardar_tabla(rda, "dias_atipicos_resumen")
for (k in c(103, 99)) {
  x <- da |> filter(estacion_id == k, sentido == ifelse(k == 103, "descendente", "ascendente"))
  anotar(sprintf("Días laborables de %s (%s): %d usados y %d excluidos (%s); de los usados, %d marcados como posibles atípicos (puentes %d, Navidad %d, Semana Santa %d, punta anómala %d). Incidentes y obras: el Cabildo publica un registro de incidencias en carreteras que no se ha incorporado (matriz de lagunas, D09); lluvia: sin dato incorporado (D15).",
                 x$etiqueta[1], x$sentido[1], sum(x$estado == "usado"), sum(x$estado == "excluido"),
                 paste(sprintf("%s: %d", names(table(x$motivo_exclusion[x$estado == "excluido"])), table(x$motivo_exclusion[x$estado == "excluido"])), collapse = "; "),
                 sum(x$estado == "usado" & nzchar(x$marca)), sum(x$estado == "usado" & x$puente), sum(x$estado == "usado" & x$navidad),
                 sum(x$estado == "usado" & x$semana_santa), sum(x$punta_anomala)))
}
ssa <- sensibilidad_sin_atipicos(sc, da)
guardar_tabla(ssa, "sensibilidad_sin_dias_atipicos")
anotar("Sensibilidad a los días atípicos (2025; horas de cola media y descarga mediana):")
for (i in seq_len(nrow(ssa)))
  anotar(sprintf("  %s · %s (%s): %d días, %s h de media, descarga %s veh/h", ssa$variante[i], ssa$etiqueta[i], ssa$sentido[i], ssa$dias[i],
                 num_es(ssa$horas_cola_media[i], 0.01), num_es(ssa$descarga_mediana[i])))

# =============================================================================
# QUÉ ESTIMAMOS
# =============================================================================

# Perfil híbrido de cada cuello: aforos de 2025 fuera de la ventana de la punta
perf103d <- perf |> filter(estacion_id == 103, sentido == "descendente") |> arrange(hora)
perf103a <- perf |> filter(estacion_id == 103, sentido == "ascendente") |> arrange(hora)
perf99a  <- perf |> filter(estacion_id == 99, sentido == "ascendente") |> arrange(hora)
obs1 <- list(veh_hora = perf103d$veh, ventana = ventana_punta(perf103d$prob_congestion))
obs2 <- list(veh_hora = perf103a$veh, ventana = ventana_punta(perf99a$prob_congestion))
V1 <- sum(obs1$veh_hora); V2 <- sum(obs2$veh_hora)
anotar(sprintf("Perfil híbrido: ventana de la punta %02d-%02d h (mañana hacia Santa Cruz) y %02d-%02d h (tarde hacia el Norte); fuera de ella la demanda es el caudal aforado.",
               obs1$ventana[1], obs1$ventana[2], obs2$ventana[1], obs2$ventana[2]))
for (o in list(list("mañana", obs1), list("tarde", obs2))) {
  pr <- perfil_hibrido(o[[2]]$veh_hora, o[[2]]$ventana, mean(o[[2]]$ventana) * 60, 50)
  anotar(sprintf("  Punta elástica (joroba) de la %s: %s veh de %s aforados en la ventana (%s del día).", o[[1]], num_es(pr$vehiculos_joroba),
                 num_es(sum(o[[2]]$veh_hora[(o[[2]]$ventana[1] + 1):o[[2]]$ventana[2]])), pct_es(pr$vehiculos_joroba / sum(o[[2]]$veh_hora), 0.1)))
}

# Parámetros comunes de los dos casos (la cuota de la hora punta y la nocturna salen de los aforos)
par_cal <- par |>
  fijar_parametro("c_carril", 1850, 1950, 2100,
                  descripcion = "Capacidad por carril antes de la caída. Rango ajustado a los aforos horarios 2025: el caudal horario máximo por carril en el tramo de 2 carriles es 1.887-1.940 veh/h (p99 1.821-1.885)",
                  fuente = "Aforos horarios 2025 del Cabildo (tabla capacidad_observada_2025) y HCM 6ª ed.") |>
  fijar_parametro("k_dir", 0.075, 0.10, 0.13,
                  descripcion = "Fracción de la demanda diaria del sentido en su hora punta (solo para el perfil sintético del Bus-VAO). Rango ampliado: los aforos dan 0,072-0,086 de caudal (en tramos congestionados es un mínimo)") |>
  fijar_parametro("sigma_punta", 40, 60, 120,
                  descripcion = "Anchura de la punta en el perfil sintético del Bus-VAO (desviación típica de la joroba gaussiana)")
par_h <- par_cal |>
  filter(!parametro %in% c("k_dir", "cuota_noche")) |>
  fijar_parametro("sigma_punta", 20, 50, 120,
                  descripcion = "Anchura de la joroba de la punta (desviación típica, perfil híbrido). Su tamaño sale de los aforos; la anchura se calibra con la duración y el horario de la cola",
                  fuente = "Calibración con los aforos horarios 2025 (tabla horario_cola)")

# ---- 5. Caso 1: punta de mañana hacia Santa Cruz (donde actúa el tercer carril)
anotar("== 5. Caso 1: Los Rodeos-Guamasa hacia Santa Cruz (tercer carril) ==")
r103d <- rc |> filter(estacion_id == 103, sentido == "descendente")
# Objetivos de calibración con todos los días laborables válidos de 2025: duración, inicio y
# fin de la cola (rango intercuartílico ± 30 min) y descarga (como parámetro: p10-p90 del
# caudal horario con cola; medida como en el aforo: p25-p75 de la mediana de cada día)
od1_25 <- observado_diario(sc, 103, 103, "descendente", HORAS_CASO1, 2025)
obj1 <- objetivo_desde_dias(od1_25$dias, od1_25$horas)

# Holgura del tramo siguiente estimada con caudales horarios
holg <- holgura_observada(sc)
holg_h <- holg |> filter(restrictiva) |> distinct(dia, hora, .keep_all = TRUE)
holg_hora <- holg_h |> group_by(hora) |> summarise(horas = n(), p10 = quantile(holgura, 0.1), mediana = median(holgura),
                                                   p90 = quantile(holgura, 0.9), sin_holgura = mean(holgura <= 0),
                                                   estacion_restrictiva = names(which.max(table(estacion_abajo))),
                                                   entradas_netas = median(entradas_netas), C_abajo = median(C_abajo), .groups = "drop")
guardar_tabla(holg_hora, "holgura_aguas_abajo_por_hora")
hq <- as.numeric(quantile(holg_h$holgura, c(0.1, 0.5, 0.9)))
HH <- matriz_holgura_horaria(holg_h)
anotar(sprintf("Holgura estimada del tramo siguiente (Bomberos/Campus Guajara) en las %d horas con cola: mediana %s (p10-p90 %s a %s); sin holgura en el %s de las horas.",
               nrow(holg_h), pct_es(hq[2], 0.1), pct_es(hq[1], 0.1), pct_es(hq[3], 0.1), pct_es(mean(holg_h$holgura <= 0))))
for (hh in 6:8) with(holg_hora[holg_hora$hora == hh, ],
  anotar(sprintf("  a las %02d h: mediana %s (p10-p90 %s a %s), sin holgura el %s de los días", hh, pct_es(mediana, 0.1),
                 pct_es(p10, 0.1), pct_es(p90, 0.1), pct_es(sin_holgura))))
# Con la capacidad de abajo (p99) estimada en 2025: en 2026 solo cambian los caudales, no la capacidad
cap_abajo_2025 <- holg |> distinct(estacion_abajo, C_abajo) |> (\(x) stats::setNames(x$C_abajo, x$estacion_abajo))()
holg26 <- holgura_observada(sc, anios = 2026, capacidad = cap_abajo_2025) |> filter(restrictiva, format(dia, "%m") %in% c("06", "07", "09")) |>
  distinct(dia, hora, .keep_all = TRUE)
holg26_hora <- holg26 |> group_by(hora) |> summarise(horas = n(), mediana = median(holgura), sin_holgura = mean(holgura <= 0),
                                                     capacidad_abajo = "p99 de los caudales de 2025 (misma que holgura_aguas_abajo_por_hora)", .groups = "drop")
guardar_tabla(holg26_hora, "holgura_aguas_abajo_jun_sep_2026")
for (hh in intersect(6:8, holg26_hora$hora[holg26_hora$horas >= 10])) with(holg26_hora[holg26_hora$hora == hh, ],
  anotar(sprintf("  después de abrir la pasarela (jun, jul y sep de 2026), a las %02d h: mediana %s, sin holgura el %s de los días (%d horas con cola)", hh,
                 pct_es(mediana, 0.1), pct_es(sin_holgura), horas)))

par_c1 <- par_h |>
  fijar_parametro("t0_punta", 360, 420, 540,
                  descripcion = "Centro de la joroba de la punta de la mañana (minuto del día, 06:00-09:00). La calibración selecciona los valores con los que la cola empieza y acaba a las horas medidas",
                  fuente = "Aforos horarios 2025 (tabla horario_cola)") |>
  fijar_parametro("holgura_aguas_abajo", max(0, hq[1]), max(0, hq[2]), max(0, hq[3]),
                  descripcion = "Holgura del tramo siguiente estimada con los caudales horarios de 2025, hora a hora: cada simulación toma un mismo cuantil de la distribución de cada hora (aquí, p10, mediana y p90 del conjunto de horas con cola; los valores negativos cuentan como 0)",
                  fuente = "Aforos horarios 2025 (tabla holgura_aguas_abajo_por_hora)")

# Especificación de la descarga elegida por validación cruzada en 2025 (2026 no interviene):
# propagación de la cola de abajo, descarga dependiente de la hora, mezcla de pesados y
# descarga medida como en el aforo, con la regla de elegir_especificacion()
rej1 <- rejilla_especificaciones("manana_hacia_santa_cruz", sc, 103, 103, "descendente", HORAS_CASO1, par_c1, V1, 2, obs1, HH, n = N_REJILLA,
                                 holgura_args = list(cuello = 103, abajo = c(99, 93), sent = "descendente"))
el1 <- elegir_especificacion(rej1) |> mutate(caso = "manana_hacia_santa_cruz")
esp1 <- especificacion_elegida(el1, sc, 103, 103, "descendente", HORAS_CASO1)
obs1$especificacion <- esp1$especificacion; obj1$medida_descarga <- esp1$medida_descarga
# Tabla de parámetros documentada: la del muestreo más la equivalencia de pesados si la especificación la usa
par_c1_doc <- if (!is.null(obs1$especificacion$cuota_pesados)) fila_equivalencia_pesados(par_c1) else par_c1
guardar_tabla(par_c1_doc, "parametros_usados_caso1")
anotar(sprintf("Especificación de la descarga de la mañana (elegida por validación cruzada en 2025 entre %d variantes): %s.", nrow(el1), esp1$descripcion))
if (!is.null(esp1$especificacion$factor_descarga))
  anotar(sprintf("  Factor de la descarga por hora (frente a las %02d h): %s.", esp1$especificacion$hora_referencia,
                 paste(sprintf("%02d h %s", which(esp1$especificacion$factor_descarga < 1) - 1,
                               num_es(esp1$especificacion$factor_descarga[esp1$especificacion$factor_descarga < 1], 0.001)), collapse = ", ")))

mc1_todo <- simular_montecarlo(par_c1, V1, 2, TRUE, n = N_SIMULACIONES[1], evaluar_si = selector_calibraciones(obj1),
                               holgura_horaria = HH, perfil_obs = obs1, horas_holgura = 7:9)
mc1 <- calibrar_montecarlo(mc1_todo, "aforos", obj1)
res1 <- resumir_montecarlo(mc1)
guardar_tabla(res1, "montecarlo_caso1_manana_hacia_santa_cruz")
caso1 <- sprintf("Ermita Cruz Chica (Los Rodeos-Guamasa), hacia Santa Cruz: %s veh/día laborable en 2 carriles", num_es(V1))
anotar(caso1)
anotar(sprintf("Objetivos de calibración: cola de %s-%s h/día que empieza entre las %s y las %s y acaba entre las %s y las %s; descarga %s de %s-%s veh/h. Combinaciones compatibles: %d de %s (%s).",
               num_es(obj1$duracion[1], 0.1), num_es(obj1$duracion[2], 0.1), hora_txt(obj1$inicio[1]), hora_txt(obj1$inicio[2]),
               hora_txt(obj1$fin[1]), hora_txt(obj1$fin[2]), if (obj1$medida_descarga == "como_aforo") "medida como en el aforo" else "(parámetro)",
               num_es(ventana_descarga(obj1)[1]), num_es(ventana_descarga(obj1)[2]),
               mc1$n_validas, num_es(N_SIMULACIONES[1]), pct_es(mc1$n_validas / N_SIMULACIONES[1], 0.1)))
d1 <- mc1$draws
anotar(sprintf("  Situación actual simulada: espera máxima %s min (p10-p90 %s-%s), espera media en la hora punta %s min, cola %s h (de %s a %s).",
               num_es(median(d1$base_espera_max), 0.1), num_es(quantile(d1$base_espera_max, 0.1), 0.1),
               num_es(quantile(d1$base_espera_max, 0.9), 0.1), num_es(median(d1$base_media_punta), 0.1),
               num_es(median(d1$base_horas_cola), 0.1), hora_txt(median(d1$base_inicio)), hora_txt(median(d1$base_fin))))
anotar(sprintf("  Medida como en los aforos (horas enteras con >= 60 %% de vehículos en cola): %s h, de las %02.0f a las %02.0f h (mediana).",
               num_es(median(d1$base_horas_aforo), 0.1), median(d1$base_inicio_aforo), median(d1$base_fin_aforo)))
for (i in seq_len(nrow(res1)))
  anotar(sprintf("  %s mediana %4s  (p10 %4s, p90 %4s)", rellenar(res1$etiqueta[i], 42), pct_es(res1$mediana[i]),
                 pct_es(res1$p10[i]), pct_es(res1$p90[i])))
sc1 <- sensibilidad_calibracion(mc1_todo, obj1)
guardar_tabla(sc1, "sensibilidad_calibracion_caso1")
sens <- sensibilidad(mc1, "tercer_carril_largo")
guardar_tabla(sens, "sensibilidad_tercer_carril")
anotar("Parámetros que más pesan en el resultado del tercer carril a 10 años (rho de Spearman):")
for (i in seq_len(min(4, nrow(sens)))) anotar(sprintf("  %-24s %+.2f", sens$parametro[i], sens$rho[i]))

curva1 <- curva_holgura(mc1)
guardar_tabla(curva1, "tercer_carril_segun_holgura")
c0 <- curva1 |> filter(holgura == 0)
c15 <- curva1 |> filter(abs(holgura - 0.15) < 1e-9)
anotar(sprintf("Tercer carril según la holgura de abajo: con 0 %% (paso por Padre Anchieta con 2 carriles efectivos) %s el 1er año; con 15 %% %s.",
               pct_es(c0$mediana[c0$horizonte == "corto"]), pct_es(c15$mediana[c15$horizonte == "corto"])))
guardar_grafico(grafico_holgura(curva1, holg_hora), "g15_tercer_carril_holgura", 9, 5.6)
# Sensibilidad de la holgura: capacidad de abajo, ramales desconocidos, cuello desplazado
# y carriles del inventario de 2006 en el tramo siguiente (submuestra de 300 combinaciones)
inv1 <- geo_cap |> filter(sentido == "descendente", estacion_id %in% c(99, 93), carriles_inventario_2006 != carriles_aforados)
vh1 <- variantes_holgura(sc, 103, c(99, 93), "descendente", carriles_inventario = stats::setNames(inv1$carriles_inventario_2006, inv1$estacion_id))
sh1 <- sensibilidad_holgura(mc1, vh1, "manana_hacia_santa_cruz", 6:8, duracion = obj1$duracion)
guardar_tabla(sh1$holgura, "sensibilidad_holgura_caso1")
guardar_tabla(sh1$resultados, "sensibilidad_holgura_resultados_caso1")
anotar("Sensibilidad de la holgura del tramo siguiente (mañana; holgura mediana a las 7 h y tercer carril el 1er año, mediana y p10-p90):")
for (v in names(vh1)) {
  h7 <- sh1$holgura |> filter(variante == v, hora == 7); r <- sh1$resultados |> filter(variante == v, escenario == "tercer_carril_corto")
  anotar(sprintf("  %s: %s a las 7 h; tercer carril %s (%s-%s); cola de %s h hoy (en el rango medido en 2025 en el %s de las combinaciones) y %s h con el tercer carril%s",
                 v, pct_es(h7$holgura_mediana, 0.1), pct_es(r$mediana), pct_es(r$p10), pct_es(r$p90), num_es(r$horas_cola_hoy, 0.1),
                 pct_es(r$parte_cola_hoy_en_rango_medido), num_es(r$horas_cola_con_tercer_carril, 0.1),
                 ifelse(is.na(r$cola_restante_limitada_por_abajo), "", sprintf(", marcada por el tramo siguiente en el %s de sus minutos (cuello desplazado)",
                                                                                pct_es(r$cola_restante_limitada_por_abajo)))))
}
guardar_grafico(grafico_montecarlo(res1, caso1, mc1$n_validas,
                                   "Punta de mañana hacia Santa Cruz: reducción de la demora frente a no hacer nada",
                                   "la duración, el horario de la cola y la descarga medidos en 2025"), "g07_montecarlo_caso1", 9, 7)
i_central <- d1$sim[which.min(abs(d1$base_demora_vh - median(d1$base_demora_vh)))]
p_central <- as.list(mc1_todo$draws[mc1_todo$draws$sim == i_central, ])
guardar_grafico(grafico_colas_ejemplo(p_central, V1, 2, caso1, reloj = TRUE, obs = obs1,
                                      holgura_t = holgura_minutos(HH, p_central$holgura_cuantil)),
                "g06_colas_escenarios", 9, 7.8)

# ---- 6. Caso 2: regreso de tarde hacia el Norte --------------------------------
anotar("== 6. Caso 2: regreso hacia el Norte (cuello de Bomberos-Ermita Cruz Chica, de 3 a 2 carriles) ==")
r99a <- rc |> filter(estacion_id == 99, sentido == "ascendente")
od2_25 <- observado_diario(sc, 99, 103, "ascendente", HORAS_CASO2, 2025)
obj2 <- objetivo_desde_dias(od2_25$dias, od2_25$horas)
# Holgura del tramo siguiente hacia el Norte: La Matanza (2 carriles) en las horas con
# cola en Bomberos La Laguna. Solo sirve para un tercer carril hacia el Norte en Los
# Rodeos-Guamasa, que no está proyectado
holg2 <- holgura_observada(sc, cuello = 103, abajo = 111, sent = "ascendente", est_cola = 99)
holg2_h <- holg2 |> filter(restrictiva) |> distinct(dia, hora, .keep_all = TRUE)
holg2_hora <- holg2_h |> group_by(hora) |> summarise(horas = n(), p10 = quantile(holgura, 0.1), mediana = median(holgura),
                                                     p90 = quantile(holgura, 0.9), sin_holgura = mean(holgura <= 0),
                                                     entradas_netas = median(entradas_netas), C_abajo = median(C_abajo), .groups = "drop")
guardar_tabla(holg2_hora, "holgura_la_matanza_por_hora")
hq2 <- as.numeric(quantile(holg2_h$holgura, c(0.1, 0.5, 0.9)))
HH2 <- matriz_holgura_horaria(holg2_h)
anotar(sprintf("Holgura de La Matanza (2 carriles) hacia el Norte en las %s horas con cola en Bomberos: mediana %s (p10-p90 %s a %s).",
               num_es(nrow(holg2_h)), pct_es(hq2[2], 0.1), pct_es(hq2[1], 0.1), pct_es(hq2[3], 0.1)))
for (hh in 14:16) with(holg2_hora[holg2_hora$hora == hh, ],
  anotar(sprintf("  a las %02d h: mediana %s (p10-p90 %s a %s), sin holgura el %s de los días", hh, pct_es(mediana, 0.1),
                 pct_es(p10, 0.1), pct_es(p90, 0.1), pct_es(sin_holgura))))
par_c2 <- par_h |>
  fijar_parametro("t0_punta", 780, 900, 1080,
                  descripcion = "Centro de la joroba de la punta de la tarde (minuto del día, 13:00-18:00). La calibración selecciona los valores con los que la cola empieza y acaba a las horas medidas",
                  fuente = "Aforos horarios 2025 (tabla horario_cola)") |>
  fijar_parametro("holgura_aguas_abajo", max(0, hq2[1]), max(0, hq2[2]), max(0, hq2[3]),
                  descripcion = "Holgura de La Matanza (2 carriles) hacia el Norte estimada con los caudales horarios de 2025 en las horas con cola en Bomberos La Laguna; solo afecta al tercer carril hipotético hacia el Norte y al límite de la regulación de accesos",
                  fuente = "Aforos horarios 2025 (tabla holgura_la_matanza_por_hora)")
rej2 <- rejilla_especificaciones("tarde_hacia_el_norte", sc, 99, 103, "ascendente", HORAS_CASO2, par_c2, V2, 2, obs2, HH2, n = N_REJILLA,
                                 holgura_args = list(cuello = 103, abajo = 111, sent = "ascendente", est_cola = 99))
el2 <- elegir_especificacion(rej2) |> mutate(caso = "tarde_hacia_el_norte")
esp2 <- especificacion_elegida(el2, sc, 99, 103, "ascendente", HORAS_CASO2)
obs2$especificacion <- esp2$especificacion; obj2$medida_descarga <- esp2$medida_descarga
par_c2_doc <- if (!is.null(obs2$especificacion$cuota_pesados)) fila_equivalencia_pesados(par_c2) else par_c2
guardar_tabla(par_c2_doc, "parametros_usados_caso2")
anotar(sprintf("Especificación de la descarga de la tarde (elegida por validación cruzada en 2025 entre %d variantes): %s.", nrow(el2), esp2$descripcion))
caso2 <- sprintf("Ermita Cruz Chica, hacia el Norte: %s veh/día laborable en 2 carriles (la cola se forma en Bomberos La Laguna, con 3)", num_es(V2))
anotar(caso2)
mc2_todo <- simular_montecarlo(par_c2, V2, 2, TRUE, n = N_SIMULACIONES[2], evaluar_si = selector_calibraciones(obj2),
                               holgura_horaria = HH2, perfil_obs = obs2, horas_holgura = 15:17)   # filas 15:17 = horas 14-16, como el resto del caso 2
mc2 <- calibrar_montecarlo(mc2_todo, "aforos", obj2)
res2 <- resumir_montecarlo(mc2, ETIQUETAS_ESC_NORTE)
guardar_tabla(res2, "montecarlo_caso2_regreso_hacia_el_norte")
anotar(sprintf("Objetivos de calibración: cola de %s-%s h/día que empieza entre las %s y las %s y acaba entre las %s y las %s; descarga %s de %s-%s veh/h. Combinaciones compatibles: %d de %s (%s).",
               num_es(obj2$duracion[1], 0.1), num_es(obj2$duracion[2], 0.1), hora_txt(obj2$inicio[1]), hora_txt(obj2$inicio[2]),
               hora_txt(obj2$fin[1]), hora_txt(obj2$fin[2]), if (obj2$medida_descarga == "como_aforo") "medida como en el aforo" else "(parámetro)",
               num_es(ventana_descarga(obj2)[1]), num_es(ventana_descarga(obj2)[2]),
               mc2$n_validas, num_es(N_SIMULACIONES[2]), pct_es(mc2$n_validas / N_SIMULACIONES[2], 0.1)))
d2 <- mc2$draws
anotar(sprintf("  Situación actual simulada: espera máxima %s min (p10-p90 %s-%s), espera media en la hora punta %s min, cola %s h (de %s a %s).",
               num_es(median(d2$base_espera_max), 0.1), num_es(quantile(d2$base_espera_max, 0.1), 0.1),
               num_es(quantile(d2$base_espera_max, 0.9), 0.1), num_es(median(d2$base_media_punta), 0.1),
               num_es(median(d2$base_horas_cola), 0.1), hora_txt(median(d2$base_inicio)), hora_txt(median(d2$base_fin))))
anotar(sprintf("  Medida como en los aforos (horas enteras con >= 60 %% de vehículos en cola): %s h, de las %02.0f a las %02.0f h (mediana).",
               num_es(median(d2$base_horas_aforo), 0.1), median(d2$base_inicio_aforo), median(d2$base_fin_aforo)))
for (i in seq_len(nrow(res2)))
  anotar(sprintf("  %s mediana %4s  (p10 %4s, p90 %4s)", rellenar(res2$etiqueta[i], 52), pct_es(res2$mediana[i]),
                 pct_es(res2$p10[i]), pct_es(res2$p90[i])))
sc2 <- sensibilidad_calibracion(mc2_todo, obj2, ETIQUETAS_ESC_NORTE)
guardar_tabla(sc2, "sensibilidad_calibracion_caso2")
curva2 <- curva_holgura(mc2)
guardar_tabla(curva2, "tercer_carril_norte_segun_holgura")
c2_0 <- curva2 |> filter(holgura == 0, horizonte == "corto"); c2_50 <- curva2 |> filter(abs(holgura - 0.5) < 1e-9, horizonte == "corto")
anotar(sprintf("Tercer carril hipotético hacia el Norte según la holgura de La Matanza: con 0 %% %s el 1er año; con 50 %% (si La Matanza tuviera 3 carriles, tercer carril continuo hasta La Orotava) %s.",
               pct_es(c2_0$mediana), pct_es(c2_50$mediana)))
guardar_grafico(grafico_holgura(curva2, holg2_hora, horas = 14:16,
                                titulo = "Hacia el Norte, un tercer carril en Los Rodeos rendiría lo que deje La Matanza",
                                subtitulo = paste("Reducción de la demora de la tarde hacia el Norte con un tercer carril hipotético entre Los Rodeos y Guamasa,",
                                                  "si el tramo siguiente (La Matanza, 2 carriles) tuviera esa capacidad libre. Línea: mediana de las simulaciones",
                                                  "calibradas; banda: p10-p90. Líneas discontinuas: holgura mediana estimada a las 14, 15 y 16 h en 2025."),
                                pie = paste("Ningún proyecto añade un carril hacia el Norte entre Los Rodeos y Guamasa: el contratado va hacia Santa Cruz y el de",
                                            "Guamasa-La Orotava (en tramitación, ~300 M€) empieza en Guamasa. Con los dos, La Matanza tendría 3 carriles (holgura muy superior al 30 %).")),
                "g15b_tercer_carril_norte_holgura", 9, 5.6)
guardar_grafico(grafico_montecarlo(res2, caso2, mc2$n_validas,
                                   "Regreso hacia el Norte: reducción de la demora frente a no hacer nada",
                                   "la duración, el horario de la cola y la descarga medidos en 2025"), "g07b_montecarlo_caso2", 9, 7)
vh2 <- variantes_holgura(sc, 103, 111, "ascendente", est_cola = 99)
sh2 <- sensibilidad_holgura(mc2, vh2, "tarde_hacia_el_norte", 14:16, ETIQUETAS_ESC_NORTE, duracion = obj2$duracion)
guardar_tabla(sh2$holgura, "sensibilidad_holgura_caso2")
guardar_tabla(sh2$resultados, "sensibilidad_holgura_resultados_caso2")
anotar("Sensibilidad de la holgura de La Matanza (tarde; holgura mediana a las 15 h y tercer carril hipotético el 1er año):")
for (v in names(vh2)) {
  h15 <- sh2$holgura |> filter(variante == v, hora == 15); r <- sh2$resultados |> filter(variante == v, escenario == "tercer_carril_corto")
  anotar(sprintf("  %s: %s a las 15 h; tercer carril %s (%s-%s); cola de hoy en el rango medido en 2025 en el %s de las combinaciones", v,
                 pct_es(h15$holgura_mediana, 0.1), pct_es(r$mediana), pct_es(r$p10), pct_es(r$p90), pct_es(r$parte_cola_hoy_en_rango_medido)))
}
anotar("  (La Matanza no tiene velocidad utilizable: no se puede saber si su tramo tiene cola, así que no hay variante de cuello desplazado hacia el Norte.)")

# ---- 7. Bus-VAO del Cabildo (PK 2,5-12,2): reserva el carril izquierdo en punta
anotar("== 7. Bus-VAO en Padre Anchieta, hacia el Norte (3 carriles -> 2 + 1 reservado) ==")
pa <- perf |> filter(estacion_id == 97, sentido == "ascendente")
V_pa <- pa$dia_medio[1]
cn_pa <- sum(pa$veh[pa$hora >= 22 | pa$hora < 6]) / V_pa
anotar(sprintf("Padre Anchieta hacia el Norte: %s veh/día laborable (media de %d días válidos de 2025; la estación pasó meses sin datos). Sin velocidades fiables: perfil sintético calibrado con una espera de 10-40 min (franja supuesta que cubre las cifras de la prensa: 15-20 min, Atlántico Hoy 24-11-2025; 40 min en un día con incidente, COPE 20-10-2021).",
               num_es(V_pa), max(pa$dias)))
par_bv <- par_cal |>
  fijar_parametro("cuota_noche", cn_pa, descripcion = sprintf("Cuota nocturna (22-06 h) observada en Padre Anchieta hacia el Norte: %s", pct_es(cn_pa, 0.1))) |>
  fijar_parametro("t0_punta", 780, 900, 1080, descripcion = "Centro de la punta de la tarde (13:00-18:00)")
bv_todo <- simular_montecarlo(par_bv, V_pa, 3, FALSE, n = 800, semilla = 7, evaluar_si = function(d) rep(FALSE, nrow(d)))
d_bv <- bv_todo$draws |> filter(base_espera_max >= 10, base_espera_max <= 40, base_cola_final < 0.5)
bv <- tibble(
  equilibrio = vapply(seq_len(nrow(d_bv)), function(i) as.numeric(trasvase_bus_vao(as.list(d_bv[i, ]), V_pa, 3, 0)), numeric(1)),
  mitad      = vapply(seq_len(nrow(d_bv)), function(i) as.numeric(trasvase_bus_vao(as.list(d_bv[i, ]), V_pa, 3, 0.5)), numeric(1))) |>
  filter(!is.na(equilibrio))
guardar_tabla(bv, "bus_vao_trasvase_necesario")
anotar(sprintf("Para que el tráfico general no vaya peor debe pasar al carril reservado el %s de los vehículos (p10-p90: %s-%s);",
               pct_es(median(bv$equilibrio)), pct_es(quantile(bv$equilibrio, 0.1)), pct_es(quantile(bv$equilibrio, 0.9))))
anotar(sprintf("  para que su espera en la hora punta baje a la mitad, el %s (p10-p90: %s-%s). %d combinaciones calibradas (espera máxima actual de 10-40 min, franja supuesta a partir de la prensa).",
               pct_es(median(bv$mitad)), pct_es(quantile(bv$mitad, 0.1)), pct_es(quantile(bv$mitad, 0.9)), nrow(bv)))
g11 <- grafico_bus_vao(d_bv, V_pa, 3)
curva_bus_vao <- attr(g11, "datos")
guardar_tabla(curva_bus_vao, "bus_vao_curva_padre_anchieta")
guardar_grafico(g11, "g11_bus_vao_padre_anchieta", 9, 5.4)

# ---- Diagnóstico de la calibración y validación del modelo ---------------------
anotar("== Validación del modelo ==")
pp <- bind_rows(prior_posterior(par_c1_doc, mc1_todo, mc1, "manana_hacia_santa_cruz"),
                prior_posterior(par_c2_doc, mc2_todo, mc2, "tarde_hacia_el_norte"))
guardar_tabla(pp, "parametros_prior_posterior")
for (cs_i in unique(pp$caso)) {
  x <- pp |> filter(caso == cs_i)
  anotar(sprintf("  %s: %s de %s combinaciones aceptadas (%s). Lo que más estrecha la calibración: %s.", cs_i, num_es(x$aceptadas[1]), num_es(x$simuladas[1]),
                 pct_es(x$tasa_aceptacion[1], 0.1),
                 paste(sprintf("%s (%s)", x$parametro, pct_es(x$estrechamiento))[order(-x$estrechamiento)][1:min(3, nrow(x))], collapse = ", ")))
}
dg <- bind_rows(diagnostico_reducciones(mc1, "manana_hacia_santa_cruz"), diagnostico_reducciones(mc2, "tarde_hacia_el_norte"))
guardar_tabla(dg, "diagnostico_reducciones_extremas")
anotar("  Reducciones del 100 %: son simulaciones en las que la alternativa elimina la cola (demora cero), no un tope del cálculo:")
for (i in which(dg$elimina_cola > 0.05))
  anotar(sprintf("    %s · %s: elimina la cola en el %s de las simulaciones", dg$caso[i], dg$etiqueta[i], pct_es(dg$elimina_cola[i])))
met <- bind_rows(metricas_alternativas(mc1, "manana_hacia_santa_cruz"), metricas_alternativas(mc2, "tarde_hacia_el_norte"))
guardar_tabla(met, "metricas_por_alternativa")
estab <- bind_rows(estabilidad_percentiles(mc1, "manana_hacia_santa_cruz"), estabilidad_percentiles(mc2, "tarde_hacia_el_norte"))
guardar_tabla(estab, "estabilidad_percentiles")
anotar(sprintf("  Estabilidad (bootstrap de las simulaciones calibradas): error típico de la mediana de %s a %s puntos; del p10, hasta %s; del p90, hasta %s.",
               num_es(100 * min(estab$ee_mediana), 0.1), num_es(100 * max(estab$ee_mediana), 0.1),
               num_es(100 * max(estab$ee_p10), 0.1), num_es(100 * max(estab$ee_p90), 0.1)))
# Validación día a día (cada día laborable válido y cada hora de la ventana; 2025 calibra,
# 2026 no se usa) y validación resumida (medianas)
vd1 <- validacion_diaria(mc1, sc, 103, 103, "descendente", "manana_hacia_santa_cruz", HORAS_CASO1, n_max = N_PREVISION)
vd2 <- validacion_diaria(mc2, sc, 99, 103, "ascendente", "tarde_hacia_el_norte", HORAS_CASO2, n_max = N_PREVISION)
vdt <- bind_rows(vd1$tabla, vd2$tabla)
guardar_tabla(vdt, "validacion_diaria")
guardar_tabla(bind_rows(vd1$por_hora, vd2$por_hora), "validacion_diaria_por_hora")
val1 <- validacion_modelo(mc1, sc, 103, 103, "descendente", "manana_hacia_santa_cruz", HORAS_CASO1, descarga_aforo = vd1$por_sim$descarga_aforo)
val2 <- validacion_modelo(mc2, sc, 99, 103, "ascendente", "tarde_hacia_el_norte", HORAS_CASO2, descarga_aforo = vd2$por_sim$descarga_aforo)
val <- bind_rows(val1$tabla, val2$tabla)
guardar_tabla(val, "validacion_modelo")
val_err <- bind_rows(val1$error_perfil, val2$error_perfil)
guardar_tabla(val_err, "validacion_perfil_horario")
guardar_tabla(bind_rows(val1$perfil, val2$perfil), "validacion_perfil_por_hora")
guardar_grafico(grafico_validacion_perfil(bind_rows(val1$perfil, val2$perfil)), "g17_validacion_perfil_horario", 9, 7.4)
for (i in seq_len(nrow(val)))
  anotar(sprintf("  %s · %s: 2025 %s, 2026 %s; modelo %s (p10-p90 %s-%s); error de la mediana %s en 2025 y %s en 2026%s", val$caso[i], val$indicador[i],
                 num_es(val$observado_2025[i], 0.01), num_es(val$observado_2026[i], 0.01), num_es(val$simulado_mediana[i], 0.01),
                 num_es(val$simulado_p10[i], 0.01), num_es(val$simulado_p90[i], 0.01),
                 num_es(val$error_mediana_2025[i], 0.01), num_es(val$error_mediana_2026[i], 0.01),
                 ifelse(isTRUE(val$dentro_2026[i]), " · 2026 dentro de la banda",
                        sprintf(" · 2026 FUERA de la banda (a %s del límite)", num_es(abs(val$distancia_a_la_banda_2026[i]), 0.01)))))
fuera_val <- val |> filter(!dentro_2026)
anotar(sprintf("  Control: validacion_modelo.csv tiene %d filas de indicadores (%s por sentido). Fuera de la banda en 2026: %d %s, de %d %s (%s)%s.",
               nrow(val), paste(unique(as.integer(table(val$caso))), collapse = "/"), nrow(fuera_val), ifelse(nrow(fuera_val) == 1, "fila", "filas"),
               nrow(distinct(fuera_val, caso, fenomeno)), ifelse(nrow(distinct(fuera_val, caso, fenomeno)) == 1, "fenómeno", "fenómenos distintos"),
               if (nrow(fuera_val)) paste(sprintf("%s: %s", fuera_val$caso, fuera_val$fenomeno), collapse = "; ") else "ninguno",
               if (any(duplicated(paste(fuera_val$caso, fuera_val$fenomeno))))
                 "; las filas de un mismo fenómeno miden lo mismo de dos formas y no son fallos independientes" else ""))
for (i in seq_len(nrow(val_err)))
  anotar(sprintf("  %s · caudal hora a hora de %s frente a %s: error medio %s; %s de las horas dentro de la banda p10-p90",
                 val_err$caso[i], val_err$horas[i], val_err$comparado_con[i], pct_es(val_err$error_medio_absoluto[i], 0.1),
                 pct_es(val_err$horas_dentro_p10_p90[i])))
anotar("Validación día a día (sesgo = modelo - aforo; banda de parámetros = un día típico; intervalo predictivo del 80 % = banda + variabilidad de un día a otro y error de observación de 2025):")
for (i in which(vdt$periodo %in% c("2025 (calibración)", "2026 (validación, no usado)")))
  anotar(sprintf("  %s · %s · %s: %s observaciones; sesgo %s%s; MAE %s%s; RMSE %s; dentro de la banda de parámetros %s; dentro del intervalo predictivo %s",
                 vdt$caso[i], vdt$indicador[i], vdt$periodo[i], num_es(vdt$observaciones[i]), num_es(vdt$sesgo[i], 0.01),
                 ifelse(is.na(vdt$sesgo_relativo[i]), "", sprintf(" (%s)", pct_es(vdt$sesgo_relativo[i], 0.1))), num_es(vdt$mae[i], 0.01),
                 ifelse(is.na(vdt$mae_relativo[i]), "", sprintf(" (%s)", pct_es(vdt$mae_relativo[i], 0.1))), num_es(vdt$rmse[i], 0.01),
                 pct_es(vdt$cobertura_p10_p90[i]), ifelse(is.na(vdt$cobertura_intervalo_predictivo[i]), "no aplica", pct_es(vdt$cobertura_intervalo_predictivo[i]))))
# Validación cruzada temporal (2025, semanas alternas) y prueba final con 2026 de todas las especificaciones
vcx <- bind_rows(rej1, rej2)
guardar_tabla(vcx, "validacion_cruzada")
elx <- bind_rows(el1, el2)
guardar_tabla(elx, "eleccion_especificacion")
for (cs_i in unique(elx$caso)) {
  e <- elx |> filter(caso == cs_i, elegida); r0 <- elx |> filter(caso == cs_i, referencia)
  anotar(sprintf("Elección de la especificación (%s): %s. Variantes admisibles: %d de %d. Sesgo absoluto de la descarga del día fuera de muestra (media de las dos mitades de 2025): %s veh/h con la elegida y %s con la referencia; RMSE relativo medio %s.",
                 cs_i, describir_especificacion(e$propagacion, e$horario, e$pesados, e$medida_descarga), sum(elx$admisible[elx$caso == cs_i]),
                 sum(elx$caso == cs_i) - 1, num_es(e$sesgo_descarga), num_es(r0$sesgo_descarga), num_es(e$rmse_relativo_medio, 0.001)))
  pf <- vcx |> filter(caso == cs_i, prueba == "2026", propagacion == e$propagacion, horario == e$horario, pesados == e$pesados, medida_descarga == e$medida_descarga)
  p0 <- vcx |> filter(caso == cs_i, prueba == "2026", !propagacion, !horario, !pesados, medida_descarga == "parametro")
  p0 <- p0[match(pf$indicador, p0$indicador), ]
  for (k in seq_len(nrow(pf)))
    anotar(sprintf("  2026 (prueba final) · %s: sesgo %s (referencia %s); RMSE %s (%s); intervalo predictivo %s (%s)", pf$indicador[k],
                   num_es(pf$sesgo[k], 0.01), num_es(p0$sesgo[k], 0.01), num_es(pf$rmse[k], 0.01), num_es(p0$rmse[k], 0.01),
                   pct_es(pf$cobertura_intervalo_predictivo[k]), pct_es(p0$cobertura_intervalo_predictivo[k])))
}
guardar_grafico(grafico_validacion_cruzada(vcx, elx), "g20_validacion_fuera_de_muestra", 9, 7.2)
dgd <- bind_rows(diagnostico_descarga(vd1, mc1_todo, mc1, obj1, sc, "manana_hacia_santa_cruz", est_abajo = c(99, 93), sen = "descendente"),
                 diagnostico_descarga(vd2, mc2_todo, mc2, obj2, sc, "tarde_hacia_el_norte", sen = "ascendente"))
guardar_tabla(dgd, "diagnostico_descarga")
anotar("Diagnóstico de la descarga de la mañana (mediana del caudal en las horas con cola; aforo 2025 / modelo):")
x <- dgd |> filter(caso == "manana_hacia_santa_cruz", bloque %in% c("Por hora del día", "Por posición en la cola"), fuente %in% c("aforo 2025", "modelo (calibrado)"))
for (g in unique(x$grupo)) {
  a <- x |> filter(grupo == g, fuente == "aforo 2025"); m <- x |> filter(grupo == g, fuente == "modelo (calibrado)")
  if (nrow(a) && nrow(m) && a$n >= 10) anotar(sprintf("  %s: aforo %s (%d horas); modelo %s", g, num_es(a$mediana), a$n, if (m$n > 0) num_es(m$mediana) else "sin horas con cola"))
}
x <- dgd |> filter(caso == "manana_hacia_santa_cruz", bloque == "Según haya cola aguas abajo", fuente == "aforo 2025")
for (i in seq_len(nrow(x))) if (x$n[i] >= 10) anotar(sprintf("  %s: %s veh/h (%d horas)", x$grupo[i], num_es(x$mediana[i]), x$n[i]))
x <- dgd |> filter(caso == "manana_hacia_santa_cruz", bloque == "Parámetro de descarga")
for (i in seq_len(nrow(x))) anotar(sprintf("  %s: mediana %s (p10-p90 %s-%s)%s", x$grupo[i], num_es(x$mediana[i]), num_es(x$p10[i]), num_es(x$p90[i]),
                                         ifelse(nzchar(x$nota[i]), paste0(". ", x$nota[i]), "")))

# Diseño del Monte Carlo: distribuciones, dependencias, semillas, reglas y descartes
dm1 <- diseno_montecarlo(par_c1_doc, mc1_todo, mc1, obj1, "manana_hacia_santa_cruz")
dm2 <- diseno_montecarlo(par_c2_doc, mc2_todo, mc2, obj2, "tarde_hacia_el_norte")
guardar_tabla(bind_rows(dm1$parametros, dm2$parametros), "montecarlo_parametros")
guardar_tabla(bind_rows(dm1$filtros, dm2$filtros), "montecarlo_filtros")
guardar_tabla(SEMILLAS_MC, "montecarlo_semillas")
anotar(sprintf("Monte Carlo: combinaciones que pasa cada regla de calibración (sobre las %s simuladas por la mañana y %s por la tarde; el resto se descarta):",
               num_es(N_SIMULACIONES[1]), num_es(N_SIMULACIONES[2])))
for (i in seq_len(nrow(dm1$filtros) + nrow(dm2$filtros))) with(bind_rows(dm1$filtros, dm2$filtros)[i, ],
  anotar(sprintf("  %s · %s%s: pasan %s (%s); se descarta el %s", caso, regla, ifelse(nzchar(umbral), paste0(" (", umbral, ")"), ""),
                 num_es(pasan), pct_es(tasa, 0.1), pct_es(descartadas, 0.1))))
for (cs_i in c("manana_hacia_santa_cruz", "tarde_hacia_el_norte")) {
  s_i <- if (cs_i == "manana_hacia_santa_cruz") sc1 else sc2
  a <- s_i |> filter(regla == "Aforos horarios 2025 (principal)", escenario == "tercer_carril_corto")
  b <- s_i |> filter(regla == "Sin calibrar (muestra aleatoria con cola)", escenario == "tercer_carril_corto")
  if (nrow(a) && nrow(b))
    anotar(sprintf("  %s · tercer carril el 1er año con el filtro (calibrado) %s (banda de parámetros p10-p90 %s-%s) y sin filtro (%s combinaciones al azar con cola) %s (%s-%s)",
                   cs_i, pct_es(a$mediana), pct_es(a$p10), pct_es(a$p90), num_es(b$n_validas), pct_es(b$mediana), pct_es(b$p10), pct_es(b$p90)))
}
anotar("  Población: los percentiles describen las combinaciones de parámetros compatibles con los aforos de 2025 en cada cuello, con previas triangulares independientes; no son probabilidades de lo que pasará en la TF-5 ni intervalos predictivos.")
# Auditoría del Monte Carlo: otras semillas, previas alternativas (reponderación), correlaciones y diferencias por regla
sem <- bind_rows(
  replicar_semillas(par_c1, V1, 2, obj1, SEMILLAS_AUDITORIA, N_SIMULACIONES[1], HH, obs1, 7:9, caso = "manana_hacia_santa_cruz"),
  replicar_semillas(par_c2, V2, 2, obj2, SEMILLAS_AUDITORIA, N_SIMULACIONES[2], HH2, obs2, 15:18, ETIQUETAS_ESC_NORTE, caso = "tarde_hacia_el_norte"))
sem_ref <- bind_rows(res1 |> mutate(caso = "manana_hacia_santa_cruz", aceptadas = mc1$n_validas), res2 |> mutate(caso = "tarde_hacia_el_norte", aceptadas = mc2$n_validas)) |>
  transmute(caso, semilla = 2026L, aceptadas, escenario, etiqueta, p10, mediana, p90)
sem <- bind_rows(sem_ref, sem) |> arrange(caso, escenario, semilla)
guardar_tabla(sem, "montecarlo_otras_semillas")
for (cs_i in unique(sem$caso)) {
  x <- sem |> filter(caso == cs_i, escenario %in% c("tercer_carril_corto", "paquete_gestion_corto"))
  anotar(sprintf("  Otras semillas (%s): aceptadas %s; tercer carril el 1er año %s; regulación + escalonamiento %s.", cs_i,
                 paste(unique(x$aceptadas), collapse = " / "),
                 paste(pct_es(x$mediana[x$escenario == "tercer_carril_corto"], 0.1), collapse = " / "),
                 paste(pct_es(x$mediana[x$escenario == "paquete_gestion_corto"], 0.1), collapse = " / ")))
}
PREVIAS_ALTERNATIVAS <- list(
  "Uniformes en el mismo rango" = stats::setNames(rep(list("uniforme"), 10), c("c_carril", "caida_capacidad", "eta_corto", "eta_largo", "T_libre",
                                                                              "eficacia_rm", "desplazamiento_horario", "reduccion_tarificacion", "sigma_punta",
                                                                              "equivalencia_pesados")),
  "Más demanda inducida (moda de las elasticidades en su extremo)" = list(eta_corto = c(-0.5, -0.5, -0.1), eta_largo = c(-1, -1, -0.3)),
  "Regulación menos eficaz (moda de la eficacia en el mínimo)" = list(eficacia_rm = c(0.5, 0.5, 1)),
  "Caída de capacidad más pequeña (moda en el mínimo)" = list(caida_capacidad = c(0.03, 0.03, 0.18)))
# Con la mezcla de pesados en la especificación, también una previa con más peso de los pesados
previas_caso <- function(par_doc) if ("equivalencia_pesados" %in% par_doc$parametro)
  c(PREVIAS_ALTERNATIVAS, list("Pesados con más peso (moda de la equivalencia en 3,5)" = list(equivalencia_pesados = c(1.5, 3.5, 4)))) else PREVIAS_ALTERNATIVAS
prv <- bind_rows(reponderar_previas(mc1, par_c1_doc, previas_caso(par_c1_doc), "manana_hacia_santa_cruz"),
                 reponderar_previas(mc2, par_c2_doc, previas_caso(par_c2_doc), "tarde_hacia_el_norte", ETIQUETAS_ESC_NORTE))
guardar_tabla(prv, "montecarlo_previas_alternativas")
for (cs_i in unique(prv$caso)) for (pv in unique(prv$previa)) {
  x <- prv |> filter(caso == cs_i, previa == pv, escenario %in% c("tercer_carril_corto", "paquete_gestion_corto"))
  anotar(sprintf("  Previa «%s» (%s; tamaño efectivo %s de %s): tercer carril %s; regulación + escalonamiento %s.", pv, cs_i,
                 num_es(x$tamano_efectivo[1]), num_es(x$aceptadas[1]), pct_es(x$mediana[x$escenario == "tercer_carril_corto"], 0.1),
                 pct_es(x$mediana[x$escenario == "paquete_gestion_corto"], 0.1)))
}
corr <- bind_rows(correlaciones_parametros(mc1_todo, mc1, par_c1_doc, "manana_hacia_santa_cruz"),
                  correlaciones_parametros(mc2_todo, mc2, par_c2_doc, "tarde_hacia_el_norte"))
guardar_tabla(corr, "montecarlo_correlaciones")
for (cs_i in unique(corr$caso)) {
  x <- corr |> filter(caso == cs_i) |> slice_max(abs(rho_aceptadas), n = 3)
  anotar(sprintf("  Correlaciones que crea la calibración (%s; Spearman en las aceptadas, previa ~0): %s.", cs_i,
                 paste(sprintf("%s-%s %+.2f", x$parametro_1, x$parametro_2, x$rho_aceptadas), collapse = "; ")))
}
# La cola de la mañana se acumula en La Matanza hacia Santa Cruz (2 carriles); la de la tarde, en Bomberos La Laguna
# hacia el Norte (3 carriles), antes del paso de 3 a 2 carriles
car_cola <- function(id, sentido) carriles$carriles[carriles$estacion_id == id & carriles$sentido == sentido]
idm <- bind_rows(indicadores_demora(mc1, "manana_hacia_santa_cruz", aguas_arriba = "La Matanza", carriles_cola = car_cola(111, "descendente")),
                 indicadores_demora(mc2, "tarde_hacia_el_norte", aguas_arriba = "Padre Anchieta", carriles_cola = car_cola(99, "ascendente")))
guardar_tabla(idm, "indicadores_demora")
anotar("Indicadores de demora de la situación actual (todos simulados; mediana y p10-p90):")
for (i in seq_len(nrow(idm)))
  anotar(sprintf("  %s · %s (%s): %s (%s-%s)", idm$caso[i], idm$indicador[i], idm$unidad[i], num_es(idm$simulado_mediana[i], 0.1),
                 num_es(idm$simulado_p10[i], 0.1), num_es(idm$simulado_p90[i], 0.1)))
# Diferencias emparejadas entre alternativas (misma combinación de parámetros para todas)
dem <- bind_rows(diferencias_emparejadas(mc1, "manana_hacia_santa_cruz"), diferencias_emparejadas(mc2, "tarde_hacia_el_norte", ETIQUETAS_ESC_NORTE))
guardar_tabla(dem, "diferencias_emparejadas")
dreg <- bind_rows(diferencias_por_regla(mc1_todo, obj1, "manana_hacia_santa_cruz"),
                  diferencias_por_regla(mc2_todo, obj2, "tarde_hacia_el_norte", ETIQUETAS_ESC_NORTE))
guardar_tabla(dreg, "diferencias_emparejadas_por_regla")
anotar("Diferencia emparejada tercer carril - (regulación + escalonamiento), el 1er año (puntos; mediana, banda p10-p90 y parte de las combinaciones en que el tercer carril reduce más):")
for (cs_i in unique(dem$caso)) {
  x <- dem |> filter(caso == cs_i, horizonte == "corto", alternativa_a == "tercer_carril", alternativa_b == "paquete_gestion")
  anotar(sprintf("  %s: %s (%s a %s; error de muestreo %s); el tercer carril reduce más en el %s de las combinaciones. %s.", cs_i,
                 num_es(100 * x$dif_mediana, 0.1), num_es(100 * x$dif_p10, 0.1), num_es(100 * x$dif_p90, 0.1), num_es(100 * x$ee_dif_mediana, 0.1),
                 pct_es(x$parte_a_mayor), x$lectura))
}
guardar_grafico(grafico_diferencias_emparejadas(dem), "g21_diferencias_emparejadas", 9, 6.2)
cpr <- coste_plazo_riesgo()
guardar_tabla(cpr, "coste_plazo_riesgo")
cr1 <- cola_remanente(mc1, holg_h)
guardar_tabla(cr1, "cola_remanente_aguas_abajo")
anotar("Tercer carril de la mañana en serie con el tramo siguiente (almacenamiento entre los dos y entradas de los ramales; 1er año, mediana de 200 combinaciones):")
for (i in seq_len(nrow(cr1)))
  anotar(sprintf("  almacenamiento %s veh (%s km): reducción %s (banda %s-%s) frente a %s en el modelo principal; cola remanente máxima %s veh; rebose %s min; espera en los ramales %s veh·h (hoy %s)",
                 num_es(cr1$almacenamiento_veh[i]), num_es(cr1$longitud_km[i], 0.1), pct_es(cr1$reduccion_mediana[i]), pct_es(cr1$reduccion_p10[i]),
                 pct_es(cr1$reduccion_p90[i]), pct_es(cr1$reduccion_modelo_principal[i]), num_es(cr1$cola_remanente_max_mediana[i]),
                 num_es(cr1$minutos_rebose_mediana[i]), num_es(cr1$demora_ramales_tercer_carril_vh[i], 0.1), num_es(cr1$demora_ramales_actual_vh[i], 0.1)))

# =============================================================================
# QUÉ PREVEMOS
# =============================================================================
anotar("== 8. Previsión: evolución sin actuar, alternativas en 2030 y escenarios adversos ==")
crecimientos <- esc_dem$crecimiento_anual
ev1 <- evolucion_demanda(mc1, "manana_hacia_santa_cruz", crecimientos, n_max = N_PREVISION, holg_h = holg_h)
ev2 <- evolucion_demanda(mc2, "tarde_hacia_el_norte", crecimientos, n_max = N_PREVISION, holg_h = holg2_h)
evo <- bind_rows(ev1, ev2)
guardar_tabla(evo, "evolucion_sin_actuar")
guardar_grafico(grafico_evolucion_sin_actuar(evo, c(r103d$horas_media, r99a$horas_media)), "g18_evolucion_sin_actuar", 9, 6)
for (i in which(evo$anio != 2025))
  anotar(sprintf("  %s, %d, +%s %%/año: %s h de cola (media; p10-p90 %s-%s) si toda la demanda nueva va a la punta; %s h (%s-%s) si se adapta (2025: %s h)",
                 evo$caso[i], evo$anio[i], num_es(100 * evo$crecimiento_anual[i], 0.1), num_es(evo$horas_cola_sin_adaptacion[i], 0.1),
                 num_es(evo$horas_cola_sin_p10[i], 0.1), num_es(evo$horas_cola_sin_p90[i], 0.1),
                 num_es(evo$horas_cola_con_adaptacion[i], 0.1), num_es(evo$horas_cola_con_p10[i], 0.1), num_es(evo$horas_cola_con_p90[i], 0.1),
                 num_es(evo$horas_cola_sin_adaptacion[evo$caso == evo$caso[i] & evo$anio == 2025 & evo$crecimiento_anual == evo$crecimiento_anual[i]], 0.1)))
# Sensibilidad de la previsión al supuesto de la descarga fuera de las horas con datos. Si
# la especificación de la mañana reduce la descarga por hora, el factor solo se aplica en
# las horas con datos suficientes de 2025 (después, descarga de referencia). Aquí se repite
# la evolución manteniendo el factor de la última hora con datos el resto del día: es un
# supuesto que los aforos no pueden comprobar, porque en 2025 la cola casi nunca llega a
# esas horas
sdp <- NULL
if (!is.null(mc1$perfil_obs$especificacion$factor_descarga)) {
  mc1x <- mc1
  mc1x$perfil_obs$especificacion$factor_descarga <- as.numeric(factor_horario_descarga(od1_25$horas, extrapolar = TRUE))
  ev1x <- evolucion_demanda(mc1x, "manana_hacia_santa_cruz", crecimientos, n_max = N_PREVISION, holg_h = holg_h)
  sdp <- bind_rows(ev1 |> mutate(supuesto = "Principal: factor horario solo en las horas con datos; después, descarga de referencia"),
                   ev1x |> mutate(supuesto = "Sensibilidad: el factor de la última hora con datos se mantiene el resto del día")) |>
    mutate(categoria = "simulado (escenario condicionado)") |> relocate(caso, supuesto)
  guardar_tabla(sdp, "sensibilidad_prevision_descarga")
  for (g in setdiff(crecimientos, 0)) for (a in c(2030, 2035)) {
    x <- sdp |> filter(abs(crecimiento_anual - g) < 1e-9, anio == a)
    anotar(sprintf("  Mañana, %d, +%s %%/año: %s h de cola con el supuesto principal y %s h si la descarga reducida se mantuviera el resto del día",
                   a, num_es(100 * g, 0.1), num_es(x$horas_cola_sin_adaptacion[1], 0.1), num_es(x$horas_cola_sin_adaptacion[2], 0.1)))
  }
} else anotar("  La especificación elegida para la mañana no reduce la descarga por hora: no hace falta la sensibilidad de la previsión a ese supuesto.")
g_central <- esc_dem$crecimiento_anual[esc_dem$escenario == "Central"]
af <- bind_rows(alternativas_futuro(mc1, "manana_hacia_santa_cruz", 2030, g_central, holg_h, TRUE, n_max = N_PREVISION),
                alternativas_futuro(mc2, "tarde_hacia_el_norte", 2030, g_central, holg2_h, TRUE, n_max = N_PREVISION) |>
                  mutate(etiqueta = ifelse(escenario == "base", etiqueta, unname(ETIQUETAS_ESC_NORTE[escenario]))))
guardar_tabla(af, "alternativas_2030")
anotar(sprintf("Alternativas en 2030 (demanda +%s %%/año desde 2025; tercer carril en servicio hacia 2029-2030):", num_es(100 * g_central, 0.1)))
for (i in which(af$escenario %in% c("tercer_carril_corto", "ramp_metering_corto", "escalonamiento_corto", "tarificacion", "paquete_gestion_corto")))
  anotar(sprintf("  %s · %s: %s (p10-p90 %s-%s)", af$caso[i], af$etiqueta[i], pct_es(af$reduccion_mediana[i]),
                 pct_es(af$reduccion_p10[i]), pct_es(af$reduccion_p90[i])))
# Las mismas alternativas en 2030 con los otros dos ritmos de crecimiento (bajo y alto)
af_otros <- bind_rows(lapply(setdiff(crecimientos, g_central), function(g) bind_rows(
  alternativas_futuro(mc1, "manana_hacia_santa_cruz", 2030, g, holg_h, TRUE, n_max = N_PREVISION),
  alternativas_futuro(mc2, "tarde_hacia_el_norte", 2030, g, holg2_h, TRUE, n_max = N_PREVISION) |>
    mutate(etiqueta = ifelse(escenario == "base", etiqueta, unname(ETIQUETAS_ESC_NORTE[escenario]))))))
af3 <- bind_rows(af, af_otros) |> arrange(caso, crecimiento_anual)
guardar_tabla(af3, "alternativas_2030_por_crecimiento")
# Retraso de la obra: el tercer carril de la mañana entrando en servicio entre 2029 y 2032
ret <- bind_rows(af3 |> filter(caso == "manana_hacia_santa_cruz", anio == 2030, crecimiento_anual %in% c(g_central, max(crecimientos)),
                               escenario %in% c("base", "tercer_carril_corto", "paquete_gestion_corto")) |> mutate(categoria = "simulado (escenario condicionado)"),
                 retraso_obra(mc1, "manana_hacia_santa_cruz", holg_h, setdiff(2029:2032, 2030), c(g_central, max(crecimientos)), N_PREVISION)) |>
  arrange(crecimiento_anual, anio, escenario)
guardar_tabla(ret, "retraso_obra_tercer_carril")
anotar("Tercer carril según el año en que entre en servicio (reducción el 1er año, mediana; crecimiento central / alto):")
for (a in sort(unique(ret$anio))) {
  x <- ret |> filter(anio == a, escenario == "tercer_carril_corto") |> arrange(crecimiento_anual)
  b <- ret |> filter(anio == a, escenario == "base") |> arrange(crecimiento_anual)
  anotar(sprintf("  %d: %s; horas de cola sin actuar ese año %s", a, paste(pct_es(x$reduccion_mediana), collapse = " / "),
                 paste(num_es(b$horas_cola_mediana, 0.1), collapse = " / ")))
}
anotar("Alternativas en 2030 según el crecimiento de la demanda (0 % / 0,5 % / 1 % anual; mediana):")
for (cs_i in unique(af3$caso)) for (e in c("tercer_carril_corto", "ramp_metering_corto", "paquete_gestion_corto", "tarificacion")) {
  x <- af3 |> filter(caso == cs_i, escenario == e) |> arrange(crecimiento_anual)
  anotar(sprintf("  %s · %s: %s", cs_i, x$etiqueta[1], paste(sprintf("%s (%s-%s)", pct_es(x$reduccion_mediana), pct_es(x$reduccion_p10), pct_es(x$reduccion_p90)), collapse = " / ")))
}
adv1 <- escenarios_adversos(mc1, "manana_hacia_santa_cruz", HH, TRUE, n_max = N_PREVISION)
adv2 <- escenarios_adversos(mc2, "tarde_hacia_el_norte", HH2, TRUE, n_max = N_PREVISION,
                            nombre_sin_holgura = "Tramo siguiente sin holgura (La Matanza llena)") |>
  mutate(etiqueta = ifelse(escenario == "base", etiqueta, unname(ETIQUETAS_ESC_NORTE[escenario])))
adv <- bind_rows(adv1, adv2)
guardar_tabla(adv, "escenarios_adversos")
# Coherencia: con todas las simulaciones calibradas, la referencia de los escenarios
# adversos tiene que dar exactamente la mediana del modelo (secciones 5 y 6)
ref_chk <- adv |> filter(supuesto == "Referencia (calibrado)", escenario != "base") |>
  inner_join(bind_rows(res1 |> mutate(caso = "manana_hacia_santa_cruz"), res2 |> mutate(caso = "tarde_hacia_el_norte")) |>
               select(caso, escenario, mediana), by = c("caso", "escenario"))
dif_ref <- max(abs(ref_chk$reduccion_mediana - ref_chk$mediana))
anotar(sprintf("Comprobación: la referencia de los escenarios adversos reproduce la mediana del modelo en %d de %d alternativas (diferencia máxima %s puntos)%s.",
               sum(abs(ref_chk$reduccion_mediana - ref_chk$mediana) < 1e-9), nrow(ref_chk), num_es(100 * dif_ref, 0.01),
               if (N_PREVISION < max(nrow(mc1$draws), nrow(mc2$draws))) "; con una submuestra puede diferir" else ""))
anotar("Escenarios adversos (alternativa con mayor reducción mediana el 1er año en cada supuesto):")
for (cs_i in unique(adv$caso)) for (s in unique(adv$supuesto[adv$caso == cs_i])) {
  x <- adv |> filter(caso == cs_i, supuesto == s, escenario != "base") |> arrange(puesto)
  emp <- x |> filter(empate_con_la_primera)
  if (nrow(emp) > 1) {
    anotar(sprintf("  %s · %s: empatadas a menos de 2 puntos: %s", cs_i, s,
                   paste(sprintf("%s (%s)", emp$etiqueta, pct_es(emp$reduccion_mediana)), collapse = ", ")))
  } else anotar(sprintf("  %s · %s: 1.º %s (%s); 2.º %s (%s)", cs_i, s, x$etiqueta[1], pct_es(x$reduccion_mediana[1]),
                        x$etiqueta[2], pct_es(x$reduccion_mediana[2])))
}
tp1 <- curva_trasvase_tp(mc1, n_max = N_PREVISION) |> mutate(caso = "manana_hacia_santa_cruz")
tp2 <- curva_trasvase_tp(mc2, n_max = N_PREVISION) |> mutate(caso = "tarde_hacia_el_norte")
tpt <- bind_rows(tp1, tp2) |> relocate(caso)
guardar_tabla(tpt, "transporte_publico_trasvase")
anotar("Transporte público: reducción de la demora si una parte de la punta pasa a la guagua o al tranvía (sin rebote; 1er año; 10 años):")
for (i in seq_len(nrow(tpt)))
  anotar(sprintf("  %s · %s de la punta (%s veh/día): %s; %s; %s", tpt$caso[i], pct_es(tpt$trasvase[i]), num_es(tpt$veh_dia_trasvasados[i]),
                 pct_es(tpt$reduccion_sin_rebote[i]), pct_es(tpt$reduccion_1er_anio[i]), pct_es(tpt$reduccion_10_anios[i])))
guardar_grafico(grafico_horizontes(res1, res2), "g19_duracion_de_la_mejora", 9, 5.8)
prev <- previsiones_condicionadas(evo, af3, tpt, list(manana_hacia_santa_cruz = res1, tarde_hacia_el_norte = res2), esc_dem)
guardar_tabla(prev, "previsiones_condicionadas")
anotar(sprintf("Previsiones condicionadas: %d filas (crecimiento exógeno, cambio de red, gestión, transporte público y demanda inducida), todas con p10-p90 y condición de validez.", nrow(prev)))

# ---- Confianza de cada alternativa, lagunas y limitaciones -----------------------
crit <- readr::read_csv(file.path(DIR_DATOS, "confianza_alternativas.csv"), show_col_types = FALSE)
conf <- tabla_confianza(crit, list(manana_hacia_santa_cruz = res1, tarde_hacia_el_norte = res2),
                        list(manana_hacia_santa_cruz = adv1, tarde_hacia_el_norte = adv2))
guardar_tabla(conf, "confianza_alternativas")
anotar("Confianza de cada alternativa (evidencia, mecanismo, conducta y robustez en escenarios adversos):")
for (i in seq_len(nrow(conf)))
  anotar(sprintf("  %s · %s: %s el 1er año, %s a 10 años; peor supuesto %s (%s); confianza %s", conf$caso[i], conf$nombre[i],
                 pct_es(conf$reduccion_1er_anio[i]), ifelse(is.na(conf$reduccion_10_anios[i]), "no aplica", pct_es(conf$reduccion_10_anios[i])), conf$peor_supuesto[i],
                 pct_es(conf$reduccion_peor_supuesto[i]), toupper(conf$confianza[i])))
lag <- readr::read_csv(file.path(DIR_DATOS, "matriz_lagunas.csv"), show_col_types = FALSE)
guardar_tabla(lag, "matriz_lagunas")
lim <- readr::read_csv(file.path(DIR_DATOS, "limitaciones_por_resultado.csv"), show_col_types = FALSE)
guardar_tabla(lim, "limitaciones_por_resultado")
rf <- registro_fuentes()
guardar_tabla(rf, "registro_fuentes")
anotar(sprintf("Registro de fuentes: %d entradas (%d ficheros oficiales con su huella SHA-256 y %d fuentes documentales, sin copia guardada).",
               nrow(rf), sum(rf$tipo == "dato oficial"), sum(rf$tipo != "dato oficial")))
fich <- fichas_alternativas(conf, crit, list(manana_hacia_santa_cruz = res1, tarde_hacia_el_norte = res2), af3, adv, g_central)
guardar_tabla(fich, "fichas_alternativas")
anotar("Ficha de cada alternativa (reducción simulada de la demora; mediana y p10-p90 el 1er año; a 10 años; 2030 con crecimiento 0-1 %; escenarios adversos):")
for (i in seq_len(nrow(fich)))
  anotar(sprintf("  %s · %s · %s · %s: 1er año %s (%s-%s); 10 años %s; 2030 %s-%s; adversos %s-%s; confianza %s. Supuesto clave: %s. Limitación: %s",
                 fich$caso[i], fich$nombre[i], fich$tramo[i], fich$horario[i], pct_es(fich$mediana_1er_anio[i]), pct_es(fich$p10_1er_anio[i]),
                 pct_es(fich$p90_1er_anio[i]), ifelse(is.na(fich$mediana_10_anios[i]), "no aplica", pct_es(fich$mediana_10_anios[i])),
                 pct_es(fich$min_2030_crecimiento[i]), pct_es(fich$max_2030_crecimiento[i]), pct_es(fich$min_escenarios_adversos[i]),
                 pct_es(fich$max_escenarios_adversos[i]), fich$confianza[i], fich$supuesto_clave[i], fich$limitacion_principal[i]))

# ---- 9. Proyectos y verificación de los apuntes ------------------------------
anotar("== 9. Proyectos y verificación de afirmaciones ==")
proy <- readr::read_csv(file.path(DIR_DATOS, "proyectos.csv"), show_col_types = FALSE)
afir <- readr::read_csv(file.path(DIR_DATOS, "afirmaciones_apuntes.csv"), show_col_types = FALSE)
guardar_grafico(grafico_proyectos(proy), "g08_proyectos", 9, 5.6)
guardar_grafico(grafico_verificacion(afir), "g09_verificacion_apuntes", 9, 5.6)
tab <- table(factor(afir$veredicto, levels = names(COLORES_VEREDICTO)))
anotar(paste0("Veredictos (", nrow(afir), " afirmaciones): ",
              paste(names(tab), tab, sep = " = ", collapse = "; ")))
comprobaciones <- comprobar_aritmetica_apuntes()
guardar_tabla(comprobaciones, "comprobaciones_aritmeticas")
for (i in seq_len(nrow(comprobaciones)))
  anotar(sprintf("  [%s] %s", comprobaciones$resultado[i], comprobaciones$comprobacion[i]))

# ---- 10. Comprobaciones numéricas del modelo -------------------------------------
anotar("== 10. Comprobaciones numéricas del modelo ==")
va <- comprobaciones_modelo(par, list("mañana" = mc1, "tarde" = mc2))
guardar_tabla(va, "comprobaciones_modelo")
for (i in seq_len(nrow(va))) anotar(sprintf("  [%s] %s: %s%s", va$id[i], va$comprobacion[i], va$resultado[i], ifelse(va$cumple[i], "", " · NO CUMPLE")))

# ---- 11. Tablas limpias para el panel de resultados ---------------------------
dir.create(file.path("salidas", "panel"), showWarnings = FALSE)
panel <- function(df, nombre) readr::write_csv(df, file.path("salidas", "panel", paste0(nombre, ".csv")), na = "")
# Seis decimales: el panel redondea al mostrar con la misma regla que los documentos (no se redondea dos veces)
rp <- function(x) round(x, 6)
panel(imd |> transmute(anio, estacion_id, estacion = etiqueta, orden, zona, imd_ascendentes, imd_descendentes,
                       imd_total, imd_pesados, velocidad_media), "imd_tf5_2018_2025")
panel(carga |> transmute(estacion_id, estacion = etiqueta, orden, sentido, carriles, imd_sentido = imd_dir,
                         imd_por_carril = rp(imd_por_carril), k_crit_min = rp(k_crit_min),
                         k_crit_central = rp(k_crit_cen), k_crit_max = rp(k_crit_max)), "capacidad_2025")
panel(bind_rows(res1 |> mutate(caso = "manana_hacia_santa_cruz"), res2 |> mutate(caso = "tarde_hacia_el_norte")) |>
        transmute(caso, escenario, alternativa = etiqueta, horizonte = ifelse(escenario == "tarificacion", "neto",
                                                                              sub(".*_", "", escenario)),
                  p10 = rp(p10), mediana = rp(mediana), p90 = rp(p90)), "modelo_reduccion_demora")
panel(tibble(objetivo = c("no_empeorar", "reducir_a_la_mitad"),
             mediana = rp(c(median(bv$equilibrio), median(bv$mitad))),
             p10 = rp(c(quantile(bv$equilibrio, 0.1), quantile(bv$mitad, 0.1))),
             p90 = rp(c(quantile(bv$equilibrio, 0.9), quantile(bv$mitad, 0.9)))), "bus_vao_trasvase")
panel(curva_bus_vao, "bus_vao_curva")
panel(proy, "proyectos")
panel(afir, "afirmaciones_apuntes")
k_ref <- par |> filter(parametro == "k_dir") |>      # banda de la literatura para el gráfico de k crítico
  mutate(parametro = "k_dir_referencia", caso = "referencia",
         descripcion = paste("Cuota habitual de la hora punta en autovías urbanas según la literatura (2·K·D con K = 0,09-0,10",
                             "y D = 0,50-0,65). Es la banda de referencia del gráfico de k crítico; el modelo de los dos cuellos",
                             "no la usa (la punta sale de los aforos)"),
         transferibilidad = "Referencia de la literatura para comparar; no entra en la simulación de los cuellos")
panel(bind_rows(par_c1_doc |> mutate(caso = "manana_hacia_santa_cruz"), par_c2_doc |> mutate(caso = "tarde_hacia_el_norte"), k_ref) |>
        select(caso, parametro, descripcion, minimo, central, maximo, unidad, tipo, fuente, transferibilidad) |>
        mutate(across(c(minimo, central, maximo), ~ signif(.x, 3))), "parametros_modelo")
panel(tp, "transporte_publico_viajeros")
panel(perf |> left_join(ESTACIONES_TF5 |> select(estacion_id, etiqueta, orden), by = "estacion_id") |>
        left_join(fiab |> select(estacion_id, sentido, velocidad_fiable), by = c("estacion_id", "sentido")) |>
        transmute(estacion_id, estacion = etiqueta, orden, sentido, hora, carriles, veh = rp(veh), veh_carril = rp(veh_carril),
                  cuota_lenta = ifelse(velocidad_fiable, rp(cuota_lenta), NA),
                  exceso_lento = ifelse(velocidad_fiable, rp(pmax(cuota_lenta - base_noche, 0)), NA),
                  prob_congestion = rp(prob_congestion), dias), "perfil_horario_2025")
panel(rc |> transmute(estacion_id, estacion = etiqueta, orden, sentido, dias = dias_con_velocidad, velocidad_utilizable, horas_media = rp(horas_media),
                      horas_p25, horas_mediana, horas_p75, dias_sin_congestion, hora_inicio_tipica, hora_fin_tipica), "congestion_diaria_2025")
panel(bind_rows(cmp_ull |> mutate(comparacion = "oct_nov_2025_vs_2024"), cmp_26 |> mutate(comparacion = "ene_sep_2026_vs_2025")) |>
        transmute(comparacion, estacion_id, estacion = etiqueta, orden, sentido, dias_antes = dias_a, dias_despues = dias_b,
                  veh_7_9_antes = rp(veh_horas_a), veh_7_9_despues = rp(veh_horas_b), diferencia = rp(dif),
                  ic_inf = rp(ic_inf), ic_sup = rp(ic_sup), p_valor = rp(p_valor),
                  horas_cola_antes = rp(horas_cong_a), horas_cola_despues = rp(horas_cong_b),
                  cambio_reparto_carriles = rp(cambio_reparto), comparable), "comparaciones")
panel(bind_rows(curva1 |> mutate(caso = "manana_hacia_santa_cruz"), curva2 |> mutate(caso = "tarde_hacia_el_norte")) |>
        mutate(across(c(p10, mediana, p90), rp)), "tercer_carril_holgura")
panel(bind_rows(holg_hora |> mutate(caso = "manana_hacia_santa_cruz"), holg2_hora |> mutate(caso = "tarde_hacia_el_norte")) |>
        filter(horas >= 10) |>     # horas con cola al menos 10 días (las demás son casos sueltos)
        select(caso, hora, horas, p10, mediana, p90, sin_holgura) |> mutate(across(c(p10, mediana, p90, sin_holgura), rp)), "holgura_por_hora")
panel(bind_rows(sc1 |> mutate(caso = "manana_hacia_santa_cruz"), sc2 |> mutate(caso = "tarde_hacia_el_norte")) |>
        transmute(caso, regla, n_validas, escenario, alternativa = etiqueta, mediana = rp(mediana),
                  p10 = rp(p10), p90 = rp(p90), descarga_mediana = rp(descarga_mediana)), "sensibilidad_calibracion")
panel(val_h |> group_by(regla, gravedad, estacion = etiqueta, sentido) |> summarise(casos = n(), filas = sum(filas), .groups = "drop"),
      "validacion_horarios")
panel(va |> mutate(valor = signif(valor, 6)), "comprobaciones_modelo")
panel(meta_h, "procedencia_horarios")
panel(hcol |> mutate(across(where(is.numeric), ~ round(.x, 6))), "horario_cola")
panel(cob_res |> mutate(across(starts_with("pct"), rp)), "cobertura_resumen")
panel(bind_rows(did, did_jj) |> transmute(control, estacion_id, estacion = etiqueta, sentido, variable, indicador, lectivo_antes = rp(lectivo_antes),
                       lectivo_despues = rp(lectivo_despues), julio_antes = rp(julio_antes), julio_despues = rp(julio_despues),
                       dif_lectivo = rp(dif_lectivo), ic_lectivo_inf = rp(ic_lectivo_inf), ic_lectivo_sup = rp(ic_lectivo_sup),
                       efecto_did = rp(efecto_did), ic_inf = rp(ic_inf), ic_sup = rp(ic_sup), dias, comparable),
      "ull_diferencias_en_diferencias")
panel(di |> transmute(estacion_id, estacion = etiqueta, orden, variable, indicador, mes, mes_antes, tipo_mes, valor_antes = rp(valor_antes),
                      valor = rp(valor), dif = rp(dif), ic_inf = rp(ic_inf), ic_sup = rp(ic_sup), dias_antes, dias), "diferencias_interanuales")
panel(val |> mutate(across(where(is.numeric), ~ round(.x, 6))), "validacion_modelo")
panel(val_err |> mutate(across(where(is.numeric), rp)), "validacion_perfil")
panel(pp |> mutate(across(where(is.numeric), ~ signif(.x, 4))), "prior_posterior")
panel(dg |> mutate(across(where(is.numeric), rp)), "diagnostico_reducciones")
panel(met |> mutate(across(where(is.numeric), ~ round(.x, 6))), "metricas_alternativas")
panel(estab |> mutate(across(where(is.numeric), ~ round(.x, 6))), "estabilidad_percentiles")
panel(evo |> mutate(across(where(is.numeric), rp)), "evolucion_sin_actuar")
panel(af |> mutate(across(where(is.numeric), rp)), "alternativas_2030")
panel(adv |> mutate(across(where(is.numeric), rp)), "escenarios_adversos")
panel(tpt |> mutate(across(where(is.numeric), rp)), "transporte_publico_trasvase")
panel(conf |> mutate(across(where(is.numeric), rp)), "confianza_alternativas")
panel(lag, "matriz_lagunas")
panel(lim, "limitaciones_por_resultado")
panel(rf |> select(id, fuente, tipo, url, fecha_fuente, consultado, sha256, uso), "registro_fuentes")
panel(pob, "poblacion_tenerife")
panel(esc_dem, "escenarios_demanda")
panel(vdt |> mutate(across(where(is.numeric), ~ round(.x, 6))), "validacion_diaria")
panel(dgd |> mutate(across(where(is.numeric), ~ round(.x, 6))), "diagnostico_descarga")
panel(geo_cap |> transmute(estacion_id, estacion = etiqueta, sentido, tramo, seccion_inventario_2006, carriles_aforados, carriles_inventario_2006,
                           carriles_efectivos_modelo, papel_en_el_modelo, estado, explicacion_posible, escenario_alternativo,
                           p99_por_carril_2025 = rp(p99_por_carril_2025), capacidad_p99_sentido_2025 = rp(capacidad_p99_sentido_2025),
                           carril_dias_sin_vehiculos, meses_con_horas_incompletas, fuentes), "geometria")
panel(bt$resumen |> mutate(across(where(is.numeric), ~ round(.x, 6))), "balance_tramos")
panel(bind_rows(sh1$resultados, sh2$resultados) |> mutate(across(where(is.numeric), rp)), "sensibilidad_holgura")
panel(bind_rows(sh1$holgura, sh2$holgura) |> mutate(across(where(is.numeric), rp)), "sensibilidad_holgura_hora")
panel(proc |> select(id, organismo, conjunto, recurso, formato, url, licencia, modificado_origen, descargado, bytes_original, sha256_original,
                     copia_local, cobertura, filtros, unidades, contraste_catalogo, conservacion_totales, integridad, verificacion), "procedencia")
panel(bind_rows(dm1$filtros, dm2$filtros) |> mutate(across(where(is.numeric), ~ round(.x, 6))), "montecarlo_filtros")
panel(bind_rows(dm1$parametros, dm2$parametros) |> mutate(across(where(is.numeric), ~ signif(.x, 4))), "montecarlo_parametros")
panel(fich |> mutate(across(where(is.numeric), rp)), "fichas_alternativas")
panel(prev |> mutate(across(where(is.numeric), rp)), "previsiones")
panel(idm |> mutate(across(where(is.numeric), ~ round(.x, 6))), "indicadores_demora")
panel(sdep |> mutate(across(where(is.numeric), ~ round(.x, 6))), "sensibilidad_depuracion")
panel(af3 |> mutate(across(where(is.numeric), rp)), "alternativas_2030_por_crecimiento")
panel(vcx |> mutate(across(where(is.numeric), rp)), "validacion_cruzada")
panel(elx |> mutate(across(where(is.numeric), rp)), "eleccion_especificacion")
panel(dem |> mutate(across(where(is.numeric), rp)), "diferencias_emparejadas")
panel(dreg |> mutate(across(where(is.numeric), rp)), "diferencias_emparejadas_por_regla")
panel(cpr, "coste_plazo_riesgo")
panel(ret |> mutate(across(where(is.numeric), rp)), "retraso_obra")
panel(cr1 |> mutate(across(where(is.numeric), rp)), "cola_remanente")
panel(sem |> mutate(across(where(is.numeric), rp)), "montecarlo_otras_semillas")
panel(prv |> mutate(across(where(is.numeric), rp)), "montecarlo_previas_alternativas")
panel(corr |> mutate(across(where(is.numeric), rp)), "montecarlo_correlaciones")
panel(rda, "dias_atipicos_resumen")
panel(ssa |> mutate(across(where(is.numeric), rp)), "sensibilidad_sin_dias_atipicos")
panel(ug, "uso_de_la_geometria")
panel(cpo |> select(conjunto, recurso_id, nombre_publicado, url_publicada, fuente_contraste, consultado, url_usada_al_descargar,
                    en_la_instantanea_del_portal, nombre_igual, licencia_igual, diferencia_modificacion_h, resultado), "contraste_publicacion_original")
if (!is.null(sdp)) panel(sdp |> mutate(across(where(is.numeric), rp)), "sensibilidad_prevision_descarga")

# Metadatos de los gráficos: tipo de resultado, horizonte, hipótesis e incertidumbre de cada uno
mg <- metadatos_graficos()
guardar_tabla(mg, "graficos_metadatos")
panel(mg, "graficos_metadatos")
anotar(sprintf("Gráficos: %d generados; %d con su tipo de resultado, horizonte, hipótesis e incertidumbre en graficos_metadatos.csv%s.",
               length(list.files(DIR_GRAFICOS, pattern = "\\.png$")), sum(mg$generado),
               ifelse(all(mg$generado) && length(list.files(DIR_GRAFICOS, pattern = "\\.png$")) == nrow(mg), "", " · FALTAN METADATOS O GRÁFICOS")))

# Entradas sin cambios durante la ejecución (mismas huellas al empezar y al acabar)
huellas_fin <- manifiesto(ENTRADAS)
clave_h <- function(h) paste(h$fichero, h$huella)
cambiadas <- unique(c(huellas_inicio$fichero[!clave_h(huellas_inicio) %in% clave_h(huellas_fin)],
                      huellas_fin$fichero[!clave_h(huellas_fin) %in% clave_h(huellas_inicio)]))
if (length(cambiadas)) {
  warning(sprintf("Entradas modificadas durante la ejecución (las salidas pueden no corresponder a ellas%s): %s",
                  if (DESCARGAR_HORARIOS || CONTRASTAR_EN_LINEA) "; con DESCARGAR_HORARIOS o CONTRASTAR_EN_LINEA es normal en datos/" else "",
                  paste(cambiadas, collapse = ", ")))
} else anotar(sprintf("Entradas sin cambios durante la ejecución: los %d ficheros de main.R, R/, tests/, entorno/, renv.lock y datos/ tienen la misma huella al empezar y al acabar.",
                      nrow(huellas_fin)))
}, warning = registrar_aviso)   # fin del bloque que recoge los avisos

writeLines(log_txt, file.path("salidas", "resumen_resultados.txt"), useBytes = TRUE)
writeLines(c(sprintf("Avisos durante la ejecución de main.R: %d", length(avisos)), avisos), file.path("salidas", "registro_avisos.txt"), useBytes = TRUE)
registrar_sesion(inicio = inicio)
# Manifiesto: huella de cada fichero de código, datos y resultados al terminar la ejecución
readr::write_csv(manifiesto(c("main.R", "R", "tests", "entorno", "renv.lock", "datos", "salidas")), file.path("salidas", "manifiesto_ejecucion.csv"))
message(sprintf("\nListo en %s min (%d avisos). Resultados en la carpeta 'salidas/'.",
                num_es(as.numeric(difftime(Sys.time(), inicio, units = "mins")), 0.1), length(avisos)))
