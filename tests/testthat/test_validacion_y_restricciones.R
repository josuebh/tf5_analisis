# Pruebas de la validación fuera de muestra, la especificación de la descarga, la
# restricción aguas abajo (propagación y cuellos en serie), las diferencias emparejadas,
# los días atípicos y la trazabilidad de la geometría y de los gráficos

perfil_val <- function() c(240, 120, 80, 110, 300, 1490, 3490, 3280, 3020, 3110, 3010, 3000, 2810, 2920,
                           3160, 3090, 3110, 2910, 2630, 2270, 1860, 1310, 950, 580)
p_central <- function() {
  par <- readr::read_csv(file.path(DIR_DATOS, "parametros_modelo.csv"), show_col_types = FALSE)
  p <- as.list(completar_parametros(as_tibble(stats::setNames(as.list(par$central), par$parametro))))
  p$t0_punta <- 420; p$sigma_punta <- 45; p$holgura_aguas_abajo <- 0.1
  p
}

test_that("con propagación, un tramo siguiente que admite menos frena la situación actual y anula la ganancia de las alternativas", {
  p <- p_central(); h <- rep(-0.05, DURACION_MIN)
  base_sin <- capacidades(p, 2, h, propagacion = FALSE)
  base_con <- capacidades(p, 2, h, propagacion = TRUE)
  desc0 <- 2 * p$c_carril * (1 - p$caida_capacidad)
  expect_equal(base_sin$con_cola, rep(desc0, DURACION_MIN))                       # sin propagación la holgura negativa no cuenta
  expect_equal(base_con$con_cola, rep(desc0 * 0.95, DURACION_MIN))                 # con propagación descarga lo que admite abajo
  for (alt in c("tercer_carril", "regulacion")) {
    a <- capacidades(p, 2, h, propagacion = TRUE, alternativa = alt)
    expect_equal(a$con_cola, base_con$con_cola)
  }
  grande <- capacidades(p, 2, rep(5, DURACION_MIN), propagacion = TRUE, alternativa = "tercer_carril")
  expect_equal(grande$antes, rep(3 * p$c_carril, DURACION_MIN))                    # sin límite abajo, suma un carril
  rm0 <- capacidades(p, 2, NULL, alternativa = "regulacion")
  expect_equal(rm0$caida, rep(p$caida_capacidad * (1 - p$eficacia_rm), DURACION_MIN), tolerance = 1e-12)
})

test_that("la especificación de la descarga se aplica igual en todas las alternativas y conserva los vehículos", {
  p <- p_central(); vh <- perfil_val()
  obs <- list(veh_hora = vh, ventana = c(6, 10))
  pr0 <- perfil_de(p, sum(vh), obs)
  f <- rep(1, 24); f[9:12] <- 0.9
  obs$especificacion <- especificacion_descarga(FALSE, f, NULL, 7)
  pr1 <- perfil_de(p, sum(vh), obs)
  expect_equal(sum(pr1$base + pr1$joroba), sum(vh), tolerance = 1e-9)
  b0 <- evaluar_actual(p, 2, pr0); b1 <- evaluar_actual(p, 2, pr1)
  expect_gte(b1$demora_vh, b0$demora_vh)                                           # menos descarga, más demora
  expect_equal(sum(b1$lambda) - sum(b1$s), b1$cola_final, tolerance = 1e-6)
  e1 <- escenarios_cuello(p, sum(vh), 2, TRUE, prof = pr1, holgura_t = rep(0.1, DURACION_MIN))
  expect_true(all(vapply(e1, function(x) abs(sum(x$lambda) - sum(x$s) - x$cola_final) < 1e-6, logical(1))))
  # pesados: el factor vale 1 en la hora de referencia y baja con más pesados
  fp <- factor_pesados(c(rep(0.02, 7), 0.02, rep(0.04, 16)), 2.5, 7)
  expect_equal(fp[8], 1); expect_true(all(fp[9:24] < 1))
})

test_that("el factor horario de la descarga solo baja después de la hora de referencia", {
  set.seed(5)
  h <- tibble::tibble(dia = rep(as.Date("2025-03-03") + 0:39, each = 3), hora = rep(7:9, 40), cong = TRUE,
                      tipo = rep(c("plena", "final", "final"), 40), veh = c(rbind(rnorm(40, 3300, 30), rnorm(40, 3000, 30), rnorm(40, 3100, 30))))
  f <- factor_horario_descarga(h)
  expect_equal(attr(f, "hora_referencia"), 7L)
  expect_true(all(f[1:8] == 1)); expect_true(all(f[9:24] <= 1)); expect_lt(f[9], 0.95)
  # sin datos suficientes no se extrapola: las horas sin estimar valen 1
  expect_equal(attr(f, "horas_estimadas"), 8:9); expect_true(all(f[11:24] == 1))
  h2 <- dplyr::bind_rows(h, tibble::tibble(dia = as.Date("2025-03-03") + 0:2, hora = 10L, cong = TRUE, tipo = "final", veh = 2500))
  f2 <- factor_horario_descarga(h2)
  expect_equal(f2[11], 1)                                                           # 3 horas a las 10 h: pocas
  fx <- factor_horario_descarga(h, extrapolar = TRUE)                                # sensibilidad: se mantiene el de las 9 h
  expect_equal(fx[11:24], rep(fx[10], 14)); expect_equal(fx[1:10], as.numeric(f[1:10]))
})

