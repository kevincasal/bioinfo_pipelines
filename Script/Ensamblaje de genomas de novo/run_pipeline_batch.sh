#!/bin/bash

# ==============================================================================
# Script:      batch_masurca_assembly.sh
# Descripción: Ensamblado por lote (batch) de genomas bacterianos con MaSuRCA
#              a partir de lecturas Illumina paired-end.
#
# Qué hace, paso a paso:
#   1. Busca en INPUT_DIR todos los pares de lecturas R1/R2 (_R1/_R2, _r1/_r2
#      o _1/_2) y extrae el identificador de cada muestra a partir del nombre
#      del archivo.
#   2. Para cada muestra, genera un config.txt de MaSuRCA con parámetros
#      estándar para bacterias con Illumina PE.
#   3. Corre 'masurca config.txt' (genera assemble.sh) y luego './assemble.sh'.
#   4. Copia el ensamblado final (primary.genome.scf.fasta) a la carpeta de
#      resultados, renombrado como '<muestra>_assembly.fasta'.
#   5. Guarda toda la salida de cada muestra en su propio log:
#      logs/<muestra>.log
#
# AUTOR:   [KEVIN JOSUE CASAL ARROYO] — INSPI, Coordinación Zonal 9
# FECHA:   Agosto 2026
# ==============================================================================


# ==============================================================================
# ------------------------- CONFIGURACIÓN (edítala aquí) ---------------------
# ==============================================================================

# --- Carpetas del proyecto ---
INPUT_DIR="$HOME/Desktop/secuencias"              # Aquí van tus .fastq.gz de entrada (R1/R2)
RESULTS_DIR="$HOME/Desktop/ensamblados_finales"    # Aquí se copian los ensamblados finales
LOGS_DIR="$HOME/Desktop/logs"                      # Un archivo .log por muestra
WORK_DIR="$HOME/Desktop/trabajo_temporal"          # Archivos intermedios de MaSuRCA (una subcarpeta por muestra)

# --- Entorno conda donde está instalado MaSuRCA ---
ENV_NAME="masurca_env"

# --- Parámetros estándar de MaSuRCA para bacterias con Illumina PE ---
PE_MEAN=350              # Tamaño medio del inserto de las lecturas paired-end
                        # NOTA: ajusta esto a los valores reales estimados por QC
                        # (ej. Picard InsertSizeMetrics o FastQC), no dejes el default a ciegas.
PE_STDEV=35              # Desviación estándar del inserto

GRAPH_KMER_SIZE="auto"   # K-mer del grafo de de Bruijn ('auto' deja que MaSuRCA lo calcule)
USE_LINKING_MATES=1      # OBLIGATORIO en 1 para ensamblados solo-Illumina
CA_ERROR_RATE=0.25       # cgwErrorRate de Celera Assembler; 0.25 es el estándar para bacterias/virus
CLOSE_GAPS=0             # 1 = cerrar gaps del ensamblado; 0 = omitir este paso
                        # (déjalo en 0 si tu máquina tiene poca RAM; el gap-closing
                        #  es la etapa que más memoria consume)

THREADS=8                # Hilos/núcleos a usar (ajusta al máximo disponible en el servidor)

JF_SIZE=200000000        # Tamaño del hash de Jellyfish (nº de k-mers reservados en memoria).
                        # Regla práctica para bacterias:
                        #   genoma ~5 Mb con cobertura alta : 50M-100M
                        #   genomas pequeños (<3 Mb)        : 30M-50M
                        #   genomas grandes (>8 Mb)         : 100M-200M
                        # Se deja un valor moderado por defecto para lotes automatizados.

SOAP_ASSEMBLY=0           # Desactivado: no aplica a bacterias/Illumina-only
FLYE_ASSEMBLY=0           # Desactivado: es para lecturas largas (PacBio/Nanopore)

EXTEND_JUMP_READS=0       # Legacy de librerías JUMP, no aplica aquí
LIMIT_JUMP_COVERAGE=60
LHE_COVERAGE=35

USE_GRID=0                # 0 = ejecución local (no cluster/SGE)
GRID_ENGINE="SGE"
GRID_QUEUE="all.q"
GRID_BATCH_SIZE=100000000  # Reducido desde el default de MaSuRCA (500000000) para
                           # evitar picos de memoria innecesarios en máquinas modestas.

# --- Límite de lecturas en memoria durante el gap-closing ---
# Esta es la causa directa del error "std::bad_alloc" / "signal 6" que puede
# aparecer en la etapa de gap-closing: MaSuRCA intenta reservar espacio para
# demasiadas lecturas a la vez. Bajarlo reduce drásticamente el uso de RAM.
MAX_READS_IN_MEMORY=5000000

# ==============================================================================
# ------------------------- FIN DE LA CONFIGURACIÓN ---------------------------
# A partir de aquí no debería ser necesario editar nada para el uso normal.
# ==============================================================================

set -uo pipefail
# No usamos 'set -e' a nivel global a propósito: si una muestra falla, el
# script debe seguir procesando las demás en vez de abortar todo el lote.

mkdir -p "$RESULTS_DIR" "$LOGS_DIR" "$WORK_DIR"

