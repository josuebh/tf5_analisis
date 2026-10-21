# Pruebas de calidad y trazabilidad: invariantes físicos de la cola, casos extremos,
# balance de la holgura, métricas de validación, procedencia de los datos, series con
# banderas y no regresión frente a los resultados de referencia

perfil_calidad <- function() c(240, 120, 80, 110, 300, 1490, 3490, 3280, 3020, 3110, 3010, 3000, 2810, 2920,
                              3160, 3090, 3110, 2910, 2630, 2270, 1860, 1310, 950, 580)

# Fichero sintético en el formato oficial (cinco días laborables, cuatro carriles, un
# duplicado y un rango negativo); cada fichero de pruebas se ejecuta por separado
fichero_sintetico_calidad <- function() {
  dias <- seq(as.Date("2025-10-06"), as.Date("2025-10-10"), by = "day")
  g <- expand.grid(hora = 0:23, dia = dias, carril_id = c(-2, -1, 1, 2))
  g$fecha <- sprintf("%s %02d:00:00", format(g$dia), g$hora)
  g$ligeros <- ifelse(g$hora %in% 6:20, 1500, 100); g$pesados <- 20
  tot <- g$ligeros + g$pesados
  g$rango1_vehiculos <- round(tot * ifelse(g$carril_id < 0 & g$hora %in% 7:8, 0.9, 0.05)); g$rango2_vehiculos <- tot - g$rango1_vehiculos
  g$rango3_vehiculos <- 0; g$rango4_vehiculos <- 0; g$rango5_vehiculos <- 0; g$rango6_vehiculos <- 0
  g$estacion_id <- 103
  x <- g[, c("estacion_id", "carril_id", "fecha", "ligeros", "pesados", paste0("rango", 1:6, "_vehiculos"))]
  x <- rbind(x, x[1, ])
  x$rango3_vehiculos[5] <- -3
  x
}

comprobar_invariantes <- function(lam, cap_hora, caida, tol = 1e-7) {
  r <- simular_cola(lam, cap_hora, caida)
  mu <- rep_len(cap_hora / 60, length(lam))
  expect_true(all(r$Q >= -tol))                                   # cola nunca negativa
  expect_true(all(r$s >= -tol))                                   # salidas nunca negativas
  expect_true(all(r$s <= mu + tol))                               # nunca sale más que la capacidad del minuto
  expect_true(all(cumsum(r$s) <= cumsum(lam) + tol))              # no sale lo que no ha llegado (D(t) <= A(t))
  expect_equal(r$Q, cumsum(lam) - cumsum(r$s), tolerance = 1e-6)  # cola = llegadas - salidas acumuladas
  expect_equal(sum(lam), sum(r$s) + r$Q[length(r$Q)], tolerance = 1e-6)
  expect_true(all(r$w >= 0))
  invisible(r)
}

test_that("la cola cumple los invariantes físicos minuto a minuto con demandas y capacidades variadas", {
  set.seed(101)
  for (k in 1:25) {
    lam <- pmax(0, stats::rnorm(DURACION_MIN, runif(1, 20, 70), runif(1, 2, 25)))
    cap <- runif(1, 2400, 4200) * (1 - 0.5 * (seq_len(DURACION_MIN) %in% sample(DURACION_MIN, 30)))   # capacidad que varía
    comprobar_invariantes(lam, cap, runif(1, 0, 0.3))
  }
  pr <- perfil_hibrido(perfil_calidad(), c(6, 10), 420, 45)
  comprobar_invariantes(pr$base + pr$joroba, 2 * 1950, 0.1)
})

test_that("casos extremos: sin demanda, demanda baja, demanda que nunca se disipa y caída nula o máxima", {
  r0 <- simular_cola(rep(0, DURACION_MIN), 3900, 0.1)
  expect_equal(sum(r0$Q), 0); expect_equal(sum(r0$w), 0)
  m0 <- metricas(rep(0, DURACION_MIN), r0, rep(0, DURACION_MIN))
  expect_equal(m0$demora_vh, 0); expect_true(is.na(m0$inicio_cola))
  r1 <- comprobar_invariantes(rep(30, DURACION_MIN), 3900, 0.1)    # 1.800 veh/h frente a 3.900: sin cola
  expect_equal(max(r1$Q), 0)
  r2 <- comprobar_invariantes(rep(130, DURACION_MIN), 3900, 0.1)   # el doble de la capacidad todo el día
  expect_gt(r2$Q[DURACION_MIN], 0)                                  # no se disipa, pero se conservan los vehículos
  lam <- c(rep(40, 400), rep(90, 120), rep(40, 920))
  d <- vapply(c(0, 0.1, 0.3, 0.6), function(cd) sum(lam * simular_cola(lam, 3900, cd)$w), numeric(1))
  expect_true(all(diff(d) >= -1e-6))                                # más caída de capacidad, más demora
})

