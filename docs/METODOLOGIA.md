# Metodología del proyecto TF-5

Este documento reúne el método completo del proyecto: qué datos se usan y cómo se comprueban, cómo se deduce
cada estimación, cómo funciona el modelo, cómo se calibra y se valida, y qué significa cada cifra. Las cifras
que cita salen de la ejecución entregada (`salidas/tablas`). El `README.md` resume los resultados, y
`docs/VALIDACION_Y_CALIDAD.md` reúne los criterios de calidad y cómo se comprueban.

## 0. Alcance y tipos de resultado

Es un estudio técnico-predictivo con simulación exploratoria, hecho solo con datos públicos. No sustituye a una
microsimulación con datos de 15 minutos, tiempos de recorrido y matrices origen-destino. Cada resultado se rotula
con una categoría (`datos/limitaciones_por_resultado.csv`: 9 simulados, 7 observados, 4 supuestos, 3 estimados y 2 asociaciones no causales), y cada gráfico, con su tipo de
resultado, su horizonte, su hipótesis y su incertidumbre (`datos/graficos_metadatos.csv`):

| Categoría | Qué es | Ejemplos |
|---|---|---|
| Observado | Sale directamente de los aforos oficiales o de documentos, con las reglas de depuración declaradas | Horas de cola de cada día; caudal en las horas con cola; carriles aforados; coste de un contrato |
| Estimado | Se deduce de los aforos con un método explícito | Capacidad libre del tramo siguiente; especificación y parámetro de descarga calibrados |
| Supuesto | Valor o regla que no sale de los datos del proyecto y se declara | Crecimiento de la demanda; elasticidades de la literatura; longitud entre cuellos; descarga fuera de las horas con datos |
| Simulado | Resultado del modelo calibrado bajo esos supuestos: un escenario condicionado | Demoras; reducción de la demora de cada alternativa; diferencias entre alternativas; previsiones |
| Asociación no causal | Coincidencia temporal entre una actuación y un cambio en los aforos, sin un control válido | Horarios escalonados de la ULL; pasarela del Padre Anchieta |

Las cifras simuladas se dan con mediana y banda de parámetros p10-p90 y en números redondos: los porcentajes, sin
decimales. La banda de parámetros describe las combinaciones compatibles con los aforos para un día típico; el
intervalo predictivo del 80 % (apartado 8) es el que se compara con días concretos.

## 1. Datos y procedencia

**Recursos.** Todos son del portal de datos abiertos del Cabildo de Tenerife (datos.tenerife.es), con licencia
CC BY según el propio catálogo:
- 24 ficheros mensuales de registros horarios por carril (TXT), de septiembre de 2024 a septiembre de 2026, sin
  diciembre de 2024;
- 13 ficheros oficiales más: IMD 2018-2025, el catálogo de carriles y los diccionarios de datos.

Se completan con fuentes documentales (`datos/fuentes_documentales.csv`, con URL, fecha de consulta y licencia),
como el inventario viario del PTEOSVAM, el INE, el BOC, la ULL o la prensa.

**Manifiesto de procedencia** (`salidas/tablas/procedencia_datos.csv`, generado por `procedencia_datos()` en
cada ejecución). Tiene una fila por recurso (24 horarios, 13 oficiales y 3 publicados sin usar) con
estos campos:
- organismo, conjunto, recurso, formato, URL e identificador del recurso;
- licencia (leída del catálogo);
- fecha de modificación en origen (la versión del recurso) y fecha de descarga;
- bytes y SHA-256 del original, ruta y SHA-256 de la copia;
- cobertura temporal y espacial, cabecera, filtros aplicados y unidades;
- contraste con el catálogo, conservación de los totales, integridad y forma de verificación.

**Correspondencia de campos** (`correspondencia_de_campos.csv`). Los 31 campos de los ficheros horarios, de la
IMD y del catálogo de carriles, cada uno con su definición en el diccionario oficial y su nombre en el proyecto. Los
identificadores de estación son los del Cabildo (`ESTACIONES_TF5` en `R/00_utilidades.R`).

**Integridad no es autenticidad.** El SHA-256 prueba que la copia del proyecto es la misma que se registró al
descargarla. No prueba que el origen sea auténtico, y eso no se puede probar desde dentro del proyecto. Lo que se
hace son dos contrastes:
- cada recurso se compara (tamaño y fecha de modificación) con una instantánea del catálogo del portal tomada el
  16-10-2026 y guardada en el proyecto (`datos/oficial/catalogo_portal_2026-10-16.json`). Para los extractos
  horarios se comprueba además que los totales por estación y sentido (filas, ligeros, pesados y rangos) coinciden
  con las sumas de control que calculó sobre el TXT original, al descargarlo, un script del navegador que no se
  conserva (queda su registro en `datos/horarios/meta_AAAA-MM.json`);
- una muestra se contrastó el 16-10-2026 con una publicación fuera del proyecto: el catálogo nacional de datos
  abiertos (datos.gob.es), que federa el portal del Cabildo. Los 12 TXT de 2025 y su diccionario coinciden (13 de
  13) en URL, identificador, nombre y licencia (`contraste_publicacion_original()`;
  `contraste_publicacion_original.csv`; lo listado está en `datos/contraste_catalogo_nacional_2026-10-16.csv`).

En la ejecución entregada no se volvió a descargar nada. `CONTRASTAR_EN_LINEA <- TRUE` toma una instantánea nueva
del catálogo (`consultar_catalogo_portal()`), y `DESCARGAR_HORARIOS <- TRUE` vuelve a bajar los TXT y compara su
huella: es la forma de contrastar valores, no solo metadatos.

**Discrepancias y huecos registrados** (en la tabla de procedencia, en `datos/matriz_lagunas.csv` con el estado de
cada petición y en `docs/solicitud_datos_cabildo.md`):
- diciembre de 2024 está publicado pero no se descargó;
- los diccionarios de datos de 2024 y de 2026 no se descargaron: los datos se leen con el de 2025, porque la
  cabecera de los 24 TXT es idéntica;
