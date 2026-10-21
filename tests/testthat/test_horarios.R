# Lectura, validación y detección de colas con un fichero sintético en el
# formato oficial (no se usa para ningún resultado)

fichero_sintetico <- function() {
  dias <- seq(as.Date("2025-10-06"), as.Date("2025-10-10"), by = "day")     # lunes a viernes
  g <- expand.grid(hora = 0:23, dia = dias, carril_id = c(-2, -1, 1, 2))
  g$fecha <- sprintf("%s %02d:00:00", format(g$dia), g$hora)
  g$ligeros <- ifelse(g$hora %in% 6:20, 1500, 100); g$pesados <- 20
  tot <- g$ligeros + g$pesados
  lento <- ifelse(g$carril_id < 0 & g$hora %in% 7:8, 0.9, 0.05)            # cola de 7 a 9 h hacia Santa Cruz
  g$rango1_vehiculos <- round(tot * lento); g$rango2_vehiculos <- tot - g$rango1_vehiculos
  g$rango3_vehiculos <- 0; g$rango4_vehiculos <- 0; g$rango5_vehiculos <- 0; g$rango6_vehiculos <- 0
  g$estacion_id <- 103
  x <- g[, c("estacion_id", "carril_id", "fecha", "ligeros", "pesados", paste0("rango", 1:6, "_vehiculos"))]
  x <- rbind(x, x[1, ])                                                     # un duplicado
  x$rango3_vehiculos[5] <- -3                                               # un rango negativo
  x
}

test_that("el extractor lee un TXT oficial de 13 columnas con BOM", {
  x <- fichero_sintetico()[1:30, ]
  txt <- data.frame(estacion_id = x$estacion_id, estacion_nombre = "ERMITA CRUZ CHICA", carril_id = x$carril_id,
                    carril_descripcion = "Los Rodeos D. Lento", x[, -(1:2)])
  f <- tempfile(fileext = ".txt")
  con <- file(f, "wb"); writeBin(as.raw(c(0xEF, 0xBB, 0xBF)), con); close(con)
  suppressWarnings(utils::write.table(txt, f, sep = ",", row.names = FALSE, quote = FALSE, append = TRUE))
  y <- extraer_tf5_de_original(f)
  expect_equal(nrow(y), 30)
  expect_equal(names(y), COLS_HORARIO)
})

test_that("la validación horaria detecta duplicados, rangos negativos y detecta la cola inyectada", {
  car <- leer_carriles_json()
  cs <- carriles_por_sentido(car)
  hp <- preparar_horarios(fichero_sintetico(), car, tibble(fecha = as.Date(character())))
  v <- validar_horarios(hp, cs)
  expect_true(any(grepl("^H4", v$regla)))
  expect_true(any(grepl("^H6", v$regla)))
  sd <- agregar_por_sentido(hp |> distinct(estacion_id, carril_id, fecha, .keep_all = TRUE), cs, estaciones = 103)
  dv <- dias_validos(sd, excluir_agosto = TRUE)
  expect_equal(nrow(dv), 10)                                               # 5 días x 2 sentidos
  b <- base_nocturna(sd, dv)
  sc <- marcar_congestion(sd, dv, b)
  cong <- sc |> filter(congestionada) |> distinct(sentido, hora)
  expect_equal(sort(unique(cong$hora)), c(7L, 8L))
  expect_true(all(cong$sentido == "descendente"))
  rc <- resumen_congestion(sc |> mutate(anio = 2025L), 2025)
  expect_equal(rc$horas_mediana[rc$sentido == "descendente"], 2)
})

test_that("la comparación entre periodos detecta un carril que cuenta mal solo en las horas comparadas", {
  car <- leer_carriles_json(); cs <- carriles_por_sentido(car)
  x <- fichero_sintetico() |> distinct(estacion_id, carril_id, fecha, .keep_all = TRUE)
  x$rango3_vehiculos <- pmax(x$rango3_vehiculos, 0)
  k <- as.integer(substr(x$fecha, 9, 10)) - 8                                # variación entre días (para el test t)
  x$ligeros <- round(x$ligeros * (1 + 0.02 * k)); x$pesados <- round(x$pesados * (1 + 0.02 * k))
  recalcular <- function(z) {
    tot <- z$ligeros + z$pesados
    z$rango1_vehiculos <- round(tot * ifelse(z$carril_id < 0 & as.integer(substr(z$fecha, 12, 13)) %in% 7:8, 0.9, 0.05))
    z$rango2_vehiculos <- tot - z$rango1_vehiculos; z
  }
  a <- recalcular(x)                                                          # oct 2024: mismo tráfico
  a$fecha <- sprintf("2024-10-%02d%s", as.integer(substr(a$fecha, 9, 10)) + 1, substr(a$fecha, 11, 19))
  b <- x; h <- as.integer(substr(b$fecha, 12, 13))                            # oct 2025: el carril -1 «roba» las 7-9 h
  b$ligeros <- with(b, ifelse(carril_id == -1 & h %in% 7:8, ligeros * 1.6,
                       ifelse(carril_id == -2 & h %in% 7:8, ligeros * 0.4,
                       ifelse(carril_id == -1 & h %in% 10:11, ligeros * 0.4,
                       ifelse(carril_id == -2 & h %in% 10:11, ligeros * 1.6, ligeros)))))
  b <- recalcular(b)
  hp <- preparar_horarios(rbind(a, b), car, tibble(fecha = as.Date(character())))
  sd <- agregar_por_sentido(hp, cs, estaciones = 103)
  dv <- dias_validos(sd)
  sc <- marcar_congestion(sd, dv, base_nocturna(sd, dv))
  cmp <- comparar_periodos(sc, "2024-10", "2025-10", horas = 7:8, estaciones = 103, hp = hp, min_dias = 3)
  expect_equal(nrow(cmp), 2)
  expect_true(all(abs(cmp$dif) < 1))                                          # el total por sentido no cambia
  expect_true(all(cmp$cambio_reparto_dia < 0.005))                            # ni el reparto del día completo
  expect_gt(cmp$cambio_reparto_horas[cmp$sentido == "descendente"], 0.25)     # pero sí el de 7 a 9 h
  expect_false(cmp$comparable[cmp$sentido == "descendente"])
  expect_true(cmp$comparable[cmp$sentido == "ascendente"])
})

