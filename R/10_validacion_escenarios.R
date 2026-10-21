# =============================================================================
# 10_validacion_escenarios.R · Validación, previsión y robustez
# -----------------------------------------------------------------------------
# Organiza el análisis en tres preguntas:
#   1. Qué sabemos: cobertura y calidad de los aforos, horario real de la cola y
#      asociación (antes y después) de los horarios escalonados de la ULL y de la pasarela.
#   2. Qué estimamos: parámetros antes y después de calibrar, diagnóstico de los
#      resultados extremos, varias métricas de demora y validación con datos y
#      variables que no se usan para calibrar.
#   3. Qué prevemos: evolución sin actuar con crecimiento de la demanda,
#      alternativas en el año de puesta en servicio y escenarios adversos.
# =============================================================================

# ---- 1. Qué sabemos ------------------------------------------------------------

# Horario de la cola en cada día laborable válido (solo días con velocidad en todas
# las horas de la ventana): primera hora congestionada (inicio) y última + 1 (fin).
# Las horas son las de la marca de tiempo oficial (00 a 23 = hora que empieza: cada
# día tiene marcas de 00:00 a 23:00; el diccionario del Cabildo no lo precisa).
horario_cola <- function(sc, est, sen, anios = 2025, horas = 0:23) {
  sc |> filter(anio %in% anios, estacion_id == est, sentido == sen, hora %in% horas) |>
    group_by(dia) |>
    filter(n() == length(horas), all(!is.na(cuota_lenta))) |>
    summarise(horas_cola = sum(congestionada),
              inicio = if (any(congestionada)) min(hora[congestionada]) else NA_real_,
              fin = if (any(congestionada)) max(hora[congestionada]) + 1 else NA_real_, .groups = "drop")
}

resumen_horario <- function(hc, etiqueta) {
  q <- function(x, p) as.numeric(stats::quantile(x, p, na.rm = TRUE))
  tibble(cuello = etiqueta, dias = nrow(hc), dias_con_cola = sum(!is.na(hc$inicio)),
         horas_cola_mediana = q(hc$horas_cola, 0.5),
         inicio_p10 = q(hc$inicio, 0.1), inicio_p25 = q(hc$inicio, 0.25), inicio_mediana = q(hc$inicio, 0.5),
         inicio_p75 = q(hc$inicio, 0.75), inicio_p90 = q(hc$inicio, 0.9),
         fin_p10 = q(hc$fin, 0.1), fin_p25 = q(hc$fin, 0.25), fin_mediana = q(hc$fin, 0.5),
         fin_p75 = q(hc$fin, 0.75), fin_p90 = q(hc$fin, 0.9))
}

# Objetivo de calibración del horario: rango intercuartílico ± 30 min (la misma
# tolerancia que la duración; la resolución horaria de los aforos no da para menos);
# inicio y fin en horas del día
objetivo_horario <- function(hc) {
  q <- function(x, p) as.numeric(stats::quantile(x, p, na.rm = TRUE))
  list(inicio = c(q(hc$inicio, 0.25) - 0.5, q(hc$inicio, 0.75) + 0.5),
       fin = c(q(hc$fin, 0.25) - 0.5, q(hc$fin, 0.75) + 0.5))
}

# Cobertura y calidad por estación, sentido y mes: horas con datos, horas con todos
# los carriles, horas con velocidades utilizables, días laborables y días válidos
dias_del_mes <- function(m) as.integer(format(seq(as.Date(paste0(m, "-01")), by = "month", length.out = 2)[2] - 1, "%d"))

cobertura_calidad <- function(sd, dv, estaciones = EST_CORREDOR) {
  meses <- sort(unique(sd$mes))
  rejilla <- tidyr::crossing(estacion_id = estaciones, sentido = c("ascendente", "descendente"), mes = meses)
  x <- sd |> filter(estacion_id %in% estaciones) |>
    group_by(estacion_id, sentido, mes) |>
    summarise(horas_con_datos = n(), horas_completas = sum(completa),
              horas_velocidad = sum(completa & !is.na(cuota_lenta)), dias_laborables = n_distinct(dia[laborable]),
              .groups = "drop")
  v <- dv |> count(estacion_id, sentido, mes, name = "dias_validos")
  rejilla |> left_join(x, by = c("estacion_id", "sentido", "mes")) |>
    left_join(v, by = c("estacion_id", "sentido", "mes")) |>
    mutate(across(c(horas_con_datos, horas_completas, horas_velocidad, dias_laborables, dias_validos), ~ coalesce(as.numeric(.x), 0)),
           horas_mes = vapply(mes, dias_del_mes, integer(1)) * 24,
           pct_ausente = 1 - horas_con_datos / horas_mes,
           pct_horas_completas = horas_completas / horas_mes,
           pct_horas_velocidad = horas_velocidad / horas_mes) |>
    left_join(ESTACIONES_TF5 |> select(estacion_id, etiqueta, orden), by = "estacion_id") |>
    arrange(orden, sentido, mes) |>
    select(estacion_id, etiqueta, sentido, mes, horas_mes, horas_con_datos, pct_ausente, horas_completas,
           pct_horas_completas, horas_velocidad, pct_horas_velocidad, dias_laborables, dias_validos)
}

# La misma cobertura por hora del día (todo el periodo): ¿faltan más datos de noche
# o en la punta?
cobertura_por_hora <- function(sd, estaciones = EST_CORREDOR) {
  n_dias <- n_distinct(sd$dia)
  sd |> filter(estacion_id %in% estaciones) |>
    group_by(estacion_id, sentido, hora) |>
    summarise(pct_horas_completas = sum(completa) / n_dias,
              pct_horas_velocidad = sum(completa & !is.na(cuota_lenta)) / n_dias, .groups = "drop") |>
    left_join(ESTACIONES_TF5 |> select(estacion_id, etiqueta, orden), by = "estacion_id") |>
    arrange(orden, sentido, hora)
}

# Días con registros duplicados, con un número de horas distinto de 24 o de cambio
# de hora (último domingo de marzo y de octubre). Si las marcas fueran hora local
# con cambio de hora, el domingo de marzo tendría 23 horas y el de octubre una hora
# repetida.
cambio_hora <- function(hp) {
  ultimo_domingo <- function(anio, mes) {
    d <- seq(as.Date(sprintf("%d-%02d-01", anio, mes)), by = "day", length.out = 31)
    d <- d[as.integer(format(d, "%m")) == mes]
    max(d[format(d, "%u") == "7"])
  }
  anios <- sort(unique(hp$anio))
  dst <- as.Date(c(vapply(anios, function(a) as.numeric(ultimo_domingo(a, 3)), numeric(1)),
                   vapply(anios, function(a) as.numeric(ultimo_domingo(a, 10)), numeric(1))), origin = "1970-01-01")
  dup <- hp |> count(estacion_id, carril_id, fecha) |> filter(n > 1) |>
    mutate(dia = as.Date(substr(fecha, 1, 10))) |>
    group_by(dia) |> summarise(registros_duplicados = sum(n - 1), carriles_con_duplicados = n(),
                               horas_duplicadas = paste(sort(unique(substr(fecha, 12, 13))), collapse = " "), .groups = "drop")
  horas_dia <- hp |> distinct(dia, hora) |> count(dia, name = "horas_distintas")
  tibble(dia = sort(unique(hp$dia))) |>
    left_join(dup, by = "dia") |> left_join(horas_dia, by = "dia") |>
    mutate(registros_duplicados = coalesce(registros_duplicados, 0L),
           carriles_con_duplicados = coalesce(carriles_con_duplicados, 0L)) |>
    filter(registros_duplicados > 0 | horas_distintas != 24 | dia %in% dst) |>
    mutate(cambio_de_hora = ifelse(dia %in% dst, ifelse(as.integer(format(dia, "%m")) == 3, "marzo (+1 h)", "octubre (-1 h)"), ""),
           laborable = as.integer(format(dia, "%u")) <= 5)
}

