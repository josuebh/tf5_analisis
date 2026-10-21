# Análisis integral y modelización predictiva de la congestión de la autopista TF-5 en Tenerife: diagnóstico, evolución y evaluación de alternativas de mejora

Proyecto en R · datos hasta septiembre de 2026 · ejecución del 21 de octubre de 2026

Es un **estudio técnico-predictivo con simulación exploratoria**, hecho solo con datos públicos. Responde a tres
preguntas y separa siempre lo que se mide de lo que se estima:

| Pregunta | Con qué | En `main.R` |
|---|---|---|
| **Qué sabemos** | Aforos oficiales del Cabildo de Tenerife: IMD 2018-2025 y 942.041 registros horarios por carril de la TF-5 en 24 ficheros mensuales (septiembre de 2024 a septiembre de 2026, sin diciembre de 2024) | Secciones 1-4 y 4b |
| **Qué estimamos** | Capacidad de cada tramo, capacidad libre del tramo siguiente y balance entre estaciones, deducidos de los aforos; modelo de cola de un día laborable completo en cada cuello, calibrado con 2025, con la especificación de la descarga elegida por validación cruzada dentro de 2025 y contrastado con enero-septiembre de 2026 | Secciones 5-7 |
| **Qué prevemos** | El mismo modelo con la demanda de 2030 y 2035 (crecimiento bajo, central y alto), con cada alternativa, con retrasos de obra, en escenarios adversos y a 1, 5 y 10 años de ponerla en marcha | Sección 8 |

### Cómo leer cada cifra

Cada resultado lleva una de estas etiquetas (columna `categoria` de `datos/limitaciones_por_resultado.csv`, que
tipifica 25 resultados; las tablas de resultados simulados la repiten, y `graficos_metadatos.csv` la da para
cada gráfico con su horizonte, su hipótesis y su incertidumbre):

- **Observado:** sale directamente de los aforos oficiales o de documentos, con las reglas de depuración
  declaradas. Ejemplo: las horas de cola de cada día.
- **Estimado:** se deduce de los aforos con un método explícito. Ejemplo: la capacidad libre del tramo siguiente.
- **Supuesto:** un valor o una regla que no sale de los datos del proyecto y se declara. Ejemplos: el crecimiento
  de la demanda, las elasticidades de la literatura o la longitud entre dos cuellos.
- **Simulado:** lo da el modelo calibrado bajo esos supuestos. Es un escenario condicionado, no una observación ni
  una previsión segura.
- **Asociación no causal:** coincidencia temporal entre una actuación y un cambio en los aforos, sin un grupo de
  control válido.

Dos bandas distintas acompañan a las cifras simuladas:
- la **banda de parámetros p10-p90** describe la población de combinaciones de parámetros compatibles con los
  aforos de 2025 para un día típico. No es una probabilidad de lo que pasará ni un intervalo predictivo;
- el **intervalo predictivo del 80 %** le suma la variabilidad de un día a otro y el error de observación, y su
  cobertura se mide en días no usados para calibrar (apartado 2.5).

Cada número lleva su fuente. La procedencia de los 37 ficheros oficiales usados está en
`salidas/tablas/procedencia_datos.csv`, y las fuentes documentales, en `datos/fuentes_documentales.csv`. Los
parámetros que usa el modelo en cada cuello, con su rango y su fuente, están en
`salidas/tablas/parametros_usados_caso1.csv` y `_caso2.csv` (los valores por defecto, en
`datos/parametros_modelo.csv`). Los datos que faltan, cómo se suplen y en qué estado está su petición, en
`datos/matriz_lagunas.csv`, con la petición preparada para el Cabildo en `docs/solicitud_datos_cabildo.md`. El método
completo está en `docs/METODOLOGIA.md`, y los diez criterios de calidad del estudio, cómo se comprueban y con qué
resultado, en `docs/VALIDACION_Y_CALIDAD.md`.

## Contraste de los originales con el portal

La madrugada del 17-10-2026 (hora canaria; `consultado_utc` en la evidencia) se volvieron a consultar por descarga directa, fuera de `main.R`, los **37 recursos oficiales** (8 CSV de IMD, 5 recursos auxiliares y 24 TXT horarios). Las 37 huellas SHA-256 coinciden con las registradas. Además, se cotejaron las **942.041 filas** de los extractos horarios con los mismos campos de los TXT actuales, respetando las estaciones seleccionadas en los metadatos de cada mes; todas coinciden. Evidencia y herramienta reproducible: `docs/contraste_fuentes/contraste_37_recursos_oficiales.csv` y `herramientas/comprobaciones/contrastar_fuentes.py`.

## La respuesta en una tabla

¿Qué solución parece más eficaz, en qué tramo, en qué horario, durante cuánto tiempo y bajo qué condiciones?
Indicador: **reducción de los vehículos·hora de demora de un día laborable frente a no actuar** (simulado;
mediana y banda de parámetros p10-p90 de las combinaciones calibradas).

| | Mañana hacia Santa Cruz | Tarde hacia el Norte |
|---|---|---|
| **Dónde** (observado) | Los Rodeos-Guamasa (Ermita Cruz Chica, 2 carriles). A las 7 h se suma un segundo cuello en La Laguna | Bomberos La Laguna, justo antes de pasar de 3 a 2 carriles hacia Los Rodeos |
| **Cuándo** (observado) | De 6 a 9 h; 215 de 226 días laborables de 2025 con cola entre las 3 y las 13 h. Igual en 2026 | De 13 a 18 h; 224 de 224 días laborables de 2025, con cola entre las 11 y las 24 h. Igual en 2026 |
| **Reducción el primer año, por mediana** (simulado) | Tarificación de la punta (no la permite la ley) 61 % (38-99 %); regulación de accesos + escalonamiento 48 % (32-73 %); tercer carril 40 % (22-73 %); regulación de accesos 34 % (20-55 %); escalonamiento horario 17 % (10-31 %) | Tercer carril hipotético (no proyectado) 72 % (34-99 %); regulación de accesos + escalonamiento 62 % (38-81 %); regulación de accesos 55 % (30-74 %); tarificación de la punta (no la permite la ley) 47 % (29-100 %); escalonamiento horario 10 % (6-19 %) |
| **¿Cuál reduce más?** Tercer carril frente a regulación + escalonamiento, combinación a combinación (simulado) | Diferencia de −8,0 puntos (−18,6 a +11,0); depende de los parámetros (la banda de la diferencia cruza el 0) | Diferencia de +6,1 puntos (−7,9 a +28,3); depende de los parámetros (la banda de la diferencia cruza el 0) |
| **Cuánto dura** (simulado; a 10 años, con la demanda inducida) | Tercer carril: 40 % el 1er año → 33 % (18-60 %). Regulación + escalonamiento: 48 % → 39 % (24-59 %) | Regulación + escalonamiento: 62 % → 55 % (33-73 %). Tercer carril hipotético: 72 % → 64 % (30-96 %) |
| **Con qué confianza** | Tercer carril, media; regulación de accesos y paquete de gestión, baja; escalonamiento solo, media | Tercer carril hipotético, media; gestión, baja; escalonamiento solo, media |
| **Coste y plazo** (documental) | Tercer carril: 58,2 M€, contrato de 2-10-2026 con 35 meses de plazo. Regulación de accesos: 1,8-4 M€, sin fecha. Escalonamiento: sin coste de obra, en marcha en la ULL | Tercer carril: no proyectado. Gestión: la misma que por la mañana |
| **De qué depende** (estimado) | De la capacidad libre del tramo de La Laguna, que a las 7 h es de 0,6 % (−4,8 % a 9,8 %); sin capacidad libre el 44 % de los días. Con las estimaciones compatibles con las colas medidas, el tercer carril rendiría el 1er año entre nada, si no queda capacidad libre (los aforos no descartan ese caso), y un 61 %; con alguna capacidad libre, entre un 24 % y un 61 % | De la caída de capacidad, que los aforos horarios no permiten medir, y de la capacidad libre de La Matanza: a las 15 h, 2,8 % (−0,6 % a 9,8 %); sin capacidad libre el 14 % de los días |
| **Si la demanda crece un 0,5 % al año** (simulado; horas de cola: media y p10-p90) | Sin actuar, la cola pasaría de 3,0 h al día (hoy, en el modelo) a 5,5 (4-6) h en 2035. En 2030 el tercer carril rendiría 40 % (22-68 %) | Sin actuar, de 4,0 a 6,5 (5-8) h al día en 2035. En 2030 la regulación + escalonamiento rendiría 60 % (39-75 %) |

**En pocas palabras** (escenarios del modelo, no certezas). Por la mañana, el tercer carril contratado y la gestión
de la demanda (regulación de accesos + escalonamiento) reducen en el modelo la demora un 40 % y un
48 % el primer año (medianas), con bandas anchas. Comparadas combinación a combinación, cuál de los dos reduce más depende de los parámetros (la banda de la diferencia cruza el 0).
Por eso el estudio no elige entre los dos por el efecto simulado: los distinguen sobre todo el coste, el plazo y los riesgos.
La gestión podría funcionar años antes y cuesta una fracción, pero su efecto descansa en parámetros tomados
de la literatura; el tercer carril está contratado y su efecto depende de cuánta capacidad libre quede en el tramo de
La Laguna, que solo se puede estimar de forma indirecta (con las estimaciones compatibles con las colas medidas,
entre nada, si ese tramo está lleno, y un 61 % el primer año; entre un 24 % y un 61 % si le queda alguna capacidad libre). Por la tarde no hay obra prevista y
solo la gestión puede actuar a corto plazo; un tercer carril hacia el Norte entre Los Rodeos y Guamasa (no
proyectado) daría 72 % (34-99 %) en el modelo, limitado por La Matanza; frente a la gestión, cuál de los dos reduce más depende de los parámetros (la banda de la diferencia cruza el 0). Si
la demanda sigue creciendo, en el modelo las colas se alargan y todas las mejoras se erosionan.

## Abrir el panel sin instalar nada

Extrae el ZIP completo y abre `panel/index.html` en tu navegador. Los datos, el código gráfico y los estilos están incluidos en `panel/assets/`; los gráficos y tablas funcionan sin conexión.

Después de una nueva ejecución de R y de las pruebas, actualiza los documentos y los datos empaquetados del panel:

```bash
python3 herramientas/documentos/rellenar.py
python3 herramientas/panel/preparar_panel.py
```

## Cómo ejecutarlo

Instala R por separado (R 4.3.3 reproduce el entorno de la ejecución original). `renv::restore()` restaura los paquetes del proyecto y no instala el intérprete de R.

```r
# Una sola vez. Versiones con las que se generaron los resultados: renv.lock
install.packages("renv")
renv::activate()  # activa el entorno de este proyecto; si R reinicia, continúa con restore
renv::restore()   # restaura paquetes; instala R 4.3.3 por separado (ver entorno/versiones_paquetes.csv)
# Sin renv: install.packages(c("dplyr", "tidyr", "readr", "ggplot2", "scales", "ggrepel",
#                              "patchwork", "jsonlite", "digest", "testthat"))
```

```bash
# Desde la carpeta del proyecto:
Rscript main.R                                                    # análisis completo: unos 63 minutos
TF5_N_SIM=2000 TF5_N_REJILLA=2000 TF5_N_PREV=200 Rscript main.R   # ejecución rápida (menos simulaciones)
Rscript tests/ejecutar_pruebas.R                                  # 72 bloques de pruebas, 2.536 comprobaciones
Rscript tests/comparar_ejecuciones.R tests/referencia salidas/tablas ../informe.csv --solo-referencia   # salida 1 si detecta diferencias (informe fuera de la carpeta: verificar_entrega.py exige que todo lo que haya dentro esté en el manifiesto)
```