test_that("la forma reducida de los escenarios da lo mismo que escenarios_cuello(), con y sin propagación", {
  par <- readr::read_csv(file.path(DIR_DATOS, "parametros_modelo.csv"), show_col_types = FALSE)
  p <- as.list(completar_parametros(as_tibble(setNames(as.list(par$central), par$parametro))))
  p$t0_punta <- 420; p$sigma_punta <- 45
  pr <- perfil_hibrido(perfil_calidad(), c(6, 10), 420, 45)
  V <- sum(perfil_calidad())
  for (prop in c(FALSE, TRUE)) for (h in c(-0.04, 0, 0.08, 0.3)) {
    ht <- rep(h, DURACION_MIN); ht[400:460] <- h / 2
    prx <- pr; prx$propagacion <- prop
    e <- escenarios_cuello(p, V, 2, TRUE, prof = prx, holgura_t = ht)
    r <- escenarios_holgura(p, V, 2, prx, ht)
    ref <- vapply(names(r$reduccion), function(n) 1 - e[[n]]$demora_vh / e$base$demora_vh, numeric(1))
    expect_equal(unname(r$reduccion), unname(ref), tolerance = 1e-9)
  }
  r0 <- escenarios_holgura(p, V, 2, pr, rep(0, DURACION_MIN))
  expect_equal(unname(r0$reduccion[c("tercer_carril_corto", "ramp_metering_corto")]), c(0, 0), tolerance = 1e-9)
  expect_equal(r0$limitado_por_abajo, 1)                            # sin holgura, el cuello se desplaza siempre
  r1 <- escenarios_holgura(p, V, 2, pr, rep(10, DURACION_MIN))
  expect_true(is.na(r1$limitado_por_abajo) || r1$limitado_por_abajo == 0)   # con holgura enorme, nunca (o no queda cola)
  expect_lte(r1$horas_cola_con_tercer_carril, r0$horas_cola_con_tercer_carril)
})

test_that("la holgura es (capacidad de abajo - caudal de abajo) / caudal del cuello y las variantes la mueven como deben", {
  dias <- as.Date("2025-03-03") + 0:9
  g <- tidyr::crossing(dia = dias, hora = 0:23)
  mk <- function(e, veh, cong) g |> mutate(estacion_id = e, sentido = "descendente", anio = 2025L, veh = veh, congestionada = cong)
  set.seed(7)
  f103 <- ifelse(g$hora %in% 6:8, 3300, 1500) + round(stats::rnorm(nrow(g), 0, 30))
  f99 <- f103 + ifelse(g$hora %in% 6:8, 1300, 600) + round(stats::rnorm(nrow(g), 0, 30))
  f93 <- f99 + 100
  sc <- bind_rows(mk(103, f103, g$hora %in% 6:8), mk(99, f99, g$hora == 7), mk(93, f93, FALSE))
  h <- holgura_observada(sc, 103, c(99, 93), "descendente")
  expect_equal(h$holgura, (h$C_abajo - h$F_abajo) / h$F_cuello, tolerance = 1e-12)   # las entradas netas se cancelan
  v <- variantes_holgura(sc, 103, c(99, 93), "descendente", carriles_inventario = c("99" = 3))
  base <- v[[1]]
  expect_equal(nrow(base), 30)                                       # una fila por día y hora con cola
  ram <- v[[grep("entradas un 10", names(v))]]
  expect_true(all(ram$holgura <= base$holgura + 1e-12))
  expect_equal(v[[grep("salidas del 5", names(v))]]$holgura, base$holgura - 0.05, tolerance = 1e-12)
  desp <- v[[grep("Cuello desplazado", names(v))]]
  expect_true(all(desp$holgura[desp$hora == 7] <= 0))                 # con cola abajo (7 h) no hay holgura
  expect_equal(desp$holgura[desp$hora != 7], base$holgura[base$hora != 7], tolerance = 1e-12)
  expect_true(all(v[["Holgura nula en todas las horas"]]$holgura == 0))
  expect_true(all(v[[grep("p95", names(v))]]$holgura <= v[[grep("p99,9", names(v))]]$holgura + 1e-12))
  # Capacidad de abajo fijada desde fuera (la de 2025 para comparar otro periodo): se usa tal cual
  cap <- c("99" = 5000, "93" = 5100)
  h2 <- holgura_observada(sc, 103, c(99, 93), "descendente", capacidad = cap)
  expect_equal(unname(cap[as.character(h2$estacion_abajo)]), h2$C_abajo)
  expect_equal(h2$holgura, (h2$C_abajo - h2$F_abajo) / h2$F_cuello, tolerance = 1e-12)
  expect_error(holgura_observada(sc, 103, c(99, 93), "descendente", capacidad = c("99" = 5000)), "falta la capacidad")
})