# Efecto de los horarios escalonados de la ULL (curso 2025-26, clases desde el
# 9-9-2025: 13 grados, unos 2.700 estudiantes) con diferencias en diferencias:
#   (lectivo 2025-26 - lectivo 2024-25) - (julio 2026 - julio 2025)
# Meses lectivos: octubre, noviembre y febrero a mayo (sin septiembre, diciembre,
# enero, junio ni agosto, que mezclan arranque de curso, vacaciones o exámenes).
# Julio, sin clases, es el grupo de control: recoge lo que cambia de un año a otro en
# todo el corredor (obras, economía, transporte público), con el supuesto de que eso
# afecta por igual a julio y a los meses lectivos (tendencias paralelas). Ese supuesto
# no se puede contrastar con datos previos: el Cabildo no publica aforos horarios de
# enero a agosto de 2024. IC 95 % por bootstrap por bloques de semanas (los días de
# una misma semana no son independientes).
MESES_LECTIVOS_ULL <- list(antes = c("2024-10", "2024-11", "2025-02", "2025-03", "2025-04", "2025-05"),
                           despues = c("2025-10", "2025-11", "2026-02", "2026-03", "2026-04", "2026-05"))
MESES_CONTROL_ULL <- list(antes = "2025-07", despues = "2026-07")

did_ull <- function(sc, hp = NULL, estaciones = c(93, 99, 103), sentido_ = "descendente", horas = 7:8,
                    horas_cola = 5:11, control = MESES_CONTROL_ULL, n_boot = 2000, semilla = 3) {
  celdas <- c(stats::setNames(rep("lectivo antes", length(MESES_LECTIVOS_ULL$antes)), MESES_LECTIVOS_ULL$antes),
              stats::setNames(rep("lectivo despues", length(MESES_LECTIVOS_ULL$despues)), MESES_LECTIVOS_ULL$despues),
              stats::setNames(rep("julio antes", length(control$antes)), control$antes),
              stats::setNames(rep("julio despues", length(control$despues)), control$despues))
  d <- sc |> filter(estacion_id %in% estaciones, sentido == sentido_, mes %in% names(celdas)) |>
    group_by(estacion_id, sentido, mes, dia) |>
    summarise(v = sum(veh[hora %in% horas]), v_dia = sum(veh),
              cola = if (isTRUE(first(velocidad_fiable)) && all(!is.na(cuota_lenta[hora %in% horas_cola])))
                as.numeric(sum(congestionada[hora %in% horas_cola])) else NA_real_, .groups = "drop") |>
    mutate(cuota = v / v_dia, grupo = unname(celdas[mes]), semana = format(dia, "%G-%V"))
  comp <- if (is.null(hp)) NULL else
    comparar_periodos(sc, c(MESES_LECTIVOS_ULL$antes, control$antes),
                      c(MESES_LECTIVOS_ULL$despues, control$despues), horas = horas,
                      estaciones = estaciones, hp = hp) |>
      filter(sentido == sentido_) |> select(estacion_id, cambio_reparto, comparable)
  grupos <- c("lectivo antes", "lectivo despues", "julio antes", "julio despues")
  did <- function(m) (m[2] - m[1]) - (m[4] - m[3])
  nombres <- c(v = sprintf("Vehículos de %d a %d h por día", min(horas), max(horas) + 1),
               cuota = sprintf("Parte del tráfico del día que pasa de %d a %d h", min(horas), max(horas) + 1),
               cola = sprintf("Horas de cola por día (de %d a %d h)", min(horas_cola), max(horas_cola) + 1))
  set.seed(semilla)
  out <- bind_rows(lapply(split(d, d$estacion_id), function(x) bind_rows(lapply(names(nombres), function(y) {
    x <- x[!is.na(x[[y]]), ]
    por <- lapply(grupos, function(g) split(x[[y]][x$grupo == g], x$semana[x$grupo == g]))
    n_dias <- vapply(por, function(z) length(unlist(z)), integer(1))
    if (any(n_dias < 10)) return(NULL)
    medias <- vapply(por, function(z) mean(unlist(z)), numeric(1))
    mb <- vapply(seq_len(n_boot), function(b)                        # remuestrea semanas completas
      vapply(por, function(z) mean(unlist(z[sample.int(length(z), length(z), replace = TRUE)])), numeric(1)),
      numeric(4))
    boot <- apply(mb, 2, did)
    boot_lect <- mb[2, ] - mb[1, ]
    tibble(estacion_id = x$estacion_id[1], sentido = sentido_, variable = y, indicador = nombres[[y]],
           lectivo_antes = medias[1], lectivo_despues = medias[2], julio_antes = medias[3], julio_despues = medias[4],
           dif_lectivo = medias[2] - medias[1],
           ic_lectivo_inf = as.numeric(stats::quantile(boot_lect, 0.025)), ic_lectivo_sup = as.numeric(stats::quantile(boot_lect, 0.975)),
           dif_julio = medias[4] - medias[3],
           efecto_did = did(medias), ic_inf = as.numeric(stats::quantile(boot, 0.025)),
           ic_sup = as.numeric(stats::quantile(boot, 0.975)),
           dias = sum(n_dias), semanas = sum(vapply(por, length, integer(1))))
  }))))
  if (!is.null(comp)) out <- out |> left_join(comp, by = "estacion_id")
  out |> left_join(ESTACIONES_TF5 |> select(estacion_id, etiqueta, orden), by = "estacion_id") |>
    arrange(orden, match(variable, names(nombres)))
}

# Diferencia interanual mes a mes (mismo mes del año anterior) con IC 95 % (Welch)
# de dos medidas: vehículos de 7 a 9 h y horas de cola de la mañana. Muestra si el
# cambio se concentra en los meses con clases (horarios de la ULL) o después del
# 20-05-2026 (cierre de los pasos de peatones de la glorieta del Padre Anchieta al
# abrir la pasarela).
TIPO_MES_ULL <- function(mes) dplyr::case_when(
  mes %in% MESES_LECTIVOS_ULL$despues ~ "Meses lectivos del curso 2025-26 (horarios escalonados)",
  mes %in% c("2026-06", "2026-07", "2026-09") ~ "Junio-septiembre de 2026 (después de abrir la pasarela del Padre Anchieta)",
  mes == "2025-09" ~ "Septiembre de 2025 (arranque de curso)",
  mes == "2026-01" ~ "Enero de 2026 (exámenes)",
  TRUE ~ "Otros meses")

dif_interanual <- function(sc, estaciones = c(93, 99, 103), sentido_ = "descendente", horas = 7:8, horas_cola = 5:11) {
  d <- sc |> filter(estacion_id %in% estaciones, sentido == sentido_) |>
    group_by(estacion_id, mes, dia) |>
    summarise(veh = sum(veh[hora %in% horas]),
              cola = if (isTRUE(first(velocidad_fiable)) && all(!is.na(cuota_lenta[hora %in% horas_cola])))
                as.numeric(sum(congestionada[hora %in% horas_cola])) else NA_real_, .groups = "drop")
  meses <- sort(unique(d$mes))
  previo <- function(m) sprintf("%d-%s", as.integer(substr(m, 1, 4)) - 1, substr(m, 6, 7))
  pares <- tibble(mes = meses, mes_antes = vapply(meses, previo, character(1))) |> filter(mes_antes %in% meses)
  nombres <- c(veh = sprintf("Vehículos de %d a %d h por día", min(horas), max(horas) + 1),
               cola = sprintf("Horas de cola por día (de %d a %d h)", min(horas_cola), max(horas_cola) + 1))
  bind_rows(lapply(seq_len(nrow(pares)), function(i) bind_rows(lapply(estaciones, function(e) bind_rows(lapply(names(nombres), function(v) {
    a <- d[[v]][d$estacion_id == e & d$mes == pares$mes_antes[i]]; b <- d[[v]][d$estacion_id == e & d$mes == pares$mes[i]]
    a <- a[!is.na(a)]; b <- b[!is.na(b)]
    if (length(a) < 8 || length(b) < 8) return(NULL)
    tt <- tryCatch(stats::t.test(b, a), error = function(err) NULL)
    tibble(estacion_id = e, variable = v, indicador = nombres[[v]], mes = pares$mes[i], mes_antes = pares$mes_antes[i],
           dias_antes = length(a), dias = length(b), valor_antes = mean(a), valor = mean(b), dif = mean(b) - mean(a),
           ic_inf = if (is.null(tt)) NA_real_ else tt$conf.int[1], ic_sup = if (is.null(tt)) NA_real_ else tt$conf.int[2])
  })))))) |>
    mutate(tipo_mes = TIPO_MES_ULL(mes)) |>
    left_join(ESTACIONES_TF5 |> select(estacion_id, etiqueta, orden), by = "estacion_id") |>
    arrange(orden, variable, mes)
}

