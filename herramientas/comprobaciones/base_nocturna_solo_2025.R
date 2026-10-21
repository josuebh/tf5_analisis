# =============================================================================
# Comprobación aparte (no la ejecuta main.R): ¿intervienen los datos de 2026 en
# los objetivos de calibración a través de la línea base de velocidad?
#
# La hora congestionada exige que la parte de vehículos lentos supere en 30 puntos
# la de la madrugada de esa estación y sentido (base_nocturna(), R/07_datos_horarios.R).
# main.R calcula esa línea base con los días válidos de los 24 meses, incluido 2026.
# Aquí se recalcula solo con los días válidos de 2025 y se cuentan las horas de 2025
# que cambian de estado (congestionada o no). Si no cambia ninguna en las estaciones
# que usa el modelo, los objetivos de calibración de 2025 son los mismos con o sin
# 2026.
#
# Uso, desde la carpeta del proyecto:
#   Rscript herramientas/comprobaciones/base_nocturna_solo_2025.R
# Escribe docs/comprobacion_base_nocturna_2025.csv. Tarda unos dos minutos.
# =============================================================================

options(warn = 1)
invisible(Sys.setlocale("LC_CTYPE", "C.UTF-8"))
Sys.setenv(TZ = "Atlantic/Canary")
for (f in sort(list.files("R", pattern = "\\.R$", full.names = TRUE))) source(f, encoding = "UTF-8")

fest <- readr::read_csv(file.path(DIR_DATOS, "festivos_canarias.csv"), show_col_types = FALSE)
car <- leer_carriles_json()
cs <- carriles_por_sentido(car)
hp <- preparar_horarios(leer_horarios(), car, fest)
sd <- agregar_por_sentido(hp, cs)
dv <- dias_validos(sd)

base_24 <- base_nocturna(sd, dv)
base_25 <- base_nocturna(sd, dv |> filter(format(dia, "%Y") == "2025"))

solo_2025 <- function(x) x |> filter(format(dia, "%Y") == "2025") |>
  select(estacion_id, sentido, dia, hora, congestionada)
cambios <- inner_join(solo_2025(marcar_congestion(sd, dv, base_24)),
                      solo_2025(marcar_congestion(sd, dv, base_25)),
                      by = c("estacion_id", "sentido", "dia", "hora"), suffix = c("_24", "_25")) |>
  group_by(estacion_id, sentido) |>
  summarise(horas_2025 = n(),
            horas_que_cambian = sum(congestionada_24 != congestionada_25, na.rm = TRUE), .groups = "drop")

papel <- tibble::tribble(
  ~estacion_id, ~sentido,       ~papel_en_el_modelo,
  103,          "descendente",  "cuello de la mañana: objetivos de calibración",
  99,           "ascendente",   "cuello de la tarde: objetivos de calibración",
  99,           "descendente",  "tramo siguiente de la mañana: variantes de la capacidad libre",
  93,           "descendente",  "tramo siguiente de la mañana: variantes de la capacidad libre",
  111,          "ascendente",   "tramo siguiente de la tarde: solo caudales (sin velocidad utilizable)"
)

res <- base_24 |>
  left_join(base_25, by = c("estacion_id", "sentido"), suffix = c("_24_meses", "_2025")) |>
  left_join(cambios, by = c("estacion_id", "sentido")) |>
  left_join(papel, by = c("estacion_id", "sentido")) |>
  left_join(ESTACIONES_TF5 |> select(estacion_id, etiqueta), by = "estacion_id") |>
  mutate(papel_en_el_modelo = ifelse(is.na(papel_en_el_modelo), "descriptiva", papel_en_el_modelo),
         base_noche_24_meses = round(base_noche_24_meses, 6), base_noche_2025 = round(base_noche_2025, 6)) |>
  relocate(estacion_id, etiqueta, sentido, papel_en_el_modelo) |>
  arrange(match(estacion_id, ESTACIONES_TF5$estacion_id), sentido)

readr::write_csv(res, file.path("docs", "comprobacion_base_nocturna_2025.csv"), na = "")
print(as.data.frame(res))
cat("Horas de 2025 que cambian en las estaciones que usa el modelo:",
    sum(res$horas_que_cambian[res$papel_en_el_modelo != "descriptiva"], na.rm = TRUE), "\n")
