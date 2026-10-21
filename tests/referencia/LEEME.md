# Referencia de no regresión

Copias exactas de tablas clave de la ejecución completa entregada de `main.R` (mismo SHA-256 que las de
`salidas/tablas` en `salidas/manifiesto_ejecucion.csv`), con la configuración de esa ejecución
(`configuracion_ejecucion.csv`: simulaciones, semillas de la auditoría del Monte Carlo y zona horaria).

La prueba «no regresión» de `tests/testthat/test_calidad_y_trazabilidad.R` comprueba, después de una ejecución
completa con la misma configuración, que cada tabla se reproduce: mismas filas y textos y una diferencia relativa de
1e-8 como mucho en las cifras. Con otra configuración, la prueba se omite. También se pueden comparar a mano:

```bash
Rscript tests/comparar_ejecuciones.R tests/referencia salidas/tablas ../informe.csv --solo-referencia
```

Estas copias salen de la propia ejecución entregada, así que no son una entrada de `main.R` y no figuran en su
manifiesto; `manifiesto_entrega.csv` sí las incluye.
