# =============================================================================
# 05_montecarlo.R · Incertidumbre y calibración
# -----------------------------------------------------------------------------
# Cada parámetro incierto se muestrea de una distribución triangular
# (mínimo, valor central, máximo) tomada de parametros_modelo.csv, donde cada
# rango lleva su fuente. Después se calibra por rechazo (ABC): solo se quedan
# las combinaciones cuya situación actual reproduce lo observado.
#   · criterio «aforos» (el principal): duración diaria, inicio y fin de la cola y
#     caudal de descarga medidos en los aforos horarios de 2025. La descarga se compara
#     como parámetro del modelo o medida igual que en el aforo, según la especificación
#     elegida por validación cruzada (12_validacion_predictiva.R);
#   · criterio «prensa»: espera máxima de 10-40 min (franja supuesta que cubre los 15-20 min
#     que estima Atlántico Hoy, 24-11-2025, y los 40 min de un día con incidente, COPE, 20-10-2021), solo
#     como sensibilidad.
# El resultado no es «la» predicción, sino el abanico de resultados compatibles
# con lo que se sabe.
# =============================================================================

rtriang <- function(n, a, m, b) {
  if (a == b) return(rep(a, n))
  u <- runif(n); fc <- (m - a) / (b - a)
  ifelse(u < fc, a + sqrt(u * (b - a) * (m - a)), b - sqrt((1 - u) * (b - a) * (b - m)))
}

muestrear_parametros <- function(par, n) {
  out <- lapply(seq_len(nrow(par)), function(i)
    rtriang(n, par$minimo[i], par$central[i], par$maximo[i]))
  names(out) <- par$parametro
  as_tibble(out)
}

fijar_parametro <- function(par, nombre, minimo, central = minimo, maximo = central, descripcion = NULL, fuente = NULL, tipo = NULL) {
  i <- which(par$parametro == nombre)
  if (length(i) != 1) stop("Parámetro desconocido en parametros_modelo.csv: ", nombre)
  stopifnot(minimo <= central, central <= maximo)
  par$minimo[i] <- minimo; par$central[i] <- central; par$maximo[i] <- maximo
  if (!is.null(descripcion)) par$descripcion[i] <- descripcion
  if (!is.null(fuente)) par$fuente[i] <- fuente
  if (!is.null(tipo)) par$tipo[i] <- tipo
  par
}

ETIQUETAS_ESC <- c(
  tercer_carril_corto   = "Tercer carril (1er año)",
  tercer_carril_medio   = "Tercer carril (a 5 años)",
  tercer_carril_largo   = "Tercer carril (a 10 años)",
  ramp_metering_corto   = "Regulación de accesos (1er año)",
  ramp_metering_medio   = "Regulación de accesos (a 5 años)",
  ramp_metering_largo   = "Regulación de accesos (a 10 años)",
  escalonamiento_corto  = "Escalonamiento horario (1er año)",
  escalonamiento_medio  = "Escalonamiento horario (a 5 años)",
  escalonamiento_largo  = "Escalonamiento horario (a 10 años)",
  tarificacion          = "Tarificación de la punta",
  paquete_gestion_corto = "Regulación + escalonamiento (1er año)",
  paquete_gestion_medio = "Regulación + escalonamiento (a 5 años)",
  paquete_gestion_largo = "Regulación + escalonamiento (a 10 años)"
)

# Parámetros derivados de cada realización: la elasticidad a 10 años no puede ser
# menor en valor absoluto que la del primer año, y la de 5 años sale del ajuste
# parcial (eta_medio(), 04_modelo_cuello_botella.R)
completar_parametros <- function(draws) {
  draws$eta_largo <- pmin(draws$eta_largo, draws$eta_corto)
  rho <- if ("persistencia_anual" %in% names(draws)) draws$persistencia_anual else 0.75
  draws$eta_medio <- eta_medio(draws$eta_corto, draws$eta_largo, rho)
  draws
}

# Simula en dos etapas: (1) situación actual de todas las combinaciones, que es
# lo que se compara con lo observado; (2) todas las alternativas solo para las
# combinaciones que interesan (las que pasa alguna regla de calibración), para
# no gastar tiempo en las que se van a descartar.
#   evaluar_si: función (draws con métricas de la base) -> lógico; NULL = todas
#   holgura_horaria: matriz 24 x 101 (hora x cuantiles 0-100 %) de la holgura del
#   tramo siguiente estimada con aforos; cada combinación toma un mismo cuantil u
#   para todas las horas (un «día bueno» o «malo» aguas abajo).
holgura_minutos <- function(holgura_horaria, u) {
  rep(holgura_horaria[, round(u * 100) + 1], each = 60)
}

