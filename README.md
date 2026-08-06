# Pipeline de Automatización Bioinformática y Configuración de Entornos para genomas procariotas

## Descripción General
Este repositorio contiene los scripts de automatización, guías y protocolos desarrollados para estandarizar, agilizar y asegurar la reproducibilidad en la instalación y gestión de herramientas bioinformáticas empleadas en el análisis, ensamblaje, caracterización y anotación de genomas.

---

## Autoría y Créditos
* **Autor Principàl / Desarrollador:** [Kevin Josue Casal Arroyo]
* **Filiación / Departamento:** [Coordinación Zonal 9-INSPI]
* **Institución:** Instituto Nacional de Investigación en Salud Pública (INSPI)
* **Correo de Contacto:** [kevincasal0@gmail.com]

---

## Estructura del Repositorio

```text
bioinfo-pipelines/
├── README.md                          # Documentación principal del proyecto
├── LICENSE                            # Licencia de derechos de autor y términos de uso
└── Script/
    ├── Anotación del genoma/
    │   └── run_bakta.sh               # Script de anotación genómica con Bakta
    ├── Ensamblaje de genomas de novo/
    │   ├── masurca_config.txt         # Archivo de configuración para MASURCA
    │   └── run_pipeline.sh            # Script de ejecución para ensambles de novo con MASURCA
    ├── Evaluación de calidad del ensa.../
    │   └── quast_busco_eval.sh        # Evaluación de métricas de ensamblado con QUAST y BUSCO
    └── Instalación de programas/
        ├── setup_bioinfo_env.sh       # Script de despliegue automatizado de Miniconda y entornos
        └── setup_bioinfo_env_v1.sh    # Versión alternativa/anterior del script de setup

---

## __Módulos y Herramientas Automatizadas 
El script principal de aprovisionamiento (scripts/setup_bioinfo_env.sh) despliega entornos de Conda aislados de manera independiente para evitar el conflicto de dependencias:
Entorno (env)                             Herramienta Bioinformática                    Aplicación Principal
fastqc_env                                FastQC                                        Control de calidad de lecturas de secuenciación bruta
multiqc_env                               MultiQC                                       Agregación de reportes de análisis de múltiples muestras
kraken2_env                               Kraken2                                       Clasificación taxonómica rápida de secuencias
shovill_bacterias_env                     Shovill                                       Ensamblaje genómico optimizado para genomas bacterianos
spades_env                                SPAdes                                        Ensamblador de genomas de novo
quast_env                                 QUAST                                         Evaluación de métricas y calidad de ensamblajes de genomas
bakta_env                                 Bakta                                         Anotación rápida de genomas bacterianos.
masurca_env                               MASURCA                                       Anotación de genomas de novo
---

# Pipeline de Ensamblado y Anotación Bacteriana — 

Flujo de trabajo para ir de lecturas/ensamblado crudo a un genoma bacteriano
evaluado y anotado, usando Conda/Mamba y cuatro scripts:

| Script | Función | Cuándo correrlo |
|---|---|---|
| `setup_bioinfo_env.sh` | Instala Miniforge/Mamba y crea los entornos con las herramientas | Una sola vez (o al agregar una herramienta nueva) |
| `run_pipeline.sh` | Ensambla el genoma de novo con MaSuRCA | Una vez por cada muestra a ensamblar |
| `quast_busco_eval.sh` | Evalúa el ensamblado (QUAST + BUSCO) y da un veredicto de calidad | Después de cada ensamblado |
| `run_bakta.sh` | Anota el genoma con Bakta (descarga de DB, reintentos, sync de AMRFinderPlus) | Después de evaluar (o cuando el ensamblado te convenza) |

Cada script es **independiente**: no se llaman entre sí, no comparten
estado más allá de los archivos que uno deja como entrada del siguiente
(el genoma ensamblado). Puedes correr cualquiera de ellos por separado,
las veces que necesites, en cualquier orden que tenga sentido para tu caso
(por ejemplo, reevaluar con `quast_busco_eval.sh` sin volver a ensamblar).

---

## 0. Requisitos previos

- Ubuntu/Linux (probado en Ubuntu 24.x) con conexión a internet.
- Espacio en disco: reserva al menos **10 GB** libres (la base de datos `full`
  de Bakta y las de BUSCO pesan varios GB).
- Los cuatro scripts en la misma carpeta de trabajo, con permisos de ejecución:

```bash
chmod +x setup_bioinfo_env.sh run_pipeline.sh quast_busco_eval.sh run_bakta.sh
```

---

## 1. Instalar Conda/Mamba y los entornos — `setup_bioinfo_env.sh`

Este script **solo instala programas**; no ensambla, evalúa ni anota nada.
Es el único paso que necesitas correr una sola vez (o cuando quieras agregar
una herramienta nueva).

```bash
./setup_bioinfo_env.sh
```

Instala **Miniforge** (Conda + Mamba) en `~/miniforge3` y crea un entorno
por herramienta, instalando cada paquete con `mamba` para mayor velocidad:

| Entorno | Herramienta |
|---|---|
| `fastqc_env` | FastQC |
| `multiqc_env` | MultiQC |
| `kraken2_env` | Kraken2 |
| `shovill_bacterias_env` | Shovill |
| `busco_env` | BUSCO *(Python 3.11 fijo)* |
| `quast_env` | QUAST |
| `bakta_env` | Bakta *(Python 3.11 fijo)* |
| `masurca_env` | MaSuRCA |

El script es idempotente: si vuelves a correrlo, detecta qué entornos ya
existen y no los recrea. Deja un log con timestamp en
`~/setup_bioinfo_env_FECHA.log`.

> BUSCO y Bakta se fijan a Python 3.11 explícitamente porque sus
> dependencias (ej. `pyrodigal`, `pyhmmer`) todavía no soportan versiones
> más recientes como 3.12+/3.14 — si tu sistema tiene una versión más nueva
> por defecto, el `python=3.11` en la creación del entorno evita el
> conflicto.



---

## 2. Ensamblar el genoma — `run_pipeline.sh` (MaSuRCA)

**Antes de correrlo:**

1. Activa el entorno de MaSuRCA (el script no lo hace por ti):
   ```bash
   conda activate masurca_env
   ```
2. Genera y edita el archivo de configuración `masurca_config.txt` con tus
   lecturas (Illumina/PacBio/Nanopore según tu caso). Consulta la
   documentación oficial de MaSuRCA si no tienes una plantilla:
   https://github.com/alekseyzimin/masurca

**Ejecutar:**

```bash
./run_pipeline.sh
```

El script:
1. Corre `masurca masurca_config.txt`, que genera `assemble.sh`.
2. Verifica que `assemble.sh` se haya creado correctamente.
3. Lo ejecuta para producir el ensamblado de novo.

Como el ensamblado puede tardar horas, se recomienda correrlo en segundo
plano (el propio script trae el comando sugerido al final):

```bash
nohup ./run_pipeline.sh > ensamblado.log 2>&1 &
```

Al terminar, el genoma ensamblado suele quedar como algo similar a
`CA.mr.*/primary.genome.scf.fasta` dentro de la carpeta de trabajo de
MaSuRCA — este es el archivo que usarás en los pasos siguientes.

---

## 3. Evaluar la calidad del ensamblado — `quast_busco_eval.sh`

Antes de correrlo, revisa/edita estas variables al inicio del script según
tu caso:

```bash
ASSEMBLY_FILE="primary.genome.scf.fasta"   # tu genoma ensamblado
REFERENCE=""                                # ruta a un genoma de referencia (opcional)
THREADS=8
BUSCO_LINEAGE="bacteria_odb12.2"            # cambia el linaje si no es bacteria
```

Si `ASSEMBLY_FILE` no existe con ese nombre exacto, el script intenta
localizarlo automáticamente en rutas típicas de salida de MaSuRCA.

**Ejecutar:**

```bash
./quast_busco_eval.sh
```

El script:
1. Corre **QUAST** (`quast_env`) → métricas de contigüidad (N50, nº de
   contigs, tamaño total, GC%, etc.) en `quast_results/`.
2. Corre **BUSCO** (`busco_env`) → completitud génica contra el linaje
   indicado, en `busco_results/`.
3. Extrae las métricas clave de ambos reportes y calcula un **puntaje
   ponderado** (tamaño, N50, nº de contigs, contig más largo, % BUSCO
   completo, y misassemblies si diste una referencia).
4. Imprime un veredicto final:
   - **ALTA CALIDAD** (score ≥ 6)
   - **BUENO/ACEPTABLE** (score ≥ 4)
   - **DEFICIENTE / REVISAR** (score < 4)

Guarda la salida en un archivo si quieres conservar el reporte:

```bash
./quast_busco_eval.sh | tee evaluacion_$(date +%Y%m%d).log
```

---

## 4. Anotar el genoma — `run_bakta.sh`

```bash
./run_bakta.sh -i primary.genome.scf.fasta
```

El script:
1. Activa `bakta_env` (detecta automáticamente si tu instalación es
   Miniconda, Miniforge o Anaconda).
2. Te pregunta (o recibe por bandera) qué base de datos usar:
   - **light** — más rápida y liviana (~1.3 GB), suficiente para la mayoría
     de anotaciones de rutina.
   - **full** — más completa (mejor detección de UPS/IPS), pero mucho más
     pesada y lenta de descargar.
   - **skip** — omite la descarga; úsala solo si ya tienes la base de datos
     descargada en `--db-path`.
3. Si hay que descargar, reintenta automáticamente ante cortes de red
   (hasta 5 veces, con espera creciente).
4. Sincroniza la base de datos de **AMRFinderPlus** con la versión instalada
   de `amrfinder` (paso necesario para evitar el error
   `amrfinder error! error code: 1`).
5. Corre `bakta --db <db-path> --output <output> --threads <n> genoma.fasta`.

**Opciones más usadas:**

```bash
# Elegir DB por bandera (sin preguntar) y ajustar hilos/salida
./run_bakta.sh -i genoma.fasta --db-type light -t 16 -o resultados_muestra1

