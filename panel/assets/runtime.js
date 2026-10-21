/* Runtime local del panel TF-5. Datos procedentes de assets/datos.js. */
(() => {
  'use strict';
  const datos = window.TF5_DATOS || {};
  const calculos = new Map();
  const callbacks = [];
  const errores = [];
  const falta = {status: 'missing', columns: [], data: []};
  let iniciado = false;
  const data = id => datos[id] || falta;
  window.dash = {
    colors: ['#2a78d6','#eb6834','#1baf7a','#eda100','#e87ba4','#008300','#6250d6','#e34948'],
    data,
    calc(id, definicion) { calculos.set(id, definicion); },
    onData(fn) { callbacks.push(fn); if (iniciado) ejecutar(fn); },
    setLink(id) { if (location.hash.slice(1) !== id) history.replaceState(null, '', '#' + encodeURIComponent(id)); },
    errors: errores,
  };
  function ejecutar(fn) {
    try { fn(); } catch (e) { errores.push(String(e)); console.error(e); }
  }
  function iniciar() {
    let pendientes = [...calculos.keys()];
    while (pendientes.length) {
      const anteriores = pendientes.length;
      pendientes = pendientes.filter(id => {
        const def = calculos.get(id);
        if (!def.inputs.every(k => data(k).status === 'ok')) return true;
        try {
          const filas = def.fn(...def.inputs.map(k => data(k).data));
          datos[id] = {status: 'ok', data: filas, columns: Object.keys(filas[0] || {})};
        } catch (e) {
          datos[id] = {status: 'error', data: [], columns: []};
          errores.push(id + ': ' + e); console.error(e);
        }
        return false;
      });
      if (pendientes.length === anteriores) {
        pendientes.forEach(id => errores.push('Dependencias sin resolver: ' + id));
        break;
      }
    }
    iniciado = true;
    // Las tablas con desplazamiento horizontal se pueden recorrer con el teclado
    document.querySelectorAll('.table-wrap').forEach(d => { d.setAttribute('tabindex', '0'); d.setAttribute('aria-label', 'Tabla desplazable'); });
    callbacks.forEach(ejecutar);
    const aviso = document.getElementById('estado-panel');
    if (aviso) {
      aviso.textContent = errores.length ? 'Hay errores al cargar el panel. Revisa la consola.' : 'Panel local · datos cargados · funciona sin conexión';
      aviso.dataset.estado = errores.length ? 'error' : 'ok';
      aviso.setAttribute('role', 'status');
    }
    window.TF5_LISTO = true;
  }
  document.addEventListener('DOMContentLoaded', iniciar, {once: true});
  let pendienteResize;
  window.addEventListener('resize', () => {
    clearTimeout(pendienteResize);
    pendienteResize = setTimeout(() => callbacks.forEach(ejecutar), 180);
  });
})();
