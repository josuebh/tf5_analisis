# =============================================================================
# 11_validacion_y_trazabilidad.R · Validación día a día, geometría y trazabilidad
# -----------------------------------------------------------------------------
#   1. Validación día a día (sesgo, error absoluto medio, RMSE y cobertura de la banda
#      de parámetros y del intervalo predictivo, por año, trimestre, día de la semana y
#      hora) y diagnóstico del caudal de descarga de la mañana.
#   2. Geometría: carriles aforados, documentados y efectivos de cada estación,
#      con fuente y fecha, enlazados con la capacidad que usa el modelo.
#   3. Balance por tramos entre estaciones consecutivas y sensibilidad de la
#      holgura (capacidad de abajo, ramales desconocidos, cuello desplazado).
#   4. Indicadores de demora: definición, unidades y contraste indirecto.
#   5. Diseño del Monte Carlo: distribuciones, dependencias, semillas, reglas
#      de aceptación y descartes.
#   7. Procedencia de cada recurso y contraste con una instantánea del catálogo oficial.
#   8. Series con banderas de calidad (sin imputar) y sensibilidad a la depuración.
#   9. Previsiones condicionadas con escenarios bajo, central y alto.
#  10. Ficha de cada alternativa.
# Ninguna función modifica los datos originales de datos/.
# =============================================================================

trimestre <- function(dia) paste0(format(dia, "%Y"), "-T", (as.integer(format(dia, "%m")) - 1) %/% 3 + 1)

# Posición de cada hora en la cola del día (vector lógico ordenado por hora)
tipo_hora_cola <- function(cong) {
  antes <- dplyr::lag(cong, default = FALSE); despues <- dplyr::lead(cong, default = FALSE)
  dplyr::case_when(!cong ~ "sin cola", antes & despues ~ "plena", !antes & despues ~ "inicio",
                   antes & !despues ~ "final", TRUE ~ "aislada")
}

cuantil <- function(x, p) as.numeric(stats::quantile(x, p, na.rm = TRUE, names = FALSE))

# ---- 1. Validación día a día ------------------------------------------------------

# Lo medido cada día laborable válido: horas, inicio y fin de la cola (estación de la
# cola) y caudal de la estación de salida en esas horas con cola (mediana del día y
# mediana de las horas de cola plena: con cola la hora anterior y la siguiente)
observado_diario <- function(sc, est_cola, est_salida, sen, horas_cola, anios = c(2025, 2026)) {
  hc <- bind_rows(lapply(anios, function(a) horario_cola(sc, est_cola, sen, a, horas_cola)))
  cola <- sc |> filter(anio %in% anios, estacion_id == est_cola, sentido == sen, hora %in% horas_cola) |>
    semi_join(hc, by = "dia") |> select(dia, hora, cong = congestionada) |>
    arrange(dia, hora) |> group_by(dia) |> mutate(tipo = tipo_hora_cola(cong)) |> ungroup()
  sal <- sc |> filter(anio %in% anios, estacion_id == est_salida, sentido == sen) |> select(dia, hora, veh)
  horas <- cola |> inner_join(sal, by = c("dia", "hora")) |>
    mutate(anio = as.integer(format(dia, "%Y")), periodo = trimestre(dia))
  desc <- horas |> filter(cong) |> group_by(dia) |>
    summarise(horas_descarga = n(), descarga_dia = median(veh),
              descarga_plena = if (any(tipo == "plena")) median(veh[tipo == "plena"]) else NA_real_, .groups = "drop")
  dias <- hc |> left_join(desc, by = "dia") |>
    mutate(anio = as.integer(format(dia, "%Y")), periodo = trimestre(dia))
  list(dias = dias, horas = horas)
}

# Lo mismo en el modelo, combinación a combinación (situación actual): caudal que sale
# cada hora y si el aforo la contaría como hora con cola (>= 60 % de los vehículos que
# pasan lo hacen con cola, igual que horas_como_aforo())
simulado_por_combinacion <- function(mc, n_max = Inf, semilla = 41) {
  set.seed(semilla)
  d <- mc$draws
  if (nrow(d) > n_max) d <- d[sort(sample.int(nrow(d), n_max)), ]
  h <- rep(0:23, each = 60)
  bind_rows(lapply(seq_len(nrow(d)), function(i) {
    p <- as.list(d[i, ])
    ht <- if (is.null(mc$holgura_horaria)) NULL else holgura_minutos(mc$holgura_horaria, p$holgura_cuantil)
    r <- evaluar_actual(p, mc$carriles, perfil_de(p, mc$V_dir, mc$perfil_obs), ht)
    sal <- as.numeric(tapply(r$s, h, sum))
    frac <- as.numeric(tapply(r$s * (r$Q > 0.5), h, sum)) / pmax(sal, 1e-9)
    cong <- frac >= 0.6
    tibble(sim = d$sim[i], hora = 0:23, salida = sal, cong = cong, tipo = tipo_hora_cola(cong))
  }))
}

# Métricas de un indicador: el modelo da una banda de parámetros (p10-p90 de las
# combinaciones calibradas) y una mediana; cada observación (día u hora) se compara con
# ellas. ip: intervalo predictivo del 80 % (banda + variabilidad de un día a otro y error
# de observación, ver intervalo_predictivo())
metricas_contraste <- function(o, b, relativo = TRUE, ip = c(NA_real_, NA_real_)) {
  o <- o[!is.na(o)]
  if (!length(o)) return(tibble(observaciones = 0L))
  mae <- mean(abs(b[2] - o))
  tibble(observaciones = length(o), observado_media = mean(o), observado_mediana = median(o),
         simulado_p10 = b[1], simulado_mediana = b[2], simulado_p90 = b[3],
         sesgo = b[2] - mean(o), sesgo_relativo = if (relativo) (b[2] - mean(o)) / mean(o) else NA_real_,
         mae = mae, mae_relativo = if (relativo) mae / mean(o) else NA_real_, rmse = sqrt(mean((b[2] - o)^2)),
         cobertura_p10_p90 = mean(o >= b[1] & o <= b[3]), bajo_p10 = mean(o < b[1]), sobre_p90 = mean(o > b[3]),
         ip_p10 = ip[1], ip_p90 = ip[2], cobertura_intervalo_predictivo = if (is.na(ip[1])) NA_real_ else mean(o >= ip[1] & o <= ip[2]))
}

