# =============================================================================
# 03_saturacion.R · ¿Hay capacidad libre en la hora punta?
# -----------------------------------------------------------------------------
# Sin datos horarios, la IMD no dice directamente si un tramo se satura. Pero
# se puede calcular el «k crítico»: la fracción del tráfico diario de un sentido
# que tendría que concentrarse en la hora punta para llenar la capacidad.
#
#     k_crit = (carriles x capacidad por carril) / IMD del sentido
#
# Si el k_crit es MENOR que la fracción que la literatura observa en la hora
# punta de autovías urbanas (k_dir típico), el tramo está saturado en punta.
# =============================================================================

calcular_k_critico <- function(imd, carriles, par, anio_ref = 2025) {
  c_min <- par$minimo[par$parametro == "c_carril"]
  c_cen <- par$central[par$parametro == "c_carril"]
  c_max <- par$maximo[par$parametro == "c_carril"]
  imd |>
    filter(anio == anio_ref) |>
    select(estacion_id, etiqueta, orden, imd_ascendentes, imd_descendentes) |>
    pivot_longer(c(imd_ascendentes, imd_descendentes), names_to = "sentido", values_to = "imd_dir") |>
    mutate(sentido = ifelse(sentido == "imd_ascendentes", "ascendente", "descendente")) |>
    inner_join(carriles, by = c("estacion_id", "sentido")) |>
    mutate(cap_min = carriles * c_min, cap_cen = carriles * c_cen, cap_max = carriles * c_max,
           k_crit_min = cap_min / imd_dir,
           k_crit_cen = cap_cen / imd_dir,
           k_crit_max = cap_max / imd_dir)
}

grafico_k_critico <- function(kc, par) {
  k_lo <- par$minimo[par$parametro == "k_dir"]
  k_hi <- par$maximo[par$parametro == "k_dir"]
  d <- kc |>
    mutate(sent_lbl = ifelse(sentido == "ascendente", "Hacia el Norte", "Hacia Santa Cruz"),
           fila = paste0(etiqueta, " · ", sent_lbl, " (", carriles, " carriles)"),
           fila = reorder(fila, -orden + ifelse(sentido == "ascendente", 0.1, 0)))
  ggplot(d, aes(y = fila)) +
    annotate("rect", xmin = k_lo, xmax = k_hi, ymin = -Inf, ymax = Inf,
             fill = "#f0efec", colour = NA) +
    annotate("text", x = (k_lo + k_hi) / 2, y = Inf, vjust = -0.4, size = 3, colour = TINTA_2,
             label = "Cuota habitual de la hora punta") +
    geom_segment(aes(x = k_crit_min, xend = k_crit_max, yend = fila, colour = sent_lbl),
                 linewidth = 0.9) +
    geom_point(aes(x = k_crit_cen, colour = sent_lbl), size = 2.6) +
    scale_colour_manual(values = c("Hacia el Norte" = PAL[["azul"]],
                                   "Hacia Santa Cruz" = PAL[["naranja"]])) +
    scale_x_continuous(labels = function(x) pct_es(x, 1), limits = c(0, NA),
                       expand = expansion(mult = c(0, 0.05))) +
    coord_cartesian(clip = "off") +
    labs(title = "Margen de capacidad en la hora punta: k crítico por tramo y sentido",
         subtitle = envolver(paste(
           "k crítico = % del tráfico diario del sentido que llenaría la capacidad en una hora.",
           "A la izquierda de la banda gris, el tramo se satura en punta; dentro, va al límite."), 110),
         x = "k crítico (punto: capacidad central; línea: rango de capacidad por carril)", y = NULL,
         caption = envolver(paste(FUENTE_IMD,
                                  "Capacidad por carril y banda de cuota horaria: ver parametros_modelo.csv (fuentes citadas).",
                                  "Carriles por sentido: ver carriles_tf5.csv."), 150)) +
    tema_tf5(10) +
    theme(panel.grid.major.y = element_blank(),
          panel.grid.major.x = element_line(colour = REJILLA, linewidth = 0.3),
          plot.title = element_text(margin = margin(b = 4)),
          plot.subtitle = element_text(margin = margin(b = 18)))
}
