# Pruebas de escenarios y previsión: perfil híbrido, horizontes, supresión de demanda,
# incidentes, horario de la cola, cambio de hora, diferencias en diferencias,
# holgura con crecimiento y tabla de confianza

perfil_prueba <- function() c(240, 120, 80, 110, 300, 1490, 3490, 3280, 3020, 3110, 3010, 3000, 2810, 2920,
                              3160, 3090, 3110, 2910, 2630, 2270, 1860, 1310, 950, 580)

test_that("el perfil híbrido conserva los vehículos y respeta los aforos fuera de la ventana", {
  vh <- perfil_prueba()
  for (t0 in c(360, 420, 500)) for (s in c(20, 60, 120)) {
    pr <- perfil_hibrido(vh, c(6, 10), t0, s)
    lam <- pr$base + pr$joroba
    expect_equal(sum(lam), sum(vh), tolerance = 1e-9)
    fuera <- !(pr$t >= 360 & pr$t < 600)
    expect_equal(lam[fuera], rep(vh / 60, each = 60)[fuera], tolerance = 1e-12)
    expect_true(all(pr$joroba[fuera] == 0))
    expect_true(all(pr$joroba >= 0) && all(pr$base >= 0))
    expect_equal(sum(lam[!fuera]), sum(vh[7:10]), tolerance = 1e-9)   # horas 6 a 9
  }
  # con crecimiento de la demanda se escala todo el perfil
  pr2 <- perfil_hibrido(vh, c(6, 10), 420, 50, V_dir = 1.1 * sum(vh))
  expect_equal(sum(pr2$base + pr2$joroba), 1.1 * sum(vh), tolerance = 1e-9)
  expect_equal(pr2$vehiculos_joroba, 1.1 * perfil_hibrido(vh, c(6, 10), 420, 50)$vehiculos_joroba, tolerance = 1e-9)
})

test_that("la ventana de la punta va de la primera hora congestionada a una hora después de la última", {
  pc <- c(rep(0, 6), 0.92, 0.91, 0.6, 0.2, rep(0, 14))
  expect_equal(ventana_punta(pc), c(6, 10))
})

test_that("la elasticidad a 5 años queda entre la del primer año y la de 10 años", {
  for (rho in c(0.708, 0.75, 0.795)) {
    e5 <- eta_medio(-0.3, -0.7, rho)
    expect_true(e5 < -0.3 && e5 > -0.7)
  }
  expect_equal(eta_medio(-0.3, -0.7, 0.75), -0.3 + (-0.4) * (1 - 0.75^4) / (1 - 0.75^9))
})

test_that("con más demanda y la misma capacidad, la supresión reduce la joroba y nunca la aumenta", {
  vh <- perfil_prueba()
  pr <- perfil_hibrido(vh, c(6, 10), 400, 45)
  d_ref <- evaluar(pr, 3900, 0.1)$demora_media_joroba
  pr_f <- perfil_hibrido(vh, c(6, 10), 400, 45, V_dir = 1.1 * sum(vh))
  s <- equilibrio_inducido(pr_f, 3900, 0.1, -0.7, 25, d_ref, permitir_supresion = TRUE)
  expect_lt(s, 1)
  expect_gt(s, 0)
  expect_equal(equilibrio_inducido(pr_f, 3900, 0.1, -0.7, 25, d_ref), 1)          # sin supresión: comportamiento anterior
  expect_gte(equilibrio_inducido(pr, 4400, 0.1, -0.7, 25, d_ref, permitir_supresion = TRUE), 1)   # mejora: demanda inducida
})

test_that("un incidente solo reduce la capacidad durante el corte y aumenta la demora", {
  f <- factor_incidente(c(400, 430), 2)
  expect_equal(sum(f < 1), 30)
  expect_equal(unique(f[401:430]), 0.5)
  par <- readr::read_csv(file.path(DIR_DATOS, "parametros_modelo.csv"), show_col_types = FALSE)
  p <- setNames(as.list(par$central), par$parametro)
  pr <- perfil_hibrido(perfil_prueba(), c(6, 10), 400, 45)
  e0 <- escenarios_cuello(p, sum(perfil_prueba()), 2, TRUE, prof = pr, holgura_t = rep(0.1, 1440))
  e1 <- escenarios_cuello(p, sum(perfil_prueba()), 2, TRUE, prof = pr, holgura_t = rep(0.1, 1440), incidente = c(385, 415))
  expect_gt(e1$base$demora_vh, e0$base$demora_vh)
  expect_true(all(c("tercer_carril_corto", "tercer_carril_medio", "tercer_carril_largo") %in% names(e0)))
})

