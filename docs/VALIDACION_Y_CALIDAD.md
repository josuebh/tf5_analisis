# Validación y calidad del proyecto TF-5

Este documento reúne los diez criterios de calidad del estudio, cómo se comprueba cada uno y con qué resultado. Las
cifras salen de la ejecución entregada (`salidas/tablas`) y se rellenan con `herramientas/documentos/rellenar.py`,
igual que en el `README.md`. Lo que no se ha podido resolver con datos públicos se dice en cada criterio y está
en `datos/matriz_lagunas.csv`.

## Resumen

| # | Criterio | Resultado | Evidencia principal |
|---|---|---|---|
| 1 | Calibración separada de la validación, con intervalos predictivos | 2025 calibra; una mitad de 2025 valida la otra para elegir la especificación; enero-septiembre de 2026 es la prueba final. Sesgo, MAE, RMSE y cobertura por hora, día y sentido; banda de parámetros e intervalo predictivo del 80 %, con nombres distintos | `validacion_cruzada.csv`, `eleccion_especificacion.csv`, `validacion_diaria.csv`, `validacion_diaria_por_hora.csv`, g20 |
| 2 | Descarga de la mañana | Se adopta la especificación «propagación de la cola del tramo siguiente + descarga dependiente de la hora + mezcla de pesados; descarga calibrada medida igual que en el aforo», que mejora el sesgo de la descarga fuera de muestra sin empeorar más de un 10 % ningún otro indicador; en 2026 la cobertura del intervalo predictivo se acerca al 80 % en unos indicadores y se aleja algo en otros; la descarga de las horas de cola plena sigue sobrestimada (apartado 2); las bandas no se han ensanchado | `eleccion_especificacion.csv`, `diagnostico_descarga.csv`, `validacion_modelo.csv` |
| 3 | Monte Carlo auditado | Previas, dependencias, reglas y tasas por filtro; otras dos semillas; previas alternativas; correlaciones; estabilidad de los percentiles | `montecarlo_parametros.csv`, `montecarlo_filtros.csv`, `montecarlo_otras_semillas.csv`, `montecarlo_previas_alternativas.csv`, `montecarlo_correlaciones.csv` |
| 4 | Geometría y ramales con procedencia | 11 cálculos que dependen del número de carriles, todos con fuente o supuesto explícito; 6 estación-sentidos pendientes de confirmación, con escenario alternativo | `uso_de_la_geometria.csv`, `geometria_y_capacidad.csv`, `datos/geometria_tramos.csv` |
| 5 | Restricción aguas abajo | El tercer carril y la regulación no añaden caudal si el tramo siguiente limita; cuellos en serie con almacenamiento finito y bloqueo de ramales; conservación en cada minuto | `comprobaciones_modelo.csv`, `cola_remanente_aguas_abajo.csv`, `escenarios_adversos.csv` |
| 6 | Sin ganador por diferencias mínimas | Diferencias emparejadas con su banda y su error; umbral de 2 puntos fijado de antemano; coste, plazo y riesgos aparte | `diferencias_emparejadas.csv`, `diferencias_emparejadas_por_regla.csv`, `coste_plazo_riesgo.csv`, g21 |
| 7 | Días atípicos y datos faltantes | Cada día con su estado (usado o excluido) y su motivo; marcas de días atípicos; cobertura e imputación por estación, mes y hora; sensibilidad sin atípicos y con dos métodos de imputación | `dias_atipicos.csv`, `dias_atipicos_resumen.csv`, `sensibilidad_sin_dias_atipicos.csv`, `sensibilidad_depuracion.csv`, `cobertura_e_imputacion_por_estacion_mes_hora.csv` |
| 8 | Fuentes originales | Procedencia por recurso (URL, organismo, fechas, licencia, identificador, SHA-256); correspondencia de 31 campos; 13 de 13 recursos contrastados con el catálogo nacional; datos no publicados con su estado | `procedencia_datos.csv`, `correspondencia_de_campos.csv`, `contraste_publicacion_original.csv`, `datos/matriz_lagunas.csv` |
| 9 | Hechos separados de escenarios | Cada resultado con su categoría (observado, estimado, supuesto, simulado o asociación no causal) y cada gráfico con su horizonte, hipótesis e incertidumbre | `datos/limitaciones_por_resultado.csv`, `graficos_metadatos.csv`, `previsiones_condicionadas.csv` |
| 10 | Reproducibilidad | Versiones fijadas, semillas, zona horaria, ejecución completa sin intervención, 0 avisos registrados, pruebas y dos ejecuciones completas iguales dentro de la tolerancia | `renv.lock`, `salidas/registro_*.txt`, `salidas/resultado_pruebas.csv`, `docs/reproducibilidad_dos_ejecuciones.csv` |

## Nota de control: la tabla de validación resumida

`validacion_modelo.csv` tiene **10 filas de indicadores, 5 por sentido**: horas de cola, inicio y fin de
la cola, y dos filas de la descarga con cola. Esas dos miden **el mismo fenómeno** de dos formas (columna
`fenomeno`): el parámetro de descarga del modelo y el caudal que sale del modelo medido igual que en el aforo
(mediana de las medianas de cada día). No son dos contrastes independientes, así que se cuentan como un solo
fenómeno. En 2026 queda fuera de la banda de parámetros una sola fila (mañana, parámetro de descarga); la otra fila del mismo fenómeno queda dentro.
La banda de parámetros describe un día típico, no la variabilidad entre días: para juzgar días concretos está el
intervalo predictivo (criterio 1).

## 1. Calibración separada de la validación