En RStudio: abre la carpeta como proyecto (o haz `setwd()` en ella) y pulsa *Source* en `main.R`.

Al empezar, `main.R` fija la zona horaria (`Atlantic/Canary`), compara las versiones instaladas con
`entorno/versiones_paquetes.csv` y lo anota en `salidas/tablas/entorno_versiones.csv`. Con otras versiones el
análisis corre igual, pero lo avisa. Todos los avisos de la ejecución se guardan en `salidas/registro_avisos.txt`
(0 en la ejecución entregada) y las opciones usadas (simulaciones, semillas y zona horaria), en
`salidas/configuracion_ejecucion.csv`.

**No hace falta Internet:** todos los datos están en `datos/` con la huella SHA-256 que se registró al
descargarlos. La huella prueba que la copia no ha cambiado desde la descarga (integridad), no que el origen sea
auténtico, y la autenticidad no se puede probar desde dentro del proyecto. Lo que hay son dos contrastes: la tabla
de procedencia compara el tamaño y la fecha de modificación de cada fichero con los de una instantánea del catálogo
del portal guardada el 16-10-2026 (`datos/oficial/catalogo_portal_2026-10-16.json`), y una muestra de recursos se
contrastó ese día con el catálogo nacional datos.gob.es (`contraste_publicacion_original.csv`). Las huellas y las
sumas de control de los TXT originales las calculó al descargarlos un script del navegador que no se conserva; queda
su registro (`datos/horarios/meta_AAAA-MM.json`). Dos opciones del principio de `main.R` permiten repetir el
contraste contra el portal:

- `DESCARGAR_HORARIOS <- TRUE`: vuelve a bajar los 24 ficheros horarios oficiales (unos 230 MB) y comprueba que su
  SHA-256 es el registrado. Para añadir un mes nuevo, agrega su enlace a `datos/fuentes_horarias.csv`.
- `CONTRASTAR_EN_LINEA <- TRUE`: contrasta además la IMD con el portal y guarda una instantánea nueva del
  catálogo, que pasa a usar la tabla de procedencia.

En la ejecución entregada no se volvió a descargar nada.

## 1. Qué sabemos: datos observados

### Aforos anuales

La estación más cargada en 2025 es Padre Anchieta (117.791 veh/día). Entre 2019 y 2025 el tráfico del
corredor La Laguna-La Orotava (siete estaciones) apenas cambia (de −7,0 % en Campus Guajara a +4,1 % en Padre Anchieta),
mientras la población de Tenerife crece un 0,95 % anual entre 2021 y 2025 (de 930.570 a 966.469
habitantes, INE). En un tramo saturado el aforo mide lo que cabe, no lo que se querría circular. Por
carril, el tramo más cargado es Los Rodeos-Guamasa (Ermita Cruz Chica, 2 carriles): 22.674 veh/día/carril
hacia Santa Cruz y 22.282 hacia el Norte. Su «k crítico» (parte del tráfico diario que llenaría la
capacidad en una hora) es del 8,6 % y el 8,8 %, por debajo de la cuota habitual de la hora punta: se
satura casi todos los días laborables.

### Procedencia y calidad de los aforos horarios

- **Procedencia** (`procedencia_datos.csv`, una fila por recurso). Cada fila recoge el organismo, el conjunto de
  datos, la URL, el identificador, la licencia, la fecha de modificación en origen, la de descarga, el tamaño, el
  SHA-256 del original y de la copia, la cobertura, los filtros y las unidades. De los 37 ficheros
  descargados:
  - 37 copias están íntegras (mismo SHA-256 que al descargarlas);
  - 37 coinciden en tamaño y fecha con el recurso de la instantánea del catálogo del 16-10-2026;
  - en 24 de 24 extractos horarios, los totales por estación y sentido son las sumas de control que se
    registraron al descargar el TXT original;
  - 13 de 13 recursos de 2025 (los 12 TXT y su diccionario) coinciden en URL, identificador, nombre y licencia con
    el catálogo nacional datos.gob.es, consultado el 16-10-2026 (`contraste_publicacion_original.csv`).

  La correspondencia entre los campos de los ficheros oficiales y los del proyecto, con la definición de cada uno
  en el diccionario oficial, está en `correspondencia_de_campos.csv`. Quedan 3 recursos publicados sin usar,
  registrados como huecos: diciembre de 2024 y los diccionarios de datos de 2024 y 2026 (los datos de esos años se
  leen con el de 2025; la cabecera de los 24 TXT es la misma).
- **Registros:** 942.041 registros horarios por carril en 24 meses. Se validan con 9 reglas (H1-H9,
  `validacion_horarios.csv`), y la IMD se contrasta valor a valor con las copias locales de los CSV oficiales:
  555 valores, 0 diferencias.
- **Serie depurada con banderas** (`horarios_corredor_con_banderas.csv.gz`). Tiene una fila por estación, sentido,
  día y hora, y los extractos originales no se tocan. Las banderas marcan:
  - laborable, hora completa, velocidad utilizable, duplicado, rangos negativos, caudal implausible, agosto,
    cambio de hora y día válido;
  - el estado de la hora (observada, imputada o excluida) y el motivo de la exclusión.

  **No se imputa nada.** Las horas incompletas se excluyen: la tasa de imputación es del 0 % en todas las
  estaciones, meses y horas (`cobertura_e_imputacion_por_estacion_mes_hora.csv`, con la cobertura de cada celda).
- **Sensibilidad a la depuración** (`sensibilidad_depuracion.csv`). Se probó a quitar el filtro del tráfico diario,
  hacerlo más estricto, incluir agosto e imputar con dos métodos (proporcional y mediana de la misma hora y mes) las
  horas a las que les falta un carril. En los dos cuellos, la media de horas de cola cambia como mucho
  0,21 h y la descarga mediana 15,0 veh/h. Las variantes de imputación no cambian nada en los cuellos,
  porque allí no hay horas así.
- **Días atípicos** (`dias_atipicos.csv`, `dias_atipicos_resumen.csv`). Cada día laborable de cada estación y
  sentido tiene su estado (usado o excluido) y su motivo. Se excluyen agosto, los días incompletos (avería o corte
  del aforador) y los de tráfico por debajo del 85 % de la mediana del mes; se marcan, y se prueba el análisis sin
  ellos, los puentes, la Navidad, la Semana Santa y los días con la punta anómala (más de tres desviaciones
  robustas por debajo de la mediana del mes: posible incidente u obra). En Ermita Cruz Chica hacia Santa Cruz quedan
  49 días excluidos y 44 marcas; en Bomberos La Laguna hacia el Norte, 49 y 48. Sin los días
  marcados, la media de horas de cola de los cuellos cambia como mucho 0,03 h y la descarga mediana 22,0 veh/h
  (`sensibilidad_sin_dias_atipicos.csv`). En los cambios de hora de marzo falta la marca de la 1 h y la de las 2 h sale
  duplicada (59 y 50 registros); son domingos y no afectan a los días laborables. El 27 de enero de 2026 el fichero
  oficial trae una sola hora. Entran en el análisis 5.759 días laborables válidos, sumando estaciones y sentidos.
  Incidentes, obras y lluvia no están vinculados a los días (apartado 7).
- **Cobertura** (`cobertura_y_calidad.csv`, `cobertura_por_hora.csv`). En el conjunto de los 24 meses, todas las
  estaciones superan el 95 % de horas completas salvo **Padre Anchieta**, la más cargada, con un 46,9 % de horas
  completas y solo un 11-12 % con velocidades utilizables (rangos negativos o ausentes). Hospital Residencia no
  tiene registros en septiembre de 2026. En La Matanza el 76 % (hacia el Norte) y el 81 % (hacia Santa Cruz) del
  tráfico va a menos de 80 km/h también de madrugada, así que el indicador de velocidad no detecta su cola.
- **Hora congestionada:** al menos el 60 % de los vehículos pasa a menos de 80 km/h, y 30 puntos más que de
  madrugada en la misma estación. Con umbrales de 50 % y +20 o de 70 % y +40, el diagnóstico de los dos cuellos
  principales apenas cambia. El segundo cuello de La Laguna hacia Santa Cruz sí depende del umbral: con el más
  estricto, su mediana pasa a 0 h (`sensibilidad_umbral_congestion.csv`).

### Dónde y cuándo hay cola (días laborables de 2025)

| Estación y sentido | Horas de cola al día (mediana; p25-p75) | Días sin cola | Empieza |
|---|---|---|---|
| Ermita Cruz Chica → Santa Cruz | 3 (2-3) | 10 de 226 | 6 h |
| Bomberos La Laguna → Santa Cruz | 1 (0-2) | 69 de 223 | 7 h |
| Campus Guajara → Santa Cruz | 1 (0-1) | 106 de 226 | 7 h |
| Bomberos La Laguna → Norte | 4 (3-6) | **0 de 224** | 13 h |
| Campus Guajara → Norte | 2 (1-3) | 39 de 226 | 14 h |
| Ermita Cruz Chica → Norte | 0 (0-0) | 173 de 227 | 17 h |

**Horario de la cola** (`horario_cola.csv`; primera hora congestionada y fin de la última, en la ventana de cada cuello: de 3 a 13 h por la mañana y de 11 a 24 h por la tarde; la tabla de arriba mira el día entero):

| Cuello | 2025 | 2026 (enero-septiembre, sin agosto) |
|---|---|---|
| Mañana hacia Santa Cruz (Ermita Cruz Chica) | de 06:00 a 09:00 (fin p10-p90: 08:00-10:36); 215 de 226 días | de 06:00 a 09:00 (08:00-10:00); 153 de 163 días |
| Tarde hacia el Norte (Bomberos La Laguna) | de 13:00 a 18:00 (17:00-21:00); 224 de 224 días | de 13:00 a 18:00 (17:00-21:00); 160 de 165 días |

**Caudal en las horas con cola** (observado; `caudal_descarga_cuellos.csv`). Por los 2 carriles de Los Rodeos
hacia Santa Cruz pasan 3.345 veh/h de mediana en las horas con cola de 3 a 13 h
(p10-p90: 2.854-3.632; 620 horas). Hacia el Norte, en las horas con
cola en Bomberos La Laguna de 11 a 24 h, pasan 3.561 (3.061-3.744;
1.025 horas).

Este caudal **no es la capacidad**: es lo que pasó en esas horas, y mezcla tres tipos de hora:
- la hora en que empieza la cola, con caudal alto: 3.580 veh/h a las 6 h;
- las horas centrales: 3.370 a las 7 h;
- las de disipación: 3.062 a las 8 h, y menos aún cuando también hay cola en La Laguna
  (apartado 2.5).

### ¿Ha cambiado algo ya? (asociaciones no causales y comparación entre años)

- **Horarios escalonados de la Universidad de La Laguna** (desde el 9-9-2025; 13 grados y unos 2.700
  estudiantes según la ULL). *Asociación no causal.* Se comparan los meses lectivos (octubre, noviembre y febrero a
  mayo) del curso 2025-26 con los del 2024-25, hacia Santa Cruz, de 7 a 9 h:
  - Campus Guajara: −67 veh/día (IC 95 %: −334 a 190);
  - Ermita Cruz Chica: −90 (−215 a 35);
  - la cola de Los Rodeos pasa de 2,9 a 3,1 h/día.

  **No se ve un cambio en los cuellos.** La bajada de octubre y noviembre de 2025 junto al campus (−475 veh/día) no
  se mantiene de febrero a mayo. Las diferencias en diferencias, con julio (o junio y julio) como control, no son
  válidas: esos meses de 2026 ya tienen la pasarela del Padre Anchieta, y no hay registros de obras ni de incidencias
  incorporados para controlarlas (`ull_diferencias_en_diferencias.csv`).