test_that("el balance por tramos no tiene caudales negativos y mide bien unas entradas netas constantes", {
  dias <- as.Date("2025-03-03") + 0:39
  g <- tidyr::crossing(dia = dias, hora = 0:23)
  a <- g |> mutate(estacion_id = 103, sentido = "descendente", anio = 2025L, veh = 1000 + 50 * hora, congestionada = FALSE)
  b <- a |> mutate(estacion_id = 99, veh = veh + 400)               # 400 veh/h de entradas netas, siempre
  bt <- balance_tramos(bind_rows(a, b), anios = 2025, pares = tibble::tibble(arriba = 103, abajo = 99, sentido = "descendente"))
  expect_equal(bt$resumen$flujos_negativos, 0)
  expect_equal(bt$resumen$neto_dia_mediana, 400 * 24)
  expect_equal(bt$resumen$dias_completos, 40)
  expect_true(bt$resumen$estable)
  expect_true(all(bt$por_hora$neto_mediana == 400))
})

test_that("las métricas de contraste (sesgo, error absoluto y cobertura) son las esperadas", {
  m <- metricas_contraste(c(90, 100, 110, 130), c(95, 100, 120))
  expect_equal(m$sesgo, 100 - 107.5)
  expect_equal(m$mae, mean(abs(100 - c(90, 100, 110, 130))))
  expect_equal(m$cobertura_p10_p90, 0.5)
  expect_equal(m$bajo_p10, 0.25); expect_equal(m$sobre_p90, 0.25)
  expect_true(is.na(metricas_contraste(c(6, 7), c(6, 6, 7), relativo = FALSE)$mae_relativo))
  expect_equal(tipo_hora_cola(c(FALSE, TRUE, TRUE, TRUE, FALSE, TRUE, FALSE)),
               c("sin cola", "inicio", "plena", "final", "sin cola", "aislada", "sin cola"))
  expect_equal(trimestre(as.Date(c("2025-01-31", "2025-04-01", "2026-09-30"))), c("2025-T1", "2025-T2", "2026-T3"))
})

test_that("la procedencia de los datos es completa, íntegra y coincide con el catálogo del portal", {
  skip_if_not_installed("digest")
  pr <- procedencia_datos()
  h <- pr[grepl("^H-", pr$id), ]
  expect_gte(nrow(h), 24)
  expect_true(all(grepl("^Coincide", h$contraste_catalogo)))
  expect_true(all(grepl("^Copia íntegra", h$integridad)))
  expect_true(all(grepl("^Totales del extracto", h$conservacion_totales)))
  expect_true(all(!is.na(h$licencia) & !is.na(h$url) & !is.na(h$sha256_original) & !is.na(h$cobertura) & !is.na(h$unidades)))
  o <- pr[grepl("^O-", pr$id), ]
  expect_true(all(grepl("^Copia íntegra", o$integridad)))
  f <- pr[grepl("^F-", pr$id), ]
  expect_true(any(grepl("diciembre 2024", f$recurso)))               # hueco registrado
  expect_true(isTRUE(attr(pr, "cabecera_unica")))
  # El filtro de cada extracto nombra sus estaciones: 8 en 2024 y 2026, las 12 del fichero en 2025
  expect_match(h$filtros[h$id == "H-2024-09"], "^Filas de 8 estaciones de la TF-5 \\(83, 85, 93, 97, 99, 103, 111, 123\\)")
  expect_match(h$filtros[h$id == "H-2025-01"], "^Filas de 12 estaciones de la TF-5 \\(82, 83, 85,")
  expect_false(any(grepl("Filas de 1 estaciones", h$filtros)))
  mh <- metadatos_horarios()
  expect_equal(mh$estaciones[mh$mes == "2025-01"], "82 83 85 93 97 99 103 111 123 131 136 138")
  expect_equal(mh$estaciones[mh$mes == "2024-09"], "83 85 93 97 99 103 111 123")
})

