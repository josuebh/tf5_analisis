# =============================================================================
# 02_descriptivo.R · ¿Qué dicen los aforos oficiales de la TF-5?
# =============================================================================

resumen_evolucion <- function(imd) {
  imd |>
    filter(anio %in% c(2019, 2025)) |>
    select(estacion_id, etiqueta, orden, anio, imd_total) |>
    pivot_wider(names_from = anio, values_from = imd_total, names_prefix = "imd_") |>
    mutate(var_2019_2025 = imd_2025 / imd_2019 - 1,
           tcam_2019_2025 = (imd_2025 / imd_2019)^(1 / 6) - 1) |>
    arrange(orden)
}

# ---- g01 · Perfil del corredor en 2025 por sentido ---------------------------
grafico_perfil_corredor <- function(imd, anio_ref = 2025, tramo_obra = NULL) {
  d <- imd |>
    filter(anio == anio_ref, !is.na(imd_ascendentes)) |>
    select(etiqueta, orden, imd_ascendentes, imd_descendentes, imd_total) |>
    pivot_longer(c(imd_ascendentes, imd_descendentes), names_to = "sentido", values_to = "imd") |>
    mutate(sentido = recode(sentido,
                            imd_ascendentes  = "Ascendente (hacia el Norte)",
                            imd_descendentes = "Descendente (hacia Santa Cruz)"),
           etiqueta = factor(etiqueta, levels = rev(ESTACIONES_TF5$etiqueta)))
  maximo <- imd |> filter(anio == anio_ref) |> slice_max(imd_total, n = 1)

  p <- ggplot(d, aes(x = imd, y = etiqueta, fill = sentido)) +
    scale_y_discrete()                                   # fija el eje como discreto
  if (!is.null(tramo_obra)) {
    p <- p + annotate("rect", xmin = -Inf, xmax = Inf,
                      ymin = tramo_obra$ymin, ymax = tramo_obra$ymax,
                      fill = "#f0efec", colour = NA) +
      annotate("text", x = 47500, y = (tramo_obra$ymin + tramo_obra$ymax) / 2, label = tramo_obra$texto,
               hjust = 0, vjust = 0.5, size = 2.9, colour = TINTA_2, lineheight = 0.95)
  }
  p +
    geom_col(position = position_dodge(width = 0.72), width = 0.62) +
    scale_fill_manual(values = c(PAL[["azul"]], PAL[["naranja"]])) +
    scale_x_continuous(labels = function(x) num_es(x), expand = expansion(mult = c(0, 0.16))) +
    labs(title = paste0("TF-5: tráfico medio diario por sentido y estación de aforo (", anio_ref, ")"),
         subtitle = envolver(sprintf("Máximo en %s: %s vehículos/día (ambos sentidos). Estaciones ordenadas de Santa Cruz (arriba) al oeste.",
                            maximo$etiqueta, num_es(maximo$imd_total)), 110),
         x = "Vehículos al día (IMD)", y = NULL, caption = FUENTE_IMD) +
    tema_tf5() +
    theme(panel.grid.major.y = element_blank(),
          panel.grid.major.x = element_line(colour = REJILLA, linewidth = 0.3))
}

# ---- g02 · Evolución 2018-2025 en las estaciones clave -----------------------
grafico_evolucion <- function(imd, estaciones = c(93, 97, 99, 103, 111, 123)) {
  ev <- resumen_evolucion(imd) |> filter(estacion_id %in% estaciones)
  d <- imd |>
    filter(estacion_id %in% estaciones) |>
    select(anio, estacion_id, etiqueta, orden, imd_total) |>
    complete(anio = 2018:2025, nesting(estacion_id, etiqueta, orden)) |>
    left_join(ev |> select(estacion_id, var_2019_2025), by = "estacion_id") |>
    mutate(panel = sprintf("%s  (%s%s 2019→2025)", etiqueta,
                           ifelse(var_2019_2025 >= 0, "+", ""), pct_es(var_2019_2025, 0.1)),
           panel = reorder(panel, orden))

  ggplot(d, aes(anio, imd_total)) +
    annotate("rect", xmin = 2019.5, xmax = 2021.5, ymin = -Inf, ymax = Inf,
             fill = "#f0efec", colour = NA) +
    geom_line(colour = PAL[["azul"]], linewidth = 0.8, na.rm = TRUE) +
    geom_point(colour = PAL[["azul"]], size = 1.8, na.rm = TRUE) +
    facet_wrap(~panel, ncol = 2) +
    scale_y_continuous(labels = function(x) num_es(x / 1000), limits = c(40000, 125000),
                       breaks = seq(40000, 120000, 20000)) +
    scale_x_continuous(breaks = 2018:2025, labels = c("18", "19", "20", "21", "22", "23", "24", "25")) +
    labs(title = "El tráfico diario de la TF-5 apenas ha variado desde 2019",
         subtitle = envolver(paste("IMD total en miles de vehículos/día; entre paréntesis, variación 2019-2025.",
                                   "Banda gris: años COVID (2020-2021). Hueco en 2024: Padre Anchieta no publicó datos ese año."), 105),
         x = NULL, y = "Miles de vehículos/día", caption = FUENTE_IMD) +
    tema_tf5(10)
}

