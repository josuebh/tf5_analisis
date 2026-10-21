# Pruebas del modelo de cola (04_modelo_cuello_botella.R)

test_that("el perfil sintético conserva la IMD y respeta la cuota de la hora punta", {
  for (k in c(0.075, 0.10, 0.13)) for (s in c(40, 75, 120)) for (cn in c(0.05, 0.12)) {
    pr <- perfil_demanda(45000, k, s, cn, t0 = 450)
    lam <- pr$base + pr$joroba
    expect_equal(sum(lam), 45000, tolerance = 1e-9)
    hp <- abs(pr$t - 450 + 0.5) <= 30
    expect_equal(sum(lam[hp]) / 45000, k, tolerance = 1e-9)
    expect_true(all(lam >= 0))
  }
})

test_that("el perfil observado reparte cada hora y conserva el total", {
  vh <- c(rep(200, 6), 3000, 3500, 3200, rep(2500, 8), rep(1500, 4), 800, 500, 300)
  pr <- perfil_observado(vh, V_dir = 50000)
  expect_equal(sum(pr$base + pr$joroba), 50000, tolerance = 1e-9)
  expect_true(all(pr$joroba >= 0))
})

# Cola de referencia: bucle minuto a minuto (descarga mu sin cola y mu·(1 - caída) con cola)
cola_por_bucle <- function(lambda, cap_hora, caida = 0) {
  mu <- cap_hora / 60; Q <- numeric(length(lambda)); q <- 0
  for (i in seq_along(lambda)) {
    m <- if (q > 1e-9) mu * (1 - caida) else mu
    disp <- q + lambda[i]; q <- disp - min(disp, m); Q[i] <- q
  }
  Q
}

test_that("la cola vectorizada coincide con un bucle minuto a minuto de referencia", {
  set.seed(3)
  for (r in 1:20) {
    lam <- pmax(0, 50 + 20 * sin(seq(0, 6, length.out = 1440)) + rnorm(1440, 0, 8))
    cap <- runif(1, 2800, 4200); cd <- runif(1, 0, 0.2)
    expect_equal(simular_cola(lam, cap, cd)$Q, cola_por_bucle(lam, cap, cd), tolerance = 1e-8)
  }
})

test_that("una capacidad constante en vector da lo mismo que un número", {
  pr <- perfil_demanda(48000, 0.09, 60, 0.08)
  lam <- pr$base + pr$joroba
  expect_equal(simular_cola(lam, rep(3800, 1440), 0.1)$Q, simular_cola(lam, 3800, 0.1)$Q)
})

test_that("la espera FIFO por cohortes reproduce el caso analítico de sobredemanda constante", {
  # llegadas a 2*mu durante 60 min: quien llega en t espera t*(lambda/mu - 1) = t min
  mu <- 50; lam <- c(rep(2 * mu, 60), rep(0, 200))
  w <- simular_cola(lam, mu * 60, 0)$w
  t_mid <- (1:60) - 0.5
  expect_equal(w[1:60], t_mid, tolerance = 1e-6)
})

test_that("la demora total es el área bajo la cola (identidad de Little)", {
  pr <- perfil_demanda(46000, 0.095, 55, 0.08)
  lam <- pr$base + pr$joroba
  s <- simular_cola(lam, 3700, 0.1)
  area <- sum((c(0, s$Q[-length(s$Q)]) + s$Q) / 2)
  expect_equal(sum(lam * s$w), area, tolerance = 1e-6 * area)
  expect_lt(s$Q[length(s$Q)], 1e-6)                      # la cola se disipa en el día
})

test_that("escalonar desplaza vehículos sin perder ninguno", {
  pr <- perfil_demanda(48000, 0.13, 120, 0.05, t0 = 100)   # punta pegada al borde del día
  for (p in c(0.03, 0.08, 0.15)) expect_equal(sum(escalonar(pr$joroba, p)), sum(pr$joroba), tolerance = 1e-9)
})

test_that("más capacidad nunca aumenta la demora y sin sobredemanda no hay cola", {
  pr <- perfil_demanda(48000, 0.09, 60, 0.08)
  lam <- pr$base + pr$joroba
  d <- vapply(c(3400, 3600, 3800, 4000, 4400), function(cp) evaluar(pr, cp, 0.1)$demora_vh, numeric(1))
  expect_true(all(diff(d) <= 1e-9))
  expect_equal(evaluar(pr, max(lam) * 60 * 1.01, 0.1)$demora_vh, 0)
})

test_that("el umbral del Bus-VAO es 1/carriles (invariancia de escala)", {
  par <- readr::read_csv(file.path(DIR_DATOS, "parametros_modelo.csv"), show_col_types = FALSE)
  p <- setNames(as.list(par$central), par$parametro)
  for (L in 2:4) expect_equal(trasvase_bus_vao(p, 30000 * L, L, 0), 1 / L, tolerance = 0.01)
})

test_that("la holgura nula anula el efecto del tercer carril y la grande lo maximiza", {
  par <- readr::read_csv(file.path(DIR_DATOS, "parametros_modelo.csv"), show_col_types = FALSE)
  p <- setNames(as.list(par$central), par$parametro)
  r <- tercer_carril_por_holgura(p, 48000, 2, c(0, 0.5))
  expect_equal(r$reduccion[r$holgura == 0], c(0, 0), tolerance = 1e-9)
  expect_true(all(r$reduccion[r$holgura == 0.5] > 0.5))
})

test_that("sin holgura aguas abajo, ni el tercer carril ni la regulación de accesos reducen la demora", {
  par <- readr::read_csv(file.path(DIR_DATOS, "parametros_modelo.csv"), show_col_types = FALSE)
  p <- setNames(as.list(par$central), par$parametro)
  pr <- perfil_demanda(48000, 0.10, 60, 0.08)
  r <- escenarios_cuello(p, 48000, 2, TRUE, prof = pr, holgura_t = rep(0, 1440))
  b <- r$base$demora_vh
  expect_gt(b, 0)
  for (e in c("tercer_carril_corto", "ramp_metering_corto", "ramp_metering_largo"))
    expect_equal(r[[e]]$demora_vh, b, tolerance = 1e-6 * b)
  expect_lt(r$tarificacion$demora_vh, b)                 # reducir la demanda sí funciona
  expect_equal(simular_cola(pr$base + pr$joroba, 3800, rep(0.1, 1440))$Q, simular_cola(pr$base + pr$joroba, 3800, 0.1)$Q)
})