# Validación con muchas observaciones: cada día laborable válido (y cada hora de la
# ventana de la punta) de 2025 (calibración) y de enero-septiembre de 2026 (no usado),
# por año, trimestre y día de la semana. Dos bandas: la de parámetros (p10-p90 de las
# combinaciones calibradas, un día típico: no tiene por qué cubrir el 80 % de los días) y
# el intervalo predictivo del 80 % (más la variabilidad de un día a otro y el error de
# observación de los días de 2025), que sí se compara con el 80 %.
validacion_diaria <- function(mc, sc, est_cola, est_salida, sen, caso, horas_cola, n_max = Inf, semilla = 41) {
  ob <- observado_diario(sc, est_cola, est_salida, sen, horas_cola)
  sim <- simulado_por_combinacion(mc, n_max, semilla)
  por_sim <- sim |> group_by(sim) |>
    summarise(descarga_aforo = if (any(cong)) median(salida[cong]) else NA_real_,
              descarga_plena = if (any(tipo == "plena")) median(salida[tipo == "plena"]) else NA_real_,
              .groups = "drop") |>
    left_join(mc$draws |> select(sim, horas = base_horas_aforo, inicio = base_inicio_aforo, fin = base_fin_aforo, descarga),
              by = "sim")
  ind <- tibble::tribble(
    ~indicador, ~unidad, ~col_obs, ~col_sim, ~definicion,
    "Horas de cola al día", "h", "horas_cola", "horas",
    "Horas enteras con >= 60 % de vehículos a menos de 80 km/h (aforo) o con cola (modelo)",
    "Inicio de la cola", "hora del día", "inicio", "inicio", "Primera hora con cola",
    "Fin de la cola", "hora del día", "fin", "fin", "Última hora con cola + 1",
    "Descarga del día frente al parámetro del modelo", "veh/h", "descarga_dia", "descarga",
    "Mediana diaria del caudal aforado en las horas con cola frente al parámetro carriles x capacidad x (1 - caída) (definiciones distintas)",
    "Descarga del día medida igual en el modelo y en el aforo", "veh/h", "descarga_dia", "descarga_aforo",
    "Mediana del caudal que sale en las horas que el aforo contaría como horas con cola (inicio, plena y final)",
    "Descarga en las horas de cola plena", "veh/h", "descarga_plena", "descarga_plena",
    "Mediana del caudal en las horas con cola la hora anterior y la siguiente")
  periodos <- sort(unique(ob$dias$periodo))
  dsem <- c("lunes", "martes", "miércoles", "jueves", "viernes")
  grupos <- c(list("2025 (calibración)" = function(x) x$anio == 2025, "2026 (validación, no usado)" = function(x) x$anio == 2026),
              stats::setNames(lapply(periodos, function(pp) function(x) x$periodo == pp), periodos),
              stats::setNames(lapply(1:5, function(k) function(x) x$anio == 2026 & as.integer(format(x$dia, "%u")) == k), paste0("2026, ", dsem)))
  uso <- function(g) ifelse(grepl("^2025", g), "calibración", "validación")
  d25 <- ob$dias[ob$dias$anio == 2025, ]
  diarias <- bind_rows(lapply(seq_len(nrow(ind)), function(k) {
    s <- por_sim[[ind$col_sim[k]]]
    b <- cuantil(s, c(0.1, 0.5, 0.9))
    resid <- d25[[ind$col_obs[k]]] - stats::median(d25[[ind$col_obs[k]]], na.rm = TRUE)
    ip <- intervalo_predictivo(s, resid)
    bind_rows(lapply(names(grupos), function(g) {
      x <- ob$dias[grupos[[g]](ob$dias), ]
      metricas_contraste(x[[ind$col_obs[k]]], b, relativo = ind$unidad[k] != "hora del día", ip = ip) |>
        mutate(caso = caso, indicador = ind$indicador[k], unidad = ind$unidad[k], definicion = ind$definicion[k],
               periodo = g, uso = uso(g), nivel = "día")
    }))
  }))
  # Caudal de cada hora de la ventana de la punta, día a día (todos los días laborables
  # válidos de la estación de salida)
  w <- if (is.null(mc$perfil_obs)) c(5, 22) else mc$perfil_obs$ventana
  hh <- seq(w[1], w[2] - 1)
  oh <- sc |> filter(anio %in% c(2025, 2026), estacion_id == est_salida, sentido == sen, hora %in% hh) |>
    select(dia, hora, veh) |> mutate(anio = as.integer(format(dia, "%Y")), periodo = trimestre(dia))
  res25 <- oh |> filter(anio == 2025) |> group_by(hora) |> mutate(r = veh - stats::median(veh)) |> ungroup()
  bandas <- sim |> filter(hora %in% hh) |> group_by(hora) |>
    summarise(p10 = cuantil(salida, 0.1), med = cuantil(salida, 0.5), p90 = cuantil(salida, 0.9),
              ip10 = intervalo_predictivo(salida, res25$r[res25$hora == first(hora)])[1],
              ip90 = intervalo_predictivo(salida, res25$r[res25$hora == first(hora)])[2], .groups = "drop")
  oh <- oh |> left_join(bandas, by = "hora")
  horarias <- bind_rows(lapply(names(grupos), function(g) {
    x <- oh[grupos[[g]](oh), ]
    if (!nrow(x)) return(NULL)
    mae <- mean(abs(x$med - x$veh))
    tibble(observaciones = nrow(x), observado_media = mean(x$veh), observado_mediana = median(x$veh),
           simulado_p10 = NA_real_, simulado_mediana = mean(x$med), simulado_p90 = NA_real_,
           sesgo = mean(x$med - x$veh), sesgo_relativo = mean(x$med - x$veh) / mean(x$veh),
           mae = mae, mae_relativo = mae / mean(x$veh), rmse = sqrt(mean((x$med - x$veh)^2)),
           cobertura_p10_p90 = mean(x$veh >= x$p10 & x$veh <= x$p90), bajo_p10 = mean(x$veh < x$p10), sobre_p90 = mean(x$veh > x$p90),
           cobertura_intervalo_predictivo = mean(x$veh >= x$ip10 & x$veh <= x$ip90),
           caso = caso, indicador = sprintf("Caudal de cada hora de %d a %d h (ventana de la punta)", w[1], w[2]), unidad = "veh/h",
           definicion = "Vehículos por hora en la estación de salida, día a día; banda del modelo de esa hora del día",
           periodo = g, uso = uso(g), nivel = "hora")
  }))
  por_hora <- oh |> group_by(anio, hora) |>
    summarise(dias = n(), observado_mediana = median(veh), simulado_mediana = first(med),
              sesgo = mean(med - veh), mae = mean(abs(med - veh)), rmse = sqrt(mean((med - veh)^2)),
              cobertura_p10_p90 = mean(veh >= p10 & veh <= p90), cobertura_intervalo_predictivo = mean(veh >= ip10 & veh <= ip90),
              ip_p10 = first(ip10), ip_p90 = first(ip90), .groups = "drop") |>
    mutate(caso = caso, sesgo_relativo = sesgo / observado_mediana, uso = ifelse(anio == 2025, "calibración", "validación")) |> relocate(caso)
  list(tabla = bind_rows(diarias, horarias) |>
         relocate(caso, indicador, unidad, nivel, periodo, uso, observaciones) |>
         relocate(definicion, .after = last_col()),
       por_hora = por_hora, observado = ob, simulado = sim, por_sim = por_sim)
}

# Diagnóstico del caudal de descarga: dónde está la diferencia entre el modelo y el
# aforo (hora del día, posición en la cola, cola aguas abajo, previa y posterior)
diagnostico_descarga <- function(vd, mc_todo, mc, objetivo, sc, caso, est_abajo = NULL, sen = "descendente") {
  ob <- vd$observado; sim <- vd$simulado
  fila <- function(bloque, grupo, fuente, x, nota = "") {
    x <- x[!is.na(x)]
    tibble(caso = caso, bloque = bloque, grupo = grupo, fuente = fuente, n = length(x),
           p10 = if (length(x)) cuantil(x, 0.1) else NA_real_, mediana = if (length(x)) median(x) else NA_real_,
           p90 = if (length(x)) cuantil(x, 0.9) else NA_real_, nota = nota)
  }
  hc <- ob$horas |> filter(cong)
  out <- list()
  # A. Por hora del día (con la parte de pesados de esas horas, que reduce la capacidad en vehículos)
  pes <- sc |> filter(anio %in% c(2025, 2026), estacion_id == 103) |> select(dia, hora, sentido, pesados_h = pesados, veh_h = veh)
  for (h in sort(unique(hc$hora))) {
    xp <- hc |> filter(anio == 2025, hora == h) |> inner_join(pes |> filter(sentido == sen), by = c("dia", "hora"))
    if (nrow(xp)) out[[length(out) + 1]] <- fila("Parte de pesados en las horas con cola", sprintf("%02d h", h), "aforo 2025", xp$pesados_h / xp$veh_h,
                                                 "Fracción de vehículos de más de 6 m (pesados) en la estación de salida")
    out[[length(out) + 1]] <- fila("Por hora del día", sprintf("%02d h", h), "aforo 2025", hc$veh[hc$anio == 2025 & hc$hora == h])
    out[[length(out) + 1]] <- fila("Por hora del día", sprintf("%02d h", h), "aforo 2026", hc$veh[hc$anio == 2026 & hc$hora == h])
    out[[length(out) + 1]] <- fila("Por hora del día", sprintf("%02d h", h), "modelo (calibrado)", sim$salida[sim$cong & sim$hora == h],
                                   "Caudal simulado en las horas que el aforo contaría con cola")
  }
  # B. Por posición en la cola
  for (t in c("inicio", "plena", "final", "aislada")) {
    out[[length(out) + 1]] <- fila("Por posición en la cola", t, "aforo 2025", hc$veh[hc$anio == 2025 & hc$tipo == t])
    out[[length(out) + 1]] <- fila("Por posición en la cola", t, "aforo 2026", hc$veh[hc$anio == 2026 & hc$tipo == t])
    out[[length(out) + 1]] <- fila("Por posición en la cola", t, "modelo (calibrado)", sim$salida[sim$cong & sim$tipo == t])
  }
  # C. Con y sin cola aguas abajo en la misma hora (solo si hay estaciones de abajo con velocidad fiable)
  if (length(est_abajo)) {
    ab <- sc |> filter(estacion_id %in% est_abajo, sentido == sen) |> group_by(dia, hora) |>
      summarise(cola_abajo = any(congestionada), .groups = "drop")
    x <- hc |> inner_join(ab, by = c("dia", "hora"))
    for (h in intersect(c(6, 7, 8, 9), unique(x$hora))) for (a in c(2025, 2026)) {
      y <- x |> filter(anio == a, hora == h)
      out[[length(out) + 1]] <- fila("Según haya cola aguas abajo", sprintf("%02d h, con cola abajo", h), paste("aforo", a), y$veh[y$cola_abajo],
                                     "Cola en Bomberos La Laguna o Campus Guajara en la misma hora")
      out[[length(out) + 1]] <- fila("Según haya cola aguas abajo", sprintf("%02d h, sin cola abajo", h), paste("aforo", a), y$veh[!y$cola_abajo])
    }
  }
  # D. El parámetro de descarga del modelo: previa, filtros y posterior
  d0 <- mc_todo$draws
  resto <- d0$base_horas_aforo >= objetivo$duracion[1] & d0$base_horas_aforo <= objetivo$duracion[2] & d0$base_cola_final < 0.5 &
    (if (is.null(objetivo$inicio)) TRUE else !is.na(d0$base_inicio_aforo) & d0$base_inicio_aforo >= objetivo$inicio[1] &
       d0$base_inicio_aforo <= objetivo$inicio[2] & d0$base_fin_aforo >= objetivo$fin[1] & d0$base_fin_aforo <= objetivo$fin[2])
  dentro <- mean(cumple_descarga(d0, objetivo), na.rm = TRUE)
  w <- ventana_descarga(objetivo)
  out[[length(out) + 1]] <- fila("Parámetro de descarga", "previa (todas las combinaciones)", "modelo", d0$descarga,
                                 sprintf("El %s %% de la previa cumple la regla de la descarga (%s; %s-%s veh/h)",
                                         num_es(100 * dentro), if (identical(objetivo$medida_descarga, "como_aforo")) "medida como en el aforo" else "como parámetro",
                                         num_es(w[1]), num_es(w[2])))
  out[[length(out) + 1]] <- fila("Parámetro de descarga", "cumplen duración, inicio y fin (sin mirar la descarga)", "modelo", d0$descarga[resto])
  out[[length(out) + 1]] <- fila("Parámetro de descarga", "aceptadas (calibración principal)", "modelo", mc$draws$descarga)
  out[[length(out) + 1]] <- fila("Parámetro de descarga", "medida del día (mediana de sus horas con cola), 2025", "aforo 2025",
                                 ob$dias$descarga_dia[ob$dias$anio == 2025])
  out[[length(out) + 1]] <- fila("Parámetro de descarga", "medida del día (mediana de sus horas con cola), 2026", "aforo 2026",
                                 ob$dias$descarga_dia[ob$dias$anio == 2026])
  bind_rows(out)
}