#   perfil_obs: aforos horarios del cuello (list(veh_hora, ventana)) para el perfil
#   híbrido; NULL = perfil sintético
#   horas_holgura: filas de la matriz (hora + 1) con las que se resume la holgura de
#   cada combinación en holgura_aguas_abajo (solo descriptivo: el modelo usa la
#   holgura minuto a minuto)
simular_montecarlo <- function(par, V_dir, carriles, con_tercer_carril = TRUE, n = 2000,
                               semilla = 2026, t0 = T0_PUNTA, evaluar_si = NULL, holgura_horaria = NULL,
                               perfil_obs = NULL, horas_holgura = 7:9) {
  set.seed(semilla)
  draws <- muestrear_parametros(par, n) |> mutate(sim = seq_len(n))
  draws$eta_largo_muestra <- draws$eta_largo           # valor muestreado (antes de la dependencia), para reponderar previas
  draws <- completar_parametros(draws)
  if (!"t0_punta" %in% names(draws)) draws$t0_punta <- t0
  if (!is.null(holgura_horaria)) {
    draws$holgura_cuantil <- runif(n)
    draws$holgura_aguas_abajo <- vapply(draws$holgura_cuantil, function(u)
      mean(holgura_horaria[horas_holgura, round(u * 100) + 1]), numeric(1))   # media de las horas de la punta
  }
  # La equivalencia de pesados, al final y con su propia semilla: no cambia el resto de la muestra
  if (!is.null(perfil_obs$especificacion$cuota_pesados)) draws <- anadir_equivalencia_pesados(draws, semilla)
  base <- vector("list", n)
  for (i in seq_len(n)) {
    p <- as.list(draws[i, ])
    prof <- perfil_de(p, V_dir, perfil_obs)
    ht <- if (is.null(holgura_horaria)) NULL else holgura_minutos(holgura_horaria, p$holgura_cuantil)
    b <- evaluar_actual(p, carriles, prof, ht)
    da <- descarga_como_aforo(b$s, b$Q)
    base[[i]] <- tibble(sim = i, b_h = prof$b_h, vehiculos_joroba = sum(prof$joroba), base_demora_vh = b$demora_vh, base_espera_max = b$espera_max,
                        base_horas_cola = b$min_con_cola / 60, base_media_punta = b$demora_media_punta,
                        base_cola_max = b$cola_max, base_inicio = b$inicio_cola / 60, base_fin = b$fin_cola / 60,
                        base_horas_aforo = b$horas_aforo, base_inicio_aforo = b$inicio_aforo, base_fin_aforo = b$fin_aforo,
                        base_cola_final = b$cola_final, base_descarga_aforo = da[["dia"]], base_descarga_plena = da[["plena"]])
  }
  draws <- draws |> mutate(descarga = carriles * c_carril * (1 - caida_capacidad)) |>
    left_join(bind_rows(base), by = "sim")
  sel <- if (is.null(evaluar_si)) rep(TRUE, n) else evaluar_si(draws)
  draws$muestra_aleatoria <- if (is.null(attr(sel, "muestra"))) TRUE else attr(sel, "muestra")
  sel <- as.vector(sel)
  filas <- vector("list", n)
  for (i in which(sel)) {
    p <- as.list(draws[i, ])
    prof <- perfil_de(p, V_dir, perfil_obs)
    ht <- if (is.null(holgura_horaria)) NULL else holgura_minutos(holgura_horaria, p$holgura_cuantil)
    r <- escenarios_cuello(p, V_dir, carriles, con_tercer_carril, prof = prof, holgura_t = ht)
    b <- r$base$demora_vh
    filas[[i]] <- tibble(
      sim = i, escenario = names(r),
      demora_vh = vapply(r, function(x) x$demora_vh, numeric(1)),
      demora_media_punta = vapply(r, function(x) x$demora_media_punta, numeric(1)),
      espera_max = vapply(r, function(x) x$espera_max, numeric(1)),
      horas_con_cola = vapply(r, function(x) x$min_con_cola / 60, numeric(1)),
      horas_aforo = vapply(r, function(x) x$horas_aforo, numeric(1)),
      cola_max = vapply(r, function(x) x$cola_max, numeric(1)),
      cola_final = vapply(r, function(x) x$cola_final, numeric(1)),
      reduccion = if (b > DEMORA_MINIMA_VH) 1 - demora_vh / b else NA_real_
    )
  }
  draws$evaluada <- sel
  list(draws = draws, resultados = bind_rows(filas), n_total = n,
       V_dir = V_dir, carriles = carriles, t0 = t0, holgura_horaria = holgura_horaria, perfil_obs = perfil_obs)
}