- el filtro de extracción guarda 8 estaciones de la TF-5 en 2024 y 2026 y las 12 que trae el fichero en 2025 (el
  corredor de 7 estaciones está en todos los meses salvo septiembre de 2026, sin Hospital Residencia);
- Hospital Residencia no tiene filas en septiembre de 2026;
- 6 estación-sentidos tienen un número de carriles distinto en el catálogo de aforos y en el inventario viario
  (apartado 4);
- el registro público «Incidencias en carreteras de Tenerife» se identificó pero no se incorporó (apartado 2).

## 2. Calidad de las series

- **Originales inalterados.** Los extractos (`datos/horarios/tf5_horario_AAAA-MM.csv.gz`) son las filas de la TF-5
  de cada TXT oficial, sin las columnas de nombre. Nunca se modifican, y las pruebas comprueban su huella.
- **Reglas H1-H9** (`validacion_horarios.csv`): rangos de velocidad que no suman los vehículos, horas incompletas,
  carriles sin vehículos, duplicados, rangos negativos, caudales implausibles, media horaria distinta de la IMD y
  perfil horario anómalo en un carril.
- **Serie depurada con banderas** (`salidas/tablas/horarios_corredor_con_banderas.csv.gz`). Tiene una fila por
  estación, sentido, día y hora con estas columnas: `estacion_id`, `sentido`, `dia`, `hora`, `laborable`, `veh`, `pesados`, `lento`, `carriles`, `carriles_con_dato`, `completa`, `velocidad_valida`, `duplicado`, `negativos`, `caudal_implausible`, `agosto`, `cambio_de_hora`, `dia_valido`, `imputado`, `usado_en_el_analisis`, `estado`, `motivo`.
- **No se imputa.** Una hora incompleta o un día que no cumple las reglas se excluye. La tasa de imputación es del
  0 % por estación, mes y hora (`cobertura_e_imputacion_por_estacion_mes_hora.csv`, con la cobertura de cada
  celda). No se rellenan los meses sin datos de Padre Anchieta: serían colas inventadas.
- **Día válido:** laborable (sin festivos autonómicos e insulares ni agosto), con las 24 horas completas y con al
  menos el 85 % del tráfico mediano de ese mes en esa estación y sentido.
- **Días atípicos** (`dias_atipicos()`; `dias_atipicos.csv` y `dias_atipicos_resumen.csv`). Cada día laborable de
  cada estación y sentido tiene un estado (usado o excluido) y, si se excluye, su motivo: agosto, día incompleto
  (avería o corte del aforador), tráfico por debajo del 85 % de la mediana del mes o cambio de hora. Los días usados
  llevan una marca si pueden ser atípicos: puente (día laborable entre un festivo y el fin de semana), Navidad (24 de
  diciembre a 6 de enero), Semana Santa (lunes a viernes antes del domingo de Pascua, calculado con el algoritmo de
  Meeus) y punta anómala (caudal de la ventana de la punta más de tres desviaciones absolutas medianas, escaladas, por
  debajo de la mediana de los días válidos del mes: un criterio de valor atípico, no un número fijo de días). Los
  cambios de hora caen en domingo y no afectan a los días laborables. Incidentes, obras y lluvia no están vinculados:
  el Cabildo publica un registro de incidencias (carretera, tramo, fecha y hora de inicio y tipo) que se identificó
  pero no se incorporó, y la lluvia exige una clave de AEMET OpenData (`matriz_lagunas.csv`, D09 y D15).
- **Sin días atípicos** (`sensibilidad_sin_dias_atipicos()`). Se repiten las horas de cola, el horario y la descarga
  de cada cuello sin los puentes, la Navidad y la Semana Santa; sin las puntas anómalas de su estación y sentido; y
  sin ninguno de ellos.
- **Resumen de las banderas** (`banderas_resumen.csv`). Horas que marca cada bandera, en el corredor y por estación
  y sentido, sobre las horas con registro. Las banderas se solapan, así que no suman el total excluido.
- **Conservación.** Los totales de cada extracto coinciden con las sumas de control registradas del TXT original,
  en los 24 meses. La suma de los carriles por estación, sentido y hora reproduce el total (0 vehículos de
  diferencia), pero es una comprobación de coherencia del código, no independiente: el total se construye
  sumando los carriles.
- **Sensibilidad a la depuración** (`sensibilidad_depuracion.csv`). Se repite el diagnóstico de los dos cuellos sin
  el filtro del tráfico diario, con un filtro del 95 %, incluyendo agosto e imputando con dos métodos las horas a las
  que les falta un solo carril: A, proporcional (los carriles que faltan llevan lo mismo que los que hay); B, la
  mediana de las horas completas de la misma hora, mes y estación-sentido. En los cuellos no hay horas así, de modo
  que las dos variantes de imputación coinciden con la principal.

## 3. Diagnóstico de la congestión (observado)

- **Hora congestionada:** al menos el 60 % de los vehículos pasa a menos de 80 km/h y hay 30 puntos más de vehículos
  lentos que de madrugada en la misma estación. Se publica la sensibilidad a 50 % y +20 y a 70 % y +40.
- **Horario de la cola:** primera hora congestionada y fin de la última de cada día válido.
- **Caudal en las horas con cola** del cuello: es lo que pasa por Ermita Cruz Chica en esas horas, de 3 a 13 h por
  la mañana y de 11 a 24 h por la tarde (horas con cola en Bomberos La Laguna). No es una capacidad: mezcla la hora
  de inicio, las horas centrales y las de disipación.

## 4. Geometría y capacidad

- **Fuentes de los carriles.** Por un lado, el catálogo de carriles de los aforos (JSON del Cabildo, julio de 2026).
  Por otro, el inventario del PTEOSVAM, el Plan Territorial Especial de Ordenación del Sistema Viario del Área
  Metropolitana (Anexo III-b, ficha de la TF-5; aprobado el 19-7-2006; BOC n.º 38 de 21-2-2007). El inventario da
  por tramo los carriles por sentido (el primero, hacia el Norte): Santa Cruz-Guajara 4+3, Guajara-Padre Anchieta
  3+3, paso por Padre Anchieta 3+2, Padre Anchieta-Los Rodeos 3+3 y Los Rodeos-Icod 2+2.