**Criterio.** Días o periodos no usados para calibrar; MAE, RMSE, sesgo y cobertura por hora, día y sentido;
intervalos predictivos que incluyan la variabilidad diaria y el error de observación, bien rotulados.

**Cómo se hace** (`R/12_validacion_predictiva.R`):
- **Tres conjuntos.** Los días laborables válidos de 2025 se reparten en dos mitades por semanas ISO alternas (A,
  impares; B, pares). Para elegir la especificación de la descarga, se calibra con una mitad y se mide el error en
  la otra, y al revés: validación cruzada. Cada calibración usa solo sus días para todo lo que se ajusta: el
  objetivo de calibración, el perfil horario de la demanda, la cuota de pesados, el factor horario de la descarga y
  la capacidad libre del tramo siguiente. Enero-septiembre de 2026 (sin agosto) no interviene en la calibración ni en
  la elección: es la prueba final. La línea base de velocidad de madrugada, con la que se decide si una hora está
  congestionada, se calcula con los 24 meses; calculada solo con 2025, no cambia ninguna hora congestionada de 2025 en las estaciones que usa el modelo
  (`docs/comprobacion_base_nocturna_2025.csv`).
- **Dos bandas con nombres distintos.** La *banda de parámetros p10-p90* es la dispersión de las combinaciones
  calibradas para un día típico: no es un intervalo predictivo ni una probabilidad. El *intervalo predictivo del
  80 %* le suma la variabilidad de un día a otro y el error de observación, con los residuos de los días de
  calibración (valor del día menos la mediana de esos días). Su cobertura se mide en días no usados.
- **Métricas** por indicador diario (horas de cola, inicio, fin y descarga), por hora de la punta, por día de la
  semana, por trimestre y por sentido (cada caso es un sentido): sesgo (mediana del modelo − media aforada), error absoluto medio
  (MAE), raíz del error cuadrático medio (RMSE) y cobertura de las dos bandas.

**Resultado: prueba final en 2026** (`validacion_diaria.csv`; especificación elegida, calibrada con todo 2025 en el Monte Carlo
principal: 20.000 combinaciones, 378 aceptadas):

| Indicador | Sentido | Sesgo | MAE | RMSE | Dentro de la banda de parámetros | Dentro del intervalo predictivo del 80 % |
|---|---|---|---|---|---|---|
| Horas de cola al día | Mañana, hacia Santa Cruz | +0,36 h | 0,93 | 1,31 | 37 % | 79 % |
| Inicio de la cola | Mañana, hacia Santa Cruz | −0,10 h | 0,10 | 0,65 | 96 % | 96 % |
| Fin de la cola | Mañana, hacia Santa Cruz | +0,05 h | 0,81 | 1,17 | 39 % | 90 % |
| Descarga del día medida igual en el modelo y en el aforo | Mañana, hacia Santa Cruz | +84 veh/h | 142 | 188 | 31 % | 88 % |
| Descarga en las horas de cola plena | Mañana, hacia Santa Cruz | +260 veh/h | 266 | 363 | 28 % | 82 % |
| Horas de cola al día | Tarde, hacia el Norte | −0,58 h | 1,30 | 1,88 | 68 % | 90 % |
| Inicio de la cola | Tarde, hacia el Norte | +0,73 h | 0,73 | 0,93 | 94 % | 94 % |
| Fin de la cola | Tarde, hacia el Norte | −0,34 h | 1,38 | 1,68 | 62 % | 99 % |
| Descarga del día medida igual en el modelo y en el aforo | Tarde, hacia el Norte | +87 veh/h | 162 | 233 | 51 % | 80 % |
| Descarga en las horas de cola plena | Tarde, hacia el Norte | +38 veh/h | 197 | 268 | 38 % | 64 % |

La cobertura de la banda de parámetros es baja porque no está hecha para días concretos. La del intervalo
predictivo es la que debe acercarse al 80 %: en los indicadores diarios de `validacion_diaria.csv` va del
64 % al 99 %; por debajo del 80 % quedan horas de cola al día (mañana, 79 %); descarga del día frente al parámetro del modelo (mañana, 76 %); descarga en las horas de cola plena (tarde, 64 %). Hora a hora, cubre el
75 % de las horas por la mañana y el 71 % por la tarde. Por debajo del 80 %, el intervalo es demasiado
estrecho para ese indicador; por encima, conservador (sobre todo en el inicio y el fin, que el aforo mide en horas
enteras). En conjunto puede pecar de ancho, porque la dispersión de las combinaciones y los residuos de los días
recogen en parte la misma variabilidad.

**Por hora** (`validacion_diaria_por_hora.csv`; 2026, caudal de cada hora de la punta):

| Hora | Sentido | Sesgo (veh/h) | RMSE (veh/h) | Dentro del intervalo predictivo |
|---|---|---|---|---|
| 06 h | Mañana | +16 | 218 | 79 % |
| 07 h | Mañana | +173 | 336 | 87 % |
| 08 h | Mañana | +85 | 308 | 75 % |
| 09 h | Mañana | −202 | 282 | 58 % |
| 13 h | Tarde | +179 | 327 | 86 % |
| 14 h | Tarde | +86 | 346 | 47 % |
| 15 h | Tarde | −20 | 281 | 60 % |
| 16 h | Tarde | +128 | 264 | 78 % |
| 17 h | Tarde | +231 | 342 | 82 % |