test_that("las alternativas de los tres horizontes van de menos a más demanda inducida", {
  par <- readr::read_csv(file.path(DIR_DATOS, "parametros_modelo.csv"), show_col_types = FALSE)
  p <- completar_parametros(as_tibble(setNames(as.list(par$central), par$parametro)))
  p <- as.list(p)
  pr <- perfil_hibrido(perfil_prueba(), c(6, 10), 400, 45)
  e <- escenarios_cuello(p, sum(perfil_prueba()), 2, TRUE, prof = pr, holgura_t = rep(0.2, 1440))
  for (a in c("tercer_carril", "ramp_metering", "escalonamiento", "paquete_gestion")) {
    s <- vapply(HORIZONTES, function(h) e[[paste0(a, "_", h)]]$escala, numeric(1))
    expect_true(all(diff(s) >= -1e-6))
    v <- vapply(HORIZONTES, function(h) e[[paste0(a, "_", h)]]$demora_vh, numeric(1))
    expect_true(all(diff(v) >= -1e-6))
  }
})

test_that("el horario de la cola usa la primera y la última hora congestionada", {
  sc <- tidyr::crossing(dia = as.Date("2025-03-03") + 0:2, hora = 0:23) |>
    mutate(anio = 2025L, estacion_id = 103, sentido = "descendente", cuota_lenta = 0.1,
           congestionada = (dia == as.Date("2025-03-03") & hora %in% 6:8) | (dia == as.Date("2025-03-04") & hora %in% 7:9))
  hc <- horario_cola(sc, 103, "descendente", 2025, 3:12)
  expect_equal(hc$inicio, c(6, 7, NA))
  expect_equal(hc$fin, c(9, 10, NA))
  expect_equal(hc$horas_cola, c(3, 3, 0))
  o <- objetivo_horario(hc)
  expect_equal(o$inicio, c(6.25 - 0.5, 6.75 + 0.5))
})

test_that("se detectan los días con horas duplicadas o que faltan (cambio de hora)", {
  base <- tidyr::crossing(dia = as.Date(c("2025-03-29", "2025-03-30")), hora = 0:23) |>
    mutate(estacion_id = 103, carril_id = -1, anio = 2025L,
           fecha = sprintf("%s %02d:00:00", dia, hora))
  hp <- base |> filter(!(dia == as.Date("2025-03-30") & hora == 1))
  hp <- bind_rows(hp, hp |> filter(dia == as.Date("2025-03-30"), hora == 2))
  ch <- cambio_hora(hp)
  expect_equal(nrow(ch), 1)
  expect_equal(ch$horas_distintas, 23)
  expect_equal(ch$registros_duplicados, 1L)
  expect_equal(ch$cambio_de_hora, "marzo (+1 h)")
})

test_that("las diferencias en diferencias recuperan un efecto conocido", {
  set.seed(4)
  meses <- c(MESES_LECTIVOS_ULL$antes, MESES_LECTIVOS_ULL$despues, MESES_CONTROL_ULL$antes, MESES_CONTROL_ULL$despues)
  dias <- unlist(lapply(meses, function(m) as.character(seq(as.Date(paste0(m, "-01")), by = "day", length.out = 20))))
  sc <- tidyr::crossing(dia = as.Date(dias), hora = 0:23) |>
    mutate(mes = format(dia, "%Y-%m"), estacion_id = 93, sentido = "descendente", velocidad_fiable = TRUE, cuota_lenta = 0.1,
           lectivo = mes %in% c(MESES_LECTIVOS_ULL$antes, MESES_LECTIVOS_ULL$despues),
           despues = mes %in% c(MESES_LECTIVOS_ULL$despues, MESES_CONTROL_ULL$despues),
           veh = 1000 + 300 * despues - ifelse(lectivo & despues & hora %in% 7:8, 150, 0) + rnorm(n(), 0, 5),
           congestionada = FALSE)
  r <- did_ull(sc, NULL, estaciones = 93, n_boot = 200) |> filter(variable == "v")
  expect_equal(r$efecto_did, -300, tolerance = 0.03)     # 150 veh/h menos en cada una de las 2 horas
  expect_true(r$ic_inf < -300 && r$ic_sup > -300)
})

