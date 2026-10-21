"""Rellena los documentos del proyecto con las cifras de la última ejecución de main.R.

Uso (desde la carpeta del proyecto, después de main.R y de las pruebas):
    python3 herramientas/documentos/rellenar.py

Cada plantilla (*.plantilla.md, en esta carpeta) es el documento con expresiones de Python entre dobles llaves
que leen las tablas de salidas/tablas y las formatean en español. Las definiciones auxiliares van entre {% y %}.
Si una expresión falla (una tabla o una fila que no existe), no se escribe ningún documento y se dice cuál falla.
Así ninguna cifra de los documentos se copia a mano.
"""
import collections
import csv
import gzip
import json
import math
import os
import re
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
PROY = os.path.abspath(os.path.join(AQUI, "..", ".."))
DESTINOS = {
    "README.plantilla.md": "README.md",
    "METODOLOGIA.plantilla.md": "docs/METODOLOGIA.md",
    "VALIDACION_Y_CALIDAD.plantilla.md": "docs/VALIDACION_Y_CALIDAD.md",
}
CASOS = {"m": "manana_hacia_santa_cruz", "t": "tarde_hacia_el_norte"}
_cache = {}


def T(nombre):
    """Filas (diccionarios) de salidas/tablas/<nombre>.csv."""
    ruta = os.path.join(PROY, "salidas", "tablas", nombre if nombre.endswith(".csv") else nombre + ".csv")
    if ruta not in _cache:
        with open(ruta, encoding="utf-8") as f:
            _cache[ruta] = list(csv.DictReader(f))
    return _cache[ruta]


def _cumple(x, conds):
    for k, v in conds.items():
        if k == "caso" and v in CASOS:
            v = CASOS[v]
        if callable(v):
            if not v(x.get(k)):
                return False
        elif str(x.get(k)) != str(v):
            return False
    return True


def rows(nombre, **conds):
    return [x for x in T(nombre) if _cumple(x, conds)]


def row(nombre, **conds):
    r = rows(nombre, **conds)
    if len(r) != 1:
        raise ValueError(f"{nombre} {conds}: {len(r)} filas")
    return r[0]


def v(nombre, col, **conds):
    """Valor numérico de una celda (la fila tiene que ser única)."""
    x = row(nombre, **conds)[col]
    return float(x) if x not in ("", "NA") else float("nan")


def s(nombre, col, **conds):
    """Texto de una celda."""
    return row(nombre, **conds)[col]


def starts(prefijo):
    return lambda x: x is not None and x.startswith(prefijo)


def _redondear(x, d=0):
    """Redondeo como el del panel: la mitad hacia arriba, sobre el valor absoluto (el mismo número sale igual en los dos)."""
    f = 10 ** d
    v = math.floor(abs(x) * f * (1 + 1e-12) + 0.5) / f
    return -v if x < 0 else v


def es(x, d=0):
    """Número en formato español: punto de miles y coma decimal."""
    if x is None or (isinstance(x, float) and math.isnan(x)):
        return "—"
    x = _redondear(float(x), d)
    if d == 0:
        x = int(round(x))
        return ("−" if x < 0 else "") + f"{abs(x):,}".replace(",", ".")
    t = f"{abs(x):,.{d}f}".replace(",", "X").replace(".", ",").replace("X", ".")
    return ("−" if x < 0 else "") + t


def sg(x, d=0):
    """Número con signo explícito (+/−); el cero, sin signo."""
    t = es(x, d)
    if t == "—" or t.startswith("−"):
        return t
    return t if float(x) == 0 or re.fullmatch(r"0(,0+)?", t) else "+" + t


def pct(x, d=0):
    """Fracción como porcentaje: 0,452 -> «45 %»."""
    if x is None or (isinstance(x, float) and math.isnan(x)):
        return "—"
    return f"{es(100 * float(x), d)} %"


def spct(x, d=0):
    t = pct(x, d)
    return t if t.startswith("−") or t.startswith("0 ") else "+" + t


def pr(a, b, d=0):
    """Rango de porcentajes: «24-93 %»."""
    return f"{es(100 * float(a), d)}-{es(100 * float(b), d)} %"


def esp(t):
    """Texto que viene de R: «92%» -> «92 %»."""
    return re.sub(r"(\d)%", r"\1 %", t)


def hm(h):
    """Hora decimal a hh:mm."""
    m = int(round(float(h) * 60))
    return f"{m // 60:02d}:{m % 60:02d}"


def quant(xs, p):
    """Cuantil de tipo 7 (el de R por defecto)."""
    xs = sorted(float(x) for x in xs)
    if not xs:
        return float("nan")
    h = (len(xs) - 1) * p
    lo = int(math.floor(h))
    hi = min(lo + 1, len(xs) - 1)
    return xs[lo] + (h - lo) * (xs[hi] - xs[lo])


def leer(ruta_rel):
    with open(os.path.join(PROY, ruta_rel), encoding="utf-8") as f:
        return f.read()


def csvp(ruta_rel):
    with open(os.path.join(PROY, ruta_rel), encoding="utf-8") as f:
        return list(csv.DictReader(f))