grafico_dif_interanual <- function(di) {
  d <- di |> mutate(fecha = as.Date(paste0(mes, "-01")),
                    etiqueta = factor(etiqueta, levels = unique(etiqueta[order(orden)])),
                    indicador = factor(indicador, levels = unique(indicador)))
  pal <- c("Meses lectivos del curso 2025-26 (horarios escalonados)" = PAL[["azul"]],
           "Junio-septiembre de 2026 (después de abrir la pasarela del Padre Anchieta)" = PAL[["naranja"]],
           "Septiembre de 2025 (arranque de curso)" = PAL[["violeta"]], "Enero de 2026 (exámenes)" = TINTA_MUTE)
  ggplot(d, aes(fecha, dif, colour = tipo_mes)) +
    geom_hline(yintercept = 0, colour = "#c3c2b7", linewidth = 0.4) +
    geom_linerange(aes(ymin = ic_inf, ymax = ic_sup), linewidth = 0.8) +
    geom_point(size = 2) +
    facet_grid(indicador ~ etiqueta, scales = "free_y", labeller = labeller(indicador = label_wrap_gen(22))) +
    scale_colour_manual(values = pal, name = NULL) +
    scale_y_continuous(labels = function(x) ifelse(abs(x) >= 10, num_es(x, 1), num_es(x, 0.1))) +
    scale_x_date(date_breaks = "4 months", date_labels = "%m-%y") +
    guides(colour = guide_legend(nrow = 2)) +
    labs(title = "Hacia Santa Cruz por la mañana: cambio frente al mismo mes del año anterior",
         subtitle = envolver(paste("Días laborables válidos; punto: diferencia de medias; línea: IC 95 % (Welch). Horarios escalonados de la ULL",
                                   "desde el 9-9-2025 (13 grados, unos 2.700 estudiantes); pasarela del Padre Anchieta abierta el 18-5-2026,",
                                   "con cierre de los 11 pasos de peatones de la glorieta dos días después."), 112),
         x = NULL, y = "Diferencia interanual",
         caption = envolver(paste("Fuente: aforos horarios por carril del Cabildo de Tenerife (datos.tenerife.es); ULL (19-06-2025, 09-09-2025);",
                                  "Diario de Avisos (05-2026). No hay aforos horarios publicados de enero a agosto de 2024 ni de diciembre de 2024 en el",
                                  "extracto, por eso faltan esos meses."), 150)) +
    tema_tf5(9.5) + theme(legend.position = "top", strip.text.y = element_text(angle = 0, hjust = 0))
}

# Serie mensual del tráfico en cada hora de la punta (para ver si cambia a partir
# de septiembre de 2025)
serie_mensual_punta <- function(sc, estaciones = c(93, 99, 103), sentido_ = "descendente", horas = 6:9) {
  sc |> filter(estacion_id %in% estaciones, sentido == sentido_) |>
    group_by(estacion_id, mes, dia) |> mutate(v_dia = sum(veh)) |> ungroup() |>
    filter(hora %in% horas) |>
    group_by(estacion_id, mes, hora) |>
    summarise(cuota = mean(veh / v_dia), veh = mean(veh), dias = n_distinct(dia), .groups = "drop") |>   # cuota antes de redefinir veh
    left_join(ESTACIONES_TF5 |> select(estacion_id, etiqueta, orden), by = "estacion_id")
}

grafico_serie_punta <- function(sm) {
  d <- sm |> mutate(fecha = as.Date(paste0(mes, "-15")), franja = sprintf("%02d-%02d h", hora, hora + 1),
                    etiqueta = factor(paste(etiqueta, "hacia Santa Cruz"),
                                      levels = unique(paste(etiqueta, "hacia Santa Cruz")[order(orden)])))
  cols <- c(PAL[["violeta"]], PAL[["azul"]], PAL[["naranja"]], PAL[["aqua"]])[seq_along(unique(d$franja))]
  ggplot(d, aes(fecha, veh, colour = franja)) +
    annotate("rect", xmin = as.Date("2025-09-09"), xmax = max(d$fecha) + 20, ymin = -Inf, ymax = Inf, fill = "#f0efec") +
    geom_line(linewidth = 0.7) + geom_point(size = 1.3) +
    facet_wrap(~etiqueta, ncol = 1, scales = "free_y") +
    scale_colour_manual(values = cols, name = NULL) +
    scale_y_continuous(labels = function(x) num_es(x)) +
    scale_x_date(date_breaks = "3 months", date_labels = "%m-%Y") +
    labs(title = "Tráfico hacia Santa Cruz en cada hora de la punta, mes a mes",
         subtitle = envolver(paste("Vehículos por hora en días laborables válidos (sin agosto). Sombreado: curso 2025-26, con",
                                   "horarios escalonados en 13 grados de la ULL desde el 9 de septiembre de 2025 (unos 2.700 estudiantes)."), 110),
         x = NULL, y = "Vehículos por hora",
         caption = "Fuente: aforos horarios por carril del Cabildo de Tenerife (datos.tenerife.es); ULL (19-06-2025 y 09-09-2025).") +
    tema_tf5(10) + theme(legend.position = "top")
}

# ---- 2. Qué estimamos -----------------------------------------------------------

# Parámetros antes (lo que se supone) y después de calibrar (lo compatible con lo
# medido). La tasa de aceptación indica cuánto filtra la calibración: los resultados
# son condicionales a ese filtro (no son probabilidades incondicionales).
prior_posterior <- function(par, mc_todo, mc, caso) {
  q <- function(x, p) as.numeric(stats::quantile(x, p, na.rm = TRUE))
  vars <- intersect(par$parametro, names(mc$draws))
  vars <- vars[vapply(vars, function(v) stats::sd(mc_todo$draws[[v]]) > 0, logical(1))]
  bind_rows(lapply(vars, function(v) {
    a <- mc_todo$draws[[v]]; b <- mc$draws[[v]]
    tibble(caso = caso, parametro = v, previa_p10 = q(a, 0.1), previa_mediana = q(a, 0.5), previa_p90 = q(a, 0.9),
           posterior_p10 = q(b, 0.1), posterior_mediana = q(b, 0.5), posterior_p90 = q(b, 0.9),
           estrechamiento = 1 - (q(b, 0.9) - q(b, 0.1)) / (q(a, 0.9) - q(a, 0.1)))
  })) |>
    mutate(aceptadas = mc$n_validas, simuladas = mc$n_total, tasa_aceptacion = mc$n_validas / mc$n_total)
}

# Diagnóstico de los resultados extremos: una reducción del 100 % significa demora
# cero (la alternativa elimina la cola en esa simulación), no un tope numérico; el
# denominador (demora sin actuar) nunca es cero en las simulaciones calibradas
diagnostico_reducciones <- function(mc, caso) {
  base <- mc$resultados |> filter(escenario == "base") |> select(sim, base_vh = demora_vh)
  mc$resultados |> filter(escenario != "base") |>
    left_join(base, by = "sim") |>
    group_by(escenario) |>
    summarise(simulaciones = n(), elimina_cola = mean(reduccion >= 0.995), empeora = mean(reduccion < -0.005),
              reduccion_mediana = median(reduccion), reduccion_p90 = as.numeric(stats::quantile(reduccion, 0.9)),
              base_demora_minima_vh = min(base_vh), horas_cola_restantes_mediana = median(horas_con_cola),
              cola_al_final_del_dia = mean(cola_final > 0.5), .groups = "drop") |>
    mutate(caso = caso, etiqueta = unname(ETIQUETAS_ESC[escenario]),
           orden = match(escenario, names(ETIQUETAS_ESC))) |>
    arrange(orden) |> select(-orden) |> relocate(caso, escenario, etiqueta)
}

