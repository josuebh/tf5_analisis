# =============================================================================
# 04_modelo_cuello_botella.R · Modelo de cola en un cuello de botella
# -----------------------------------------------------------------------------
# Modelo didáctico (cola puntual determinista, tipo Vickrey 1969):
#   · La demanda llega minuto a minuto durante un DÍA COMPLETO (1.440 min) y
#     suma exactamente la IMD oficial del sentido (conservación de vehículos).
#     Sin datos horarios se usa un perfil sintético «noche + día + joroba de
#     punta»; con datos horarios se usa el perfil observado (07_datos_horarios.R).
#   · El tramo descarga como máximo su capacidad (carriles x veh/h/carril).
#   · Cuando hay cola, la capacidad cae un % («caída de capacidad»).
#   · La espera de cada cohorte de llegadas se calcula con curvas acumuladas
#     de llegadas y salidas (distancia horizontal, disciplina FIFO; Newell).
#   · La demanda de punta reacciona al tiempo de viaje con una elasticidad
#     (demanda inducida): si una mejora reduce la demora, vuelve tráfico a la
#     punta hasta un nuevo equilibrio.
# Es una cola puntual: no localiza la cola en el espacio. La espera en los
# ramales que provoca la regulación de accesos está incluida en la demora total.
# Especificación de la descarga (se elige por validación cruzada en 2025, ver
# 12_validacion_predictiva.R) que viaja en el perfil de demanda:
#   · propagación: si el tramo siguiente admite menos que lo que hoy descarga el
#     cuello (holgura negativa), la cola de abajo limita lo que pasa por el cuello
#     (almacenamiento nulo entre los dos; el caso con almacenamiento finito está
#     en simular_tandem());
#   · descarga dependiente de la hora: factor por hora del caudal con cola;
#   · mezcla de pesados: capacidad en vehículos que baja con la parte de pesados.
# No sustituye a una microsimulación (AIMSUN/VISSIM) con datos horarios reales;
# sirve para comparar alternativas con los mismos supuestos y ver qué
# parámetros deciden el resultado.
# =============================================================================

DURACION_MIN <- 1440   # día completo: sin truncar llegadas ni colas
DEMORA_MINIMA_VH <- 1e-6   # por debajo, la demora es ruido de redondeo: no hay cola que reducir
T0_PUNTA     <- 450    # centro de la joroba sintética (07:30); solo sitúa la punta en el día
MIN_NOCHE    <- c(0:359, 1320:1439)   # 22:00-06:00 (8 h)

# ---- Perfil de demanda --------------------------------------------------------
# Perfil sintético de 24 h que conserva la IMD del sentido:
#   · noche (22-06 h): cuota_noche de la IMD, repartida por igual;
#   · día (06-22 h): un nivel base de b_h (fracción de la IMD por hora);
#   · joroba gaussiana de anchura sigma centrada en t0.
# La hora punta (60 min centrados en t0) lleva k_dir de la IMD. Las dos
# condiciones (suma = IMD y hora punta = k_dir) fijan b_h y la altura de la
# joroba, así que b_h deja de ser un supuesto libre.
perfil_demanda <- function(V_dir, k_dir, sigma, cuota_noche, t0 = T0_PUNTA) {
  t <- 0:(DURACION_MIN - 1)
  noche <- t %in% MIN_NOCHE
  w <- exp(-((t - t0)^2) / (2 * sigma^2))
  hp <- abs(t - t0 + 0.5) <= 30                       # 60 min centrados en t0
  phi <- sum(w[hp]) / sum(w)                          # parte de la joroba en la hora punta
  h_dia <- sum(!noche) / 60
  b_h <- (1 - cuota_noche - k_dir / phi) / (h_dia - 1 / phi)
  if (!is.finite(b_h) || b_h <= 0 || b_h >= k_dir)
    stop("Parámetros incompatibles con la IMD: b_h = ", signif(b_h, 3))
  base <- ifelse(noche, cuota_noche * V_dir / length(MIN_NOCHE), b_h * V_dir / 60)
  A <- (k_dir - b_h) * V_dir / sum(w[hp])
  list(t = t, base = base, joroba = A * w, b_h = b_h, V = V_dir, t0 = t0, tipo = "sintetico")
}