- **Estado** (`datos/geometria_tramos.csv`; `geometria_y_capacidad.csv`). Hay 8 estación-sentidos
  confirmados y 6 **pendientes de confirmación**. Cada fila tiene una explicación posible (carril de enlace o
  auxiliar contado como carril, u obra posterior a 2006) y un escenario alternativo.
- **Capacidad por carril:** 1.850-2.100 veh/h (moda 1.950), igual en el modelo de cola y en el «k crítico». Parte
  del HCM y se acota con los caudales máximos por carril del tramo de 2 carriles de Los Rodeos-Guamasa.
- **Vínculo de cada capacidad.** `geometria_y_capacidad.csv` liga cada estación-sentido a sus carriles aforados, del
  inventario y del modelo, a la fecha del catálogo, a su fuente y a su papel en el modelo: cuello, tramo siguiente
  o Bus-VAO. También da su p99 y su máximo por carril en 2025.
- **Uso de la geometría** (`uso_geometria()`; `uso_de_la_geometria.csv`). Los 11 cálculos que dependen del número de
  carriles (k crítico, capacidad de cada cuello, tramo siguiente, tercer carril, Bus-VAO, longitud de la cola,
  almacenamiento entre cuellos y balance), con los carriles que usa cada uno, su estado, su fuente y el supuesto que
  lo sustituye si no está confirmado. Ninguna capacidad ni balance se calcula sin una fuente o un supuesto
  explícito.
- **Escenarios geométricos ejecutados:**
  - el k crítico con los carriles del inventario (`k_critico_geometria_alternativa.csv`);
  - la capacidad libre del tramo siguiente con los carriles del inventario en Campus Guajara y Bomberos La Laguna,
    con capacidad 3 × 1.850 × 0,82 (cota baja: el mínimo de la capacidad por carril y la mayor caída de capacidad del modelo);
  - el tramo siguiente sin capacidad libre (2 carriles efectivos en Padre Anchieta).

## 5. Capacidad libre del tramo siguiente y balance por tramos (estimado)

- **Definición.** En cada hora con cola en el cuello, `holgura = (C_abajo − F_abajo) / F_cuello`, con
  `C_abajo` = p99 del caudal horario de 2025 de la estación de abajo. Se toma la estación más restrictiva: Bomberos
  La Laguna o Campus Guajara por la mañana, y La Matanza por la tarde. Las entradas y salidas de los ramales se
  cancelan en la cuenta: la holgura no las necesita, pero tampoco las ve. Como `C_abajo` sale de caudales de la
  misma punta, la estimación es circular en parte.
- **En el modelo** cada simulación toma un cuantil `u ~ U(0, 1)`, común a todas las horas, de la distribución
  estimada de cada hora (una matriz de 24 × 101). Lo que admite el tramo siguiente es
  `D = descarga del modelo en esa hora × (1 + holgura)`: la holgura es relativa al caudal del cuello, así que se
  aplica a la descarga del modelo, con los mismos factores de hora y de pesados que la especificación. Sin
  propagación de la cola, una holgura negativa cuenta como 0 y `D` solo limita lo que añaden el tercer carril y la
  regulación; con propagación, `D` limita también la situación actual (la cola de abajo frena el cuello). Con el
  tercer carril, la capacidad del cuello sube a la de tres carriles, pero nunca por encima de `D` ni por debajo de
  la actual.
- **Variantes** (`variantes_holgura()`; `sensibilidad_holgura_caso1.csv` y `_caso2.csv`, con sus resultados). Por
  la mañana son 9; por la tarde, 6: La Matanza no tiene velocidad utilizable, así que no se sabe cuándo
  tiene cola (variantes «solo horas sin cola» y «cuello desplazado»), y sus carriles coinciden en el catálogo y en
  el inventario. Las de la mañana:
  - principal: capacidad de abajo = p99 de su caudal; entradas netas de los aforos;
  - capacidad de abajo más baja (p95 de su caudal);
  - capacidad de abajo más alta (p99,9 de su caudal);
  - capacidad de abajo solo con horas sin cola en esa estación (p99);
  - ramales: entradas un 10 % mayores (demanda que hoy no consigue entrar);
  - ramales desconocidos: salidas del 5 % del caudal después del punto crítico;
  - cuello desplazado: sin holgura en las horas con cola en la estación de abajo;
  - carriles del inventario de 2006 en Campus Guajara y Bomberos La Laguna (cota baja: 3/3 x 1.850 x 0,82);
  - holgura nula en todas las horas.

  Para cada variante se da qué parte de las combinaciones calibradas da una cola de hoy dentro del rango medido en
  2025 (`parte_cola_hoy_en_rango_medido`): con propagación, una variante con menos capacidad abajo alarga también la
  cola de hoy, y si la saca del rango medido, los aforos no son compatibles con ella.
- **Balance por tramos** (`balance_tramos()`; `balance_por_tramos.csv` y `balance_por_tramos_hora.csv`). Para cada
  par de estaciones (las consecutivas y Ermita Cruz Chica → Campus Guajara) y cada hora de los días válidos en las
  dos, `F_abajo − F_arriba` son las entradas netas por los ramales. Es descriptivo: no entra en el modelo. Se
  publican la mediana, el p10-p90, el coeficiente de variación entre días, la estabilidad entre 2025 y 2026 y una
  lectura. El coeficiente no se calcula cuando el neto es casi nulo: entradas y salidas se compensan y no se pueden
  separar.

## 6. Modelo de cola (simulado)

- **Demanda híbrida de 24 h.** Fuera de la ventana de la punta (6-10 h y 13-18 h), la demanda es el caudal
  aforado medio de los días válidos de 2025. Dentro, los mismos vehículos se reparten con una forma de punta
  gaussiana cuyo centro (`t0_punta`) y anchura (`sigma_punta`) se calibran. El día suma exactamente los vehículos
  aforados.
- **Cola puntual** (Vickrey, 1969). Cuando hay cola, la capacidad cae (`caida_capacidad`; Cassidy y Bertini, 1999).
  Las esperas se calculan por cohortes con curvas acumuladas (Newell, 1993).