# Calibración por rechazo
# submuestra = TRUE: la regla se resume con la submuestra uniforme del selector, que está
# evaluada entera (sin sesgo; ver selector_calibraciones()). Es lo que usan las reglas de la
# sensibilidad, salvo la principal, que usa todas sus combinaciones.
calibrar_montecarlo <- function(mc, criterio = "aforos", objetivo = NULL, espera_obs = c(10, 40), submuestra = FALSE) {
  d <- mc$draws
  ok <- switch(criterio,
    prensa = d$base_espera_max >= espera_obs[1] & d$base_espera_max <= espera_obs[2],
    aforos = d$base_horas_aforo >= objetivo$duracion[1] & d$base_horas_aforo <= objetivo$duracion[2] &
             cumple_descarga(d, objetivo) &
             (if (is.null(objetivo$inicio)) TRUE else
               !is.na(d$base_inicio_aforo) & d$base_inicio_aforo >= objetivo$inicio[1] & d$base_inicio_aforo <= objetivo$inicio[2] &
               d$base_fin_aforo >= objetivo$fin[1] & d$base_fin_aforo <= objetivo$fin[2]),
    ninguno = d$base_espera_max >= 1,                   # con cola: alguien espera al menos 1 minuto
    stop("criterio desconocido"))
  ok <- ok & d$base_cola_final < 0.5                   # la cola se disipa dentro del día
  validas_total <- if (criterio == "ninguno") sum(ok & d$muestra_aleatoria) else sum(ok)
  if (submuestra || criterio == "ninguno") ok <- ok & d$evaluada & d$muestra_aleatoria   # submuestra uniforme
  if (any(ok & !d$evaluada)) {
    warning(sum(ok & !d$evaluada), " combinaciones válidas sin evaluar; se descartan")
    ok <- ok & d$evaluada
  }
  validas <- d$sim[ok]
  desc <- switch(criterio,
    prensa = sprintf("espera máxima actual de %d-%d min", espera_obs[1], espera_obs[2]),
    aforos = paste0(sprintf("cola diaria de %s-%s h y descarga %s de %s-%s veh/h",
                            num_es(objetivo$duracion[1], 0.1), num_es(objetivo$duracion[2], 0.1),
                            if (identical(objetivo$medida_descarga, "como_aforo")) "medida como en el aforo (mediana del día)" else "(parámetro)",
                            num_es(ventana_descarga(objetivo)[1]), num_es(ventana_descarga(objetivo)[2])),
                    if (is.null(objetivo$inicio)) "" else
                      sprintf(", empieza entre las %s y las %s y acaba entre las %s y las %s", hora_txt(objetivo$inicio[1]),
                              hora_txt(objetivo$inicio[2]), hora_txt(objetivo$fin[1]), hora_txt(objetivo$fin[2])),
                    " (aforos 2025)"),
    ninguno = "muestra aleatoria de combinaciones con cola actual, sin calibrar")
  message(sprintf("  · Calibración (%s): %s de %s combinaciones.", desc, num_es(length(validas)), num_es(mc$n_total)))
  c(mc[c("n_total", "V_dir", "carriles", "t0", "holgura_horaria", "perfil_obs")],
    list(draws = d |> filter(sim %in% validas), resultados = mc$resultados |> filter(sim %in% validas),
         n_validas = length(validas), n_validas_total = validas_total, criterio = criterio, descripcion = desc,
         objetivo = objetivo))
}

# Descarga del día medida como en el aforo: mediana del caudal que sale en las horas
# que el aforo contaría con cola (>= 60 % de los vehículos de la hora pasan con cola) y
# mediana de las horas de cola plena (con cola la hora anterior y la siguiente)
descarga_como_aforo <- function(s, Q, umbral = 0.6) {
  h <- rep(0:23, each = 60)[seq_along(s)]
  sal <- as.numeric(tapply(s, h, sum)); frac <- as.numeric(tapply(s * (Q > 0.5), h, sum)) / pmax(sal, 1e-9)
  cg <- frac >= umbral
  plena <- cg & dplyr::lag(cg, default = FALSE) & dplyr::lead(cg, default = FALSE)
  c(dia = if (any(cg)) stats::median(sal[cg]) else NA_real_, plena = if (any(plena)) stats::median(sal[plena]) else NA_real_)
}

# Regla de la descarga: como parámetro del modelo (carriles x capacidad x (1 - caída))
# dentro del p10-p90 del caudal horario con cola, o medida igual que en el aforo dentro
# del p25-p75 de las medianas diarias aforadas
ventana_descarga <- function(objetivo) if (identical(objetivo$medida_descarga, "como_aforo")) objetivo$descarga_dia else objetivo$descarga
cumple_descarga <- function(d, objetivo) {
  w <- ventana_descarga(objetivo)
  x <- if (identical(objetivo$medida_descarga, "como_aforo")) d$base_descarga_aforo else d$descarga
  !is.na(x) & x >= w[1] & x <= w[2]
}

