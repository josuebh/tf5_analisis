# =============================================================================
# 12_validacion_predictiva.R · Calibración separada de la validación
# -----------------------------------------------------------------------------
# 1. Validación cruzada temporal dentro de 2025: los días laborables válidos se
#    reparten en dos mitades por semanas ISO alternas (impares = A, pares = B). Se
#    calibra con una mitad y se mide el error en la otra, y al revés; enero-septiembre
#    de 2026 (sin agosto) queda fuera de todo ajuste y es la prueba final.
# 2. Métricas: sesgo (modelo - aforo), error absoluto medio (MAE), raíz del error
#    cuadrático medio (RMSE) y cobertura, por indicador diario, por hora del día y por
#    sentido (cada caso es un sentido).
# 3. Dos bandas distintas, cada una con su nombre:
#    · banda de parámetros p10-p90: dispersión de las combinaciones calibradas para un
#      día laborable típico (incertidumbre de los parámetros); no es un intervalo
#      predictivo y no tiene por qué cubrir el 80 % de los días;
#    · intervalo predictivo del 80 %: la banda de parámetros más la variabilidad de un
#      día a otro y el error de observación, estimados con los residuos de los días de
#      calibración (valor del día - mediana de los días de calibración). Su cobertura se
#      mide en días no usados para calibrar.
# 4. Elección de la especificación de la descarga con una regla fijada antes de mirar
#    2026: se prueban la propagación de la cola de abajo, la descarga dependiente de la
#    hora, la mezcla de pesados y la descarga medida igual que en el aforo, y solo se
#    adopta una variante si mejora el sesgo de la descarga fuera de muestra sin empeorar
#    otros indicadores (regla en elegir_especificacion()).
# =============================================================================

# Mitad de validación cruzada de cada día: A (semana ISO impar de 2025), B (par) o 2026
pliegue_temporal <- function(dia, anio = as.integer(format(dia, "%Y"))) {
  ifelse(anio == 2026, "2026", ifelse(as.integer(format(dia, "%V")) %% 2 == 1, "A", "B"))
}

# Objetivos de calibración a partir de un conjunto de días (los de calibración)
#   dias: observado_diario()$dias de esos días; horas: horas con cola de esos días
objetivo_desde_dias <- function(dias, horas, medida_descarga = "parametro") {
  hc <- horas |> filter(cong)
  list(duracion = c(cuantil(dias$horas_cola, 0.25) - 0.5, cuantil(dias$horas_cola, 0.75) + 0.5),
       descarga = cuantil(hc$veh, c(0.1, 0.9)),
       descarga_dia = cuantil(dias$descarga_dia, c(0.25, 0.75)),
       descarga_plena = cuantil(dias$descarga_plena, c(0.25, 0.75)),
       inicio = c(cuantil(dias$inicio, 0.25) - 0.5, cuantil(dias$inicio, 0.75) + 0.5),
       fin = c(cuantil(dias$fin, 0.25) - 0.5, cuantil(dias$fin, 0.75) + 0.5),
       medida_descarga = medida_descarga)
}

# Factor de la descarga por hora: mediana del caudal en las horas con cola plena o final
# de cada hora frente a la de la hora con más horas así (la de referencia). Solo baja
# (nunca sube), solo después de la hora de referencia y solo en las horas con datos
# suficientes: al menos min_obs horas con cola y al menos el min_rel (10 %) de las de la
# hora de referencia. En las demás horas vale 1 (descarga de referencia): no se extrapola
# fuera de lo observado, porque las colas que llegan a esas horas son pocas y de días
# atípicos. extrapolar = TRUE (solo para la sensibilidad de las previsiones) mantiene el
# factor de la última hora estimada el resto del día.
factor_horario_descarga <- function(horas, min_obs = 10, min_rel = 0.1, extrapolar = FALSE) {
  x <- horas |> filter(cong, tipo %in% c("plena", "final"))
  f <- rep(1, 24)
  if (!nrow(x)) return(structure(f, hora_referencia = 7L, horas_estimadas = integer(0)))
  tab <- table(x$hora)
  href <- as.integer(names(which.max(tab)))
  ref <- stats::median(x$veh[x$hora == href])
  est <- integer(0)
  if (href < 23) for (hh in (href + 1):23) {
    v <- x$veh[x$hora == hh]
    if (length(v) >= max(min_obs, min_rel * max(tab))) { f[hh + 1] <- min(1, stats::median(v) / ref); est <- c(est, hh) }
  }
  if (extrapolar && length(est) && max(est) < 23) f[(max(est) + 2):24] <- f[max(est) + 1]
  attr(f, "hora_referencia") <- href
  attr(f, "horas_estimadas") <- est
  f
}