- **Especificación de la descarga** (`aplicar_especificacion()`, `capacidades()`). Se elige por validación cruzada
  (apartado 8) entre 16 variantes que combinan:
  - **propagación de la cola del tramo siguiente:** `D` limita también la situación actual;
  - **descarga dependiente de la hora:** un factor por hora (≤ 1), la mediana del caudal de las horas con cola plena
    o final de esa hora frente a la de la hora de referencia (la que más horas así tiene), estimado solo en las horas
    con al menos 10 horas con cola y el 10 % de las de la hora de referencia; en las demás horas vale 1 (no se
    extrapola);
  - **mezcla de pesados:** la capacidad en vehículos de cada hora se corrige con su cuota de pesados frente a la de
    la hora de referencia, `(1 + (E − 1) · p_ref) / (1 + (E − 1) · p_h)`, con una equivalencia `E` de 1,5 a 4
    ligeros por pesado (`equivalencia_pesados`, en la tabla de parámetros);
  - **forma de medir la descarga calibrada:** como parámetro (carriles × capacidad × (1 − caída), dentro del
    p10-p90 de los caudales horarios con cola) o medida igual que en el aforo (mediana del caudal de las horas que el
    aforo contaría con cola en el día del modelo, dentro del p25-p75 de las medianas diarias aforadas).

  Elegidas: por la mañana, **propagación de la cola del tramo siguiente + descarga dependiente de la hora + mezcla de pesados; descarga calibrada medida igual que en el aforo**; por la tarde, **descarga constante; descarga calibrada como parámetro**.
- **Alternativas:**
  - tercer carril: capacidad de 3 carriles, limitada por `D`;
  - regulación de accesos: evita una fracción `eficacia_rm` de la caída, con el mismo límite;
  - escalonamiento: desplaza una fracción de la punta 30-90 min, sin perder vehículos;
  - tarificación: reduce la demanda de la punta en un efecto neto observado;
  - regulación + escalonamiento.
- **Demanda inducida.** Cada mejora atrae demanda según una elasticidad respecto al tiempo de viaje: primer año,
  5 años con ajuste parcial y 10 años. Se resuelve un equilibrio entre demora y demanda. La tarificación no la
  lleva, porque su efecto observado ya es neto.
- **Dos cuellos en serie** (`simular_tandem()`, `cola_remanente()`; comprobación, no entra en las demás cifras). El
  cuello de la mañana (A) y el tramo siguiente (B) se simulan minuto a minuto con un almacenamiento finito entre los
  dos, `N = longitud × 3 carriles × 140 veh/km`, con longitudes supuestas de 1, 2 y 4 km (no hay puntos kilométricos
  publicados). B admite lo que deja el tramo siguiente al tronco (`D`) más las entradas netas de los ramales (mediana
  de cada hora). Si el almacenamiento se llena, lo que sale de A y lo que entra por los ramales se reduce en
  proporción a lo que llega: los ramales quedan bloqueados y su cola cuenta en la demora. Se conservan los vehículos
  en cada minuto (llegadas = salidas + cola en A + cola entre A y B + cola en los ramales).

## 7. Monte Carlo

**Parámetros** (`montecarlo_parametros.csv`; por la tarde cambian el centro de la punta, 780-1.080 min, y la
holgura, que es la de La Matanza):

| Parámetro | Distribución | Mínimo | Moda | Máximo | Tipo | Dependencia |
|---|---|---|---|---|---|---|
| `c_carril` | triangular (mínimo, moda, máximo) | 1.850 | 1.950 | 2.100 | literatura + datos | Independiente de los demás |
| `sigma_punta` | triangular (mínimo, moda, máximo) | 20 | 50 | 120 | supuesto | Independiente; la calibración selecciona los valores compatibles con la duración de la cola |
| `caida_capacidad` | triangular (mínimo, moda, máximo) | 0,03 | 0,1 | 0,18 | literatura | Independiente de los demás |
| `holgura_aguas_abajo` | empírica por hora (cuantil común u ~ U(0, 1)) | 0 | 0,121 | 0,327 | datos (estimado) + supuesto | No se usa la triangular: se muestrea un cuantil u ~ U(0, 1) común a todas las horas (día bueno o malo aguas abajo) y la holgura de cada hora es ese cuantil de su distribución estimada; mínimo, moda y máximo de esta tabla son solo descriptivos (p10, mediana y p90 de las horas con cola; un valor negativo se muestra como 0, aunque el modelo usa la holgura negativa cuando la especificación incluye la propagación) |
| `eta_corto` | triangular (mínimo, moda, máximo) | −0,5 | −0,3 | −0,1 | literatura | Independiente de los demás |
| `eta_largo` | triangular (mínimo, moda, máximo) | −1 | −0,7 | −0,3 | literatura | Se toma min(eta_largo, eta_corto): a 10 años la demanda inducida nunca es menor que el primer año |
| `T_libre` | triangular (mínimo, moda, máximo) | 15 | 25 | 35 | supuesto | Independiente de los demás |
| `eficacia_rm` | triangular (mínimo, moda, máximo) | 0,5 | 0,75 | 1 | literatura | Independiente de los demás |
| `desplazamiento_horario` | triangular (mínimo, moda, máximo) | 0,03 | 0,08 | 0,15 | datos + supuesto | Independiente de los demás |
| `reduccion_tarificacion` | triangular (mínimo, moda, máximo) | 0,05 | 0,12 | 0,22 | literatura | Independiente de los demás |
| `persistencia_anual` | triangular (mínimo, moda, máximo) | 0,708 | 0,75 | 0,795 | literatura | Independiente de los demás |
| `t0_punta` | triangular (mínimo, moda, máximo) | 360 | 420 | 540 | datos + supuesto | Independiente; la calibración selecciona los valores compatibles con el inicio y el fin de la cola |
| `equivalencia_pesados` | triangular (mínimo, moda, máximo) | 1,5 | 2,5 | 4 | literatura | Solo si la especificación incluye la mezcla de pesados; se muestrea al final con su propia semilla (la del caso + 50.000) y el generador vuelve a su estado, así que no cambia el resto de la muestra |

