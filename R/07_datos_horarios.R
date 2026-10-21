# =============================================================================
# 07_datos_horarios.R · Aforos HORARIOS oficiales por carril (2024-2026)
# -----------------------------------------------------------------------------
# Fuente: Cabildo de Tenerife, conjuntos «Intensidad diaria de tráfico de
# Tenerife (AAAA)» en datos.tenerife.es. Pese al nombre, cada TXT mensual trae
# registros HORARIOS por carril: estacion_id, carril_id (signo = sentido:
# + creciente/ascendente hacia el Norte, - decreciente hacia Santa Cruz;
# el 1/-1 es el carril derecho), fecha (inicio de la hora), ligeros, pesados y
# vehículos por rango de velocidad (rango1 ... rango6).
# El catálogo «Rango de velocidades de los carriles» (JSON oficial) describe
# cada carril y los límites de los rangos: en la TF-5, rango1 = menos de 80 km/h.
#
# datos/horarios/tf5_horario_AAAA-MM.csv.gz: filas de la TF-5 extraídas de cada
# TXT oficial (mismas columnas, sin los dos campos de nombre). meta_AAAA-MM.json:
# URL, SHA-256 del TXT original, SHA-256 del extracto y controles de la
# extracción. Con TXT/ZIP oficiales en datos/horarios/originales/ se leen también.
# =============================================================================

EST_CORREDOR <- c(85, 93, 97, 99, 103, 111, 123)   # autopista, ambos sentidos con aforo permanente
UMBRAL_LENTO  <- 0.60   # hora congestionada: >= 60 % de vehículos por debajo del rango 1 ...
EXCESO_LENTO  <- 0.30   # ... y al menos 30 puntos más que la madrugada (0-5 h, horas 0 a 4) de esa estación
CAP_MAX_CARRIL <- 2600  # veh/h/carril: por encima se considera caudal horario implausible
UMBRAL_PERFIL_CARRIL <- 0.10  # H9: distancia de variación total del perfil horario de un carril (p98 de 2024-2026)

# ---- Catálogo de carriles (JSON oficial) --------------------------------------
clasificar_carril <- function(desc) {
  d <- tolower(desc)
  dplyr::case_when(grepl("bus", d) ~ "bus",
                   grepl("acceso", d) ~ "acceso",
                   grepl("salida", d) ~ "salida",
                   TRUE ~ "principal")
}

leer_carriles_json <- function(ruta = file.path(DIR_DATOS, "oficial", "rango-de-velocidades-de-los-carriles.json")) {
  js <- jsonlite::fromJSON(ruta, simplifyVector = FALSE)
  bind_rows(lapply(js$estaciones, function(e) bind_rows(lapply(e$carriles, function(cc) {
    r <- cc$rangos[[1]]
    tibble(estacion_id = as.numeric(e$estacion_id), carril_id = as.numeric(cc$carril_id),
           carril_descripcion = trimws(cc$carril_descripcion),
           rango1_max = r$rango1_max, rango2_max = r$rango2_max, rango3_max = r$rango3_max,
           rango4_max = r$rango4_max, rango5_max = r$rango5_max)
  })))) |>
    mutate(sentido = ifelse(carril_id > 0, "ascendente", "descendente"),
           tipo = clasificar_carril(carril_descripcion))
}

carriles_por_sentido <- function(car, estaciones = ESTACIONES_TF5$estacion_id) {
  car |>
    filter(estacion_id %in% estaciones) |>
    group_by(estacion_id, sentido) |>
    summarise(carriles_principales = sum(tipo == "principal"),
              carriles_auxiliares = sum(tipo != "principal"),
              tipos_auxiliares = paste(unique(tipo[tipo != "principal"]), collapse = ", "),
              umbral_lento_kmh = suppressWarnings(min(rango1_max[tipo == "principal"])),
              descripcion = paste(carril_descripcion, collapse = "; "), .groups = "drop")
}

contrastar_carriles <- function(car_sentido, carriles_csv) {
  carriles_csv |>
    select(estacion_id, sentido, carriles_csv = carriles) |>
    full_join(car_sentido |> select(estacion_id, sentido, carriles_json = carriles_principales,
                                    carriles_auxiliares, tipos_auxiliares),
              by = c("estacion_id", "sentido")) |>
    mutate(coincide = ifelse(is.na(carriles_csv) | is.na(carriles_json), NA, carriles_csv == carriles_json)) |>
    arrange(estacion_id, sentido)
}

# ---- Lectura -------------------------------------------------------------------
COLS_HORARIO <- c("estacion_id", "carril_id", "fecha", "ligeros", "pesados",
                  paste0("rango", 1:6, "_vehiculos"))

# Extrae las filas de la TF-5 de un TXT (o ZIP) mensual oficial (13 columnas)
extraer_tf5_de_original <- function(ruta, estaciones = ESTACIONES_TF5$estacion_id) {
  if (grepl("\\.zip$", ruta, ignore.case = TRUE)) {
    d <- tempfile(); utils::unzip(ruta, exdir = d)
    ruta <- list.files(d, pattern = "\\.(txt|csv)$", full.names = TRUE, recursive = TRUE)[1]
  }
  x <- readr::read_csv(ruta, show_col_types = FALSE, locale = readr::locale(encoding = "UTF-8"),
                       col_types = readr::cols(.default = readr::col_double(), estacion_nombre = readr::col_character(),
                                               carril_descripcion = readr::col_character(), fecha = readr::col_character()))
  names(x) <- sub("^﻿", "", names(x))
  x |> filter(estacion_id %in% estaciones) |> select(all_of(COLS_HORARIO))
}