# Parte de pesados por hora (días laborables válidos del año) en la estación de salida
cuota_pesados_por_hora <- function(sc, est, sen, anios = 2025) {
  x <- sc |> filter(anio %in% anios, estacion_id == est, sentido == sen) |> group_by(hora) |>
    summarise(cuota = sum(pesados) / sum(veh), .groups = "drop") |> arrange(hora)
  stats::setNames(x$cuota, x$hora)[as.character(0:23)]
}

# Especificación de la descarga (va en perfil_obs$especificacion)
especificacion_descarga <- function(propagacion = FALSE, factor_descarga = NULL, cuota_pesados = NULL, hora_referencia = 7) {
  list(propagacion = propagacion, factor_descarga = if (is.null(factor_descarga)) NULL else as.numeric(factor_descarga),
       cuota_pesados = if (is.null(cuota_pesados)) NULL else as.numeric(cuota_pesados), hora_referencia = hora_referencia)
}

# Equivalencia de un pesado en vehículos ligeros (solo si la especificación usa la mezcla
# de pesados): triangular 1,5-2,5-4 (HCM: 2 en llano y 3 en terreno ondulado; más en
# rampas largas). Se muestrea con su propia semilla (semilla + 50.000, que no coincide con
# ninguna otra semilla del proyecto) y se deja el generador como estaba, para no cambiar el
# resto de la muestra.
EQUIVALENCIA_PESADOS <- c(1.5, 2.5, 4)
DESFASE_SEMILLA_PESADOS <- 50000L
anadir_equivalencia_pesados <- function(draws, semilla) {
  estado <- if (exists(".Random.seed", envir = globalenv(), inherits = FALSE)) get(".Random.seed", envir = globalenv()) else NULL
  on.exit(if (!is.null(estado)) assign(".Random.seed", estado, envir = globalenv()), add = TRUE)
  set.seed(semilla + DESFASE_SEMILLA_PESADOS)
  draws$equivalencia_pesados <- rtriang(nrow(draws), EQUIVALENCIA_PESADOS[1], EQUIVALENCIA_PESADOS[2], EQUIVALENCIA_PESADOS[3])
  draws
}

# Fila de la equivalencia de pesados para las tablas de parámetros, la auditoría del Monte
# Carlo y la reponderación de previas (no se muestrea con muestrear_parametros(): la añade
# anadir_equivalencia_pesados())
fila_equivalencia_pesados <- function(par) {
  bind_rows(par, tibble(
    parametro = "equivalencia_pesados",
    descripcion = "Equivalencia de un pesado en vehículos ligeros: la capacidad de cada hora se corrige con la parte de pesados de esa hora frente a la de la hora de referencia (solo con la especificación de la descarga con mezcla de pesados)",
    minimo = EQUIVALENCIA_PESADOS[1], central = EQUIVALENCIA_PESADOS[2], maximo = EQUIVALENCIA_PESADOS[3], unidad = "ligeros por pesado",
    tipo = "literatura",
    fuente = "HCM 6ª ed.: equivalencia de 2 en llano y 3 en terreno ondulado para tramos largos (más en rampas largas; ver c_carril); cuota de pesados por hora de los aforos de 2025",
    transferibilidad = "Transferido del HCM; los aforos no la informan directamente. Si las rampas pesan más, un valor mayor acentuaría el efecto de los pesados"))
}