- **Después de abrir la pasarela del Padre Anchieta** (abierta el 18-5-2026; los 11 pasos de peatones de la
  glorieta se cerraron dos días después). *Asociación no causal.* La cola de la mañana en Bomberos La Laguna hacia
  Santa Cruz fue menor que en el mismo mes de 2025:
  - junio: 0,62 h/día (1,05 en 2025);
  - julio: 0,00 (1,00);
  - septiembre: 0,36 (0,95).

  En Los Rodeos no cambia. Son tres meses, dos de verano, sin un grupo de control y sin registros de obras ni de
  incidencias incorporados: es una coincidencia temporal que hay que confirmar, no un efecto demostrado
  (`diferencias_interanuales_por_mes.csv`, g16). Como comparación de control, en noviembre de 2025, antes de la
  pasarela, la cola ya bajó tanto: de 1,50 a 0,80 h/día (IC 95 % de la diferencia: −1,12 a −0,28).
  Bajadas así aparecen también sin pasarela.
- **2026 frente a 2025** (enero-septiembre, sin agosto; observado). En los dos cuellos principales, las horas de
  cola no cambian de forma significativa:
  - Ermita Cruz Chica hacia Santa Cruz: 2,65 → 2,84 h/día, p = 0,21;
  - Bomberos La Laguna hacia el Norte: 4,66 → 4,67, p = 0,94.

  En Campus Guajara hacia Santa Cruz, parte del segundo cuello de La Laguna, suben (0,57 → 0,80 h/día, p = 0,01).
  Se descartan las comparaciones en las que el reparto del tráfico entre carriles cambia más de 4 puntos (aforador
  alterado).

## 2. Qué estimamos

### 2.1 Carriles y capacidad de cada tramo (estimado)

Los carriles de cada estación y sentido salen de dos fuentes oficiales con fechas distintas:
- el catálogo de carriles de los aforos del Cabildo (julio de 2026);
- el inventario del Plan Territorial Especial de Ordenación del Sistema Viario del Área Metropolitana de Tenerife
  (PTEOSVAM, aprobado en 2006).

Coinciden en 8 de 14 estación-sentidos. Los otros 6 quedan **pendientes de confirmación**
(`datos/geometria_tramos.csv`, `geometria_y_capacidad.csv`): Campus Guajara en los dos sentidos (4 aforados frente
a 3 en el inventario), Padre Anchieta hacia Santa Cruz (3 frente a 2), Bomberos La Laguna hacia Santa Cruz (4
frente a 3) y La Orotava en los dos sentidos (3 frente a 2). El inventario advierte de que «en los enlaces ... se
suele disponer un carril adicional»: la diferencia puede ser un carril de enlace contado como carril, o una obra
posterior. Queda preparada una petición al Cabildo para confirmarlo (`docs/solicitud_datos_cabildo.md`,
punto 6), que no se ha enviado.

Cada capacidad del modelo está ligada a una configuración, un sentido, una fecha y una fuente
(`geometria_y_capacidad.csv`), y `uso_de_la_geometria.csv` recoge los 11 cálculos que dependen del número de
carriles, con su estado y el supuesto que los sustituye cuando no están confirmados: todos tienen fuente o supuesto explícito. La
capacidad por carril es la misma, 1.850-2.100 veh/h (moda 1.950), en el modelo de cola y en el «k crítico». Las
hipótesis geométricas alternativas se ejecutan como cambios de capacidad:
- **k crítico con los carriles del inventario** (`k_critico_geometria_alternativa.csv`). Por ejemplo, en Padre
  Anchieta hacia Santa Cruz, 6,7 % con 2 carriles
  frente a 10,0 % con 3. Con menos carriles, el tramo se satura con menos tráfico.
- **Capacidad libre del tramo siguiente con los carriles del inventario** en Campus Guajara y Bomberos La Laguna
  (apartado 2.2).
- **Tramo siguiente sin capacidad libre** (por ejemplo, si el paso por Padre Anchieta tuviera en la práctica 2
  carriles efectivos): ni el tercer carril ni la regulación de accesos reducirían la demora.

### 2.2 Capacidad libre del tramo siguiente y balance entre estaciones (estimado)

La **capacidad libre** (holgura) de una hora es `(C_abajo − F_abajo) / F_cuello`:
- `C_abajo` es la capacidad de la estación de abajo, que se estima como el percentil 99 de su caudal de 2025;
- `F_abajo` y `F_cuello` son los caudales de esa hora en la estación de abajo y en el cuello.

Las entradas y salidas de los ramales entre las dos estaciones se cancelan en la cuenta: no hace falta medirlas,
pero tampoco se pueden ver. Y como `C_abajo` sale de los caudales de la misma punta, la estimación es circular en
parte. Por eso se publica con rango y con variantes: nueve por la mañana y seis por la tarde.

| Hora | Mañana: La Laguna (Bomberos y Campus Guajara), mediana (p10 a p90) | Hora | Tarde: La Matanza (2 carriles) |
|---|---|---|---|
| 6 h | 13,3 % (8,4 % a 22,1 %); ningún día sin capacidad libre | 14 h | 10,0 % (3,5 % a 16,1 %); sin capacidad libre el 3 % de los días |
| 7 h | **0,6 % (−4,8 % a 9,8 %); sin capacidad libre el 44 % de los días** | 15 h | **2,8 % (−0,6 % a 9,8 %); sin capacidad libre el 14 % de los días** |
| 8 h | 13,9 % (8,3 % a 25,6 %); ningún día sin capacidad libre | 16 h | 3,9 % (0,3 % a 10,1 %); sin capacidad libre el 8 % de los días |

**Balance entre estaciones** (`balance_por_tramos.csv`; días con las 24 horas completas en las dos). Es descriptivo:
comprueba si las entradas netas por los ramales son estables, pero no entra en el modelo, que solo usa la capacidad
libre. En ningún tramo hay caudales negativos. Entre Ermita Cruz Chica y Bomberos La Laguna hacia Santa Cruz entran por los
ramales 14.125 veh/día netos (p10-p90:
12.648-15.763).
Es un balance estable de un día a otro (coeficiente de variación 0,11),
casi igual en 2025 (14.034) y en 2026 (14.172). En cambio,
solo 4 de los 13 pares de estaciones dan un balance estable (12 pares consecutivos y
Ermita Cruz Chica → Campus Guajara hacia Santa Cruz, que salta Bomberos La Laguna y Padre Anchieta); los que tocan
Padre Anchieta están entre los más inestables, porque su aforador falla buena parte del tiempo.

**Sensibilidad de la capacidad libre** (`sensibilidad_holgura_caso1.csv` y `sensibilidad_holgura_resultados_caso1.csv`;
300 combinaciones calibradas). La tabla da la capacidad libre a las 7 h, el tercer carril el primer año y qué parte
de las combinaciones da con esa variante una cola de hoy dentro del rango medido en 2025:

| Variante (mañana) | Capacidad libre a las 7 h (mediana) | Tercer carril, 1er año | Cola de hoy en el rango medido |
|---|---|---|---|
| Principal: capacidad de abajo = p99 de su caudal; entradas netas de los aforos | 0,6 % | 41 % (23-73 %) | 95 % |
| Capacidad de abajo más baja (p95 de su caudal) | −13,9 % | 10 % (2-31 %) | 6 % |
| Capacidad de abajo más alta (p99,9 de su caudal) | 6,1 % | 61 % (36-95 %) | 92 % |
| Capacidad de abajo solo con horas sin cola en esa estación (p99) | −4,8 % | 27 % (8-54 %) | 50 % |
| Ramales: entradas un 10 % mayores (demanda que hoy no consigue entrar) | −3,8 % | 31 % (10-60 %) | 55 % |
| Ramales desconocidos: salidas del 5 % del caudal después del punto crítico | −4,4 % | 24 % (5-51 %) | 53 % |
| Cuello desplazado: sin holgura en las horas con cola en la estación de abajo | 0,0 % | 35 % (18-66 %) | 94 % |
| Carriles del inventario de 2006 en Campus Guajara y Bomberos La Laguna (cota baja: 3/3 x 1.850 x 0,82) | −8,5 % | 12 % (1-40 %) | 17 % |
| Holgura nula en todas las horas | 0,0 % | 0 % (0-0 %) | 90 % |

Una capacidad libre negativa significa que esa hora el tramo de abajo pasó más que la capacidad supuesta.
Con la propagación de la cola en la especificación de la mañana (apartado 2.3), una variante con menos capacidad abajo alarga también la cola de hoy; si con ella menos de la mitad de las combinaciones da una cola de hoy dentro del rango medido, los aforos de 2025 no son compatibles con esa variante: es el caso de «capacidad de abajo más baja (p95 de su caudal)» y de «carriles del inventario de 2006 en Campus Guajara y Bomberos La Laguna (cota baja: 3/3 x 1.850 x 0,82)». Es el supuesto que más pesa en el resultado del
tercer carril y de la regulación de accesos de la mañana. Con el tercer carril, la cola que queda la marca el tramo
siguiente: es un cuello que se desplaza, no una cola que desaparece (apartado 2.3, cuellos en serie). Hacia el Norte,
la especificación no tiene propagación de la cola, así que la cola de hoy no depende de la capacidad libre y las colas medidas no descartan ninguna variante: el tercer carril hipotético va de nada, con holgura nula, al 82 %, y del 39 % al 82 % si queda alguna capacidad libre (`sensibilidad_holgura_resultados_caso2.csv`). La
Matanza no tiene velocidad utilizable, así que allí no se puede probar la variante de cuello desplazado.

### 2.3 El modelo (simulado)

**Qué hace.** Simula minuto a minuto un día laborable completo en cada cuello:

- **Demanda híbrida.** Fuera de la ventana de la punta (6-10 h por la mañana, 13-18 h por la tarde), la
  demanda es el caudal aforado hora a hora. Dentro, donde el caudal medido está topado por la capacidad, se
  reparten los mismos vehículos con una forma de punta cuya hora y anchura se calibran. Conserva exactamente los
  vehículos del día (48.857 hacia Santa Cruz y 48.151 hacia el Norte).
- **Cola puntual** (Vickrey, 1969) con **caída de capacidad** cuando hay cola (Cassidy y Bertini, 1999), y
  esperas por cohortes con curvas acumuladas (Newell, 1993).
- **Especificación de la descarga, elegida por validación cruzada** (apartado 2.5). Se probaron 16 variantes:
  propagación de la cola del tramo siguiente (si no tiene capacidad libre, frena también la descarga actual),
  descarga que depende de la hora (medida en 2025 y aplicada solo en las horas con datos suficientes), mezcla de
  pesados y descarga calibrada como parámetro o medida igual que en el aforo. Elegidas: por la mañana,
  **propagación de la cola del tramo siguiente + descarga dependiente de la hora + mezcla de pesados; descarga calibrada medida igual que en el aforo**; por la tarde, **descarga constante; descarga calibrada como parámetro**. La mezcla de pesados entra por un empate: sin ella, el RMSE relativo medio es casi el mismo (0,9279 frente a 0,9277) y el sesgo absoluto de la descarga es menor (81 frente a 93 veh/h); la regla, fijada de antemano, se queda con la de menor RMSE.
