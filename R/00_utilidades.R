# =============================================================================
# 00_utilidades.R  ·  Paquetes, rutas, tema gráfico y funciones auxiliares
# Proyecto: Evaluación del plan contra la congestión en la TF-5 (Tenerife)
# =============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(readr)
  library(ggplot2)
  library(scales)
  library(ggrepel)
  library(patchwork)
})

# Valida las opciones antes de borrar o generar salidas. Evita convertir texto,
# decimales o desbordamientos en NA después de haber eliminado resultados previos.
entero_positivo_entorno <- function(nombre, defecto) {
  texto <- Sys.getenv(nombre, unset = "")
  if (!nzchar(texto)) return(as.integer(defecto))
  valido <- grepl("^[0-9]+$", texto)
  n <- suppressWarnings(as.numeric(texto))
  if (!valido || !is.finite(n) || n < 1 || n > .Machine$integer.max)
    stop(nombre, " debe ser un entero positivo (1-", .Machine$integer.max, ")", call. = FALSE)
  as.integer(n)
}

# ---- Rutas (relativas a la carpeta del proyecto) ----------------------------
DIR_DATOS    <- "datos"
DIR_GRAFICOS <- file.path("salidas", "graficos")
DIR_TABLAS   <- file.path("salidas", "tablas")
dir.create(DIR_GRAFICOS, recursive = TRUE, showWarnings = FALSE)
dir.create(DIR_TABLAS,   recursive = TRUE, showWarnings = FALSE)

# ---- Paleta (validada para daltonismo; orden fijo, nunca cíclico) ------------
PAL <- c(
  azul    = "#2a78d6", naranja = "#eb6834", aqua  = "#1baf7a",
  amarillo= "#eda100", magenta = "#e87ba4", verde = "#008300",
  violeta = "#6250d6", rojo    = "#e34948"
)
GRIS_ENFASIS <- "#c3c2b7"   # series de contexto (énfasis = 1 color + gris)
TINTA        <- "#0b0b0b"
TINTA_2      <- "#52514e"
TINTA_MUTE   <- "#898781"
REJILLA      <- "#e1e0d9"
SUPERFICIE   <- "#fcfcfb"
# Paleta de estado (solo para veredictos, siempre con etiqueta de texto)
ESTADO <- c(bien = "#0ca30c", aviso = "#fab219", serio = "#ec835a", critico = "#d03b3b")

tema_tf5 <- function(base = 11) {
  theme_minimal(base_size = base, base_family = "sans") +
    theme(
      plot.background   = element_rect(fill = SUPERFICIE, colour = NA),
      panel.background  = element_rect(fill = SUPERFICIE, colour = NA),
      panel.grid.minor  = element_blank(),
      panel.grid.major.x= element_blank(),
      panel.grid.major.y= element_line(colour = REJILLA, linewidth = 0.3),
      axis.line.x       = element_line(colour = "#c3c2b7", linewidth = 0.3),
      axis.text         = element_text(colour = TINTA_2),
      axis.title        = element_text(colour = TINTA_2, size = rel(0.9)),
      plot.title        = element_text(colour = TINTA, face = "bold", size = rel(1.15),
                                       margin = margin(b = 4)),
      plot.subtitle     = element_text(colour = TINTA_2, margin = margin(b = 10)),
      plot.caption      = element_text(colour = TINTA_MUTE, size = rel(0.75), hjust = 0,
                                       margin = margin(t = 10)),
      plot.caption.position = "plot",
      plot.title.position   = "plot",
      legend.position   = "top",
      legend.justification = "left",
      legend.title      = element_blank(),
      legend.text       = element_text(colour = TINTA_2),
      strip.text        = element_text(colour = TINTA, face = "bold", hjust = 0),
      plot.margin       = margin(14, 18, 10, 14)
    )
}

# Números en formato español: 117.791 · 8,5 %
num_es <- function(x, acc = 1) scales::label_number(accuracy = acc, big.mark = ".",
                                                    decimal.mark = ",")(x)
pct_es <- function(x, acc = 1) scales::label_percent(accuracy = acc, big.mark = ".",
                                                     decimal.mark = ",")(x)
# Valor p con tres decimales; por debajo de 0,001 se escribe "p < 0,001" en lugar de "p = 0,000"
p_txt <- function(p) ifelse(is.na(p), "p = NA", ifelse(p < 0.001, "p < 0,001", paste0("p = ", num_es(p, 0.001))))
# Hora del día en horas decimales -> "HH:MM" (p. ej. 6.5 -> "06:30")
hora_txt <- function(h) { m <- round(h * 60); sprintf("%02d:%02d", (m %/% 60) %% 24, m %% 60) }

guardar_grafico <- function(p, nombre, ancho = 9, alto = 5.6) {
  ruta <- file.path(DIR_GRAFICOS, paste0(nombre, ".png"))
  ggsave(ruta, p, width = ancho, height = alto, dpi = 200, bg = SUPERFICIE)
  message("  · gráfico guardado: ", ruta)
  invisible(ruta)
}

guardar_tabla <- function(df, nombre) {
  ruta <- file.path(DIR_TABLAS, paste0(nombre, ".csv"))
  readr::write_csv(df, ruta, na = "")
  message("  · tabla guardada:   ", ruta)
  invisible(ruta)
}

# Ajusta textos largos (subtítulos y pies) a un ancho de línea dado
envolver <- function(x, ancho = 120) paste(strwrap(x, width = ancho), collapse = "\n")

FUENTE_IMD <- paste0("Fuente: Cabildo de Tenerife, «Intensidad Media Diaria (IMD) de tráfico de ",
                     "Tenerife», datos.tenerife.es (CSV anuales 2018-2025).")
