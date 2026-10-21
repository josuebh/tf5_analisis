# Ejecuta las pruebas automáticas del proyecto:   Rscript tests/ejecutar_pruebas.R
# (desde la carpeta del proyecto). Requiere el paquete testthat.
options(warn = 1)
invisible(Sys.setlocale("LC_CTYPE", "C.UTF-8"))
if (!requireNamespace("testthat", quietly = TRUE)) stop("Instala testthat: install.packages('testthat')")
if (!file.exists("main.R")) stop("Ejecuta las pruebas desde la carpeta del proyecto")
for (f in sort(list.files("R", pattern = "\\.R$", full.names = TRUE))) source(f, encoding = "UTF-8")
# testthat ejecuta cada fichero desde tests/testthat: rutas absolutas
DIR_DATOS <- normalizePath("datos")
DIR_TABLAS <- file.path(tempdir(), "tablas_prueba"); dir.create(DIR_TABLAS, showWarnings = FALSE)
DIR_GRAFICOS <- file.path(tempdir(), "graficos_prueba"); dir.create(DIR_GRAFICOS, showWarnings = FALSE)
res <- testthat::test_dir("tests/testthat", reporter = testthat::ProgressReporter$new(show_praise = FALSE),
                          stop_on_failure = FALSE, load_package = "none")
df <- as.data.frame(res)
cat(sprintf("\nPruebas: %d bloques, %d comprobaciones superadas, %d fallos, %d errores, %d avisos, %d omitidas.\n",
            nrow(df), sum(df$passed), sum(df$failed), sum(df$error), sum(df$warning), sum(df$skipped)))
dir.create("salidas", showWarnings = FALSE)
readr::write_csv(df[, c("file", "test", "nb", "passed", "failed", "skipped", "error", "warning")],
                 file.path("salidas", "resultado_pruebas.csv"))
if (sum(df$failed) > 0 || any(df$error)) quit(status = 1)
