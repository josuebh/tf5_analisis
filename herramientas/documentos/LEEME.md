# Plantillas de los documentos

Las cifras de `README.md`, `docs/METODOLOGIA.md` y `docs/VALIDACION_Y_CALIDAD.md` no se
copian a mano. Cada documento tiene aquí una plantilla (`*.plantilla.md`) con el texto y, en lugar de cada cifra,
una expresión que la lee de las tablas de `salidas/tablas` (o de otro fichero del proyecto) y la escribe en formato
español.

**Cómo se usan.** Después de ejecutar `main.R` y las pruebas, desde la carpeta del proyecto:

```bash
python3 herramientas/documentos/rellenar.py
```

El script reescribe los cuatro documentos con las cifras de la última ejecución. Si una expresión falla (por
ejemplo, porque una tabla ha cambiado de forma), no escribe nada y dice qué expresión falla. Necesita Python 3,
sin paquetes adicionales.

**Formato de las plantillas.**

- `{{ expresión }}` se sustituye por el resultado de la expresión. Por ejemplo,
  `{{pct(v('fichas_alternativas', 'mediana_1er_anio', caso='m', alternativa='tercer_carril'))}}` escribe la mediana
  del tercer carril de la mañana el primer año, como porcentaje. La expresión no puede contener `}}`.
- `{% nombre = expresión %}` define una variable o una función auxiliar, que pueden usar las expresiones que vienen
  después. La expresión no puede contener `%}`.
- Funciones disponibles: `v()` (valor numérico de una celda de una fila única), `s()` (texto), `row()`, `rows()` y
  `T()` (filas de una tabla), `starts()` (condición «empieza por»), `es()` (número con punto de miles y coma decimal;
  redondea la mitad hacia arriba, igual que el panel), `pct()` y `pr()` (porcentajes y rangos), `sg()` y `spct()`
  (con signo), `esp()` (espacio antes de «%» en los textos que vienen de R), `hm()` (hora), `quant()` (cuantil como
  en R), `leer()`, `csvp()` y `cabecera_gz()` (ficheros del proyecto), `gz_max()` (máximo de una columna de una tabla
  comprimida, leída fila a fila, con condiciones como `rows()`), `rx()` (primer grupo de una expresión regular en un
  fichero de texto de salidas, como `resumen_resultados.txt`; falla si el patrón no aparece exactamente una vez) y
  `clasificar_comparacion()` (clasifica las filas de un informe de `tests/comparar_ejecuciones.R` para redactar el
  resumen de una comparación entre ejecuciones: iguales byte a byte, mismas cifras con otro formato, solo textos, filas
  añadidas o retiradas, gráficos distintos y cualquier otro caso).
- Las plantillas pueden incluir comprobaciones: una línea `{% _chk_x = 1 / int(condición) %}` hace que `rellenar.py`
  falle, sin escribir nada, si la condición no se cumple (por ejemplo, si la comparación con otra ejecución tuviera
  alguna cifra distinta o un fichero de un tipo no previsto).
- El caso `'m'` es la mañana hacia Santa Cruz y `'t'`, la tarde hacia el Norte.
- Algunas frases dependen del resultado (por ejemplo, si una diferencia entre alternativas es material o no): la
  plantilla elige el texto con la misma regla que el código R, así que el documento no puede afirmar algo que la
  tabla no dice.