`eta_medio` (5 años) no se muestrea: se deriva de `eta_corto`, `eta_largo` y `persistencia_anual`. Los dos
casos usan la misma semilla y el mismo orden de parámetros, así que comparten los números aleatorios: la previa
de cada parámetro común es idéntica en los dos. La equivalencia de pesados se muestrea al final, con su propia semilla, y el generador vuelve a su estado: no cambia el resto de la muestra.

**Semillas** (`montecarlo_semillas.csv`):

| Semilla | Función | Uso |
|---|---|---|
| 2026 | `simular_montecarlo()` | Muestreo de los parámetros de los dos casos (y cuantil de la holgura) |
| 99 | `selector_calibraciones()` | Submuestra uniforme de 3.000 combinaciones con la que se resumen las reglas de la sensibilidad y la regla «sin calibrar» |
| 7 | `simular_montecarlo() del Bus-VAO` | Muestreo del perfil sintético de Padre Anchieta |
| 11 | `grafico_bus_vao()` | Submuestra de 300 combinaciones para la curva del Bus-VAO |
| 5 | `curva_holgura()` | Submuestra de 300 combinaciones para la curva del tercer carril según la holgura |
| 8 | `salidas_por_hora()` | Submuestra de 300 combinaciones para el caudal hora a hora |
| 21 | `evolucion_demanda()` | Submuestra (si N_PREVISION < combinaciones calibradas) |
| 22 | `alternativas_futuro()` | Submuestra (si N_PREVISION < combinaciones calibradas) |
| 23 | `escenarios_adversos()` | Submuestra (si N_PREVISION < combinaciones calibradas) |
| 24 | `curva_trasvase_tp()` | Submuestra (si N_PREVISION < combinaciones calibradas) |
| 31 | `estabilidad_percentiles()` | Bootstrap de las simulaciones calibradas |
| 3 | `did_ull()` | Bootstrap por bloques de semanas |
| 41 | `validacion_diaria() (simulado_por_combinacion())` | Submuestra (si N_PREVISION < combinaciones calibradas) |
| 51 | `sensibilidad_holgura()` | Submuestra de 300 combinaciones calibradas |
| 61 | `validacion_modelo()` | Bootstrap por bloques de días del intervalo del 95 % de la mediana aforada en 2026 |
| 2027 | `replicar_semillas()` | Repetición completa del Monte Carlo con otra semilla (auditoría) |
| 2028 | `replicar_semillas()` | Repetición completa del Monte Carlo con otra semilla (auditoría) |
| 52026 | `anadir_equivalencia_pesados()` | Equivalencia de los pesados (semilla del caso + 50.000: 52.026 en la calibración y en la rejilla de especificaciones; 52.027 y 52.028 en las repeticiones), solo si la especificación la usa |
| 71 | `intervalo_predictivo()` | Submuestra de 400 combinaciones para el intervalo predictivo |
| 81 | `diferencias_emparejadas()` | Bootstrap del error de la diferencia emparejada mediana |
| 91 | `cola_remanente()` | Submuestra de 200 combinaciones calibradas para los cuellos en serie |

**Reglas de aceptación** (`montecarlo_filtros.csv`; calibración por rechazo con los aforos de 2025):

| Regla | Mañana: umbral | Pasan | Se descarta | Tarde: umbral | Pasan | Se descarta |
|---|---|---|---|---|---|---|
| Duración de la cola (horas como el aforo) | 1,5-3,5 h | 6.420 (32,1 %) | 67,9 % | 2,5-6,5 h | 4.753 (47,5 %) | 52,5 % |
| Caudal de descarga | 3.242-3.463 veh/h (medida como en el aforo) | 6.512 (32,6 %) | 67,4 % | 3.061-3.744 veh/h (parámetro) | 9.226 (92,3 %) | 7,7 % |
| Inicio de la cola | 05:30-06:30 | 2.167 (10,8 %) | 89,2 % | 12:30-14:30 | 2.132 (21,3 %) | 78,7 % |
| Fin de la cola | 07:30-09:30 | 4.188 (20,9 %) | 79,1 % | 16:30-19:30 | 3.468 (34,7 %) | 65,3 % |
| La cola se disipa dentro del día | cola final < 0,5 veh | 20.000 (100,0 %) | 0,0 % | cola final < 0,5 veh | 10.000 (100,0 %) | 0,0 % |
| Todas salvo la descarga | — | 1.347 (6,7 %) | 93,3 % | — | 1.381 (13,8 %) | 86,2 % |
| Todas (calibración principal) | — | 378 (1,9 %) | 98,1 % | — | 1.369 (13,7 %) | 86,3 % |

Los umbrales de duración, inicio y fin son el rango intercuartílico de 2025 ± 0,5 h (duración) o ± 30 min (inicio y
fin). El de descarga depende de la especificación: el p10-p90 de los caudales horarios con cola si se calibra como
parámetro, o el p25-p75 de las medianas diarias si se mide como en el aforo. Las horas se cuentan como en el aforo:
una hora cuenta si al menos el 60 % de sus vehículos pasa con cola. Por la mañana se simulan más combinaciones (20.000) que por la tarde (10.000) porque su regla acepta una parte menor.

**Qué se evalúa del todo** (`selector_calibraciones()`). La situación actual se simula para todas las
combinaciones; las alternativas, para las que pasan la regla principal y para una submuestra uniforme de 3.000 de
todas. Las reglas de la sensibilidad se resumen solo con esa submuestra: como es uniforme, la parte de cada regla que
cae en ella es una muestra sin sesgo de la regla.

**Población a la que se refieren los resultados.** Los percentiles describen las combinaciones de parámetros
compatibles con los aforos de 2025, con previas triangulares independientes. No son probabilidades de lo que
pasará en la TF-5. La comparación con y sin filtro lo muestra (`sensibilidad_calibracion_caso1.csv`). Para el
tercer carril de la mañana, el primer año:
- sin calibrar (2.249 combinaciones al azar con cola: alguien espera al menos un minuto): 67 % (36-94 %);
- con la calibración principal: 40 % (22-73 %).