# Varias métricas por alternativa (mediana de las simulaciones calibradas): la
# reducción en vehículos·hora no cuenta toda la historia
metricas_alternativas <- function(mc, caso) {
  q <- function(x, p) as.numeric(stats::quantile(x, p))
  mc$resultados |>
    group_by(escenario) |>
    # los percentiles de la demora antes de su mediana (summarise() redefine demora_vh por orden)
    summarise(demora_vh_p10 = q(demora_vh, 0.1), demora_vh_p90 = q(demora_vh, 0.9),
              demora_vh = median(demora_vh), espera_media_punta_min = median(demora_media_punta),
              espera_max_min = median(espera_max), horas_con_cola = median(horas_con_cola),
              horas_cola_como_aforo = median(horas_aforo), cola_max_veh = median(cola_max),
              espera_media_punta_p10 = q(demora_media_punta, 0.1), espera_media_punta_p90 = q(demora_media_punta, 0.9),
              espera_max_p10 = q(espera_max, 0.1), espera_max_p90 = q(espera_max, 0.9),
              horas_cola_como_aforo_p10 = q(horas_aforo, 0.1), horas_cola_como_aforo_p90 = q(horas_aforo, 0.9),
              cola_max_p10 = q(cola_max, 0.1), cola_max_p90 = q(cola_max, 0.9), .groups = "drop") |>
    relocate(demora_vh_p10, demora_vh_p90, .after = cola_max_veh) |>
    mutate(caso = caso, etiqueta = ifelse(escenario == "base", "Sin actuación", unname(ETIQUETAS_ESC[escenario])),
           orden = match(escenario, c("base", names(ETIQUETAS_ESC)))) |>
    arrange(orden) |> select(-orden) |> relocate(caso, escenario, etiqueta)
}

# Salidas por hora del día simuladas en la situación actual (veh/h que pasan por
# el cuello), para compararlas con los aforos
salidas_por_hora <- function(mc, n_max = 300, semilla = 8) {
  set.seed(semilla)
  d <- mc$draws; if (nrow(d) > n_max) d <- d[sample.int(nrow(d), n_max), ]
  m <- vapply(seq_len(nrow(d)), function(i) {
    p <- as.list(d[i, ])
    ht <- if (is.null(mc$holgura_horaria)) NULL else holgura_minutos(mc$holgura_horaria, p$holgura_cuantil)
    r <- evaluar_actual(p, mc$carriles, perfil_de(p, mc$V_dir, mc$perfil_obs), ht)
    as.numeric(tapply(r$s, rep(0:23, each = 60), sum))
  }, numeric(24))
  tibble(hora = 0:23, sim_p10 = apply(m, 1, stats::quantile, 0.1), sim_mediana = apply(m, 1, stats::median),
         sim_p90 = apply(m, 1, stats::quantile, 0.9))
}

# Validación: lo simulado frente a lo medido.
#   · 2025 es la muestra de calibración (duración, horario de la cola y descarga).
#   · Enero-septiembre de 2026 (sin agosto) no se ha usado: validación temporal.
#   · El perfil horario del tráfico no entra en la calibración (solo la demanda del
#     día y la cuota nocturna): validación con una variable no usada.
# Es una validación parcial: no hay tiempos de recorrido ni longitudes de cola
# medidos de forma independiente.
# Cada fila lleva el fenómeno que mide: las dos filas de la descarga miden el mismo (el
# caudal con cola, como parámetro y medido igual que el aforo) y no son dos contrastes
# independientes. Por sentido hay cinco filas.
validacion_modelo <- function(mc, sc, est_cola, est_salida, sen, caso, horas_cola, descarga_aforo = NULL, n_boot = 1000, semilla = 61) {
  obs_anio <- function(a) {
    hc <- horario_cola(sc, est_cola, sen, a, horas_cola)
    cola <- sc |> filter(anio == a, estacion_id == est_cola, sentido == sen, congestionada, hora %in% horas_cola) |>
      select(dia, hora)
    salida <- sc |> filter(anio == a, estacion_id == est_salida, sentido == sen)
    desc <- salida |> semi_join(cola, by = c("dia", "hora"))
    list(hc = hc, descarga = desc$veh, descarga_dia = desc$dia,
         perfil = salida |> group_by(hora) |> summarise(veh = mean(veh), dias = n_distinct(dia), .groups = "drop"))
  }
  o25 <- obs_anio(2025); o26 <- obs_anio(2026)
  d <- mc$draws
  q <- function(x, p) as.numeric(stats::quantile(x, p, na.rm = TRUE))
  # IC 95 % de la mediana observada en 2026, por bootstrap de días (las horas de un mismo día no son independientes)
  ic_mediana <- function(x, dia) {
    ok <- !is.na(x); x <- x[ok]; dia <- dia[ok]
    if (length(x) < 2) return(c(NA_real_, NA_real_))
    set.seed(semilla)
    g <- split(x, dia); k <- length(g)
    b <- vapply(seq_len(n_boot), function(i) stats::median(unlist(g[sample.int(k, k, replace = TRUE)], use.names = FALSE)), numeric(1))
    as.numeric(stats::quantile(b, c(0.025, 0.975)))
  }
  # dias_*: días con observaciones de ese indicador (para la descarga, días con alguna hora con cola)
  fila <- function(indicador, unidad, x25, x26, xs, n25, n26, ic26, uso = "sí (2025)", d25 = nrow(o25$hc), d26 = nrow(o26$hc),
                   fenomeno = indicador) {
    p10 <- q(xs, 0.1); p50 <- q(xs, 0.5); p90 <- q(xs, 0.9)
    tibble(caso = caso, indicador = indicador, fenomeno = fenomeno, unidad = unidad, usado_en_calibracion = uso,
           observado_2025 = x25, observado_2026 = x26, dias_2025 = d25, dias_2026 = d26,
           simulado_p10 = p10, simulado_mediana = p50, simulado_p90 = p90,
           dentro_2026 = x26 >= p10 & x26 <= p90,
           observaciones_2025 = n25, observaciones_2026 = n26,
           error_mediana_2025 = p50 - x25, error_mediana_2026 = p50 - x26,
           error_relativo_2026 = if (unidad == "hora del día") NA_real_ else (p50 - x26) / x26,
           distancia_a_la_banda_2026 = ifelse(x26 < p10, x26 - p10, ifelse(x26 > p90, x26 - p90, 0)),
           ic95_observado_2026_inf = ic26[1], ic95_observado_2026_sup = ic26[2])
  }
  # El modelo se mide como el aforo (horas enteras con >= 60 % de vehículos en cola).
  # Observaciones: días (horas, inicio y fin) u horas con cola (descarga)
  e <- mc$perfil_obs$especificacion
  como_aforo <- identical(mc$objetivo$medida_descarga, "como_aforo")
  uso_param <- if (!is.null(e$factor_descarga) || !is.null(e$cuota_pesados))
    "sí (2025); en el modelo es un parámetro: la descarga de la hora de referencia (carriles x capacidad x (1 - caída)), antes del factor horario y de los pesados, así que no se mide igual que el aforo"
  else "sí (2025); en el modelo es un parámetro (carriles x capacidad x (1 - caída))"
  if (como_aforo) uso_param <- paste0(uso_param, "; la calibración usa la descarga medida igual que el aforo (fila siguiente)")
  uso_igual <- if (como_aforo) "sí (2025): es la descarga que se calibra; en el modelo, caudal que sale en las horas que el aforo contaría con cola"
               else "sí (2025, a través de la descarga); en el modelo, caudal que sale en las horas que el aforo contaría con cola"
  tab <- bind_rows(
    fila("Horas de cola al día (mediana)", "h", median(o25$hc$horas_cola), median(o26$hc$horas_cola), d$base_horas_aforo,
         nrow(o25$hc), nrow(o26$hc), ic_mediana(o26$hc$horas_cola, o26$hc$dia), fenomeno = "duración de la cola"),
    fila("Inicio de la cola (mediana)", "hora del día", median(o25$hc$inicio, na.rm = TRUE), median(o26$hc$inicio, na.rm = TRUE), d$base_inicio_aforo,
         sum(!is.na(o25$hc$inicio)), sum(!is.na(o26$hc$inicio)), ic_mediana(o26$hc$inicio, o26$hc$dia), fenomeno = "inicio de la cola"),
    fila("Fin de la cola (mediana)", "hora del día", median(o25$hc$fin, na.rm = TRUE), median(o26$hc$fin, na.rm = TRUE), d$base_fin_aforo,
         sum(!is.na(o25$hc$fin)), sum(!is.na(o26$hc$fin)), ic_mediana(o26$hc$fin, o26$hc$dia), fenomeno = "fin de la cola"),
    fila("Caudal de descarga con cola (mediana)", "veh/h", median(o25$descarga), median(o26$descarga), d$descarga,
         length(o25$descarga), length(o26$descarga), ic_mediana(o26$descarga, o26$descarga_dia), uso = uso_param,
         d25 = dplyr::n_distinct(o25$descarga_dia), d26 = dplyr::n_distinct(o26$descarga_dia), fenomeno = "descarga con cola"),
    # Medido igual: en el modelo, la mediana de las horas con cola de su día típico; en el
    # aforo, la mediana de las medianas de cada día (no la mediana de todas las horas juntas)
    if (!is.null(descarga_aforo)) {
      md25 <- tapply(o25$descarga, o25$descarga_dia, stats::median); md26 <- tapply(o26$descarga, o26$descarga_dia, stats::median)
      fila("Caudal en las horas con cola, medido igual en el modelo y en el aforo (mediana de las medianas diarias)", "veh/h",
           median(md25), median(md26), descarga_aforo, length(md25), length(md26), ic_mediana(as.numeric(md26), names(md26)),
           uso = uso_igual, d25 = length(md25), d26 = length(md26), fenomeno = "descarga con cola")
    })
  sal <- salidas_por_hora(mc)
  w <- if (is.null(mc$perfil_obs)) c(5, 22) else mc$perfil_obs$ventana
  prf <- sal |> left_join(o25$perfil |> select(hora, obs_2025 = veh), by = "hora") |>
    left_join(o26$perfil |> select(hora, obs_2026 = veh), by = "hora") |>
    mutate(caso = caso, en_ventana = hora >= w[1] & hora < w[2])
  ventana <- prf |> filter(en_ventana)
  err <- function(o) mean(abs(ventana$sim_mediana - o) / o)
  dentro <- function(o) mean(o >= ventana$sim_p10 & o <= ventana$sim_p90)
  error_perfil <- tibble(caso = caso, comparado_con = c("aforos 2025 (calibración)", "aforos 2026 (no usados)"),
                         horas = sprintf("%d a %d h (ventana de la punta)", w[1], w[2]),
                         usado_en_calibracion = "no: en la ventana solo se fija el total de vehículos, no su reparto por horas",
                         error_medio_absoluto = c(err(ventana$obs_2025), err(ventana$obs_2026)),
                         horas_dentro_p10_p90 = c(dentro(ventana$obs_2025), dentro(ventana$obs_2026)))
  list(tabla = tab, perfil = prf, error_perfil = error_perfil)
}