test_that("la regla H9 señala un carril con perfil horario anómalo", {
  car <- leer_carriles_json(); cs <- carriles_por_sentido(car)
  x <- fichero_sintetico() |> distinct(estacion_id, carril_id, fecha, .keep_all = TRUE)
  x$rango3_vehiculos <- pmax(x$rango3_vehiculos, 0)
  meses <- lapply(0:3, function(m) { z <- x; z$fecha <- sprintf("2025-%02d%s", 3 + m, substr(z$fecha, 8, 19)); z })
  h <- as.integer(substr(meses[[4]]$fecha, 12, 13))                              # en el 4.º mes el carril 1 cuenta mal:
  malo <- meses[[4]]$carril_id == 1
  meses[[4]]$ligeros[malo] <- ifelse(h[malo] %in% 7:12, 3000, ifelse(h[malo] %in% 13:20, 200, meses[[4]]$ligeros[malo]))
  hp <- preparar_horarios(bind_rows(meses), car, tibble(fecha = as.Date(character())))
  v <- validar_horarios(hp, cs) |> filter(grepl("^H9", regla))
  expect_equal(nrow(v), 1)
  expect_equal(v$mes, "2025-06")
  expect_match(v$detalle, "carril 1:")
})

test_that("la sensibilidad al umbral de congestión responde al umbral", {
  car <- leer_carriles_json(); cs <- carriles_por_sentido(car)
  hp <- preparar_horarios(fichero_sintetico() |> distinct(estacion_id, carril_id, fecha, .keep_all = TRUE), car,
                          tibble(fecha = as.Date(character())))
  sd <- agregar_por_sentido(hp, cs, estaciones = 103)
  dv <- dias_validos(sd)
  su <- sensibilidad_umbrales(sd, dv, base_nocturna(sd, dv), 2025, tibble(umbral = c(0.5, 0.95), exceso = c(0.2, 0.9)))
  expect_equal(nrow(su), 4)                                                   # 2 umbrales x 2 sentidos
  d <- su |> filter(sentido == "descendente") |> arrange(umbral)
  expect_equal(d$horas_mediana, c(2, 0))                                      # la cola inyectada (90 % lentos) no supera el 95 %
  expect_true(all(su$velocidad_utilizable))                                   # sin tabla de fiabilidad, todo cuenta
  # Con la velocidad declarada no utilizable en un sentido, ningún umbral le cuenta horas (misma máscara que el análisis)
  fiab <- tibble(estacion_id = 103, sentido = c("ascendente", "descendente"), velocidad_fiable = c(TRUE, FALSE))
  su2 <- sensibilidad_umbrales(sd, dv, base_nocturna(sd, dv), 2025, tibble(umbral = c(0.5, 0.95), exceso = c(0.2, 0.9)), fiab = fiab)
  d2 <- su2 |> filter(sentido == "descendente")
  expect_true(all(d2$horas_mediana == 0) && all(!d2$velocidad_utilizable))
  expect_true(all(su2$velocidad_utilizable[su2$sentido == "ascendente"]))
})

test_that("la regla H2 señala un mes sin ningún registro en un sentido", {
  car <- leer_carriles_json(); cs <- carriles_por_sentido(car)
  x <- fichero_sintetico() |> distinct(estacion_id, carril_id, fecha, .keep_all = TRUE)
  x$rango3_vehiculos <- pmax(x$rango3_vehiculos, 0)
  meses <- lapply(0:2, function(m) { z <- x; z$fecha <- sprintf("2025-%02d%s", 3 + m, substr(z$fecha, 8, 19)); z })
  meses[[2]] <- meses[[2]][meses[[2]]$carril_id > 0, ]                     # abril: sin datos hacia Santa Cruz
  hp <- preparar_horarios(bind_rows(meses), car, tibble(fecha = as.Date(character())))
  v <- validar_horarios(hp, cs) |> filter(grepl("^H2", regla), mes == "2025-04", sentido == "descendente")
  expect_equal(nrow(v), 1)
  expect_equal(v$filas, 30L * 24L)
})
