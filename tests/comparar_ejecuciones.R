# Compara las salidas de dos ejecuciones (tablas CSV, también comprimidas .csv.gz, y gráficos PNG) y escribe un
# informe fichero a fichero: igual, cambia (con la mayor diferencia numérica), nueva o
# retirada. Sirve para comprobar lo que cambia entre dos ejecuciones sin editar nada a mano.
#
# Uso (desde la carpeta del proyecto):
#   Rscript tests/comparar_ejecuciones.R <salidas_de_referencia> <salidas_nuevas> <informe.csv> [tolerancia] [--solo-referencia]
# Ejemplo:
#   Rscript tests/comparar_ejecuciones.R ../otra_ejecucion/salidas salidas ../informe.csv
#   (el informe, fuera de la carpeta del proyecto: verificar_entrega.py exige que todo lo que haya dentro esté en el manifiesto)
# --solo-referencia: compara solo los ficheros de referencia; permite tablas adicionales en la nueva salida
#   (la configuración guardada con la referencia no se compara). Sin esa opción, un fichero propio de la
#   ejecución (configuración o manifiesto) que falte en una de las dos carpetas se informa como nueva o retirada.
# Termina con código 1 si hay diferencias fuera de tolerancia.
# Tolerancia: diferencia relativa máxima admitida en las cifras de las tablas (por defecto
# 1e-8, la misma de la prueba de no regresión). Una tabla está dentro de la tolerancia si
# tiene las mismas filas, columnas y textos y ninguna cifra cambia más que eso; un gráfico,
# si es igual byte a byte.
options(warn = 1)
invisible(Sys.setlocale("LC_CTYPE", "C.UTF-8"))
suppressPackageStartupMessages({ library(dplyr); library(readr) })
args <- commandArgs(trailingOnly = TRUE)
solo_referencia <- "--solo-referencia" %in% args
args <- args[args != "--solo-referencia"]
if (length(args) < 3) stop("Uso: Rscript tests/comparar_ejecuciones.R <referencia> <nuevas> <informe.csv> [tolerancia] [--solo-referencia]")
ref <- args[1]; nue <- args[2]; salida <- args[3]
tolerancia <- if (length(args) >= 4) as.numeric(args[4]) else 1e-8
if (length(tolerancia) != 1L || !is.finite(tolerancia) || tolerancia < 0)
  stop("La tolerancia debe ser un número finito mayor o igual que cero")
if (!dir.exists(ref) || !dir.exists(nue)) stop("Las dos carpetas de comparación deben existir")
huella <- function(f) if (requireNamespace("digest", quietly = TRUE)) digest::digest(file = f, algo = "sha256") else unname(tools::md5sum(f))

comparar_tabla <- function(fa, fb) {
  a <- suppressWarnings(read_csv(fa, show_col_types = FALSE, guess_max = 1e5))
  b <- suppressWarnings(read_csv(fb, show_col_types = FALSE, guess_max = 1e5))
  comunes <- intersect(names(a), names(b))
  nuevas <- setdiff(names(b), names(a)); quitadas <- setdiff(names(a), names(b))
  dif_max <- NA_real_; dif_rel <- NA_real_; texto_dif <- 0L; ausentes_dif <- 0L
  orden_igual <- identical(names(a), names(b))
  if (nrow(a) == nrow(b)) {
    num <- comunes[vapply(comunes, function(n) is.numeric(a[[n]]) && is.numeric(b[[n]]), logical(1))]
    # Un NA frente a una cifra es una diferencia: na.rm=TRUE la ocultaba.
    ausentes_dif <- sum(vapply(comunes, function(n) sum(xor(is.na(a[[n]]), is.na(b[[n]]))), integer(1)))
    diferencias <- function(n, relativa = FALSE) {
      x <- a[[n]]; y <- b[[n]]
      ok <- !is.na(x) & !is.na(y)
      x <- x[ok]; y <- y[ok]
      iguales_inf <- !is.finite(x) & !is.finite(y) & x == y
      if (any((!is.finite(x) | !is.finite(y)) & !iguales_inf)) return(Inf)
      finitos <- is.finite(x) & is.finite(y)
      delta <- abs(y[finitos] - x[finitos])
      if (relativa) delta <- delta / pmax(abs(x[finitos]), 1e-9)
      if (length(delta)) max(delta) else 0
    }
    d <- vapply(num, diferencias, numeric(1))
    r <- vapply(num, diferencias, numeric(1), relativa = TRUE)
    if (length(d)) { dif_max <- max(d); dif_rel <- max(r) }
    txt <- setdiff(comunes, num)
    texto_dif <- sum(vapply(txt, function(n) {
      ok <- !is.na(a[[n]]) & !is.na(b[[n]])
      sum(as.character(a[[n]][ok]) != as.character(b[[n]][ok]))
    }, integer(1)))
  }
  tibble(filas_ref = nrow(a), filas_nueva = nrow(b), columnas_nuevas = paste(nuevas, collapse = " "),
         columnas_retiradas = paste(quitadas, collapse = " "), dif_numerica_max = dif_max, dif_relativa_max = dif_rel,
         celdas_texto_distintas = texto_dif, celdas_ausencia_distinta = ausentes_dif, orden_columnas_igual = orden_igual)
}