grafico_validacion_perfil <- function(prf) {
  d <- prf |> group_by(caso) |>
    filter(hora >= min(hora[en_ventana]) - 2, hora <= max(hora[en_ventana]) + 2) |> ungroup() |>
    mutate(caso = ifelse(caso == "manana_hacia_santa_cruz", "Mañana hacia Santa Cruz (Ermita Cruz Chica, en el cuello)",
                         "Tarde hacia el Norte (Ermita Cruz Chica, tras el estrechamiento de 3 a 2 carriles)"))
  v <- d |> filter(en_ventana) |> group_by(caso) |> summarise(xmin = min(hora), xmax = max(hora) + 1, .groups = "drop")
  ggplot(d, aes(hora + 0.5)) +
    geom_rect(data = v, aes(xmin = xmin, xmax = xmax, ymin = -Inf, ymax = Inf), inherit.aes = FALSE, fill = "#f0efec") +
    geom_ribbon(aes(ymin = sim_p10, ymax = sim_p90), fill = PAL[["azul"]], alpha = 0.15) +
    geom_line(aes(y = sim_mediana, colour = "Modelo calibrado con 2025 (mediana y p10-p90)"), linewidth = 0.9) +
    geom_point(aes(y = obs_2025, colour = "Aforos 2025"), size = 1.6) +
    geom_point(aes(y = obs_2026, colour = "Aforos 2026 (no usados)"), size = 1.6, shape = 17) +
    facet_wrap(~caso, ncol = 1) +
    scale_colour_manual(values = c("Modelo calibrado con 2025 (mediana y p10-p90)" = PAL[["azul"]],
                                   "Aforos 2025" = TINTA_MUTE, "Aforos 2026 (no usados)" = PAL[["naranja"]]), name = NULL) +
    scale_x_continuous(breaks = seq(0, 24, 2), labels = function(x) sprintf("%02d h", x)) +
    scale_y_continuous(labels = function(x) num_es(x)) +
    guides(colour = guide_legend(nrow = 2)) +
    labs(title = "¿Reproduce el modelo el tráfico de cada hora?",
         subtitle = envolver(paste("Vehículos por hora que pasan por el cuello en un día laborable. Sombreado: ventana de la punta, donde el",
                                   "modelo reparte los vehículos aforados con una forma calibrada (fuera de ella usa directamente los aforos de 2025).",
                                   "Puntos: aforos de 2025 y de 2026 (no usados)."), 110),
         x = NULL, y = "Vehículos por hora",
         caption = "Fuente: aforos horarios por carril del Cabildo de Tenerife (datos.tenerife.es); modelo del proyecto.") +
    tema_tf5(10) + theme(legend.position = "top")
}

# ---- 3. Qué prevemos -------------------------------------------------------------

# Holgura del tramo siguiente si la demanda crece un factor f: el cuello sigue
# descargando lo mismo (está saturado), pero las entradas netas entre estaciones
# crecen: holgura' = (C_abajo - f · entradas_netas) / F_cuello - 1
matriz_holgura_crecimiento <- function(holg_h, f = 1, min_obs = 10) {
  hh <- holg_h |> mutate(holgura = (C_abajo - f * entradas_netas) / F_cuello - 1)
  matriz_holgura_horaria(hh, min_obs)
}