# Descarga los TXT oficiales (requiere Internet) a datos/horarios/originales/ y comprueba que
# su SHA-256 es el registrado al crear los extractos (datos/fuentes_horarias.csv, 24 meses).
# Para añadir un mes nuevo, agrega su fila (mes, url_fuente) a fuentes_horarias.csv: sin
# huella registrada se descarga igual y leer_horarios() lo incorpora.
descargar_horarios_oficiales <- function(meses = NULL, fuentes = file.path(DIR_DATOS, "fuentes_horarias.csv")) {
  f <- readr::read_csv(fuentes, show_col_types = FALSE, col_types = readr::cols(.default = readr::col_character()))
  if (!is.null(meses)) f <- f |> filter(mes %in% meses)
  dir_o <- file.path(DIR_DATOS, "horarios", "originales")
  dir.create(dir_o, recursive = TRUE, showWarnings = FALSE)
  hay_digest <- requireNamespace("digest", quietly = TRUE)
  bind_rows(lapply(seq_len(nrow(f)), function(i) {
    destino <- file.path(dir_o, basename(f$url_fuente[i]))
    ok <- tryCatch({ utils::download.file(f$url_fuente[i], destino, quiet = TRUE, mode = "wb"); TRUE },
                   error = function(e) FALSE, warning = function(w) FALSE)
    if (!ok && file.exists(destino)) unlink(destino)            # no dejar descargas a medias
    huella <- if (ok && hay_digest) digest::digest(file = destino, algo = "sha256") else NA_character_
    registrada <- f$sha256_txt[i]
    coincide <- if (is.na(huella) || is.na(registrada)) NA else huella == registrada
    estado <- if (!ok) "sin conexión o error"
              else if (is.na(huella)) "descargado (instala 'digest' para comprobar la huella)"
              else if (is.na(registrada)) "descargado (mes nuevo, sin huella registrada)"
              else if (coincide) "descargado; SHA-256 idéntico al registrado"
              else "descargado; SHA-256 DISTINTO: el Cabildo ha cambiado el fichero (manda el extracto registrado en el proyecto)"
    message(sprintf("  · %s: %s", f$mes[i], estado))
    tibble(mes = f$mes[i], fichero = basename(destino), descargado = ok, sha256 = huella,
           sha256_registrado = registrada, coincide = coincide, estado = estado)
  }))
}

leer_horarios <- function(dir = file.path(DIR_DATOS, "horarios")) {
  fs <- list.files(dir, pattern = "^tf5_horario_\\d{4}-\\d{2}\\.csv\\.gz$", full.names = TRUE)
  h <- bind_rows(lapply(fs, function(f) readr::read_csv(f, show_col_types = FALSE,
    col_types = readr::cols(fecha = readr::col_character(), .default = readr::col_double()))))
  orig <- list.files(file.path(dir, "originales"), pattern = "\\.(txt|zip)$", full.names = TRUE)
  if (length(orig)) {
    meses_ya <- unique(substr(h$fecha, 1, 7))
    fu <- file.path(DIR_DATOS, "fuentes_horarias.csv")
    if (file.exists(fu)) {   # no relee los originales de meses que ya están en los extractos registrados
      f <- readr::read_csv(fu, show_col_types = FALSE, col_types = readr::cols(.default = readr::col_character()))
      mes_de <- stats::setNames(f$mes, basename(f$url_fuente))[basename(orig)]
      orig <- orig[is.na(mes_de) | !mes_de %in% meses_ya]
    }
    if (length(orig)) {
      ho <- bind_rows(lapply(orig, extraer_tf5_de_original))
      h <- bind_rows(h, ho |> filter(!substr(fecha, 1, 7) %in% meses_ya))   # el extracto registrado manda
    }
  }
  h
}

metadatos_horarios <- function(dir = file.path(DIR_DATOS, "horarios")) {
  fs <- list.files(dir, pattern = "^meta_\\d{4}-\\d{2}\\.json$", full.names = TRUE)
  bind_rows(lapply(fs, function(f) {
    m <- jsonlite::fromJSON(f)
    tibble(mes = m$mes, url = m$url, bytes_txt_oficial = m$bytes_raw, sha256_txt_oficial = m$sha256_raw,
           ultima_modificacion = m$last_modified_ckan, descargado_utc = m$descargado_utc,
           filas_tf5 = m$filas_tf5, sha256_extracto = m$sha256_compact, fichero = m$fichero_local,
           # m[["estaciones"]], no m$estaciones: «$» completaría el nombre con «estaciones_en_fichero»
           estaciones = if (is.null(m[["estaciones"]]))
             paste(sort(unique(as.integer(sub("[+-]$", "", names(m$control))))), collapse = " ") else
             paste(m[["estaciones"]], collapse = " "))
  }))
}

preparar_horarios <- function(h, car, festivos) {
  h |>
    left_join(car |> select(estacion_id, carril_id, tipo, rango1_max), by = c("estacion_id", "carril_id")) |>
    mutate(veh  = ligeros + pesados,
           rsum = rango1_vehiculos + rango2_vehiculos + rango3_vehiculos +
                  rango4_vehiculos + rango5_vehiculos + rango6_vehiculos,
           rangos_negativos = rango1_vehiculos < 0 | rango2_vehiculos < 0 | rango3_vehiculos < 0 |
                              rango4_vehiculos < 0 | rango5_vehiculos < 0 | rango6_vehiculos < 0,
           dia  = as.Date(substr(fecha, 1, 10)),
           hora = as.integer(substr(fecha, 12, 13)),
           mes  = substr(fecha, 1, 7),
           anio = as.integer(substr(fecha, 1, 4)),
           sentido = ifelse(carril_id > 0, "ascendente", "descendente"),
           dow = as.integer(format(dia, "%u")),
           festivo = dia %in% festivos$fecha,
           laborable = dow <= 5 & !festivo)
}

