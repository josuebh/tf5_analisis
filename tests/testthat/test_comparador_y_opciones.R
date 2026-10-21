test_that("las opciones de simulación se validan sin admitir NA, ceros ni decimales", {
  clave <- "TF5_PRUEBA_ENTERO"
  anterior <- Sys.getenv(clave, unset = NA_character_)
  on.exit(if (is.na(anterior)) Sys.unsetenv(clave) else Sys.setenv(TF5_PRUEBA_ENTERO = anterior))
  Sys.unsetenv(clave)
  expect_identical(entero_positivo_entorno(clave, 10L), 10L)
  for (x in c("0", "-1", "2.5", "abc", "NA", "Inf", "2147483648")) {
    Sys.setenv(TF5_PRUEBA_ENTERO = x)
    expect_error(entero_positivo_entorno(clave, 10L), "entero positivo")
  }
  Sys.setenv(TF5_PRUEBA_ENTERO = "2000")
  expect_identical(entero_positivo_entorno(clave, 10L), 2000L)
})

test_that("el comparador rechaza datos perdidos, infinitos y columnas reordenadas", {
  raiz <- dirname(DIR_DATOS)
  script <- file.path(raiz, "tests", "comparar_ejecuciones.R")
  rscript <- file.path(R.home("bin"), "Rscript")
  temporal <- tempfile("comparacion_"); dir.create(temporal)
  on.exit(unlink(temporal, recursive = TRUE))
  a <- file.path(temporal, "a"); b <- file.path(temporal, "b")
  dir.create(a); dir.create(b)
  x <- data.frame(id = 1:3, valor = c(1, 2, 3))
  readr::write_csv(x, file.path(a, "valores.csv"))
  variantes <- list(transform(x, valor = c(1, NA, 3)), transform(x, valor = c(1, Inf, 3)), x[, c("valor", "id")])
  for (y in variantes) {
    readr::write_csv(y, file.path(b, "valores.csv"))
    inf <- file.path(temporal, "informe.csv")
    estado <- system2(rscript, c("--vanilla", shQuote(script), shQuote(a), shQuote(b), shQuote(inf)), stdout = FALSE, stderr = FALSE)
    expect_identical(estado, 1L)
    informe <- readr::read_csv(inf, show_col_types = FALSE)
    expect_false(informe$dentro_de_tolerancia[1])
  }
  readr::write_csv(x, file.path(b, "valores.csv"))
  for (tol in c("-1", "NA", "Inf", "texto")) {
    estado <- system2(rscript, c("--vanilla", shQuote(script), shQuote(a), shQuote(b), shQuote(file.path(temporal, "informe.csv")), tol), stdout = FALSE, stderr = FALSE)
    expect_identical(estado, 1L)
  }
  readr::write_csv(data.frame(adicional = 1), file.path(b, "otra.csv"))
  estado <- system2(rscript, c("--vanilla", shQuote(script), shQuote(a), shQuote(b), shQuote(file.path(temporal, "informe.csv")), "--solo-referencia"), stdout = FALSE, stderr = FALSE)
  expect_identical(estado, 0L)
  informe <- readr::read_csv(file.path(temporal, "informe.csv"), show_col_types = FALSE)
  expect_true(all(informe$dentro_de_tolerancia))
})

