# Ensambla los trozos TF5CHUNK guardados por la herramienta del navegador, verifica
# SHA-256 del CSV compacto y escribe datos/horarios/tf5_horario_AAAA-MM.csv.gz + metadatos.
import json, sys, os, glob, base64, gzip, hashlib
dir_res, dir_out = sys.argv[1], sys.argv[2]
trozos, metas, nmeta = {}, {}, {}
for f in sorted(glob.glob(os.path.join(dir_res, '*.txt'))):
    try:
        d = json.load(open(f, encoding='utf-8'))
    except Exception:
        continue
    for item in d:
        t = item.get('text', '')
        if not t.startswith('"TF5CHUNK|'):
            continue
        s, _ = json.JSONDecoder().raw_decode(t)
        p = s.split('|')
        mes, i, n, data, fin = p[1], int(p[2]), int(p[3]), p[4], p[5]
        if fin != 'FINCHUNK':
            print('TROZO INCOMPLETO', f, mes, i); continue
        trozos.setdefault(mes, {})[i] = (n, data)
        if '|META|' in s:
            metas[mes] = json.loads(s.split('|META|', 1)[1].split('|FINMETA', 1)[0])
            nmeta[mes] = n
resumen = []
for mes in sorted(trozos):
    partes = trozos[mes]; n = nmeta.get(mes, next(iter(partes.values()))[0])
    faltan = [i for i in range(n) if i not in partes or partes[i][0] != n]
    if faltan or mes not in metas:
        print(f'{mes}: faltan trozos {faltan} o metadatos ({mes in metas})'); continue
    b64 = ''.join(partes[i][1] for i in range(n))
    gz = base64.b64decode(b64)
    raw = gzip.decompress(gz)
    m = metas[mes]
    ok = hashlib.sha256(raw).hexdigest() == m['sha256_compact'] and len(raw) == m['bytes_compact']
    destino = os.path.join(dir_out, f'tf5_horario_{mes}.csv.gz')
    if ok:
        with open(destino, 'wb') as fh: fh.write(gz)
        m2 = dict(m); m2['fichero_local'] = os.path.basename(destino); m2['sha256_gz_local'] = hashlib.sha256(gz).hexdigest()
        with open(os.path.join(dir_out, f'meta_{mes}.json'), 'w', encoding='utf-8') as fh: json.dump(m2, fh, ensure_ascii=False, indent=1)
    resumen.append((mes, n, ok, m['filas_tf5'], m['bytes_raw'], m['sha256_raw'][:12], m['duplicados'], m['fechas_formato_raro'], m['fechas_fuera_de_mes'], m['filas_tf5_malformadas']))
for r in resumen: print('%s trozos=%d verificado=%s filas=%d bytes_raw=%d sha_raw=%s dup=%d fecha_rara=%d fuera_mes=%d malformadas=%d' % r)