# ---- Validación de los aforos horarios (reglas H1-H8) --------------------------
validar_horarios <- function(hp, car_sentido, imd = NULL) {
  out <- list()
  # H1. Suma de rangos de velocidad distinta de ligeros + pesados
  h1 <- hp |> filter(rsum != veh)
  if (nrow(h1)) out$h1 <- h1 |>
    group_by(estacion_id, sentido) |>
    summarise(filas = n(), detalle = sprintf("diferencia rangos - vehículos entre %s y %s (total %s)",
                                             num_es(min(rsum - veh)), num_es(max(rsum - veh)), num_es(sum(rsum - veh))),
              .groups = "drop") |>
    mutate(regla = "H1 rangos de velocidad != vehículos", gravedad = "info")
  # H2. Horas sin todos los carriles principales
  esperado <- car_sentido |> select(estacion_id, sentido, carriles_principales)
  hor <- hp |> filter(tipo == "principal") |>
    group_by(estacion_id, sentido, mes, dia, hora) |> summarise(ncar = n_distinct(carril_id), .groups = "drop") |>
    left_join(esperado, by = c("estacion_id", "sentido"))
  dias_mes <- function(m) as.integer(format(seq(as.Date(paste0(m, "-01")), by = "month", length.out = 2)[2] - 1, "%d"))
  # rejilla completa de las estaciones del corredor presentes en los datos: un mes sin
  # ningún registro cuenta como cobertura 0 (si no, no aparecería)
  rejilla <- esperado |> filter(estacion_id %in% intersect(EST_CORREDOR, unique(hp$estacion_id))) |>
    select(estacion_id, sentido) |> tidyr::crossing(mes = sort(unique(hp$mes)))
  out$h2 <- hor |> group_by(estacion_id, sentido, mes) |>
    summarise(horas_completas = sum(ncar == carriles_principales), .groups = "drop") |>
    full_join(rejilla, by = c("estacion_id", "sentido", "mes")) |>
    mutate(horas_completas = coalesce(horas_completas, 0L)) |>
    mutate(horas_mes = vapply(mes, dias_mes, integer(1)) * 24L,
           cobertura = horas_completas / horas_mes) |>
    filter(cobertura < 0.9) |>
    transmute(estacion_id, sentido, mes, filas = horas_mes - horas_completas,
              detalle = sprintf("solo %s de las horas del mes con todos los carriles", pct_es(cobertura)),
              regla = "H2 horas incompletas (> 10 % del mes)", gravedad = "aviso")
  # H3. Carril-día con cero vehículos (detector parado)
  out$h3 <- hp |> group_by(estacion_id, sentido, carril_id, mes, dia) |> summarise(v = sum(veh), .groups = "drop") |>
    filter(v == 0) |> group_by(estacion_id, sentido, mes) |>
    summarise(filas = n(), detalle = paste0("carril-días a cero: carriles ", paste(sort(unique(carril_id)), collapse = ", ")),
              .groups = "drop") |>
    mutate(regla = "H3 carril-día sin vehículos", gravedad = "aviso")
  # H4. Registros duplicados (estación, carril, fecha)
  out$h4 <- hp |> count(estacion_id, sentido, carril_id, fecha) |> filter(n > 1) |>
    group_by(estacion_id, sentido) |>
    summarise(filas = sum(n - 1), detalle = paste("fechas:", paste(unique(fecha), collapse = ", ")), .groups = "drop") |>
    mutate(regla = "H4 registros duplicados", gravedad = "aviso")
  # H5. Carriles que no están en el catálogo oficial
  out$h5 <- hp |> filter(is.na(tipo)) |> count(estacion_id, sentido, name = "filas") |>
    mutate(detalle = "carril sin catalogar en el JSON", regla = "H5 carril no catalogado", gravedad = "error")
  # H6. Valores negativos en los rangos de velocidad
  out$h6 <- hp |> filter(rangos_negativos) |> group_by(estacion_id, sentido, mes) |>
    summarise(filas = n(), detalle = "rangos de velocidad con valores negativos (se descartan las velocidades)", .groups = "drop") |>
    mutate(regla = "H6 rangos negativos", gravedad = "error")
  # H7. Caudal horario por carril implausible
  out$h7 <- hp |> filter(veh > CAP_MAX_CARRIL) |> count(estacion_id, sentido, name = "filas") |>
    mutate(detalle = paste0("más de ", num_es(CAP_MAX_CARRIL), " veh/h en un carril"), regla = "H7 caudal implausible", gravedad = "aviso")
  # H8. Media diaria del año (días completos) frente a la IMD oficial del mismo año
  if (!is.null(imd)) {
    dd <- hor |> filter(ncar == carriles_principales) |> select(estacion_id, sentido, dia) |>
      count(estacion_id, sentido, dia, name = "horas") |> filter(horas == 24) |> select(-horas)
    vol <- hp |> filter(tipo == "principal") |> semi_join(dd, by = c("estacion_id", "sentido", "dia")) |>
      group_by(estacion_id, sentido, anio, dia) |> summarise(v = sum(veh), .groups = "drop") |>
      group_by(estacion_id, sentido, anio) |> summarise(media = mean(v), dias = n(), .groups = "drop")
    ref <- imd |> transmute(anio, estacion_id, ascendente = imd_ascendentes, descendente = imd_descendentes) |>
      pivot_longer(c(ascendente, descendente), names_to = "sentido", values_to = "imd")
    out$h8 <- vol |> inner_join(ref, by = c("anio", "estacion_id", "sentido")) |>
      mutate(ratio = media / imd) |>
      filter(dias >= 30, abs(ratio - 1) > 0.10) |>
      transmute(estacion_id, sentido, mes = as.character(anio), filas = dias,
                detalle = sprintf("media de %d días completos = %s veh/día frente a IMD %s (%s)", dias,
                                  num_es(media), num_es(imd), pct_es(ratio - 1, 0.1)),
                regla = "H8 media horaria != IMD oficial (> 10 %)", gravedad = "aviso")
  }
  # H9. Perfil horario de un carril muy distinto de su perfil habitual (aforador que cuenta
  # mal unas horas aunque el total del día parezca normal). Distancia de variación total
  # entre el reparto horario medio del mes (laborables) y la mediana de todos los meses.
  pm <- hp |> filter(laborable, tipo == "principal", substr(mes, 6, 7) != "08") |>
    group_by(estacion_id, sentido, carril_id, mes, hora) |> summarise(v = mean(veh), dias = n(), .groups = "drop") |>
    group_by(estacion_id, sentido, carril_id, mes) |> filter(n() == 24, sum(v) > 0) |>
    mutate(s = v / sum(v), dias = min(dias)) |> ungroup()
  if (nrow(pm)) {
    pref <- pm |> group_by(estacion_id, sentido, carril_id, hora) |> summarise(s_ref = stats::median(s), .groups = "drop") |>
      group_by(estacion_id, sentido, carril_id) |> mutate(s_ref = s_ref / sum(s_ref)) |> ungroup()
    out$h9 <- pm |> left_join(pref, by = c("estacion_id", "sentido", "carril_id", "hora")) |>
      group_by(estacion_id, sentido, carril_id, mes) |>
      summarise(tvd = sum(abs(s - s_ref)) / 2, dias = first(dias), .groups = "drop") |>
      filter(tvd > UMBRAL_PERFIL_CARRIL) |>
      transmute(estacion_id, sentido, mes, filas = dias * 24L,
                detalle = sprintf("carril %d: perfil horario distinto del habitual (distancia %s)", carril_id, num_es(tvd, 0.01)),
                regla = "H9 perfil horario anómalo en un carril", gravedad = "aviso")
  }
  bind_rows(out) |>
    left_join(ESTACIONES_TF5 |> select(estacion_id, etiqueta, orden), by = "estacion_id") |>
    select(regla, gravedad, estacion_id, etiqueta, sentido, mes, filas, detalle, orden) |>
    arrange(regla, orden, sentido, mes) |> select(-orden)
}