# Qué combinaciones evaluar del todo: todas las que pasa la calibración principal y una
# submuestra uniforme de todas las simuladas (n_submuestra). Las reglas de la sensibilidad
# se resumen solo con esa submuestra: como es uniforme, la parte de cada regla que cae en
# ella es una muestra sin sesgo de la regla (las combinaciones de la regla principal no
# quedan sobrerrepresentadas). La regla «sin calibrar» usa la submuestra con cola.
selector_calibraciones <- function(objetivo, n_submuestra = 3000, semilla = 99) {
  function(d) {
    set.seed(semilla)
    n <- nrow(d)
    muestra <- seq_len(n) %in% sample.int(n, min(n_submuestra, n))
    principal <- if (is.null(objetivo)) rep(FALSE, n) else
      d$base_horas_aforo >= objetivo$duracion[1] & d$base_horas_aforo <= objetivo$duracion[2] & cumple_descarga(d, objetivo) &
      (if (is.null(objetivo$inicio)) TRUE else !is.na(d$base_inicio_aforo) & d$base_inicio_aforo >= objetivo$inicio[1] &
         d$base_inicio_aforo <= objetivo$inicio[2] & d$base_fin_aforo >= objetivo$fin[1] & d$base_fin_aforo <= objetivo$fin[2]) &
      d$base_cola_final < 0.5
    structure(principal | muestra, muestra = muestra)
  }
}

resumir_montecarlo <- function(mc, etiquetas = ETIQUETAS_ESC) {
  mc$resultados |>
    filter(escenario != "base") |>
    group_by(escenario) |>
    summarise(p10 = quantile(reduccion, 0.10), mediana = median(reduccion),
              p90 = quantile(reduccion, 0.90),
              # parte de las combinaciones calibradas (no una probabilidad) que reduce la demora a la mitad o más
              parte_mejora_50 = mean(reduccion >= 0.5), .groups = "drop") |>
    mutate(etiqueta = unname(etiquetas[escenario]),
           escenario = factor(escenario, levels = names(etiquetas))) |>
    arrange(escenario) |>
    mutate(escenario = as.character(escenario))
}

# Etiquetas del caso 2: el tercer carril hacia el Norte no está en ningún proyecto
# (el contratado es hacia Santa Cruz y el de Guamasa-La Orotava empieza en Guamasa)
ETIQUETAS_ESC_NORTE <- ETIQUETAS_ESC
ETIQUETAS_ESC_NORTE[c("tercer_carril_corto", "tercer_carril_medio", "tercer_carril_largo")] <-
  c("Tercer carril hacia el Norte, hipotético (1er año)", "Tercer carril hacia el Norte, hipotético (a 5 años)",
    "Tercer carril hacia el Norte, hipotético (a 10 años)")

# Sensibilidad a la regla de calibración (misma muestra, distinto filtro). Si el
# objetivo trae descarga_dia o descarga_plena (rangos p25-p75 de 2025 de la descarga
# medida día a día o en las horas de cola plena), se añaden como reglas alternativas
# para la descarga: no sustituyen a la principal (que se fijó antes de ver 2026).
reglas_calibracion <- function(objetivo) {
  como_aforo <- identical(objetivo$medida_descarga, "como_aforo")
  reglas <- list(
    list(nombre = "Aforos horarios 2025 (principal)", criterio = "aforos", objetivo = objetivo, principal = TRUE),
    list(nombre = "Aforos sin el horario de la cola", criterio = "aforos",
         objetivo = utils::modifyList(objetivo, list(inicio = NULL, fin = NULL))),
    list(nombre = "Aforos: solo duración de la cola", criterio = "aforos",
         objetivo = list(duracion = objetivo$duracion, descarga = c(0, Inf))),
    if (como_aforo)
      list(nombre = "Descarga como parámetro del modelo (p10-p90 del caudal horario con cola)", criterio = "aforos",
           objetivo = utils::modifyList(objetivo, list(medida_descarga = "parametro")))
    else if (!is.null(objetivo$descarga_dia))
      list(nombre = "Descarga medida como en el aforo (p25-p75 de las medianas diarias)", criterio = "aforos",
           objetivo = utils::modifyList(objetivo, list(medida_descarga = "como_aforo"))),
    if (!is.null(objetivo$descarga_plena))
      list(nombre = "Descarga: horas de cola plena de 2025 (p25-p75)", criterio = "aforos",
           objetivo = utils::modifyList(objetivo, list(medida_descarga = "parametro", descarga = objetivo$descarga_plena))),
    list(nombre = "Prensa: espera máxima 10-40 min", criterio = "prensa", espera = c(10, 40)),
    list(nombre = "Prensa: espera máxima 5-20 min", criterio = "prensa", espera = c(5, 20)),
    list(nombre = "Prensa: espera máxima 20-60 min", criterio = "prensa", espera = c(20, 60)),
    list(nombre = "Sin calibrar (muestra aleatoria con cola)", criterio = "ninguno"))
  Filter(Negate(is.null), reglas)
}