**Por día de la semana** (2026, horas de cola al día; sesgo y cobertura del intervalo predictivo):
mañana, lunes +0,55 h y 70 %; martes +0,19 h y 84 %; miércoles +0,15 h y 79 %; jueves +0,03 h y 88 %; viernes +0,91 h y 72 %;
tarde, lunes +0,64 h y 91 %; martes −0,69 h y 94 %; miércoles −0,71 h y 89 %; jueves −0,91 h y 91 %; viernes −1,25 h y 84 %.
Por trimestre, en `validacion_diaria.csv` (periodos 2025-T1 a 2026-T3).

**Límites.** La validación compara lo que miden los aforos (colas por horas enteras y caudales horarios en un
punto). No hay tiempos de recorrido ni longitudes de cola medidas, así que la demora simulada no se valida
directamente (matriz de lagunas, D02 y D13).

## 2. Descarga de la mañana

**Criterio.** Comprobar que el detector y el modelo miden lo mismo; probar una descarga que dependa de la hora,
los incidentes, la mezcla de vehículos y la propagación de la cola; no ensanchar las bandas; aceptar el cambio solo
si mejoran el sesgo y la cobertura fuera de muestra sin empeorar otros periodos.

**Cómo se hace.**
- **Misma medida.** La descarga del aforo es la mediana del caudal de las horas que el aforo cuenta con cola (al
  menos el 60 % de los vehículos a menos de 80 km/h), en Ermita Cruz Chica. El modelo se mide igual: caudal que sale
  en las horas en que al menos el 60 % de los vehículos ha pasado por la cola, y mediana de esas horas en su día. El
  parámetro del modelo (carriles × capacidad × (1 − caída)) es otra cosa: la descarga a pleno rendimiento en la hora
  de referencia.
- **Variantes probadas** (`rejilla_especificaciones()`; 2 × 2 × 2 × 2 = 16): con o sin propagación de la cola del
  tramo siguiente (cuando no tiene capacidad libre, frena también la descarga actual); descarga constante o
  dependiente de la hora (factor medido en 2025 en las horas con cola plena o final, solo en las horas con datos
  suficientes); con o sin mezcla de pesados (capacidad en vehículos según la cuota de pesados de cada hora, con una
  equivalencia de 1,5 a 4 ligeros por pesado); y la descarga calibrada como parámetro o medida igual que en el aforo.
  Los incidentes no tienen un registro incorporado (criterio 7): se tratan como días atípicos y en el escenario
  adverso de incidente.
- **Regla fijada antes de mirar 2026.** La referencia es la variante más simple. Otra es admisible si reduce al
  menos un 20 % el sesgo absoluto de la descarga del día en la validación cruzada (media de los sesgos absolutos de
  las dos mitades, para que un sesgo positivo en una y negativo en la otra no se compensen) y no empeora más de un
  10 % el RMSE de ningún indicador. Entre las admisibles se elige la de menor RMSE relativo medio. La cobertura no
  entra en la regla: se informa aparte, más abajo, para ver si también mejora.

**Resultado** (`eleccion_especificacion.csv`, `validacion_cruzada.csv`).
- **Mañana:** 6 de las 15 variantes distintas de la referencia son admisibles. Se elige: **propagación de la cola del tramo siguiente + descarga dependiente de la hora + mezcla de pesados; descarga calibrada medida igual que en el aforo**. Sesgo absoluto de la descarga del día en la validación cruzada: 93 veh/h, frente a 149 con la referencia (37 % menos); el indicador que más empeora, caudal de las 06 h, lo hace un 0,7 % en RMSE.
- **Tarde:** 0 de las 15 variantes distintas de la referencia son admisibles. Se mantiene la referencia (descarga constante; descarga calibrada como parámetro): ninguna variante reduce el sesgo de la descarga un 20 % sin empeorar otro indicador más de un 10 %.

**Prueba final en 2026** (calibrando con todo 2025; ni 2026 ni la prueba intervinieron en la elección). Las cifras salen
de la rejilla de especificaciones (10.000 combinaciones por forma; 168 aceptadas con la elegida), no del Monte Carlo
principal del criterio 1, así que difieren un poco de las de su tabla:

| Indicador (mañana) | Referencia: sesgo; RMSE; intervalo predictivo | Elegida: sesgo; RMSE; intervalo predictivo |
|---|---|---|
| Horas de cola al día | +0,36; 1,31; 88 % | +0,36; 1,31; 79 % |
| Inicio de la cola | −0,10; 0,65; 96 % | −0,10; 0,65; 96 % |
| Fin de la cola | +0,05; 1,17; 92 % | +0,05; 1,17; 90 % |
| Descarga del día (medida igual en el modelo y en el aforo) | +137; 217; 86 % | +88; 190; 88 % |
| Caudal de las 06 h | 0; 217; 78 % | +5; 217; 77 % |
| Caudal de las 07 h | +229; 367; 87 % | +179; 339; 87 % |
| Caudal de las 08 h | +172; 342; 84 % | +83; 308; 75 % |
| Caudal de las 09 h | −349; 401; 25 % | −210; 288; 58 % |

**¿Mejora también la cobertura?** La cobertura del intervalo predictivo del 80 % de esa descarga se acerca más al 80 % en la validación cruzada (83 % y 85 % en las dos mitades con la elegida, frente a 78 % y 90 % con la referencia); en 2026 es del 88 %, frente al 86 % con la referencia (algo más lejos del 80 %). Con la elegida, la banda de parámetros cubre menos días en 2026 (29 % frente a 55 %): no es un fallo, porque la banda describe un día típico y no la variabilidad entre días. De los 8 indicadores de la tabla, con la elegida la cobertura del intervalo predictivo en 2026 se acerca al 80 % en 3, se aleja en 2 (como mucho 2,6 puntos) y queda igual, a medio punto o menos, en 3.