# Perfil observado: 24 valores horarios (veh/h) del día laborable medio. Se
# reparte cada hora por igual entre sus 60 minutos y se escala para que sume la
# IMD del sentido. La «joroba» es lo que excede del nivel de los hombros de la
# punta (mínimo de las 2 h anteriores y posteriores a la hora punta): es la parte
# de la demanda que se trata como elástica y desplazable.
perfil_observado <- function(veh_hora, V_dir = sum(veh_hora)) {
  stopifnot(length(veh_hora) == 24, all(veh_hora >= 0))
  f <- V_dir / sum(veh_hora)
  lam <- rep(veh_hora * f / 60, each = 60)
  hp <- which.max(veh_hora)
  vecinas <- setdiff(max(1, hp - 2):min(24, hp + 2), hp)
  hombro <- min(veh_hora[vecinas]) * f / 60
  joroba <- pmax(lam - hombro, 0)
  zona <- rep(abs(seq_len(24) - hp) <= 2, each = 60)   # la joroba solo alrededor de la punta
  joroba[!zona] <- 0
  list(t = 0:(DURACION_MIN - 1), base = lam - joroba, joroba = joroba,
       b_h = hombro * 60 / V_dir, V = V_dir, t0 = (hp - 1) * 60 + 30, tipo = "observado")
}

# Perfil híbrido (el que usan los dos casos): fuera de la ventana de la
# punta, la demanda es el caudal medido en los aforos (sin cola, caudal = demanda).
# Dentro de la ventana [h0, h1) el caudal está topado por la capacidad y no revela la
# demanda; se reparte el mismo número de vehículos que miden los aforos en esa ventana
# (conservación: la cola se vacía dentro del día) entre:
#   · una base que va en línea recta del caudal de la hora anterior a la ventana al
#     de la hora posterior (centros de hora), y
#   · una joroba gaussiana (centro t0, anchura sigma), recortada a la ventana, que es
#     la parte elástica y desplazable de la punta.
# El tamaño de la joroba sale de los datos (vehículos de la ventana - base); solo su
# forma (t0, sigma) se calibra con el horario y la duración de la cola.
perfil_hibrido <- function(veh_hora, ventana, t0, sigma, V_dir = sum(veh_hora)) {
  stopifnot(length(veh_hora) == 24, all(veh_hora >= 0), ventana[1] >= 1, ventana[2] <= 23, ventana[2] > ventana[1])
  o <- veh_hora * V_dir / sum(veh_hora)           # escala si V_dir no es el total medido (crecimiento)
  t <- 0:(DURACION_MIN - 1)
  base <- rep(o / 60, each = 60)
  en_v <- t >= ventana[1] * 60 & t < ventana[2] * 60
  x0 <- (ventana[1] - 1) * 60 + 30; y0 <- o[ventana[1]] / 60      # centro de la hora anterior (o[h + 1] = hora h)
  x1 <- ventana[2] * 60 + 30;       y1 <- o[ventana[2] + 1] / 60  # centro de la hora posterior
  base[en_v] <- y0 + (y1 - y0) * (t[en_v] + 0.5 - x0) / (x1 - x0)
  resto <- sum(o[(ventana[1] + 1):ventana[2]]) - sum(base[en_v])
  if (resto <= 0) stop("La ventana de la punta no tiene vehículos por encima de la base")
  w <- exp(-((t[en_v] - t0)^2) / (2 * sigma^2))
  joroba <- numeric(DURACION_MIN); joroba[en_v] <- resto * w / sum(w)
  list(t = t, base = base, joroba = joroba, b_h = NA_real_, V = V_dir, t0 = t0, tipo = "hibrido",
       ventana = ventana, vehiculos_joroba = resto)
}

# Ventana de la punta a partir de los aforos: desde la primera hora congestionada al
# menos la mitad de los días hasta una hora después de la última (descarga de la cola)
ventana_punta <- function(prob_congestion, horas = 0:23, umbral = 0.5) {
  h <- horas[prob_congestion >= umbral]
  c(min(h), max(h) + 2)
}