# ---- g03 · La TF-5 frente a sus alternativas en el norte ---------------------
grafico_alternativas <- function(imd, ctx) {
  tf5 <- imd |> filter(anio == 2025, estacion_id %in% c(97, 99, 103, 111)) |>
    transmute(carretera_codigo, nombre = etiqueta, imd_total)
  alt <- ctx |>
    filter(carretera_codigo %in% c("TF-152", "TF-217"), imd_total > 0,
           estacion_id %in% c(426, 427, 429, 431, 435, 437, 445, 495, 500)) |>
    transmute(carretera_codigo, nombre = stringr_title(estacion_nombre), imd_total)
  d <- bind_rows(tf5, alt) |>
    mutate(lbl = paste0(carretera_codigo, " · ", nombre),
           lbl = reorder(lbl, imd_total),
           carretera_codigo = factor(carretera_codigo, levels = c("TF-5", "TF-152", "TF-217")))
  diez_pct <- 0.10 * imd$imd_total[imd$anio == 2025 & imd$estacion_id == 97]
  ref_152 <- ctx$imd_total[ctx$estacion_id == 431]

  ggplot(d, aes(imd_total, lbl, fill = carretera_codigo)) +
    geom_col(width = 0.6) +
    geom_text(aes(label = num_es(imd_total)), hjust = -0.12, size = 3, colour = TINTA_2) +
    scale_fill_manual(values = c(PAL[["azul"]], PAL[["naranja"]], PAL[["aqua"]])) +
    scale_x_continuous(labels = function(x) num_es(x), expand = expansion(mult = c(0, 0.12))) +
    labs(title = "Las carreteras alternativas mueven una décima parte que la TF-5",
         subtitle = sprintf("Un 10 %% del tráfico de la TF-5 en Padre Anchieta (%s veh/día) equivale a toda la IMD\nde la TF-152 en Ermita Cruz Chica (%s veh/día): cualquier desvío masivo las colapsaría.",
                            num_es(diez_pct), num_es(ref_152)),
         x = "Vehículos al día (IMD 2025)", y = NULL,
         caption = envolver(paste(FUENTE_IMD, "Se excluye la estación TF-152 «Tacoronte Abales» (IMD publicada = 0, dato ausente)."), 150)) +
    tema_tf5() +
    theme(panel.grid.major.y = element_blank(),
          panel.grid.major.x = element_line(colour = REJILLA, linewidth = 0.3))
}

stringr_title <- function(x) {
  x <- tolower(x)
  x <- gsub("(^|[ (.-])([a-záéíóúñ])", "\\1\\U\\2", x, perl = TRUE)
  x <- gsub(" (De|La|Del|El|Los|Las) ", " \\L\\1 ", x, perl = TRUE)   # artículos en minúscula
  gsub("Tf-", "TF-", x)
}

