# =============================================================================
# 13_comparacion_y_trazabilidad.R · Comparación de alternativas y trazabilidad
# -----------------------------------------------------------------------------
#   1. Diferencias emparejadas entre alternativas: cada combinación calibrada de
#      parámetros se usa para todas las alternativas, así que la diferencia se mide
#      combinación a combinación (escenarios emparejados), con su incertidumbre.
#   2. Coste, plazo y riesgos de cada alternativa, por separado del efecto simulado.
#   3. Retrasos de obra del tercer carril (año de puesta en servicio).
#   4. Uso de la geometría: qué número de carriles entra en cada cálculo, de dónde
#      sale y qué supuesto lo sustituye cuando no está confirmado.
#   5. Correspondencia entre los campos de los ficheros oficiales y los del proyecto.
#   6. Días atípicos: motivo de cada exclusión o marca y sensibilidad sin ellos.
#   7. Cola remanente aguas abajo con almacenamiento finito y bloqueo de ramales.
#   8. Metadatos de los gráficos: tipo de resultado, horizonte, hipótesis e incertidumbre.
# =============================================================================

# ---- 1. Diferencias emparejadas ------------------------------------------------------
ALTERNATIVAS_PAR <- c("tercer_carril", "ramp_metering", "escalonamiento", "paquete_gestion")
# Umbral de diferencia material, fijado de antemano: una diferencia de reducción de la
# demora de menos de 2 puntos no distingue dos alternativas (el error de muestreo de una
# mediana llega a varios puntos y los supuestos de la literatura pesan más)
UMBRAL_DIFERENCIA <- 0.02

diferencias_emparejadas <- function(mc, caso = "", etiquetas = ETIQUETAS_ESC, n_boot = 300, semilla = 81) {
  r <- mc$resultados |> filter(escenario != "base") |> select(sim, escenario, reduccion)
  w <- tidyr::pivot_wider(r, names_from = escenario, values_from = reduccion)
  alt_de <- function(e) sub("_(corto|medio|largo)$", "", e)
  out <- list()
  for (h in HORIZONTES) {
    cols <- paste0(ALTERNATIVAS_PAR, "_", h); cols <- cols[cols %in% names(w)]
    if (h == "corto" && "tarificacion" %in% names(w)) cols <- c(cols, "tarificacion")
    if (length(cols) < 2) next
    for (pp in utils::combn(cols, 2, simplify = FALSE)) {
      a <- w[[pp[1]]]; b <- w[[pp[2]]]; ok <- !is.na(a) & !is.na(b)
      dif <- a[ok] - b[ok]
      set.seed(semilla)
      bt <- vapply(seq_len(n_boot), function(k) stats::median(dif[sample.int(length(dif), length(dif), replace = TRUE)]), numeric(1))
      q <- cuantil(dif, c(0.1, 0.5, 0.9))
      out[[length(out) + 1]] <- tibble(
        caso = caso, horizonte = h, alternativa_a = alt_de(pp[1]), alternativa_b = alt_de(pp[2]),
        etiqueta_a = unname(etiquetas[pp[1]]), etiqueta_b = unname(etiquetas[pp[2]]), combinaciones = sum(ok),
        mediana_a = stats::median(a[ok]), mediana_b = stats::median(b[ok]), dif_de_medianas = stats::median(a[ok]) - stats::median(b[ok]),
        dif_mediana = q[2], dif_p10 = q[1], dif_p90 = q[3], dif_media = mean(dif), ee_dif_mediana = stats::sd(bt),
        dif_relativa = q[2] / stats::median(b[ok]), parte_a_mayor = mean(dif > 1e-6),
        parte_casi_igual = mean(abs(dif) < UMBRAL_DIFERENCIA),
        orden_estable = q[1] > 1e-6 | q[3] < -1e-6)
    }
  }
  # Primero se descartan las diferencias no materiales (menos de 2 puntos, o casi iguales en
  # la mitad de las combinaciones) y las que no superan el error de muestreo; solo después se
  # dice si una alternativa reduce más en casi todas las combinaciones
  bind_rows(out) |>
    mutate(umbral_material = UMBRAL_DIFERENCIA,
           lectura = dplyr::case_when(
      abs(dif_mediana) < UMBRAL_DIFERENCIA | parte_casi_igual >= 0.5 ~
        "Sin diferencia material: la diferencia mediana es menor de 2 puntos o en la mitad de las combinaciones difieren menos de 2 puntos",
      abs(dif_mediana) < 2 * ee_dif_mediana ~ "Sin diferencia distinguible: la diferencia mediana es menor que dos veces su error de muestreo",
      orden_estable & dif_mediana > 0 ~ "A reduce más que B en al menos el 90 % de las combinaciones (p10 de la diferencia por encima de 0)",
      orden_estable & dif_mediana < 0 ~ "B reduce más que A en al menos el 90 % de las combinaciones (p90 de la diferencia por debajo de 0)",
      TRUE ~ "Depende de los parámetros: la banda p10-p90 de la diferencia cruza el 0"))
}