# ---- 2. Geometría y capacidad ------------------------------------------------------
# Une el inventario documental (datos/geometria_tramos.csv) con el catálogo oficial de
# carriles, la capacidad observada y las incidencias de los aforos (cortes de carril y
# horas incompletas), y enlaza cada estación con la capacidad que usa el modelo
geometria_capacidades <- function(geo, cs, cap, val_h, fecha_catalogo) {
  inc <- val_h |> filter(regla %in% c("H3 carril-día sin vehículos", "H2 horas incompletas (> 10 % del mes)")) |>
    group_by(estacion_id, sentido) |>
    summarise(carril_dias_sin_vehiculos = sum(filas[regla == "H3 carril-día sin vehículos"]),
              meses_con_horas_incompletas = sum(regla == "H2 horas incompletas (> 10 % del mes)"), .groups = "drop")
  geo |>
    left_join(cs |> select(estacion_id, sentido, carriles_catalogo = carriles_principales, carriles_auxiliares_catalogo = carriles_auxiliares,
                           descripcion_catalogo = descripcion), by = c("estacion_id", "sentido")) |>
    left_join(cap |> select(estacion_id, sentido, p99_por_carril_2025 = p99, max_por_carril_2025 = max,
                            caudal_con_cola_por_carril_2025 = caudal_en_cola_p50), by = c("estacion_id", "sentido")) |>
    left_join(inc, by = c("estacion_id", "sentido")) |>
    mutate(across(c(carril_dias_sin_vehiculos, meses_con_horas_incompletas), ~ coalesce(.x, 0)),
           fecha_catalogo = fecha_catalogo,
           coincide_catalogo = carriles_aforados == carriles_catalogo,
           capacidad_p99_sentido_2025 = p99_por_carril_2025 * carriles_aforados) |>
    left_join(ESTACIONES_TF5 |> select(estacion_id, etiqueta, orden), by = "estacion_id") |>
    arrange(sentido, orden) |>
    relocate(estacion_id, etiqueta, sentido, tramo)
}

# ---- 3. Balance por tramos y sensibilidad de la holgura -----------------------------
# Pares de estaciones consecutivas (en el sentido de la marcha). Entre dos estaciones
# solo hay ramales: diferencia de caudal = entradas - salidas (puede ser negativa). Con
# datos completos de las dos, la diferencia diaria debe ser estable de un día a otro.
PARES_TRAMOS <- tibble::tribble(
  ~arriba, ~abajo, ~sentido,
  123, 111, "descendente", 111, 103, "descendente", 103, 99, "descendente", 99, 97, "descendente", 97, 93, "descendente",
  93, 85, "descendente", 103, 93, "descendente",
  85, 93, "ascendente", 93, 97, "ascendente", 97, 99, "ascendente", 99, 103, "ascendente", 103, 111, "ascendente", 111, 123, "ascendente")

balance_tramos <- function(sc, anios = c(2025, 2026), pares = PARES_TRAMOS) {
  et <- function(e) ESTACIONES_TF5$etiqueta[match(e, ESTACIONES_TF5$estacion_id)]
  filas <- bind_rows(lapply(seq_len(nrow(pares)), function(i) {
    a <- sc |> filter(anio %in% anios, estacion_id == pares$arriba[i], sentido == pares$sentido[i]) |>
      select(dia, hora, anio, F_arriba = veh, cola_arriba = congestionada)
    b <- sc |> filter(anio %in% anios, estacion_id == pares$abajo[i], sentido == pares$sentido[i]) |>
      select(dia, hora, F_abajo = veh, cola_abajo = congestionada)
    inner_join(a, b, by = c("dia", "hora")) |>
      mutate(arriba = pares$arriba[i], abajo = pares$abajo[i], sentido = pares$sentido[i], neto = F_abajo - F_arriba,
             tramo = paste(et(pares$arriba[i]), "->", et(pares$abajo[i])))
  }))
  diario <- filas |> group_by(sentido, tramo, arriba, abajo, anio, dia) |> filter(n() == 24) |>
    summarise(neto = sum(neto), F_arriba = sum(F_arriba), .groups = "drop")
  resumen <- filas |> group_by(sentido, tramo, arriba, abajo) |>
    summarise(horas = n(), flujos_negativos = sum(F_arriba < 0 | F_abajo < 0), horas_neto_negativo = mean(neto < 0),
              .groups = "drop") |>
    left_join(diario |> group_by(sentido, tramo, arriba, abajo) |>
                summarise(dias_completos = n(), neto_dia_mediana = median(neto), neto_dia_p10 = cuantil(neto, 0.1),
                          neto_dia_p90 = cuantil(neto, 0.9),
                          cv_neto_dia = if (abs(mean(neto)) >= 1000) stats::sd(neto) / abs(mean(neto)) else NA_real_,   # sin sentido si el neto es ~0
                          neto_relativo = median(neto / F_arriba),
                          neto_dia_2025 = median(neto[anio == 2025]), neto_dia_2026 = median(neto[anio == 2026]), .groups = "drop"),
              by = c("sentido", "tramo", "arriba", "abajo")) |>
    mutate(estable = !is.na(cv_neto_dia) & cv_neto_dia <= 0.25 & abs(neto_dia_mediana) >= 1000,
           lectura = dplyr::case_when(
             is.na(dias_completos) | dias_completos < 30 ~ "Pocos días completos en las dos estaciones: balance no concluyente",
             abs(neto_dia_mediana) < 1000 ~ "Entradas y salidas casi se compensan: no se puede separar cada ramal",
             cv_neto_dia <= 0.25 ~ "Balance estable de un día a otro: entradas netas regulares (la estabilidad no prueba que los dos aforos sean exactos)",
             TRUE ~ "Balance inestable: alguna de las dos estaciones cuenta mal parte del tiempo (o cambian los ramales)"))
  por_hora <- filas |> filter(anio == 2025) |> group_by(sentido, tramo, arriba, abajo, hora) |>
    summarise(horas = n(), neto_mediana = median(neto), neto_p10 = cuantil(neto, 0.1), neto_p90 = cuantil(neto, 0.9),
              neto_con_cola_abajo = if (sum(cola_abajo) >= 10) median(neto[cola_abajo]) else NA_real_,
              neto_sin_cola_abajo = if (sum(!cola_abajo) >= 10) median(neto[!cola_abajo]) else NA_real_,
              cola_abajo = mean(cola_abajo), .groups = "drop")
  list(resumen = resumen, por_hora = por_hora)
}

# Variantes de la holgura del tramo siguiente. Parte de las filas de holgura_observada()
# (una por día, hora y estación de abajo) y devuelve, para cada variante, la holgura de
# la estación más restrictiva de cada hora
# Nota: holgura = (C_abajo - entradas_netas) / F_cuello - 1 = (C_abajo - F_abajo) / F_cuello,
# así que las entradas netas solo cuentan cuando se cambian (variante de los ramales).
# C_abajo sale de los caudales de la misma punta (p99): por eso se prueban otras
# estimaciones, entre ellas una que solo usa horas sin cola en la estación de abajo.
variantes_holgura <- function(sc, cuello = 103, abajo = c(99, 93), sent = "descendente", anios = 2025, est_cola = cuello,
                              carriles_inventario = NULL) {
  base <- holgura_observada(sc, cuello, abajo, sent, anios, est_cola = est_cola)
  caudales <- function(e, solo_sin_cola = FALSE) {
    x <- sc[sc$anio %in% anios & sc$estacion_id == e & sc$sentido == sent, ]
    if (solo_sin_cola) x <- x[!x$congestionada, ]
    x$veh
  }
  Cq <- function(q, solo_sin_cola = FALSE) stats::setNames(vapply(abajo, function(e) cuantil(caudales(e, solo_sin_cola), q), numeric(1)), abajo)
  recalc <- function(x) x |> mutate(holgura = (C_abajo - entradas_netas) / F_cuello - 1)
  con_C <- function(x, C) recalc(x |> mutate(C_abajo = unname(C[as.character(estacion_abajo)])))
  hay_velocidad <- any(base$cong_abajo)
  v <- list(
    "Principal: capacidad de abajo = p99 de su caudal; entradas netas de los aforos" = function(x) x,
    "Capacidad de abajo más baja (p95 de su caudal)" = function(x) con_C(x, Cq(0.95)),
    "Capacidad de abajo más alta (p99,9 de su caudal)" = function(x) con_C(x, Cq(0.999)))
  if (hay_velocidad)
    v[["Capacidad de abajo solo con horas sin cola en esa estación (p99)"]] <- function(x) con_C(x, Cq(0.99, TRUE))
  v[["Ramales: entradas un 10 % mayores (demanda que hoy no consigue entrar)"]] <- function(x)
    x |> mutate(holgura = (C_abajo - (entradas_netas + 0.1 * pmax(entradas_netas, 0))) / F_cuello - 1)
  v[["Ramales desconocidos: salidas del 5 % del caudal después del punto crítico"]] <- function(x) x |> mutate(holgura = holgura - 0.05)
  if (hay_velocidad)
    v[["Cuello desplazado: sin holgura en las horas con cola en la estación de abajo"]] <- function(x)
      x |> mutate(holgura = ifelse(cong_abajo, pmin(holgura, 0), holgura))
  if (!is.null(carriles_inventario) && length(carriles_inventario)) {
    nm <- paste0("Carriles del inventario de 2006 en ", paste(ESTACIONES_TF5$etiqueta[match(as.numeric(names(carriles_inventario)), ESTACIONES_TF5$estacion_id)],
                                                            collapse = " y "),
                 " (cota baja: ", paste(carriles_inventario, collapse = "/"), " x 1.850 x 0,82)")
    v[[nm]] <- function(x) {
      tope <- unname(carriles_inventario[as.character(x$estacion_abajo)]) * 1850 * 0.82
      recalc(x |> mutate(C_abajo = ifelse(is.na(tope), C_abajo, pmin(C_abajo, tope))))
    }
  }
  v[["Holgura nula en todas las horas"]] <- function(x) x |> mutate(holgura = 0)
  lapply(v, function(f) f(base) |> group_by(dia, hora) |> slice_min(holgura, n = 1, with_ties = FALSE) |> ungroup())
}