**Sensibilidad a la regla de calibración** (`sensibilidad_calibracion_caso1.csv` y `_caso2.csv`). Las reglas de la
mañana son: aforos horarios 2025 (principal); aforos sin el horario de la cola; aforos: solo duración de la cola; descarga como parámetro del modelo (p10-p90 del caudal horario con cola); descarga: horas de cola plena de 2025 (p25-p75); prensa: espera máxima 10-40 min; prensa: espera máxima 5-20 min; prensa: espera máxima 20-60 min; sin calibrar (muestra aleatoria con cola). Para cada una se dan las
combinaciones que pasan (en total y en la submuestra), el resultado de cada alternativa y la descarga que implica. La regla «descarga: horas de cola plena de 2025 (p25-p75)» solo la cumple 1 de 20.000 combinaciones, así que no tiene resultados.
Hay además una rho de Spearman entre parámetros y resultado (`sensibilidad_tercer_carril.csv`) y un bootstrap de la
estabilidad de los percentiles (`estabilidad_percentiles.csv`).

**Auditoría** (`docs/VALIDACION_Y_CALIDAD.md`, criterio 3):
- **otras semillas** (`replicar_semillas()`; `montecarlo_otras_semillas.csv`): el Monte Carlo completo con las
  semillas 2027 y 2028, misma previa y misma regla;
- **previas alternativas** (`reponderar_previas()`; `montecarlo_previas_alternativas.csv`): las combinaciones
  aceptadas se pesan con la densidad de la previa alternativa dividida por la de la usada (muestreo por importancia;
  mismo soporte), con su tamaño efectivo (`(Σw)² / Σw²`) y percentiles ponderados;
- **correlaciones** (`correlaciones_parametros()`; `montecarlo_correlaciones.csv`): Spearman entre parámetros en
  todas las combinaciones (previa) y en las aceptadas.

## 8. Validación

- **Tres conjuntos de días.** 2025 calibra. Para elegir la especificación de la descarga, los días laborables
  válidos de 2025 se reparten en dos mitades por semanas ISO alternas (A, impares; B, pares): se calibra con una y
  se mide en la otra, y al revés (`pliegue_temporal()`, `rejilla_especificaciones()`). Cada calibración usa solo sus
  días para todo lo que se ajusta: el objetivo, el perfil horario de la demanda, la cuota de pesados, el factor
  horario de la descarga y la capacidad libre del tramo siguiente (con la capacidad de abajo estimada con esos
  días). Enero-septiembre de 2026 (sin agosto) no interviene en la calibración ni en la elección: es la prueba final.
  La línea base de velocidad de madrugada (`base_nocturna()`), con la que se decide si una hora está congestionada, se
  calcula con los días válidos de los 24 meses; calculada solo con 2025, no cambia ninguna hora congestionada de 2025 en las estaciones que usa el modelo
  (`herramientas/comprobaciones/base_nocturna_solo_2025.R`; `docs/comprobacion_base_nocturna_2025.csv`).
- **Regla de elección** (`elegir_especificacion()`), fijada antes de mirar 2026: la referencia es la variante más
  simple; otra es admisible si reduce al menos un 20 % el sesgo absoluto de la descarga del día (media de los
  sesgos absolutos de las dos mitades) y no empeora más de un 10 % el RMSE de ningún indicador; entre las
  admisibles, la de menor RMSE relativo medio, aunque la diferencia sea mínima (por la mañana, la elegida y la misma
  sin mezcla de pesados quedan prácticamente empatadas: `README.md`, apartado 2.3). Las coberturas se informan, pero no
  deciden.
- **Qué se compara.** Las horas de cola, el inicio y el fin se miden igual en el modelo y en el aforo. La descarga
  se compara de dos formas: el parámetro y el caudal que sale del modelo en las horas que el aforo contaría con cola
  (mediana de su día, frente a la mediana de las medianas diarias aforadas). En `validacion_modelo.csv` son dos filas
  del mismo fenómeno (columna `fenomeno`): no son contrastes independientes.
- **Métricas** (`validacion_diaria.csv`, `validacion_diaria_por_hora.csv`, `validacion_cruzada.csv`;
  `metricas_contraste()`, `metricas_prediccion()`):
  - sesgo = mediana del modelo − media observada;
  - error absoluto medio (MAE) y raíz del error cuadrático medio (RMSE); el sesgo y el MAE, también divididos por la
    media observada (salvo en los indicadores que son una hora del día);
  - cobertura de la banda de parámetros p10-p90, con la parte que queda por debajo y por encima;
  - cobertura del intervalo predictivo del 80 %.

  Se calculan por indicador diario y por hora de la punta, para 2025, 2026, cada trimestre y cada día de la
  semana de 2026, en los dos sentidos.
- **Intervalo predictivo del 80 %** (`intervalo_predictivo()`). A los valores simulados de una submuestra de
  combinaciones calibradas se suman residuos de los días de calibración (valor del día − mediana de esos días), que
  recogen la variabilidad de un día a otro y el error de observación; el intervalo es el p10-p90 de esa suma. Su
  cobertura se mide en días no usados para calibrar. Puede ser algo conservador, porque la dispersión de las
  combinaciones y los residuos recogen en parte la misma variabilidad, y no está igual de bien ajustado en todos los
  indicadores: la cobertura de cada uno se publica en `validacion_diaria.csv`.
- **Intervalo de la mediana observada** de 2026: bootstrap por bloques de días (1.000 réplicas), porque las horas de
  un mismo día no son independientes.
- **Diagnóstico de la descarga** (`diagnostico_descarga.csv`). Compara aforo y modelo por hora del día, por posición
  en la cola (inicio, plena, final o aislada), según haya cola en la estación de abajo y con la cuota de pesados de
  cada hora. También compara el parámetro de descarga en la previa, en las combinaciones que cumplen el horario y en
  las aceptadas.
- **La tarde en 2026.** El caudal con cola bajó de 3.561 a 3.424 veh/h (IC 95 % de 2026:
  3.398-3.453). No se ha identificado la causa.

## 9. Demoras (simulado)

Definiciones (filas de la mañana; las de la tarde son iguales salvo lo que se indica debajo):