# La pareja clave con cada regla de calibración de la sensibilidad
diferencias_por_regla <- function(mc_todo, objetivo, caso = "", etiquetas = ETIQUETAS_ESC,
                                  a = "tercer_carril", b = "paquete_gestion") {
  bind_rows(lapply(reglas_calibracion(objetivo), function(r) {
    cal <- suppressMessages(calibrar_montecarlo(mc_todo, r$criterio, r$objetivo, if (is.null(r$espera)) c(10, 40) else r$espera,
                                                submuestra = !isTRUE(r$principal)))
    if (cal$n_validas < 20) return(NULL)
    diferencias_emparejadas(cal, caso, etiquetas) |> filter(alternativa_a == a, alternativa_b == b) |>
      mutate(regla = r$nombre, n_validas = cal$n_validas) |> relocate(caso, regla, n_validas)
  }))
}

# ---- 2. Coste, plazo y riesgos ---------------------------------------------------------
coste_plazo_riesgo <- function(ruta = file.path(DIR_DATOS, "coste_plazo_riesgo.csv")) {
  readr::read_csv(ruta, show_col_types = FALSE) |> mutate(categoria = "dato documental (coste y plazo) y valoración cualitativa (riesgos)")
}

# ---- 3. Retraso de la obra -------------------------------------------------------------
# Reducción de la demora el primer año de servicio del tercer carril según el año en que
# entre en servicio, con la demanda de ese año (crecimiento central y alto)
retraso_obra <- function(mc, caso, holg_h, anios = 2029:2032, crecimientos = c(0.005, 0.01), n_max = 1e5) {
  bind_rows(lapply(crecimientos, function(g) bind_rows(lapply(anios, function(a)
    alternativas_futuro(mc, caso, a, g, holg_h, TRUE, n_max = n_max) |>
      filter(escenario %in% c("base", "tercer_carril_corto", "paquete_gestion_corto")))))) |>
    mutate(categoria = "simulado (escenario condicionado)")
}