# Forma reducida de escenarios_cuello(): solo las alternativas que dependen de la
# holgura (mismas fórmulas; las pruebas comprueban que dan lo mismo)
escenarios_holgura <- function(p, V_dir, carriles, prof, ht) {
  prop <- isTRUE(prof$propagacion)
  cb <- capacidades(p, carriles, ht, propagacion = prop)
  base <- evaluar(prof, cb$antes, cb$caida); d0 <- base$demora_media_joroba
  red <- function(prof_x, cap_x, caida_x, h) {
    s <- equilibrio_inducido(prof_x, cap_x, caida_x, eta_horizonte(p, h), p$T_libre, d0)
    evaluar(prof_x, cap_x, caida_x, s)$demora_vh
  }
  tc <- capacidades(p, carriles, ht, propagacion = prop, alternativa = "tercer_carril")
  rm <- capacidades(p, carriles, ht, propagacion = prop, alternativa = "regulacion")
  prof_esc <- prof; prof_esc$joroba <- escalonar(prof$joroba, p$desplazamiento_horario)
  s1 <- equilibrio_inducido(prof, tc$antes, tc$caida, eta_horizonte(p, "corto"), p$T_libre, d0)
  tc1 <- evaluar(prof, tc$antes, tc$caida, s1)
  v <- c(tercer_carril_corto = tc1$demora_vh, tercer_carril_largo = red(prof, tc$antes, tc$caida, "largo"),
         ramp_metering_corto = red(prof, rm$antes, rm$caida, "corto"), paquete_gestion_corto = red(prof_esc, rm$antes, rm$caida, "corto"))
  # Cuello desplazado: con el tercer carril, ¿quién marca el caudal en los minutos con cola?
  # El tramo siguiente, si admite menos que los tres carriles (D < (carriles + 1) x capacidad)
  D <- carriles * p$c_carril * (1 - p$caida_capacidad) * (1 + if (prop) ht else pmax(ht, 0))
  limitado <- rep_len(D < (carriles + 1) * p$c_carril, DURACION_MIN)
  list(reduccion = if (base$demora_vh > DEMORA_MINIMA_VH) 1 - v / base$demora_vh else v * NA,
       limitado_por_abajo = if (any(tc1$Q > 0.5)) mean(limitado[tc1$Q > 0.5]) else NA_real_,
       horas_cola_hoy = base$min_con_cola / 60, horas_cola_con_tercer_carril = tc1$min_con_cola / 60)
}

# duracion: rango de horas de cola calibrado con 2025 (obj$duracion). Con la propagación de
# la cola, una variante con menos capacidad abajo también alarga la cola de hoy: si la
# cola de hoy del modelo sale del rango medido, los aforos de 2025 no son compatibles con
# esa variante (columna parte_cola_hoy_en_rango_medido).
sensibilidad_holgura <- function(mc, variantes, caso, horas_clave, etiquetas = ETIQUETAS_ESC, n_max = 300, semilla = 51,
                                 duracion = NULL) {
  set.seed(semilla)
  d <- mc$draws; if (nrow(d) > n_max) d <- d[sort(sample.int(nrow(d), n_max)), ]
  resumen <- bind_rows(lapply(names(variantes), function(nm) {
    x <- variantes[[nm]]
    x |> filter(hora %in% horas_clave) |> group_by(hora) |>
      summarise(horas_con_cola = n(), holgura_p10 = cuantil(holgura, 0.1), holgura_mediana = median(holgura),
                holgura_p90 = cuantil(holgura, 0.9), sin_holgura = mean(holgura <= 0), .groups = "drop") |>
      mutate(variante = nm)
  })) |> mutate(caso = caso) |> relocate(caso, variante)
  res <- bind_rows(lapply(names(variantes), function(nm) {
    HHv <- matriz_holgura_horaria(variantes[[nm]])
    r <- lapply(seq_len(nrow(d)), function(i) {
      p <- as.list(d[i, ])
      escenarios_holgura(p, mc$V_dir, mc$carriles, perfil_de(p, mc$V_dir, mc$perfil_obs), holgura_minutos(HHv, p$holgura_cuantil))
    })
    red <- do.call(rbind, lapply(r, `[[`, "reduccion"))
    lim <- vapply(r, `[[`, numeric(1), "limitado_por_abajo")
    tibble(variante = nm, escenario = colnames(red),
           mediana = apply(red, 2, stats::median, na.rm = TRUE), p10 = apply(red, 2, cuantil, 0.1),
           p90 = apply(red, 2, cuantil, 0.9),
           horas_cola_hoy = median(vapply(r, `[[`, numeric(1), "horas_cola_hoy")),
           parte_cola_hoy_en_rango_medido = if (is.null(duracion)) NA_real_ else
             mean(vapply(r, `[[`, numeric(1), "horas_cola_hoy") >= duracion[1] & vapply(r, `[[`, numeric(1), "horas_cola_hoy") <= duracion[2]),
           horas_cola_con_tercer_carril = median(vapply(r, `[[`, numeric(1), "horas_cola_con_tercer_carril")),
           cola_restante_limitada_por_abajo = if (all(is.na(lim))) NA_real_ else stats::median(lim, na.rm = TRUE),
           simulaciones = nrow(red))
  })) |> mutate(caso = caso, etiqueta = unname(etiquetas[escenario])) |> relocate(caso, variante, escenario, etiqueta)
  list(holgura = resumen, resultados = res)
}

# ---- 4. Indicadores de demora: definición y contraste indirecto ----------------------
# Ningún indicador de demora del proyecto está medido: todos son simulados. Esta tabla
# da la unidad, el denominador, el horizonte y el método de cada uno, su valor en la
# situación actual simulada y con qué dato independiente se puede contrastar
# carriles_cola: carriles del tramo donde se acumula la cola (aguas arriba del cuello), que
# no tienen por qué ser los del cuello: la cola de la tarde se forma en el tramo de 3 carriles.
indicadores_demora <- function(mc, caso, espera_prensa = c(10, 40), k_atasco = 140L, aguas_arriba = "La Matanza",
                               carriles_cola = mc$carriles) {
  b <- mc$resultados |> filter(escenario == "base")
  d <- mc$draws
  f <- function(indicador, unidad, denominador, horizonte, metodo, x, contraste) {
    tibble(caso = caso, indicador = indicador, unidad = unidad, denominador = denominador, horizonte = horizonte, metodo = metodo,
           categoria = "simulado", simulado_p10 = cuantil(x, 0.1), simulado_mediana = cuantil(x, 0.5), simulado_p90 = cuantil(x, 0.9),
           contraste_independiente = contraste)
  }
  dentro <- mean(d$base_espera_max >= espera_prensa[1] & d$base_espera_max <= espera_prensa[2])
  bind_rows(
    f("Demora total", "vehículos·hora por día laborable", "ninguno (suma de todos los vehículos del día)", "un día laborable completo (24 h)",
      "Área entre las curvas acumuladas de llegadas y salidas (cola puntual FIFO, Newell)", b$demora_vh,
      "Sin dato independiente: no hay tiempos de recorrido publicados"),
    f("Espera media en la hora punta", "minutos por vehículo", "vehículos que llegan en los 60 minutos de más llegadas",
      "hora punta del día", "Media de la espera de cada cohorte de llegada, ponderada por sus vehículos", b$demora_media_punta,
      "Sin dato independiente"),
    f("Espera máxima", "minutos", "el vehículo que más espera", "un día laborable", "Máximo de la espera por cohortes", b$espera_max,
      sprintf("Prensa: franja supuesta de %d-%d min, que cubre los 15-20 min que estima Atlántico Hoy (24-11-2025) y los 40 min de un día con incidente (COPE, 20-10-2021); el %s de las combinaciones calibradas cae en esa franja (contraste débil: estimaciones periodísticas, sin fecha ni tramo exactos)",
              espera_prensa[1], espera_prensa[2], pct_es(dentro))),
    f("Duración de la cola", "horas por día", "minutos con más de medio vehículo en cola / 60", "un día laborable",
      "Cola puntual", b$horas_con_cola, "Indirecto: horas con >= 60 % de vehículos a menos de 80 km/h en el aforo (ver horas como el aforo)"),
    f("Horas de cola como las cuenta el aforo", "horas enteras por día", "horas del día", "un día laborable",
      "Horas en que >= 60 % de los vehículos que pasan lo hacen con cola", d$base_horas_aforo,
      "Directo con los aforos (velocidad): calibrado con 2025 y contrastado día a día con 2026"),
    f("Cola máxima", "vehículos", "ninguno", "un día laborable", "Máximo de vehículos acumulados en la cola puntual", b$cola_max,
      "Sin dato independiente: la cola puntual no tiene longitud; no hay medidas de longitud de cola"),
    f("Longitud equivalente de la cola máxima", "km",
      sprintf("densidad de atasco supuesta: %d veh/km por carril, en los %d carriles del tramo donde se forma la cola", k_atasco, carriles_cola),
      "un día laborable", "Cola máxima / (densidad de atasco x carriles del tramo de la cola). Solo orientativo: la cola puntual no ocupa espacio en el modelo",
      b$cola_max / (k_atasco * carriles_cola),
      sprintf("Sin dato independiente: no hay medidas de longitud de cola, y la estación de aguas arriba (%s) no tiene velocidad utilizable", aguas_arriba)))
}