# Reintentar sobrescribiendo resultados de una corrida anterior
./run_bakta.sh -i genoma.fasta --force-output

# Ver todas las opciones disponibles
./run_bakta.sh -h
```

Resultados (anotación en GFF3, GenBank, FASTA de proteínas, resumen TSV,
etc.) quedan en la carpeta indicada con `-o` (por defecto `./bakta_results`).

---

## Flujo completo, de principio a fin

```bash
# 1. Instalar Conda + entornos (una sola vez)
./setup_bioinfo_env.sh
# ... crear busco_env, bakta_env y masurca_env manualmente si hace falta (ver sección 1)

# 2. Ensamblar
conda activate masurca_env
nohup ./run_pipeline.sh > ensamblado.log 2>&1 &

# 3. Evaluar calidad (una vez terminado el ensamblado)
./quast_busco_eval.sh | tee evaluacion.log

# 4. Anotar
./run_bakta.sh -i primary.genome.scf.fasta --db-type light
```

---

## Problemas comunes

| Síntoma | Causa probable | Solución |
|---|---|---|
| `amrfinder error! error code: 1` | DB de AMRFinderPlus desactualizada | Ya automatizado en `run_bakta.sh` (Paso 2.5); si persiste, corre manualmente `amrfinder_update --force_update --database <db-path>/amrfinderplus-db` |
| `output path already exists` | Ya corriste Bakta antes con esa carpeta de salida | Usa `--force-output`, o borra/renombra la carpeta |
| Descarga de la DB de Bakta se corta a mitad | Conexión inestable / Zenodo saturado | `run_bakta.sh` reintenta solo; si sigue fallando, sube `--max-retries` y `--retry-delay`, o intenta en otro horario |
| BUSCO o Bakta fallan al instalar/correr con errores de dependencias | El entorno se creó sin fijar Python 3.11 (por ejemplo, si lo creaste a mano sin `python=3.11`) | `setup_bioinfo_env.sh` ya fija `python=3.11` para ambos; si el problema persiste, borra y recrea el entorno: `mamba env remove -n busco_env` (o `bakta_env`) y vuelve a correr el setup |
| `run_pipeline.sh` falla porque no encuentra `masurca` | No activaste el entorno correcto antes de correrlo | `conda activate masurca_env` antes de ejecutar el script |

---

## Créditos

Desarrollado por **Kevin Josué Casal Arroyo** — Analista Zonal de Laboratorio
de Vigilancia Epidemiológica y Referencia Nacional 2, Coordinación Zonal 9,
INSPI. Contacto: kevincasal0@gmail.com
Desarrollado por **Kevin Josué Casal Arroyo** — Analista Zonal de Laboratorio
de Vigilancia Epidemiológica y Referencia Nacional 2, Coordinación Zonal 9,
INSPI. Contacto: kevincasal0@gmail.com