# ---- 4. Uso de la geometría ------------------------------------------------------------
# Cada cálculo que depende del número de carriles, con el valor usado, su fuente, su
# estado y el supuesto o escenario que lo cubre si no está confirmado
uso_geometria <- function(geo_cap, k_atasco = 140L) {
  g <- function(e, s, col) geo_cap[[col]][geo_cap$estacion_id == e & geo_cap$sentido == s][1]
  fila <- function(calculo, e, s, carriles, fuente, supuesto, escenario) {
    tibble(calculo = calculo, estacion = if (is.na(e)) NA_character_ else ESTACIONES_TF5$etiqueta[match(e, ESTACIONES_TF5$estacion_id)],
           sentido = s, carriles_usados = as.character(carriles),
           estado = if (is.na(e)) "no aplica" else g(e, s, "estado"),
           fuente = fuente, supuesto_explicito = supuesto, escenario_alternativo = escenario)
  }
  cat_ <- "Catálogo oficial de carriles de las estaciones de aforo (JSON del Cabildo, modificado el 02-07-2026)"
  bind_rows(
    fila("k crítico de cada estación (sección 3)", NA, "ambos", "los aforados de cada estación", cat_,
         "Carriles aforados = carriles efectivos del tramo", "k crítico con los carriles del inventario de 2006 (k_critico_geometria_alternativa.csv)"),
    fila("Capacidad del cuello de la mañana en el modelo", 103, "descendente", g(103, "descendente", "carriles_efectivos_modelo"),
         paste(cat_, "e inventario del PTEOSVAM (2006): coinciden"), "Capacidad por carril de 1.850-2.100 veh/h (aforos de 2025 y HCM)", "No hace falta: los dos inventarios coinciden"),
    fila("Capacidad del cuello de la tarde en el modelo (sale por Ermita Cruz Chica)", 103, "ascendente", g(103, "ascendente", "carriles_efectivos_modelo"),
         paste(cat_, "e inventario del PTEOSVAM (2006): coinciden"), "La cola se forma en Bomberos La Laguna (3 carriles) y descarga por 2", "No hace falta"),
    fila("Capacidad del tramo siguiente por la mañana (holgura)", 99, "descendente", "no se usan: capacidad = p99 del caudal aforado", "Aforos horarios de 2025 del Cabildo",
         "El p99 del caudal horario equivale a la capacidad del tramo", "p95 y p99,9; solo horas sin cola; carriles del inventario de 2006 en Campus Guajara (cota baja de 3 carriles) y en Padre Anchieta (holgura nula)"),
    fila("Capacidad del tramo siguiente por la tarde (holgura de La Matanza)", 111, "ascendente", "no se usan: capacidad = p99 del caudal aforado", "Aforos horarios de 2025 del Cabildo",
         "El p99 del caudal horario equivale a la capacidad del tramo", "p95 y p99,9; ramales desconocidos; holgura nula"),
    fila("Tercer carril de la mañana", 103, "descendente", "2 + 1", "Contrato del tercer carril Guamasa-Aeropuerto Norte (Gobierno de Canarias, 02-10-2026)",
         "El carril nuevo tiene la misma capacidad por carril que los actuales", "Tercer carril limitado por el tramo siguiente (holgura) y en serie con almacenamiento finito"),
    fila("Bus-VAO en Padre Anchieta hacia el Norte", 97, "ascendente", g(97, "ascendente", "carriles_efectivos_modelo"),
         paste(cat_, "e inventario del PTEOSVAM (2006): coinciden; proyecto del Cabildo (D-10)"), "El carril reservado no tiene cola", "No hace falta"),
    fila("Longitud equivalente de la cola de la mañana (indicadores de demora)", 111, "descendente", g(111, "descendente", "carriles_aforados"), cat_,
         sprintf("Densidad de atasco de %d veh/km por carril", k_atasco), "Solo orientativo: la cola puntual no ocupa espacio"),
    fila("Longitud equivalente de la cola de la tarde (indicadores de demora)", 99, "ascendente", g(99, "ascendente", "carriles_aforados"), cat_,
         sprintf("Densidad de atasco de %d veh/km por carril", k_atasco), "Solo orientativo"),
    fila("Almacenamiento entre el cuello de la mañana y el tramo siguiente (cálculo en serie)", 99, "descendente", "3 (supuesto)",
         "Sin puntos kilométricos publicados de las estaciones: la longitud es un supuesto",
         sprintf("1, 2 o 4 km x 3 carriles x %d veh/km", k_atasco), "Tres longitudes de almacenamiento (cola_remanente_aguas_abajo.csv)"),
    fila("Balance entre estaciones", NA, "ambos", "no se usan", "Aforos horarios del Cabildo",
         "La diferencia de caudal mezcla ramales sin aforar, cambios de carril, desfase entre detectores y errores de los aforadores: es descriptiva",
         "No entra en ningún cálculo del modelo")) |>
    mutate(tiene_procedencia_o_supuesto = nzchar(fuente) & nzchar(supuesto_explicito))
}

