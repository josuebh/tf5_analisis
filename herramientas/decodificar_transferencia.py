# Decodifica la salida guardada de javascript_tool: {mes,url,bytes,sha256,gz_b64,...}
# Escribe el fichero original en el directorio de destino y verifica SHA-256 y tamaño.
import json, sys, base64, gzip, hashlib, os
src, outdir, nombre = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open(src, encoding='utf-8'))
t = d[0]['text']
s, _ = json.JSONDecoder().raw_decode(t)
meta = json.loads(s)
raw = gzip.decompress(base64.b64decode(meta['gz_b64']))
h = hashlib.sha256(raw).hexdigest()
ok = (h == meta['sha256']) and (len(raw) == meta['bytes'])
path = os.path.join(outdir, nombre)
with open(path, 'wb') as f:
    f.write(raw)
info = {k: v for k, v in meta.items() if k != 'gz_b64'}
info.update({'sha256_local': h, 'bytes_local': len(raw), 'verificado': ok, 'fichero': path})
print(json.dumps(info, ensure_ascii=False))