sensibilidad_calibracion <- function(mc, objetivo, etiquetas = ETIQUETAS_ESC) {
  reglas <- reglas_calibracion(objetivo)
  bind_rows(lapply(reglas, function(r) {
    cal <- suppressMessages(calibrar_montecarlo(mc, r$criterio, r$objetivo, if (is.null(r$espera)) c(10, 40) else r$espera,
                                                submuestra = !isTRUE(r$principal)))
    dq <- stats::quantile(cal$draws$descarga, c(0.1, 0.5, 0.9), names = FALSE)
    if (cal$n_validas < 20) return(tibble(regla = r$nombre, n_validas = cal$n_validas, validas_total = cal$n_validas_total))
    resumir_montecarlo(cal, etiquetas) |> transmute(regla = r$nombre, n_validas = cal$n_validas, validas_total = cal$n_validas_total,
                                                    escenario, etiqueta, mediana, p10, p90,
                                                    descarga_p10 = dq[1], descarga_mediana = dq[2], descarga_p90 = dq[3])
  }))
}

# Qué parámetros explican la variación del resultado (correlación de rangos)
sensibilidad <- function(mc, esc = "tercer_carril_largo") {
  r <- mc$resultados |> filter(escenario == esc) |> arrange(sim)
  d <- mc$draws |> arrange(sim) |> select(-any_of(c("sim", "descarga", "b_h", "base_demora_vh", "base_espera_max",
                                                    "base_horas_cola", "base_media_punta", "base_cola_final", "evaluada", "holgura_cuantil",
                                                    "muestra_aleatoria", "base_cola_max", "base_inicio", "base_fin",
                                                    "base_horas_aforo", "base_inicio_aforo", "base_fin_aforo",
                                                    "eta_medio", "vehiculos_joroba", "eta_largo_muestra")), -starts_with("base_"))
  # Solo parámetros: columnas numéricas sin huecos que varían entre combinaciones
  vars <- names(d)[vapply(d, function(x) is.numeric(x) && !anyNA(x) && isTRUE(stats::sd(x) > 0), logical(1))]
  tibble(parametro = vars,
         rho = vapply(vars, function(v) cor(d[[v]], r$reduccion, method = "spearman"), numeric(1))) |>
    arrange(desc(abs(rho)))
}

# Curva de reducción del tercer carril según la holgura aguas abajo
curva_holgura <- function(mc, holguras = round(seq(0, 0.5, 0.05), 2), n_max = 300, semilla = 5) {
  set.seed(semilla)
  d <- mc$draws
  if (nrow(d) > n_max) d <- d[sample.int(nrow(d), n_max), ]
  bind_rows(lapply(seq_len(nrow(d)), function(i) {
    p <- as.list(d[i, ])
    tercer_carril_por_holgura(p, mc$V_dir, mc$carriles, holguras, prof = perfil_de(p, mc$V_dir, mc$perfil_obs))
  })) |>
    group_by(holgura, horizonte) |>
    summarise(p10 = quantile(reduccion, 0.1, na.rm = TRUE), mediana = median(reduccion, na.rm = TRUE),
              p90 = quantile(reduccion, 0.9, na.rm = TRUE), .groups = "drop")
}

grafico_montecarlo <- function(res, titulo_caso, n_validas, titulo = NULL, calibracion = NULL) {
  d <- res |>
    mutate(etiqueta = factor(etiqueta, levels = rev(unique(etiqueta))),
           tipo = ifelse(grepl("Tercer", etiqueta), "Ampliar capacidad",
                         "Gestionar demanda y capacidad"))
  ggplot(d, aes(y = etiqueta)) +
    geom_vline(xintercept = 0, colour = "#c3c2b7", linewidth = 0.4) +
    geom_segment(aes(x = p10, xend = p90, yend = etiqueta, colour = tipo), linewidth = 1) +
    geom_point(aes(x = mediana, colour = tipo), size = 3) +
    geom_text(aes(x = p90, label = pct_es(mediana, 1)), hjust = -0.35, size = 3.1, colour = TINTA) +
    scale_colour_manual(values = c("Ampliar capacidad" = PAL[["naranja"]],
                                   "Gestionar demanda y capacidad" = PAL[["azul"]])) +
    scale_x_continuous(labels = function(x) pct_es(x, 1), limits = c(min(0, min(d$p10)), 1.12),
                       breaks = seq(0, 1, 0.25)) +
    labs(title = if (is.null(titulo)) "Reducción de la demora total en la punta frente a no hacer nada" else titulo,
         subtitle = envolver(paste0(titulo_caso, ". Punto: mediana de ", num_es(n_validas),
                                    " simulaciones compatibles con ", if (is.null(calibracion)) "lo observado" else calibracion,
                                    "; línea: banda p10-p90 de esas combinaciones (incertidumbre de los parámetros; no es un intervalo predictivo ni una probabilidad). Número: mediana."), 110),
         x = "Reducción de vehículos·hora de demora (100 % = desaparece la cola)", y = NULL,
         caption = envolver(paste("Modelo de cola en cuello de botella (día completo, esperas por cohortes) calibrado con los",
                                  "aforos horarios oficiales de 2025; parámetros usados, rangos y fuentes en salidas/tablas/parametros_usados_caso1.csv y _caso2.csv."), 150)) +
    tema_tf5(10) +
    theme(panel.grid.major.y = element_blank(),
          panel.grid.major.x = element_line(colour = REJILLA, linewidth = 0.3))
}