# ---- 5. Correspondencia de campos --------------------------------------------------------
correspondencia_campos <- function(dir = file.path(DIR_DATOS, "oficial")) {
  dic <- function(f) {
    d <- jsonlite::fromJSON(file.path(dir, f), simplifyVector = FALSE)
    stats::setNames(vapply(d$tableSchema$columns, function(x) x$`dc:description` %||% "", character(1)),
                    vapply(d$tableSchema$columns, function(x) x$name, character(1)))
  }
  hor <- dic("diccionario-de-datos-de-intensidad-diaria-de-trafico.json")
  imd <- dic("diccionario-de-datos-de-intensidad-media-diaria-imd.json")
  car <- dic("diccionario-de-datos-de-rango-de-velocidades-de-los-carriles.json")
  m_hor <- c(estacion_id = "estacion_id", estacion_nombre = "no se guarda (nombre de ESTACIONES_TF5)", carril_id = "carril_id; sentido = ascendente (hacia el Norte) si > 0, descendente (hacia Santa Cruz) si < 0",
             carril_descripcion = "no se guarda (tipo de carril del catálogo de carriles)", fecha = "dia, hora (hora de inicio del registro), mes, anio",
             ligeros = "veh = ligeros + pesados", pesados = "pesados (y veh)", rango1_vehiculos = "lento (vehículos a menos de 80 km/h, rango 1) y rsum",
             rango2_vehiculos = "rsum", rango3_vehiculos = "rsum", rango4_vehiculos = "rsum", rango5_vehiculos = "rsum", rango6_vehiculos = "rsum")
  m_imd <- c(carretera_codigo = "filtro: TF-5", tramo_nombre = "tramo (descriptivo)", estacion_id = "estacion_id", estacion_nombre = "etiqueta (ESTACIONES_TF5)",
             velocidad_media = "velocidad_media", imd_ascendentes = "imd_ascendentes (hacia el Norte)", imd_descendentes = "imd_descendentes (hacia Santa Cruz)",
             imd_total = "imd_total", imd_pesados = "imd_pesados")
  f <- function(fuente, d, m) tibble(fuente = fuente, campo_original = names(d), definicion_oficial = unname(d),
                                     campo_en_el_proyecto = unname(ifelse(names(d) %in% names(m), m[names(d)], "no se usa")))
  bind_rows(f("Intensidad diaria de tráfico (TXT horarios por carril)", hor, m_hor),
            f("Intensidad media diaria (IMD, CSV anual)", imd, m_imd),
            f("Rangos de velocidades de los carriles (JSON)", car, c(estacion_id = "estacion_id", carril_id = "carril_id",
                                                                    carril_descripcion = "tipo (principal, enlace, bus...) y carriles por sentido",
                                                                    rango1_max = "rango1_max (límite del rango 1: 80 km/h en la TF-5)")))
}
`%||%` <- function(a, b) if (is.null(a)) b else a

# ---- 5b. Contraste con la publicación original, fuera del proyecto ---------------------------
# Muestra contrastada el 16-10-2026 con el catálogo nacional de datos abiertos (datos.gob.es),
# que federa el portal del Cabildo: los 12 TXT horarios de 2025 y su diccionario. Para cada
# recurso se comprueba que la URL publicada es la que se usó al descargar, que el identificador
# y el nombre están en la instantánea del catálogo del portal y que la licencia del conjunto
# coincide. La fecha de modificación del conjunto se compara aparte (los dos catálogos pueden
# usar zonas horarias distintas). No compara valores: eso exige volver a descargar los ficheros
# (DESCARGAR_HORARIOS <- TRUE en main.R).
contraste_publicacion_original <- function(ruta = file.path(DIR_DATOS, "contraste_catalogo_nacional_2026-10-16.csv"),
                                           dir = DIR_DATOS, ruta_catalogo = ultimo_catalogo(file.path(dir, "oficial"))) {
  pub <- readr::read_csv(ruta, show_col_types = FALSE, col_types = readr::cols(.default = readr::col_character()))
  fh <- readr::read_csv(file.path(dir, "fuentes_horarias.csv"), show_col_types = FALSE, col_types = readr::cols(.default = readr::col_character()))
  man <- jsonlite::fromJSON(file.path(dir, "oficial", "manifiesto_oficiales.json"))$ficheros
  usadas <- c(fh$url_fuente, man$url)
  catp <- leer_catalogo_portal(ruta_catalogo)
  conj <- catp |> filter(conjunto == pub$conjunto[1])
  mod_portal <- as.POSIXct(sub("\\..*$", "", conj$conjunto_modificado[1]), format = "%Y-%m-%dT%H:%M:%S", tz = "UTC")
  mod_nacional <- as.POSIXct(pub$conjunto_modificado_utc, format = "%Y-%m-%d %H:%M", tz = "UTC")
  pub |> mutate(
    url_usada_al_descargar = url_publicada %in% usadas,
    en_la_instantanea_del_portal = recurso_id %in% catp$resource_id,
    nombre_igual = coalesce(catp$nombre[match(recurso_id, catp$resource_id)] == nombre_publicado, FALSE),
    licencia_igual = grepl("cc-by", licencia_publicada, fixed = TRUE) & identical(conj$licencia_catalogo[1], "cc-by"),
    modificacion_conjunto_portal = format(mod_portal, "%Y-%m-%d %H:%M"),
    diferencia_modificacion_h = round(as.numeric(difftime(mod_portal, mod_nacional, units = "hours")), 2),
    resultado = ifelse(url_usada_al_descargar & en_la_instantanea_del_portal & nombre_igual & licencia_igual, "coincide", "no coincide"),
    categoria = "observado (contraste documental)")
}