En la tabla resumida (`validacion_modelo.csv`), la descarga de la mañana medida igual que el aforo da en 2026
3.371,5 veh/h en el aforo y 3.419 en el modelo (+48 veh/h,
+1,4 %; banda de parámetros 3.317-3.457, dentro). El parámetro de
descarga (3.497 veh/h de mediana) no se mide igual que el aforo con la especificación elegida: es la descarga de la hora de referencia, antes del factor horario y de los pesados; por eso su
diferencia con la mediana de todas las horas con cola (+158 veh/h) no es un error de predicción.

**La forma de la descarga dentro de la cola.** La especificación elegida cuadra la mediana del día, que es lo que se
calibra, pero no su forma: con la cola plena el modelo da 3.427 veh/h frente a 3.243 en el aforo de
2025, y al final de la cola, 3.110 frente a 3.218 (`diagnostico_descarga.csv`). En las horas de cola plena el sesgo es de
+215 veh/h en 2025 y de +260 en 2026 (`validacion_diaria.csv`). La regla de calibración «descarga: horas de cola plena de 2025 (p25-p75)» solo la cumple 1 de 20.000 combinaciones: el modelo no reproduce a la vez la duración y el horario de la cola y ese caudal.

**Empate en la mezcla de pesados.** La misma forma sin la mezcla de pesados tiene casi el mismo RMSE relativo medio (0,9279 frente a 0,9277) y un sesgo absoluto de la descarga menor (81 frente a 93 veh/h). La regla, fijada de antemano, elige la de menor RMSE: la mezcla de pesados entra por un empate, no porque los datos la exijan.

**Otros periodos.** La regla de la elección y la tabla de 2026 comparan la referencia y la elegida hora a hora en la
punta; por trimestre y por día de la semana solo se publica la elegida (`validacion_diaria.csv`).

**Límites.** El factor horario solo se estima en las horas con datos suficientes de 2025; fuera de ellas se
supone la descarga de referencia, y la sensibilidad de las previsiones a ese supuesto se publica (criterio 9).

## 3. Monte Carlo auditado

**Criterio.** Documentar previas, correlaciones, reglas de aceptación y tasas por filtro; repetir con otras
semillas y otras previas justificadas; comparar con calibraciones alternativas y medir la estabilidad de los
percentiles.

**Resultado.**
- **Tasas por filtro** (`montecarlo_filtros.csv`; sobre 20.000 simulaciones por la mañana y 10.000 por la tarde):

  | Regla | Mañana: umbral | Pasan | Tarde: umbral | Pasan |
  |---|---|---|---|---|
  | Duración de la cola (horas como el aforo) | 1,5-3,5 h | 6.420 (32,1 %) | 2,5-6,5 h | 4.753 (47,5 %) |
  | Caudal de descarga | 3.242-3.463 veh/h (medida como en el aforo) | 6.512 (32,6 %) | 3.061-3.744 veh/h (parámetro) | 9.226 (92,3 %) |
  | Inicio de la cola | 05:30-06:30 | 2.167 (10,8 %) | 12:30-14:30 | 2.132 (21,3 %) |
  | Fin de la cola | 07:30-09:30 | 4.188 (20,9 %) | 16:30-19:30 | 3.468 (34,7 %) |
  | La cola se disipa dentro del día | cola final < 0,5 veh | 20.000 (100,0 %) | cola final < 0,5 veh | 10.000 (100,0 %) |
  | Todas salvo la descarga | — | 1.347 (6,7 %) | — | 1.381 (13,8 %) |
  | Todas (calibración principal) | — | 378 (1,9 %) | — | 1.369 (13,7 %) |

  Que se acepte una parte pequeña no es un error: la regla exige a la vez la duración, el inicio, el fin y la
  descarga medidos en 2025. Los resultados describen esa población de combinaciones, no cualquier combinación
  verosímil.
- **Previas y dependencias** (`montecarlo_parametros.csv`): triangulares con su fuente; la elasticidad a 10 años
  nunca es menor que la del primer año; la capacidad libre del tramo siguiente se muestrea con un cuantil común a
  todas las horas; la equivalencia de los pesados se muestrea con su propia semilla, sin cambiar el resto de la muestra.
- **Otras semillas** (`montecarlo_otras_semillas.csv`; misma previa y misma regla, otras combinaciones):

  | Semilla | Mañana: aceptadas; tercer carril, 1er año; regulación + escalonamiento | Tarde: aceptadas; tercer carril hipotético; regulación + escalonamiento |
  |---|---|---|
  | 2026 | 378; 40,2 %; 48,5 % | 1.369; 71,8 %; 62,1 % |
  | 2027 | 385; 41,3 %; 48,7 % | 1.384; 71,0 %; 60,8 % |
  | 2028 | 399; 43,0 %; 51,0 % | 1.345; 72,2 %; 60,9 % |

  Las medianas cambian como mucho 2,8 puntos entre semillas; el error de muestreo de una mediana va de
  0,1 a 2,0 puntos (`estabilidad_percentiles.csv`).