# ---- Cola puntual con caída de capacidad --------------------------------------
# Dos regímenes: sin cola descarga mu; con cola, mu·(1 - caida). Se recorre por
# episodios (vectorizado): cada episodio empieza cuando la demanda supera mu y
# acaba cuando la cola se vacía. cap_hora y caida pueden ser un número o un
# vector de un valor por minuto (capacidad que cambia a lo largo del día).
simular_cola <- function(lambda, cap_hora, caida = 0) {
  n <- length(lambda)
  mu <- rep_len(cap_hora / 60, n); mu2 <- mu * (1 - rep_len(caida, n)); eps <- 1e-9
  Q <- numeric(n); s <- numeric(n)
  exceso <- lambda - mu > eps
  i <- 1
  while (i <= n) {
    k <- which(exceso[i:n])[1]
    if (is.na(k)) { s[i:n] <- lambda[i:n]; break }
    k <- i + k - 1
    if (k > i) s[i:(k - 1)] <- lambda[i:(k - 1)]
    s[k] <- mu[k]; Q[k] <- lambda[k] - mu[k]          # se forma la cola
    if (k == n) break
    idx <- (k + 1):n
    traj <- Q[k] + cumsum(lambda[idx] - mu2[idx])
    fin <- which(traj <= eps)[1]
    if (is.na(fin)) { Q[idx] <- traj; s[idx] <- mu2[idx]; break }   # no se disipa en el día
    e <- idx[fin]
    if (fin > 1) { r <- idx[seq_len(fin - 1)]; Q[r] <- traj[seq_len(fin - 1)]; s[r] <- mu2[r] }
    s[e] <- Q[e - 1] + lambda[e]; Q[e] <- 0           # se vacía
    i <- e + 1
  }
  list(Q = Q, s = s, w = esperas_cohortes(lambda, s))
}

# Espera FIFO de cada cohorte (minuto de llegada): distancia horizontal entre la
# curva acumulada de llegadas A(t) y la de salidas D(t), evaluada en el vehículo
# central de la cohorte (llegadas y salidas uniformes dentro de cada minuto).
esperas_cohortes <- function(lambda, s) {
  n <- length(lambda)
  A <- c(0, cumsum(lambda)); D <- c(0, cumsum(s))
  x <- (A[-1] + A[-(n + 1)]) / 2
  j <- findInterval(x, D, left.open = TRUE)          # D[j] < x <= D[j + 1]
  j <- pmin(pmax(j, 1), n)
  td <- (j - 1) + (x - D[j]) / pmax(D[j + 1] - D[j], 1e-12)
  w <- pmax(td - (seq_len(n) - 0.5), 0)
  w[lambda <= 0] <- 0
  w
}

hora_punta_idx <- function(lambda) {
  n <- length(lambda); cs <- cumsum(lambda)
  tot <- cs[60:n] - c(0, cs[seq_len(n - 60)])
  fin <- which.max(tot) + 59
  (fin - 59):fin
}

# Lo que vería el aforo: una hora cuenta como congestionada si al menos el 60 %
# (UMBRAL_LENTO) de los vehículos que pasan en ella lo hace con cola, igual que en
# los aforos (>= 60 % de vehículos a menos de 80 km/h). Así el modelo se calibra y
# se valida con la misma vara de medir que los datos (horas enteras).
horas_como_aforo <- function(s, Q, umbral = 0.6) {
  h <- rep(0:23, each = 60)[seq_along(s)]
  frac <- tapply(s * (Q > 0.5), h, sum) / pmax(tapply(s, h, sum), 1e-9)
  marcadas <- as.integer(names(frac)[frac >= umbral])
  list(horas = length(marcadas), inicio = if (length(marcadas)) min(marcadas) else NA_real_,
       fin = if (length(marcadas)) max(marcadas) + 1 else NA_real_)
}