# ---- 6. Días atípicos ----------------------------------------------------------------------
# Domingo de Pascua (algoritmo anónimo gregoriano, Meeus/Jones/Butcher)
domingo_pascua <- function(anio) {
  a <- anio %% 19; b <- anio %/% 100; c <- anio %% 100; d <- b %/% 4; e <- b %% 4; f <- (b + 8) %/% 25
  g <- (b - f + 1) %/% 3; h <- (19 * a + b - d - g + 15) %% 30; i <- c %/% 4; k <- c %% 4
  l <- (32 + 2 * e + 2 * i - h - k) %% 7; m <- (a + 11 * h + 22 * l) %/% 451
  mes <- (h + l - 7 * m + 114) %/% 31; dia <- ((h + l - 7 * m + 114) %% 31) + 1
  as.Date(sprintf("%d-%02d-%02d", anio, mes, dia))
}

# Una fila por estación, sentido y día laborable: si se usa y, si no, por qué; y las marcas
# de días que se usan pero pueden ser atípicos (puentes, Navidad, Semana Santa y días con la
# punta anómala, posible incidente u obra). Los incidentes y las obras tienen un registro público
# del Cabildo que no se ha incorporado (matriz de lagunas, D09); la lluvia, ninguno incorporado (D15).
dias_atipicos <- function(sd, dv, festivos, ch, ventanas = list("103|descendente" = 6:9, "99|ascendente" = 13:18)) {
  fest <- as.Date(festivos$fecha)
  dias <- sd |> filter(laborable) |> group_by(estacion_id, sentido, anio, mes, dia) |>
    summarise(horas = n(), completas = sum(completa), total = sum(veh), .groups = "drop") |>
    left_join(dv |> transmute(estacion_id, sentido, dia, valido = TRUE), by = c("estacion_id", "sentido", "dia")) |>
    mutate(valido = coalesce(valido, FALSE))
  med_mes <- dias |> filter(horas == 24, completas == 24) |> group_by(estacion_id, sentido, mes) |> summarise(mediana_mes = stats::median(total), .groups = "drop")
  pascua <- domingo_pascua(sort(unique(as.integer(format(dias$dia, "%Y")))))
  semana_santa <- as.Date(unlist(lapply(pascua, function(p) as.character(p - (6:2)))))
  navidad <- function(d) (format(d, "%m-%d") >= "12-24") | (format(d, "%m-%d") <= "01-06")
  dow <- as.integer(format(dias$dia, "%u"))
  puente <- (dow == 1 & (dias$dia + 1) %in% fest) | (dow == 5 & (dias$dia - 1) %in% fest) |
            (dow %in% 2:4 & (dias$dia - 1) %in% fest & (dias$dia + 1) %in% fest)
  dias <- dias |> left_join(med_mes, by = c("estacion_id", "sentido", "mes")) |>
    mutate(cambio_hora = dia %in% ch$dia[ch$cambio_de_hora != ""], puente = puente, semana_santa = dia %in% semana_santa,
           navidad = navidad(dia), agosto = substr(mes, 6, 7) == "08",
           motivo_exclusion = dplyr::case_when(
             cambio_hora ~ "Día de cambio de hora (marcas horarias que faltan o se repiten)",
             horas < 24 | completas < 24 ~ "Día incompleto: faltan horas o algún carril (avería o corte del aforador)",
             agosto ~ "Agosto (vacaciones; fuera del análisis por diseño)",
             !valido ~ "Tráfico del día por debajo del 85 % de la mediana del mes (posible incidencia, festivo local o fallo del aforador)",
             TRUE ~ ""))
  # Punta anómala en los días que se usan: caudal de la ventana de la punta más de tres
  # desviaciones absolutas medianas (escaladas) por debajo de la mediana de los días válidos
  # del mismo mes (posible incidente u obra). Es un criterio de valor atípico: no marca un
  # número fijo de días por mes.
  pun <- bind_rows(lapply(names(ventanas), function(k) {
    e <- as.numeric(sub("\\|.*", "", k)); s <- sub(".*\\|", "", k)
    sd |> filter(estacion_id == e, sentido == s, hora %in% ventanas[[k]]) |> group_by(estacion_id, sentido, mes, dia) |>
      summarise(punta = sum(veh), .groups = "drop")
  }))
  dias <- dias |> left_join(pun, by = c("estacion_id", "sentido", "mes", "dia")) |>
    group_by(estacion_id, sentido, mes) |>
    mutate(umbral_punta = if (sum(valido & !is.na(punta)) >= 5)
             stats::median(punta[valido], na.rm = TRUE) - 3 * stats::mad(punta[valido], na.rm = TRUE) else NA_real_) |> ungroup() |>
    mutate(punta_anomala = valido & !is.na(punta) & !is.na(umbral_punta) & punta < umbral_punta,
           marca = trimws(paste0(ifelse(puente, "puente; ", ""), ifelse(semana_santa, "Semana Santa; ", ""), ifelse(navidad, "Navidad; ", ""),
                                 ifelse(punta_anomala, "punta anómala (posible incidente u obra); ", ""))),
           estado = ifelse(motivo_exclusion == "", "usado", "excluido"),
           lluvia = "sin dato incorporado (D15)", incidentes_y_obras = "registro público del Cabildo no incorporado (D09)")
  dias |> left_join(ESTACIONES_TF5 |> select(estacion_id, etiqueta), by = "estacion_id") |>
    select(estacion_id, etiqueta, sentido, dia, estado, motivo_exclusion, marca, puente, semana_santa, navidad, punta_anomala,
           total, mediana_mes, lluvia, incidentes_y_obras) |>
    arrange(estacion_id, sentido, dia)
}