test_that("el comparador trata igual los infinitos y los datos perdidos coincidentes y no oculta ficheros propios ausentes", {
  raiz <- dirname(DIR_DATOS)
  script <- file.path(raiz, "tests", "comparar_ejecuciones.R")
  rscript <- file.path(R.home("bin"), "Rscript")
  temporal <- tempfile("comparacion_"); dir.create(temporal)
  on.exit(unlink(temporal, recursive = TRUE))
  a <- file.path(temporal, "a"); b <- file.path(temporal, "b")
  dir.create(a); dir.create(b)
  inf <- file.path(temporal, "informe.csv")
  comparar <- function(...) system2(rscript, c("--vanilla", shQuote(script), shQuote(a), shQuote(b), shQuote(inf), ...), stdout = FALSE, stderr = FALSE)
  # Inf frente a Inf y NA frente a NA son iguales; -Inf frente a Inf, no
  x <- data.frame(id = 1:3, valor = c(1, Inf, NA))
  readr::write_csv(x, file.path(a, "valores.csv"))
  readr::write_csv(transform(x, id = as.numeric(id)), file.path(b, "valores.csv"))   # mismas cifras, otro formato
  expect_identical(comparar(), 0L)
  informe <- readr::read_csv(inf, show_col_types = FALSE)
  expect_true(all(informe$dentro_de_tolerancia))
  readr::write_csv(transform(x, valor = c(1, -Inf, NA)), file.path(b, "valores.csv"))
  expect_identical(comparar(), 1L)
  # Con --solo-referencia, una tabla de referencia que falte en la salida nueva es un fallo
  readr::write_csv(x, file.path(b, "valores.csv"))
  readr::write_csv(x, file.path(a, "otra.csv"))
  expect_identical(comparar("--solo-referencia"), 1L)
  informe <- readr::read_csv(inf, show_col_types = FALSE)
  expect_identical(informe$estado[informe$fichero == "otra.csv"], "retirada")
  unlink(file.path(a, "otra.csv"))
  # La configuración de la referencia no se compara con --solo-referencia; sin la opción, su ausencia se informa
  readr::write_csv(data.frame(clave = "N", valor = "1"), file.path(a, "configuracion_ejecucion.csv"))
  expect_identical(comparar("--solo-referencia"), 0L)
  informe <- readr::read_csv(inf, show_col_types = FALSE)
  expect_identical(informe$estado[informe$fichero == "configuracion_ejecucion.csv"], "propio de la ejecución (no se compara)")
  expect_identical(comparar(), 1L)
  informe <- readr::read_csv(inf, show_col_types = FALSE)
  expect_identical(informe$estado[informe$fichero == "configuracion_ejecucion.csv"], "retirada")
  expect_false(informe$dentro_de_tolerancia[informe$fichero == "configuracion_ejecucion.csv"])
  # Un manifiesto que falte en una carpeta se informa también con --solo-referencia
  unlink(file.path(a, "configuracion_ejecucion.csv"))
  readr::write_csv(data.frame(fichero = "x", huella = "y"), file.path(a, "manifiesto_ejecucion.csv"))
  expect_identical(comparar("--solo-referencia"), 1L)
  informe <- readr::read_csv(inf, show_col_types = FALSE)
  expect_identical(informe$estado[informe$fichero == "manifiesto_ejecucion.csv"], "retirada")
})

test_that("cada componente de las previsiones condicionadas lleva su condición de validez", {
  ruta_prev <- file.path(dirname(DIR_DATOS), "salidas", "tablas", "previsiones_condicionadas.csv")
  skip_if_not(file.exists(ruta_prev) && file.exists(file.path(dirname(DIR_DATOS), "salidas", "panel", "previsiones.csv")),
              "sin ejecución completa (faltan las previsiones en salidas/)")
  prev <- readr::read_csv(ruta_prev, show_col_types = FALSE)
  esperado <- c("Crecimiento exógeno" = "^Misma red", "Cambio de red" = "^Obra ", "Gestión de la demanda" = "^Medida implantada",
                "Transporte público" = "^Hace falta oferta", "Demanda inducida" = "^Elasticidades de la literatura")
  for (comp in names(esperado)) {
    filas <- prev[startsWith(prev$componente, comp), ]
    expect_gt(nrow(filas), 0)
    expect_true(all(grepl(esperado[[comp]], filas$condicion)), info = comp)
  }
  obra <- prev[startsWith(prev$componente, "Cambio de red"), ]
  # Solo hacia Santa Cruz hay contrato; hacia el Norte el tercer carril es hipotético
  expect_true(all(grepl("contrato formalizado", obra$condicion[obra$caso == "manana_hacia_santa_cruz"])))
  expect_true(all(grepl("^Obra hipotética", obra$condicion[obra$caso == "tarde_hacia_el_norte"])))
  expect_false(any(grepl("contrato", obra$condicion[obra$caso == "tarde_hacia_el_norte"])))
  panel <- readr::read_csv(file.path(dirname(DIR_DATOS), "salidas", "panel", "previsiones.csv"), show_col_types = FALSE)
  expect_identical(panel$condicion, prev$condicion)
})
