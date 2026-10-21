# =============================================================================
# 08_comprobaciones_modelo.R · Comprobaciones numéricas del modelo
# -----------------------------------------------------------------------------
# Cada fila es una comprobación que se calcula ejecutando el modelo en cada
# ejecución de main.R (no leyendo el código): conservación de vehículos, identidad
# entre el área de la cola y la suma de esperas, cola y salidas físicas, efecto de
# un tramo siguiente que limita, cuellos en serie y umbral del Bus-VAO.
# =============================================================================

# Espera aproximada como cola / descarga (la que no sigue a cada cohorte de llegadas)
espera_aproximada <- function(Q, cap_hora, caida) Q / (cap_hora / 60 * (1 - caida))

comprobaciones_modelo <- function(par, mcs = list()) {
  p0 <- stats::setNames(as.list(par$central), par$parametro)
  out <- list()
  fila <- function(comprobacion, valor, resultado, cumple) tibble(comprobacion = comprobacion, valor = valor, resultado = resultado, cumple = cumple)
  V <- 45347; L <- 2; cap <- L * p0$c_carril
  prof <- perfil_demanda(V, p0$k_dir, p0$sigma_punta, p0$cuota_noche)
  lam <- prof$base + prof$joroba
  r <- simular_cola(lam, cap, p0$caida_capacidad)
  hp <- hora_punta_idx(lam)
  vh_Q <- sum((c(0, r$Q[-length(r$Q)]) + r$Q) / 2) / 60
  vh_w <- sum(lam * r$w) / 60
  out[[1]] <- fila("Identidad: área bajo la cola = suma de esperas de las llegadas (perfil sintético)", abs(vh_Q - vh_w) / vh_Q,
                   sprintf("%s frente a %s veh·h (diferencia %s)", num_es(vh_Q, 0.1), num_es(vh_w, 0.1), pct_es(abs(vh_Q - vh_w) / vh_Q, 0.01)),
                   abs(vh_Q - vh_w) / vh_Q < 1e-4)
  wa <- espera_aproximada(r$Q, cap, p0$caida_capacidad)
  out[[2]] <- fila("Espera de cada cohorte (curvas acumuladas, FIFO) frente a la aproximación cola / descarga", max(abs(wa - r$w)),
                   sprintf("diferencia máxima %s min por vehículo; espera máxima %s frente a %s min", num_es(max(abs(wa - r$w)), 0.01),
                           num_es(max(wa), 0.01), num_es(max(r$w), 0.01)), TRUE)
  pj <- sum(prof$joroba * r$w) / sum(prof$joroba); pt <- sum(lam[hp] * r$w[hp]) / sum(lam[hp])
  out[[3]] <- fila("Demora media de la parte elástica de la punta frente a todas las llegadas de la hora punta", pj - pt,
                   sprintf("%s frente a %s min/veh; día completo: %s min/veh", num_es(pj, 0.1), num_es(pt, 0.1), num_es(sum(lam * r$w) / sum(lam), 0.1)), TRUE)
  out[[4]] <- fila("Conservación: la demanda simulada suma la IMD del sentido (perfil sintético)", sum(lam) / V - 1,
                   sprintf("suma = %s veh frente a IMD %s (error %s)", num_es(sum(lam)), num_es(V), format(signif(sum(lam) / V - 1, 2))),
                   abs(sum(lam) / V - 1) < 1e-9)
  perd <- 1 - sum(escalonar(prof$joroba, 0.15)) / sum(prof$joroba)
  pb <- prof; pb$joroba <- c(prof$joroba[61:1440], rep(0, 60)); pb$joroba[1:30] <- pb$joroba[1:30] + 5   # joroba pegada al principio del día
  perd_borde <- 1 - sum(escalonar(pb$joroba, 0.3)) / sum(pb$joroba)
  out[[5]] <- fila("Escalonamiento: vehículos que se pierden al desplazar la punta (también cerca del borde del día)", max(abs(perd), abs(perd_borde)),
                   sprintf("%s y %s", format(signif(perd, 2)), format(signif(perd_borde, 2))), max(abs(perd), abs(perd_borde)) < 1e-9)
  # Un tramo siguiente que limita (holgura negativa con propagación, o nula) anula la ganancia del tercer carril y de la regulación
  p1 <- p0; p1$holgura_aguas_abajo <- 0
  for (h in c(0, -0.05)) {
    base <- capacidades(p1, 2, rep(h, DURACION_MIN), propagacion = TRUE)
    tc <- capacidades(p1, 2, rep(h, DURACION_MIN), propagacion = TRUE, alternativa = "tercer_carril")
    rm <- capacidades(p1, 2, rep(h, DURACION_MIN), propagacion = TRUE, alternativa = "regulacion")
    d <- max(abs(tc$con_cola - base$con_cola), abs(rm$con_cola - base$con_cola))
    out[[length(out) + 1]] <- fila(sprintf("Tramo siguiente que limita (holgura %s): el tercer carril y la regulación no añaden caudal con cola", pct_es(h)),
                                   d, sprintf("diferencia máxima de la descarga con cola %s veh/h", format(signif(d, 2))), d < 1e-9)
  }
  # Dos cuellos en serie: conservación y equivalencia con un cuello sin almacenamiento
  lam2 <- c(rep(30, 300), rep(70, 120), rep(40, 300), rep(20, 720))
  x <- simular_tandem(lam2, 3700, 0.1, 3000, r = 5, almacen = 400)
  err <- max(abs(cumsum(lam2 + 5) - (cumsum(x$sB) + x$QA + x$QB + x$QR)))
  x0 <- simular_tandem(lam2, 3700, 0.1, 3000, r = 0, almacen = 0)
  s0 <- simular_cola(lam2, 3000, 1 - min(3700 * 0.9, 3000) / 3000)
  out[[length(out) + 1]] <- fila("Dos cuellos en serie: llegadas = salidas + colas en cada minuto; sin almacenamiento equivale a un cuello con la capacidad menor",
                                 max(err, max(abs(x0$QA - s0$Q))),
                                 sprintf("error de conservación máximo %s veh; diferencia de cola con un solo cuello %s veh",
                                         format(signif(err, 2)), format(signif(max(abs(x0$QA - s0$Q)), 2))), err < 1e-6 & max(abs(x0$QA - s0$Q)) < 1e-6)
  # Con las combinaciones calibradas de cada caso: conservación, cola disipada y salidas físicas
  for (nm in names(mcs)) {
    mc <- mcs[[nm]]
    e <- t(vapply(seq_len(nrow(mc$draws)), function(i) {
      p <- as.list(mc$draws[i, ]); pr <- perfil_de(p, mc$V_dir, mc$perfil_obs)
      ht <- if (is.null(mc$holgura_horaria)) NULL else holgura_minutos(mc$holgura_horaria, p$holgura_cuantil)
      cb <- capacidades(p, mc$carriles, ht, propagacion = isTRUE(pr$propagacion))
      rr <- evaluar(pr, cb$antes, cb$caida)
      tope <- cb$antes * (if (is.null(pr$f_cap)) 1 else pr$f_cap) / 60
      c(abs(sum(pr$base + pr$joroba) / mc$V_dir - 1), abs(sum(rr$lambda) - sum(rr$s) - rr$cola_final), min(c(rr$Q, rr$s)),
        max(rr$s - tope), rr$cola_final)
    }, numeric(5)))
    out[[length(out) + 1]] <- fila(sprintf("Conservación con el perfil de cada combinación calibrada (%s)", nm), max(e[, 1:2]),
                                   sprintf("error relativo máximo de la demanda %s; llegadas - salidas - cola final: máximo %s veh (%d combinaciones)",
                                           format(signif(max(e[, 1]), 2)), format(signif(max(e[, 2]), 2)), nrow(e)), max(e[, 1]) < 1e-9 & max(e[, 2]) < 1e-6)
    out[[length(out) + 1]] <- fila(sprintf("Cola y salidas no negativas, salidas por debajo de la capacidad y cola disipada al final del día (%s)", nm),
                                   max(pmax(-min(e[, 3]), 0), max(e[, 4]), max(e[, 5])),
                                   sprintf("mínimo de cola y salidas %s; exceso máximo de las salidas sobre la capacidad %s veh/min; combinaciones con cola al final del día: %d",
                                           format(signif(min(e[, 3]), 2)), format(signif(max(e[, 4]), 2)), sum(e[, 5] > 0.5)),
                                   min(e[, 3]) > -1e-9 & max(e[, 4]) < 1e-9 & all(e[, 5] <= 0.5))
  }
  pbv <- tryCatch(trasvase_bus_vao(p0, 59286, 3, 0), error = function(e) NA_real_)
  out[[length(out) + 1]] <- fila("Bus-VAO: umbral de equilibrio frente a 1/carriles", pbv, sprintf("%s frente a 1/3 = %s", pct_es(pbv, 0.1), pct_es(1 / 3, 0.1)),
                                 !is.na(pbv) && abs(pbv - 1 / 3) < 0.01)
  bind_rows(out) |> mutate(id = sprintf("M%02d", row_number())) |> relocate(id)
}