- **Restricción aguas abajo.** El tercer carril y la regulación de accesos no pueden pasar más de lo que admite el
  tramo siguiente hora a hora (`D = descarga × (1 + capacidad libre)`); si el tramo siguiente no tiene capacidad
  libre, no añaden nada. Además, un modelo de **dos cuellos en serie** (`simular_tandem()`) comprueba qué pasa con
  un almacenamiento finito entre los dos (1, 2 o 4 km supuestos), la cola remanente y el bloqueo de las entradas de
  los ramales (apartado 2.7).
- **Alternativas:**
  - tercer carril, limitado hora a hora por la capacidad libre estimada del tramo siguiente;
  - regulación de accesos, que evita la caída de capacidad, con el mismo límite;
  - escalonamiento horario;
  - tarificación de la punta;
  - regulación + escalonamiento.

  Por la tarde, el tercer carril es hipotético.
- **Demanda inducida** a 1, 5 y 10 años, igual para todas las alternativas que reducen la demora. Usa las
  elasticidades de Goodwin y SACTRA, más bajas según Cervero, y el reparto en el tiempo de Hymel, Small y Van
  Dender. La tarificación no la lleva, porque las reducciones observadas con peaje ya son netas.

### 2.4 Monte Carlo y calibración

- **Distribuciones** (`montecarlo_parametros.csv`). Cada parámetro tiene una distribución triangular (mínimo,
  moda, máximo) con su tipo y su fuente. Son independientes entre sí, con dos excepciones:
  - la elasticidad a 10 años nunca es menor que la del primer año;
  - la capacidad libre del tramo siguiente no es triangular: se muestrea un cuantil común a todas las horas (un día
    bueno o malo aguas abajo) de su distribución estimada hora a hora.
- **Semillas** (`montecarlo_semillas.csv`): una por cada paso aleatorio, y todas fijas.
- **Calibración por rechazo** (`montecarlo_filtros.csv`). Se simulan 20.000 combinaciones por la mañana y
  10.000 por la tarde, y solo se quedan las que reproducen lo medido en 2025: la duración de la cola (contada
  como en el aforo), la hora de inicio y de fin, el caudal de descarga y una cola que se disuelve dentro del día. Se
  aceptan 378 por la mañana (1,9 %) y 1.369 por la tarde (13,7 %). La regla que más
  descarta por la mañana es «inicio de la cola»: solo la cumple el 10,8 % de las combinaciones.
- **Auditoría del Monte Carlo** (`docs/VALIDACION_Y_CALIDAD.md`, criterio 3):
  - con otras dos semillas, las medianas del tercer carril y de la regulación + escalonamiento cambian como mucho
    2,8 puntos (`montecarlo_otras_semillas.csv`);
  - con previas alternativas (uniformes en el mismo rango, o con la moda en un extremo para la demanda inducida, la
    eficacia de la regulación, la caída de capacidad y, donde la forma de la descarga los usa, los pesados),
    reponderando las combinaciones aceptadas, esas medianas cambian como mucho 5,1 puntos con las previas cuyo
    tamaño efectivo es al menos el 10 % de las aceptadas, y hasta 14,1 con las demás, que por su tamaño efectivo pequeño dan un resultado poco preciso
    (`montecarlo_previas_alternativas.csv`);
  - las correlaciones que crea la calibración entre parámetros (`montecarlo_correlaciones.csv`);
  - el error típico de la mediana por el muestreo va de 0,1 a 2,0 puntos (`estabilidad_percentiles.csv`).
- **Con y sin filtro** (`sensibilidad_calibracion_caso1.csv`). Sin calibrar (2.249 combinaciones al azar que dan
  cola), el tercer carril de la mañana rendiría 67 % (36-94 %) el primer año, frente a
  40 % (22-73 %) con la calibración. Con las 6 reglas alternativas de calibración va del 51 % al
  68 %. Los resultados describen la población calibrada, no cualquier combinación verosímil. La regla «descarga: horas de cola plena de 2025 (p25-p75)» solo la cumple 1 de 20.000 combinaciones y no se puede usar: con la especificación elegida, el modelo no reproduce a la vez la duración y el horario de la cola y el caudal de las horas de cola plena (apartado 2.5).

Lo que más estrecha la calibración es la hora y la anchura de la punta (`parametros_prior_posterior.csv`). Las
elasticidades y la eficacia de cada medida no las informan los aforos: vienen de la literatura.

### 2.5 Validación: calibración, validación cruzada en 2025 y prueba final en 2026

**Tres conjuntos de días.** 2025 calibra. Para elegir la especificación de la descarga, los días de 2025 se
reparten en dos mitades por semanas alternas: se calibra con una y se mide el error en la otra, y al revés
(validación cruzada; cada calibración usa solo sus días para todo lo que se ajusta). Enero-septiembre de 2026 (sin
agosto) no interviene en la calibración ni en la elección de la especificación: es la prueba final. La excepción es la línea
base de velocidad de madrugada, con la que se decide si una hora está congestionada, que se calcula con los 24 meses;
calculada solo con 2025, no cambia ninguna hora congestionada de 2025 en las estaciones que usa el modelo (cambian 15 de 5.424 horas en Campus Guajara hacia el Norte, que no interviene en él). Detalle en `docs/comprobacion_base_nocturna_2025.csv`.

**Elección de la descarga** (`eleccion_especificacion.csv`, `validacion_cruzada.csv`, g20). Una variante solo se
adopta si reduce al menos un 20 % el sesgo absoluto de la descarga del día fuera de muestra y no empeora más de un
10 % el error (RMSE) de ningún otro indicador; la regla se fijó antes de mirar 2026. Por la mañana hay 6
variantes admisibles; la elegida reduce el sesgo absoluto de la descarga del día en la validación cruzada de 149 a 93 veh/h. Por la tarde, 0: se mantiene la referencia.
En la prueba final de 2026, la descarga del día de la mañana pasa de un sesgo de
+137 veh/h con la referencia a +88 con la elegida, y el RMSE, de 217 a
190. La cobertura del intervalo predictivo del 80 % de esa descarga se acerca más al 80 % en la validación cruzada (83 % y 85 % en las dos mitades con la elegida, frente a 78 % y 90 % con la referencia); en 2026 es del 88 %, frente al 86 % con la referencia (algo más lejos del 80 %). Con la elegida, la banda de parámetros cubre menos días en 2026 (29 % frente a 55 %): no es un fallo, porque la banda describe un día típico y no la variabilidad entre días. Estas cifras de la elección salen de la rejilla de
especificaciones (10.000 combinaciones por forma; 168 aceptadas con la elegida calibrada con todo 2025); las de
la tabla siguiente, del Monte Carlo principal (20.000 combinaciones; 378 aceptadas), así que difieren un
poco (+88 frente a +84 veh/h de sesgo).

**Día a día en 2026** (`validacion_diaria.csv`; sesgo = mediana del modelo − media aforada; el intervalo predictivo del 80 % es el que
debe cubrir unos 8 de cada 10 días):

| Indicador | Sentido | 2025 (calibración): sesgo; RMSE | 2026 (prueba): sesgo; MAE; RMSE | 2026: dentro del intervalo predictivo |
|---|---|---|---|---|
| Horas de cola al día | Mañana | +0,26; 1,14 | +0,36; 0,93; 1,31 | 79 % |
| Inicio de la cola | Mañana | −0,05; 0,28 | −0,10; 0,10; 0,65 | 96 % |
| Fin de la cola | Mañana | −0,04; 1,13 | +0,05; 0,81; 1,17 | 90 % |
| Descarga del día medida igual en el modelo y en el aforo | Mañana | +95; 232 | +84; 142; 188 | 88 % |
| Descarga en las horas de cola plena | Mañana | +215; 371 | +260; 266; 363 | 82 % |
| Horas de cola al día | Tarde | −0,63; 1,70 | −0,58; 1,30; 1,88 | 90 % |
| Inicio de la cola | Tarde | +0,57; 0,84 | +0,73; 0,73; 0,93 | 94 % |
| Fin de la cola | Tarde | −0,34; 1,57 | −0,34; 1,38; 1,68 | 99 % |
| Descarga del día medida igual en el modelo y en el aforo | Tarde | −26; 196 | +87; 162; 233 | 80 % |
| Descarga en las horas de cola plena | Tarde | −78; 224 | +38; 197; 268 | 64 % |

En 2026 el intervalo predictivo cubre, según el indicador diario, entre el 64 % y el 99 % de los días; por debajo del 80 % quedan horas de cola al día (mañana, 79 %); descarga del día frente al parámetro del modelo (mañana, 76 %); descarga en las horas de cola plena (tarde, 64 %). Hora a hora, cubre el 75 % de las horas por la mañana y el 71 % por la tarde. Las métricas por hora de la punta, por día de la semana y por trimestre están en `validacion_diaria.csv` y
`validacion_diaria_por_hora.csv`, y el detalle, en `docs/VALIDACION_Y_CALIDAD.md` (criterio 1).

**Tabla resumida** (`validacion_modelo.csv`). Tiene **10 filas, 5 por sentido**: horas de cola, inicio, fin y
dos filas de la descarga. Esas dos miden el mismo fenómeno de dos formas (el parámetro de descarga y el caudal medido
igual que en el aforo) y no son dos contrastes independientes. En 2026
queda fuera de la banda de parámetros una sola fila (mañana, parámetro de descarga); la otra fila del mismo fenómeno queda dentro. La banda de parámetros es de un
día típico; para días concretos vale el intervalo predictivo. El error de esta tabla es la mediana del modelo menos la
mediana aforada; el sesgo de la tabla anterior se mide frente a la media de los días, así que pueden no coincidir.

| Indicador | Mañana: aforo 2025 / 2026 | Modelo, mediana (banda p10-p90) | Error 2026 | Tarde: aforo 2025 / 2026 | Modelo | Error 2026 |
|---|---|---|---|---|---|---|
| Horas de cola al día | 3 / 3 | 3 (3-3) | 0 h | 4 / 4 | 4 (3-5) | 0 h |
| Inicio | 6 h / 6 h | 6 h (6-6) | 0 h | 13 h / 13 h | 14 h (13-14) | +1 h |
| Fin | 9 h / 9 h | 9 h (9-9) | 0 h | 18 h / 18 h | 18 h (17-19) | 0 h |
| Descarga medida igual que el aforo (veh/h) | 3.371 / 3.371,5 | 3.419 (3.317-3.457) | +48 (+1,4 %) | 3.587 / 3.449 | 3.510 (3.402-3.621) | +61 (+1,8 %) |
| Parámetro de descarga (veh/h; no se mide igual que el aforo) | 3.345 / 3.338,5 | 3.497 (3.439-3.613) | +158 | 3.561 / 3.423,5 | 3.510 (3.402-3.621) | +86 |

**La descarga de la mañana** (`diagnostico_descarga.csv`). En el aforo, el caudal con cola cae a lo largo de la
mañana: 3.580, 3.370 y 3.062 veh/h a las 6, 7 y 8 h en 2025 (3.515, 3.427 y 3.110 en el modelo calibrado). A
las 8 h pasan 2.956 veh/h cuando hay cola en La Laguna y
3.133 cuando no la hay. Por eso se probaron la descarga dependiente de la hora, la propagación de la cola y la
mezcla de pesados, y se mide la descarga del modelo igual que la del aforo. El parámetro de descarga es la descarga
a pleno rendimiento en la hora de referencia, antes del factor horario y de los pesados: no se mide como el aforo, y su diferencia con la mediana de todas
las horas con cola no es un error de predicción. No se ha ensanchado ninguna banda. Por posición en la cola, el modelo
reproduce el caudal al empezar la cola (3.515 frente a 3.580 veh/h en 2025), sobrestima el de la cola plena
(3.427 frente a 3.243) y subestima el del final (3.110 frente a 3.218): cuadra la mediana del día, que es lo
que se calibra, no la forma de la descarga dentro de la cola. En las horas de cola plena el sesgo es de
+215 veh/h en 2025 y de +260 en 2026.