metricas <- function(lambda, sim, joroba) {
  w <- sim$w; hp <- hora_punta_idx(lambda)
  af <- horas_como_aforo(sim$s, sim$Q)
  list(demora_vh           = sum(lambda * w) / 60,                 # vehículos·hora de demora en el día
       demora_media_punta  = sum(lambda[hp] * w[hp]) / sum(lambda[hp]),  # min/veh, todos los que llegan en la hora punta
       demora_media_joroba = if (sum(joroba) > 0) sum(joroba * w) / sum(joroba) else 0,  # usuarios de la punta (demanda elástica)
       demora_media_dia    = sum(lambda * w) / sum(lambda),        # min/veh sobre todo el día
       espera_max          = max(w),
       cola_max            = max(sim$Q),
       min_con_cola        = sum(sim$Q > 0.5),
       inicio_cola         = if (any(sim$Q > 0.5)) which(sim$Q > 0.5)[1] - 1 else NA_real_,   # minuto del día
       fin_cola            = if (any(sim$Q > 0.5)) max(which(sim$Q > 0.5)) else NA_real_,
       horas_aforo         = af$horas, inicio_aforo = af$inicio, fin_aforo = af$fin,   # horas enteras, como los aforos
       cola_final          = sim$Q[length(sim$Q)])
}

# cap_hora y caida son la capacidad antes de la cola y la caída con cola (número o
# vector por minuto). Si el perfil trae la especificación de la descarga, se aplican
# aquí, igual en todas las alternativas:
#   · f_cap: capacidad en vehículos según la parte de pesados de cada hora;
#   · f_desc: factor por hora del caudal que descarga con cola.
evaluar <- function(prof, cap_hora, caida, escala_joroba = 1) {
  lam <- prof$base + escala_joroba * prof$joroba
  if (!is.null(prof$f_cap)) cap_hora <- cap_hora * prof$f_cap
  if (!is.null(prof$f_desc)) caida <- 1 - (1 - caida) * prof$f_desc
  sim <- simular_cola(lam, cap_hora, caida)
  c(metricas(lam, sim, prof$joroba), list(Q = sim$Q, w = sim$w, s = sim$s, lambda = lam))
}

# Equilibrio con demanda inducida: escala s de la joroba tal que
#   s = ((T_libre + d(s)) / (T_libre + d_ref))^eta     (eta < 0)
# d = demora media de los usuarios de la punta (la parte elástica de la demanda).
# Con permitir_supresion = TRUE también resuelve el caso contrario: si la demora
# empeora respecto a d_ref (más demanda de fondo y misma capacidad), parte de la
# joroba se va a otras horas o deja de viajar (s < 1). Es la misma elasticidad
# aplicada en los dos sentidos (Goodwin, 1996; Cairns et al., 2002).
equilibrio_inducido <- function(prof, cap_hora, caida, eta, T_libre, d_ref, permitir_supresion = FALSE) {
  if (eta == 0) return(1)
  f <- function(s) {
    d <- evaluar(prof, cap_hora, caida, s)$demora_media_joroba
    s - ((T_libre + d) / (T_libre + d_ref))^eta
  }
  f1 <- f(1)
  if (f1 >= 0) {                                       # la demora no baja respecto a d_ref
    if (!permitir_supresion || f1 < 1e-9) return(1)
    lo <- 0.5; while (f(lo) > 0 && lo > 1 / 64) lo <- lo / 2
    return(uniroot(f, c(lo, 1), tol = 1e-3)$root)
  }
  hi <- 2; while (f(hi) < 0 && hi < 16) hi <- hi * 2
  uniroot(f, c(1, hi), tol = 1e-3)$root
}

# Desplaza una fracción p de la joroba a ±30-90 min (escalonamiento horario).
# Conserva los vehículos: lo que caería fuera del día se reescala dentro.
escalonar <- function(joroba, p) {
  if (p <= 0) return(joroba)
  n <- length(joroba); desplazada <- numeric(n); desfases <- 30:90
  for (d in desfases) {
    antes   <- c(joroba[(d + 1):n], rep(0, d))
    despues <- c(rep(0, d), joroba[1:(n - d)])
    desplazada <- desplazada + 0.5 * (antes + despues) / length(desfases)
  }
  if (sum(desplazada) > 0) desplazada <- desplazada * sum(joroba) / sum(desplazada)
  (1 - p) * joroba + p * desplazada
}