# ---- Agregación por estación, sentido y hora (carriles principales) ------------
agregar_por_sentido <- function(hp, car_sentido, estaciones = EST_CORREDOR) {
  hp |>
    filter(estacion_id %in% estaciones, tipo == "principal") |>
    group_by(estacion_id, sentido, anio, mes, dia, hora, laborable) |>
    summarise(veh = sum(veh), pesados = sum(pesados), lento = sum(rango1_vehiculos), rsum = sum(rsum),
              ncar = n_distinct(carril_id), neg = any(rangos_negativos), .groups = "drop") |>
    left_join(car_sentido |> select(estacion_id, sentido, carriles = carriles_principales),
              by = c("estacion_id", "sentido")) |>
    mutate(completa = ncar == carriles,
           cuota_lenta = ifelse(!neg & rsum > 0, lento / rsum, NA_real_))
}

# Días laborables válidos: 24 h completas, no festivos, sin agosto (opcional) y
# con un total diario >= 85 % de la mediana del mes (filtra festivos locales y
# días con incidencias de aforo)
dias_validos <- function(sd, excluir_agosto = TRUE, umbral_rel = 0.85) {
  sd |>
    filter(laborable, completa) |>
    group_by(estacion_id, sentido, anio, mes, dia) |>
    summarise(horas = n(), v = sum(veh), .groups = "drop") |>
    filter(horas == 24) |>
    group_by(estacion_id, sentido, mes) |>
    mutate(rel = v / median(v)) |> ungroup() |>
    filter(rel >= umbral_rel, !(excluir_agosto & substr(mes, 6, 7) == "08")) |>
    select(estacion_id, sentido, anio, mes, dia, v)
}

# Línea base de velocidad: % de vehículos lentos de madrugada (0-5 h, horas 0 a 4)
base_nocturna <- function(sd, dv) {
  sd |> semi_join(dv, by = c("estacion_id", "sentido", "dia")) |>
    filter(hora <= 4, !is.na(cuota_lenta)) |>
    group_by(estacion_id, sentido) |>
    summarise(base_noche = sum(lento) / sum(rsum), .groups = "drop")
}

marcar_congestion <- function(sd, dv, base, umbral = UMBRAL_LENTO, exceso = EXCESO_LENTO) {
  sd |> semi_join(dv, by = c("estacion_id", "sentido", "dia")) |>
    left_join(base, by = c("estacion_id", "sentido")) |>
    mutate(congestionada = !is.na(cuota_lenta) & cuota_lenta >= umbral &
             (cuota_lenta - base_noche) >= exceso)
}

# Sensibilidad del diagnóstico a la definición de hora congestionada: horas de cola
# por día laborable con umbrales más laxos y más estrictos que los del análisis
#   fiab: tabla de fiabilidad_velocidad(); si se da, las estaciones con velocidad no utilizable
#   no cuentan horas congestionadas con ningún umbral (misma máscara que el análisis principal)
sensibilidad_umbrales <- function(sd, dv, base, anios = 2025,
                                  umbrales = tibble(umbral = c(0.5, 0.6, 0.7), exceso = c(0.2, 0.3, 0.4)), fiab = NULL) {
  bind_rows(lapply(seq_len(nrow(umbrales)), function(i) {
    sc_i <- marcar_congestion(sd, dv, base, umbrales$umbral[i], umbrales$exceso[i])
    if (!is.null(fiab)) sc_i <- sc_i |>
      left_join(fiab |> select(estacion_id, sentido, velocidad_fiable), by = c("estacion_id", "sentido")) |>
      mutate(congestionada = congestionada & velocidad_fiable)
    resumen_congestion(sc_i, anios, fiab) |>
      mutate(umbral = umbrales$umbral[i], exceso = umbrales$exceso[i])
  })) |>
    select(umbral, exceso, estacion_id, etiqueta, sentido, dias_con_velocidad, velocidad_utilizable, horas_media, horas_p25,
           horas_mediana, horas_p75, dias_sin_congestion, hora_inicio_tipica, hora_fin_tipica)
}

perfil_laborable <- function(sc, anios = 2025) {
  sc |> filter(anio %in% anios) |>
    group_by(estacion_id, sentido, hora) |>
    summarise(veh = mean(veh), veh_carril = mean(veh / carriles),
              cuota_lenta = if (any(!is.na(cuota_lenta))) sum(lento[!is.na(cuota_lenta)]) / sum(rsum[!is.na(cuota_lenta)]) else NA_real_,
              prob_congestion = mean(congestionada), dias = n_distinct(dia), carriles = first(carriles),
              base_noche = first(base_noche), .groups = "drop") |>
    group_by(estacion_id, sentido) |>
    mutate(cuota = veh / sum(veh), dia_medio = sum(veh), k_observado = max(cuota),
           hora_punta = hora[which.max(veh)]) |>
    ungroup()
}

