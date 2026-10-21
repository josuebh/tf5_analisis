# Reimplementación en Python de las cifras observadas

**Qué es.** Una reimplementación del cálculo en Python, escrita por separado y sin ver las salidas del
proyecto: los días válidos, las horas congestionadas, el
horario de la cola, el caudal de descarga, el efecto de los horarios de la ULL, el de la pasarela del Padre
Anchieta, la comparación 2026-2025, la cobertura de Padre Anchieta, la IMD y el crecimiento de la población.
Solo leyó el código R para conocer las definiciones.

**Qué no es.** No es una verificación externa de los datos: lee las mismas copias de `datos/` que el
proyecto, no los ficheros del portal. Tampoco es una ejecución del proyecto en otro entorno. Comprueba que
el código R calcula lo que dice calcular, no que las definiciones sean las mejores.

- `verificar_tf5.py`: recálculo principal (pandas, numpy y scipy). Se ejecuta desde esta carpeta con
  `python3 verificar_tf5.py`; lee `../../datos/` y escribe `results.json`, `results.csv` y ficheros intermedios aquí.
  Para no alterar los entregables (ni las huellas de `manifiesto_entrega.csv`), ejecútalo sobre una copia de la carpeta
  o con `TF5_BASE` apuntando al proyecto desde otro directorio. Re-ejecutado el 20-10-2026 con Python 3.13, pandas 3.0.5,
  numpy 2.5.3 y scipy 1.18.1: `results.json` y `results.csv` idénticos (el `.csv.gz` solo cambia la marca de tiempo de la
  cabecera gzip).
- `contraste_alternativo.py`: segundo cálculo, construido de otra forma, para los apartados 1 a 8.
- `results.csv` y `results.json`: resultados obtenidos el 16-10-2026 con las mismas copias de `datos/` que usa la
  ejecución entregada.

Sus cifras coinciden con las tablas del proyecto; `contraste_alternativo.log` es la salida de `contraste_alternativo.py`.
