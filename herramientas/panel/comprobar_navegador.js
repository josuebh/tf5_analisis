// Prueba real de renderizado. Requiere Playwright y un navegador Chromium instalado.
// Uso desde la raíz: node herramientas/panel/comprobar_navegador.js [panel/index.html] [resultado.json] [marcas.txt]
// marcas.txt (opcional) es la salida de comprobar_marcas.js: cada cifra que pinta el navegador se compara, en orden,
// con la que calcula el comprobador a partir de los CSV (campo cifras_iguales_al_comprobador del resultado).
// TF5_CHROMIUM permite indicar un ejecutable; TF5_CHROMIUM_ARGS, argumentos como JSON.
const fs = require('fs');
const path = require('path');
const {pathToFileURL} = require('url');
const {chromium} = require('playwright');

(async () => {
  const opciones = {headless: true};
  if (process.env.TF5_CHROMIUM) opciones.executablePath = process.env.TF5_CHROMIUM;
  if (process.env.TF5_CHROMIUM_ARGS) opciones.args = JSON.parse(process.env.TF5_CHROMIUM_ARGS);
  const browser = await chromium.launch(opciones);
  const resultados = [];
  // Cifras esperadas: parte final («-> valor») de cada marca en línea del informe de comprobar_marcas.js
  const esperadas = process.argv[4]
    ? fs.readFileSync(process.argv[4], 'utf8').split('\n').filter(l => /^\S+ \[.*\] = .* -> /.test(l))
        .map(l => l.slice(l.lastIndexOf(' -> ') + 4))
    : null;
  const page = await browser.newPage();
  try {
    for (const viewport of [{width: 1365, height: 1000}, {width: 390, height: 844}]) {
      await page.setViewportSize(viewport);
      page.removeAllListeners('pageerror');
      page.removeAllListeners('console');
      await page.unrouteAll();
      const errores = [], red = [];
      page.on('pageerror', e => errores.push(e.message));
      page.on('console', m => { if (m.type() === 'error') errores.push(m.text()); });
      await page.route(/^https?:/, route => { red.push(route.request().url()); return route.abort(); });
      await page.goto(pathToFileURL(path.resolve(process.argv[2] || 'panel/index.html')).href);
      await page.waitForFunction(() => window.TF5_LISTO === true);
      const metricas = await page.evaluate(() => ({
        errores_runtime: dash.errors,
        graficos_svg: document.querySelectorAll('svg').length,
        filas_tablas: document.querySelectorAll('tbody tr').length,
        cifras_sin_rellenar: [...document.querySelectorAll('span.v')].filter(x => x.textContent === '—').length,
        cifras_renderizadas: [...document.querySelectorAll('span.v')].map(x => x.textContent),
        ancho_vista: innerWidth, ancho_documento: document.documentElement.scrollWidth,
        afirmaciones: TF5.rows('afirmaciones').length,
      }));
      await page.locator('a[href="#datos"]').click();
      await page.locator('#q-afirmaciones').fill('tercer carril');
      const filtradas = await page.locator('#tb-afirmaciones tbody tr').count();
      await page.locator('#q-afirmaciones').fill('');
      const restauradas = await page.locator('#tb-afirmaciones tbody tr').count();
      const {cifras_renderizadas, ...resto} = metricas;
      const iguales = esperadas ? cifras_renderizadas.filter((v, i) => v === esperadas[i]).length : null;
      const cifras = esperadas ? {en_pagina: cifras_renderizadas.length, en_comprobador: esperadas.length, iguales} : null;
      const cifras_ok = !esperadas || (iguales === esperadas.length && cifras_renderizadas.length === esperadas.length);
      resultados.push({viewport, ...resto, errores, peticiones_externas: red,
        cifras_iguales_al_comprobador: cifras,
        filtro_funciona: filtradas > 0 && filtradas < restauradas && restauradas === metricas.afirmaciones,
        ok: !errores.length && !metricas.errores_runtime.length && !red.length && metricas.graficos_svg > 0 &&
          metricas.cifras_sin_rellenar === 0 && metricas.ancho_documento <= viewport.width && cifras_ok &&
          filtradas > 0 && filtradas < restauradas && restauradas === metricas.afirmaciones});
    }
  } finally { await browser.close(); }
  const texto = JSON.stringify(resultados, null, 2);
  if (process.argv[3]) fs.writeFileSync(process.argv[3], texto + '\n');
  console.log(texto);
  if (!resultados.every(x => x.ok)) process.exitCode = 1;
})().catch(e => { console.error(e); process.exitCode = 1; });
