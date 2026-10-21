"""Audita integridad y coherencia estructural sin cambiar los datos del proyecto.

Uso: python3 herramientas/comprobaciones/verificar_entrega.py [--salida informe.csv]
Solo Python estándar. Para el código científico usa también las pruebas de R.
"""
import argparse
from collections import Counter
import csv
import gzip
import hashlib
from html.parser import HTMLParser
import json
from pathlib import Path
import sys
from urllib.parse import unquote, urlsplit

BASE = Path(__file__).resolve().parents[2]


class Panel(HTMLParser):
    def __init__(self):
        super().__init__(); self.ids = []; self.enlaces = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if "id" in attrs: self.ids.append(attrs["id"])
        for clave in ("src", "href"):
            if clave in attrs: self.enlaces.append(attrs[clave])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--salida")
    args = parser.parse_args()
    resultados = []
    def registrar(grupo, elemento, correcto, detalle=""):
        resultados.append(dict(grupo=grupo, elemento=str(elemento), estado="OK" if correcto else "ERROR", detalle=detalle))
    for p in sorted(BASE.rglob("*.csv")):
        try:
            with p.open(encoding="utf-8-sig", newline="") as f:
                r = csv.reader(f, strict=True); columnas = next(r)
                assert columnas and len(columnas) == len(set(columnas)), "Cabecera vacía o duplicada"
                for numero, fila in enumerate(r, 2):
                    assert len(fila) == len(columnas), f"Fila {numero}: número de campos distinto de la cabecera"
            registrar("CSV", p.relative_to(BASE), True)
        except Exception as exc: registrar("CSV", p.relative_to(BASE), False, str(exc))
    for p in sorted(BASE.rglob("*.json")) + [BASE / "renv.lock"]:
        try: json.loads(p.read_text(encoding="utf-8-sig")); registrar("JSON", p.relative_to(BASE), True)
        except Exception as exc: registrar("JSON", p.relative_to(BASE), False, str(exc))
    for p in sorted((BASE / "datos/horarios").glob("meta_*.json")):
        try:
            m = json.loads(p.read_text(encoding="utf-8"))
            gz = (p.parent / m["fichero_local"]).read_bytes(); raw = gzip.decompress(gz)
            assert hashlib.sha256(gz).hexdigest() == m["sha256_gz_local"], "Huella del gzip distinta"
            assert hashlib.sha256(raw).hexdigest() == m["sha256_compact"], "Huella del extracto distinta"
            registrar("extractos", m["mes"], True)
        except Exception as exc: registrar("extractos", p.name, False, str(exc))
    for p in sorted(BASE.rglob("*.py")):
        try: compile(p.read_text(encoding="utf-8"), str(p), "exec"); registrar("Python", p.relative_to(BASE), True)
        except Exception as exc: registrar("Python", p.relative_to(BASE), False, str(exc))
    for p in [BASE / "README.md", BASE / "docs/METODOLOGIA.md", BASE / "docs/VALIDACION_Y_CALIDAD.md"]:
        texto = p.read_text(encoding="utf-8")
        registrar("documentos", p.relative_to(BASE), "{{" not in texto and "{%" not in texto, "Sin expresiones de plantilla pendientes")
    panel = Panel(); panel.feed((BASE / "panel/index.html").read_text(encoding="utf-8"))
    registrar("panel", "ids únicos", len(panel.ids) == len(set(panel.ids)))
    for enlace in panel.enlaces:
        parsed = urlsplit(enlace)
        if parsed.scheme or parsed.netloc: continue
        if parsed.path:
            destino = (BASE / "panel" / unquote(parsed.path)).resolve()
            registrar("panel_enlaces", enlace, destino.is_file())
        elif parsed.fragment:
            registrar("panel_anclas", enlace, unquote(parsed.fragment) in panel.ids)
    try:
        contenido = (BASE / "panel/assets/datos.js").read_text(encoding="utf-8")
        empaquetados = json.loads(contenido.split("window.TF5_DATOS=", 1)[1].rstrip(";\n"))
        mapa = json.loads((BASE / "herramientas/panel/fuentes_panel.json").read_text(encoding="utf-8"))
        for id, nombre in mapa.items():
            destino = next(p for p in [BASE / "salidas/panel" / nombre, BASE / "salidas" / nombre, BASE / nombre] if p.is_file())
            with destino.open(encoding="utf-8-sig", newline="") as f:
                lector = csv.DictReader(f); filas = list(lector)
                registrar("panel_datos", id, empaquetados[id]["data"] == filas and empaquetados[id]["columns"] == lector.fieldnames)
    except Exception as exc: registrar("panel_datos", "paquete", False, str(exc))
    manifiesto = BASE / "manifiesto_entrega.csv"
    with manifiesto.open(encoding="utf-8") as f:
        entradas = list(csv.DictReader(f))
    registrados = set()
    for fila in entradas:
        p = BASE / fila["fichero"]; registrados.add(fila["fichero"])
        bien = p.is_file() and p.stat().st_size == int(fila["bytes"]) and hashlib.new(fila["algoritmo"], p.read_bytes()).hexdigest() == fila["huella"]
        registrar("manifiesto", fila["fichero"], bien)
    # Un clon del repositorio git añade .git/, LICENSE, .gitignore o .gitattributes y, por la publicación en GitHub
    # Pages, .nojekyll (sin Jekyll) e index.html (lleva al panel): no forman parte de la entrega
    fuera = {".gitignore", ".gitattributes", "LICENSE", ".nojekyll", "index.html"}
    def propio_del_repositorio(rel):
        return rel.parts[0] == ".git" or (len(rel.parts) == 1 and rel.name in fuera) or "__pycache__" in rel.parts
    # as_posix(): el manifiesto escribe siempre «/»; en Windows str() daría «\» y la cobertura saldría mal
    actuales = {p.relative_to(BASE).as_posix() for p in BASE.rglob("*")
                if p.is_file() and p != manifiesto and not propio_del_repositorio(p.relative_to(BASE))}
    registrar("manifiesto", "cobertura completa", actuales == registrados,
              "No inventariados: " + ", ".join(sorted(actuales - registrados)))
    if args.salida:
        with Path(args.salida).open("w", encoding="utf-8", newline="") as f:
            w = csv.DictWriter(f, fieldnames=["grupo", "elemento", "estado", "detalle"], lineterminator="\n"); w.writeheader(); w.writerows(resultados)
    resumen = Counter(r["estado"] for r in resultados)
    print(json.dumps(dict(resumen), ensure_ascii=False))
    for r in resultados:
        if r["estado"] != "OK": print(r["grupo"], r["elemento"], r["detalle"])
    return 1 if resumen["ERROR"] else 0


if __name__ == "__main__":
    sys.exit(main())
