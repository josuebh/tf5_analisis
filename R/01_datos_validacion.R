# =============================================================================
# 01_datos_validacion.R · Carga de datos oficiales y validación automática
# -----------------------------------------------------------------------------
# Datos de partida: aforos del Cabildo de Tenerife (Servicio Técnico de
# Carreteras), conjunto «Intensidad Media Diaria (IMD) de tráfico de Tenerife»,
# un CSV por año (2018-2025) en datos.tenerife.es. Columnas oficiales:
#   carretera_codigo, tramo_nombre, estacion_id, estacion_nombre,
#   velocidad_media, imd_ascendentes, imd_descendentes, imd_total, imd_pesados
# «Ascendente» = sentido de PK creciente (en la TF-5: de Santa Cruz hacia el
# Norte); «descendente» = hacia Santa Cruz.
#
# El proyecto incluye una copia (snapshot) de las filas de la TF-5 para que el
# análisis sea reproducible sin conexión. Con conexión, contrastar_con_fuente()
# descarga los CSV oficiales y comprueba que la copia coincide valor a valor.
# =============================================================================

# Estaciones de la TF-5 en orden de PK creciente (Santa Cruz -> El Tanque)
ESTACIONES_TF5 <- tibble::tribble(
  ~estacion_id, ~etiqueta,              ~zona,
  82,  "Túnel 3 de Mayo",     "Santa Cruz",
  83,  "Somosierra",          "Santa Cruz",
  85,  "Hospital Residencia", "Santa Cruz - La Laguna",
  93,  "Campus Guajara",      "La Laguna",
  97,  "Padre Anchieta",      "La Laguna",
  99,  "Bomberos La Laguna",  "La Laguna - Los Rodeos",
  103, "Ermita Cruz Chica",   "Los Rodeos - Guamasa - El Sauzal",
  111, "La Matanza",          "Acentejo",
  123, "La Orotava",          "Valle de La Orotava",
  131, "Bco. El Patronato",   "Fin de autovía",
  133, "Los Realejos-Socorro","Isla Baja",
  134, "Santa Catalina",      "Isla Baja",
  136, "El Pedregal",         "Isla Baja",
  138, "El Amparo",           "Isla Baja"
) |>
  mutate(orden = row_number())

cargar_imd <- function(ruta = file.path(DIR_DATOS, "imd_tf5_2018_2025.csv")) {
  df <- readr::read_csv(ruta, show_col_types = FALSE,
                        col_types = cols(.default = col_double(),
                                         carretera_codigo = col_character(),
                                         tramo_nombre = col_character(),
                                         estacion_nombre = col_character()))
  fuentes <- readr::read_csv(file.path(DIR_DATOS, "fuentes_imd.csv"), show_col_types = FALSE)
  df |>
    left_join(fuentes, by = "anio") |>
    left_join(ESTACIONES_TF5, by = "estacion_id")
}

# ---- Contraste con la fuente oficial (requiere Internet) ---------------------
descargar_imd_oficial <- function(anios = 2018:2025) {
  fuentes <- readr::read_csv(file.path(DIR_DATOS, "fuentes_imd.csv"), show_col_types = FALSE)
  purrr_map <- function(x, f) lapply(x, f)          # sin dependencia de purrr
  lst <- purrr_map(anios, function(a) {
    url <- fuentes$url_fuente[fuentes$anio == a]
    tmp <- tempfile(fileext = ".csv")
    ok <- tryCatch({ utils::download.file(url, tmp, quiet = TRUE, mode = "wb"); TRUE },
                   error = function(e) FALSE)
    if (!ok) { warning("No se pudo descargar ", a); return(NULL) }
    readr::read_csv(tmp, show_col_types = FALSE, locale = locale(encoding = "UTF-8"),
                    col_types = cols(.default = col_character())) |>
      mutate(anio = a)
  })
  bind_rows(lst)
}