echo "=============================================================================="
echo " Ensamblado por Lote de Genomas Bacterianos con MaSuRCA"
echo "=============================================================================="
echo "Lecturas de entrada : $INPUT_DIR"
echo "Resultados finales  : $RESULTS_DIR"
echo "Logs (uno x muestra): $LOGS_DIR"
echo "Archivos temporales : $WORK_DIR"
echo "=============================================================================="

# --- Activar el entorno conda donde está instalado MaSuRCA ---
if command -v conda >/dev/null 2>&1; then
    CONDA_BASE="$(conda info --base)"
elif [ -d "$HOME/miniforge3" ]; then
    CONDA_BASE="$HOME/miniforge3"
elif [ -d "$HOME/miniconda3" ]; then
    CONDA_BASE="$HOME/miniconda3"
elif [ -d "$HOME/anaconda3" ]; then
    CONDA_BASE="$HOME/anaconda3"
else
    echo "‼️  No se encontró una instalación de Conda/Miniforge en las rutas habituales."
    exit 1
fi
source "$CONDA_BASE/etc/profile.d/conda.sh"

if ! conda activate "$ENV_NAME" 2>/dev/null; then
    echo "‼️  No se pudo activar el entorno '$ENV_NAME'. ¿Está creado? (ver setup_bioinfo_env.sh)"
    exit 1
fi
echo "Entorno '$ENV_NAME' activado correctamente."
echo ""

if [ ! -d "$INPUT_DIR" ]; then
    echo "‼️  La carpeta de entrada '$INPUT_DIR' no existe."
    exit 1
fi

# ==============================================================================
# 1. DETECTAR PARES DE LECTURAS (R1/R2) EN INPUT_DIR
# ==============================================================================
echo "=== [1] Buscando pares de lecturas en '$INPUT_DIR' ==="

declare -A MUESTRAS   # nombre_muestra -> "ruta_r1|ruta_r2"

mapfile -t R1_FILES < <(find "$INPUT_DIR" -maxdepth 1 -type f \
    \( -iname "*_R1*.fastq.gz" -o -iname "*_R1*.fq.gz" \
       -o -iname "*_1.fastq.gz" -o -iname "*_1.fq.gz" \) | sort)

for r1 in "${R1_FILES[@]}"; do
    fname="$(basename "$r1")"
    r2=""
    sample=""

    # Identifica el patrón usado (_R1, _r1, o _1.) y arma el nombre del R2
    # y el identificador de la muestra a partir de lo que viene antes del patrón.
    if [[ "$fname" == *_R1* ]]; then
        r2="${r1/_R1/_R2}"
        sample="${fname%%_R1*}"
    elif [[ "$fname" == *_r1* ]]; then
        r2="${r1/_r1/_r2}"
        sample="${fname%%_r1*}"
    elif [[ "$fname" =~ _1\.(fastq|fq)\.gz$ ]]; then
        r2="${r1/_1./_2.}"
        sample="${fname%_1.*}"
    fi

    if [ -n "$sample" ] && [ -f "$r2" ]; then
        MUESTRAS["$sample"]="${r1}|${r2}"
    else
        echo "  ⚠️  No se encontró el par R2 correspondiente a '$fname'. Se omite."
    fi
done