- **Previas alternativas** (`montecarlo_previas_alternativas.csv`; reponderación de las combinaciones aceptadas, con
  su tamaño efectivo):

  | Previa | Mañana: tamaño efectivo; tercer carril; regulación + escalonamiento | Tarde: ídem |
  |---|---|---|
  | Caída de capacidad más pequeña (moda en el mínimo) | 271 de 378; 39,1 %; 45,3 % | 659 de 1.369; 71,0 %; 57,0 % |
  | Más demanda inducida (moda de las elasticidades en su extremo) | 61 de 378; 36,0 %; 43,7 % | 117 de 1.369; 74,2 %; 60,8 % |
  | Pesados con más peso (moda de la equivalencia en 3,5) | 243 de 378; 40,4 %; 48,9 % | no aplica |
  | Regulación menos eficaz (moda de la eficacia en el mínimo) | 158 de 378; 40,3 %; 45,3 % | 382 de 1.369; 70,0 %; 57,8 % |
  | Uniformes en el mismo rango | 36 de 378; 39,8 %; 40,5 % | 24 de 1.369; 57,7 %; 52,0 % |

  Un tamaño efectivo pequeño indica que la previa alternativa se aleja de la usada y que su resultado es poco
  preciso. Con las previas cuyo tamaño efectivo es al menos el 10 % de las aceptadas, las medianas del tercer carril
  y de la regulación + escalonamiento cambian como mucho 5,1 puntos frente a la previa usada, y hasta 14,1 con las demás.
- **Correlaciones que crea la calibración** (`montecarlo_correlaciones.csv`; Spearman, previa frente a aceptadas):
  por la mañana, c_carril-caida_capacidad +0,69; sigma_punta-t0_punta −0,51; c_carril-holgura_aguas_abajo −0,34; por la tarde,
  c_carril-caida_capacidad +0,53; sigma_punta-t0_punta −0,32; c_carril-sigma_punta −0,29. En la previa son casi nulas: la calibración
  empareja parámetros que se compensan (por ejemplo, más capacidad con más caída).
- **Calibraciones alternativas** (`sensibilidad_calibracion_caso1.csv` y `_caso2.csv`; 7 reglas con al menos 20 combinaciones, más una muestra sin calibrar; «descarga: horas de cola plena de 2025 (p25-p75)» solo la cumple 1 de 20.000 combinaciones y no tiene resultados). Las reglas
  distintas de la principal se resumen con una submuestra uniforme de las simulaciones, para que las combinaciones
  de la regla principal no queden sobrerrepresentadas. Tercer carril de la mañana, primer año: del
  40 % al 68 % según la regla (calibración principal: 40 %).

## 4. Geometría y ramales

**Criterio.** Catalogar para cada tramo el sentido, la fecha, los carriles continuos y auxiliares, las entradas y
salidas, la fuente y la vigencia; ninguna capacidad ni balance sin procedencia o supuesto explícito.

**Resultado.**
- `datos/geometria_tramos.csv` y `geometria_y_capacidad.csv`: para cada estación-sentido, el tramo, la sección del
  inventario, los carriles aforados (catálogo de julio de 2026), los del inventario del PTEOSVAM (2006), los del
  modelo, su papel, su estado, una explicación posible y el escenario alternativo. Coinciden en 8 de 14; los
  otros 6 quedan pendientes de confirmación.
- `uso_de_la_geometria.csv`: los 11 cálculos que dependen del número de carriles, con los carriles que usan, su
  estado, su fuente y el supuesto que los sustituye cuando no están confirmados. Todos tienen fuente o supuesto explícito.
- **Ramales.** No hay aforos de ramales publicados. La capacidad libre del tramo siguiente no los necesita (las
  entradas netas se cancelan), pero tampoco los ve; el balance entre estaciones es descriptivo y no entra en el
  modelo. Se publican variantes con entradas un 10 % mayores y con salidas desconocidas del 5 %.
- **Escenarios geométricos ejecutados:** el k crítico con los carriles del inventario, la capacidad libre con los
  carriles del inventario en Campus Guajara y Bomberos La Laguna (tercer carril de la mañana:
  12 % el primer año, con una cola de hoy en el rango medido en el 17 % de las
  combinaciones) y el tramo siguiente sin capacidad libre.

**Límites.** Los ficheros usados no dan el punto kilométrico de las estaciones ni el comienzo y el fin de cada
carril; la petición está preparada, sin enviar (`docs/solicitud_datos_cabildo.md`, punto 6; D05 y D16).

## 5. Restricción aguas abajo

**Criterio.** Que un tercer carril no aumente el caudal si el siguiente cuello lo limita; cola remanente,
longitud de almacenamiento y bloqueo de incorporaciones; conservación en cada intervalo; que la demanda no
desaparezca al desplazar horarios; efecto físico esperado cuando abajo no hay capacidad.

**Resultado.**
- **El tercer carril y la regulación no añaden caudal si el tramo siguiente limita** (comprobaciones M06 y M07 de
  `comprobaciones_modelo.csv`): con capacidad libre nula o negativa (−5 %), la descarga con cola es la misma con y
  sin ellos (se cumple en las dos). En el escenario adverso de tramo siguiente lleno, el tercer carril reduce la demora un
  0 % por la mañana (p90: 0 %).
- **Propagación de la cola.** Cuando la especificación la incluye, la capacidad libre negativa frena también la
  descarga actual: la cola de abajo remonta al cuello. La curva g15 (tercer carril con una capacidad libre fija en todas las
  horas) no aplica esa propagación: orienta sobre cuánto pesa la holgura y no sustituye al resultado principal.