# Situación actual de N combinaciones con una especificación: métricas como el aforo y
# caudal que sale cada hora (para validar por hora)
simular_base_rejilla <- function(draws, V_dir, carriles, obs, HH = NULL) {
  n <- nrow(draws); flu <- matrix(NA_real_, n, 24); m <- vector("list", n)
  h <- rep(0:23, each = 60)
  for (i in seq_len(n)) {
    p <- as.list(draws[i, ])
    prof <- perfil_de(p, V_dir, obs)
    ht <- if (is.null(HH)) NULL else holgura_minutos(HH, p$holgura_cuantil)
    b <- evaluar_actual(p, carriles, prof, ht)
    flu[i, ] <- as.numeric(tapply(b$s, h, sum))
    da <- descarga_como_aforo(b$s, b$Q)
    m[[i]] <- c(horas = b$horas_aforo, inicio = b$inicio_aforo, fin = b$fin_aforo, cola_final = b$cola_final,
                descarga_aforo = da[["dia"]], descarga_plena_sim = da[["plena"]])
  }
  list(m = as_tibble(do.call(rbind, m)) |> mutate(sim = draws$sim, descarga = carriles * draws$c_carril * (1 - draws$caida_capacidad)),
       flu = flu)
}

# Combinaciones que pasan una regla de calibración (mismas reglas que calibrar_montecarlo())
aceptadas_rejilla <- function(m, objetivo) {
  d <- m |> transmute(base_horas_aforo = horas, base_inicio_aforo = inicio, base_fin_aforo = fin, base_cola_final = cola_final,
                      descarga, base_descarga_aforo = descarga_aforo)
  which(d$base_horas_aforo >= objetivo$duracion[1] & d$base_horas_aforo <= objetivo$duracion[2] & cumple_descarga(d, objetivo) &
          !is.na(d$base_inicio_aforo) & d$base_inicio_aforo >= objetivo$inicio[1] & d$base_inicio_aforo <= objetivo$inicio[2] &
          d$base_fin_aforo >= objetivo$fin[1] & d$base_fin_aforo <= objetivo$fin[2] & d$base_cola_final < 0.5)
}

# Intervalo predictivo: valores simulados (combinaciones calibradas) más residuos diarios
# de los días de calibración (todas las parejas, con una submuestra fija si son muchas)
intervalo_predictivo <- function(sim, resid, p = c(0.1, 0.9), n_max = 400, semilla = 71) {
  sim <- sim[!is.na(sim)]; resid <- resid[!is.na(resid)]
  if (!length(sim) || !length(resid)) return(c(NA_real_, NA_real_))
  set.seed(semilla)
  if (length(sim) > n_max) sim <- sim[sample.int(length(sim), n_max)]
  cuantil(as.vector(outer(sim, resid, `+`)), p)
}

# Métricas de un indicador frente a observaciones (días u horas). Sesgo = mediana del
# modelo - media aforada; MAE y RMSE con la mediana del modelo como predicción puntual.
metricas_prediccion <- function(obs, sim, resid) {
  obs <- obs[!is.na(obs)]; sim <- sim[!is.na(sim)]
  if (!length(obs) || !length(sim))
    return(tibble(observaciones = length(obs), sesgo = NA_real_, mae = NA_real_, rmse = NA_real_,
                  cobertura_banda_parametros = NA_real_, cobertura_intervalo_predictivo = NA_real_,
                  banda_p10 = NA_real_, banda_p90 = NA_real_, ip_p10 = NA_real_, ip_p90 = NA_real_))
  b <- cuantil(sim, c(0.1, 0.5, 0.9)); ip <- intervalo_predictivo(sim, resid)
  tibble(observaciones = length(obs), observado_media = mean(obs), simulado_mediana = b[2],
         sesgo = b[2] - mean(obs), mae = mean(abs(b[2] - obs)), rmse = sqrt(mean((b[2] - obs)^2)),
         cobertura_banda_parametros = mean(obs >= b[1] & obs <= b[3]),
         cobertura_intervalo_predictivo = mean(obs >= ip[1] & obs <= ip[2]),
         banda_p10 = b[1], banda_p90 = b[3], ip_p10 = ip[1], ip_p90 = ip[2])
}