# ---- Escenarios ----------------------------------------------------------------
# p: lista con los parámetros de una realización (ver 05_montecarlo.R)
# prof: perfil observado opcional (si es NULL se construye el sintético, centrado
#   en p$t0_punta si existe)
# holgura_t: holgura del tramo siguiente minuto a minuto (si es NULL se usa el
#   valor único p$holgura_aguas_abajo). Con caudales horarios se sabe que la
#   holgura cambia mucho de una hora a otra de la punta.
# incidente: c(inicio, fin) en minutos del día con un carril cortado (escenario
#   adverso); NULL = día sin incidentes.
# Horizontes: corto = primer año, medio = 5 años, largo = 10 años. La demanda
# inducida usa la elasticidad de cada horizonte (eta_corto, eta_medio, eta_largo).
HORIZONTES <- c("corto", "medio", "largo")

eta_horizonte <- function(p, h) {
  if (h == "medio" && is.null(p$eta_medio)) return(eta_medio(p$eta_corto, p$eta_largo, 0.75))
  p[[paste0("eta_", h)]]
}

# Elasticidad a 5 años con ajuste parcial geométrico entre el primer año y el
# décimo: cada año se recorre una fracción (1 - rho) de lo que falta (Hymel, Small y
# Van Dender, 2010, estiman rho = 0,71-0,79 con datos anuales). Parte del primer año
# (eta_corto) y llega a eta_largo en el año 10.
eta_medio <- function(eta_corto, eta_largo, rho) {
  w5 <- (1 - rho^4) / (1 - rho^9)
  eta_corto + (eta_largo - eta_corto) * w5
}

# Perfil de demanda de una combinación de parámetros: híbrido si se pasan los aforos
# horarios del cuello (obs = list(veh_hora, ventana)); sintético si no (Bus-VAO y pruebas)
perfil_de <- function(p, V_dir, obs = NULL) {
  t0 <- if (!is.null(p$t0_punta)) p$t0_punta else T0_PUNTA
  if (is.null(obs)) return(perfil_demanda(V_dir, p$k_dir, p$sigma_punta, p$cuota_noche, t0))
  prof <- perfil_hibrido(obs$veh_hora, obs$ventana, t0, p$sigma_punta, V_dir)
  aplicar_especificacion(prof, p, obs)
}

# Especificación de la descarga (obs$especificacion, ver 12_validacion_predictiva.R):
#   propagacion (lógico), factor_descarga (24 valores, 1 = sin cambio) y
#   cuota_pesados (24 valores) con el parámetro equivalencia_pesados de cada combinación.
aplicar_especificacion <- function(prof, p, obs) {
  e <- obs$especificacion
  if (is.null(e)) return(prof)
  prof$propagacion <- isTRUE(e$propagacion)
  if (!is.null(e$factor_descarga)) prof$f_desc <- rep(e$factor_descarga, each = 60)
  if (!is.null(e$cuota_pesados) && !is.null(p$equivalencia_pesados))
    prof$f_cap <- rep(factor_pesados(e$cuota_pesados, p$equivalencia_pesados, e$hora_referencia), each = 60)
  prof
}

# Capacidad en vehículos/hora de cada hora frente a la de la hora de referencia, si la
# capacidad en vehículos equivalentes es constante y cada pesado equivale a E ligeros
factor_pesados <- function(cuota, E, hora_ref = 7) {
  (1 + (E - 1) * cuota[hora_ref + 1]) / (1 + (E - 1) * cuota)
}

factor_incidente <- function(incidente, carriles) {
  f <- rep(1, DURACION_MIN)
  if (!is.null(incidente)) f[(incidente[1] + 1):incidente[2]] <- (carriles - 1) / carriles
  f
}