# Situación sin actuar en años futuros con un crecimiento anual g de la demanda
# latente (0 %, 0,5 % y 1 % anual), con la misma muestra de combinaciones calibradas.
# Las horas de cola se miden como en los aforos (horas enteras), para compararlas
# con las de hoy.
# Dos cotas:
#   · sin adaptación: toda la demanda nueva intenta pasar en la punta;
#   · con adaptación: la joroba de la punta reacciona al empeoramiento con la
#     elasticidad a 10 años (parte de los viajes cambia de hora o desaparece).
evolucion_demanda <- function(mc, caso, crecimientos = c(0, 0.005, 0.01), anios = c(2025, 2030, 2035),
                              anio_base = 2025, n_max = 300, semilla = 21, holg_h = NULL) {
  set.seed(semilla)
  d <- mc$draws; if (nrow(d) > n_max) d <- d[sample.int(nrow(d), n_max), ]
  q <- function(x, p) as.numeric(stats::quantile(x, p, na.rm = TRUE))
  bind_rows(lapply(crecimientos, function(g) bind_rows(lapply(anios, function(a) {
    f <- (1 + g)^(a - anio_base)
    # Con propagación, la holgura del tramo siguiente se recalcula con la demanda del año
    HHf <- if (is.null(holg_h)) NULL else matriz_holgura_crecimiento(holg_h, f)
    HH1 <- if (is.null(holg_h)) NULL else matriz_holgura_crecimiento(holg_h, 1)
    r <- bind_rows(lapply(seq_len(nrow(d)), function(i) {
      p <- as.list(d[i, ])
      prof1 <- perfil_de(p, mc$V_dir, mc$perfil_obs)
      c1 <- capacidades(p, mc$carriles, if (is.null(HH1)) NULL else holgura_minutos(HH1, p$holgura_cuantil), propagacion = isTRUE(prof1$propagacion))
      d_ref <- evaluar(prof1, c1$antes, c1$caida)$demora_media_joroba
      prof <- perfil_de(p, mc$V_dir * f, mc$perfil_obs)
      cf <- capacidades(p, mc$carriles, if (is.null(HHf)) NULL else holgura_minutos(HHf, p$holgura_cuantil), propagacion = isTRUE(prof$propagacion))
      sin <- evaluar(prof, cf$antes, cf$caida)
      s <- if (f > 1) equilibrio_inducido(prof, cf$antes, cf$caida, p$eta_largo, p$T_libre, d_ref, permitir_supresion = TRUE) else 1
      con <- evaluar(prof, cf$antes, cf$caida, s)
      tibble(horas_sin = sin$horas_aforo, horas_con = con$horas_aforo, vh_sin = sin$demora_vh, vh_con = con$demora_vh,
             espera_max_sin = sin$espera_max, espera_max_con = con$espera_max, fin_sin = sin$fin_aforo, escala = s)
    }))
    tibble(caso = caso, crecimiento_anual = g, anio = a, factor_demanda = f,
           horas_cola_sin_adaptacion = mean(r$horas_sin), horas_cola_sin_p10 = q(r$horas_sin, 0.1),
           horas_cola_sin_p90 = q(r$horas_sin, 0.9), horas_cola_con_adaptacion = mean(r$horas_con),
           horas_cola_sin_mediana = q(r$horas_sin, 0.5), horas_cola_con_mediana = q(r$horas_con, 0.5),
           horas_cola_con_p10 = q(r$horas_con, 0.1), horas_cola_con_p90 = q(r$horas_con, 0.9),
           demora_vh_sin_p10 = q(r$vh_sin, 0.1), demora_vh_sin_p90 = q(r$vh_sin, 0.9),
           demora_vh_sin_adaptacion = q(r$vh_sin, 0.5), demora_vh_con_adaptacion = q(r$vh_con, 0.5),
           espera_max_sin_adaptacion = q(r$espera_max_sin, 0.5), espera_max_con_adaptacion = q(r$espera_max_con, 0.5),
           fin_cola_sin_adaptacion = q(r$fin_sin, 0.5), joroba_que_se_mantiene = q(r$escala, 0.5))
  }))))
}

grafico_evolucion_sin_actuar <- function(ev, media_obs = NULL) {
  hoy <- if (is.null(media_obs)) "" else sprintf(" (hoy se miden %s y %s h de media)", num_es(media_obs[1], 0.1), num_es(media_obs[2], 0.1))
  d <- ev |> mutate(caso = ifelse(caso == "manana_hacia_santa_cruz", "Mañana hacia Santa Cruz (Los Rodeos-Guamasa)",
                                  "Tarde hacia el Norte (Bomberos La Laguna)"),
                    escenario = factor(paste0("+", num_es(100 * crecimiento_anual, 0.1), " % al año"),
                                       levels = paste0("+", num_es(100 * sort(unique(crecimiento_anual)), 0.1), " % al año")))
  cols <- c(TINTA_MUTE, PAL[["azul"]], PAL[["naranja"]])[seq_along(levels(d$escenario))]
  ggplot(d, aes(anio, colour = escenario, fill = escenario)) +
    geom_ribbon(aes(ymin = horas_cola_con_adaptacion, ymax = horas_cola_sin_adaptacion), alpha = 0.12, colour = NA) +
    geom_line(aes(y = horas_cola_sin_adaptacion), linewidth = 0.9) +
    geom_line(aes(y = horas_cola_con_adaptacion), linewidth = 0.6, linetype = "22") +
    geom_point(aes(y = horas_cola_sin_adaptacion), size = 2) +
    facet_wrap(~caso, ncol = 2) +
    scale_colour_manual(values = cols, name = "Crecimiento de la demanda") +
    scale_fill_manual(values = cols, guide = "none") +
    scale_x_continuous(breaks = c(2025, 2030, 2035)) +
    scale_y_continuous(labels = function(x) num_es(x, 0.1)) +
    labs(title = "Si no se hace nada: horas de cola por día laborable",
         subtitle = envolver(paste0("Media de las simulaciones calibradas con los aforos de 2025, en horas enteras como las cuenta el aforo",
                                   hoy, ". Línea continua: toda la demanda nueva intenta pasar en la punta;",
                                   " discontinua: parte se adapta (cambia de hora o no viaja) con la elasticidad a 10 años. La población de",
                                   " Tenerife creció un 0,95 % anual entre 2021 y 2025 (INE); el tráfico de los cuellos, un 0,2-0,5 % anual",
                                   " entre 2019 y 2025 (Cabildo)."), 110),
         x = NULL, y = "Horas de cola al día",
         caption = "Fuente: modelo del proyecto; población: INE, Censo anual de población (tabla 78749); IMD del Cabildo de Tenerife.") +
    tema_tf5(10) + theme(legend.position = "top")
}

# Alternativas en un año futuro (tercer carril: contrato formalizado el 2-10-2026
# con 35 meses de plazo, así que el primer año completo de servicio sería hacia 2030)
# con la demanda latente de ese año y la holgura del tramo siguiente recalculada
alternativas_futuro <- function(mc, caso, anio = 2030, g = 0.005, holg_h = NULL, con_tercer_carril = TRUE,
                                anio_base = 2025, n_max = 300, semilla = 22) {
  set.seed(semilla)
  d <- mc$draws; if (nrow(d) > n_max) d <- d[sample.int(nrow(d), n_max), ]
  f <- (1 + g)^(anio - anio_base)
  HHf <- if (is.null(holg_h)) NULL else matriz_holgura_crecimiento(holg_h, f)
  r <- bind_rows(lapply(seq_len(nrow(d)), function(i) {
    p <- as.list(d[i, ])
    ht <- if (is.null(HHf)) NULL else holgura_minutos(HHf, p$holgura_cuantil)
    e <- escenarios_cuello(p, mc$V_dir * f, mc$carriles, con_tercer_carril, prof = perfil_de(p, mc$V_dir * f, mc$perfil_obs), holgura_t = ht)
    b <- e$base$demora_vh
    tibble(sim = i, escenario = names(e), demora_vh = vapply(e, function(x) x$demora_vh, numeric(1)),
           horas_cola = vapply(e, function(x) x$min_con_cola / 60, numeric(1)),
           reduccion = if (b > DEMORA_MINIMA_VH) 1 - demora_vh / b else NA_real_)
  }))
  r |> group_by(escenario) |>
    summarise(reduccion_mediana = median(reduccion), reduccion_p10 = as.numeric(stats::quantile(reduccion, 0.1)),
              reduccion_p90 = as.numeric(stats::quantile(reduccion, 0.9)), horas_cola_mediana = median(horas_cola),
              .groups = "drop") |>
    mutate(caso = caso, anio = anio, crecimiento_anual = g, factor_demanda = f,
           etiqueta = ifelse(escenario == "base", "Sin actuación", unname(ETIQUETAS_ESC[escenario])),
           orden = match(escenario, c("base", names(ETIQUETAS_ESC)))) |>
    arrange(orden) |> select(-orden) |> relocate(caso, anio, crecimiento_anual, escenario, etiqueta)
}