# Copias locales de los CSV oficiales (datos/oficial/, descargadas el 16-10-2026
# con su SHA-256 en manifiesto_oficiales.json)
leer_imd_oficial_local <- function(dir = file.path(DIR_DATOS, "oficial")) {
  fs <- list.files(dir, pattern = "^intensidad-media-diaria-de-trafico-\\d{4}\\.csv$", full.names = TRUE)
  bind_rows(lapply(fs, function(f) {
    a <- as.integer(sub(".*-(\\d{4})\\.csv$", "\\1", f))
    readr::read_csv(f, show_col_types = FALSE, locale = locale(encoding = "UTF-8"),
                    col_types = cols(.default = col_character())) |>
      rename_with(~ sub("^﻿", "", .x)) |>
      mutate(anio = a)
  }))
}

contrastar_con_fuente <- function(snapshot, oficial = NULL) {
  if (is.null(oficial)) oficial <- descargar_imd_oficial(sort(unique(snapshot$anio)))
  if (is.null(oficial) || nrow(oficial) == 0) {
    message("  ! Sin conexión: no se ha podido contrastar con la fuente oficial.")
    return(invisible(NULL))
  }
  num <- c("velocidad_media", "imd_ascendentes", "imd_descendentes", "imd_total", "imd_pesados")
  oficial <- oficial |>
    filter(carretera_codigo == "TF-5") |>
    mutate(across(all_of(c("estacion_id", num)), ~ suppressWarnings(as.numeric(.x))))
  comp <- snapshot |>
    select(anio, estacion_id, all_of(num)) |>
    pivot_longer(all_of(num), names_to = "campo", values_to = "snapshot") |>
    full_join(oficial |> select(anio, estacion_id, all_of(num)) |>
                pivot_longer(all_of(num), names_to = "campo", values_to = "oficial"),
              by = c("anio", "estacion_id", "campo")) |>
    mutate(coincide = (is.na(snapshot) & is.na(oficial)) |
             (!is.na(snapshot) & !is.na(oficial) & abs(snapshot - oficial) < 1e-6))
  n_dif <- sum(!comp$coincide)
  message(sprintf("  · Contraste con la fuente oficial: %d valores comparados, %d diferencias.",
                  nrow(comp), n_dif))
  guardar_tabla(comp, "contraste_snapshot_vs_oficial")
  invisible(comp)
}