def cabecera_gz(ruta_rel):
    with gzip.open(os.path.join(PROY, ruta_rel), "rt", encoding="utf-8") as f:
        return f.readline().strip().split(",")


def gz_max(ruta_rel, col, **conds):
    """Máximo de una columna numérica de una tabla comprimida (.csv.gz), leída fila a fila, en las filas que cumplen
    las condiciones (valor exacto o función, como en rows())."""
    mejor = None
    with gzip.open(os.path.join(PROY, ruta_rel), "rt", encoding="utf-8") as f:
        for x in csv.DictReader(f):
            if x[col] in ("", "NA") or not _cumple(x, conds):
                continue
            v = float(x[col])
            if mejor is None or v > mejor:
                mejor = v
    if mejor is None:
        raise ValueError(f"{ruta_rel}: ninguna fila cumple {conds}")
    return mejor


def clasificar_comparacion(filas):
    """Clasifica las filas de un informe de tests/comparar_ejecuciones.R (lista de diccionarios) para redactar el
    resumen de una comparación entre ejecuciones. Devuelve un diccionario con: n (ficheros comparados), byte (iguales
    byte a byte), formato (mismas cifras, otro formato de fichero), texto (cambian solo celdas de texto, mismas filas y
    sin ninguna cifra distinta), filas (ficheros con filas añadidas o retiradas), imagen (gráficos distintos) y otros
    (cualquier otro caso: cifras distintas, columnas distintas, ficheros nuevos o retirados)."""
    r = {"n": 0, "byte": 0, "formato": [], "texto": [], "filas": [], "imagen": [], "otros": []}
    for x in filas:
        if x["dentro_de_tolerancia"] not in ("TRUE", "FALSE"):
            continue   # propio de la ejecución: no se compara
        r["n"] += 1
        nombre = x["fichero"]
        num = x["dif_numerica_max"]
        sin_cifras_distintas = num in ("", "NA") or float(num) == 0
        mismas_filas = x["filas_ref"] == x["filas_nueva"]
        mismas_columnas = x["columnas_nuevas"] in ("", "NA") and x["columnas_retiradas"] in ("", "NA") and x["orden_columnas_igual"] in ("TRUE", "")
        if x["estado"] == "igual (byte a byte)":
            r["byte"] += 1
        elif x["estado"] == "igual en valores (cambia el formato)":
            r["formato"].append(nombre)
        elif x["estado"] == "cambia" and mismas_filas and mismas_columnas and sin_cifras_distintas and x["celdas_ausencia_distinta"] in ("", "0") and x["celdas_texto_distintas"] not in ("", "0"):
            r["texto"].append((nombre, int(x["celdas_texto_distintas"])))
        elif x["estado"] == "cambia" and not mismas_filas and mismas_columnas:
            r["filas"].append((nombre, int(x["filas_ref"]), int(x["filas_nueva"])))
        elif x["estado"] == "cambia (imagen)":
            r["imagen"].append(nombre)
        else:
            r["otros"].append(nombre)
    return r


def rx(ruta_rel, patron, grupo=1):
    """Primer grupo de una expresión regular en un fichero de texto de salidas (p. ej. resumen_resultados.txt);
    falla si el patrón no aparece exactamente una vez."""
    m = re.findall(patron, leer(ruta_rel))
    if len(m) != 1:
        raise ValueError(f"{ruta_rel}: el patrón {patron!r} aparece {len(m)} veces")
    return m[0] if isinstance(m[0], str) else m[0][grupo - 1]


def rellenar(texto):
    ctx = {k: x for k, x in globals().items() if not k.startswith("_")}
    fallos = []

    def definir(m):
        nombre, expr = m.group(1).strip(), m.group(2).strip()
        try:
            ctx[nombre] = eval(expr, ctx)
        except Exception as e:  # noqa: BLE001
            fallos.append(f"{nombre} = {expr[:80]} -> {type(e).__name__}: {e}")
        return ""

    def sustituir(m):
        expr = m.group(1).strip()
        try:
            return str(eval(expr, ctx))
        except Exception as e:  # noqa: BLE001
            fallos.append(f"{expr[:100]} -> {type(e).__name__}: {e}")
            return "«ERROR»"

    texto = re.sub(r"\{%\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)%\}\n?", definir, texto, flags=re.S)
    salida = re.sub(r"\{\{(.*?)\}\}", sustituir, texto, flags=re.S)
    return salida, fallos


def main():
    resultados, todos = {}, []
    for plantilla, destino in DESTINOS.items():
        with open(os.path.join(AQUI, plantilla), encoding="utf-8") as f:
            salida, fallos = rellenar(f.read())
        todos += [f"{plantilla}: {x}" for x in fallos]
        resultados[destino] = salida
    if todos:
        print("No se ha escrito nada. Expresiones que fallan:", *todos, sep="\n  ")
        sys.exit(1)
    for destino, salida in resultados.items():
        with open(os.path.join(PROY, destino), "w", encoding="utf-8") as f:
            f.write(salida)
        print(f"escrito {destino} ({len(salida.encode('utf-8')) // 1024} KB)")


if __name__ == "__main__":
    main()