# velocidad_utilizable: FALSE en las estaciones cuya velocidad no sirve para detectar la cola
# (fiabilidad_velocidad): sus 0 horas significan «no medible», no «sin cola»
resumen_congestion <- function(sc, anios = 2025, fiab = NULL) {
  fiable <- if (is.null(fiab)) tibble(estacion_id = integer(), sentido = character(), velocidad_utilizable = logical()) else
    fiab |> transmute(estacion_id, sentido, velocidad_utilizable = velocidad_fiable)
  sc |> filter(anio %in% anios) |>
    group_by(estacion_id, sentido, dia) |>
    summarise(horas = sum(congestionada), velocidad_valida = all(!is.na(cuota_lenta)),
              inicio = if (any(congestionada)) min(hora[congestionada]) else NA_integer_,
              fin = if (any(congestionada)) max(hora[congestionada]) else NA_integer_, .groups = "drop") |>
    group_by(estacion_id, sentido) |>
    summarise(dias = n(), dias_con_velocidad = sum(velocidad_valida),
              horas_media = mean(horas[velocidad_valida]), horas_p25 = quantile(horas[velocidad_valida], 0.25),
              horas_mediana = median(horas[velocidad_valida]), horas_p75 = quantile(horas[velocidad_valida], 0.75),
              dias_sin_congestion = sum(horas[velocidad_valida] == 0),
              hora_inicio_tipica = if (any(!is.na(inicio))) as.integer(names(which.max(table(inicio)))) else NA_integer_,
              hora_fin_tipica = if (any(!is.na(fin))) as.integer(names(which.max(table(fin)))) else NA_integer_,
              .groups = "drop") |>
    left_join(fiable, by = c("estacion_id", "sentido")) |>
    mutate(velocidad_utilizable = coalesce(velocidad_utilizable, TRUE)) |>
    left_join(ESTACIONES_TF5 |> select(estacion_id, etiqueta, orden), by = "estacion_id") |>
    arrange(sentido, orden)
}

# Caudales por carril: percentiles en horas laborables válidas y caudal de
# descarga en horas congestionadas aguas arriba (estación en la cola) o aguas
# abajo (estación de descarga, con la cola en la estación anterior)
capacidad_observada <- function(sc, anios = 2025) {
  sc |> filter(anio %in% anios) |>
    mutate(pc = veh / carriles) |>
    group_by(estacion_id, sentido) |>
    summarise(carriles = first(carriles), p95 = quantile(pc, 0.95), p99 = quantile(pc, 0.99), max = max(pc),
              horas_congestionadas = sum(congestionada),
              caudal_en_cola_p50 = if (any(congestionada)) median(pc[congestionada]) else NA_real_,
              .groups = "drop") |>
    left_join(ESTACIONES_TF5 |> select(estacion_id, etiqueta, orden), by = "estacion_id") |>
    arrange(sentido, orden)
}

# Caudal de una estación de descarga en las horas en que otra (aguas arriba)
# está congestionada, día a día
descarga_en_horas_de_cola <- function(sc, est_cola, sentido_cola, est_descarga, anios = 2025) {
  cola <- sc |> filter(anio %in% anios, estacion_id == est_cola, sentido == sentido_cola, congestionada) |>
    select(dia, hora)
  sc |> filter(anio %in% anios, estacion_id == est_descarga, sentido == sentido_cola) |>
    semi_join(cola, by = c("dia", "hora")) |>
    transmute(dia, hora, veh, veh_carril = veh / carriles)
}

# ---- Comparaciones entre periodos ----------------------------------------------
# Tráfico diario de unas horas dadas en dos periodos, con diferencia e IC 95 %
# (test de Welch sobre días laborables válidos). Con hp, además, comprueba que el
# reparto del tráfico entre carriles no cambia más de 4 puntos entre periodos, ni en
# el día completo ni en las horas comparadas: un salto así suele indicar un cambio o
# avería del aforador, no del tráfico.
comparar_periodos <- function(sc, meses_a, meses_b, horas = 7:8, estaciones = EST_CORREDOR,
                              hp = NULL, umbral_reparto = 0.04, min_dias = 15) {
  d <- sc |> filter(estacion_id %in% estaciones, mes %in% c(meses_a, meses_b)) |>
    mutate(periodo = ifelse(mes %in% meses_a, "a", "b")) |>
    group_by(estacion_id, sentido, periodo, dia) |>
    summarise(v_horas = sum(veh[hora %in% horas]), v_dia = sum(veh),
              lenta_horas = if (all(!is.na(cuota_lenta[hora %in% horas])))
                sum(lento[hora %in% horas]) / sum(rsum[hora %in% horas]) else NA_real_,
              horas_cong = sum(congestionada), .groups = "drop")
  out <- d |> group_by(estacion_id, sentido) |>
    group_modify(function(x, k) {
      a <- x[x$periodo == "a", ]; b <- x[x$periodo == "b", ]
      if (nrow(a) < min_dias || nrow(b) < min_dias) return(tibble())
      # test de Welch; NULL si no se puede calcular (p. ej., datos constantes, como 0 h de cola todos los días)
      t_seguro <- function(y, x) tryCatch(stats::t.test(y, x), error = function(e) NULL)
      tt <- t_seguro(b$v_horas, a$v_horas)
      con_vel <- sum(!is.na(a$lenta_horas)) >= 5 && sum(!is.na(b$lenta_horas)) >= 5
      tc <- if (con_vel) t_seguro(b$horas_cong, a$horas_cong) else NULL
      tibble(dias_a = nrow(a), dias_b = nrow(b),
             veh_horas_a = mean(a$v_horas), veh_horas_b = mean(b$v_horas),
             dif = mean(b$v_horas) - mean(a$v_horas),
             ic_inf = if (is.null(tt)) NA_real_ else tt$conf.int[1], ic_sup = if (is.null(tt)) NA_real_ else tt$conf.int[2],
             p_valor = if (is.null(tt)) NA_real_ else tt$p.value,
             veh_dia_a = mean(a$v_dia), veh_dia_b = mean(b$v_dia),
             lenta_a = mean(a$lenta_horas, na.rm = TRUE), lenta_b = mean(b$lenta_horas, na.rm = TRUE),
             horas_cong_a = if (con_vel) mean(a$horas_cong) else NA_real_,
             horas_cong_b = if (con_vel) mean(b$horas_cong) else NA_real_,
             p_valor_cong = if (!is.null(tc)) tc$p.value else NA_real_)
    }) |> ungroup()
  if (!is.null(hp)) {
    # Reparto en el día completo y en las horas comparadas: un carril que cuenta mal solo
    # unas horas (perfil horario errático) no se ve en el total del día
    dias_usados <- d |> select(estacion_id, sentido, dia)
    rep <- hp |> filter(tipo == "principal") |>
      semi_join(dias_usados, by = c("estacion_id", "sentido", "dia")) |>
      mutate(periodo = ifelse(mes %in% meses_a, "a", "b")) |>
      group_by(estacion_id, sentido, periodo, carril_id) |>
      summarise(v_dia = sum(veh), v_horas = sum(veh[hora %in% horas]), .groups = "drop") |>
      group_by(estacion_id, sentido, periodo) |>
      mutate(cuota_dia = v_dia / sum(v_dia), cuota_horas = v_horas / sum(v_horas)) |> ungroup() |>
      select(estacion_id, sentido, periodo, carril_id, cuota_dia, cuota_horas) |>
      tidyr::pivot_wider(names_from = periodo, values_from = c(cuota_dia, cuota_horas)) |>
      group_by(estacion_id, sentido) |>
      summarise(cambio_reparto_dia = max(abs(cuota_dia_b - cuota_dia_a), na.rm = TRUE),
                cambio_reparto_horas = max(abs(cuota_horas_b - cuota_horas_a), na.rm = TRUE),
                cambio_reparto = pmax(cambio_reparto_dia, cambio_reparto_horas), .groups = "drop")
    out <- out |> left_join(rep, by = c("estacion_id", "sentido")) |>
      mutate(comparable = !is.na(cambio_reparto) & cambio_reparto <= umbral_reparto)
  } else out$comparable <- TRUE
  out |>
    left_join(ESTACIONES_TF5 |> select(estacion_id, etiqueta, orden), by = "estacion_id") |>
    arrange(sentido, orden)
}