# Capacidad antes de la cola (pre) y caudal con cola (dis), minuto a minuto, de una
# alternativa. D es lo que admite el tramo siguiente: la descarga actual (sin incidente)
# por (1 + holgura). Sin propagación, la holgura negativa cuenta como 0 y D solo limita
# lo que se añade (tercer carril, regulación de accesos); con propagación, D limita
# también la situación actual (la cola de abajo frena el cuello).
#   ht: holgura por minuto (NULL = sin dato: no hay límite aguas abajo, salvo el valor
#       único p$holgura_aguas_abajo para el tercer carril)
#   alternativa: "actual", "tercer_carril" o "regulacion"
# D está en unidades del modelo: la holgura es relativa (cuánto más podría pasar, en
# proporción al caudal del cuello en esa hora), así que se aplica a la descarga del modelo
# en esa hora. Por eso evaluar() aplica a D, igual que al cuello, los factores de pesados y
# de la hora de la especificación: si el modelo descarga en esa hora lo que mide el aforo,
# D coincide con lo que admite el tramo siguiente en vehículos.
capacidades <- function(p, carriles, ht = NULL, incidente = NULL, propagacion = FALSE, alternativa = "actual") {
  c_n <- carriles * p$c_carril
  cap0 <- c_n * factor_incidente(incidente, carriles)
  desc0 <- c_n * (1 - p$caida_capacidad)
  h <- if (is.null(ht)) NULL else if (propagacion) ht else pmax(ht, 0)
  D <- if (is.null(h)) rep(Inf, DURACION_MIN) else rep_len(desc0 * (1 + h), DURACION_MIN)
  D <- pmax(D, 1)
  pre <- if (propagacion) pmin(cap0, D) else rep_len(cap0, DURACION_MIN)
  dis <- if (propagacion) pmin(cap0 * (1 - p$caida_capacidad), D) else rep_len(cap0 * (1 - p$caida_capacidad), DURACION_MIN)
  if (alternativa == "regulacion") {
    dis <- pmin(cap0 * (1 - p$caida_capacidad * (1 - p$eficacia_rm)), D)
    dis <- pmax(dis, if (propagacion) pmin(cap0 * (1 - p$caida_capacidad), D) else cap0 * (1 - p$caida_capacidad))
  }
  if (alternativa == "tercer_carril") {
    if (is.null(h)) D <- rep_len(desc0 * (1 + max(p$holgura_aguas_abajo, 0)), DURACION_MIN)
    cap_max <- (carriles + 1) * p$c_carril * factor_incidente(incidente, carriles + 1)
    pre <- pmax(pre, pmin(cap_max, D))
    dis <- pmax(dis, pmin(cap_max * (1 - p$caida_capacidad), D))
  }
  list(antes = pre, con_cola = dis, caida = 1 - dis / pre)
}

# Compatibilidad: capacidad con el tercer carril limitada por el tramo siguiente
capacidad_tercer_carril <- function(p, carriles, holgura, cap0 = carriles * p$c_carril, incidente = NULL) {
  r <- capacidades(p, carriles, rep_len(holgura, DURACION_MIN), incidente, FALSE, "tercer_carril")
  list(antes = r$antes, con_cola = r$con_cola, caida = r$caida)
}

# Situación actual de una combinación (con la especificación de su perfil)
evaluar_actual <- function(p, carriles, prof, ht = NULL, incidente = NULL, escala = 1) {
  cb <- capacidades(p, carriles, ht, incidente, isTRUE(prof$propagacion))
  evaluar(prof, cb$antes, cb$caida, escala)
}