# ---- 5. Diseño del Monte Carlo ----------------------------------------------------------
DEPENDENCIAS_MC <- c(
  eta_largo = "Se toma min(eta_largo, eta_corto): a 10 años la demanda inducida nunca es menor que el primer año",
  eta_medio = "Derivada (no se muestrea): ajuste parcial entre eta_corto y eta_largo con persistencia_anual",
  holgura_aguas_abajo = "No se usa la triangular: se muestrea un cuantil u ~ U(0, 1) común a todas las horas (día bueno o malo aguas abajo) y la holgura de cada hora es ese cuantil de su distribución estimada; mínimo, moda y máximo de esta tabla son solo descriptivos (p10, mediana y p90 de las horas con cola; un valor negativo se muestra como 0, aunque el modelo usa la holgura negativa cuando la especificación incluye la propagación)",
  t0_punta = "Independiente; la calibración selecciona los valores compatibles con el inicio y el fin de la cola",
  sigma_punta = "Independiente; la calibración selecciona los valores compatibles con la duración de la cola",
  equivalencia_pesados = "Solo si la especificación incluye la mezcla de pesados; se muestrea al final con su propia semilla (la del caso + 50.000) y el generador vuelve a su estado, así que no cambia el resto de la muestra")

diseno_montecarlo <- function(par, mc_todo, mc, objetivo, caso) {
  d <- mc_todo$draws
  con_matriz <- !is.null(mc_todo$holgura_horaria)
  parametros <- par |>
    transmute(caso = caso, parametro,
              distribucion = dplyr::case_when(parametro == "holgura_aguas_abajo" & con_matriz ~ "empírica por hora (cuantil común u ~ U(0, 1))",
                                              minimo == maximo ~ "fijo", TRUE ~ "triangular (mínimo, moda, máximo)"),
              minimo, moda = central, maximo, tipo, fuente,
              dependencia = ifelse(parametro %in% names(DEPENDENCIAS_MC), DEPENDENCIAS_MC[parametro], "Independiente de los demás"),
              numeros_aleatorios = "Semilla 2026 en los dos casos y mismo orden de parámetros: los dos casos comparten los números aleatorios (números aleatorios comunes); los parámetros con el mismo rango toman los mismos valores en las dos muestras")
  crit <- list(
    "Duración de la cola (horas como el aforo)" = d$base_horas_aforo >= objetivo$duracion[1] & d$base_horas_aforo <= objetivo$duracion[2],
    "Caudal de descarga" = cumple_descarga(d, objetivo),
    "Inicio de la cola" = !is.na(d$base_inicio_aforo) & d$base_inicio_aforo >= objetivo$inicio[1] & d$base_inicio_aforo <= objetivo$inicio[2],
    "Fin de la cola" = !is.na(d$base_fin_aforo) & d$base_fin_aforo >= objetivo$fin[1] & d$base_fin_aforo <= objetivo$fin[2],
    "La cola se disipa dentro del día" = d$base_cola_final < 0.5)
  umbral <- c(sprintf("%s-%s h", num_es(objetivo$duracion[1], 0.1), num_es(objetivo$duracion[2], 0.1)),
              sprintf("%s-%s veh/h (%s)", num_es(ventana_descarga(objetivo)[1]), num_es(ventana_descarga(objetivo)[2]),
                      if (identical(objetivo$medida_descarga, "como_aforo")) "medida como en el aforo" else "parámetro"),
              sprintf("%s-%s", hora_txt(objetivo$inicio[1]), hora_txt(objetivo$inicio[2])),
              sprintf("%s-%s", hora_txt(objetivo$fin[1]), hora_txt(objetivo$fin[2])), "cola final < 0,5 veh")
  todos <- Reduce(`&`, crit)
  filtros <- bind_rows(
    tibble(regla = names(crit), umbral = umbral, pasan = vapply(crit, sum, integer(1))),
    tibble(regla = "Todas salvo la descarga", umbral = "", pasan = sum(Reduce(`&`, crit[-2]))),
    tibble(regla = "Todas (calibración principal)", umbral = "", pasan = sum(todos))) |>
    mutate(caso = caso, simuladas = nrow(d), tasa = pasan / simuladas, descartadas = 1 - tasa,
           coincide_con_calibracion = ifelse(regla == "Todas (calibración principal)", pasan == mc$n_validas, NA)) |>
    relocate(caso)
  list(parametros = parametros, filtros = filtros)
}

SEMILLAS_MC <- tibble::tribble(
  ~semilla, ~funcion, ~uso,
  2026, "simular_montecarlo()", "Muestreo de los parámetros de los dos casos (y cuantil de la holgura)",
  99, "selector_calibraciones()", "Submuestra uniforme de 3.000 combinaciones con la que se resumen las reglas de la sensibilidad y la regla «sin calibrar»",
  7, "simular_montecarlo() del Bus-VAO", "Muestreo del perfil sintético de Padre Anchieta",
  11, "grafico_bus_vao()", "Submuestra de 300 combinaciones para la curva del Bus-VAO",
  5, "curva_holgura()", "Submuestra de 300 combinaciones para la curva del tercer carril según la holgura",
  8, "salidas_por_hora()", "Submuestra de 300 combinaciones para el caudal hora a hora",
  21, "evolucion_demanda()", "Submuestra (si N_PREVISION < combinaciones calibradas)",
  22, "alternativas_futuro()", "Submuestra (si N_PREVISION < combinaciones calibradas)",
  23, "escenarios_adversos()", "Submuestra (si N_PREVISION < combinaciones calibradas)",
  24, "curva_trasvase_tp()", "Submuestra (si N_PREVISION < combinaciones calibradas)",
  31, "estabilidad_percentiles()", "Bootstrap de las simulaciones calibradas",
  3, "did_ull()", "Bootstrap por bloques de semanas",
  41, "validacion_diaria() (simulado_por_combinacion())", "Submuestra (si N_PREVISION < combinaciones calibradas)",
  51, "sensibilidad_holgura()", "Submuestra de 300 combinaciones calibradas",
  61, "validacion_modelo()", "Bootstrap por bloques de días del intervalo del 95 % de la mediana aforada en 2026",
  2027, "replicar_semillas()", "Repetición completa del Monte Carlo con otra semilla (auditoría)",
  2028, "replicar_semillas()", "Repetición completa del Monte Carlo con otra semilla (auditoría)",
  52026, "anadir_equivalencia_pesados()", "Equivalencia de los pesados (semilla del caso + 50.000: 52.026 en la calibración y en la rejilla de especificaciones; 52.027 y 52.028 en las repeticiones), solo si la especificación la usa",
  71, "intervalo_predictivo()", "Submuestra de 400 combinaciones para el intervalo predictivo",
  81, "diferencias_emparejadas()", "Bootstrap del error de la diferencia emparejada mediana",
  91, "cola_remanente()", "Submuestra de 200 combinaciones calibradas para los cuellos en serie")

# ---- 7. Procedencia de los datos -------------------------------------------------------
# Un registro por recurso oficial: organismo, conjunto, URL, identificador, licencia,
# fechas, tamaño, huella SHA-256 del original y de la copia, cobertura, filtros y
# unidades; contraste con el catálogo del portal consultado el 16-10-2026 y, para los
# aforos horarios, conservación de los totales del original en el extracto.
# Las huellas prueban que la copia no ha cambiado desde la descarga (integridad); no
# prueban la autenticidad del origen.
# Instantánea más reciente del catálogo del portal (datos/oficial/catalogo_portal_AAAA-MM-DD.json)
ultimo_catalogo <- function(dir = file.path(DIR_DATOS, "oficial")) {
  fs <- sort(list.files(dir, pattern = "^catalogo_portal_\\d{4}-\\d{2}-\\d{2}\\.json$", full.names = TRUE))
  if (!length(fs)) stop("Falta la instantánea del catálogo del portal en ", dir)
  fs[length(fs)]
}

leer_catalogo_portal <- function(ruta = ultimo_catalogo()) {
  cat_ <- jsonlite::fromJSON(ruta, simplifyVector = FALSE)
  bind_rows(lapply(names(cat_), function(k) bind_rows(lapply(cat_[[k]]$res, function(r)
    tibble(clave = k, conjunto = cat_[[k]]$title, licencia_catalogo = cat_[[k]]$license,
           conjunto_modificado = cat_[[k]]$metadata_modified, resource_id = r[[1]], nombre = r[[2]], formato = r[[3]],
           modificado_catalogo = if (is.null(r[[4]])) NA_character_ else r[[4]],
           bytes_catalogo = if (length(r) < 5 || is.null(r[[5]])) NA_real_ else as.numeric(r[[5]]))))))
}

totales_extracto <- function(fichero) {
  x <- readr::read_csv(fichero, show_col_types = FALSE, col_types = readr::cols(fecha = readr::col_character(), .default = readr::col_double()))
  x |> mutate(clave = paste0(estacion_id, ifelse(carril_id > 0, "+", "-")),
              rangos = rango1_vehiculos + rango2_vehiculos + rango3_vehiculos + rango4_vehiculos + rango5_vehiculos + rango6_vehiculos) |>
    group_by(clave) |> summarise(filas = n(), ligeros = sum(ligeros), pesados = sum(pesados), rangos = sum(rangos), .groups = "drop")
}