test_that("la holgura del tramo siguiente baja si crece la demanda", {
  hh <- tibble(hora = rep(6:8, each = 20), F_cuello = 3300, entradas_netas = runif(60, 200, 600), C_abajo = 4200) |>
    mutate(holgura = (C_abajo - entradas_netas) / F_cuello - 1)
  m1 <- matriz_holgura_crecimiento(hh, 1); m2 <- matriz_holgura_crecimiento(hh, 1.1)
  expect_equal(m1[7, ], matriz_holgura_horaria(hh)[7, ])
  expect_true(all(m2[7:9, ] <= m1[7:9, ] + 1e-12))
})

test_that("la confianza combina los cuatro criterios con la regla publicada", {
  crit <- tibble(alternativa = "tercer_carril", nombre = "x", caso = "c1", tramo = "t", horario = "h", estado = "e",
                 evidencia = "media", mecanismo = "alta", conducta = "media", motivo_evidencia = "a", motivo_mecanismo = "b",
                 motivo_conducta = "c")
  res <- tibble(escenario = c("tercer_carril_corto", "tercer_carril_medio", "tercer_carril_largo"), mediana = c(0.5, 0.45, 0.4),
                p10 = 0.2, p90 = 0.9)
  adv <- tibble(escenario = "tercer_carril_corto", supuesto = c("Referencia (calibrado)", "Sin holgura"), reduccion_mediana = c(0.5, 0.1))
  r <- tabla_confianza(crit, list(c1 = res), list(c1 = adv))
  expect_equal(r$robustez, "baja")                       # 0,1 / 0,5 = 0,2 < 0,4
  expect_equal(r$puntuacion, mean(c(2, 3, 2, 1)))
  expect_equal(r$confianza, "media")
})

test_that("las horas de cola se miden como en el aforo (>= 60 % de los vehículos de la hora con cola)", {
  s <- rep(50, 1440); Q <- rep(0, 1440)
  Q[(6 * 60 + 15):(8 * 60 + 40)] <- 100           # cola de 06:15 a 08:40
  a <- horas_como_aforo(s, Q)
  expect_equal(a$horas, 3)                          # 6 h (75 %), 7 h (100 %), 8 h (68 %)
  expect_equal(a$inicio, 6); expect_equal(a$fin, 9)
  Q2 <- rep(0, 1440); Q2[(6 * 60 + 30):(7 * 60 + 20)] <- 100   # 06:30-07:20: ninguna hora llega al 60 %
  expect_equal(horas_como_aforo(s, Q2)$horas, 0)
})

test_that("el tercer carril nunca empeora la situación y, sin límite aguas abajo, suma un carril", {
  p <- list(c_carril = 1950, caida_capacidad = 0.1)
  sin_lim <- capacidad_tercer_carril(p, 2, 10)                # un valor por minuto del día
  expect_equal(unique(sin_lim$antes), 3 * 1950); expect_equal(unique(sin_lim$caida), 0.1)
  cero <- capacidad_tercer_carril(p, 2, 0)
  expect_equal(unique(cero$antes), 2 * 1950); expect_equal(unique(cero$con_cola), 2 * 1950 * 0.9)   # igual que hoy
  for (h in c(0.02, 0.05, 0.13, 0.3)) {
    x <- capacidad_tercer_carril(p, 2, h)
    expect_true(all(x$antes >= 2 * 1950) && all(x$con_cola >= 2 * 1950 * 0.9))
    expect_true(all(x$con_cola <= 2 * 1950 * 0.9 * (1 + h) + 1e-9))               # lo que admite el tramo siguiente
  }
})