# Contraste de una especificación calibrada con unos días y probada en otros
#   ob: observado_diario() con la columna pliegue; flujos: caudal horario observado (dia, hora, veh, pliegue)
#   S: simular_base_rejilla(); objetivo: el de los días de calibración
contraste_pliegue <- function(S, objetivo, ob, flujos, cal, prueba, horas_v) {
  acc <- aceptadas_rejilla(S$m, objetivo)
  m <- S$m[acc, ]
  dc <- ob$dias |> filter(pliegue %in% cal); dp <- ob$dias |> filter(pliegue %in% prueba)
  ind <- tibble::tribble(~indicador, ~obs, ~sim, ~unidad,
                         "Horas de cola al día", "horas_cola", "horas", "h",
                         "Inicio de la cola", "inicio", "inicio", "hora del día",
                         "Fin de la cola", "fin", "fin", "hora del día",
                         "Descarga del día (medida igual en el modelo y en el aforo)", "descarga_dia", "descarga_aforo", "veh/h")
  diarios <- bind_rows(lapply(seq_len(nrow(ind)), function(k) {
    r <- dc[[ind$obs[k]]] - stats::median(dc[[ind$obs[k]]], na.rm = TRUE)
    metricas_prediccion(dp[[ind$obs[k]]], m[[ind$sim[k]]], r) |> mutate(indicador = ind$indicador[k], unidad = ind$unidad[k], nivel = "día")
  }))
  horarios <- bind_rows(lapply(horas_v, function(hh) {
    oc <- flujos |> filter(pliegue %in% cal, hora == hh); op <- flujos |> filter(pliegue %in% prueba, hora == hh)
    metricas_prediccion(op$veh, S$flu[acc, hh + 1], oc$veh - stats::median(oc$veh)) |>
      mutate(indicador = sprintf("Caudal de las %02d h", hh), unidad = "veh/h", nivel = "hora")
  }))
  bind_rows(diarios, horarios) |> mutate(calibracion = paste(cal, collapse = "+"), prueba = paste(prueba, collapse = "+"), aceptadas = length(acc))
}