resumen_dias_atipicos <- function(da) {
  bind_rows(
    da |> filter(estado == "excluido") |> count(etiqueta, sentido, motivo = motivo_exclusion, name = "dias") |> mutate(tratamiento = "excluido"),
    da |> filter(estado == "usado", nzchar(marca)) |> tidyr::separate_rows(marca, sep = ";\\s*") |> filter(nzchar(marca)) |>
      count(etiqueta, sentido, motivo = marca, name = "dias") |> mutate(tratamiento = "usado y marcado (se prueba sin ellos)")) |>
    arrange(etiqueta, sentido, tratamiento, desc(dias))
}

# Indicadores medidos sin los días marcados como atípicos (los que se usan). Para cada cuello
# se quitan los días con las marcas de su estación y sentido (las de calendario son comunes),
# en todas las estaciones que entran en sus indicadores (cola y salida).
sensibilidad_sin_atipicos <- function(sc, da, casos = list(list(103, "descendente", 3:12, 103), list(99, "ascendente", 11:23, 103)), anio = 2025) {
  calendario <- unique(da$dia[da$puente | da$navidad | da$semana_santa])
  variantes <- list("Todos los días válidos (principal)" = function(e, s) as.Date(character()),
                    "Sin puentes, Navidad ni Semana Santa" = function(e, s) calendario,
                    "Sin días con la punta anómala" = function(e, s) unique(da$dia[da$estacion_id == e & da$sentido == s & da$punta_anomala]),
                    "Sin ningún día marcado" = function(e, s) unique(c(calendario, da$dia[da$estacion_id == e & da$sentido == s & da$punta_anomala])))
  bind_rows(lapply(names(variantes), function(nm) bind_rows(lapply(casos, function(z) {
    quitar <- variantes[[nm]](z[[1]], z[[2]])
    scx <- sc |> filter(!dia %in% quitar)
    hc <- horario_cola(scx, z[[1]], z[[2]], anio, z[[3]])
    desc <- if (z[[1]] == 103) scx |> filter(anio == !!anio, estacion_id == 103, sentido == z[[2]], congestionada, hora %in% z[[3]]) |> pull(veh)
            else descarga_en_horas_de_cola(scx, z[[1]], z[[2]], z[[4]], anio) |> filter(hora %in% z[[3]]) |> pull(veh)
    tibble(variante = nm, estacion_id = z[[1]], sentido = z[[2]], dias = nrow(hc), horas_cola_media = mean(hc$horas_cola),
           horas_cola_mediana = stats::median(hc$horas_cola), inicio_mediana = stats::median(hc$inicio, na.rm = TRUE),
           fin_mediana = stats::median(hc$fin, na.rm = TRUE), descarga_mediana = stats::median(desc))
  })))) |> left_join(ESTACIONES_TF5 |> select(estacion_id, etiqueta), by = "estacion_id") |> relocate(variante, estacion_id, etiqueta)
}

