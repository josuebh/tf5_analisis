"""Regenera el inventario SHA-256 después de cambios legítimos en el proyecto.

Uso: python3 herramientas/comprobaciones/actualizar_manifiesto_entrega.py
Reemplaza manifiesto_entrega.csv. Una huella acredita integridad, no autoría.
"""
import csv
import hashlib
from pathlib import Path

BASE = Path(__file__).resolve().parents[2]
DESTINO = BASE / "manifiesto_entrega.csv"


# Ficheros propios de un repositorio git y de su publicación en GitHub Pages (.nojekyll, index.html), fuera del inventario
FUERA_DEL_INVENTARIO = {".gitignore", ".gitattributes", "LICENSE", ".nojekyll", "index.html"}


def es_del_repositorio(p):
    rel = p.relative_to(BASE)
    return rel.parts[0] == ".git" or (len(rel.parts) == 1 and rel.name in FUERA_DEL_INVENTARIO) or "__pycache__" in rel.parts


def main():
    ficheros = sorted(p for p in BASE.rglob("*") if p.is_file() and p != DESTINO and not es_del_repositorio(p))
    with DESTINO.open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["fichero", "bytes", "algoritmo", "huella"], lineterminator="\n")
        w.writeheader()
        for p in ficheros:
            w.writerow(dict(fichero=p.relative_to(BASE).as_posix(), bytes=p.stat().st_size,
                            algoritmo="sha256", huella=hashlib.sha256(p.read_bytes()).hexdigest()))
    print(f"Manifiesto de entrega actualizado: {len(ficheros)} archivos.")


if __name__ == "__main__":
    main()