# Rejilla de especificaciones: propagación x descarga por hora x mezcla de pesados, con la
# descarga calibrada como parámetro o medida igual que en el aforo. Devuelve el contraste
# de cada una en validación cruzada (A->B y B->A) y en 2026 (calibrando con todo 2025).
# Cada calibración usa solo sus días también para las entradas del modelo: perfil horario y
# total de la demanda, cuota de pesados por hora, factor horario de la descarga y holgura
# del tramo siguiente (holgura_args: argumentos de holgura_observada(); la capacidad de la
# estación de abajo también se estima solo con esos días). Así la mitad de prueba no
# interviene en nada de lo que se ajusta.
rejilla_especificaciones <- function(caso, sc, est_cola, est_salida, sen, horas_cola, par, V_dir, carriles, obs, HH,
                                     n = 10000, semilla = 2026, holgura_args = NULL) {
  ob <- observado_diario(sc, est_cola, est_salida, sen, horas_cola)
  ob$dias <- ob$dias |> mutate(pliegue = pliegue_temporal(dia, anio))
  ob$horas <- ob$horas |> mutate(pliegue = pliegue_temporal(dia, anio))
  horas_v <- seq(obs$ventana[1], obs$ventana[2] - 1)
  flujos <- sc |> filter(estacion_id == est_salida, sentido == sen, hora %in% horas_v, anio %in% c(2025, 2026)) |>
    select(dia, hora, veh, anio) |> mutate(pliegue = pliegue_temporal(dia, anio))
  set.seed(semilla)
  draws <- muestrear_parametros(par, n) |> mutate(sim = seq_len(n)) |> completar_parametros()
  draws$holgura_cuantil <- runif(n)
  draws <- anadir_equivalencia_pesados(draws, semilla)
  rejilla <- tidyr::crossing(propagacion = c(FALSE, TRUE), horario = c(FALSE, TRUE), pesados = c(FALSE, TRUE))
  calibraciones <- list(A = "A", B = "B", AB = c("A", "B"))
  pruebas <- list(A = "B", B = "A", AB = "2026")
  sc25 <- sc |> filter(anio == 2025) |> mutate(pliegue = pliegue_temporal(dia, anio))
  entradas <- lapply(calibraciones, function(cal) {
    scc <- sc25 |> filter(pliegue %in% cal)
    s <- scc |> filter(estacion_id == est_salida, sentido == sen) |> group_by(hora) |>
      summarise(cuota = sum(pesados) / sum(veh), veh = mean(veh), .groups = "drop") |> arrange(hora)   # cuota antes de redefinir veh
    stopifnot(nrow(s) == 24, all(s$cuota >= 0 & s$cuota <= 1))
    o <- obs; o$veh_hora <- s$veh
    HHc <- if (is.null(holgura_args)) HH else {
      hf <- do.call(holgura_observada, c(list(sc = scc |> select(-pliegue)), holgura_args))
      matriz_holgura_horaria(hf |> filter(restrictiva) |> distinct(dia, hora, .keep_all = TRUE))
    }
    list(obs = o, V = sum(s$veh), pes = stats::setNames(s$cuota, s$hora), HH = HHc,
         f = factor_horario_descarga(ob$horas |> filter(pliegue %in% cal)))
  })
  bind_rows(lapply(seq_len(nrow(rejilla)), function(k) {
    v <- rejilla[k, ]
    sims <- lapply(names(calibraciones), function(cn) {
      ec <- entradas[[cn]]
      fh <- if (v$horario) ec$f else NULL
      o <- ec$obs; o$especificacion <- especificacion_descarga(v$propagacion, fh, if (v$pesados) ec$pes else NULL, attr(ec$f, "hora_referencia"))
      simular_base_rejilla(draws, ec$V, carriles, o, if (v$propagacion) ec$HH else NULL)
    })
    names(sims) <- names(calibraciones)
    bind_rows(lapply(c("parametro", "como_aforo"), function(md) bind_rows(lapply(names(calibraciones), function(cn) {
      cal <- calibraciones[[cn]]
      obj <- objetivo_desde_dias(ob$dias |> filter(pliegue %in% cal), ob$horas |> filter(pliegue %in% cal), md)
      contraste_pliegue(sims[[cn]], obj, ob, flujos, cal, pruebas[[cn]], horas_v)
    })) |> mutate(medida_descarga = md))) |>
      mutate(propagacion = v$propagacion, horario = v$horario, pesados = v$pesados)
  })) |> mutate(caso = caso, uso = ifelse(prueba == "2026", "prueba final (2026, no usado para elegir)", "validación cruzada en 2025 (para elegir)")) |>
    relocate(caso, propagacion, horario, pesados, medida_descarga, calibracion, prueba, uso, aceptadas, indicador, nivel, unidad)
}