- **Cuellos en serie** (`cola_remanente_aguas_abajo.csv`; `simular_tandem()`). El cuello de la mañana y el tramo
  siguiente se simulan en serie, con un almacenamiento finito entre los dos (longitud × 3 carriles × 140 veh/km) y
  las entradas de los ramales, que se bloquean en proporción cuando el almacenamiento se llena. Tercer carril, primer
  año (mediana de 200 combinaciones calibradas; con esas mismas, el modelo principal da 39 %):

  | Almacenamiento | Reducción de la demora | Cola remanente máxima | Minutos con rebose | Demora en los ramales (veh·h; hoy) |
  |---|---|---|---|---|
  | 0 km (0 veh) | 39 % (23-73 %) | 0 veh | 143 | 20,7 (0,6) |
  | 1 km (420 veh) | 32 % (15-73 %) | 420 veh | 66 | 11,8 (0,0) |
  | 2 km (840 veh) | 32 % (15-73 %) | 634 veh | 0 | 0,0 (0,0) |
  | 4 km (1.680 veh) | 32 % (15-73 %) | 634 veh | 0 | 0,0 (0,0) |

  Con almacenamiento, la cola que el tercer carril quita en Los Rodeos queda en parte entre los dos cuellos y retiene
  también a los vehículos que entran por los ramales: por eso la reducción en serie es distinta de la del modelo
  principal. Las longitudes son supuestas (no hay puntos kilométricos publicados).
- **Conservación** (`comprobaciones_modelo.csv`; se cumplen 13 de 13 comprobaciones): en cada minuto,
  llegadas = salidas + colas, también en los dos cuellos en serie; con el perfil de cada combinación calibrada, la
  demanda simulada suma los vehículos del día; al desplazar la punta no se pierde ningún vehículo, tampoco cerca del
  borde del día; la cola y las salidas nunca son negativas y las salidas no superan la capacidad. Las pruebas
  automáticas repiten estas comprobaciones con casos extremos.

## 6. Sin ganador por diferencias mínimas

**Criterio.** Diferencias absolutas y relativas, incertidumbre de la diferencia con escenarios emparejados,
sensibilidad y condiciones de aplicabilidad; coste, plazo y riesgos por separado; ninguna recomendación basada solo
en una diferencia menor que la incertidumbre.

**Cómo se hace** (`diferencias_emparejadas()`). Cada combinación calibrada se usa para todas las alternativas, así
que la diferencia se mide combinación a combinación. Para cada pareja se dan la diferencia mediana, su banda p10-p90,
su error de muestreo (bootstrap), la diferencia relativa y la parte de las combinaciones en que gana cada una. Una
diferencia de menos de **2 puntos** (umbral fijado de antemano) no es material.

**Resultado: tercer carril frente a regulación + escalonamiento, primer año** (en puntos de reducción de la demora):

| Sentido | Diferencia mediana (p10 a p90) | Error de muestreo | Combinaciones en que el tercer carril reduce más | Lectura |
|---|---|---|---|---|
| Mañana | −8,0 (−18,6 a +11,0) | 0,9 | 26 % | Depende de los parámetros: la banda p10-p90 de la diferencia cruza el 0 |
| Tarde (tercer carril hipotético) | +6,1 (−7,9 a +28,3) | 0,5 | 66 % | Depende de los parámetros: la banda p10-p90 de la diferencia cruza el 0 |

Con cada regla de calibración (`diferencias_emparejadas_por_regla.csv`), la diferencia mediana de la mañana va de
−8,0 a +7,4 puntos. Todas las parejas, en los tres horizontes, están en
`diferencias_emparejadas.csv` y en g21. «Sin diferencia material» describe la diferencia típica (la mediana, o la mitad
de las combinaciones dentro de 2 puntos): si la banda es ancha, cuál reduce más puede cambiar según los parámetros,
y por eso cada lectura va con su banda.

**Coste, plazo y riesgos, aparte del efecto** (`coste_plazo_riesgo.csv`; dato documental y valoración cualitativa):

| Alternativa | Coste | Plazo | Riesgos principales |
|---|---|---|---|
| Tercer carril Guamasa-Aeropuerto Norte (hacia Santa Cruz) | 58,2 M€ con IGIC (contrato formalizado) | 35 meses de ejecución según licitación («casi tres años», según el Cabildo); inicio de las obras anunciado para noviembre de 2026, con el acta de replanteo prevista para la semana del 26-10-2026 (Cabildo de Tenerife, 20-10-2026); cómputo sujeto al acta y a los pliegos | Retraso de obra (la pasarela del Padre Anchieta abrió con tres años de retraso); molestias durante casi tres años de obra 24 h (el Cabildo anuncia que se mantienen los dos carriles actuales y las vías TF-252 y TF-235; demolición del puente de Los Rodeos); el beneficio depende de la capacidad libre del tramo siguiente (La Laguna); demanda inducida |
| Tercer carril hacia el Norte en Los Rodeos-Guamasa (hipotético) | Sin presupuesto: no proyectado (el tercer carril Guamasa-La Orotava, ~300 M€, empieza en Guamasa) | Sin proyecto ni fecha | Exigiría un proyecto nuevo; La Matanza (2 carriles) limitaría el beneficio mientras no se amplíe |
| Regulación de accesos (semáforos en los ramales) | 1,8-4 M€ (Padre Anchieta + 4 enlaces, según el Cabildo) | Anunciada en mayo de 2025 para octubre-noviembre de 2025; pruebas de la DGT del 12 al 14-01-2026; sin implantar | Colas en los ramales y en las vías que llegan a ellos; eficacia sin piloto en Tenerife; depende de que la caída de capacidad sea la supuesta; necesita coordinación del Cabildo y la DGT |
| Escalonamiento de horarios (ULL, Administración, colegios) | Sin coste de obra (reorganización de horarios) | En marcha en la ULL desde el curso 2025-26 (13 grados); ampliación anunciada para 2026-27 (unos 4.700 estudiantes) | Depende de instituciones y de la conducta de las personas; efecto pequeño y sin cambio visible en los cuellos (asociación no causal) |
| Tarificación de la punta | ~10 M€ (PIMSIT, horizonte 2032-2033) y cambio legal | Exige cambiar la ley canaria; descartada por la presidencia del Cabildo el 07-10-2026 | Aceptación social y política; marco legal; sin alternativa viaria; equidad entre usuarios |
| Regulación de accesos + escalonamiento | 1,8-4 M€ (regulación) + reorganización de horarios | Componentes en pruebas (regulación) o en marcha (escalonamiento) | Los de la regulación de accesos y los del escalonamiento a la vez |