test_that("las series con banderas no imputan nada y marcan solo los días válidos como usados", {
  car <- leer_carriles_json(); cs <- carriles_por_sentido(car)
  hp <- preparar_horarios(fichero_sintetico_calidad(), car, tibble(fecha = as.Date(character())))
  sd <- agregar_por_sentido(hp |> distinct(estacion_id, carril_id, fecha, .keep_all = TRUE), cs, estaciones = 103)
  dv <- dias_validos(sd)
  ser <- series_con_banderas(hp, sd, dv, cambio_hora(hp))
  expect_false(any(ser$imputado))
  expect_equal(sum(ser$usado_en_el_analisis), nrow(dv) * 24)
  expect_true(any(ser$negativos))
  expect_true(any(ser$duplicado))
  ti <- tasa_imputacion(sd)
  expect_true(all(ti$tasa_imputacion_analisis == 0))
})

test_that("cada extracto horario conserva los totales del TXT original (sumas de control)", {
  metas <- list.files(file.path(DIR_DATOS, "horarios"), pattern = "^meta_.*\\.json$", full.names = TRUE)
  expect_equal(length(metas), 24)
  for (m in metas) {
    x <- jsonlite::fromJSON(m, simplifyVector = FALSE)
    tot <- totales_extracto(file.path(DIR_DATOS, "horarios", x$fichero_local))
    for (k in tot$clave) {
      expect_equal(tot$ligeros[tot$clave == k], x$control[[k]]$ligeros)
      expect_equal(tot$pesados[tot$clave == k], x$control[[k]]$pesados)
      expect_equal(tot$filas[tot$clave == k], x$control[[k]]$filas)
    }
  }
})

test_that("la geometría enlaza cada estación-sentido del corredor con su fuente y su estado", {
  geo <- readr::read_csv(file.path(DIR_DATOS, "geometria_tramos.csv"), show_col_types = FALSE)
  expect_equal(nrow(geo), 14)
  expect_true(all(geo$estado %in% c("confirmado", "pendiente de confirmación")))
  expect_true(all(nzchar(geo$fuentes)))
  cs <- carriles_por_sentido(leer_carriles_json())
  x <- geo |> left_join(cs, by = c("estacion_id", "sentido"))
  expect_equal(x$carriles_aforados, x$carriles_principales)          # coincide con el catálogo oficial
  expect_true(all(geo$estado[geo$carriles_aforados != geo$carriles_inventario_2006] == "pendiente de confirmación"))
})

test_that("las versiones fijadas se leen y se comparan con las instaladas", {
  v <- comprobar_versiones(file.path(dirname(DIR_DATOS), "entorno", "versiones_paquetes.csv"))
  expect_true(all(c("R", "dplyr", "ggplot2") %in% v$paquete))
  expect_true(all(!is.na(v$instalada)))
})

test_that("cada semilla del código figura en la tabla de semillas del Monte Carlo", {
  raiz <- dirname(DIR_DATOS)
  codigo <- unlist(lapply(c(file.path(raiz, "main.R"), list.files(file.path(raiz, "R"), pattern = "\\.R$", full.names = TRUE)),
                          readLines, encoding = "UTF-8", warn = FALSE))
  usadas <- c(regmatches(codigo, regexpr("semilla = [0-9]+", codigo)), regmatches(codigo, regexpr("set\\.seed\\([0-9]+\\)", codigo)))
  usadas <- unique(as.numeric(gsub("[^0-9]", "", usadas)))
  expect_gt(length(usadas), 10)
  expect_true(all(usadas %in% SEMILLAS_MC$semilla), info = paste(setdiff(usadas, SEMILLAS_MC$semilla), collapse = ", "))
})

test_that("el rango de los escenarios adversos de cada ficha no incluye la referencia ni la cota favorable", {
  tab <- file.path(dirname(DIR_DATOS), "salidas", "tablas")
  skip_if_not(file.exists(file.path(tab, "fichas_alternativas.csv")) && file.exists(file.path(tab, "escenarios_adversos.csv")),
              "sin ejecución de main.R")
  fi <- readr::read_csv(file.path(tab, "fichas_alternativas.csv"), show_col_types = FALSE)
  ad <- readr::read_csv(file.path(tab, "escenarios_adversos.csv"), show_col_types = FALSE)
  ad <- ad[!grepl("^Referencia|cota favorable", ad$supuesto), ]
  n <- 0
  for (i in seq_len(nrow(fi))) {
    esc <- if (fi$alternativa[i] == "tarificacion") "tarificacion" else paste0(fi$alternativa[i], "_corto")
    x <- ad$reduccion_mediana[ad$caso == fi$caso[i] & ad$escenario == esc]
    if (!length(x)) next
    n <- n + 1
    expect_equal(fi$min_escenarios_adversos[i], min(x), tolerance = 1e-12)
    expect_equal(fi$max_escenarios_adversos[i], max(x), tolerance = 1e-12)
  }
  expect_gt(n, 0)
})