# Regla de elección, fijada antes de mirar 2026 y aplicada solo a la validación cruzada:
#   1. la referencia es la especificación más simple (sin propagación, descarga constante,
#      sin pesados, descarga como parámetro);
#   2. una variante es admisible si reduce al menos un 20 % el sesgo absoluto de la
#      descarga del día (medida igual en el modelo y en el aforo) y no empeora más de un
#      10 % el RMSE de ningún indicador;
#   3. entre las admisibles se elige la de menor RMSE relativo medio; si no hay ninguna,
#      se queda la referencia. Las coberturas se informan, pero no deciden.
# El sesgo de cada variante es la media de los sesgos absolutos de las dos mitades (un sesgo
# de +45 en una y de -45 en la otra no cuenta como 0). Si una mitad no tiene combinaciones
# aceptadas, sus métricas son NA y la variante no es admisible.
elegir_especificacion <- function(rej, mejora_min = 0.2, empeora_max = 0.10) {
  cv <- rej |> filter(prueba != "2026") |>
    group_by(propagacion, horario, pesados, medida_descarga, indicador) |>
    summarise(sesgo_abs = mean(abs(sesgo)), sesgo = mean(sesgo), rmse = mean(rmse), cobertura_ip = mean(cobertura_intervalo_predictivo),
              aceptadas = mean(aceptadas), .groups = "drop")
  ref <- cv |> filter(!propagacion, !horario, !pesados, medida_descarga == "parametro") |>
    select(indicador, rmse_ref = rmse, sesgo_abs_ref = sesgo_abs)
  ind_desc <- "Descarga del día (medida igual en el modelo y en el aforo)"
  uno <- function(x) if (length(x) == 1) x else NA_real_
  res <- cv |> left_join(ref, by = "indicador") |> mutate(ratio = rmse / rmse_ref) |>
    group_by(propagacion, horario, pesados, medida_descarga) |>
    summarise(aceptadas = round(mean(aceptadas)),
              rmse_relativo_medio = if (all(is.na(ratio))) NA_real_ else mean(ratio, na.rm = TRUE),
              peor_rmse_relativo = if (anyNA(ratio)) NA_real_ else max(ratio),
              indicador_que_mas_empeora = if (all(is.na(ratio))) NA_character_ else indicador[which.max(ratio)],
              sesgo_descarga = uno(sesgo_abs[indicador == ind_desc]), sesgo_descarga_referencia = uno(sesgo_abs_ref[indicador == ind_desc]),
              mejora_sesgo_descarga = 1 - sesgo_descarga / sesgo_descarga_referencia,
              cobertura_ip_minima = if (all(is.na(cobertura_ip))) NA_real_ else min(cobertura_ip, na.rm = TRUE), .groups = "drop") |>
    mutate(referencia = !propagacion & !horario & !pesados & medida_descarga == "parametro",
           admisible = coalesce(!referencia & mejora_sesgo_descarga >= mejora_min & peor_rmse_relativo <= 1 + empeora_max, FALSE)) |>
    arrange(desc(admisible), rmse_relativo_medio)
  elegida <- if (any(res$admisible)) res[which(res$admisible)[1], ] else res[res$referencia, ]
  res |> mutate(elegida = propagacion == elegida$propagacion & horario == elegida$horario & pesados == elegida$pesados &
                  medida_descarga == elegida$medida_descarga)
}

# Especificación elegida, construida con todos los días de 2025 (calibración principal)
especificacion_elegida <- function(eleccion, sc, est_cola, est_salida, sen, horas_cola) {
  e <- eleccion[eleccion$elegida, ]
  ob <- observado_diario(sc, est_cola, est_salida, sen, horas_cola, anios = 2025)
  f_todo <- factor_horario_descarga(ob$horas)
  fh <- if (e$horario) f_todo else NULL
  list(especificacion = especificacion_descarga(e$propagacion, fh, if (e$pesados) cuota_pesados_por_hora(sc, est_salida, sen) else NULL,
                                                attr(f_todo, "hora_referencia")),
       medida_descarga = e$medida_descarga,
       descripcion = describir_especificacion(e$propagacion, e$horario, e$pesados, e$medida_descarga))
}

describir_especificacion <- function(propagacion, horario, pesados, medida_descarga) {
  partes <- c(if (propagacion) "propagación de la cola del tramo siguiente" else NULL,
              if (horario) "descarga dependiente de la hora" else NULL,
              if (pesados) "mezcla de pesados" else NULL)
  paste0(if (length(partes)) paste(partes, collapse = " + ") else "descarga constante",
         "; descarga calibrada ", if (medida_descarga == "como_aforo") "medida igual que en el aforo" else "como parámetro del modelo")
}