if [ ${#MUESTRAS[@]} -eq 0 ]; then
    echo "‼️  No se detectaron pares de lecturas válidos en '$INPUT_DIR'."
    echo "    Nombres reconocidos: muestra_R1.fastq.gz/muestra_R2.fastq.gz,"
    echo "    muestra_r1.fastq.gz/muestra_r2.fastq.gz, o muestra_1.fastq.gz/muestra_2.fastq.gz"
    exit 1
fi

echo "Muestras detectadas (${#MUESTRAS[@]}):"
for s in "${!MUESTRAS[@]}"; do echo "  - $s"; done
echo ""

# ==============================================================================
# 2. FUNCIÓN: ENSAMBLAR UNA MUESTRA
#    (se invoca más abajo con su salida completa redirigida a su propio log)
# ==============================================================================
ensamblar_muestra() {
    local sample="$1" r1="$2" r2="$3"
    local sample_dir="$WORK_DIR/$sample"
    local config_file="$sample_dir/config.txt"

    echo "=============================================================================="
    echo " Muestra: $sample"
    echo " R1: $r1"
    echo " R2: $r2"
    echo " Carpeta temporal: $sample_dir"
    echo "=============================================================================="

    mkdir -p "$sample_dir"

    # --- 2a. Generar config.txt de MaSuRCA para esta muestra ---
    cat > "$config_file" <<EOF
# =====================================================================
# MASURCA CONFIGURATION FILE - OPTIMIZED FOR ILLUMINA-ONLY (BACTERIA/VIRUS)
# Generado automáticamente para la muestra: $sample
# =====================================================================
DATA
# Illumina paired-end reads: <prefijo> <inserto medio> <desviación estándar> <R1> <R2>
# NOTA: '$PE_MEAN $PE_STDEV' se ajustó en las variables de configuración del script.
PE = pe $PE_MEAN $PE_STDEV $r1 $r2
# Librerías opcionales (JUMP, PACBIO, NANOPORE, OTHER, REFERENCE) se omiten:
# este es un proyecto Illumina-only.
END
PARAMETERS
# Configuración del k-mer para el grafo de de Bruijn ('auto' = MaSuRCA lo calcula)
GRAPH_KMER_SIZE = $GRAPH_KMER_SIZE
# OBLIGATORIO: debe ser 1 para ensamblados basados exclusivamente en Illumina
USE_LINKING_MATES = $USE_LINKING_MATES
# Tasa de error permitida en Celera Assembler (estándar para bacterias/virus: 0.25)
CA_PARAMETERS = cgwErrorRate=$CA_ERROR_RATE
# Intenta cerrar huecos (gaps) en los scaffolds usando lecturas Illumina PE
CLOSE_GAPS = $CLOSE_GAPS
# Límite de lecturas cargadas en memoria durante el gap-closing (evita bad_alloc)
MAX_READS_IN_MEMORY = $MAX_READS_IN_MEMORY
# Número de hilos de procesamiento
NUM_THREADS = $THREADS
# Tamaño del hash de Jellyfish (ver regla práctica en la configuración del script)
JF_SIZE = $JF_SIZE
# Desactivar ensambladores de lecturas largas / genomas eucariotas gigantes
SOAP_ASSEMBLY = $SOAP_ASSEMBLY
FLYE_ASSEMBLY = $FLYE_ASSEMBLY
# Parámetros legacy en entornos Illumina-only (desactivados o en valores por defecto)
EXTEND_JUMP_READS = $EXTEND_JUMP_READS
LIMIT_JUMP_COVERAGE = $LIMIT_JUMP_COVERAGE
LHE_COVERAGE = $LHE_COVERAGE
# Configuración de ejecución en clúster (desactivada para procesamiento local)
USE_GRID = $USE_GRID
GRID_ENGINE = $GRID_ENGINE
GRID_QUEUE = $GRID_QUEUE
GRID_BATCH_SIZE = $GRID_BATCH_SIZE
END
EOF

    cd "$sample_dir" || { echo "‼️  No se pudo entrar a '$sample_dir'"; return 1; }

    # --- 2b. Generar el script de ensamblado (assemble.sh) ---
    echo "[1/3] Generando script de ensamblado con MaSuRCA..."
    if ! masurca "$(basename "$config_file")"; then
        echo "‼️  'masurca' falló al generar assemble.sh para '$sample'."
        return 1
    fi

    if [ ! -f "assemble.sh" ]; then
        echo "‼️  No se generó 'assemble.sh' para '$sample'. Revisa el config.txt."
        return 1
    fi
    chmod +x assemble.sh

    # --- 2c. Ejecutar el ensamblado de novo ---
    echo "[2/3] Ejecutando ensamblado de novo (puede tardar varias horas)..."
    if ! ./assemble.sh; then
        echo "‼️  El ensamblado falló para '$sample'."
        return 1
    fi

    # --- 2d. Localizar y copiar el ensamblado final ---
    echo "[3/3] Buscando 'primary.genome.scf.fasta'..."
    local final_file
    final_file="$(find . -name "primary.genome.scf.fasta" | head -n 1)"
    if [ -z "$final_file" ]; then
        echo "‼️  No se encontró 'primary.genome.scf.fasta' para '$sample'."
        return 1
    fi

    cp "$final_file" "$RESULTS_DIR/${sample}_assembly.fasta"
    echo "✅ Ensamblado final copiado a: $RESULTS_DIR/${sample}_assembly.fasta"
}

# ==============================================================================
# 3. PROCESAR CADA MUESTRA (salida redirigida a su propio log)
# ==============================================================================
echo "=== [2] Ensamblando cada muestra ==="

EXITOSAS=()
FALLIDAS=()

for sample in "${!MUESTRAS[@]}"; do
    IFS='|' read -r r1 r2 <<< "${MUESTRAS[$sample]}"
    log_file="$LOGS_DIR/${sample}.log"

    echo "Procesando '$sample'... (log: $log_file)"

    # Todo lo que imprime ensamblar_muestra (incluyendo la salida de MaSuRCA)
    # se guarda en su propio archivo de log, no en la consola.
    if ( ensamblar_muestra "$sample" "$r1" "$r2" ) > "$log_file" 2>&1; then
        echo "  ✅ '$sample' completada."
        EXITOSAS+=("$sample")
    else
        echo "  ❌ '$sample' falló. Revisa: $log_file"
        FALLIDAS+=("$sample")
    fi
done

# ==============================================================================
# 4. RESUMEN FINAL DEL LOTE
# ==============================================================================
echo ""
echo "=============================================================================="
echo " RESUMEN DEL LOTE"
echo "=============================================================================="
echo "Completadas (${#EXITOSAS[@]}): ${EXITOSAS[*]:-ninguna}"
echo "Fallidas    (${#FALLIDAS[@]}): ${FALLIDAS[*]:-ninguna}"
echo "=============================================================================="
echo "Resultados en : $RESULTS_DIR"
echo "Logs en       : $LOGS_DIR"
echo "=============================================================================="