# Reparto del tráfico entre carriles de una estación por mes (detecta carriles
# que dejan de contar o cortes de carril)
reparto_carriles <- function(hp, estacion, sent) {
  hp |> filter(estacion_id == estacion, sentido == sent, laborable) |>
    group_by(mes, carril_id) |> summarise(v = sum(veh), .groups = "drop") |>
    group_by(mes) |> mutate(cuota = v / sum(v)) |> ungroup()
}

# ---- Holgura del tramo siguiente con caudales observados ----------------------
# Para el caso 1 (hacia Santa Cruz): en cada hora congestionada del cuello
# (103), cuánto podría crecer su descarga antes de llenar el tramo siguiente:
#   holgura = (C_abajo - (F_abajo - F_cuello)) / F_cuello - 1
# C_abajo = capacidad observada de la estación de abajo (percentil 99 de sus
# caudales horarios en días laborables válidos; el máximo horario subestima algo
# la capacidad); F_abajo - F_cuello = entradas netas entre ambas estaciones en
# esa misma hora. Se toma la estación de abajo más restrictiva de cada hora.
# est_cola: estación donde se mide la cola (por defecto, el propio cuello). En el
# caso 2 la cola está en Bomberos La Laguna (99) y el caudal que sale del cuello se
# mide en Ermita Cruz Chica (103), ya con 2 carriles.
# capacidad: C_abajo ya estimada (vector con nombre = estación de abajo). Si es NULL se
# estima con los caudales de los mismos años; para comparar otro periodo (2026) con 2025
# se pasa la capacidad de 2025, y así solo cambian los caudales, no la capacidad estimada.
holgura_observada <- function(sc, cuello = 103, abajo = c(99, 93), sent = "descendente", anios = 2025,
                              prob_capacidad = 0.99, est_cola = cuello, capacidad = NULL) {
  cola <- sc |> filter(anio %in% anios, estacion_id == est_cola, sentido == sent) |>
    select(dia, hora, cong_cuello = congestionada)
  cc <- sc |> filter(anio %in% anios, estacion_id == cuello, sentido == sent) |>
    select(dia, hora, F_cuello = veh) |>
    inner_join(cola, by = c("dia", "hora"))
  por_estacion <- bind_rows(lapply(abajo, function(e) {
    ab <- sc |> filter(anio %in% anios, estacion_id == e, sentido == sent)
    C_abajo <- if (is.null(capacidad)) as.numeric(stats::quantile(ab$veh, prob_capacidad)) else unname(capacidad[as.character(e)])
    if (is.na(C_abajo)) stop("holgura_observada: falta la capacidad de la estación ", e)
    ab |> select(dia, hora, F_abajo = veh, cong_abajo = congestionada) |>
      inner_join(cc, by = c("dia", "hora")) |>
      filter(cong_cuello) |>
      mutate(estacion_abajo = e, C_abajo = C_abajo, entradas_netas = F_abajo - F_cuello,
             holgura = (C_abajo - entradas_netas) / F_cuello - 1)
  }))
  por_estacion |>
    group_by(dia, hora) |>
    mutate(restrictiva = holgura == min(holgura)) |>
    ungroup()
}

# Fiabilidad del indicador de velocidad por estación y sentido
fiabilidad_velocidad <- function(sd, dv, base) {
  sd |> semi_join(dv, by = c("estacion_id", "sentido", "dia")) |>
    group_by(estacion_id, sentido) |>
    summarise(horas_con_velocidad = mean(!is.na(cuota_lenta)), .groups = "drop") |>
    left_join(base, by = c("estacion_id", "sentido")) |>
    mutate(velocidad_fiable = horas_con_velocidad >= 0.9 & !is.na(base_noche) & base_noche < 0.6,
           motivo = case_when(horas_con_velocidad < 0.9 ~ "rangos de velocidad con valores negativos o ausentes",
                              is.na(base_noche) | base_noche >= 0.6 ~ "de madrugada ya va a menos de 80 km/h la mayoría: el indicador no detecta la cola",
                              TRUE ~ "fiable"))
}

# Comprobación de las horas punta de los apuntes (afirmación 4) y del día de la
# semana (afirmación 5) con los aforos horarios
verificar_horas_punta <- function(perf) {
  perf |> filter(prob_congestion > 0) |>
    group_by(estacion_id, sentido) |>
    summarise(horas_mitad_dias = paste(sprintf("%02d h", hora[prob_congestion >= 0.5]), collapse = ", "),
              horas_cuarto_dias = paste(sprintf("%02d h", hora[prob_congestion >= 0.25]), collapse = ", "),
              prob_max = max(prob_congestion), .groups = "drop") |>
    left_join(ESTACIONES_TF5 |> select(estacion_id, etiqueta, orden), by = "estacion_id") |>
    arrange(sentido, orden)
}