test_that("las mitades de la validación cruzada alternan semanas de 2025 y dejan 2026 aparte", {
  d <- as.Date(c("2025-01-06", "2025-01-13", "2025-01-20", "2026-02-02"))
  expect_equal(pliegue_temporal(d), c("B", "A", "B", "2026"))
})

test_that("el intervalo predictivo cubre lo esperado y las métricas son las de su definición", {
  set.seed(11)
  sim <- rnorm(500, 100, 2); resid <- rnorm(300, 0, 10); obs <- rnorm(2000, 100, sqrt(10^2 + 2^2))
  m <- metricas_prediccion(obs, sim, resid)
  expect_equal(m$cobertura_intervalo_predictivo, 0.8, tolerance = 0.04)
  expect_lt(m$cobertura_banda_parametros, 0.4)                                     # la banda de parámetros no es predictiva
  m2 <- metricas_prediccion(c(1, 3), c(2, 2, 2), c(-1, 1))
  expect_equal(c(m2$sesgo, m2$mae, m2$rmse), c(0, 1, 1))
})

test_that("la regla de elección solo adopta una variante que mejora la descarga sin empeorar otros indicadores", {
  ind <- c("Descarga del día (medida igual en el modelo y en el aforo)", "Horas de cola al día", "Caudal de las 07 h")
  fila <- function(prop, hor, md, sesgo_d, rmse) tibble::tibble(propagacion = prop, horario = hor, pesados = FALSE, medida_descarga = md,
    prueba = "B", indicador = ind, sesgo = c(sesgo_d, 0.1, 50), rmse = rmse, cobertura_intervalo_predictivo = 0.8, aceptadas = 300)
  rej <- dplyr::bind_rows(fila(FALSE, FALSE, "parametro", 150, c(250, 1, 300)),
                          fila(TRUE, FALSE, "parametro", 100, c(240, 1, 310)),      # mejora la descarga, no empeora > 10 %
                          fila(FALSE, TRUE, "parametro", 80, c(230, 1.3, 290)),     # empeora las horas un 30 %
                          fila(TRUE, TRUE, "como_aforo", 140, c(240, 1, 280)))      # mejora < 20 %
  e <- elegir_especificacion(rej)
  expect_equal(sum(e$elegida), 1L)
  expect_true(e$propagacion[e$elegida] && !e$horario[e$elegida])
  rej2 <- rej |> dplyr::filter(!(propagacion & !horario))
  e2 <- elegir_especificacion(rej2)
  expect_true(e2$referencia[e2$elegida])                                           # sin admisibles, la referencia
})

test_that("los cuellos en serie conservan los vehículos, limitan la salida y bloquean los ramales al rebosar", {
  lam <- c(rep(30, 300), rep(75, 150), rep(40, 300), rep(20, 690))
  for (N in c(0, 300, Inf)) {
    x <- simular_tandem(lam, 3800, 0.1, 3100, r = 6, almacen = N)
    expect_lt(max(abs(cumsum(lam + 6) - (cumsum(x$sB) + x$QA + x$QB + x$QR))), 1e-6)
    expect_true(all(x$sB <= 3100 / 60 + 1e-9)); expect_true(all(x$QB <= N + 1e-6))
    expect_true(min(c(x$QA, x$QB, x$QR)) > -1e-9)
  }
  poco <- resumen_tandem(simular_tandem(lam, 3800, 0.1, 3100, r = 6, almacen = 100))
  mucho <- resumen_tandem(simular_tandem(lam, 3800, 0.1, 3100, r = 6, almacen = 1e6))
  expect_gt(poco$demora_ramales_vh, mucho$demora_ramales_vh)                      # con poco almacenamiento los ramales esperan
  expect_equal(mucho$minutos_rebose, 0)
  sin_limite <- resumen_tandem(simular_tandem(lam, 3800, 0.1, 9000, r = 0, almacen = 0))
  expect_equal(sin_limite$demora_vh, sum(simular_cola(lam, 3800, 0.1)$Q) / 60, tolerance = 1e-9)
})

