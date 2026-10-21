# =============================================================================
# 06_proyectos_verificacion.R · Proyectos reales y verificación de los apuntes
# =============================================================================

COLORES_VEREDICTO <- c(
  "Confirmado"           = ESTADO[["bien"]],
  "Parcialmente cierto"  = ESTADO[["aviso"]],
  "No verificado"        = "#c3c2b7",
  "Falso o erróneo"      = ESTADO[["critico"]]
)

grafico_verificacion <- function(afir) {
  d <- afir |>
    mutate(veredicto = factor(veredicto, levels = names(COLORES_VEREDICTO))) |>
    count(categoria, veredicto) |>
    group_by(categoria) |> mutate(total = sum(n)) |> ungroup() |>
    mutate(categoria = reorder(categoria, total))
  tot <- afir |> mutate(veredicto = factor(veredicto, levels = names(COLORES_VEREDICTO))) |>
    count(veredicto, .drop = FALSE) |> mutate(veredicto = as.character(veredicto))
  sub <- paste0(nrow(afir), " afirmaciones revisadas: ",
                paste(sprintf("%s %d", tolower(tot$veredicto), tot$n), collapse = " · "))
  ggplot(d, aes(n, categoria, fill = veredicto)) +
    geom_col(width = 0.62, colour = SUPERFICIE, linewidth = 0.6) +
    geom_text(aes(label = n), position = position_stack(vjust = 0.5), size = 3,
              colour = ifelse(d$veredicto %in% c("Confirmado", "Falso o erróneo"), "white", TINTA)) +
    scale_fill_manual(values = COLORES_VEREDICTO, drop = FALSE) +
    scale_x_continuous(expand = expansion(mult = c(0, 0.05)), breaks = function(l) seq(0, l[2], 2)) +
    labs(title = "Verificación de los apuntes generados por IA, por tema",
         subtitle = envolver(sub, 110),
         x = "Número de afirmaciones", y = NULL,
         caption = "Detalle, dato correcto y fuente de cada afirmación en datos/afirmaciones_apuntes.csv.") +
    tema_tf5(10) +
    theme(panel.grid.major.y = element_blank(),
          panel.grid.major.x = element_line(colour = REJILLA, linewidth = 0.3))
}

grafico_proyectos <- function(proy) {
  niveles <- c("Terminado", "Adjudicado o en obras", "En tramitación", "En estudio o sin financiación")
  d <- proy |>
    filter(!is.na(coste_meur)) |>
    mutate(proyecto = envolver_vec(proyecto, 48),
           proyecto = reorder(proyecto, coste_meur),
           grupo_estado = factor(grupo_estado, levels = niveles),
           coste_txt = sub(" \\(presupuesto de 2012\\)", " (2012)", coste_txt))
  tren <- proy$coste_meur[grepl("^Tren del Norte", proy$proyecto)]
  tc   <- proy$coste_meur[grepl("^Tercer carril TF-5 Guamasa-Aeropuerto", proy$proyecto)]
  bv   <- proy$coste_meur[grepl("^Carril Bus-VAO", proy$proyecto)]
  ggplot(d, aes(coste_meur, proyecto, colour = grupo_estado)) +
    geom_segment(aes(x = 1, xend = coste_meur, yend = proyecto), linewidth = 0.5, colour = REJILLA) +
    geom_point(size = 3.2) +
    geom_text(aes(x = coste_meur * 1.35, label = coste_txt), hjust = 0, size = 2.9, colour = TINTA_2) +
    scale_x_log10(labels = function(x) paste0(num_es(x), " M€"), breaks = c(1, 3, 10, 30, 100, 300, 1000),
                  expand = expansion(mult = c(0.02, 0.32))) +
    scale_colour_manual(values = setNames(unname(PAL[c("aqua", "azul", "amarillo", "violeta")]), niveles),
                        drop = FALSE) +
    guides(colour = guide_legend(nrow = 2)) +
    labs(title = "Coste y situación de las actuaciones (escala logarítmica)",
         subtitle = sprintf("El Tren del Norte costaría unas %s veces el tercer carril y unas %s veces el Bus-VAO. Solo la pasarela está terminada.",
                            num_es(tren / tc), num_es(tren / bv)),
         x = "Coste (millones de euros, escala log.)", y = NULL,
         caption = "Situación a 20-10-2026. Fuentes por fila en datos/proyectos.csv.") +
    tema_tf5(10) +
    theme(panel.grid.major.y = element_blank(),
          panel.grid.major.x = element_line(colour = REJILLA, linewidth = 0.3),
          axis.text.y = element_text(lineheight = 0.9))
}

envolver_vec <- function(x, ancho) vapply(x, function(z) envolver(z, ancho), character(1), USE.NAMES = FALSE)

# Comprobaciones aritméticas y de coherencia de los apuntes (ejecutables)
comprobar_aritmetica_apuntes <- function() {
  chk <- function(txt, ok, detalle) tibble(comprobacion = txt, resultado = ok, detalle = detalle)
  bind_rows(
    chk("De 59 a 85 plazas por guagua = +44 %",
        ifelse(abs((85 - 59) / 59 - 0.44) < 0.01, "CORRECTO", "ERRÓNEO"),
        sprintf("(85-59)/59 = %s", pct_es((85 - 59) / 59, 0.1))),
    chk("Pasar de 2 a 3 carriles sube la oferta un 33 %",
        ifelse(abs(3 / 2 - 1 - 0.33) < 0.02, "CORRECTO", "ERRÓNEO"),
        sprintf("3/2 - 1 = %s (el 33 %% sería pasar de 3 a 4 carriles)", pct_es(3 / 2 - 1))),
    chk("Peaje de 2 €: 5.500 x (-0,3 x 2/6) = -550 veh/h",
        ifelse(abs(5500 * (-0.3 * 2 / 6) + 550) < 1, "CORRECTO", "ERRÓNEO"),
        "La cuenta cuadra, pero los 5.500 veh/h, la elasticidad y los 6 € no tienen fuente"),
    chk("5.500 veh/h circulando por dos carriles de 4.000 veh/h de capacidad",
        ifelse(5500 > 4000, "INCOHERENTE", "COHERENTE"),
        "Un aforo no puede medir más tráfico que la capacidad del tramo: es demanda, no flujo"),
    chk("Nivel F «cuando la densidad supera 2.200 vehículos por hora y carril»",
        "ERRÓNEO",
        "Mezcla unidades: la densidad se mide en veh/km/carril; 2.200 veh/h/carril es un flujo"),
    chk("Ahorro mensual: 110 + 45 + 42 = 197 €; ~2.400 €/año",
        ifelse(110 + 45 + 42 == 197 && abs(197 * 12 - 2400) < 50, "CORRECTO", "ERRÓNEO"),
        sprintf("197 x 12 = %s €; los importes de partida son supuestos sin fuente", num_es(197 * 12))),
    chk("El tren «multiplica por 15» el coste de cualquier obra en la TF-5",
        ifelse(abs(1100 / 58.18 - 15) < 1, "CORRECTO", "INCOHERENTE"),
        sprintf("1.100/58,18 = %s; 1.100/6,2 = %s", num_es(1100 / 58.18, 0.1), num_es(1100 / 6.2, 1)))
  )
}