procedencia_datos <- function(dir = DIR_DATOS, ruta_catalogo = ultimo_catalogo(file.path(dir, "oficial"))) {
  fecha_catalogo <- format(as.Date(sub("^catalogo_portal_(.*)\\.json$", "\\1", basename(ruta_catalogo))), "%d-%m-%Y")
  catp <- leer_catalogo_portal(ruta_catalogo)
  contraste <- function(rid, bytes, modif) {
    k <- match(rid, catp$resource_id)
    if (is.na(k)) return("No figura en la instantánea del catálogo")
    mismo_b <- is.na(catp$bytes_catalogo[k]) || is.na(bytes) || abs(catp$bytes_catalogo[k] - bytes) < 0.5
    mismo_f <- is.na(catp$modificado_catalogo[k]) || is.na(modif) || substr(catp$modificado_catalogo[k], 1, 19) == substr(modif, 1, 19)
    if (mismo_b && mismo_f) sprintf("Coincide con el recurso de la instantánea del catálogo del %s guardada en el proyecto: mismo tamaño y fecha de modificación", fecha_catalogo)
    else sprintf("DISTINTO del recurso de la instantánea del catálogo del %s: %s%s", fecha_catalogo, if (!mismo_b) "tamaño " else "",
                 if (!mismo_f) "fecha de modificación" else "")
  }
  integridad <- function(f, sha) {
    if (!file.exists(f)) return("Falta la copia local")
    if (is.na(sha) || !nzchar(sha)) return("Sin huella registrada")
    if (identical(huella(f), sha)) "Copia íntegra (SHA-256 igual al registrado)" else "COPIA ALTERADA (SHA-256 distinto)"
  }
  fs <- list.files(file.path(dir, "horarios"), pattern = "^meta_\\d{4}-\\d{2}\\.json$", full.names = TRUE)
  horarios <- bind_rows(lapply(fs, function(f) {
    m <- jsonlite::fromJSON(f, simplifyVector = FALSE)
    loc <- file.path(dir, "horarios", m$fichero_local)
    tot <- totales_extracto(loc)
    ctl <- bind_rows(lapply(names(m$control), function(k) tibble(clave = k, filas_c = m$control[[k]]$filas,
                                                                ligeros_c = m$control[[k]]$ligeros, pesados_c = m$control[[k]]$pesados,
                                                                rangos_c = m$control[[k]]$rangos)))
    cmp <- full_join(tot, ctl, by = "clave")
    ok <- with(cmp, !is.na(filas) & !is.na(filas_c) & filas == filas_c & ligeros == ligeros_c & pesados == pesados_c & rangos == rangos_c)
    # m[["estaciones"]], no m$estaciones: «$» completaría el nombre con «estaciones_en_fichero»
    est_ids <- if (!is.null(m[["estaciones"]])) unlist(m[["estaciones"]]) else
      sort(unique(as.integer(sub("[+-]$", "", names(m$control)))))
    est <- paste0(length(est_ids), " estaciones de la TF-5 (", paste(est_ids, collapse = ", "), ")",
                  if (is.null(m[["estaciones"]])) ", todas las de la TF-5 que trae el fichero" else "")
    tibble(id = paste0("H-", m$mes), organismo = "Cabildo de Tenerife (portal de datos abiertos, datos.tenerife.es)",
           conjunto = sprintf("Intensidad diaria de tráfico de Tenerife (%s)", substr(m$mes, 1, 4)),
           recurso = sprintf("Registros horarios por carril, %s (TXT)", m$mes), formato = "TXT (CSV, 13 columnas)",
           url = m$url, resource_id = m$resource_id, licencia = catp$licencia_catalogo[match(m$resource_id, catp$resource_id)],
           modificado_origen = m$last_modified_ckan, descargado = m$descargado_utc, bytes_original = m$bytes_raw,
           sha256_original = m$sha256_raw, copia_local = paste0("datos/horarios/", m$fichero_local), sha256_copia = m$sha256_gz_local,
           cobertura = sprintf("%s a %s (%s filas de la TF-5)", m$fecha_min, m$fecha_max, num_es(m$filas_tf5)),
           cabecera = m$header,
           filtros = paste0("Filas de ", est, "; sin las columnas de nombre (estacion_nombre, carril_descripcion)"),
           unidades = "Vehículos por hora y carril (ligeros, pesados y seis rangos de velocidad); hora de inicio del registro",
           contraste_catalogo = contraste(m$resource_id, m$size_ckan, m$last_modified_ckan),
           conservacion_totales = if (all(ok)) sprintf("Totales del extracto = sumas de control registradas al descargar el TXT original, en las %d estaciones-sentido (filas, ligeros, pesados y rangos)", nrow(cmp))
                                  else sprintf("DIFERENCIAS en %d de %d estaciones-sentido", sum(!ok), nrow(cmp)),
           integridad = integridad(loc, m$sha256_gz_local),
           verificacion = "Contenido: SHA-256 y sumas de control calculados al descargar el TXT oficial con un script del navegador (queda su registro en meta_AAAA-MM.json, no el script). Metadatos: contrastados con la instantánea del catálogo. No se ha vuelto a descargar después")
  }))
  man <- jsonlite::fromJSON(file.path(dir, "oficial", "manifiesto_oficiales.json"), simplifyVector = FALSE)
  oficiales <- bind_rows(lapply(seq_along(man$ficheros), function(i) {
    m <- man$ficheros[[i]]
    loc <- file.path(dir, "oficial", m$fichero)
    lic <- catp$licencia_catalogo[match(m$resource_id, catp$resource_id)]
    tibble(id = paste0("O-", i), organismo = "Cabildo de Tenerife (portal de datos abiertos, datos.tenerife.es)",
           conjunto = ifelse(grepl("Media Diaria", m$name), "Intensidad Media Diaria (IMD) de tráfico de Tenerife",
                             ifelse(grepl("iccionario", m$name), "Diccionarios de datos", "Rangos de velocidades de los carriles")),
           recurso = m$name, formato = m$format, url = m$url, resource_id = m$resource_id,
           licencia = if (is.na(lic)) "cc-by (según el registro de la descarga; el recurso no está en la instantánea del catálogo)" else lic,
           modificado_origen = m$last_modified_ckan, descargado = if (is.null(m$descargado_utc)) man$descargado_utc else m$descargado_utc,
           bytes_original = m$bytes, sha256_original = m$sha256, copia_local = paste0("datos/oficial/", m$fichero), sha256_copia = m$sha256,
           cobertura = ifelse(grepl("Media Diaria", m$name), paste("Año", sub("\\D+", "", m$name), "(todas las estaciones de Tenerife)"),
                              "Catálogo completo"),
           filtros = ifelse(grepl("Media Diaria", m$name), "Ninguno en la copia; el análisis usa las filas de la TF-5", "Ninguno"),
           unidades = ifelse(grepl("Media Diaria", m$name), "Vehículos por día (media anual) por sentido; % de pesados; km/h",
                             ifelse(grepl("iccionario", m$name), "Definición de campos", "Límites de velocidad de cada rango (km/h) por carril")),
           contraste_catalogo = contraste(m$resource_id, m$bytes, m$last_modified_ckan),
           conservacion_totales = ifelse(grepl("Media Diaria", m$name), "Valores de la TF-5 contrastados uno a uno con imd_tf5_2018_2025.csv (sección 1)", "No aplica"),
           integridad = integridad(loc, m$sha256),
           verificacion = "Contenido: SHA-256 calculado al descargar. Metadatos: contrastados con la instantánea del catálogo. No se ha vuelto a descargar después")
  }))
  # Recursos del catálogo que no se han descargado: meses en TXT que faltan y diccionarios
  # (los mismos meses en JSON o ZIP son el mismo dato en otro formato)
  usados <- c(horarios$resource_id, oficiales$resource_id)
  huecos <- catp |> filter(clave %in% c("2024", "2025", "2026"), !resource_id %in% usados,
                           formato == "TXT" | grepl("iccionario", nombre)) |>
    transmute(id = paste0("F-", row_number()), organismo = "Cabildo de Tenerife (portal de datos abiertos, datos.tenerife.es)",
              conjunto, recurso = nombre, formato, url = NA_character_, resource_id, licencia = licencia_catalogo,
              modificado_origen = modificado_catalogo, descargado = NA_character_, bytes_original = bytes_catalogo,
              sha256_original = NA_character_, copia_local = NA_character_, sha256_copia = NA_character_, cobertura = NA_character_,
              cabecera = NA_character_, filtros = NA_character_, unidades = NA_character_,
              contraste_catalogo = ifelse(grepl("iccionario", recurso),
                                          sprintf("Publicado en el catálogo del %s y no descargado: los datos de ese año se leen con el diccionario de 2025 (la cabecera de los 24 TXT es la misma)", fecha_catalogo),
                                          sprintf("Publicado en el catálogo del %s pero NO incluido en el proyecto (hueco registrado)", fecha_catalogo)),
              conservacion_totales = "No aplica", integridad = "No aplica", verificacion = "No descargado")
  out <- bind_rows(horarios, oficiales, huecos)
  attr(out, "cabecera_unica") <- length(unique(stats::na.omit(horarios$cabecera))) == 1
  out
}

# Con Internet: vuelve a pedir al portal (API CKAN, package_show) los metadatos de los
# cinco conjuntos y los guarda con la fecha, para contrastarlos con procedencia_datos().
# No se ejecuta por defecto (CONTRASTAR_EN_LINEA <- FALSE en main.R).
CONJUNTOS_PORTAL <- c("2024" = "e4cf320e-dda5-4b9a-bae3-ec3d6a252c80", "2025" = "94a021a2-1dea-4526-9e17-3290b3b9add3",
                      "2026" = "d02ccf54-aca2-4a82-9ef0-fbd285b5f401", imd = "1717bda1-6b7b-43e0-be4e-e3ed060b8b97",
                      carriles = "079b37ef-674e-411f-8886-f4c5a53826ae")