test_that("escalonar no pierde vehículos ni cerca del borde del día", {
  j <- numeric(DURACION_MIN); j[1:40] <- 10; j[1400:1440] <- 7
  for (pp in c(0.1, 0.5, 1)) expect_equal(sum(escalonar(j, pp)), sum(j), tolerance = 1e-9)
})

test_that("las diferencias emparejadas se calculan combinación a combinación", {
  set.seed(2)
  n <- 400; a <- runif(n, 0.3, 0.6); b <- a - 0.02 + rnorm(n, 0, 0.01)
  res <- dplyr::bind_rows(tibble::tibble(sim = 1:n, escenario = "tercer_carril_corto", reduccion = a),
                          tibble::tibble(sim = 1:n, escenario = "paquete_gestion_corto", reduccion = b))
  d <- diferencias_emparejadas(list(resultados = res))
  x <- d[d$alternativa_a == "tercer_carril" & d$alternativa_b == "paquete_gestion", ]
  expect_equal(x$dif_mediana, stats::median(a - b), tolerance = 1e-12)
  expect_equal(x$parte_a_mayor, mean(a > b))
  expect_true(x$orden_estable)                                                     # la banda p10-p90 de la diferencia no cruza el 0
  # una diferencia sistemática pero pequeña (0,1-0,15 puntos) no da ganador
  b2 <- a - runif(n, 0.001, 0.0015)
  res2 <- dplyr::bind_rows(tibble::tibble(sim = 1:n, escenario = "tercer_carril_corto", reduccion = a),
                           tibble::tibble(sim = 1:n, escenario = "paquete_gestion_corto", reduccion = b2))
  x2 <- diferencias_emparejadas(list(resultados = res2)) |> dplyr::filter(alternativa_a == "tercer_carril", alternativa_b == "paquete_gestion")
  expect_match(x2$lectura, "^Sin diferencia material")
  # una diferencia grande y estable sí
  b3 <- a - 0.10 + rnorm(n, 0, 0.02)
  res3 <- dplyr::bind_rows(tibble::tibble(sim = 1:n, escenario = "tercer_carril_corto", reduccion = a),
                           tibble::tibble(sim = 1:n, escenario = "paquete_gestion_corto", reduccion = b3))
  x3 <- diferencias_emparejadas(list(resultados = res3)) |> dplyr::filter(alternativa_a == "tercer_carril", alternativa_b == "paquete_gestion")
  expect_match(x3$lectura, "^A reduce más que B")
})

test_that("la reponderación con la misma previa no cambia nada", {
  set.seed(4)
  par <- tibble::tibble(parametro = "c_carril", minimo = 1850, central = 1950, maximo = 2100)
  d <- tibble::tibble(sim = 1:300, c_carril = rtriang(300, 1850, 1950, 2100))
  res <- tibble::tibble(sim = 1:300, escenario = "tercer_carril_corto", reduccion = runif(300))
  r <- reponderar_previas(list(draws = d, resultados = res), par, list(igual = list(c_carril = c(1850, 1950, 2100))))
  expect_equal(r$tamano_efectivo, 300, tolerance = 1e-9)
  expect_equal(r$mediana, unname(stats::quantile(res$reduccion, 0.5, type = 1)), tolerance = 1e-12)
})

test_that("cada cálculo que usa el número de carriles tiene fuente o supuesto explícito", {
  geo <- readr::read_csv(file.path(DIR_DATOS, "geometria_tramos.csv"), show_col_types = FALSE)
  ug <- uso_geometria(geo)
  expect_gte(nrow(ug), 8)
  expect_true(all(ug$tiene_procedencia_o_supuesto))
})

test_that("cada campo de los ficheros oficiales tiene definición oficial y destino en el proyecto", {
  cc <- correspondencia_campos(file.path(DIR_DATOS, "oficial"))
  expect_gte(nrow(cc), 20)
  expect_true(all(nzchar(cc$definicion_oficial))); expect_true(all(nzchar(cc$campo_en_el_proyecto)))
})

