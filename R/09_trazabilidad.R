# =============================================================================
# 09_trazabilidad.R · Reproducibilidad: salidas limpias, huellas y sesión
# -----------------------------------------------------------------------------
# · limpiar_salidas(): borra gráficos y tablas de ejecuciones anteriores para
#   que no se mezclen con las nuevas.
# · manifiesto(): huella SHA-256 (o MD5 si falta el paquete digest), tamaño y
#   fecha de cada fichero de código, datos y salida (carpetas o ficheros sueltos).
#   No incluye las referencias de no regresión (tests/referencia): se copian de
#   la propia ejecución entregada después de hacerla, así que no son una entrada.
# · registrar_sesion(): versión de R y de cada paquete usado.
# =============================================================================

limpiar_salidas <- function() {
  for (d in c(DIR_GRAFICOS, DIR_TABLAS, file.path("salidas", "panel"))) {
    unlink(list.files(d, full.names = TRUE))
    dir.create(d, recursive = TRUE, showWarnings = FALSE)
  }
  invisible(TRUE)
}

huella <- function(f) {
  if (requireNamespace("digest", quietly = TRUE)) digest::digest(file = f, algo = "sha256")
  else unname(tools::md5sum(f))
}

manifiesto <- function(dirs = c("datos", "salidas")) {
  fs <- unlist(lapply(dirs, function(d) if (dir.exists(d)) list.files(d, recursive = TRUE, full.names = TRUE) else if (file.exists(d)) d))
  fs <- fs[!grepl("manifiesto_ejecucion", fs) & !startsWith(fs, file.path("tests", "referencia"))]
  info <- file.info(fs)
  tibble(fichero = fs, bytes = info$size,
         modificado = format(info$mtime, "%Y-%m-%d %H:%M:%S"),
         algoritmo = if (requireNamespace("digest", quietly = TRUE)) "sha256" else "md5",
         huella = vapply(fs, huella, character(1)))
}

registrar_sesion <- function(ruta = file.path("salidas", "registro_sesion.txt"), inicio = NULL) {
  paquetes <- c("dplyr", "tidyr", "readr", "ggplot2", "scales", "ggrepel", "patchwork", "jsonlite", "digest", "testthat", "ragg", "systemfonts", "textshaping")
  vers <- vapply(paquetes, function(p) if (requireNamespace(p, quietly = TRUE)) as.character(utils::packageVersion(p)) else "no instalado",
                 character(1))
  txt <- c(paste("Ejecución:", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
           if (!is.null(inicio)) paste("Duración:", round(as.numeric(difftime(Sys.time(), inicio, units = "mins")), 1), "min"),
           paste("R:", R.version.string),
           paste("Sistema:", Sys.info()[["sysname"]], Sys.info()[["release"]]),
           "", "Paquetes:", paste0("  ", names(vers), " ", vers), "",
           "sessionInfo():", utils::capture.output(utils::sessionInfo()))
  writeLines(txt, ruta, useBytes = TRUE)
  invisible(ruta)
}