# ---- 7. Cola remanente aguas abajo: dos cuellos en serie -----------------------------------
# Para una submuestra de combinaciones calibradas de la mañana: situación actual y tercer
# carril (primer año, con la demanda inducida resuelta en el modelo principal) en serie con el
# tramo siguiente, con su capacidad hora a hora (descarga actual x (1 + holgura) + entradas) y
# las entradas netas de los ramales entre los dos (mediana de cada hora). Se comparan tres
# longitudes de almacenamiento con el modelo principal (almacenamiento nulo).
cola_remanente <- function(mc, holg_h, longitudes_km = c(1, 2, 4), carriles_tramo = 3, k_atasco = 140, n_max = 200, semilla = 91) {
  set.seed(semilla)
  d <- mc$draws; if (nrow(d) > n_max) d <- d[sort(sample.int(nrow(d), n_max)), ]
  ent <- holg_h |> group_by(hora) |> summarise(entradas = stats::median(entradas_netas), .groups = "drop")
  r_h <- rep(0, 24); r_h[ent$hora + 1] <- pmax(ent$entradas, 0)
  r_min <- rep(r_h / 60, each = 60)
  HH <- matriz_holgura_horaria(holg_h)
  filas <- list()
  for (i in seq_len(nrow(d))) {
    p <- as.list(d[i, ]); prof <- perfil_de(p, mc$V_dir, mc$perfil_obs)
    ht <- holgura_minutos(HH, p$holgura_cuantil)
    fc <- if (is.null(prof$f_cap)) 1 else prof$f_cap
    fa <- if (is.null(prof$f_desc)) 1 else prof$f_desc
    # Lo que admite el tramo siguiente del tronco, igual que en el modelo principal (descarga
    # del modelo en esa hora x (1 + holgura)), más las entradas de los ramales (veh/h)
    desc0 <- mc$carriles * p$c_carril * (1 - p$caida_capacidad)
    capB <- desc0 * fc * fa * (1 + ht) + r_min * 60
    e <- escenarios_cuello(p, mc$V_dir, mc$carriles, TRUE, prof = prof, holgura_t = ht)
    lam_tc <- e$tercer_carril_corto$lambda
    lam_b <- e$base$lambda
    preA0 <- mc$carriles * p$c_carril * fc; preA1 <- (mc$carriles + 1) * p$c_carril * fc
    for (L in c(0, longitudes_km)) {
      N <- L * carriles_tramo * k_atasco
      b0 <- resumen_tandem(simular_tandem(lam_b, preA0, 1 - (1 - p$caida_capacidad) * fa, capB, r_min, N))
      b1 <- resumen_tandem(simular_tandem(lam_tc, preA1, 1 - (1 - p$caida_capacidad) * fa, capB, r_min, N))
      filas[[length(filas) + 1]] <- tibble(sim = d$sim[i], longitud_km = L, almacenamiento_veh = N,
                                           demora_actual_vh = b0$demora_vh, demora_tercer_carril_vh = b1$demora_vh,
                                           ramales_tercer_carril_vh = b1$demora_ramales_vh, ramales_actual_vh = b0$demora_ramales_vh,
                                           cola_remanente_max = b1$cola_B_max, minutos_rebose = b1$minutos_rebose,
                                           reduccion_modelo_principal = 1 - e$tercer_carril_corto$demora_vh / e$base$demora_vh)
    }
  }
  bind_rows(filas) |> mutate(reduccion_en_serie = 1 - demora_tercer_carril_vh / demora_actual_vh) |>
    group_by(longitud_km, almacenamiento_veh) |>
    summarise(simulaciones = n(), reduccion_mediana = stats::median(reduccion_en_serie), reduccion_p10 = cuantil(reduccion_en_serie, 0.1),
              reduccion_p90 = cuantil(reduccion_en_serie, 0.9), reduccion_modelo_principal = stats::median(reduccion_modelo_principal),
              cola_remanente_max_mediana = stats::median(cola_remanente_max), minutos_rebose_mediana = stats::median(minutos_rebose),
              demora_ramales_tercer_carril_vh = stats::median(ramales_tercer_carril_vh), demora_ramales_actual_vh = stats::median(ramales_actual_vh),
              .groups = "drop") |>
    mutate(supuesto = ifelse(longitud_km == 0, "Almacenamiento nulo: la cola de abajo frena el cuello al instante (como el modelo principal con propagación)",
                             sprintf("%s km x %d carriles x %d veh/km por carril (longitud supuesta: no hay puntos kilométricos publicados)",
                                     num_es(longitud_km, 0.1), carriles_tramo, k_atasco)),
           categoria = "simulado (comprobación)")
}