perfil_por_dia_semana <- function(sc, estacion, sent, anios = 2025, horas = 11:17) {
  nombres_dias <- c("lunes", "martes", "miércoles", "jueves", "viernes")
  sc |> filter(anio %in% anios, estacion_id == estacion, sentido == sent) |>
    mutate(dow = as.integer(format(dia, "%u"))) |>
    group_by(dow, hora) |> summarise(veh = mean(veh), cong = mean(congestionada), dias = n_distinct(dia), .groups = "drop") |>
    group_by(dow) |>
    summarise(dias = max(dias), veh_franja = sum(veh[hora %in% horas]), hora_max = hora[hora %in% horas][which.max(veh[hora %in% horas])],
              veh_hora_max = max(veh[hora %in% horas]), horas_congestion = sum(cong), .groups = "drop") |>
    mutate(dia_semana = nombres_dias[dow], estacion_id = estacion, sentido = sent)
}

# Matriz 24 x 101 (hora x cuantil) de la holgura estimada. Horas con menos de 10
# observaciones (casi sin cola en el cuello): cuantiles del conjunto de horas
# desde las 9 h, en las que sobra capacidad aguas abajo.
matriz_holgura_horaria <- function(holg_h, min_obs = 10) {
  q <- seq(0, 1, 0.01)
  resto <- holg_h$holgura[holg_h$hora >= 9]
  if (length(resto) < min_obs) resto <- holg_h$holgura
  t(vapply(0:23, function(hh) {
    x <- holg_h$holgura[holg_h$hora == hh]
    if (length(x) >= min_obs) as.numeric(stats::quantile(x, q)) else as.numeric(stats::quantile(resto, q))
  }, numeric(length(q))))
}

# ---- Gráficos -------------------------------------------------------------------
grafico_mapa_congestion <- function(perf, fiables) {
  d <- perf |>
    left_join(ESTACIONES_TF5 |> select(estacion_id, etiqueta, orden), by = "estacion_id") |>
    left_join(fiables |> select(estacion_id, sentido, velocidad_fiable), by = c("estacion_id", "sentido")) |>
    mutate(valor = ifelse(velocidad_fiable, pmax(cuota_lenta - base_noche, 0), NA_real_),
           fila = factor(paste0(etiqueta, " (", carriles, " c.)"),
                         levels = unique(paste0(etiqueta, " (", carriles, " c.)")[order(orden)])),
           sent_lbl = ifelse(sentido == "descendente", "Hacia Santa Cruz (sentido de la obra del tercer carril)",
                             "Hacia el Norte"))
  ggplot(d, aes(hora, fila, fill = valor)) +
    geom_tile(colour = SUPERFICIE, linewidth = 0.6) +
    geom_text(data = d |> filter(!is.na(valor), prob_congestion >= 0.5),
              aes(label = pct_es(prob_congestion)), size = 2.3, colour = "white") +
    facet_wrap(~sent_lbl, ncol = 1, scales = "free_y") +
    scale_fill_gradientn(colours = c("#f3f7fc", "#a9c9ec", PAL[["azul"]], "#173f72"),
                         limits = c(0, 0.9), oob = scales::squish, labels = function(x) pct_es(x),
                         na.value = "#e6e5e0", name = "Aumento de vehículos lentos sobre la madrugada") +
    scale_x_continuous(breaks = seq(0, 23, 2), labels = function(x) sprintf("%02d h", x), expand = c(0, 0)) +
    scale_y_discrete(limits = rev) +
    labs(title = "Dónde y cuándo se atasca la TF-5: velocidad por estación y hora",
         subtitle = envolver(paste("Días laborables de 2025 sin agosto. Color: puntos porcentuales de vehículos a menos de 80 km/h por",
                                   "encima de la madrugada (0-5 h) de cada estación. Número: % de días con esa hora congestionada",
                                   "(se muestra si es la mitad o más). De Santa Cruz (arriba) al Norte (abajo). Gris: sin datos de velocidad fiables."), 112),
         x = NULL, y = NULL,
         caption = envolver(paste("Fuente: Cabildo de Tenerife, aforos horarios por carril 2025 (datos.tenerife.es), carriles principales;",
                                  "umbral de 80 km/h del catálogo oficial de rangos de velocidad. Padre Anchieta: velocidades con valores negativos",
                                  "y meses sin datos. La Matanza: casi todos los vehículos van a menos de 80 km/h también de madrugada, por lo",
                                  "que este indicador no detecta allí la congestión."), 150)) +
    tema_tf5(10) +
    theme(legend.position = "top", legend.key.width = unit(2.2, "cm"), legend.title = element_text(colour = TINTA_2, size = 8.5),
          panel.grid.major.y = element_blank(), strip.text = element_text(size = 9.5))
}

grafico_perfiles_cuello <- function(perf, casos) {
  d <- perf |> inner_join(casos, by = c("estacion_id", "sentido")) |>
    mutate(caso = factor(caso, levels = unique(casos$caso)))
  bandas <- d |> filter(prob_congestion >= 0.5) |> group_by(caso) |>
    summarise(xmin = min(hora) - 0.5, xmax = max(hora) + 0.5, .groups = "drop")
  ggplot(d, aes(hora, veh)) +
    geom_rect(data = bandas, aes(xmin = xmin, xmax = xmax, ymin = -Inf, ymax = Inf), inherit.aes = FALSE,
              fill = "#fbe3d6", alpha = 0.8) +
    geom_col(fill = PAL[["azul"]], width = 0.75) +
    geom_hline(data = d |> filter(!is.na(capacidad)) |> distinct(caso, capacidad), aes(yintercept = capacidad),
               linetype = "22", colour = PAL[["naranja"]], linewidth = 0.6) +
    facet_wrap(~caso, ncol = 1, scales = "free_y") +
    scale_x_continuous(breaks = seq(0, 23, 2), labels = function(x) sprintf("%02d h", x)) +
    scale_y_continuous(labels = function(x) num_es(x)) +
    labs(title = "Tráfico por hora en los dos cuellos de botella (días laborables de 2025)",
         subtitle = envolver(paste("Barras: vehículos por hora de media. Franja: horas congestionadas al menos la mitad de los días.",
                                   "Línea discontinua: caudal de descarga observado con cola (mediana)."), 110),
         x = NULL, y = "Vehículos por hora",
         caption = "Fuente: Cabildo de Tenerife, aforos horarios por carril 2025 (datos.tenerife.es).") +
    tema_tf5(10)
}