# Escenarios adversos: ¿cambia el orden de las alternativas si el tramo siguiente
# no tiene holgura, si la demanda inducida es alta, si la caída de capacidad es
# pequeña (lo que más perjudica a la regulación de accesos) o si hay un incidente?
# Incluye también la cota favorable sin demanda inducida (elasticidades nulas), para
# ver el abanico completo de supuestos sobre la conducta de los conductores.
escenarios_adversos <- function(mc, caso, HH = NULL, con_tercer_carril = TRUE, n_max = 200, semilla = 23,
                                nombre_sin_holgura = "Tramo siguiente sin holgura (Padre Anchieta con 2 carriles efectivos)") {
  set.seed(semilla)
  d <- mc$draws; if (nrow(d) > n_max) d <- d[sample.int(nrow(d), n_max), ]
  ht_ref <- function(p) if (is.null(HH)) NULL else holgura_minutos(HH, p$holgura_cuantil)
  esc <- list(
    "Referencia (calibrado)" = function(p) list(p = p, ht = ht_ref(p), inc = NULL),
    "Sin demanda inducida (cota favorable)" = function(p) {
      p$eta_corto <- 0; p$eta_medio <- 0; p$eta_largo <- 0
      list(p = p, ht = ht_ref(p), inc = NULL) },
    "Demanda inducida alta (elasticidades -0,5 el 1er año y -1,0 a 10 años)" = function(p) {
      p$eta_corto <- -0.5; p$eta_largo <- -1.0; p$eta_medio <- eta_medio(-0.5, -1.0, p$persistencia_anual)
      list(p = p, ht = ht_ref(p), inc = NULL) },
    "Caída de capacidad pequeña (4 %) con la misma descarga medida" = function(p) {
      descarga <- p$c_carril * (1 - p$caida_capacidad); p$caida_capacidad <- 0.04; p$c_carril <- descarga / 0.96
      list(p = p, ht = ht_ref(p), inc = NULL) },
    "Incidente: un carril cortado 30 min en lo más alto de la punta" = function(p)
      list(p = p, ht = ht_ref(p), inc = round(p$t0_punta) + c(-15, 15)))
  if (!is.null(HH)) esc <- append(esc, stats::setNames(list(function(p) list(p = p, ht = rep(0, DURACION_MIN), inc = NULL)),
                                                       nombre_sin_holgura), after = 2)
  bind_rows(lapply(names(esc), function(nm) {
    r <- bind_rows(lapply(seq_len(nrow(d)), function(i) {
      x <- esc[[nm]](as.list(d[i, ]))
      e <- escenarios_cuello(x$p, mc$V_dir, mc$carriles, con_tercer_carril, prof = perfil_de(x$p, mc$V_dir, mc$perfil_obs),
                             holgura_t = x$ht, incidente = x$inc)
      b <- e$base$demora_vh
      tibble(sim = i, escenario = names(e), demora_vh = vapply(e, function(y) y$demora_vh, numeric(1)),
             reduccion = if (b > DEMORA_MINIMA_VH) 1 - demora_vh / b else NA_real_)
    }))
    r |> group_by(escenario) |>
      summarise(reduccion_mediana = median(reduccion, na.rm = TRUE),
                reduccion_p10 = as.numeric(stats::quantile(reduccion, 0.1, na.rm = TRUE)),
                reduccion_p90 = as.numeric(stats::quantile(reduccion, 0.9, na.rm = TRUE)),
                demora_vh_mediana = median(demora_vh), .groups = "drop") |>
      mutate(supuesto = nm)
  })) |>
    filter(escenario %in% c("base", "tercer_carril_corto", "tercer_carril_largo", "ramp_metering_corto", "ramp_metering_largo",
                            "escalonamiento_corto", "tarificacion", "paquete_gestion_corto", "paquete_gestion_largo")) |>
    mutate(caso = caso, etiqueta = ifelse(escenario == "base", "Sin actuación", unname(ETIQUETAS_ESC[escenario])),
           supuesto = factor(supuesto, levels = names(esc))) |>
    group_by(supuesto) |>
    mutate(puesto = ifelse(escenario == "base", NA_integer_,
                           rank(-ifelse(escenario == "base", -Inf, reduccion_mediana), ties.method = "min")),
           # a menos de UMBRAL_DIFERENCIA (2 puntos) de la mejor: empatada con ella
           empate_con_la_primera = escenario != "base" &
             reduccion_mediana >= max(reduccion_mediana[escenario != "base"]) - UMBRAL_DIFERENCIA) |>
    ungroup() |> arrange(supuesto, puesto) |> mutate(supuesto = as.character(supuesto)) |>
    relocate(caso, supuesto, escenario, etiqueta)
}

# Transporte público: qué parte de la joroba de la punta (los vehículos por encima
# del nivel de los hombros) tendría que pasar a la guagua o al tranvía para reducir
# la demora, sin y con efecto rebote (el hueco se rellena en parte con viajes nuevos
# en coche, con las mismas elasticidades que el resto de alternativas)
curva_trasvase_tp <- function(mc, trasvases = c(0.02, 0.05, 0.10, 0.15), n_max = 200, semilla = 24) {
  set.seed(semilla)
  d <- mc$draws; if (nrow(d) > n_max) d <- d[sample.int(nrow(d), n_max), ]
  r <- bind_rows(lapply(seq_len(nrow(d)), function(i) {
    p <- as.list(d[i, ])
    prof <- perfil_de(p, mc$V_dir, mc$perfil_obs)
    cb <- capacidades(p, mc$carriles, if (is.null(mc$holgura_horaria)) NULL else holgura_minutos(mc$holgura_horaria, p$holgura_cuantil),
                      propagacion = isTRUE(prof$propagacion))
    base <- evaluar(prof, cb$antes, cb$caida)
    bind_rows(lapply(trasvases, function(m) {
      pm <- prof; pm$joroba <- prof$joroba * (1 - m)
      sin_rebote <- evaluar(pm, cb$antes, cb$caida)$demora_vh
      con <- vapply(HORIZONTES, function(h) {
        s <- equilibrio_inducido(pm, cb$antes, cb$caida, eta_horizonte(p, h), p$T_libre, base$demora_media_joroba)
        evaluar(pm, cb$antes, cb$caida, s)$demora_vh
      }, numeric(1))
      tibble(sim = i, trasvase = m, veh_dia = m * sum(prof$joroba), sin_rebote = 1 - sin_rebote / base$demora_vh,
             con_rebote_1 = 1 - con[["corto"]] / base$demora_vh, con_rebote_5 = 1 - con[["medio"]] / base$demora_vh,
             con_rebote_10 = 1 - con[["largo"]] / base$demora_vh)
    }))
  }))
  q <- function(x, p) as.numeric(stats::quantile(x, p))
  r |> group_by(trasvase) |>
    summarise(veh_dia_trasvasados = median(veh_dia), reduccion_sin_rebote = median(sin_rebote),
              reduccion_1er_anio = median(con_rebote_1), reduccion_5_anios = median(con_rebote_5),
              reduccion_10_anios = median(con_rebote_10),
              p10_sin_rebote = q(sin_rebote, 0.1), p90_sin_rebote = q(sin_rebote, 0.9),
              p10_1er_anio = q(con_rebote_1, 0.1), p90_1er_anio = q(con_rebote_1, 0.9),
              p10_10_anios = q(con_rebote_10, 0.1), p90_10_anios = q(con_rebote_10, 0.9), .groups = "drop")
}

# Trayectoria de cada alternativa en el tiempo (1er año, 5 y 10 años)
grafico_horizontes <- function(res1, res2) {
  nombres <- c(tercer_carril = "Tercer carril", ramp_metering = "Regulación de accesos",
               escalonamiento = "Escalonamiento horario", paquete_gestion = "Regulación + escalonamiento")
  d <- bind_rows(res1 |> mutate(caso = "Mañana hacia Santa Cruz (tercer carril contratado)"),
                 res2 |> mutate(caso = "Tarde hacia el Norte (tercer carril hipotético)")) |>
    filter(grepl("_(corto|medio|largo)$", escenario)) |>
    mutate(alternativa = unname(nombres[sub("_(corto|medio|largo)$", "", escenario)]),
           anio = unname(c(corto = 1, medio = 5, largo = 10)[sub(".*_", "", escenario)]))
  pal <- c("Tercer carril" = PAL[["naranja"]], "Regulación de accesos" = PAL[["azul"]],
           "Escalonamiento horario" = PAL[["aqua"]], "Regulación + escalonamiento" = PAL[["violeta"]])
  pd <- position_dodge(width = 1.2)
  ggplot(d, aes(anio, mediana, colour = alternativa, group = alternativa)) +
    geom_linerange(aes(ymin = p10, ymax = p90), position = pd, linewidth = 0.6, alpha = 0.45) +
    geom_line(position = pd, linewidth = 0.9) + geom_point(position = pd, size = 2) +
    facet_wrap(~caso, ncol = 2) +
    scale_colour_manual(values = pal, name = NULL) +
    scale_x_continuous(breaks = c(1, 5, 10), labels = c("1er año", "5 años", "10 años")) +
    scale_y_continuous(labels = function(x) pct_es(x), limits = c(0, 1), oob = scales::squish) +
    guides(colour = guide_legend(nrow = 2)) +
    labs(title = "Cuánto dura la mejora: reducción de la demora con el paso de los años",
         subtitle = envolver(paste("Punto: mediana; barra: p10-p90 de las simulaciones calibradas. La demanda inducida crece con los años (elasticidades",
                                   "de Goodwin y SACTRA; reparto en el tiempo según Hymel, Small y Van Dender); sin crecimiento de fondo",
                                   "de la demanda. La tarificación no aparece: su efecto observado ya es neto."), 110),
         x = NULL, y = "Reducción de la demora",
         caption = "Fuente: modelo del proyecto; parámetros usados, rangos y fuentes en salidas/tablas/parametros_usados_caso1.csv y _caso2.csv.") +
    tema_tf5(10) + theme(legend.position = "top")
}

