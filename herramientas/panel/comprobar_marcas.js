// Comprueba las marcas del panel contra los CSV: cada data-where debe dar una sola fila,
// cada campo debe existir, cada tabla debe tener columnas y claves válidas. También ejecuta
// los cálculos (dash.calc) de la página con esos datos. No dibuja la página.
// Uso (desde la carpeta del proyecto, con Node.js):
//   node herramientas/panel/comprobar_marcas.js panel/index.html salidas/panel
// Los CSV que no están en la carpeta indicada se buscan en la de encima (resultado_pruebas.csv) y en la del proyecto
// (docs/reproducibilidad_dos_ejecuciones.csv).
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const [, , htmlPath, dir] = process.argv;
const html = fs.readFileSync(htmlPath, 'utf8');

const MAPA = require('./fuentes_panel.json');

function parseCSV(text) {
  const rows = []; let row = []; let f = ''; let q = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (q) {
      if (c === '"') { if (text[i + 1] === '"') { f += '"'; i++; } else q = false; } else f += c;
    } else if (c === '"') q = true;
    else if (c === ',') { row.push(f); f = ''; }
    else if (c === '\n') { row.push(f); rows.push(row); row = []; f = ''; }
    else if (c === '\r') { /* nada */ } else f += c;
  }
  if (f.length || row.length) { row.push(f); rows.push(row); }
  const cols = rows.shift();
  return { columns: cols, data: rows.filter((r) => r.length > 1 || r[0] !== '').map((r) => Object.fromEntries(cols.map((c, j) => [c, r[j] ?? ''])) ) };
}

const datos = {};
const ruta = (f) => [path.join(dir, f), path.join(dir, '..', f), path.join(dir, '..', '..', f)].find((r) => fs.existsSync(r)) || path.join(dir, f);
for (const [id, f] of Object.entries(MAPA)) datos[id] = parseCSV(fs.readFileSync(ruta(f), 'utf8'));

// Cálculos del panel: se ejecuta el primer script con un dash falso
const calcs = {};
const dash = {
  colors: Array.from({ length: 8 }, (_, i) => `c${i}`),
  data: (id) => (datos[id] ? { status: 'ok', data: datos[id].data, columns: datos[id].columns }
    : calcs[id] ? { status: 'ok', data: calcs[id].out } : { status: 'missing', data: [] }),
  calc: (id, def) => { calcs[id] = def; },
  onData: () => {}, setLink: () => {},
};
const scripts = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map((m) => m[1]);
const ctx = { window: {}, dash, document: { querySelectorAll: () => [], getElementById: () => null }, URLSearchParams, console, Math, Number, String };
vm.createContext(ctx);
vm.runInContext(scripts[0], ctx);
const TF5 = ctx.window.TF5;
// Resolver los cálculos en orden de dependencias
let pend = Object.keys(calcs);
for (let k = 0; k < 5 && pend.length; k++) {
  pend = pend.filter((id) => {
    const d = calcs[id];
    const ins = d.inputs.map((i) => (datos[i] ? datos[i].data : calcs[i] && calcs[i].out));
    if (ins.some((x) => x === undefined)) return true;
    d.out = d.fn(...ins);
    return false;
  });
}
const filas = (id) => (datos[id] ? datos[id].data : calcs[id] ? calcs[id].out : null);
const columnas = (id) => (datos[id] ? datos[id].columns : calcs[id] && calcs[id].out ? Object.keys(calcs[id].out[0] || {}) : []);

let errores = 0;
const err = (m) => { errores++; console.log('ERROR ' + m); };
const dec = (s) => s.replace(/&amp;/g, '&');

// 1. Marcas en línea
const marcas = [...html.matchAll(/<span class="v"([^>]*)>/g)].map((m) => m[1]);
const salida = [];
for (const a of marcas) {
  const at = Object.fromEntries([...a.matchAll(/(data-[a-z]+)="([^"]*)"/g)].map((m) => [m[1], dec(m[2])]));
  const id = at['data-source'], campo = at['data-field'];
  const rs = filas(id);
  if (!rs) { err(`sin datos: ${id}`); continue; }
  if (!columnas(id).includes(campo)) { err(`${id}: no existe el campo ${campo}`); continue; }
  let r;
  if (at['data-row'] !== undefined) r = rs[Number(at['data-row'])];
  else {
    const w = new URLSearchParams(at['data-where'] || '');
    const m = rs.filter((x) => [...w.entries()].every(([k, v]) => String(x[k]) === v));
    if (m.length !== 1) { err(`${id} ${at['data-where']}: ${m.length} filas`); continue; }
    for (const k of w.keys()) if (!columnas(id).includes(k)) err(`${id}: where con columna inexistente ${k}`);
    r = m[0];
  }
  salida.push(`${id}.${campo} [${at['data-where'] || 'fila ' + at['data-row']}] = ${r[campo]} -> ${TF5.fmt(r[campo], at['data-fmt'])}`);
}

// 2. Tablas
const tablas = [...html.matchAll(/<table id="([^"]+)" data-source="([^"]+)" data-row-key="([^"]+)">([\s\S]*?)<\/table>/g)];
for (const [, tid, id, clave, cuerpo] of tablas) {
  const cols = columnas(id);
  const ths = [...cuerpo.matchAll(/<th data-field="([^"]+)"/g)].map((m) => m[1]);
  for (const t of ths) if (!cols.includes(t)) err(`${tid}: th ${t} no está en ${id}`);
  const ks = clave.split(',');
  for (const k of ks) if (!cols.includes(k)) err(`${tid}: clave ${k} no está en ${id}`);
  const vistos = new Set();
  for (const r of filas(id)) {
    const key = ks.map((k) => r[k]).join('\u0001');
    if (vistos.has(key)) err(`${tid}: clave repetida ${key}`);
    vistos.add(key);
  }
  salida.push(`tabla ${tid}: ${filas(id).length} filas, ${ths.length} columnas`);
}

// 3. Fuentes declaradas en contenedores de gráficos
const contenedores = [...html.matchAll(/id="([^"]+)"[^>]*data-source="([^"]+)"/g)];
for (const [, el, ids] of contenedores) for (const id of ids.split(' ')) if (!filas(id)) err(`${el}: fuente desconocida ${id}`);
const usadas = new Set([...html.matchAll(/data-source="([^"]+)"/g)].flatMap((m) => m[1].split(' ')));
for (const id of Object.keys(MAPA)) if (!usadas.has(id) && !Object.values(calcs).some((c) => c.inputs.includes(id))) err(`dataset sin usar: ${id}`);
console.log(salida.join('\n'));
console.log(`\nCálculos: ${Object.entries(calcs).map(([k, v]) => k + '=' + JSON.stringify(v.out).slice(0, 120)).join('\n  ')}`);
console.log(`\n${marcas.length} marcas en línea, ${tablas.length} tablas, ${errores} errores`);
process.exit(errores ? 1 : 0);