**La tarde en 2026.** El caudal con cola de la tarde bajó de 3.561 veh/h en 2025 a 3.424 en 2026
(IC 95 % por días: 3.398-3.453, que no incluye el valor de 2025), y el sesgo diario
de la descarga pasa de −26 veh/h en 2025 a +87 en 2026. Es un cambio observado entre los dos
años cuya causa no se ha identificado.

### 2.6 Demoras: qué se mide y en qué unidades (simulado)

Ninguna demora del proyecto es observada: no hay tiempos de recorrido publicados. Valores de la situación actual
simulada (`indicadores_demora.csv`, con el método de cada uno; mediana y banda p10-p90):

| Indicador | Unidad y denominador | Horizonte | Mañana | Tarde |
|---|---|---|---|---|
| Demora total | vehículos·hora (suma de todos los vehículos del día) | día laborable de 24 h | 1.541 (897-2.395) | 1.931 (953-3.284) |
| Espera media en la hora punta | minutos por vehículo (vehículos que llegan en los 60 minutos de más llegadas) | hora punta | 7,2 (3,3-12,6) | 6,0 (2,9-9,4) |
| Espera máxima | minutos (el vehículo que más espera) | día laborable | 15,8 (8,8-25,3) | 14,1 (8,4-20,5) |
| Duración de la cola | horas por día (minutos con cola / 60) | día laborable | 3,1 (2,7-3,4) | 4,0 (2,9-5,4) |
| Horas de cola como las cuenta el aforo | horas enteras por día | día laborable | 3 (3-3) | 4 (3-5) |
| Cola máxima | vehículos | día laborable | 899 (496-1.460) | 827 (503-1.186) |
| Longitud equivalente de la cola máxima | km (140 veh/km por carril, en los carriles del tramo donde se forma la cola: 2 por la mañana y 3 por la tarde; solo orientativa) | día laborable | 3,2 (1,8-5,2) | 2,0 (1,2-2,8) |

**Contraste indirecto.** Las horas de cola se contrastan día a día con los aforos (apartado 2.5). La espera máxima
solo se puede comparar con una franja de 10-40 min tomada de la prensa (Atlántico Hoy, 24-11-2025, estima 20 min por la
mañana y 15 por la tarde; COPE, 20-10-2021, documenta 40 min entre El Sauzal y Guamasa en un día con accidente): por la mañana
cae en esa franja el 86 % de las combinaciones calibradas, y por la tarde el
81 %. Es un contraste débil: estimaciones periodísticas, sin fecha ni tramo exactos. La longitud de la cola no se
puede contrastar: la cola puntual no ocupa espacio en el modelo.

### 2.7 Cada alternativa: tramo, horario, horizonte, supuesto clave, rango, diferencias, coste y limitación

`fichas_alternativas.csv` tiene una ficha por alternativa y cuello. El indicador es la reducción de los
vehículos·hora de demora del día laborable frente a no actuar (simulado). Los horizontes son el primer año, a 5 y a
10 años de ponerla en marcha (con demanda inducida), 2030 con crecimiento bajo, central y alto, y los escenarios
adversos (rango de las medianas de los cuatro supuestos desfavorables de cada cuello, sin la referencia ni la cota
favorable sin demanda inducida).

**Mañana hacia Santa Cruz** (Los Rodeos-Guamasa, 6 a 9 h):

| Alternativa | 1er año | A 10 años | 2030 (crecimiento 0-1 %) | Escenarios adversos | Confianza |
|---|---|---|---|---|---|
| Tercer carril | 40 % (22-73 %) | 33 % (18-60 %) | 40-44 % | 0-64 % | media |
| Regulación de accesos + escalonamiento | 48 % (32-73 %) | 39 % (24-59 %) | 46-48 % | 17-42 % | baja |
| Regulación de accesos | 34 % (20-55 %) | 28 % (15-46 %) | 34-39 % | 0-30 % | baja |
| Escalonamiento horario | 17 % (10-31 %) | 12 % (7-22 %) | 12-17 % | 8-17 % | media |
| Tarificación de la punta (no la permite la ley) | 61 % (38-99 %) | no aplica (efecto ya neto) | 58-61 % | 39-61 % | baja |

**Tarde hacia el Norte** (Bomberos La Laguna-Los Rodeos, 13 a 18 h):

| Alternativa | 1er año | A 10 años | 2030 (crecimiento 0-1 %) | Escenarios adversos | Confianza |
|---|---|---|---|---|---|
| Tercer carril hipotético (no proyectado) | 72 % (34-99 %) | 64 % (30-96 %) | 71-72 % | 0-79 % | media |
| Regulación de accesos + escalonamiento | 62 % (38-81 %) | 55 % (33-73 %) | 59-62 % | 10-58 % | baja |
| Regulación de accesos | 55 % (30-74 %) | 49 % (26-67 %) | 55-56 % | 0-51 % | baja |
| Escalonamiento horario | 10 % (6-19 %) | 8 % (4-14 %) | 5-10 % | 4-10 % | media |
| Tarificación de la punta (no la permite la ley) | 47 % (29-100 %) | no aplica (efecto ya neto) | 34-47 % | 24-47 % | baja |

**Diferencias entre alternativas, combinación a combinación** (`diferencias_emparejadas.csv`, g21). Como cada
combinación calibrada se usa para todas las alternativas, la diferencia entre dos se mide en cada combinación. Una
diferencia de menos de 2 puntos (umbral fijado de antemano) no es material. Primer año:

| Pareja | Mañana: diferencia mediana (p10 a p90); lectura | Tarde: ídem |
|---|---|---|
| Tercer carril − regulación de accesos + escalonamiento | −8,0 (−18,6 a +11,0); depende de los parámetros | +6,1 (−7,9 a +28,3); depende de los parámetros |
| Tercer carril − regulación de accesos | +5,0 (0,0 a +25,6); depende de los parámetros | +12,6 (0,0 a +34,4); depende de los parámetros |
| Regulación de accesos − regulación de accesos + escalonamiento | −13,9 (−21,2 a −8,5); la regulación + escalonamiento reduce más en al menos el 90 % de las combinaciones | −6,5 (−11,0 a −3,6); la regulación + escalonamiento reduce más en al menos el 90 % de las combinaciones |
| Escalonamiento horario − regulación de accesos + escalonamiento | −29,6 (−44,0 a −17,2); la regulación + escalonamiento reduce más en al menos el 90 % de las combinaciones | −50,3 (−66,6 a −24,5); la regulación + escalonamiento reduce más en al menos el 90 % de las combinaciones |

**Coste, plazo y riesgos, aparte del efecto simulado** (`coste_plazo_riesgo.csv`; dato documental y valoración
cualitativa):

| Alternativa | Coste | Plazo | Riesgos principales |
|---|---|---|---|
| Tercer carril Guamasa-Aeropuerto Norte (hacia Santa Cruz) | 58,2 M€ con IGIC (contrato formalizado) | 35 meses de ejecución según licitación («casi tres años», según el Cabildo); inicio de las obras anunciado para noviembre de 2026, con el acta de replanteo prevista para la semana del 26-10-2026 (Cabildo de Tenerife, 20-10-2026); cómputo sujeto al acta y a los pliegos | Retraso de obra (la pasarela del Padre Anchieta abrió con tres años de retraso); molestias durante casi tres años de obra 24 h (el Cabildo anuncia que se mantienen los dos carriles actuales y las vías TF-252 y TF-235; demolición del puente de Los Rodeos); el beneficio depende de la capacidad libre del tramo siguiente (La Laguna); demanda inducida |
| Tercer carril hacia el Norte en Los Rodeos-Guamasa (hipotético) | Sin presupuesto: no proyectado (el tercer carril Guamasa-La Orotava, ~300 M€, empieza en Guamasa) | Sin proyecto ni fecha | Exigiría un proyecto nuevo; La Matanza (2 carriles) limitaría el beneficio mientras no se amplíe |
| Regulación de accesos (semáforos en los ramales) | 1,8-4 M€ (Padre Anchieta + 4 enlaces, según el Cabildo) | Anunciada en mayo de 2025 para octubre-noviembre de 2025; pruebas de la DGT del 12 al 14-01-2026; sin implantar | Colas en los ramales y en las vías que llegan a ellos; eficacia sin piloto en Tenerife; depende de que la caída de capacidad sea la supuesta; necesita coordinación del Cabildo y la DGT |
| Escalonamiento de horarios (ULL, Administración, colegios) | Sin coste de obra (reorganización de horarios) | En marcha en la ULL desde el curso 2025-26 (13 grados); ampliación anunciada para 2026-27 (unos 4.700 estudiantes) | Depende de instituciones y de la conducta de las personas; efecto pequeño y sin cambio visible en los cuellos (asociación no causal) |
| Tarificación de la punta | ~10 M€ (PIMSIT, horizonte 2032-2033) y cambio legal | Exige cambiar la ley canaria; descartada por la presidencia del Cabildo el 07-10-2026 | Aceptación social y política; marco legal; sin alternativa viaria; equidad entre usuarios |
| Regulación de accesos + escalonamiento | 1,8-4 M€ (regulación) + reorganización de horarios | Componentes en pruebas (regulación) o en marcha (escalonamiento) | Los de la regulación de accesos y los del escalonamiento a la vez |

**Supuesto clave y limitación principal de cada una:**

- **Tercer carril.** Que el tramo siguiente (La Laguna) admita más caudal en la punta: holgura estimada hora a hora con los aforos de 2025; demanda inducida con elasticidades de la literatura. *Limitación:* La holgura es una estimación indirecta (sin aforos de ramales; la capacidad de abajo sale de los caudales de la misma punta): con holgura nula el tercer carril no reduce nada.
- **Regulación de accesos + escalonamiento.** Los supuestos de la regulación de accesos y del escalonamiento a la vez. *Limitación:* Hereda las incertidumbres de las dos medidas; sin piloto en Tenerife.
- **Regulación de accesos.** La regulación evita una parte (50-100 %) de la caída de capacidad y el tramo siguiente admite ese caudal. *Limitación:* La caída de capacidad no se puede medir con datos horarios y la eficacia viene de Minneapolis y Melbourne: con caída pequeña o con el tramo siguiente lleno rinde poco.
- **Escalonamiento horario.** Un 3-15 % de la joroba de la punta se desplaza 30-90 min (ancla local: unos 500 vehículos al día de la ULL, según el Cabildo). *Limitación:* Los aforos no muestran una reducción significativa con los horarios de la ULL; depende de acuerdos con centros de estudio y empresas.
- **Tarificación de la punta (no la permite la ley).** La demanda de la punta baja un 5-22 % (efecto neto observado en Estocolmo, Londres, Gotemburgo y Nueva York). *Limitación:* Sin experiencia local ni alternativa viaria; exige cambiar la ley y la presidencia del Cabildo la descartó.
- **Tercer carril hacia el Norte (hipotético).** Que La Matanza (2 carriles) admita más caudal: holgura estimada con los aforos de 2025. *Limitación:* Obra no proyectada; La Matanza no tiene velocidad utilizable, así que no se puede ver si su tramo se satura.