# ---- g20 · Validación fuera de muestra: especificación de referencia y elegida en 2026 ----
grafico_validacion_cruzada <- function(vcx, elx) {
  nombre_caso <- c(manana_hacia_santa_cruz = "Mañana hacia Santa Cruz", tarde_hacia_el_norte = "Tarde hacia el Norte")
  d <- bind_rows(lapply(unique(elx$caso), function(cs) {
    e <- elx |> filter(caso == cs, elegida)
    ref <- vcx |> filter(caso == cs, prueba == "2026", !propagacion, !horario, !pesados, medida_descarga == "parametro") |> mutate(especificacion = "Referencia (descarga constante)")
    ele <- vcx |> filter(caso == cs, prueba == "2026", propagacion == e$propagacion, horario == e$horario, pesados == e$pesados,
                         medida_descarga == e$medida_descarga) |> mutate(especificacion = "Elegida en 2025")
    misma <- e$referencia
    sd_obs <- vcx |> filter(caso == cs, prueba == "2026") |> group_by(indicador) |> summarise(escala = mean(rmse, na.rm = TRUE), .groups = "drop")
    bind_rows(if (misma) NULL else ref, ele |> mutate(especificacion = if (misma) "Elegida en 2025 (= referencia)" else especificacion)) |>
      left_join(sd_obs, by = "indicador") |>
      mutate(caso = unname(nombre_caso[cs]))
  }))
  orden <- unique(d$indicador)
  d <- d |> mutate(indicador = factor(indicador, levels = rev(orden)))
  largo <- bind_rows(d |> transmute(caso, indicador, especificacion, metrica = "Sesgo / RMSE medio (0 = sin sesgo)", valor = sesgo / escala),
                     d |> transmute(caso, indicador, especificacion, metrica = "Días u horas dentro del intervalo predictivo del 80 %", valor = cobertura_intervalo_predictivo))
  ref_l <- tibble(metrica = c("Sesgo / RMSE medio (0 = sin sesgo)", "Días u horas dentro del intervalo predictivo del 80 %"), x = c(0, 0.8))
  cols <- c("Referencia (descarga constante)" = GRIS_ENFASIS, "Elegida en 2025" = PAL[["azul"]], "Elegida en 2025 (= referencia)" = PAL[["azul"]])
  largo <- largo |> filter(!is.na(valor))
  ggplot(largo, aes(valor, indicador, colour = especificacion)) +
    geom_vline(data = ref_l, aes(xintercept = x), colour = TINTA_MUTE, linewidth = 0.4, linetype = "22") +
    geom_point(size = 2.8) +
    facet_grid(caso ~ metrica, scales = "free", space = "free_y", labeller = labeller(metrica = label_wrap_gen(30))) +
    scale_colour_manual(values = cols, name = NULL) +
    scale_x_continuous(labels = function(x) ifelse(abs(x) <= 1.2 & x >= 0 & x <= 1, pct_es(x), num_es(x, 0.1))) +
    labs(title = "Validación fuera de muestra: enero-septiembre de 2026, no usado para calibrar ni para elegir",
         subtitle = envolver(paste("Cada punto, un indicador diario (horas, inicio, fin y descarga de la cola) o el caudal de una hora de la punta.",
                                   "Izquierda: sesgo del modelo (mediana de las combinaciones calibradas menos la media aforada) dividido por el RMSE medio",
                                   "de las especificaciones. Derecha: parte de los días (o de las horas) de 2026 dentro del intervalo predictivo del 80 %",
                                   "(banda de parámetros más la variabilidad de un día a otro y el error de observación de 2025)."), 112),
         x = NULL, y = NULL,
         caption = envolver(paste("La especificación se elige con validación cruzada en 2025 (semanas alternas) y una regla fijada antes de mirar 2026:",
                                  "mejorar al menos un 20 % el sesgo de la descarga sin empeorar más de un 10 % el RMSE de ningún indicador.",
                                  "Tablas: validacion_cruzada.csv y eleccion_especificacion.csv."), 150)) +
    tema_tf5(10) + theme(panel.grid.major.y = element_blank(), panel.grid.major.x = element_line(colour = REJILLA, linewidth = 0.3))
}
