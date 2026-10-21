# Herramientas de descarga (procedencia de los datos)

Los ficheros oficiales se descargaron el 16 de octubre de 2026 (hora canaria; en los metadatos, `descargado_utc`
va de las 23:37 UTC del día 15 a las 02:20 UTC del día 16) desde el portal de datos abiertos
del Cabildo de Tenerife (datos.tenerife.es). El entorno donde se hizo el análisis no podía conectarse al
portal, así que la descarga se hizo desde un navegador:

1. Un script en el navegador (no se conserva; queda lo que registró) pidió al portal cada TXT mensual (URL de `datos/fuentes_horarias.csv`) y cada
   fichero pequeño (IMD 2018-2025, catálogo de carriles y diccionarios). De cada TXT calculó el SHA-256 y el
   tamaño, contó filas, duplicados y fechas fuera de su mes, sumó por estación y sentido las filas, los
   ligeros, los pesados y los rangos de velocidad (campo `control` de `datos/horarios/meta_AAAA-MM.json`),
   extrajo las filas de la TF-5 (sin las columnas de nombre) y las envió comprimidas por trozos.
2. `ensamblar_horarios.py` une los trozos, comprueba el SHA-256 y el tamaño del extracto y escribe
   `datos/horarios/tf5_horario_AAAA-MM.csv.gz` y `meta_AAAA-MM.json`.
3. `decodificar_transferencia.py` hace lo mismo con los ficheros pequeños, que se copian enteros en
   `datos/oficial/` con su huella en `manifiesto_oficiales.json`.
4. La instantánea del catálogo (`datos/oficial/catalogo_portal_2026-10-16.json`) guarda, para los cinco
   conjuntos, la licencia, la fecha de modificación y la lista de recursos (identificador, nombre, formato,
   fecha de modificación y tamaño).
5. El listado del conjunto de 2025 en el catálogo nacional de datos abiertos, que federa el portal del Cabildo
   ([datos.gob.es](https://datos.gob.es/es/catalogo/l03380011-intensidad-diaria-de-trafico-de-tenerife-2025)), se
   consultó el 16-10-2026 y se copió en `datos/contraste_catalogo_nacional_2026-10-16.csv` (identificador, nombre,
   formato, URL y licencia de cada recurso). `contraste_publicacion_original()` lo compara con las URL usadas al
   descargar y con la instantánea del portal: es el contraste con una publicación que no es del proyecto.

**Qué prueba y qué no.** Las huellas SHA-256 prueban que las copias no han cambiado desde la descarga
(integridad). No prueban la autenticidad del origen, que depende de la conexión HTTPS con el portal en el
momento de la descarga y no se puede comprobar desde dentro del proyecto. La tabla
`salidas/tablas/procedencia_datos.csv` comprueba en cada ejecución que:

- cada copia conserva su huella;
- los totales de cada extracto coinciden con las sumas de control que registró el script al leer el TXT original;
- tamaño y fecha de modificación coinciden con los del recurso en la instantánea del catálogo guardada en el
  proyecto (es un contraste con un fichero del proyecto, no una consulta al portal).

También registra los recursos publicados que no se han descargado (diciembre de 2024 y los diccionarios de
2024 y 2026).

**Cómo repetirlo con Internet** (en `main.R`):

- `DESCARGAR_HORARIOS <- TRUE` vuelve a bajar los TXT a `datos/horarios/originales/` y compara su SHA-256
  con el registrado.
- `CONTRASTAR_EN_LINEA <- TRUE` contrasta la IMD con el portal y guarda una nueva instantánea del catálogo
  (`consultar_catalogo_portal()`). La tabla de procedencia usa siempre la instantánea más reciente.

**Plantillas de los documentos** (`herramientas/documentos/`). Las cifras del README, de la metodología, de la
validación se rellenan desde las tablas de `salidas/` con
`python3 herramientas/documentos/rellenar.py`, después de ejecutar `main.R` y las pruebas. Detalles en
`herramientas/documentos/LEEME.md`.

**Comprobación del panel** (`herramientas/panel/comprobar_marcas.js`, con Node.js). Comprueba que cada cifra de
`panel/index.html` (marcas `data-source`, `data-field` y `data-where`) encuentra una sola fila en los CSV de
`salidas/panel` y que cada tabla tiene sus columnas y claves, y ejecuta los cálculos de la página con esos datos. No
dibuja la página. Desde la carpeta del proyecto: `node herramientas/panel/comprobar_marcas.js panel/index.html salidas/panel`.

**Comprobaciones aparte** (`herramientas/comprobaciones/`; no las ejecuta `main.R`). `base_nocturna_solo_2025.R`
recalcula la línea base de velocidad de madrugada solo con los días válidos de 2025 (`main.R` la calcula con los 24
meses) y cuenta las horas de 2025 que cambiarían de estado, congestionada o no, en cada estación y sentido. Escribe
`docs/comprobacion_base_nocturna_2025.csv`. Desde la carpeta del proyecto:
`Rscript herramientas/comprobaciones/base_nocturna_solo_2025.R` (unos dos minutos).


## Panel autónomo y comprobaciones del paquete

Extrae todo el ZIP y abre `panel/index.html`; incluye D3 7.9.0 con su licencia, estilos, un runtime local y los datos empaquetados. No requiere servidor ni conexión.

Tras ejecutar R y sus pruebas, ejecuta `python3 herramientas/documentos/rellenar.py` y `python3 herramientas/panel/preparar_panel.py` para sincronizar documentos y panel. El empaquetador no modifica los CSV ni recalcula el modelo.

Comprobaciones adicionales:

```bash
node herramientas/panel/comprobar_marcas.js panel/index.html salidas/panel > ../marcas.txt
python3 herramientas/comprobaciones/verificar_entrega.py
# Con Internet; contrasta los 37 originales y todas las filas de los extractos:
python3 herramientas/comprobaciones/contrastar_fuentes.py --salida ../contraste_actual.csv
# Opcional: requiere Playwright y Chromium instalados. El tercer argumento (la salida de comprobar_marcas.js)
# hace que cada cifra pintada por el navegador se compare con la que calcula el comprobador:
node herramientas/panel/comprobar_navegador.js panel/index.html ../resultado_navegador.json ../marcas.txt
```

Los informes creados al repetir comprobaciones se escriben fuera de la carpeta del proyecto (`../`): `verificar_entrega.py` exige que todo fichero dentro de ella esté en `manifiesto_entrega.csv`. El manifiesto de entrega describe el ZIP tal como se entregó; si modificas archivos, genera un manifiesto nuevo con `python3 herramientas/comprobaciones/actualizar_manifiesto_entrega.py`.
