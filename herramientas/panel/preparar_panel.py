"""Empaqueta los CSV del panel para abrir index.html sin servidor ni Internet.

Uso desde la raíz del proyecto: python3 herramientas/panel/preparar_panel.py
No cambia los CSV ni recalcula las simulaciones. Solo usa Python estándar.
"""
import csv
import json
from pathlib import Path

BASE = Path(__file__).resolve().parents[2]
MAPA = json.loads((Path(__file__).parent / "fuentes_panel.json").read_text(encoding="utf-8"))


def preparar():
    datos = {}
    for clave, nombre in MAPA.items():
        candidatos = [BASE / "salidas/panel" / nombre, BASE / "salidas" / nombre, BASE / nombre]
        origen = next((p for p in candidatos if p.is_file()), None)
        if origen is None:
            raise FileNotFoundError(f"Falta el CSV del panel: {nombre}")
        with origen.open(encoding="utf-8-sig", newline="") as f:
            reader = csv.DictReader(f)
            filas = list(reader)
            if not reader.fieldnames or any(None in r or None in r.values() for r in filas):
                raise ValueError(f"CSV mal formado: {origen}")
            datos[clave] = {"status": "ok", "columns": reader.fieldnames, "data": filas}
    destino = BASE / "panel/assets/datos.js"
    destino.parent.mkdir(parents=True, exist_ok=True)
    texto = json.dumps(datos, ensure_ascii=False, separators=(",", ":"), allow_nan=False)
    texto = texto.replace("<", "\\u003c").replace("\u2028", "\\u2028").replace("\u2029", "\\u2029")
    destino.write_text("// Generado desde los CSV; no editar a mano.\nwindow.TF5_DATOS=" + texto + ";\n", encoding="utf-8")
    print(f"Panel preparado: {len(datos)} fuentes, {sum(len(x['data']) for x in datos.values())} filas.")


if __name__ == "__main__":
    preparar()