escenarios_cuello <- function(p, V_dir, carriles, con_tercer_carril = TRUE, prof = NULL, holgura_t = NULL,
                              incidente = NULL) {
  if (is.null(prof)) prof <- perfil_de(p, V_dir)
  prop <- isTRUE(prof$propagacion)
  cb <- capacidades(p, carriles, holgura_t, incidente, prop)
  base <- evaluar(prof, cb$antes, cb$caida)
  d0   <- base$demora_media_joroba
  res  <- list()
  res$base <- base
  # Mejora con demanda inducida en los tres horizontes
  con_inducida <- function(nombre, prof_x, cap_x, caida_x) {
    for (h in HORIZONTES) {
      s <- equilibrio_inducido(prof_x, cap_x, caida_x, eta_horizonte(p, h), p$T_libre, d0)
      r <- evaluar(prof_x, cap_x, caida_x, s); r$escala <- s
      res[[paste0(nombre, "_", h)]] <<- r
    }
  }

  # 1) Tercer carril: +1 carril en el cuello, limitado por lo que admite el tramo
  #    siguiente (D = descarga actual x (1 + holgura)): antes de la cola pasa como mucho
  #    min((carriles + 1) x capacidad, D); con cola, min((carriles + 1) x capacidad x
  #    (1 - caída), D); nunca menos que hoy. Con propagación y holgura negativa, el
  #    tercer carril no añade nada: el tramo siguiente ya limita.
  if (con_tercer_carril) {
    tc <- capacidades(p, carriles, holgura_t, incidente, prop, "tercer_carril")
    con_inducida("tercer_carril", prof, tc$antes, tc$caida)
  }

  # 2) Regulación de accesos (ramp metering): evita parte de la caída de capacidad,
  #    sin pasar de lo que admite el tramo siguiente (el mismo límite D).
  rm <- capacidades(p, carriles, holgura_t, incidente, prop, "regulacion")
  con_inducida("ramp_metering", prof, rm$antes, rm$caida)

  # 3) Escalonamiento horario institucional (colegios, ULL, Administración): desplaza
  #    parte de la joroba a los hombros de la punta. La demora que ahorra atrae
  #    tráfico nuevo a la punta, igual que una obra (mismas elasticidades).
  prof_esc <- prof; prof_esc$joroba <- escalonar(prof$joroba, p$desplazamiento_horario)
  con_inducida("escalonamiento", prof_esc, cb$antes, cb$caida)

  # 4) Tarificación de la punta: la reducción de la demanda de punta observada en
  #    Estocolmo, Londres o Nueva York ya es neta (incluye el tráfico que vuelve con
  #    el peaje en vigor), así que no se le añade demanda inducida.
  res$tarificacion <- evaluar(prof, cb$antes, cb$caida, 1 - p$reduccion_tarificacion)

  # 5) Paquete de gestión: regulación de accesos + escalonamiento (sin peaje), con la
  #    misma demanda inducida que las demás alternativas
  con_inducida("paquete_gestion", prof_esc, rm$antes, rm$caida)

  res
}

# Tercer carril con varias holguras aguas abajo (para separar escenarios físicos)
tercer_carril_por_holgura <- function(p, V_dir, carriles, holguras, prof = NULL) {
  if (is.null(prof)) prof <- perfil_de(p, V_dir)
  base <- evaluar(prof, carriles * p$c_carril, p$caida_capacidad)   # holgura fija >= 0: no frena la situación actual
  d0 <- base$demora_media_joroba
  out <- lapply(holguras, function(hg) {
    tc <- capacidades(p, carriles, rep(hg, DURACION_MIN), NULL, FALSE, "tercer_carril")
    r <- vapply(c("corto", "largo"), USE.NAMES = FALSE, function(h) {
      s <- equilibrio_inducido(prof, tc$antes, tc$caida, p[[paste0("eta_", h)]], p$T_libre, d0)
      evaluar(prof, tc$antes, tc$caida, s)$demora_vh
    }, numeric(1))
    tibble(holgura = hg, horizonte = c("corto", "largo"),
           reduccion = if (base$demora_vh > DEMORA_MINIMA_VH) 1 - r / base$demora_vh else NA_real_)
  })
  bind_rows(out)
}