grafico_colas_ejemplo <- function(p, V_dir, carriles, titulo_caso, t0 = T0_PUNTA, reloj = FALSE, holgura_t = NULL,
                                  obs = NULL, con_tercer_carril = TRUE, etiquetas = ETIQUETAS_ESC) {
  if (is.null(p$t0_punta)) p$t0_punta <- t0
  t0 <- p$t0_punta
  prof <- perfil_de(p, V_dir, obs)
  r <- escenarios_cuello(p, V_dir, carriles, con_tercer_carril, prof = prof, holgura_t = holgura_t)
  esc <- c("tercer_carril_corto", "tercer_carril_largo", "ramp_metering_corto", "escalonamiento_corto",
           "tarificacion", "paquete_gestion_corto")
  if (!"tercer_carril_corto" %in% names(r)) esc <- setdiff(esc, c("tercer_carril_corto", "tercer_carril_largo"))
  base <- tibble(t = seq_along(r$base$Q) - 1, Q = r$base$Q)
  d <- bind_rows(lapply(esc, function(e) tibble(t = seq_along(r[[e]]$Q) - 1, Q = r[[e]]$Q,
                                               escenario = etiquetas[[e]]))) |>
    mutate(escenario = factor(escenario, levels = unname(etiquetas[esc])))
  base_rep <- tidyr::crossing(base, escenario = levels(d$escenario)) |>
    mutate(escenario = factor(escenario, levels = levels(d$escenario)))
  rango <- range(c(which(r$base$Q > 0.5))) + c(-60, 60)
  etiqueta_x <- if (reloj) function(m) sprintf("%02d:%02d", (m %/% 60) %% 24, m %% 60) else
    function(m) sprintf("%+d h", round((m - t0) / 60))
  ggplot(d, aes(t, Q)) +
    geom_area(data = base_rep, fill = GRIS_ENFASIS, alpha = 0.45) +
    geom_line(colour = PAL[["azul"]], linewidth = 0.8) +
    facet_wrap(~escenario, ncol = 2) +
    scale_x_continuous(breaks = seq(0, DURACION_MIN, 60), labels = etiqueta_x) +
    coord_cartesian(xlim = rango) +
    scale_y_continuous(labels = function(x) num_es(x)) +
    labs(title = "Cola en el cuello de botella: sin actuación (gris) y con cada alternativa (azul)",
         subtitle = envolver(paste0(titulo_caso, ". Simulación con la combinación central calibrada."), 110),
         x = NULL, y = "Vehículos en cola",
         caption = "Modelo de cola puntual determinista (Vickrey, 1969) con caída de capacidad y demanda inducida.") +
    tema_tf5(10)
}