grafico_comparacion <- function(cmp_ull, cmp_2026) {
  niveles <- c("Oct-nov 2025 frente a oct-nov 2024 (escalonamiento ULL)", "Ene-sep 2026 frente a ene-sep 2025 (sin agosto)")
  d <- bind_rows(cmp_ull |> mutate(comparacion = niveles[1]), cmp_2026 |> mutate(comparacion = niveles[2])) |>
    mutate(comparacion = factor(comparacion, levels = niveles),
           fila = paste0(etiqueta, ifelse(sentido == "descendente", " → S/C", " → Norte")),
           fila = reorder(fila, -orden + ifelse(sentido == "ascendente", 0.1, 0)),
           clase = case_when(!comparable ~ "Aforador alterado (cambia el reparto entre carriles)",
                             p_valor < 0.05 ~ "Diferencia significativa (p < 0,05)",
                             TRUE ~ "No significativa"))
  ggplot(d, aes(y = fila)) +
    geom_vline(xintercept = 0, colour = "#c3c2b7", linewidth = 0.4) +
    geom_segment(aes(x = ic_inf, xend = ic_sup, yend = fila), colour = TINTA_MUTE, linewidth = 0.8) +
    geom_point(aes(x = dif, colour = clase, shape = clase), size = 2.6, stroke = 1) +
    facet_wrap(~comparacion, ncol = 2) +
    scale_colour_manual(values = c("Diferencia significativa (p < 0,05)" = PAL[["naranja"]], "No significativa" = PAL[["azul"]],
                                   "Aforador alterado (cambia el reparto entre carriles)" = "#a3a29a")) +
    scale_shape_manual(values = c("Diferencia significativa (p < 0,05)" = 16, "No significativa" = 16,
                                  "Aforador alterado (cambia el reparto entre carriles)" = 1)) +
    scale_x_continuous(labels = function(x) num_es(x)) +
    guides(colour = guide_legend(nrow = 2), shape = guide_legend(nrow = 2)) +
    labs(title = "¿Ha cambiado la punta de la mañana? Vehículos de 7 a 9 h, antes y después",
         subtitle = envolver(paste("Diferencia de la media diaria de vehículos entre las 7 y las 9 h (días laborables válidos)",
                                   "con su intervalo de confianza del 95 %. El Cabildo atribuye a los horarios escalonados de la ULL",
                                   "unos 500 vehículos/día menos en la punta."), 120),
         x = "Vehículos de 7 a 9 h por día laborable (después - antes)", y = NULL,
         caption = envolver(paste("Fuente: aforos horarios del Cabildo (datos.tenerife.es); test de Welch sobre días laborables válidos.",
                                  "Gris: el reparto del tráfico entre carriles cambia más de 4 puntos entre periodos, en el día o de 7 a 9 h",
                                  "(cambio o avería del aforador), así que la diferencia no es interpretable. Padre Anchieta se excluye por falta",
                                  "de datos en 2024-2025."), 150)) +
    tema_tf5(10) +
    theme(panel.grid.major.y = element_blank(), panel.grid.major.x = element_line(colour = REJILLA, linewidth = 0.3))
}

grafico_holgura <- function(curva, holg_hora, holg_inv = 0, horas = 6:8, titulo = NULL, subtitulo = NULL, pie = NULL) {
  d <- curva |> mutate(horizonte = ifelse(horizonte == "corto", "Primer año", "A 10 años"))
  hh <- holg_hora |> filter(hora %in% .env$horas) |>
    mutate(x = pmax(mediana, 0), lbl = sprintf("%02d h: %s", hora, pct_es(mediana, 0.1)),
           y = c(0.16, 0.04, 0.28, 0.40)[match(hora, .env$horas)])
  d$horizonte <- factor(d$horizonte, levels = c("Primer año", "A 10 años"))
  if (is.null(titulo)) titulo <- "El tercer carril rinde lo que deje el tramo siguiente"
  if (is.null(subtitulo)) subtitulo <- paste("Reducción de la demora de la mañana hacia Santa Cruz si el tramo siguiente (La Laguna) tuviera esa capacidad",
                                             "libre todo el rato. Línea: mediana de las simulaciones calibradas con los aforos horarios; banda: p10-p90.",
                                             "Líneas discontinuas: holgura mediana estimada a las 6, 7 y 8 h en 2025.")
  if (is.null(pie)) pie <- paste("Si el paso por Padre Anchieta tuviera 2 carriles efectivos (inventario del Cabildo), la holgura sería ~0",
                                 "y el tercer carril apenas reduciría la demora.")
  ggplot(d, aes(holgura, mediana, colour = horizonte, fill = horizonte)) +
    geom_vline(data = hh, aes(xintercept = x), colour = TINTA_MUTE, linetype = "22", linewidth = 0.4) +
    geom_label(data = hh, aes(x = x, y = y, label = lbl), inherit.aes = FALSE, hjust = -0.08, size = 2.8, colour = TINTA_2,
               fill = SUPERFICIE, label.size = 0) +
    geom_vline(xintercept = holg_inv, colour = "#c3c2b7", linewidth = 0.4) +
    geom_ribbon(aes(ymin = p10, ymax = p90), alpha = 0.12, colour = NA) +
    geom_line(linewidth = 0.9) +
    scale_colour_manual(values = c("Primer año" = PAL[["naranja"]], "A 10 años" = PAL[["azul"]])) +
    scale_fill_manual(values = c("Primer año" = PAL[["naranja"]], "A 10 años" = PAL[["azul"]])) +
    scale_x_continuous(labels = function(x) pct_es(x), breaks = seq(0, 0.5, 0.1)) +
    scale_y_continuous(labels = function(x) pct_es(x), limits = c(0, 1), oob = scales::squish) +
    labs(title = titulo, subtitle = envolver(subtitulo, 110),
         x = "Capacidad libre aguas abajo respecto al cuello actual", y = "Reducción de la demora",
         caption = envolver(pie, 150)) +
    tema_tf5(10)
}
