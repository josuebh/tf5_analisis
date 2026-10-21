"""Contrasta por descarga directa 37 recursos: 8 IMD, 5 auxiliares y 24 TXT horarios.

Uso: python3 herramientas/comprobaciones/contrastar_fuentes.py --salida informe.csv
Requiere Internet (unos 230 MB). No modifica datos/. Solo Python estándar.
La huella comprueba los originales; Counter contrasta todas las filas del extracto,
incluyendo multiplicidades, contra los campos equivalentes del TXT descargado.
"""
import argparse
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
import csv
from datetime import datetime, timezone
import gzip
import hashlib
import io
import json
from pathlib import Path
import urllib.request

BASE = Path(__file__).resolve().parents[2]
ESTACIONES = {82, 83, 85, 93, 97, 99, 103, 111, 123, 131, 133, 134, 136, 138}


def comprobar(meta):
    resultado = {"tipo": meta["tipo"], "recurso": meta["recurso"], "url": meta["url"],
                 "consultado_utc": datetime.now(timezone.utc).isoformat(), "estado": "ERROR"}
    try:
        peticion = urllib.request.Request(meta["url"], headers={"User-Agent": "TF5-contraste/1.0"})
        with urllib.request.urlopen(peticion, timeout=75) as respuesta:
            raw = respuesta.read()
            resultado.update(http=respuesta.status, bytes=len(raw), url_final=respuesta.url)
        huella = hashlib.sha256(raw).hexdigest()
        resultado.update(sha256_descargado=huella, sha256_esperado=meta["sha256"], sha256_coincide=huella == meta["sha256"])
        if meta["tipo"] == "horario":
            with gzip.open(meta["local"], "rt", encoding="utf-8-sig", newline="") as f:
                lector = csv.DictReader(f)
                columnas = lector.fieldnames
                def clave(fila):
                    return tuple(fila[c].strip() if c == "fecha" else int(fila[c]) for c in columnas)
                almacenadas = Counter(clave(r) for r in lector)
            lector = csv.DictReader(io.StringIO(raw.decode("utf-8-sig")))
            if not set(columnas).issubset(lector.fieldnames or []):
                raise ValueError("El TXT no contiene los campos del extracto")
            seleccion = set(meta.get("estaciones", ESTACIONES))
            originales = Counter(clave(r) for r in lector if int(r["estacion_id"]) in seleccion)
            resultado.update(filas_extracto=sum(almacenadas.values()), filas_oficiales_tf5=sum(originales.values()),
                             filas_coinciden=almacenadas == originales, estaciones_seleccionadas=" ".join(str(x) for x in sorted(seleccion)))
        else:
            resultado["filas_coinciden"] = (BASE / meta["local"]).read_bytes() == raw
        resultado["estado"] = "OK" if resultado["sha256_coincide"] and resultado["filas_coinciden"] else "DIFERENCIA"
    except Exception as exc:
        resultado["detalle"] = f"{type(exc).__name__}: {exc}"
    return resultado


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--salida", required=True)
    parser.add_argument("--solo-auxiliares", action="store_true", help="Contrastar solo los cinco recursos auxiliares")
    args = parser.parse_args()
    manifiesto = json.loads((BASE / "datos/oficial/manifiesto_oficiales.json").read_text(encoding="utf-8"))
    tareas = [dict(tipo="imd" if m["fichero"].startswith("intensidad-media-diaria-de-trafico-") else "auxiliar",
                   recurso=m["fichero"], url=m["url"], sha256=m["sha256"], local="datos/oficial/" + m["fichero"])
              for m in manifiesto["ficheros"]]
    if args.solo_auxiliares:
        tareas = [x for x in tareas if x["tipo"] == "auxiliar"]
    for p in ([] if args.solo_auxiliares else sorted((BASE / "datos/horarios").glob("meta_*.json"))):
        m = json.loads(p.read_text(encoding="utf-8"))
        tareas.append(dict(tipo="horario", recurso=m["mes"], url=m["url"], sha256=m["sha256_raw"],
                           local=BASE / "datos/horarios" / ("tf5_horario_" + m["mes"] + ".csv.gz"),
                           estaciones=m.get("estaciones", sorted(ESTACIONES))))
    with ThreadPoolExecutor(max_workers=4) as pool:
        resultados = list(pool.map(comprobar, tareas))
    destino = Path(args.salida)
    destino.parent.mkdir(parents=True, exist_ok=True)
    columnas = list(dict.fromkeys(k for r in resultados for k in r))
    with destino.open("w", encoding="utf-8", newline="") as f:
        escritor = csv.DictWriter(f, fieldnames=columnas, lineterminator="\n")
        escritor.writeheader(); escritor.writerows(resultados)
    resumen = Counter(r["estado"] for r in resultados)
    print(json.dumps(dict(resumen), ensure_ascii=False))
    for r in resultados:
        if r["estado"] != "OK": print(r["recurso"], r.get("detalle", r["estado"]))
    esperados = 5 if args.solo_auxiliares else 37
    return 0 if len(resultados) == esperados and resumen["OK"] == esperados else 1


if __name__ == "__main__":
    raise SystemExit(main())