Una reducción del 100 % es una simulación en la que la alternativa elimina la cola
(`diagnostico_reducciones_extremas.csv`): pasa en el 2 % de las del
tercer carril de la mañana. Otras medidas de la demora de cada alternativa (espera media en la punta, espera
máxima, horas y cola máxima), con su p10-p90, están en `metricas_por_alternativa.csv`.

**Qué decide el resultado.** El tercer carril de la mañana, a 10 años, depende sobre todo de
`holgura_aguas_abajo` (rho de Spearman +0,74) y de `sigma_punta` (rho de Spearman +0,45). Con capacidad libre nula no reduciría
nada; con un 15 %, 69 % (50-95 %) el primer año (g15; la curva fija la capacidad libre en todas las horas y no aplica la propagación de la cola de la
especificación de la mañana, así que orienta sobre cuánto pesa la holgura, no sustituye al resultado principal). Hacia el Norte, el tercer carril hipotético entre
Los Rodeos y Guamasa lo limita La Matanza. Si continuara hasta La Orotava (en el modelo, capacidad libre del 50 % en
el tramo siguiente), la reducción sería del 100 % en la mediana (g15b). Es un escenario hipotético,
no una obra proyectada.

**Cuellos en serie y cola remanente** (`cola_remanente_aguas_abajo.csv`; comprobación simulada con longitudes
supuestas). Si entre Los Rodeos y La Laguna caben los vehículos de 1, 2 o 4 km de tres carriles, el tercer carril de
la mañana reduciría la demora total un 32 % en todos los casos el primer año (el modelo principal, con las mismas 200 combinaciones calibradas:
39 %). Parte de la cola que quita en Los Rodeos queda entre los dos cuellos (hasta 634
vehículos con 2 km) y retiene también a los que entran por los ramales; sin almacenamiento, los ramales quedan
bloqueados 143 minutos al día.

**Bus-VAO convirtiendo un carril** en Padre Anchieta hacia el Norte (3 carriles → 2 + 1 reservado; g11; simulado).
Padre Anchieta no tiene velocidades fiables, así que se usa un perfil sintético calibrado con una espera de 10-40 min,
franja supuesta a partir de la prensa (15-20 min según Atlántico Hoy, 24-11-2025; 40 min en un día con incidente según
COPE, 20-10-2021), no una observación. Para que el tráfico general no vaya
peor tiene que pasar al carril reservado el 33 % de los vehículos, un carril de tres. Para que su espera
baje a la mitad, el 38 % (36-40 %). Nadie ha publicado cuántos coches llevan 2 o más
ocupantes.

**Pasarse a la guagua o al tranvía** (`transporte_publico_trasvase.csv`; simulado). Basta con poco, porque la cola
responde a los últimos vehículos. Si un 10 % de la punta de la mañana (389
coches al día) deja el coche, la demora bajaría:
- 48 % (36-95 %) sin rebote;
- 39 % (29-69 %) el primer año;
- 32 % (24-54 %) a 10 años, con la demanda inducida.

Hace falta una oferta y una conducta que lo permitan.

**Confianza de cada alternativa** (`confianza_alternativas.csv`). Es la media de cuatro criterios: la evidencia
local, si la cola puntual representa bien el mecanismo, si depende de que los conductores cambien de hábitos y la
robustez en los escenarios adversos.

| Alternativa | Dónde y cuándo | Confianza | Por qué |
|---|---|---|---|
| Tercer carril Guamasa-Aeropuerto Norte | Los Rodeos-Guamasa hacia Santa Cruz, 6-9 h | Media | Añadir capacidad en un cuello es lo que mejor representa una cola puntual. Pero la capacidad libre de La Laguna es una estimación indirecta (nula el 44 % de los días a las 7 h), y la demanda inducida viene de la literatura |
| Tercer carril hacia el Norte (hipotético) | Los Rodeos-Guamasa hacia el Norte, 13-18 h | Media | Igual, limitado por la capacidad libre de La Matanza; no está proyectado |
| Regulación de accesos | Accesos situados antes de cada cuello, en las dos puntas | Baja | Sin piloto en Tenerife: el efecto se toma de Minneapolis y Melbourne. La caída de capacidad que evita no se puede medir con aforos horarios |
| Escalonamiento horario | Todo el corredor, en las dos puntas | Media | Hay una experiencia local (ULL), sin un cambio visible en los cuellos (asociación no causal). Depende de que instituciones y personas cambien de horario |
| Tarificación de la punta | Todo el corredor, en las dos puntas | Baja | Evidencia internacional sólida, pero sin experiencia local, en ciudades con alternativas y con un cambio de ley pendiente |
| Regulación + escalonamiento | Accesos y corredor, en las dos puntas | Baja | Suma dos medidas con poca evidencia local y hereda la incertidumbre de la regulación |

## 3. Qué prevemos: escenarios condicionados (simulado)

Ninguna previsión está verificada: son escenarios condicionados a sus supuestos. Cada previsión separa cuatro
componentes (`previsiones_condicionadas.csv`, con p10-p90 y la condición de validez de cada fila):
1. el **crecimiento exógeno** de la demanda: 0 %, 0,5 % y 1 % anual, justificados en `datos/escenarios_demanda.csv`;
2. los **cambios de red**: el tercer carril en servicio hacia 2029-2030. No se combinan proyectos sin fecha, como
   Guamasa-La Orotava o la circunvalación;
3. el **transporte público**: el trasvase de una parte de la punta;
4. la **demanda inducida** por cada mejora a 1, 5 y 10 años.

**Si no se hace nada** (`evolucion_sin_actuar.csv`, g18). Horas de cola por día laborable: media de las
simulaciones calibradas, con el p10-p90 si toda la demanda nueva intenta pasar en la punta. Entre corchetes, la
media si parte de la demanda se adapta:

| Crecimiento anual de la demanda | Mañana 2030 | Mañana 2035 | Tarde 2030 | Tarde 2035 |
|---|---|---|---|---|
| 0 % | 3,0 (3-3) | 3,0 (3-3) | 4,0 (3-5) | 4,0 (3-5) |
| 0,5 % (tráfico de las estaciones con margen, 2019-2025) | 4,1 (3-5) [3,8] | 5,5 (4-6) [5,0] | 5,2 (4-7) [5,0] | 6,5 (5-8) [6,1] |
| 1 % (población, 2021-2025) | 5,5 (4-6) [5,0] | 11,6 (8-13) [10,6] | 6,4 (5-8) [6,1] | 8,2 (7-9) [7,9] |

Hoy el modelo da 3,0 h por la mañana y
4,0 por la tarde. Los aforos dan, en los días válidos de 2025 y dentro de la ventana de cada cuello,
2,7 y 4,6 h de
media, así que por la tarde el modelo se queda algo corto (apartado 2.5). Con un 1 % anual, en 2035 la cola de la mañana
acabaría hacia las 19 h (mediana), y al menos la mitad de las simulaciones da 13 horas de cola o más. Es una extrapolación a un régimen que no se ha observado.

**Supuesto que pesa en estas cifras.** Por la mañana, la descarga dependiente de la hora solo se aplica en las horas con datos de 2025; después se supone la descarga de referencia. Si la descarga reducida de la última hora con datos se mantuviera el resto del día, con un 0,5 % anual la cola de la mañana en 2035 pasaría de 5,5 a 10,9 h (`sensibilidad_prevision_descarga.csv`). Los aforos no pueden decidir entre los dos supuestos, porque en 2025 la cola casi nunca llega a esas horas.

**Alternativas en 2030 según el crecimiento** (`alternativas_2030_por_crecimiento.csv`). Primer año completo del
tercer carril según el plazo del contrato, con la capacidad libre del tramo siguiente recalculada con la demanda de
ese año:

| Alternativa | Crecimiento 0 % | 0,5 % | 1 % |
|---|---|---|---|
| Tercer carril, mañana | 40 % (22-73 %) | 40 % (22-68 %) | 44 % (21-69 %) |
| Regulación + escalonamiento, mañana | 48 % (32-73 %) | 46 % (32-64 %) | 48 % (31-64 %) |
| Regulación + escalonamiento, tarde | 62 % (38-81 %) | 60 % (39-75 %) | 59 % (40-74 %) |
| Tercer carril hipotético, tarde | 72 % (34-99 %) | 71 % (37-96 %) | 71 % (42-94 %) |

**Retraso de la obra** (`retraso_obra_tercer_carril.csv`). Si el tercer carril entra en servicio en 2029, 2030, 2031 o
2032, con un crecimiento del 0,5 % anual, el primer año reduciría la demora de la mañana
un 39 %, 40 %, 40 % y 41 %, respectivamente (mediana), sobre una situación sin actuar que empeora cada año: sin actuar, la cola de la mañana pasaría de 3,9 h en 2029 a 4,7 h en 2032.

**Escenarios adversos** (`escenarios_adversos.csv`; mediana del primer año y, entre paréntesis, p10-p90). ¿Cambia el orden si las cosas van
peor?

- **Tramo siguiente lleno** (Padre Anchieta con 2 carriles efectivos por la mañana; La Matanza llena por la
  tarde). El tercer carril y la regulación de accesos no reducirían nada en ninguno de los dos cuellos (0 % de mediana, de p10 y de p90). Quedarían la tarificación, 59 % (38-87 %) por la mañana y 47 % (29-100 %) por la tarde,
  y el escalonamiento, 17 % (10-27 %) y 10 % (6-19 %).
- **Demanda inducida alta** (elasticidades −0,5 el primer año y −1,0 a 10 años). Todo bajaría unos puntos salvo la
  tarificación, cuyo efecto ya es neto: tercer carril 36 % (20-66 %) y
  68 % (31-97 %); regulación + escalonamiento 42 % (28-63 %) y
  58 % (35-76 %).
- **Caída de capacidad pequeña** (4 %, con la misma descarga medida). La regulación de accesos bajaría al
  17 % (10-27 %) por la mañana y al 31 % (21-42 %)
  por la tarde. El tercer carril: 41 % (23-75 %) y 74 % (39-99 %).
- **Un carril cortado 30 minutos** en lo más alto de la punta: tercer carril 64 % (53-77 %) por la mañana y
  79 % (66-90 %) por la tarde; regulación + escalonamiento 34 % (25-45 %) y 39 % (25-52 %).
- **Sin demanda inducida** (cota favorable). Todas las alternativas rendirían más salvo la tarificación: el tercer
  carril, 51 % (29-87 %) y 79 % (39-100 %); la regulación + escalonamiento,
  60 % (42-86 %) y 69 % (43-90 %).

En cada supuesto, las alternativas a menos de 2 puntos de la mejor se consideran empatadas
(`escenarios_adversos.csv`, columna `empate_con_la_primera`).

**Condiciones de validez.** Las previsiones suponen:
- la misma red de 2025 salvo el tercer carril contratado;
- el mismo reparto horario de la demanda;
- la eficacia y las elasticidades de la literatura;
- un tramo siguiente que se comporta como en 2025.

No incluyen obras, incidencias ni cambios de transporte público que no estén en el escenario. Fuera de estas
condiciones, sobre todo con crecimientos del 1 % hasta 2035, el modelo trabaja en un régimen que no se ha
observado.

## 4. Contexto: proyectos y transporte público

`datos/proyectos.csv` recoge cada actuación con su promotor, coste, situación a 20 de octubre de 2026 y
fuente. Lo esencial:

- **Tercer carril Guamasa-Aeropuerto Norte** (Gobierno de Canarias). Solo hacia Santa Cruz. Se adjudicó por 58,2 M€
  (IGIC incluido) a la UTE Ferrovial-Asyota y se formalizó el 2-10-2026, con 35 meses de plazo según la
  licitación (anuncio en el Diario Oficial de la UE del 24-12-2025: calzada hacia Santa Cruz entre los PK 11+400 y
  15+000). En octubre de 2024 se anunció su licitación para el primer trimestre de 2025; salió en diciembre de 2025.
- **Regulación de accesos** (Cabildo y DGT; 1,8-4 M€). Anunciada en mayo de 2025, con una prueba piloto prevista
  para octubre y noviembre de 2025; pruebas de la DGT en enero de 2026; sin implantar.
- **Bus-VAO «inteligente»** en la TF-5 (Cabildo; 6,2 M€). Información pública en junio de 2026; promete ahorros de
  tiempo con simulaciones no publicadas.
- **Tercer carril Guamasa-La Orotava** (unos 300 M€) y **circunvalación de La Laguna** (355 M€). Son proyectos sin
  fecha de obra:
  - el primero empieza en Guamasa, después del estrechamiento de la tarde, y aliviaría La Matanza;
  - el segundo descargaría el tramo de La Laguna.

  Ninguno amplía Los Rodeos-Guamasa hacia el Norte.
- **Peajes por congestión.** Son una opción del PIMSIT; exigen cambiar la ley canaria y la presidenta del Cabildo
  los descartó el 7-10-2026.

**Transporte público** (g10; asociación no causal). Con la gratuidad para los residentes que viajan con frecuencia
(desde el 1-1-2023), TITSA casi duplicó sus viajeros: índice 190 en 2025, con 2019 = 100. En el mismo periodo, el
tráfico de la TF-5 (IMD media de las cuatro estaciones de g10) se quedó en 99. Es una coincidencia entre dos series, no una medida del efecto. No permite saber
cuántos viajes en coche se evitaron ni si el hueco lo ocupó demanda que antes no circulaba.

## 5. Verificación de los apuntes de partida

De 53 afirmaciones: **19 confirmadas, 15 parcialmente ciertas, 8 sin fuente verificable y 11 falsas o
erróneas** (`datos/afirmaciones_apuntes.csv`, g09). Los errores incluyen:
- cálculos: «+33 %» al pasar de 2 a 3 carriles, cuando es +50 %;
- unidades: densidad expresada en veh/h;
- flujos imposibles: 5.500 veh/h por dos carriles, cuando el máximo medido en Los Rodeos en 2025 es 3.880 veh/h;
- atribuciones: el −50 % es del Bus-VAO, no del tercer carril.

## 6. Reproducibilidad y pruebas

- **Entorno.** R 4.3.3 y versiones fijadas en `renv.lock` (70 paquetes, con sus dependencias) y en
  `entorno/versiones_paquetes.csv`, que `main.R` comprueba al empezar: R y 13 paquetes, entre ellos los del
  dispositivo PNG de los gráficos. La ejecución entregada usó exactamente esas versiones
  (`entorno_versiones.csv`). La zona horaria se fija en `Atlantic/Canary` y cada paso aleatorio tiene su semilla
  (`montecarlo_semillas.csv`).
- **Ejecución completa sin intervención.** Duró 62,5 minutos y dejó 0 avisos (`registro_avisos.txt` recoge todos
  los avisos del análisis). `main.R` guarda la huella de sus entradas al empezar y la vuelve a calcular al acabar: los
  109 ficheros de `main.R`, `R/`, `tests/`, `entorno/`, `renv.lock` y `datos/` no cambiaron.
- **Pruebas** (`tests/`; resultado en `salidas/resultado_pruebas.csv`): 72 bloques y 2.536 comprobaciones,
  con 0 fallos. Cubren:
  - **invariantes físicos:** conservación de vehículos, identidad de Little, caso analítico FIFO, cola y salidas no
    negativas y salidas por debajo de la capacidad minuto a minuto, el tercer carril nunca empeora, monotonía de
    los horizontes y cuellos en serie con almacenamiento finito;
  - **restricción aguas abajo:** con el tramo siguiente lleno, el tercer carril y la regulación no añaden caudal;
    el escalonamiento no pierde vehículos;
  - **casos extremos:** sin demanda, demanda que nunca se disipa, caída de capacidad nula o máxima, holgura nula o
    muy alta, día de cambio de hora, mes sin registros y fichero con BOM;
  - **validación:** mitades de la validación cruzada, intervalo predictivo, regla de elección de la especificación y
    tabla de validación con cinco indicadores por sentido;
  - **diferencias emparejadas:** sin ganador cuando la diferencia no es material;
  - **la procedencia:** integridad, catálogo, sumas de control de los 24 extractos y contraste con el catálogo
    nacional;
  - **la trazabilidad del Monte Carlo y de las fichas:** todas las semillas del código figuran en la tabla de
    semillas, y el rango de los escenarios adversos de cada ficha no incluye la referencia ni la cota favorable;
  - **la no regresión:** las tablas clave de la ejecución entregada están en `tests/referencia/`, con su
    configuración, y una ejecución completa nueva con la misma configuración tiene que reproducirlas.
- **Dos ejecuciones completas en copias limpias, con el código entregado** (`docs/reproducibilidad_dos_ejecuciones.csv`, generada con
  `tests/comparar_ejecuciones.R`): 191 de 191 tablas y gráficos de salidas iguales dentro de la tolerancia (diferencia relativa
  ≤ 1e-8 en las cifras, mismas filas, columnas y textos), contando la serie horaria comprimida y el resultado de las
  pruebas, ejecutadas en las dos copias; 191 son iguales byte a byte. No se comparan los 2 ficheros propios de
  cada ejecución (la configuración, con su hora de inicio, y el manifiesto de huellas) ni los registros de texto de la
  ejecución (resumen, sesión y avisos), que llevan la hora; los de la segunda copia están en `docs/segunda_ejecucion/`.
  Es la misma máquina: muestra que el resultado no depende de la ejecución, no que otra persona lo reproduzca.
- **Manifiestos.** `salidas/manifiesto_ejecucion.csv` tiene el SHA-256 de `main.R`, `R/`, `tests/` (sin las
  referencias de no regresión, que se copian de la propia ejecución), `entorno/`, `renv.lock`, `datos/` y `salidas/` al
  acabar la ejecución; `manifiesto_entrega.csv`, el de todos los ficheros
  entregados, también los que se añaden después (documentos, panel, referencia de no regresión y resultado de las
  pruebas). Prueban que los ficheros no han cambiado después, no quién los generó.
- **Reimplementación en Python** (`docs/verificacion_independiente/`). Recalcula las cifras observadas con otro
  lenguaje, a partir de los mismos datos del proyecto y de las definiciones del código R. Sirve para detectar
  errores de programación, pero **no es una verificación externa**: no la ha hecho otra persona ni parte de otras
  fuentes.

## 7. Límites y datos que faltan

- Es un modelo de **cola puntual**, no una microsimulación. Sirve para comparar alternativas con los mismos supuestos
  y ver qué decide el resultado, no para dimensionar obras. La restricción aguas abajo y los cuellos en serie con
  almacenamiento son aproximaciones con longitudes supuestas.
- La congestión se deduce de **rangos de velocidad en puntos de aforo**, no de tiempos de recorrido. No hay ninguna
  demora observada.
- La **capacidad libre del tramo siguiente** es una estimación indirecta: no hay aforos de ramales y la capacidad de
  abajo sale de los caudales de la misma punta. Es el supuesto que más pesa en el tercer carril (apartado 2.2).
- La **descarga del modelo** cuadra con la mediana del día, no con su forma dentro de la cola: por la mañana
  sobrestima el caudal de las horas de cola plena (+260 veh/h en 2026), y el intervalo predictivo queda por
  debajo del 80 % en algunos indicadores (apartado 2.5).
- 6 estación-sentidos tienen **carriles pendientes de confirmación** entre el catálogo de 2026 y el inventario de
  2006, y los ficheros usados no dan el punto kilométrico de las estaciones. En particular, la **posición de Ermita Cruz
  Chica (103) respecto al enlace de Guamasa** no está publicada: el catálogo de carriles la etiqueta «Los Rodeos» y la
  TF-152 tiene una estación del mismo nombre en su «Enlace TF-5», pero el CSV de IMD la asigna al tramo «El Sauzal» y
  el Cabildo cita su IMD como la del tramo Guamasa-El Sauzal (afirmación 3 de los apuntes). El estudio la sitúa entre
  Los Rodeos y Guamasa; si estuviera aguas arriba del enlace, el caudal medido con cola sería la descarga del cuello
  menos las entradas de Guamasa, y el tercer carril contratado empezaría aguas abajo del aforador. El punto
  kilométrico está pedido en `docs/solicitud_datos_cabildo.md`.
- Las **elasticidades, la eficacia de la regulación y el efecto de la tarificación** se toman de la literatura
  (columna `transferibilidad` de `parametros_modelo.csv`): los aforos no las informan.
- **Incidentes, obras y lluvia** no están vinculados a los días. El Cabildo publica un registro de «Incidencias en
  carreteras de Tenerife» (2010-2026, con carretera, tramo, fecha y hora de inicio y tipo) que se identificó pero no
  se incorporó, porque su descarga no se pudo completar en el entorno del análisis; la lluvia exige una clave de
  AEMET OpenData. Los días con la punta anómala se marcan y se prueba el análisis sin ellos.
- Los efectos de la ULL y de la pasarela son **asociaciones no causales**: sin registros de obras ni de incidencias
  incorporados y sin un grupo de control válido.
- El calendario incluye festivos autonómicos e insulares, no los municipales.
- **Diciembre de 2024** no está en el extracto horario aunque el portal lo publica. No afecta a las cifras de 2025
  ni a la validación con 2026.
- El contraste que hace `main.R` con la publicación original es de **metadatos** (URL, identificador, nombre y
  licencia) para una muestra de recursos, más las huellas y las sumas de control de las copias locales; no vuelve a
  descargar nada (`DESCARGAR_HORARIOS <- TRUE` lo haría). El contraste con descarga directa de los 37 recursos es
  un paso aparte, fuera de `main.R` (`herramientas/comprobaciones/contrastar_fuentes.py`, evidencia en
  `docs/contraste_fuentes/`), hecho la madrugada del 17-10-2026 (hora canaria).
- **Faltan datos públicos clave** (`datos/matriz_lagunas.csv`, con el estado de cada petición):
  - caudales cada 5-15 minutos;
  - tiempos de recorrido;
  - aforos de los ramales;
  - matriz origen-destino;
  - ocupación de los vehículos;
  - un aforador fiable en Padre Anchieta;
  - el inventario de carriles vigente y el punto kilométrico de las estaciones.

  Con ellos se podría pasar a un modelo de red y validar la espera.

## Documentos del proyecto

| Documento | Contenido |
|---|---|
| `docs/METODOLOGIA.md` | Método completo: datos y procedencia, calidad, geometría, capacidad libre, modelo, Monte Carlo, validación, demoras, previsiones, causalidad y reproducibilidad |
| `docs/VALIDACION_Y_CALIDAD.md` | Los diez criterios de calidad del estudio, cómo se comprueba cada uno y con qué resultado |
| `docs/solicitud_datos_cabildo.md` | Datos que habría que pedir al Cabildo |
| `docs/verificacion_independiente/` | Reimplementación en Python de las cifras observadas (no es una verificación externa) |
| `docs/reproducibilidad_dos_ejecuciones.csv` | Dos ejecuciones completas en copias limpias con el código entregado, fichero a fichero, con la tolerancia |
| `docs/contraste_fuentes/` | Contraste de los 37 recursos oficiales descargados con el portal y de la población con el INE |
| `docs/segunda_ejecucion/` | Registros de sesión y de avisos de la segunda ejecución completa |
| `docs/REVISION_2026-10-20.md` | Revisión del 20-10-2026: qué se comprobó, qué cambió (hechos, código, panel, documentación) y qué queda abierto |
| `docs/comprobacion_base_nocturna_2025.csv` | Línea base de velocidad de madrugada calculada solo con 2025: horas congestionadas de 2025 que cambiarían (`herramientas/comprobaciones/`) |