# ---- g11 · Bus-VAO convirtiendo un carril: demora del tráfico general --------
grafico_bus_vao <- function(draws, V_dir, carriles, t0 = T0_PUNTA, n = 300, semilla = 11, lugar = "Padre Anchieta hacia el Norte") {
  set.seed(semilla)
  if (nrow(draws) > n) draws <- draws[sample.int(nrow(draws), n), ]
  ms <- seq(0, 0.6, by = 0.02)
  filas <- vector("list", nrow(draws))
  for (i in seq_len(nrow(draws))) {
    p <- as.list(draws[i, ])
    if (is.null(p$t0_punta)) p$t0_punta <- t0            # cada combinación lleva su hora punta calibrada
    prof <- perfil_de(p, V_dir)
    actual <- evaluar(prof, carriles * p$c_carril, p$caida_capacidad)$demora_media_punta
    conv <- vapply(ms, function(m) {
      pm <- prof; pm$base <- prof$base * (1 - m); pm$joroba <- prof$joroba * (1 - m)
      evaluar(pm, (carriles - 1) * p$c_carril, p$caida_capacidad)$demora_media_punta
    }, numeric(1))
    filas[[i]] <- tibble(sim = i, m = ms, con_bus_vao = conv, actual = actual)
  }
  d <- bind_rows(filas) |>
    group_by(m) |>
    summarise(med = median(con_bus_vao), lo = quantile(con_bus_vao, 0.1), hi = quantile(con_bus_vao, 0.9),
              act_med = median(actual), act_lo = quantile(actual, 0.1), act_hi = quantile(actual, 0.9),
              .groups = "drop")
  act <- d[1, c("act_med", "act_lo", "act_hi")]
  i_c <- which(d$med <= act$act_med)[1]                   # primer punto de la rejilla (cada 2 %) que iguala hoy
  corte <- if (is.na(i_c) || i_c == 1) d$m[i_c] else      # interpolación lineal entre los dos puntos de la rejilla
    d$m[i_c - 1] + (d$med[i_c - 1] - act$act_med) / (d$med[i_c - 1] - d$med[i_c]) * (d$m[i_c] - d$m[i_c - 1])
  g <- ggplot(d, aes(m)) +
    annotate("rect", xmin = -Inf, xmax = Inf, ymin = act$act_lo, ymax = act$act_hi, fill = "#f0efec") +
    geom_hline(yintercept = act$act_med, colour = GRIS_ENFASIS, linewidth = 0.9) +
    annotate("text", x = 0.6, y = act$act_hi, vjust = -0.5, hjust = 1, size = 3, colour = TINTA_2,
             label = sprintf("Hoy, con %d carriles: %s min de espera media en la hora punta (mediana)", carriles, num_es(act$act_med, 0.1))) +
    geom_ribbon(aes(ymin = lo, ymax = hi), fill = PAL[["azul"]], alpha = 0.12) +
    geom_line(aes(y = med), colour = PAL[["azul"]], linewidth = 0.9) +
    geom_vline(xintercept = 1 / carriles, colour = "#c3c2b7", linewidth = 0.4) +
    annotate("text", x = 1 / carriles + 0.01, y = max(d$hi) * 0.95, hjust = 0, size = 3, colour = TINTA_2,
             label = sprintf("1/%d = %s de los vehículos", carriles, pct_es(1 / carriles))) +
    scale_x_continuous(labels = function(x) pct_es(x), breaks = seq(0, 0.6, 0.1)) +
    scale_y_continuous(labels = function(x) num_es(x, 1)) +
    labs(title = "Reservar un carril a Bus-VAO solo compensa si se pasa a él mucho tráfico",
         subtitle = envolver(sprintf(paste0(
           "%s (%s veh/día laborable, %d carriles) si el carril izquierdo se reserva en punta. ",
           "Azul: espera media en la hora punta del tráfico general según el %% de vehículos que usa el carril reservado ",
           "(guaguas, taxis, motos, 2+ ocupantes). Iguala la situación actual hacia el %s."), lugar, num_es(V_dir), carriles, pct_es(corte)), 112),
         x = "Vehículos que pasan al carril reservado", y = "Espera media en cola (min/vehículo)",
         caption = envolver(paste("Mediana y banda p10-p90 de", nrow(draws), "simulaciones calibradas.",
                                  "El carril reservado se supone sin cola. Umbral necesario, no prueba de que exista esa demanda elegible."), 150)) +
    tema_tf5(10)
  attr(g, "datos") <- d |> transmute(trasvase = m, espera_bus_vao_mediana = round(med, 2),
                                     espera_bus_vao_p10 = round(lo, 2), espera_bus_vao_p90 = round(hi, 2),
                                     espera_actual_mediana = round(act_med, 2))
  g
}