| Indicador | Unidad | Denominador | Horizonte | Método | Contraste independiente |
|---|---|---|---|---|---|
| Demora total | vehículos·hora por día laborable | ninguno (suma de todos los vehículos del día) | un día laborable completo (24 h) | Área entre las curvas acumuladas de llegadas y salidas (cola puntual FIFO, Newell) | Sin dato independiente: no hay tiempos de recorrido publicados |
| Espera media en la hora punta | minutos por vehículo | vehículos que llegan en los 60 minutos de más llegadas | hora punta del día | Media de la espera de cada cohorte de llegada, ponderada por sus vehículos | Sin dato independiente |
| Espera máxima | minutos | el vehículo que más espera | un día laborable | Máximo de la espera por cohortes | Prensa: franja supuesta de 10-40 min, que cubre los 15-20 min que estima Atlántico Hoy (24-11-2025) y los 40 min de un día con incidente (COPE, 20-10-2021); el 86 % de las combinaciones calibradas cae en esa franja (contraste débil: estimaciones periodísticas, sin fecha ni tramo exactos) |
| Duración de la cola | horas por día | minutos con más de medio vehículo en cola / 60 | un día laborable | Cola puntual | Indirecto: horas con >= 60 % de vehículos a menos de 80 km/h en el aforo (ver horas como el aforo) |
| Horas de cola como las cuenta el aforo | horas enteras por día | horas del día | un día laborable | Horas en que >= 60 % de los vehículos que pasan lo hacen con cola | Directo con los aforos (velocidad): calibrado con 2025 y contrastado día a día con 2026 |
| Cola máxima | vehículos | ninguno | un día laborable | Máximo de vehículos acumulados en la cola puntual | Sin dato independiente: la cola puntual no tiene longitud; no hay medidas de longitud de cola |
| Longitud equivalente de la cola máxima | km | densidad de atasco supuesta: 140 veh/km por carril, en los 2 carriles del tramo donde se forma la cola | un día laborable | Cola máxima / (densidad de atasco x carriles del tramo de la cola). Solo orientativo: la cola puntual no ocupa espacio en el modelo | Sin dato independiente: no hay medidas de longitud de cola, y la estación de aguas arriba (La Matanza) no tiene velocidad utilizable |

Todos se calculan en la situación actual simulada y con cada alternativa (`metricas_por_alternativa.csv`, con
p10-p90). Ninguno es un tiempo observado. La longitud equivalente se calcula con los carriles del tramo donde se
forma la cola: 2 por la mañana (La Matanza) y 3 por la tarde (Bomberos La Laguna, antes del paso de 3 a 2). Por la
tarde, el contraste de la longitud de cola cambia de estación de aguas arriba: Padre Anchieta, que tampoco tiene
velocidad utilizable.

## 10. Previsiones a 1, 5 y 10 años, 2030 y 2035 (simulado: escenarios condicionados)

- **Ninguna previsión está verificada.** Son escenarios condicionados a sus supuestos, separados en componentes
  (`previsiones_condicionadas.csv`):
  1. crecimiento exógeno de la demanda sin actuar;
  2. cambio de red (tercer carril en servicio hacia 2029-2030) y gestión, en 2030;
  3. trasvase al transporte público;
  4. demanda inducida a 1, 5 y 10 años de cada actuación.

  Cada fila lleva su p10-p90 y su condición de validez.
- **Escenarios de crecimiento** (`datos/escenarios_demanda.csv`):
  - bajo, 0 % anual;
  - central, 0,5 %: el ritmo de las estaciones con margen entre 2019 y 2025;
  - alto, 1 %: el de la población entre 2021 y 2025.

  Se aplican sin adaptación (toda la demanda nueva intenta pasar en la punta) y con adaptación (parte se desplaza).
  Con la propagación en la especificación, la capacidad libre del tramo siguiente se recalcula con las entradas de
  los ramales del año (`matriz_holgura_crecimiento()`).
- **Horizontes.** «1, 5 y 10 años» son años después de poner en marcha cada actuación, con la demanda de 2025 más la
  inducida. 2030 y 2035 son años de calendario con crecimiento de fondo.
- **Retraso de obra** (`retraso_obra()`; `retraso_obra_tercer_carril.csv`): el tercer carril entrando en servicio en
  2029, 2030, 2031 o 2032, con la demanda de ese año y crecimiento central o alto.
- **Supuesto de la descarga fuera de las horas con datos** (`sensibilidad_prevision_descarga.csv`). Con la descarga dependiente de la hora, el factor solo se aplica en las horas con datos de 2025; la sensibilidad mantiene el de la última hora con datos el resto del día. Pesa en las previsiones con crecimiento, porque la cola llega a horas que en 2025 casi nunca tenía.
- **Robustez por actuación.** `confianza_alternativas.csv` combina cuatro criterios: evidencia local, mecanismo,
  conducta y robustez, esta última medida como el peor escenario adverso frente a la referencia.
  `fichas_alternativas.csv` reúne para cada alternativa el tramo, el horario, el horizonte, el indicador, el
  supuesto clave, la mediana y el rango en cada horizonte, la confianza y la limitación principal.
- **Condiciones de validez.** La misma red salvo el tercer carril contratado, el mismo reparto horario, elasticidades
  y eficacias de la literatura y un tramo siguiente como en 2025. Con un 1 % anual hasta 2035, el modelo trabaja en
  un régimen no observado.

## 11. Comparación de alternativas

- **Diferencias emparejadas** (`diferencias_emparejadas()`; `diferencias_emparejadas.csv`, g21). Cada combinación
  calibrada se usa para todas las alternativas, así que la diferencia entre dos se mide combinación a combinación.
  Para cada pareja y horizonte: diferencia de medianas, mediana de la diferencia, p10 y p90, media, error de
  muestreo de la mediana (bootstrap de 300 réplicas), diferencia relativa, parte de las combinaciones en que gana
  cada una y parte en que difieren menos del umbral.