test_that("el comparador de ejecuciones funciona cuando todo es igual y cuando algo cambia", {
  raiz <- dirname(DIR_DATOS)
  rscript <- file.path(R.home("bin"), "Rscript")
  a <- file.path(tempdir(), "cmp_a"); b <- file.path(tempdir(), "cmp_b"); c2 <- file.path(tempdir(), "cmp_c")
  for (d in c(a, b, c2)) { unlink(d, recursive = TRUE); dir.create(file.path(d, "tablas"), recursive = TRUE) }
  x <- data.frame(id = 1:3, valor = c(0.1, 0.2, 0.3), texto = c("a", "b", "c"))
  readr::write_csv(x, file.path(a, "tablas", "t.csv")); readr::write_csv(x, file.path(b, "tablas", "t.csv"))
  x$valor[2] <- 0.25; readr::write_csv(x, file.path(c2, "tablas", "t.csv"))
  inf1 <- file.path(tempdir(), "cmp_igual.csv"); inf2 <- file.path(tempdir(), "cmp_cambia.csv")
  s1 <- system2(rscript, c("--vanilla", file.path(raiz, "tests", "comparar_ejecuciones.R"), a, b, inf1), stdout = FALSE, stderr = FALSE)
  s2 <- system2(rscript, c("--vanilla", file.path(raiz, "tests", "comparar_ejecuciones.R"), a, c2, inf2), stdout = FALSE, stderr = FALSE)
  expect_equal(s1, 0L); expect_equal(s2, 1L)
  r1 <- readr::read_csv(inf1, show_col_types = FALSE); r2 <- readr::read_csv(inf2, show_col_types = FALSE)
  expect_equal(r1$estado, "igual (byte a byte)")
  expect_equal(r2$estado, "cambia"); expect_equal(r2$dif_numerica_max, 0.05, tolerance = 1e-12)
})

test_that("no regresión: las tablas de referencia se reproducen (solo tras una ejecución completa de main.R)", {
  raiz <- dirname(DIR_DATOS)
  cfg <- file.path(raiz, "salidas", "configuracion_ejecucion.csv")
  ref <- file.path(raiz, "tests", "referencia")
  cfg_ref <- file.path(ref, "configuracion_ejecucion.csv")
  skip_if_not(file.exists(cfg) && file.exists(cfg_ref), "sin ejecución completa o sin referencias")
  # Solo se compara con una ejecución hecha con la misma configuración (simulaciones y semillas)
  leer <- function(f) readr::read_csv(f, show_col_types = FALSE, col_types = readr::cols(.default = readr::col_character()))
  a_cfg <- leer(cfg); r_cfg <- leer(cfg_ref)
  v <- function(x, k) x$valor[x$parametro == k]
  claves <- c("N_SIMULACIONES_MANANA", "N_SIMULACIONES_TARDE", "N_REJILLA", "N_PREVISION", "SEMILLAS_AUDITORIA", "zona_horaria")
  skip_if_not(all(vapply(claves, function(k) identical(v(a_cfg, k), v(r_cfg, k)), logical(1))),
              "ejecución con otra configuración que la de referencia")
  for (f in setdiff(list.files(ref, pattern = "\\.csv$"), "configuracion_ejecucion.csv")) {
    expect_true(file.exists(file.path(raiz, "salidas", "tablas", f)), info = f)
    if (!file.exists(file.path(raiz, "salidas", "tablas", f))) next
    a <- readr::read_csv(file.path(ref, f), show_col_types = FALSE)
    b <- readr::read_csv(file.path(raiz, "salidas", "tablas", f), show_col_types = FALSE)
    expect_identical(names(b), names(a), info = f)   # mismas columnas y en el mismo orden
    comunes <- intersect(names(a), names(b))
    expect_equal(nrow(b), nrow(a), info = f)
    num <- comunes[vapply(comunes, function(n) is.numeric(a[[n]]), logical(1))]
    for (n in num) expect_equal(b[[n]], a[[n]], tolerance = 1e-8, info = paste(f, n))
    for (n in setdiff(comunes, num)) expect_equal(as.character(b[[n]]), as.character(a[[n]]), info = paste(f, n))
  }
})