**Condición de aplicabilidad.** Las reducciones son escenarios del modelo con la red y la demanda de 2025: dependen de
la capacidad libre del tramo siguiente (estimada), de la caída de capacidad (no medible con aforos horarios) y de
elasticidades y eficacias de la literatura. El estudio no recomienda una alternativa por su mediana cuando la
diferencia no es material.

## 7. Días atípicos y datos faltantes

**Criterio.** Identificar festivos, incidentes, obras, lluvia, averías de sensores y cambios de hora; marcar
observación, imputación y exclusión con motivos; repetir las estimaciones sin días atípicos y con métodos
alternativos de imputación; publicar la cobertura por estación y hora y la proporción imputada.

**Resultado.**
- **Cada día con su estado y su motivo** (`dias_atipicos.csv`, una fila por estación, sentido y día laborable). En
  los dos cuellos: Ermita Cruz Chica hacia Santa Cruz, 49 días excluidos y 44 marcas
  en días usados; Bomberos La Laguna hacia el Norte, 49 y 48 (`dias_atipicos_resumen.csv`, con el
  motivo de cada uno: agosto, día incompleto por avería o corte del aforador, tráfico por debajo del 85 % de la
  mediana del mes, puente, Navidad, Semana Santa y punta anómala). Los festivos autonómicos e insulares no son
  laborables. Los cambios de hora caen en domingo, así que no afectan a los días laborables; en las horas, la serie
  con banderas marca las horas que faltan o se repiten.
- **Punta anómala:** caudal de la punta más de tres desviaciones absolutas medianas por debajo de la mediana del
  mes. Es la señal de un posible incidente u obra que se puede ver en los aforos.
- **Sin días atípicos** (`sensibilidad_sin_dias_atipicos.csv`): quitando los puentes, la Navidad, la Semana Santa y
  las puntas anómalas, la media de horas de cola de los dos cuellos cambia como mucho 0,03 h y la descarga
  mediana 22,0 veh/h.
- **Imputación** (`sensibilidad_depuracion.csv`, `cobertura_e_imputacion_por_estacion_mes_hora.csv`). El análisis no
  imputa (tasa del 0 %): excluye. Dos métodos alternativos para las horas a las que les falta un carril (A,
  proporcional; B, mediana de la misma hora, mes y estación-sentido) afectarían a 0 horas del corredor y a
  ninguna de los dos cuellos, así que no cambian sus resultados. Con todas las variantes de depuración, la media de
  horas de cola de los cuellos cambia como mucho 0,21 h y la descarga mediana 15,0 veh/h. La cobertura
  por estación, mes y hora está en la misma tabla.

**Límites.** Incidentes, obras y lluvia no están vinculados a los días. El Cabildo publica un registro de
incidencias en carreteras (2010-2026, con carretera, tramo, fecha y hora de inicio y tipo) que no se ha incorporado
porque su descarga no se pudo completar en el entorno del análisis; queda como fuente identificada (D09). La lluvia
exige una clave de AEMET OpenData (D15).

## 8. Fuentes originales

**Criterio.** URL oficial, organismo, fecha de descarga, versión, licencia, identificador de estación, huella y
correspondencia de campos; comprobar una muestra contra la publicación original; para los datos no publicados,
solicitud y estado.

**Resultado.**
- `procedencia_datos.csv`: una fila por recurso (24 horarios, 13 oficiales y 3 publicados sin usar), con
  organismo, conjunto, recurso, URL, identificador, licencia leída del catálogo, fecha de modificación en origen (la
  versión del recurso), fecha de descarga, bytes y SHA-256 del original y de la copia, cobertura, filtros y unidades.
  37 copias íntegras; 37 coinciden en tamaño y fecha con la instantánea del catálogo; en 24 de 24 extractos
  los totales coinciden con las sumas de control del TXT original. Los identificadores de estación están en
  `R/00_utilidades.R` (`ESTACIONES_TF5`) y en cada extracto.
- `correspondencia_de_campos.csv`: los 31 campos de los tres ficheros oficiales, cada uno con su definición del
  diccionario oficial y su nombre en el proyecto (o «no se usa»).
- **Contraste con la publicación original, fuera del proyecto** (`contraste_publicacion_original.csv`; de metadatos, sin
  volver a descargar: el contraste con descarga directa de los 37 recursos está en `docs/contraste_fuentes/`). El
  16-10-2026 se contrastó una muestra con el catálogo nacional de datos abiertos (datos.gob.es), que federa el portal
  del Cabildo: los 12 TXT horarios de 2025 y su diccionario. Coinciden 13 de 13 en URL, identificador, nombre
  y licencia; la fecha de modificación del conjunto difiere 1 h entre los dos catálogos
  (probablemente por la zona horaria).