# Bus-VAO convirtiendo un carril existente en punta (lo que plantea el proyecto
# del Cabildo: el carril izquierdo se reserva en hora punta). ¿Qué fracción m
# de los vehículos tiene que pasar al carril reservado (guaguas, taxis, motos,
# coches con 2+ ocupantes) para que la demora media por vehículo del tráfico
# general en la hora punta:
#   objetivo = 0   -> no empeore (equilibrio)
#   objetivo = 0,5 -> baje a la mitad (lo que anuncia el proyecto en un sentido)?
# Nota: en una cola puntual, demanda y capacidad proporcionales dan la misma
# espera por vehículo, así que el equilibrio sale m = 1/carriles. Es un umbral
# necesario, no una prueba de que exista esa demanda elegible.
trasvase_bus_vao <- function(p, V_dir, carriles, objetivo = 0, prof = NULL) {
  if (carriles < 2) return(NA_real_)
  if (is.null(prof)) prof <- perfil_de(p, V_dir)
  d_base <- evaluar(prof, carriles * p$c_carril, p$caida_capacidad)$demora_media_punta
  if (d_base <= 0) return(NA_real_)
  f <- function(m) {
    prof_m <- prof; prof_m$base <- prof$base * (1 - m); prof_m$joroba <- prof$joroba * (1 - m)
    evaluar(prof_m, (carriles - 1) * p$c_carril, p$caida_capacidad)$demora_media_punta - (1 - objetivo) * d_base
  }
  if (f(0) <= 0) return(0)
  uniroot(f, c(0, 0.99), tol = 1e-4)$root
}

# ---- Dos cuellos en serie con almacenamiento finito (restricción aguas abajo) ----
# Cuello A (el modelado) y tramo siguiente B, con un almacenamiento de N vehículos entre
# los dos (longitud x carriles x densidad de atasco) y entradas por ramales r(t) entre A y
# B. Minuto a minuto:
#   · A descarga como mucho su capacidad (pre sin cola, con cola la caída);
#   · B descarga como mucho cap_B; lo que no pasa se acumula entre A y B (cola remanente);
#   · si el almacenamiento se llena, lo que entra (desde A y desde los ramales) se limita
#     al hueco que deja B: la cola remonta hasta A (rebosa) y bloquea las incorporaciones;
#     el hueco se reparte entre el tronco y los ramales en proporción a lo que llega.
# Conserva los vehículos en cada minuto: llegadas acumuladas (A + ramales) = salidas de B
# + cola en A + cola entre A y B + cola en los ramales. Con N = 0 y sin ramales equivale a
# un cuello con capacidad min(A, B) (la especificación con propagación).
simular_tandem <- function(lambda, pre_A, caida_A, cap_B, r = 0, almacen = Inf, eps = 1e-9) {
  n <- length(lambda)
  preA <- rep_len(pre_A, n) / 60; disA <- preA * (1 - rep_len(caida_A, n))
  muB <- rep_len(cap_B, n) / 60; rr <- rep_len(r, n)
  QA <- QB <- QR <- 0
  out <- matrix(0, n, 7, dimnames = list(NULL, c("QA", "QB", "QR", "sA", "rin", "sB", "rebosa")))
  for (t in seq_len(n)) {
    capA <- if (QA > eps) disA[t] else preA[t]
    a <- min(QA + lambda[t], capA)                 # lo que A podría dejar pasar
    b <- QR + rr[t]                                # lo que los ramales querrían meter
    tot <- QB + a + b
    sB <- min(tot, muB[t])
    hueco <- almacen - QB + sB                     # sitio al final del minuto entre A y B
    rebosa <- (a + b) > hueco + eps
    if (rebosa) { k <- max(hueco, 0) / (a + b); a_in <- a * k; b_in <- b * k } else { a_in <- a; b_in <- b }
    QA <- QA + lambda[t] - a_in; QR <- QR + rr[t] - b_in; QB <- QB + a_in + b_in - sB
    out[t, ] <- c(QA, QB, QR, a_in, b_in, sB, rebosa)
  }
  as.data.frame(out)
}

# Resumen de una simulación en serie: demora (vehículos·hora) en A, entre A y B (cola
# remanente) y en los ramales bloqueados; cola máxima entre A y B y minutos con rebose
resumen_tandem <- function(x) {
  list(demora_vh = sum(x$QA + x$QB + x$QR) / 60, demora_A_vh = sum(x$QA) / 60, demora_B_vh = sum(x$QB) / 60,
       demora_ramales_vh = sum(x$QR) / 60, cola_B_max = max(x$QB), minutos_rebose = sum(x$rebosa > 0),
       salidas_B = sum(x$sB))
}