# ---- Reglas de validación -----------------------------------------------------
validar_imd <- function(df) {
  reglas <- list()

  # R1. Coherencia interna: ascendentes + descendentes = total
  reglas$suma <- df |>
    filter(!is.na(imd_ascendentes), !is.na(imd_descendentes)) |>
    mutate(dif = imd_ascendentes + imd_descendentes - imd_total) |>
    filter(dif != 0) |>
    transmute(anio, estacion_id, regla = "R1 suma de sentidos != total",
              detalle = paste("diferencia =", dif), gravedad = "error")

  # R2. Falta el desglose por sentido (típico de estaciones de cobertura, estimadas)
  reglas$sentido <- df |>
    filter(is.na(imd_ascendentes) | is.na(imd_descendentes)) |>
    transmute(anio, estacion_id, regla = "R2 sin desglose por sentido",
              detalle = "IMD total sin ascendente/descendente", gravedad = "aviso")

  # R3. Velocidad media = 0 -> no medida (se tratará como NA)
  reglas$vel0 <- df |>
    filter(velocidad_media == 0) |>
    transmute(anio, estacion_id, regla = "R3 velocidad no medida (0)",
              detalle = "velocidad_media = 0", gravedad = "aviso")

  # R4. Velocidad media diaria > 120 km/h: implausible como media de 24 h
  reglas$vel_alta <- df |>
    filter(velocidad_media > 120) |>
    transmute(anio, estacion_id, regla = "R4 velocidad media > 120 km/h",
              detalle = paste0(num_es(velocidad_media, 0.01), " km/h"), gravedad = "aviso")

  # R5. Proporción de pesados atípica para la estación: z modificada de
  #     Iglewicz-Hoaglin, z = (x - mediana) / MAD escalada (mad() de R ya aplica
  #     el factor 1,4826); se marca si |z| > 3,5
  reglas$pesados <- df |>
    mutate(p_pes = imd_pesados / imd_total) |>
    group_by(estacion_id) |>
    mutate(med = median(p_pes, na.rm = TRUE),
           mad = mad(p_pes, na.rm = TRUE),
           z = ifelse(mad > 0, (p_pes - med) / mad, NA)) |>
    ungroup() |>
    filter(!is.na(z), abs(z) > 3.5) |>
    transmute(anio, estacion_id, regla = "R5 % de pesados atípico",
              detalle = sprintf("%s de pesados (mediana de la estación %s)",
                                pct_es(p_pes, 0.1), pct_es(med, 0.1)),
              gravedad = "aviso")

  # R6. Estación ausente en un año en que existen las demás
  todas <- tidyr::expand_grid(anio = sort(unique(df$anio)),
                              estacion_id = sort(unique(df$estacion_id)))
  reglas$ausente <- todas |>
    anti_join(df, by = c("anio", "estacion_id")) |>
    transmute(anio, estacion_id, regla = "R6 estación sin datos ese año",
              detalle = "fila ausente en el CSV oficial", gravedad = "error")

  # R7. Salto interanual > 15 % fuera de los años COVID (2020-2022)
  reglas$salto <- df |>
    arrange(estacion_id, anio) |>
    group_by(estacion_id) |>
    mutate(anio_prev = lag(anio), imd_prev = lag(imd_total),
           var = imd_total / imd_prev - 1) |>
    ungroup() |>
    filter(!is.na(var), anio - anio_prev == 1, !(anio %in% 2020:2022), abs(var) > 0.15) |>
    transmute(anio, estacion_id, regla = "R7 salto interanual > 15 %",
              detalle = paste0(ifelse(var > 0, "+", ""), pct_es(var, 0.1), " vs ", anio_prev),
              gravedad = "aviso")

  # R8. Mismo valor exacto de velocidad media en años distintos (posible imputación)
  reglas$repetido <- df |>
    filter(velocidad_media > 0) |>
    group_by(estacion_id, velocidad_media) |>
    filter(n() > 1) |>
    ungroup() |>
    transmute(anio, estacion_id, regla = "R8 velocidad idéntica en otro año",
              detalle = paste0(num_es(velocidad_media, 0.01), " km/h repetido"),
              gravedad = "info")

  # R9. Asimetría extrema entre sentidos (puede ser estructural: ramales, túnel urbano)
  reglas$asim <- df |>
    filter(!is.na(imd_ascendentes), !is.na(imd_descendentes)) |>
    mutate(r = pmin(imd_ascendentes, imd_descendentes) / pmax(imd_ascendentes, imd_descendentes)) |>
    filter(r < 0.2) |>
    transmute(anio, estacion_id, regla = "R9 asimetría extrema entre sentidos",
              detalle = paste0("ratio menor/mayor = ", num_es(r, 0.01)), gravedad = "info")

  # R10. Clasificación ligeros/pesados inestable: coeficiente de variación del
  #      % de pesados de la estación entre años > 0,5 (se marca la estación entera)
  #      (se excluyen del cálculo los atípicos ya marcados por R5)
  atipicos_r5 <- reglas$pesados |> select(anio, estacion_id)
  reglas$cv_pesados <- df |>
    anti_join(atipicos_r5, by = c("anio", "estacion_id")) |>
    mutate(p_pes = imd_pesados / imd_total) |>
    group_by(estacion_id) |>
    mutate(cv = sd(p_pes, na.rm = TRUE) / mean(p_pes, na.rm = TRUE),
           rango = paste0(pct_es(min(p_pes), 0.1), " - ", pct_es(max(p_pes), 0.1))) |>
    ungroup() |>
    filter(cv > 0.5) |>
    transmute(anio, estacion_id, regla = "R10 % de pesados inestable entre años",
              detalle = paste0("CV = ", num_es(cv, 0.01), " (rango ", rango, ")"),
              gravedad = "aviso")

  bind_rows(reglas) |>
    left_join(ESTACIONES_TF5 |> select(estacion_id, etiqueta, orden), by = "estacion_id") |>
    arrange(orden, anio, regla)
}

# Limpieza tras validar: 0 -> NA en velocidad; marcar filas con incidencias
limpiar_imd <- function(df) {
  df |>
    mutate(velocidad_media = ifelse(velocidad_media == 0, NA, velocidad_media),
           p_pesados = imd_pesados / imd_total,
           asimetria = imd_ascendentes / imd_descendentes)
}

# El análisis de los aforos horarios oficiales está en 07_datos_horarios.R.