test_that("los días atípicos se clasifican con su motivo (puentes, Navidad, Semana Santa, cambio de hora)", {
  dias <- seq(as.Date("2025-04-07"), as.Date("2025-04-30"), by = "day")
  sd <- tidyr::crossing(dia = dias, hora = 0:23) |>
    dplyr::mutate(estacion_id = 103, sentido = "descendente", anio = 2025L, mes = format(dia, "%Y-%m"),
                  laborable = as.integer(format(dia, "%u")) <= 5 & dia != as.Date("2025-04-22"), completa = TRUE,
                  veh = ifelse(hora %in% 6:9, 3000, 800), pesados = 50)
  dv <- sd |> dplyr::filter(laborable) |> dplyr::distinct(estacion_id, sentido, anio, mes, dia) |> dplyr::mutate(v = 1)
  fest <- tibble::tibble(fecha = as.Date("2025-04-22"))
  ch <- tibble::tibble(dia = as.Date("2025-04-29"), cambio_de_hora = "prueba")
  da <- dias_atipicos(sd, dv, fest, ch, ventanas = list("103|descendente" = 6:9))
  expect_true(da$puente[da$dia == as.Date("2025-04-21")])                          # lunes antes de un martes festivo
  expect_true(da$semana_santa[da$dia == as.Date("2025-04-14")])                    # Pascua de 2025: 20 de abril
  expect_equal(da$estado[da$dia == as.Date("2025-04-29")], "excluido")
  expect_equal(domingo_pascua(c(2025, 2026)), as.Date(c("2025-04-20", "2026-04-05")))
})

test_that("cada gráfico tiene tipo de resultado, horizonte, hipótesis e incertidumbre", {
  mg <- readr::read_csv(file.path(DIR_DATOS, "graficos_metadatos.csv"), show_col_types = FALSE)
  expect_true(all(nzchar(mg$tipo_resultado) & nzchar(mg$horizonte) & nzchar(mg$hipotesis) & nzchar(mg$incertidumbre)))
  expect_equal(anyDuplicated(mg$grafico), 0L)
  dir_g <- file.path(dirname(DIR_DATOS), "salidas", "graficos")
  skip_if_not(dir.exists(dir_g) && length(list.files(dir_g, pattern = "\\.png$")) > 0, "sin ejecución de main.R")
  pngs <- sub("\\.png$", "", list.files(dir_g, pattern = "\\.png$"))
  expect_true(all(pngs %in% mg$grafico), info = paste(setdiff(pngs, mg$grafico), collapse = ", "))   # todo gráfico tiene metadatos
  skip_if_not(all(mg$grafico %in% pngs), "salidas/graficos de una ejecución anterior a este código")
  expect_setequal(pngs, mg$grafico)
})

test_that("las comprobaciones numéricas del modelo se cumplen", {
  par <- readr::read_csv(file.path(DIR_DATOS, "parametros_modelo.csv"), show_col_types = FALSE)
  va <- comprobaciones_modelo(par)
  expect_true(all(va$cumple), info = paste(va$comprobacion[!va$cumple], collapse = "; "))
})

test_that("la tabla de validación tiene cinco indicadores por sentido y agrupa las dos filas de la descarga", {
  f <- file.path(dirname(DIR_DATOS), "salidas", "tablas", "validacion_modelo.csv")
  skip_if_not(file.exists(f), "sin ejecución de main.R")
  v <- readr::read_csv(f, show_col_types = FALSE)
  skip_if_not("fenomeno" %in% names(v), "salidas de una ejecución anterior a este código")
  expect_equal(nrow(v), 10L)
  expect_true(all(table(v$caso) == 5L))
  desc <- v |> dplyr::filter(grepl("^Caudal", indicador))
  expect_true(all(table(desc$caso) == 2L))
  expect_true(all(desc$fenomeno == "descarga con cola"))
  expect_equal(nrow(dplyr::distinct(v, caso, fenomeno)), 8L)                         # 4 fenómenos por sentido
})

test_that("los recursos de 2025 coinciden con los del catálogo nacional (datos.gob.es)", {
  x <- contraste_publicacion_original()
  expect_equal(nrow(x), 13L)
  expect_true(all(x$resultado == "coincide"))
  expect_true(all(abs(x$diferencia_modificacion_h) < 2))                            # misma fecha; desfase horario
})

test_that("las métricas por alternativa dan percentiles de la demora distintos de la mediana", {
  set.seed(8)
  res <- tibble::tibble(sim = rep(1:200, 2), escenario = rep(c("base", "tercer_carril_corto"), each = 200),
                        demora_vh = c(runif(200, 500, 1500), runif(200, 100, 800)), demora_media_punta = runif(400, 1, 10),
                        espera_max = runif(400, 5, 30), horas_con_cola = runif(400, 1, 4), horas_aforo = sample(1:4, 400, TRUE),
                        cola_max = runif(400, 100, 900))
  m <- metricas_alternativas(list(resultados = res), "prueba")
  b <- m[m$escenario == "base", ]
  expect_lt(b$demora_vh_p10, b$demora_vh); expect_gt(b$demora_vh_p90, b$demora_vh)
  expect_equal(b$demora_vh_p10, unname(stats::quantile(res$demora_vh[1:200], 0.1)))
})