# ---- Auditoría del Monte Carlo ----------------------------------------------------
# Repetición con otras semillas: misma previa y misma regla, otras combinaciones. Solo se
# evalúan las alternativas de las combinaciones aceptadas por la regla principal.
replicar_semillas <- function(par, V_dir, carriles, objetivo, semillas, n, holgura_horaria = NULL, perfil_obs = NULL,
                              horas_holgura = 7:9, etiquetas = ETIQUETAS_ESC, caso = "") {
  bind_rows(lapply(semillas, function(sem) {
    sel <- selector_calibraciones(objetivo, n_submuestra = 0)
    mc_s <- suppressMessages(simular_montecarlo(par, V_dir, carriles, TRUE, n = n, semilla = sem, evaluar_si = sel,
                                                holgura_horaria = holgura_horaria, perfil_obs = perfil_obs, horas_holgura = horas_holgura))
    cal <- suppressMessages(calibrar_montecarlo(mc_s, "aforos", objetivo))
    if (cal$n_validas < 20) return(tibble(caso = caso, semilla = sem, aceptadas = cal$n_validas, simuladas = n))
    resumir_montecarlo(cal, etiquetas) |>
      transmute(caso = caso, semilla = sem, aceptadas = cal$n_validas, simuladas = n, tasa_aceptacion = cal$n_validas / n,
                escenario, etiqueta, p10, mediana, p90) |>
      left_join(diferencias_emparejadas(cal, caso, etiquetas = etiquetas) |>
                  filter(alternativa_b == "paquete_gestion", horizonte == "corto") |>
                  transmute(escenario = paste0(alternativa_a, "_corto"), dif_frente_al_paquete_mediana = dif_mediana,
                            dif_frente_al_paquete_p10 = dif_p10, dif_frente_al_paquete_p90 = dif_p90,
                            parte_por_encima_del_paquete = parte_a_mayor),
                by = "escenario")
  }))
}

# Densidad triangular (mínimo a, moda m, máximo b)
dtriang <- function(x, a, m, b) {
  if (a == b) return(rep(1, length(x)))
  ifelse(x < a | x > b, 0,
         ifelse(x < m, 2 * (x - a) / ((b - a) * (m - a)), ifelse(x > m, 2 * (b - x) / ((b - a) * (b - m)), 2 / (b - a))))
}

# Previas alternativas por reponderación (muestreo por importancia): las combinaciones
# aceptadas se pesan con densidad_alternativa / densidad_usada de cada parámetro. Solo
# vale para previas con el mismo soporte; el tamaño efectivo (ESS) dice cuánta
# información queda. previas: lista nombrada; cada una, lista parametro -> c(a, m, b)
# (triangular) o "uniforme".
reponderar_previas <- function(mc, par, previas, caso = "", etiquetas = ETIQUETAS_ESC) {
  d <- mc$draws
  col <- function(v) if (v == "eta_largo" && "eta_largo_muestra" %in% names(d)) d$eta_largo_muestra else d[[v]]
  wq <- function(x, w, p) { o <- order(x); x <- x[o]; w <- w[o] / sum(w); x[which(cumsum(w) >= p - 1e-9)[1]] }
  bind_rows(lapply(names(previas), function(nm) {
    alt <- previas[[nm]]
    w <- rep(1, nrow(d))
    for (v in names(alt)) {
      i <- which(par$parametro == v); if (!length(i) || !v %in% c(names(d), "eta_largo")) next
      a <- par$minimo[i]; m <- par$central[i]; b <- par$maximo[i]
      x <- col(v)
      f_usada <- dtriang(x, a, m, b)
      f_alt <- if (identical(alt[[v]], "uniforme")) ifelse(x >= a & x <= b, 1 / (b - a), 0) else dtriang(x, alt[[v]][1], alt[[v]][2], alt[[v]][3])
      w <- w * ifelse(f_usada > 0, f_alt / f_usada, 0)
    }
    ess <- sum(w)^2 / sum(w^2)
    r <- mc$resultados |> filter(escenario != "base") |> left_join(tibble(sim = d$sim, w = w), by = "sim")
    r |> group_by(escenario) |>
      summarise(p10 = wq(reduccion, w, 0.1), mediana = wq(reduccion, w, 0.5), p90 = wq(reduccion, w, 0.9), .groups = "drop") |>
      mutate(caso = caso, previa = nm, aceptadas = nrow(d), tamano_efectivo = ess, etiqueta = unname(etiquetas[escenario])) |>
      relocate(caso, previa, aceptadas, tamano_efectivo, escenario, etiqueta)
  }))
}

# Correlación de rangos (Spearman) entre parámetros en la previa (todas las combinaciones)
# y entre las aceptadas: la calibración crea dependencias que la previa no tiene
correlaciones_parametros <- function(mc_todo, mc, par, caso = "") {
  vars <- intersect(par$parametro[par$minimo < par$maximo], names(mc$draws))
  vars <- vars[vapply(vars, function(v) stats::sd(mc$draws[[v]]) > 0, logical(1))]
  pares <- utils::combn(vars, 2, simplify = FALSE)
  bind_rows(lapply(pares, function(pp) tibble(
    caso = caso, parametro_1 = pp[1], parametro_2 = pp[2],
    rho_previa = stats::cor(mc_todo$draws[[pp[1]]], mc_todo$draws[[pp[2]]], method = "spearman"),
    rho_aceptadas = stats::cor(mc$draws[[pp[1]]], mc$draws[[pp[2]]], method = "spearman")))) |>
    mutate(cambio = rho_aceptadas - rho_previa) |> arrange(desc(abs(rho_aceptadas)))
}
