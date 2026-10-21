# Solicitud de información al Cabildo de Tenerife (modelo)

Plantilla para pedir los datos que faltan en el proyecto. Se presenta por la sede electrónica del Cabildo como **solicitud de acceso a la información pública** (Ley 19/2013, de transparencia, y Ley 12/2014 de Canarias). El plazo general de respuesta es de un mes. Rellena los datos entre corchetes.

---

**Destinatario:** Cabildo Insular de Tenerife · Área de Carreteras, Movilidad e Innovación (Servicio Técnico de Carreteras y Movilidad).

**Asunto:** Solicitud de información técnica agregada de tráfico de la autopista TF-5 (2024-2026) para un trabajo académico sobre congestión.

[Nombre y apellidos], estudiante del Curso de Especialización en Inteligencia Artificial y Big Data, con [DNI/NIE], solicita, al amparo de la normativa de transparencia, la siguiente información **agregada y sin datos personales**, en formato reutilizable (CSV, JSON o similar):

1. **Aforos por detector cada 5 o 15 minutos** (intensidad por carril y clase de vehículo, y velocidad media o rangos de velocidad) de las estaciones permanentes 85, 93, 97, 99, 103, 111 y 123 de la TF-5, en ambos sentidos, de septiembre de 2024 a septiembre de 2026, al menos en las franjas de 5:00 a 11:00 y de 12:00 a 21:00 de los días laborables. Ya se usan los registros horarios publicados en datos.tenerife.es; la resolución subhoraria permitiría fijar el inicio y el fin de las colas.
2. **Aforos de los ramales de entrada y salida** de los enlaces entre Padre Anchieta y Guamasa (ambos sentidos), con la misma resolución y periodo.
3. **Registro de incidencias de los detectores**: cortes, averías, recalibraciones y sustituciones de sensores, en especial de la estación 97 (Padre Anchieta), que tiene meses sin datos y rangos de velocidad con valores negativos, y del carril 3 de la estación 85 (Hospital Residencia) hacia el Norte desde noviembre de 2025.
4. **Tiempos de recorrido** por tramos de la TF-5 (por ejemplo, los obtenidos con el GPS de las guaguas de TITSA que el Cabildo citó al presentar el balance de los horarios escalonados de la ULL el 3 de septiembre de 2026), con su método de cálculo y periodo de referencia.
5. **Incidentes y obras** en la TF-5 entre Santa Cruz y La Orotava, de septiembre de 2024 a septiembre de 2026. El portal ya publica el registro «Incidencias en carreteras de Tenerife» (carretera, tramo, fecha y hora de inicio y tipo). Se pide completarlo, para ese tramo y periodo, con el sentido, el punto kilométrico, los carriles afectados y la hora de fin o la duración de cada incidencia, y con los cortes de carril por obras o mantenimiento programados que no figuren en él.
6. **Inventario de carriles efectivos** y geometría (punto kilométrico de cada estación de aforo, comienzo y fin de cada carril adicional, en especial en Padre Anchieta y en el estrechamiento de 3 a 2 carriles hacia el Norte en Los Rodeos). El catálogo de carriles de los aforos (julio de 2026) y el inventario del Plan Territorial Especial de Ordenación del Sistema Viario del Área Metropolitana de Tenerife (PTEOSVAM, aprobado en 2006) no coinciden en seis estación-sentidos: Campus Guajara (4 aforados frente a 3 en el inventario, en los dos sentidos), Padre Anchieta hacia Santa Cruz (3 frente a 2), Bomberos La Laguna hacia Santa Cruz (4 frente a 3) y La Orotava (3 frente a 2, en los dos sentidos). Interesa saber si la diferencia es un carril de enlace contado como carril o una obra posterior.
7. **Estudios de las medidas en marcha o previstas**:
   - simulaciones del carril Bus-VAO «inteligente» (PK 2,5-12,2) que estiman reducciones del 50 % y del 21 % del tiempo de viaje;
   - resultados de las pruebas de regulación de accesos realizadas con la DGT en enero de 2026;
   - evaluación del efecto de la pasarela del Padre Anchieta y del cierre de los pasos de peatones de la glorieta (mayo de 2026);
   - método y datos de la estimación de unos 500 vehículos/día menos en la punta por los horarios escalonados de la ULL.
8. **Datos de ocupación de los vehículos** (personas por vehículo por carril y hora) o, en su defecto, de los estudios que el Cabildo haya hecho para dimensionar el Bus-VAO.

Para cada conjunto agradecería que se indicaran la estación o el punto kilométrico, la zona horaria de las marcas de tiempo (y cómo se trata el cambio de hora), el método de agregación, la cobertura, la licencia de reutilización y la fecha de la última revisión. Si algún dato no existe o no puede facilitarse, ruego que se indique qué órgano lo custodia y si se pueden facilitar esos datos agregados.

En [lugar], a [fecha].

[Firma]

---

**Por qué se pide cada dato** (relación con las lagunas de `datos/matriz_lagunas.csv`, que también da el estado de cada petición): 1 → D01; 2 → D04; 3 → D14; 4 → D02, D10 y D13 (validación independiente); 5 → D09; 6 → D05 y D16; 7 → D11; 8 → D07. No se piden aquí D17 (diciembre de 2024, ya publicado en el portal), D15 (lluvia, en AEMET OpenData con clave de acceso), D06 (encuesta de movilidad) ni D12 (contratos ya publicados).