consultar_catalogo_portal <- function(destino = file.path(DIR_DATOS, "oficial", paste0("catalogo_portal_", Sys.Date(), ".json"))) {
  out <- lapply(CONJUNTOS_PORTAL, function(id) {
    js <- jsonlite::fromJSON(paste0("https://datos.tenerife.es/ckan/api/3/action/package_show?id=", id), simplifyVector = FALSE)$result
    list(title = js$title, license = js$license_id, metadata_modified = js$metadata_modified,
         res = lapply(js$resources, function(r) list(r$id, r$name, r$format, r$last_modified, r$size)))
  })
  jsonlite::write_json(out, destino, auto_unbox = TRUE, pretty = TRUE, null = "null")
  invisible(destino)
}

# ---- 8. Series con banderas de calidad -----------------------------------------------
# Los originales no se tocan: se escribe una copia depurada con una bandera por motivo.
# No se imputa nada (imputado = FALSE en todas las filas del análisis).
series_con_banderas <- function(hp, sd, dv, ch) {
  dup <- hp |> filter(estacion_id %in% EST_CORREDOR, tipo == "principal") |>
    count(estacion_id, sentido, dia, hora, carril_id) |> filter(n > 1) |> distinct(estacion_id, sentido, dia, hora) |>
    mutate(duplicado = TRUE)
  sd |> left_join(dup, by = c("estacion_id", "sentido", "dia", "hora")) |>
    left_join(dv |> transmute(estacion_id, sentido, dia, dia_valido = TRUE), by = c("estacion_id", "sentido", "dia")) |>
    mutate(duplicado = coalesce(duplicado, FALSE), dia_valido = coalesce(dia_valido, FALSE),
           velocidad_valida = !is.na(cuota_lenta), negativos = neg, caudal_implausible = veh / carriles > CAP_MAX_CARRIL,
           agosto = substr(mes, 6, 7) == "08", cambio_de_hora = dia %in% ch$dia[ch$cambio_de_hora != ""],
           imputado = FALSE, usado_en_el_analisis = dia_valido,
           estado = ifelse(usado_en_el_analisis, "observado y usado", "excluido"),
           motivo = dplyr::case_when(usado_en_el_analisis ~ "",
                                     !laborable ~ "fin de semana o festivo",
                                     agosto ~ "agosto (fuera del análisis por diseño)",
                                     cambio_de_hora ~ "día de cambio de hora",
                                     !completa ~ "hora sin todos los carriles (día incompleto)",
                                     TRUE ~ "día no válido: incompleto o con el tráfico del día por debajo del 85 % de la mediana del mes")) |>
    transmute(estacion_id, sentido, dia, hora, laborable, veh, pesados, lento, carriles, carriles_con_dato = ncar,
              completa, velocidad_valida, duplicado, negativos, caudal_implausible, agosto, cambio_de_hora,
              dia_valido, imputado, usado_en_el_analisis, estado, motivo) |>
    arrange(estacion_id, sentido, dia, hora)
}

# Sensibilidad a la depuración: ¿cambian los indicadores medidos si se relajan o
# endurecen los filtros, o si se imputan las horas incompletas (variante, no se usa)?
sensibilidad_depuracion <- function(sd, fiab, hc_horas = list(c(103, "descendente", 3:12), c(99, "ascendente", 11:23)), anio = 2025) {
  marcar <- function(sdx, dvx) {
    bn <- base_nocturna(sdx, dvx)
    marcar_congestion(sdx, dvx, bn) |>
      left_join(fiab |> select(estacion_id, sentido, velocidad_fiable), by = c("estacion_id", "sentido")) |>
      mutate(congestionada = congestionada & velocidad_fiable)
  }
  # Método A: proporcional (los carriles que faltan llevan lo mismo que los que hay)
  imputar <- function(sdx) sdx |> mutate(imputada = !completa & ncar >= carriles - 1,
                                          veh = ifelse(imputada, veh * carriles / ncar, veh), completa = completa | imputada)
  # Método B: donante temporal (la mediana de las horas completas de la misma hora, mes y
  # estación-sentido en días laborables)
  imputar_b <- function(sdx) {
    don <- sdx |> filter(completa, laborable) |> group_by(estacion_id, sentido, mes, hora) |> summarise(veh_donante = stats::median(veh), .groups = "drop")
    sdx |> left_join(don, by = c("estacion_id", "sentido", "mes", "hora")) |>
      mutate(imputada = !completa & ncar >= carriles - 1 & !is.na(veh_donante),
             veh = ifelse(imputada, pmax(veh, veh_donante), veh), completa = completa | imputada) |> select(-veh_donante)
  }
  variantes <- list(
    "Principal (día completo, >= 85 % de la mediana del mes, sin agosto)" = function() list(sd = sd, dv = dias_validos(sd)),
    "Sin filtro del tráfico diario" = function() list(sd = sd, dv = dias_validos(sd, umbral_rel = 0)),
    "Filtro del tráfico diario estricto (>= 95 %)" = function() list(sd = sd, dv = dias_validos(sd, umbral_rel = 0.95)),
    "Con agosto" = function() list(sd = sd, dv = dias_validos(sd, excluir_agosto = FALSE)),
    "Imputando horas a las que les falta un carril: método A, proporcional" = function() { s2 <- imputar(sd); list(sd = s2, dv = dias_validos(s2)) },
    "Imputando horas a las que les falta un carril: método B, mediana de la misma hora y mes" = function() { s2 <- imputar_b(sd); list(sd = s2, dv = dias_validos(s2)) })
  bind_rows(lapply(names(variantes), function(nm) {
    v <- variantes[[nm]]()
    scx <- marcar(v$sd, v$dv)
    imp <- if ("imputada" %in% names(v$sd)) v$sd |> semi_join(v$dv, by = c("estacion_id", "sentido", "dia")) else NULL
    bind_rows(lapply(hc_horas, function(z) {
      e <- as.numeric(z[[1]]); s <- z[[2]]; hh <- as.integer(z[-(1:2)])
      hc <- horario_cola(scx, e, s, anio, hh)
      # Descarga con la misma definición que la calibración: horas con cola de la ventana del caso
      desc <- scx |> filter(anio == !!anio, estacion_id == 103, sentido == s, congestionada, hora %in% hh) |> pull(veh)
      if (e == 99) desc <- descarga_en_horas_de_cola(scx, 99, "ascendente", 103, anio) |> filter(hora %in% hh) |> pull(veh)
      tasa_imp <- if (is.null(imp)) 0 else mean(imp$imputada[imp$estacion_id == e & imp$sentido == s & imp$anio == anio])
      tibble(variante = nm, estacion_id = e, sentido = s, dias = nrow(hc), horas_cola_mediana = median(hc$horas_cola),
             horas_cola_media = mean(hc$horas_cola), inicio_mediana = median(hc$inicio, na.rm = TRUE), fin_mediana = median(hc$fin, na.rm = TRUE),
             descarga_mediana = median(desc), tasa_imputacion = tasa_imp)
    }))
  })) |> left_join(ESTACIONES_TF5 |> select(estacion_id, etiqueta), by = "estacion_id") |> relocate(variante, estacion_id, etiqueta)
}

# Cuántas horas marca cada bandera de la serie depurada, en todo el corredor y por estación
# y sentido. Las banderas se solapan (una hora puede tener varias): no suman el total excluido.
resumen_banderas <- function(ser) {
  def <- c(no_laborable = "Fin de semana o festivo autonómico o insular",
           incompleta = "Hora a la que le falta algún carril",
           sin_velocidad_utilizable = "Velocidades no utilizables (aforador sin rangos fiables)",
           duplicado = "Registro duplicado en el fichero oficial",
           negativos = "Algún rango de velocidad negativo",
           caudal_implausible = "Más vehículos por carril que el máximo físico",
           agosto = "Mes de agosto (fuera del análisis)",
           cambio_de_hora = "Día de cambio de hora",
           dia_no_valido = "Día no válido: incompleto, por debajo del 85 % de la mediana del mes, agosto o no laborable",
           no_usada = "Hora no usada en el análisis (resultado de todas las reglas)",
           imputada = "Hora imputada")
  marcas <- function(x) tibble(no_laborable = !x$laborable, incompleta = !x$completa, sin_velocidad_utilizable = !x$velocidad_valida,
                                duplicado = x$duplicado, negativos = x$negativos, caudal_implausible = x$caudal_implausible,
                                agosto = x$agosto, cambio_de_hora = x$cambio_de_hora, dia_no_valido = !x$dia_valido,
                                no_usada = !x$usado_en_el_analisis, imputada = x$imputado)
  una <- function(x, est, sen) {
    m <- marcas(x)
    tibble(estacion_id = est, sentido = sen, bandera = names(def), descripcion = unname(def), horas_totales = nrow(x),
           horas_marcadas = vapply(names(def), function(b) sum(m[[b]], na.rm = TRUE), numeric(1)),
           parte = horas_marcadas / horas_totales)
  }
  grupos <- split(ser, list(ser$estacion_id, ser$sentido), drop = TRUE)
  bind_rows(una(ser, NA_real_, "todos"),
            bind_rows(lapply(grupos, function(x) una(x, x$estacion_id[1], x$sentido[1])))) |>
    left_join(ESTACIONES_TF5 |> select(estacion_id, etiqueta), by = "estacion_id") |>
    mutate(etiqueta = coalesce(etiqueta, "Corredor (todas las estaciones)")) |>
    relocate(estacion_id, etiqueta, sentido)
}