# ---- g04 · Mapa de calidad de los datos ---------------------------------------
grafico_calidad <- function(imd, flags) {
  peor <- flags |>
    mutate(nivel = factor(gravedad, levels = c("info", "aviso", "error"), ordered = TRUE),
           cod = sub(" .*", "", regla)) |>
    group_by(anio, estacion_id) |>
    summarise(nivel = max(nivel),
              codigos = paste(unique(cod)[order(as.integer(sub("R", "", unique(cod))))], collapse = " "),
              .groups = "drop")
  d <- tidyr::expand_grid(anio = 2018:2025, estacion_id = ESTACIONES_TF5$estacion_id) |>
    left_join(ESTACIONES_TF5, by = "estacion_id") |>
    left_join(peor, by = c("anio", "estacion_id")) |>
    mutate(nivel = as.character(nivel),
           nivel = ifelse(is.na(nivel), "sin incidencias", nivel),
           nivel = factor(nivel, levels = c("sin incidencias", "info", "aviso", "error")),
           etiqueta = factor(etiqueta, levels = rev(ESTACIONES_TF5$etiqueta)))

  ggplot(d, aes(factor(anio), etiqueta, fill = nivel)) +
    geom_tile(colour = SUPERFICIE, linewidth = 1.2) +
    geom_text(aes(label = ifelse(is.na(codigos), "", codigos)), size = 2.3, colour = TINTA) +
    scale_fill_manual(values = c("sin incidencias" = "#eeeee9", info = "#c3c2b7",
                                 aviso = ESTADO[["aviso"]], error = ESTADO[["critico"]]),
                      drop = FALSE) +
    labs(title = "Validación automática de los aforos de la TF-5 (10 reglas)",
         subtitle = "Códigos de regla en cada celda. R1 (sentidos ≠ total) no falla en ninguna fila: los datos son coherentes internamente.",
         x = NULL, y = NULL,
         caption = envolver(paste0("R2 sin desglose por sentido · R3 velocidad no medida · R4 velocidad media > 120 km/h · ",
                          "R5 % pesados atípico · R6 estación sin datos · R7 salto interanual > 15 % · R8 velocidad repetida entre años · ",
                          "R9 asimetría extrema · R10 % pesados inestable. ", FUENTE_IMD), 150)) +
    tema_tf5(10) +
    theme(panel.grid.major.y = element_blank(), axis.line.x = element_blank())
}

# ---- g10 · Transporte público frente a tráfico en la TF-5 (índice 2019 = 100) --
grafico_tp_vs_tf5 <- function(imd, tp, estaciones = c(93, 99, 103, 111)) {
  tf5 <- imd |>
    filter(estacion_id %in% estaciones) |>
    group_by(anio) |>
    summarise(valor = mean(imd_total), n = n(), .groups = "drop") |>
    filter(n == length(estaciones)) |>
    mutate(serie = "Tráfico en la TF-5 (IMD media de 4 estaciones)")
  tpub <- tp |>
    transmute(anio, valor = viajeros,
              serie = ifelse(operador == "TITSA", "Viajeros de TITSA (guaguas)",
                             "Viajeros del tranvía"))
  niveles <- c("Viajeros de TITSA (guaguas)", "Viajeros del tranvía",
               "Tráfico en la TF-5 (IMD media de 4 estaciones)")
  d <- bind_rows(tf5 |> select(anio, valor, serie), tpub) |>
    group_by(serie) |>
    mutate(indice = 100 * valor / valor[anio == 2019]) |>
    ungroup() |>
    mutate(serie = factor(serie, levels = niveles))
  fin <- d |> group_by(serie) |> filter(anio == max(anio)) |> ungroup()
  ggplot(d, aes(anio, indice, colour = serie)) +
    annotate("rect", xmin = 2022.5, xmax = 2025.5, ymin = -Inf, ymax = Inf, fill = "#f0efec", colour = NA) +
    annotate("text", x = 2022.6, y = 205, label = "Transporte público gratuito\npara residentes (desde 2023)",
             hjust = 0, vjust = 1, size = 2.9, colour = TINTA_2, lineheight = 0.95) +
    geom_hline(yintercept = 100, colour = "#c3c2b7", linewidth = 0.4) +
    geom_line(linewidth = 0.9) +
    geom_point(size = 1.9) +
    geom_text(data = fin, aes(label = num_es(indice)), hjust = -0.35, size = 3.2,
              colour = TINTA, show.legend = FALSE) +
    scale_colour_manual(values = setNames(unname(PAL[c("naranja", "aqua", "azul")]), niveles)) +
    scale_x_continuous(breaks = 2017:2025, expand = expansion(mult = c(0.02, 0.07))) +
    scale_y_continuous(limits = c(50, 210), breaks = seq(50, 200, 25)) +
    guides(colour = guide_legend(nrow = 2)) +
    labs(title = "La guagua casi duplicó viajeros desde 2019; el tráfico de la TF-5 no bajó",
         subtitle = "Índice 2019 = 100. El aforo de un tramo saturado mide lo que cabe, no lo que se querría circular.",
         x = NULL, y = "Índice (2019 = 100)",
         caption = envolver(paste("Fuentes: TITSA y Metrotenerife (notas y memorias anuales; algunos valores de 2018-2020 se deducen de",
                                  "las variaciones publicadas) y Cabildo de Tenerife (IMD de Campus Guajara, Bomberos La Laguna,",
                                  "Ermita Cruz Chica y La Matanza). Detalle en datos/transporte_publico_viajeros.csv."), 150)) +
    tema_tf5(10)
}