- **Lectura**, en este orden: sin diferencia material si la diferencia mediana es menor de 2 puntos o si en la mitad
  de las combinaciones difieren menos de 2 puntos (umbral fijado de antemano); sin diferencia distinguible si es
  menor que dos veces su error de muestreo; una reduce más si lo hace en al menos el 90 % de las combinaciones (la
  banda p10-p90 de la diferencia queda a un lado del 0); si no, depende de los parámetros. «Sin diferencia material» describe
  la diferencia típica: si la banda es ancha, cuál reduce más puede cambiar según los parámetros, y la tabla da la banda
  junto a la lectura.
- **Con cada regla de calibración** (`diferencias_emparejadas_por_regla.csv`), la pareja tercer carril frente a
  regulación + escalonamiento.
- **Escenarios adversos.** En cada supuesto, las alternativas a menos de 2 puntos de la mejor se marcan como
  empatadas (`empate_con_la_primera`).
- **Coste, plazo y riesgos** (`coste_plazo_riesgo.csv`): dato documental y valoración cualitativa, aparte del efecto
  simulado. No se combinan en un índice.

## 12. Actuaciones ya ejecutadas: ULL y pasarela (asociación no causal)

- **Horarios escalonados de la ULL.** Antes y después en los meses lectivos (octubre-noviembre y febrero-mayo),
  2024-25 frente a 2025-26, con IC por bootstrap de semanas. Se comprueba además que el reparto entre carriles no
  cambie más de 4 puntos (aforador alterado). Las diferencias en diferencias, con julio o con junio y julio como
  control, no son válidas: esos meses de 2026 son posteriores a la pasarela, y las tendencias paralelas no se
  pueden contrastar.
- **Pasarela del Padre Anchieta.** Diferencia interanual mes a mes (junio, julio y septiembre de 2026 frente a 2025),
  con test de Welch. Son tres meses, dos de verano. Como comparación de control, en noviembre de 2025, antes de la
  pasarela, la cola de Bomberos La Laguna hacia Santa Cruz bajó tanto como después de abrirla
  (1,50 → 0,80 h/día; IC 95 % de la diferencia: −1,12 a −0,28): bajadas así aparecen también sin pasarela.
- **No se controlan** obras ni incidencias: el registro público del Cabildo no se ha incorporado
  (`matriz_lagunas.csv`, D09). La estacionalidad y el calendario lectivo solo se controlan comparando los mismos
  meses. Por eso las dos se rotulan como asociación no causal, y las actuaciones futuras se presentan como
  escenarios, no como efectos comprobados.

## 13. Pruebas y reproducibilidad

- **Entorno.** R 4.3.3 y las versiones de `renv.lock` (con los paquetes del dispositivo PNG de los gráficos) y
  `entorno/versiones_paquetes.csv`. `main.R` fija la zona horaria (`Atlantic/Canary`), compara las versiones al
  empezar (`entorno_versiones.csv`) y guarda las opciones (`configuracion_ejecucion.csv`: simulaciones, semillas de la
  auditoría, zona horaria e inicio) y la sesión (`registro_sesion.txt`).
- **Avisos.** Todo el análisis corre dentro de un `withCallingHandlers()` que guarda cada aviso, con su hora, en
  `registro_avisos.txt`; funciona igual con `Rscript` que con `source()`.
- **Entradas sin cambios.** `main.R` calcula la huella de sus entradas (`main.R`, `R/`, `tests/`, `entorno/`,
  `renv.lock` y `datos/`) al empezar y al acabar; si alguna cambia durante la ejecución, lo registra como aviso.
  Las referencias de no regresión (`tests/referencia/`) no cuentan como entrada: salen de la propia ejecución.
- **Sin edición manual.** Todas las tablas, gráficos y ficheros del panel los genera `main.R` desde `datos/`; las
  salidas se borran al empezar.
- **Comprobaciones del modelo en cada ejecución** (`comprobaciones_modelo()`; `comprobaciones_modelo.csv`): área bajo
  la cola igual a la suma de esperas, esperas por cohortes frente a la aproximación, conservación (también al
  escalonar y en los cuellos en serie), límite del tramo siguiente con holgura nula y negativa, límites físicos y
  cola disipada con el perfil de cada combinación calibrada, y umbral del Bus-VAO.
- **Manifiestos.** `manifiesto_ejecucion.csv` tiene el SHA-256 de `main.R`, `R/`, `tests/` (sin las referencias de no
  regresión, que se copian de la propia ejecución), `entorno/`, `renv.lock`, `datos/` y `salidas/` al acabar la
  ejecución; `manifiesto_entrega.csv`, el de todos los ficheros entregados.
- **Pruebas** (`tests/testthat`; `Rscript tests/ejecutar_pruebas.R`):
  - invariantes físicos y casos extremos;
  - holgura, balance, restricción aguas abajo y cuellos en serie;
  - especificación de la descarga, validación cruzada e intervalo predictivo;
  - métricas, diferencias emparejadas y reponderación de previas;
  - procedencia, sumas de control y contraste con el catálogo nacional;
  - series con banderas, días atípicos, geometría, metadatos de los gráficos y versiones;
  - semillas (todas las del código están en la tabla de semillas) y rango de los escenarios adversos de las fichas;
  - no regresión: las tablas clave de la ejecución entregada están en `tests/referencia/`, con la configuración de
    esa ejecución, y una ejecución completa nueva con la misma configuración tiene que reproducirlas con una
    tolerancia relativa de 1e-8.
- **Comparación de ejecuciones** (`tests/comparar_ejecuciones.R`). Compara fichero a fichero dos carpetas de salidas
  e informa de si cada uno es igual byte a byte, igual en valores, cambia (con la mayor diferencia numérica y
  relativa), es nuevo o se ha retirado, y si está dentro de la tolerancia (por defecto, diferencia relativa ≤ 1e-8,
  mismas filas, columnas y textos). Los ficheros propios de cada ejecución (configuración y manifiesto) no se
  comparan. Se usó para comparar dos ejecuciones completas en copias limpias
  (`docs/reproducibilidad_dos_ejecuciones.csv`).
- **Reimplementación en Python** (`docs/verificacion_independiente/`). Recalcula las cifras observadas con otro
  lenguaje. Usa los mismos datos y las definiciones del código R, así que detecta errores de programación, pero no
  es una verificación externa.