## Estructura

```text
main.R                          Ejecuta todo (secciones 1-11, con la 4b) y escribe salidas/
R/00_utilidades.R               Paquetes, rutas, estaciones, tema gráfico, formato español
R/01_datos_validacion.R         IMD: carga, 10 reglas de validación, contraste con las copias oficiales
R/02_descriptivo.R              Gráficos de aforos anuales y transporte público
R/03_saturacion.R               «k crítico»: margen de capacidad en la hora punta
R/04_modelo_cuello_botella.R    Modelo de cola de 24 h: perfil híbrido, especificación de la descarga, restricción
                                aguas abajo, cuellos en serie, esperas por cohortes, alternativas
R/05_montecarlo.R               Simulaciones, calibración, sensibilidad, auditoría del Monte Carlo, Bus-VAO
R/06_proyectos_verificacion.R   Actuaciones, verificación de los apuntes, comprobaciones aritméticas
R/07_datos_horarios.R           Aforos horarios: lectura, reglas H1-H9, colas, capacidad, holgura
R/08_comprobaciones_modelo.R    Comprobaciones numéricas del modelo en cada ejecución (conservación, límites)
R/09_trazabilidad.R             Manifiesto SHA-256 de código, datos y salidas; registro de la sesión
R/10_validacion_escenarios.R    Cobertura, cambio de hora, ULL, validación, previsión, escenarios adversos,
                                trasvase al transporte público, confianza, fuentes
R/11_validacion_y_trazabilidad.R Validación día a día, diagnóstico de la descarga, geometría, balance por tramos,
                                variantes de la holgura, demoras, diseño del Monte Carlo, procedencia, banderas
                                de calidad, previsiones condicionadas y fichas de las alternativas
R/12_validacion_predictiva.R    Validación cruzada temporal, intervalo predictivo y elección de la especificación
R/13_comparacion_y_trazabilidad.R Diferencias emparejadas, coste y plazo, retraso de obra, uso de la geometría,
                                correspondencia de campos, contraste con la publicación original, días atípicos,
                                cola remanente y metadatos de los gráficos
tests/                          Pruebas testthat, referencia de no regresión y comparador de ejecuciones
entorno/, renv.lock             Versiones fijadas de R y de los paquetes
datos/                          Entradas (cada fichero con su fuente)
docs/                           Metodología, validación y calidad, solicitud de datos, reimplementación en Python,
                                contraste de los originales con el portal y registros de la segunda ejecución
herramientas/                   Ensamblado de los ficheros horarios descargados, plantillas que rellenan los documentos
                                con las cifras de salidas/, comprobación de las cifras del panel y comprobaciones
                                aparte (no los usa main.R)
panel/index.html                Panel autónomo de resultados (abrir en un navegador)
salidas/graficos/               g01-g21 más g07b y g15b (23 PNG)
salidas/tablas/                 Tablas de resultados (CSV)
salidas/panel/                  Tablas limpias que usa el panel
salidas/resumen_resultados.txt  Todo lo que imprime la ejecución
salidas/manifiesto_ejecucion.csv  SHA-256 de código, datos y salidas
salidas/registro_sesion.txt     Versiones de R y de los paquetes, y duración
salidas/registro_avisos.txt     Avisos de la ejecución
salidas/configuracion_ejecucion.csv  Simulaciones, semillas de la auditoría del Monte Carlo y zona horaria
salidas/resultado_pruebas.csv   Resultado de las pruebas
manifiesto_entrega.csv          SHA-256 de todos los ficheros entregados, también los añadidos después de la
                                ejecución (documentos, panel, referencia de no regresión y pruebas)
```

## Datos

| Fichero | Contenido | Fuente |
|---|---|---|
| `horarios/tf5_horario_AAAA-MM.csv.gz` (24) | Registros horarios por carril de las estaciones de la TF-5 | Cabildo de Tenerife, datos.tenerife.es |
| `horarios/meta_AAAA-MM.json` (24) | URL, fecha, tamaño y SHA-256 del fichero oficial y del extracto; sumas de control | Generado al descargar |
| `oficial/` | CSV oficiales de IMD 2018-2025, catálogo de carriles, diccionarios de datos, manifiesto e instantánea del catálogo del portal | datos.tenerife.es |
| `imd_tf5_2018_2025.csv` | IMD por estación y sentido (idéntica, valor a valor, a las copias de los CSV oficiales de `oficial/`) | Ídem |
| `fuentes_horarias.csv` | Índice de los 24 ficheros horarios oficiales: enlace, tamaño, SHA-256 y extracto | datos.tenerife.es |
| `fuentes_imd.csv` | Enlaces de los CSV oficiales de IMD | datos.tenerife.es |
| `contraste_catalogo_nacional_2026-10-16.csv` | Recursos de 2025 tal como los lista el catálogo nacional (URL, nombre, licencia y fechas del conjunto) | datos.gob.es, consultado el 16-10-2026 |
| `imd_contexto_2025.csv` | IMD 2025 de la TF-1, TF-2, TF-13, TF-152, TF-217 y TF-24 | datos.tenerife.es |
| `carriles_tf5.csv` | Carriles aforados por sentido (los del catálogo oficial) | Catálogo oficial de carriles |
| `geometria_tramos.csv` | Carriles aforados, del inventario de 2006 y del modelo; estado (confirmado o pendiente) y escenario alternativo | Catálogo de carriles (2026) y PTEOSVAM (2006) |
| `festivos_canarias.csv` | Festivos autonómicos e insulares de 2024-2026 | BOC |
| `poblacion_tenerife.csv` | Población de Tenerife, 2021-2025 | INE, Censo anual de población (tabla 78749) |
| `escenarios_demanda.csv` | Ritmos de crecimiento simulados y su justificación | IMD del Cabildo e INE |
| `transporte_publico_viajeros.csv` | Viajeros de TITSA y del tranvía, 2017-2025 | Notas y memorias de TITSA y Metrotenerife, y prensa (fuente de cada fila) |
| `parametros_modelo.csv` | Rangos de los parámetros, tipo, fuente y transferibilidad | Aforos, HCM, Goodwin, Cassidy y Bertini… |
| `coste_plazo_riesgo.csv` | Coste, plazo, puesta en servicio prevista y riesgos de cada alternativa | Contratos, licitaciones y anuncios (fuente de cada fila) |
| `confianza_alternativas.csv` | Criterios de confianza, supuesto clave y limitación principal de cada alternativa | Elaboración propia |
| `limitaciones_por_resultado.csv` | Categoría (observado, estimado, supuesto, simulado o asociación no causal), origen, límites e incertidumbre de cada resultado | Elaboración propia |
| `graficos_metadatos.csv` | Tipo de resultado, horizonte, hipótesis e incertidumbre de cada gráfico | Elaboración propia |
| `matriz_lagunas.csv` | Datos que faltan, cómo se suplen, dónde pedirlos y estado de la petición | Elaboración propia |
| `fuentes_documentales.csv` | Fuentes documentales con fecha de consulta y licencia | Varias |
| `proyectos.csv` | Actuaciones: coste, situación y fuente | Gobierno de Canarias, Cabildo, prensa |
| `afirmaciones_apuntes.csv` | 53 afirmaciones de los apuntes con veredicto, dato y fuente | Varias |

## Fuentes

- Cabildo de Tenerife, portal de datos abiertos: [Intensidad media diaria de tráfico (IMD)](https://datos.tenerife.es/ckan/dataset/1717bda1-6b7b-43e0-be4e-e3ed060b8b97),
  [Rango de velocidades de los carriles](https://datos.tenerife.es/ckan/dataset/079b37ef-674e-411f-8886-f4c5a53826ae)
  e Intensidad diaria de tráfico de Tenerife por carril y hora:
  [2024](https://datos.tenerife.es/ckan/dataset/e4cf320e-dda5-4b9a-bae3-ec3d6a252c80),
  [2025](https://datos.tenerife.es/ckan/dataset/94a021a2-1dea-4526-9e17-3290b3b9add3) y
  [2026](https://datos.tenerife.es/ckan/dataset/d02ccf54-aca2-4a82-9ef0-fbd285b5f401).
- Catálogo nacional de datos abiertos: [Intensidad diaria de tráfico de Tenerife (2025)](https://datos.gob.es/es/catalogo/l03380011-intensidad-diaria-de-trafico-de-tenerife-2025)
  (contraste de la procedencia) e [Incidencias en carreteras de Tenerife](https://datos.gob.es/es/catalogo/l03380011-incidencias-en-carreteras-de-tenerife)
  (fuente identificada, no incorporada).
- Cabildo de Tenerife, [Plan Territorial Especial de Ordenación del Sistema Viario del Área Metropolitana, Anexo III-b](https://tenerife.es/documents/d/portal/sistema-viario-metropolitano-ANEXOIIIb)
  (ficha de la TF-5), aprobado el 19-7-2006 y publicado en el [BOC n.º 38 de 21-2-2007](https://www.gobiernodecanarias.org/boc/2007/038/023.html).
- INE, [Censo anual de población, tabla 78749](https://www.ine.es/jaxi/Tabla.htm?tpx=78749).
- Gobierno de Canarias y RTVC: [formalización del contrato del tercer carril (2-10-2026)](https://rtvc.es/obras-publicas-formaliza-contrato-obras-tercer-carril-tf-5-guamasa-aeropuerto-norte-2-octubre-2026/)
  y [adjudicación por 58,2 M€ (10-9-2026)](https://rtvc.es/adjudicada-la-obra-del-tercer-carril-de-la-tf-5-10-septiembre-2026/).
  Anuncio de la licitación para el primer trimestre de 2025: [RTVC, 29-10-2024](https://rtvc.es/obras-tercer-carril-guamasa-los-rodeos-se-licitaran-primer-trimestre-2025/).
  Anuncio oficial de licitación (35 meses; calzada hacia Santa Cruz, PK 11+400 a 15+000): [Diario Oficial de la UE, TED 861575-2025](https://ted.europa.eu/es/notice/861575-2025/pdf).
- Gratuidad del transporte público para residentes desde el 1-1-2023: [elDiario.es, 24-12-2022](https://www.eldiario.es/canariasahora/sociedad/guaguas-gratis-canarias-descuento-bono-1-enero_1_9821483.html).
- Regulación de accesos: [RTVC, 6-5-2025](https://rtvc.es/tenerife-instala-semaforos-inteligentes/).
- Universidad de La Laguna y prensa sobre los horarios escalonados y la pasarela del Padre Anchieta:
  enlaces fila a fila en `datos/fuentes_documentales.csv`, `datos/proyectos.csv` y `datos/afirmaciones_apuntes.csv`.
- Calendarios laborales de Canarias (BOC): enlaces en `datos/festivos_canarias.csv`.
- Modelo: Vickrey (1969), Newell (1993), Cassidy y Bertini (1999), Highway Capacity Manual, Goodwin (1996),
  SACTRA (1994), Cervero (2003), Duranton y Turner (2011), Hymel, Small y Van Dender (2010); las fuentes de
  cada parámetro están en `datos/parametros_modelo.csv`.