# ---- 8. Metadatos de los gráficos ---------------------------------------------------------------
metadatos_graficos <- function(ruta = file.path(DIR_DATOS, "graficos_metadatos.csv"), dir_graficos = DIR_GRAFICOS) {
  m <- readr::read_csv(ruta, show_col_types = FALSE)
  pngs <- sub("\\.png$", "", list.files(dir_graficos, pattern = "\\.png$"))
  m |> mutate(generado = grafico %in% pngs)
}

# ---- g21 · Diferencia emparejada: tercer carril frente a regulación + escalonamiento ----
grafico_diferencias_emparejadas <- function(dem) {
  nombre_caso <- c(manana_hacia_santa_cruz = "Mañana hacia Santa Cruz (tercer carril contratado)",
                   tarde_hacia_el_norte = "Tarde hacia el Norte (tercer carril hipotético)")
  d <- dem |> filter(alternativa_a == "tercer_carril", alternativa_b == "paquete_gestion") |>
    mutate(caso = unname(nombre_caso[caso]),
           horizonte = factor(c(corto = "1er año", medio = "A 5 años", largo = "A 10 años")[horizonte], levels = c("A 10 años", "A 5 años", "1er año")),
           texto = sprintf("%s pt; el tercer carril reduce más en el %s de las combinaciones", num_es(100 * dif_mediana, 0.1), pct_es(parte_a_mayor)))
  ggplot(d, aes(y = horizonte)) +
    geom_vline(xintercept = 0, colour = TINTA_MUTE, linewidth = 0.4) +
    geom_segment(aes(x = dif_p10, xend = dif_p90, yend = horizonte), colour = PAL[["azul"]], linewidth = 1) +
    geom_point(aes(x = dif_mediana), colour = PAL[["azul"]], size = 3) +
    geom_text(aes(x = dif_p90, label = texto), hjust = -0.05, size = 2.9, colour = TINTA_2) +
    facet_wrap(~caso, ncol = 1) +
    scale_x_continuous(labels = function(x) paste(num_es(100 * x), "pt"), expand = expansion(mult = c(0.05, 0.9))) +
    labs(title = "Tercer carril frente a regulación de accesos + escalonamiento: la diferencia combinación a combinación",
         subtitle = envolver(paste("Reducción de la demora del tercer carril menos la del paquete de gestión, calculada con la misma combinación de parámetros",
                                   "para las dos (escenarios emparejados). Punto: mediana de las diferencias; línea: banda p10-p90 de las combinaciones calibradas",
                                   "(incertidumbre de los parámetros, no una probabilidad). Si la línea cruza el 0, el orden depende de los parámetros."), 112),
         x = "Diferencia de la reducción de la demora (puntos porcentuales)", y = NULL,
         caption = envolver("Simulado. Coste, plazo y riesgos de cada alternativa, por separado, en coste_plazo_riesgo.csv; tabla completa en diferencias_emparejadas.csv.", 150)) +
    tema_tf5(10) + theme(panel.grid.major.y = element_blank(), panel.grid.major.x = element_line(colour = REJILLA, linewidth = 0.3))
}
