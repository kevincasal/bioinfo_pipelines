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
THREADS=8              # Hilos/núcleos a usar
PE_MEAN=300             # Tamaño medio del inserto de las lecturas paired-end
PE_STDEV=50             # Desviación estándar del inserto
JF_SIZE=200000000       # Tamaño del hash de Jellyfish (referencia: ~10x el tamaño esperado del genoma en pb)
CLOSE_GAPS=1            # 1 = cerrar gaps del ensamblado; 0 = omitir este paso
                        # (bájalo a 0 si tu máquina tiene poca RAM y falla con
                        #  "std::bad_alloc" durante el gap-closing)

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
    # PE = <nombre_libreria> <inserto_medio> <desviación_estándar> <R1> <R2>
    cat > "$config_file" <<EOF
DATA
PE= pe $PE_MEAN $PE_STDEV $r1 $r2
END

PARAMETERS
GRAPH_KMER_SIZE = auto
USE_LINKING_MATES = 1
LIMIT_JUMP_COVERAGE = 60
CA_PARAMETERS = cgwErrorRate=0.15
NUM_THREADS = $THREADS
JF_SIZE = $JF_SIZE
DO_HOMOPOLYMER_TRIM = 0
CLOSE_GAPS = $CLOSE_GAPS
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