- **Datos no publicados o no incorporados**, con su estado (`datos/matriz_lagunas.csv`, columna
  `estado_solicitud`):
  - D01, caudales por carril cada 5-15 minutos: petición preparada (docs/solicitud_datos_cabildo.md, punto 1); no enviada;
  - D02, velocidades y tiempos de recorrido por itinerario: petición preparada (punto 4); no enviada;
  - D04, caudales de entradas y salidas en los enlaces: petición preparada (punto 2); no enviada;
  - D09, incidentes y obras: publicado y no incorporado (pendiente de descarga); la petición preparada (punto 5) pide además sentido, punto kilométrico, carriles afectados y duración;
  - D15, lluvia y meteorología por día y hora: sin solicitar; requiere pedir la clave de AEMET OpenData;
  - D17, aforos horarios de diciembre de 2024: publicado; pendiente de descarga (no hace falta pedirlo).

**Límites.** El contraste de valores con el original exige volver a descargar los ficheros
(`DESCARGAR_HORARIOS <- TRUE` en `main.R`, que compara el SHA-256 con el registrado); en la ejecución entregada
no se volvió a descargar nada. La huella prueba la integridad de la copia, no la autenticidad del origen.

## 9. Hechos separados de escenarios

**Criterio.** Rotular cada cifra como observación, estimación, supuesto o resultado simulado; distinguir los
escenarios a 1, 5 y 10 años de las previsiones verificadas; probar crecimiento, demanda inducida, cambios modales y
retrasos de obra; que gráficos y conclusiones digan horizonte, hipótesis e incertidumbre.

**Resultado.**
- `datos/limitaciones_por_resultado.csv`: 25 resultados con su categoría (9 simulados, 7 observados, 4 supuestos, 3 estimados y 2 asociaciones no causales),
  origen, limitaciones e incertidumbre. Las tablas de resultados simulados repiten la categoría.
- `graficos_metadatos.csv`: los 23 gráficos con su tipo de resultado, horizonte, hipótesis e incertidumbre.
- **Ninguna previsión está verificada**: son escenarios condicionados. `previsiones_condicionadas.csv` separa el
  crecimiento de la demanda, los cambios de red, el trasvase al transporte público y la demanda inducida, cada uno
  con su condición de validez.
- **Pruebas de escenario:**
  - crecimiento de la demanda de 0 %, 0,5 % y 1 % anual, con y sin adaptación (`evolucion_sin_actuar.csv`);
  - demanda inducida a 1, 5 y 10 años y un escenario de demanda inducida alta (`escenarios_adversos.csv`);
  - trasvase al transporte público: un 10 % de la punta de la mañana reduciría la demora un
    39 % (29-69 %) el primer año (`transporte_publico_trasvase.csv`);
  - retraso de la obra del tercer carril: entrando en servicio en 2029 o en 2032, con crecimiento del
    0,5 % anual, reduciría la demora un 39 % y un 41 % el primer año (`retraso_obra_tercer_carril.csv`);
  - supuesto de la descarga fuera de las horas con datos: con crecimiento del 0,5 % anual, la cola de la mañana en 2035 sería de 5,5 h con el supuesto principal y de 10,9 h si la descarga reducida de las últimas horas con datos se mantuviera el resto del día (`sensibilidad_prevision_descarga.csv`).

## 10. Reproducibilidad

**Criterio.** Versiones de R y de los paquetes, semillas y zona horaria fijadas; ejecución completa y pruebas;
hashes y métricas regeneradas iguales a las guardadas dentro de una tolerancia definida; avisos y errores
registrados.

**Resultado.**
- **Entorno:** R 4.3.3 y 70 paquetes fijados en `renv.lock`; `main.R` compara al empezar las versiones instaladas con
  `entorno/versiones_paquetes.csv` (`entorno_versiones.csv`: todas coinciden).
- **Semillas:** una por cada paso aleatorio, todas fijas y listadas en `montecarlo_semillas.csv` (21 filas); una
  prueba comprueba que cada semilla del código está en la tabla.
- **Zona horaria:** `Atlantic/Canary`, fijada en `main.R` (`configuracion_ejecucion.csv`: Atlantic/Canary).
- **Ejecución completa sin intervención:** 62,5 minutos, 0 avisos (`registro_avisos.txt`, que recoge todos
  los avisos del análisis) y ningún error; las salidas se borran al empezar y las entradas no cambian durante la
  ejecución (comprobado con sus huellas).
- **Pruebas:** 72 bloques y 2.536 comprobaciones, 0 fallos (`salidas/resultado_pruebas.csv`).
- **Dos ejecuciones completas, en copias limpias** (`docs/reproducibilidad_dos_ejecuciones.csv`, con
  `tests/comparar_ejecuciones.R`): 191 de 191 tablas y gráficos de salidas dentro de la tolerancia (diferencia relativa
  ≤ 1e-8 en las cifras, mismas filas, columnas y textos; los gráficos, iguales byte a byte), contando la serie horaria
  comprimida y el resultado de las pruebas, ejecutadas en las dos copias; 191 son iguales byte a byte. No se comparan
  los 2 ficheros propios de cada ejecución (la configuración, con su hora de inicio, y el manifiesto de huellas) ni
  los registros de texto de la ejecución (resumen, sesión y avisos), que llevan la hora; los de la segunda copia se
  conservan en `docs/segunda_ejecucion/` y su registro de avisos también dice «0 avisos».
- **No regresión:** 23 tablas clave de la ejecución entregada en `tests/referencia/`, con su configuración; una
  ejecución completa nueva con la misma configuración tiene que reproducirlas con una tolerancia relativa de 1e-8.
- **Manifiestos:** `salidas/manifiesto_ejecucion.csv` (código, datos y salidas al acabar) y `manifiesto_entrega.csv`
  (todos los ficheros entregados).

**Límites.** Las dos ejecuciones se hicieron en la misma máquina: muestran que el resultado no depende de la
ejecución, no que otra persona lo reproduzca en otro equipo.