ficheros <- function(d) list.files(d, recursive = TRUE, pattern = "\\.(csv|csv\\.gz|png)$")   # las tablas comprimidas (.csv.gz) también se comparan
fa <- ficheros(ref); fb <- ficheros(nue)
todos <- sort(if (solo_referencia) fa else union(fa, fb))
if (!length(todos)) stop("No se encontraron tablas CSV ni gráficos PNG en las carpetas indicadas")
inf <- bind_rows(lapply(todos, function(f) {
  en_a <- f %in% fa; en_b <- f %in% fb
  base <- tibble(fichero = f, tipo = ifelse(grepl("\\.png$", f), "gráfico", "tabla"))
  if (!en_a) return(base |> mutate(estado = "nueva"))
  if (!en_b) return(base |> mutate(estado = "retirada"))
  igual <- huella(file.path(ref, f)) == huella(file.path(nue, f))
  if (igual) return(base |> mutate(estado = "igual (byte a byte)"))
  if (grepl("\\.png$", f)) return(base |> mutate(estado = "cambia (imagen)"))
  bind_cols(base |> mutate(estado = "cambia"), comparar_tabla(file.path(ref, f), file.path(nue, f)))
}))
# Columnas del informe aunque ningún fichero cambie (si todo es igual, comparar_tabla() no llega a ejecutarse)
for (col in c("filas_ref", "filas_nueva", "dif_numerica_max", "dif_relativa_max", "celdas_texto_distintas", "celdas_ausencia_distinta")) if (!col %in% names(inf)) inf[[col]] <- NA_real_
if (!"orden_columnas_igual" %in% names(inf)) inf$orden_columnas_igual <- NA
for (col in c("columnas_nuevas", "columnas_retiradas")) if (!col %in% names(inf)) inf[[col]] <- NA_character_
inf <- inf |> mutate(estado = ifelse(estado == "cambia" & coalesce(dif_numerica_max, 0) == 0 & coalesce(celdas_texto_distintas, 0) == 0 &
                                       coalesce(celdas_ausencia_distinta, 0) == 0 & coalesce(orden_columnas_igual, FALSE) &
                                       coalesce(columnas_nuevas, "") == "" & coalesce(columnas_retiradas, "") == "" & coalesce(filas_ref == filas_nueva, FALSE),
                                     "igual en valores (cambia el formato)", estado))
# Ficheros propios de cada ejecución: la configuración lleva la hora de inicio y el manifiesto,
# las huellas de las salidas (con esa configuración); no se comparan si están en las dos carpetas
# (si falta en una, se informa como nueva o retirada, igual que cualquier otro fichero)
propios <- c("configuracion_ejecucion.csv", "manifiesto_ejecucion.csv")
# Con --solo-referencia, la configuración guardada junto a la referencia describe la ejecución de origen y tampoco se compara;
# un manifiesto que falte en una de las dos carpetas se informa siempre.
inf <- inf |> mutate(estado = ifelse(basename(fichero) %in% propios &
                                       (!estado %in% c("nueva", "retirada") | (solo_referencia & basename(fichero) == "configuracion_ejecucion.csv")),
                                     "propio de la ejecución (no se compara)", estado),
                     tolerancia_relativa = tolerancia,
                     dentro_de_tolerancia = case_when(
                       startsWith(estado, "propio") ~ NA,
                       startsWith(estado, "igual") ~ TRUE,
                       estado == "cambia" ~ coalesce(filas_ref == filas_nueva, FALSE) & coalesce(orden_columnas_igual, FALSE) & coalesce(columnas_nuevas, "") == "" &
                         coalesce(columnas_retiradas, "") == "" & coalesce(celdas_texto_distintas, 0) == 0 & coalesce(celdas_ausencia_distinta, 0) == 0 &
                         coalesce(dif_relativa_max, 0) <= tolerancia,
                       TRUE ~ FALSE))
write_csv(inf, salida, na = "")
print(count(inf, tipo, estado))
cat(sprintf("Dentro de la tolerancia (diferencia relativa <= %g; mismas filas, columnas y textos): %d de %d ficheros comparados (%d propios de cada ejecución, sin comparar).\n",
            tolerancia, sum(inf$dentro_de_tolerancia, na.rm = TRUE), sum(!is.na(inf$dentro_de_tolerancia)), sum(is.na(inf$dentro_de_tolerancia))))
if (any(inf$dentro_de_tolerancia == FALSE, na.rm = TRUE)) quit(status = 1)