# ---- Trazabilidad: registro único de fuentes ---------------------------------------
registro_fuentes <- function(dir = DIR_DATOS) {
  meta <- metadatos_horarios(file.path(dir, "horarios")) |>
    transmute(id = paste0("H-", mes), fuente = paste("Cabildo de Tenerife, intensidad diaria de tráfico (registros horarios por carril),", mes),
              tipo = "dato oficial", url, licencia = "CC BY (Creative Commons Reconocimiento)",
              fecha_fuente = ultima_modificacion, consultado = descargado_utc, sha256 = sha256_txt_oficial,
              fichero_local = paste0("datos/horarios/", fichero),
              uso = "Aforos horarios: colas, capacidad, holgura, comparaciones y calibración")
  ofi <- jsonlite::fromJSON(file.path(dir, "oficial", "manifiesto_oficiales.json"))
  ofi_t <- as_tibble(ofi$ficheros)
  if (!"descargado_utc" %in% names(ofi_t)) ofi_t$descargado_utc <- NA_character_
  ofi_t <- ofi_t |>
    transmute(id = paste0("O-", seq_along(name)), fuente = paste("Cabildo de Tenerife,", name), tipo = "dato oficial", url,
              licencia = "CC BY (Creative Commons Reconocimiento)", fecha_fuente = as.character(last_modified_ckan),
              consultado = coalesce(as.character(descargado_utc), as.character(ofi$descargado_utc)), sha256,
              fichero_local = paste0("datos/oficial/", fichero),
              uso = ifelse(grepl("Media Diaria", name), "IMD anual 2018-2025",
                           ifelse(grepl("iccionario", name), "Definición de los campos", "Carriles y rangos de velocidad")))
  otras <- readr::read_csv(file.path(dir, "fuentes_documentales.csv"), show_col_types = FALSE,
                           col_types = readr::cols(.default = readr::col_character()))
  bind_rows(meta, ofi_t, otras)
}

# ---- Confianza de cada alternativa ------------------------------------------------
# Cuatro criterios (alta = 3, media = 2, baja = 1): evidencia (¿hay datos de la
# medida o del mecanismo en Tenerife?), mecanismo (¿lo representa bien una cola
# puntual?), conducta (¿depende poco de que los conductores cambien de hábitos?) y
# robustez (peor reducción mediana en los escenarios adversos / reducción de
# referencia: >= 0,7 alta, >= 0,4 media, < 0,4 baja). Los tres primeros se razonan
# en datos/confianza_alternativas.csv; la robustez sale del modelo. Confianza =
# media de los cuatro (>= 2,5 alta; >= 1,75 media; si no, baja).
tabla_confianza <- function(criterios, resultados, adversos) {
  nivel <- c(baja = 1, media = 2, alta = 3)
  a_nivel <- function(x) ifelse(x >= 2.5, "alta", ifelse(x >= 1.75, "media", "baja"))
  filas <- criterios |>
    tidyr::separate_rows(caso, sep = ";") |>
    mutate(caso = ifelse(caso == "ambos", NA, caso)) |>
    tidyr::expand_grid(caso_res = names(resultados)) |>
    filter(is.na(caso) | caso == caso_res) |> mutate(caso = caso_res) |> select(-caso_res)
  bind_rows(lapply(seq_len(nrow(filas)), function(i) {
    f <- filas[i, ]
    res <- resultados[[f$caso]]; adv <- adversos[[f$caso]]
    esc <- if (f$alternativa == "tarificacion") "tarificacion" else paste0(f$alternativa, c("_corto", "_medio", "_largo"))
    if (!esc[1] %in% res$escenario) return(NULL)
    r <- res |> filter(escenario %in% esc)
    x <- adv |> filter(escenario == esc[1])
    ref <- x$reduccion_mediana[x$supuesto == "Referencia (calibrado)"]
    otros <- x |> filter(supuesto != "Referencia (calibrado)", !grepl("cota favorable", supuesto))
    ratio <- if (length(ref) && !is.na(ref) && ref > 0 && nrow(otros)) min(otros$reduccion_mediana) / ref else NA_real_
    robustez <- if (is.na(ratio)) NA_character_ else if (ratio >= 0.7) "alta" else if (ratio >= 0.4) "media" else "baja"
    puntos <- c(nivel[[f$evidencia]], nivel[[f$mecanismo]], nivel[[f$conducta]], if (is.na(robustez)) NULL else nivel[[robustez]])
    tibble(caso = f$caso, alternativa = f$alternativa, nombre = f$nombre, tramo = f$tramo, horario = f$horario, estado = f$estado,
           coste = if ("coste" %in% names(f)) f$coste else NA_character_,
           reduccion_1er_anio = r$mediana[1], p10_1er_anio = r$p10[1], p90_1er_anio = r$p90[1],
           reduccion_5_anios = if (nrow(r) >= 2) r$mediana[2] else NA_real_,
           reduccion_10_anios = if (nrow(r) >= 3) r$mediana[3] else NA_real_,
           peor_supuesto = if (nrow(otros)) otros$supuesto[which.min(otros$reduccion_mediana)] else NA_character_,
           reduccion_peor_supuesto = if (nrow(otros)) min(otros$reduccion_mediana) else NA_real_,
           evidencia = f$evidencia, mecanismo = f$mecanismo, conducta = f$conducta, robustez = robustez,
           puntuacion = mean(puntos), confianza = a_nivel(mean(puntos)),
           motivo = paste0("Evidencia: ", f$motivo_evidencia, ". Mecanismo: ", f$motivo_mecanismo, ". Conducta: ", f$motivo_conducta, "."))
  }))
}

# Estabilidad de los percentiles: ¿cuánto cambiarían la mediana, el p10 y el p90 con
# otra muestra de combinaciones calibradas del mismo tamaño? (bootstrap de las
# simulaciones). Si el error es pequeño frente a las diferencias entre alternativas,
# el número de simulaciones basta.
estabilidad_percentiles <- function(mc, caso, n_boot = 300, semilla = 31) {
  set.seed(semilla)
  r <- mc$resultados |> filter(escenario != "base")
  por_esc <- split(r$reduccion, r$escenario)          # una fila por simulación y alternativa
  bind_rows(lapply(names(por_esc), function(e) {
    x <- por_esc[[e]]
    b <- vapply(seq_len(n_boot), function(k)
      as.numeric(stats::quantile(x[sample.int(length(x), length(x), replace = TRUE)], c(0.1, 0.5, 0.9))), numeric(3))
    tibble(caso = caso, escenario = e, simulaciones = length(x),
           mediana = median(x), ee_p10 = stats::sd(b[1, ]), ee_mediana = stats::sd(b[2, ]), ee_p90 = stats::sd(b[3, ]))
  })) |>
    mutate(orden = match(escenario, names(ETIQUETAS_ESC))) |> arrange(orden) |> select(-orden)
}