# Cobertura y tasa de imputación por estación, mes y hora (análisis principal: 0 %;
# variante de sensibilidad: horas a las que les falta un carril)
tasa_imputacion <- function(sd) {
  sd |> filter(laborable) |>
    mutate(imputable = !completa & ncar >= carriles - 1) |>
    group_by(estacion_id, sentido, mes, hora) |>
    summarise(horas_con_dato = n(), horas_completas = sum(completa), imputadas_en_el_analisis = 0L,
              imputables_en_la_variante = sum(imputable), .groups = "drop") |>
    mutate(tasa_imputacion_analisis = 0, tasa_imputacion_variante = imputables_en_la_variante / horas_con_dato)
}

# ---- 9. Previsiones condicionadas --------------------------------------------------------
# Separa los cuatro componentes: crecimiento exógeno de la demanda (sin actuar), cambio
# de red (tercer carril) y gestión en 2030 con tres ritmos de crecimiento, transporte
# público y demanda inducida (1, 5 y 10 años). Siempre con rango y condición de validez.
previsiones_condicionadas <- function(evo, af3, tpt, res_list, esc_dem) {
  nombre_g <- function(g) esc_dem$escenario[match(round(g, 4), round(esc_dem$crecimiento_anual, 4))]
  sin_actuar <- evo |> filter(anio != 2025) |>
    transmute(caso, componente = "Crecimiento exógeno de la demanda (sin actuar)", horizonte = as.character(anio),
              escenario = paste0(nombre_g(crecimiento_anual), " (", num_es(100 * crecimiento_anual, 0.1), " % anual)"),
              indicador = "Horas de cola al día (media del modelo; si toda la demanda nueva va a la punta)",
              valor = horas_cola_sin_adaptacion, p10 = horas_cola_sin_p10, p90 = horas_cola_sin_p90,
              condicion = "Misma red y mismo reparto horario de 2025; sin cambios de transporte público; cota alta (sin adaptación de la demanda)")
  red <- af3 |> filter(escenario %in% c("tercer_carril_corto", "ramp_metering_corto", "escalonamiento_corto", "tarificacion", "paquete_gestion_corto")) |>
    transmute(caso, componente = ifelse(grepl("tercer", escenario), "Cambio de red: tercer carril en servicio", "Gestión de la demanda o de la capacidad"),
              horizonte = as.character(anio),
              escenario = paste0(etiqueta, " · crecimiento ", nombre_g(crecimiento_anual), " (", num_es(100 * crecimiento_anual, 0.1), " % anual)"),
              indicador = "Reducción de la demora (vehículos·hora) frente a no actuar ese mismo año",
              valor = reduccion_mediana, p10 = reduccion_p10, p90 = reduccion_p90,
              # componente ya está calculado con el escenario original; escenario es ahora la etiqueta.
              # La obra solo está contratada hacia Santa Cruz; hacia el Norte el tercer carril es hipotético (sin proyecto ni fecha).
              condicion = case_when(
                startsWith(componente, "Cambio de red") & caso == "manana_hacia_santa_cruz" ~
                  "Obra terminada hacia 2029-2030 (35 meses según licitación; contrato formalizado el 02-10-2026 e inicio anunciado para noviembre de 2026); holgura del tramo siguiente como en 2025, recalculada con la demanda del año",
                startsWith(componente, "Cambio de red") ~
                  "Obra hipotética: sin proyecto ni fecha (el tercer carril Guamasa-La Orotava en tramitación empieza en Guamasa); holgura de La Matanza (2 carriles) como en 2025, recalculada con la demanda del año",
                TRUE ~ "Medida implantada y mantenida; eficacia y elasticidades de la literatura (sin evidencia local)"))
  tp0 <- tpt |> filter(abs(trasvase - 0.05) < 1e-9 | abs(trasvase - 0.10) < 1e-9)
  tp <- bind_rows(
    tp0 |> transmute(caso, trasvase, horizonte = "inmediato, sin rebote", valor = reduccion_sin_rebote, p10 = p10_sin_rebote, p90 = p90_sin_rebote),
    tp0 |> transmute(caso, trasvase, horizonte = "1er año", valor = reduccion_1er_anio, p10 = p10_1er_anio, p90 = p90_1er_anio),
    tp0 |> transmute(caso, trasvase, horizonte = "10 años", valor = reduccion_10_anios, p10 = p10_10_anios, p90 = p90_10_anios)) |>
    transmute(caso, componente = "Transporte público (trasvase de la punta)", horizonte,
              escenario = paste0(pct_es(trasvase), " de la punta pasa a la guagua o al tranvía"),
              indicador = "Reducción de la demora (vehículos·hora) frente a no actuar",
              valor, p10, p90,
              condicion = "Hace falta oferta y conducta que lo permitan; con rebote, el hueco se rellena en parte con viajes nuevos en coche (mismas elasticidades)")
  ind <- bind_rows(lapply(names(res_list), function(cs) res_list[[cs]] |> mutate(caso = cs))) |>
    filter(grepl("_(corto|medio|largo)$", escenario)) |>
    transmute(caso, componente = "Demanda inducida (años tras ponerla en marcha, sin crecimiento de fondo)",
              horizonte = c(corto = "1 año", medio = "5 años", largo = "10 años")[sub(".*_", "", escenario)],
              escenario = etiqueta, indicador = "Reducción de la demora (vehículos·hora) frente a no actuar",
              valor = mediana, p10 = p10, p90 = p90,
              condicion = "Elasticidades de la literatura (-0,1 a -0,5 el 1er año; -0,3 a -1,0 a 10 años); demanda de fondo constante")
  bind_rows(sin_actuar, red, tp, ind) |> mutate(categoria = "simulado (escenario condicionado)") |> relocate(caso, componente)
}

# ---- 11. Ficha de cada alternativa ----------------------------------------------------
fichas_alternativas <- function(conf, crit, res_list, af3, adv, g_central = 0.005) {
  esc_de <- function(alt, h) ifelse(alt == "tarificacion", "tarificacion", paste0(alt, "_", h))
  res <- bind_rows(lapply(names(res_list), function(cs) res_list[[cs]] |> mutate(caso = cs)))
  r10 <- res |> transmute(caso, esc_largo = escenario, p10_10_anios = p10, p90_10_anios = p90)
  a30 <- af3 |> group_by(caso, esc_corto = escenario) |>
    summarise(mediana_2030_central = reduccion_mediana[which.min(abs(crecimiento_anual - g_central))],
              min_2030 = min(reduccion_mediana), max_2030 = max(reduccion_mediana), .groups = "drop")
  # Rango de los escenarios adversos: sin la referencia ni la cota favorable (sin demanda inducida)
  adv_r <- adv |> filter(!grepl("^Referencia|cota favorable", supuesto)) |> group_by(caso, esc_corto = escenario) |>
    summarise(min_adv = min(reduccion_mediana), max_adv = max(reduccion_mediana), .groups = "drop")
  cr <- crit |> select(alternativa, caso_crit = caso, supuesto_clave, limitacion_principal) |>
    tidyr::separate_rows(caso_crit, sep = ";")
  conf |>
    mutate(esc_corto = esc_de(alternativa, "corto"), esc_largo = esc_de(alternativa, "largo")) |>
    left_join(cr, by = "alternativa", relationship = "many-to-many") |>
    filter(caso_crit == caso | caso_crit == "ambos") |>
    left_join(r10, by = c("caso", "esc_largo")) |>
    left_join(a30, by = c("caso", "esc_corto")) |>
    left_join(adv_r, by = c("caso", "esc_corto")) |>
    transmute(caso, alternativa, nombre, tramo, horario, estado, coste,
              horizonte = ifelse(alternativa == "tarificacion", "Efecto neto observado en otras ciudades (sin horizonte)",
                                 "1er año, 5 y 10 años tras ponerla en marcha; 2030 con la demanda de ese año"),
              indicador = "Reducción de los vehículos·hora de demora del día laborable frente a no actuar (simulada)",
              supuesto_clave, mediana_1er_anio = reduccion_1er_anio, p10_1er_anio, p90_1er_anio,
              mediana_10_anios = ifelse(alternativa == "tarificacion", NA_real_, reduccion_10_anios),
              p10_10_anios = ifelse(alternativa == "tarificacion", NA_real_, p10_10_anios),
              p90_10_anios = ifelse(alternativa == "tarificacion", NA_real_, p90_10_anios),
              mediana_2030_central, min_2030_crecimiento = min_2030, max_2030_crecimiento = max_2030,
              min_escenarios_adversos = min_adv, max_escenarios_adversos = max_adv, confianza, limitacion_principal,
              categoria = "simulado: escenario condicionado a los supuestos, no efecto comprobado")
}

# ---- 10. Entorno de ejecución ------------------------------------------------------------
# Versiones con las que se generaron los resultados publicados (entorno/versiones_paquetes.csv).
# Si las instaladas son otras, el análisis corre igual, pero se avisa: pueden cambiar
# decimales (p. ej., por cambios en los cuantiles o en el generador aleatorio).
comprobar_versiones <- function(ruta = file.path("entorno", "versiones_paquetes.csv")) {
  if (!file.exists(ruta)) return(tibble(paquete = character(), fijada = character(), instalada = character(), coincide = logical()))
  v <- readr::read_csv(ruta, show_col_types = FALSE, col_types = readr::cols(.default = readr::col_character()))
  v |> mutate(instalada = vapply(paquete, function(p) if (p == "R") as.character(getRversion()) else
                                   if (requireNamespace(p, quietly = TRUE)) as.character(utils::packageVersion(p)) else "no instalado", character(1)),
              coincide = instalada == version) |>
    rename(fijada = version)
}
