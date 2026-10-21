# Integridad de los datos oficiales incluidos en datos/

test_that("el catálogo de carriles es el fichero oficial y se lee bien", {
  ruta <- file.path(DIR_DATOS, "oficial", "rango-de-velocidades-de-los-carriles.json")
  skip_if_not_installed("digest")
  expect_equal(digest::digest(file = ruta, algo = "sha256"),
               "f1561fe4a42999dd5db4ff53390220aaa009b3202cb50de1ae9c1f9513620d6e")
  car <- leer_carriles_json(ruta)
  expect_equal(n_distinct(car$estacion_id), 42)
  expect_equal(nrow(car), 179)
  cs <- carriles_por_sentido(car)
  expect_equal(cs$carriles_principales[cs$estacion_id == 103], c(2, 2))
  expect_equal(car$tipo[car$estacion_id == 82 & car$carril_id < 0], c("bus", "bus"))
  expect_equal(clasificar_carril(c("Tres de Mayo C. Salida", "Acceso de Añaza", "Carril Bus", "Anchieta D. Medio")),
               c("salida", "acceso", "bus", "principal"))
})

test_that("los carriles del CSV del proyecto coinciden con el catálogo oficial", {
  car <- leer_carriles_json()
  cc <- contrastar_carriles(carriles_por_sentido(car), readr::read_csv(file.path(DIR_DATOS, "carriles_tf5.csv"), show_col_types = FALSE))
  expect_true(all(cc$coincide[!is.na(cc$coincide)]))
  expect_equal(sum(!is.na(cc$coincide)), 14)
})

test_that("la copia de la IMD coincide valor a valor con las copias locales de los CSV oficiales", {
  comp <- suppressMessages(contrastar_con_fuente(cargar_imd(), leer_imd_oficial_local()))
  expect_gt(nrow(comp), 500)
  expect_equal(sum(!comp$coincide), 0)
})

test_that("cada extracto horario coincide con su huella y sus metadatos", {
  skip_if_not_installed("digest")
  metas <- list.files(file.path(DIR_DATOS, "horarios"), pattern = "^meta_.*\\.json$", full.names = TRUE)
  expect_gte(length(metas), 24)
  for (m in metas) {
    x <- jsonlite::fromJSON(m)
    gz <- file.path(DIR_DATOS, "horarios", x$fichero_local)
    expect_equal(digest::digest(file = gz, algo = "sha256"), x$sha256_gz_local)
    tmp <- tempfile(); con <- gzfile(gz, "rb"); raw <- readBin(con, "raw", 5e7); close(con)
    expect_equal(digest::digest(raw, algo = "sha256", serialize = FALSE), x$sha256_compact)
    expect_equal(x$duplicados <= 100, TRUE)
  }
})

test_that("el calendario de festivos es válido", {
  f <- readr::read_csv(file.path(DIR_DATOS, "festivos_canarias.csv"), show_col_types = FALSE)
  expect_true(all(!is.na(as.Date(f$fecha))))
  expect_true(all(format(f$fecha, "%Y") %in% c("2024", "2025", "2026")))
  expect_true(as.Date("2025-02-03") %in% f$fecha)                       # Candelaria 2025 (Tenerife)
})
