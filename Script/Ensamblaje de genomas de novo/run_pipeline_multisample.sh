#!/bin/bash

# ==============================================================================
# ------------------------------------------------------------------------------
# Script:          run_pipeline.sh
# Descripción:     Automatiza el ENSAMBLADO DE NOVO con MaSuRCA para una o
#                  varias muestras (lecturas paired-end) a la vez. Este
#                  script SOLO ensambla; la evaluación (QUAST/BUSCO) y la
#                  anotación (Bakta) se corren después, por separado.
# ------------------------------------------------------------------------------
# AUTOR:           [KEVIN JOSUE CASAL ARROYO]
# CARGO:           [ANALISTA ZONAL DE LABORATORIO DE VIGILANCIA EPIDEMIOLÓGICA Y REFERENCIA NACIONAL 2 / Especialista en Bioinformática]
# DEPARTAMENTO:    [Cordinación zonal 9-INSPI]
# CONTACTO / EMAIL: [kevincasal0@gmail.com]
# FECHA:           Agosto 2026
# VERSIÓN:         2.0.0 (multi-muestra, carpeta de proyecto interactiva)
# ------------------------------------------------------------------------------
# USO:
#   ./run_pipeline.sh [opciones]
#
# OPCIONES (todas opcionales; si no las pasas, el script pregunta):
#   -l, --location       "escritorio" o "documentos" (dónde crear el proyecto)
#   -n, --project-name    Nombre de la carpeta del proyecto
#   -y, --yes            Omite la confirmación de "ya coloqué mis secuencias"
#                        (úsalo solo si ya sabes que los archivos ya están ahí)
#   -t, --threads        Hilos para MaSuRCA (default: 8)
#       --pe-mean        Tamaño medio de inserto de las lecturas PE (default: 300)
#       --pe-stdev       Desviación estándar del inserto (default: 50)
#       --jf-size        Tamaño del hash de Jellyfish para MaSuRCA
#                        (default: 200000000; súbelo para genomas más grandes)
#       --close-gaps     1 = cerrar gaps del ensamblado (default), 0 = omitir
#                        este paso (útil si tu máquina tiene poca RAM y falla
#                        con "std::bad_alloc" durante el gap-closing)
#   -e, --env            Nombre del entorno conda (default: masurca_env)
#   -h, --help           Muestra esta ayuda
#
# EJEMPLOS:
#   ./run_pipeline.sh
#   ./run_pipeline.sh -l escritorio -n lote_agosto2026 -y -t 16
#   nohup ./run_pipeline.sh -l escritorio -n lote_agosto2026 -y > /dev/null 2>&1 &
# ------------------------------------------------------------------------------
# DERECHOS DE AUTOR Y LICENCIA:
# (c) 2026 [Tu Nombre completo] / INSPI. Todos los derechos reservados.
# Desarrollado para uso institucional en las plataformas del INSPI.
# Prohibida su redistribución o modificación no autorizada sin citar al autor.
# ==============================================================================

set -uo pipefail
# Nota: no se usa 'set -e' a nivel global a propósito. Con varias muestras en
# un mismo lote, un fallo en una no debe abortar el procesamiento de las demás;
# los errores se controlan explícitamente por muestra (ver procesar_muestra()).

# --- Valores por defecto ---
LOCATION_ARG=""
PROJECT_NAME_ARG=""
SKIP_CONFIRM=false
THREADS=8
PE_MEAN=300
PE_STDEV=50
JF_SIZE=200000000
CLOSE_GAPS=1
ENV_NAME="masurca_env"

mostrar_ayuda() {
    grep -E '^#( |$)' "$0" | sed -n '/USO:/,/^# -----/p' | sed 's/^# \{0,1\}//;/^-----/d'
    exit 0
}

# --- Parseo de argumentos ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        -l|--location)       LOCATION_ARG="$2"; shift 2 ;;
        -n|--project-name)    PROJECT_NAME_ARG="$2"; shift 2 ;;
        -y|--yes)             SKIP_CONFIRM=true; shift ;;
        -t|--threads)         THREADS="$2"; shift 2 ;;
        --pe-mean)            PE_MEAN="$2"; shift 2 ;;
        --pe-stdev)           PE_STDEV="$2"; shift 2 ;;
        --jf-size)            JF_SIZE="$2"; shift 2 ;;
        --close-gaps)         CLOSE_GAPS="$2"; shift 2 ;;
        -e|--env)              ENV_NAME="$2"; shift 2 ;;
        -h|--help)             mostrar_ayuda ;;
        *) echo "Opción desconocida: $1"; mostrar_ayuda ;;
    esac
done

echo "=============================================================================="
echo " Automatización de Ensamblado de Novo con MaSuRCA (multi-muestra)"
echo " INSPI 2026"
echo "=============================================================================="

# --- Paso 0: Activar entorno conda de MaSuRCA automáticamente ---
echo ""
echo "=== [Paso 0] Activando entorno '$ENV_NAME' ==="

if command -v conda >/dev/null 2>&1; then
    CONDA_BASE="$(conda info --base)"
elif [ -d "$HOME/miniforge3" ]; then
    CONDA_BASE="$HOME/miniforge3"
elif [ -d "$HOME/miniconda3" ]; then
    CONDA_BASE="$HOME/miniconda3"
elif [ -d "$HOME/anaconda3" ]; then
    CONDA_BASE="$HOME/anaconda3"
else
    echo "‼️  No se pudo localizar una instalación de Conda/Miniforge."
    exit 1
fi

source "$CONDA_BASE/etc/profile.d/conda.sh"

if ! conda activate "$ENV_NAME" 2>/dev/null; then
    echo "‼️  No se pudo activar el entorno '$ENV_NAME'."
    echo "    ¿Ya corriste setup_bioinfo_env.sh? Ese script crea este entorno."
    exit 1
fi
echo "Entorno '$ENV_NAME' activado correctamente."

# --- Paso 1: Elegir ubicación y nombre de la carpeta del proyecto ---
echo ""
echo "=== [Paso 1] Carpeta del proyecto ==="

if [ -n "$LOCATION_ARG" ]; then
    case "${LOCATION_ARG,,}" in
        escritorio|desktop) UBICACION="Escritorio" ;;
        documentos|documents) UBICACION="Documentos" ;;
        *) echo "‼️  --location debe ser 'escritorio' o 'documentos'"; exit 1 ;;
    esac
else
    echo "¿Dónde deseas crear la carpeta del proyecto?"
    select UBICACION in "Escritorio" "Documentos"; do
        case "$UBICACION" in
            Escritorio|Documentos) break ;;
            *) echo "Opción inválida, elige 1 (Escritorio) o 2 (Documentos)." ;;
        esac
    done
fi

if [ "$UBICACION" = "Escritorio" ]; then
    if [ -d "$HOME/Desktop" ]; then BASE_DIR="$HOME/Desktop";
    elif [ -d "$HOME/Escritorio" ]; then BASE_DIR="$HOME/Escritorio";
    else BASE_DIR="$HOME/Desktop"; fi
else
    if [ -d "$HOME/Documents" ]; then BASE_DIR="$HOME/Documents";
    elif [ -d "$HOME/Documentos" ]; then BASE_DIR="$HOME/Documentos";
    else BASE_DIR="$HOME/Documents"; fi
fi
mkdir -p "$BASE_DIR"

if [ -n "$PROJECT_NAME_ARG" ]; then
    PROJECT_NAME="$PROJECT_NAME_ARG"
else
    read -rp "Nombre para la carpeta del proyecto (ej. 'lote_agosto2026'): " PROJECT_NAME
fi
PROJECT_NAME="${PROJECT_NAME// /_}"

if [ -z "$PROJECT_NAME" ]; then
    echo "‼️  El nombre del proyecto no puede estar vacío."
    exit 1
fi

PROJECT_DIR="$BASE_DIR/$PROJECT_NAME"
SEQ_DIR="$PROJECT_DIR/secuencias"
RESULTS_DIR="$PROJECT_DIR/ensamblados_finales"

mkdir -p "$SEQ_DIR" "$RESULTS_DIR"

# A partir de aquí el log vive DENTRO del proyecto, no en la carpeta donde
# está el script (evita que ~/Downloads se llene de logs de distintos lotes).
mkdir -p "$PROJECT_DIR/logs"
LOG_FILE="$PROJECT_DIR/logs/run_pipeline_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo ""
echo "Carpeta del proyecto : $PROJECT_DIR"
echo "  - Coloca aquí tus lecturas (.fastq.gz, pares R1/R2): $SEQ_DIR"
echo "  - Los ensamblados finales se copiarán a             : $RESULTS_DIR"

# --- Paso 2: Confirmación de que las secuencias ya están en su lugar ---
if [ "$SKIP_CONFIRM" = false ]; then
    echo ""
    while true; do
        read -rp "¿Ya colocaste tus secuencias en '$SEQ_DIR'? (s/n): " resp
        case "${resp,,}" in
            s|si)
                if [ -z "$(ls -A "$SEQ_DIR" 2>/dev/null)" ]; then
                    echo "⚠️  La carpeta '$SEQ_DIR' todavía está vacía. Copia los archivos y vuelve a responder."
                else
                    break
                fi
                ;;
            n|no)
                echo "    Cuando termines de copiar los archivos, escribe 's' para continuar."
                ;;
            *)
                echo "    Responde 's' (sí) o 'n' (no)."
                ;;
        esac
    done
else
    if [ -z "$(ls -A "$SEQ_DIR" 2>/dev/null)" ]; then
        echo "‼️  Usaste --yes pero '$SEQ_DIR' está vacía. No hay nada que ensamblar."
        exit 1
    fi
fi

# --- Paso 3: Detectar pares de lecturas (una muestra = un par R1/R2) ---
echo ""
echo "=== [Paso 2] Detectando muestras en '$SEQ_DIR' ==="

declare -A MUESTRAS   # nombre_muestra -> "ruta_r1|ruta_r2"

mapfile -t R1_CANDIDATOS < <(find "$SEQ_DIR" -maxdepth 1 -type f \
    \( -iname "*_R1*.fastq.gz" -o -iname "*_R1*.fq.gz" \
       -o -iname "*_1.fastq.gz" -o -iname "*_1.fq.gz" \) | sort)

for r1 in "${R1_CANDIDATOS[@]}"; do
    fname="$(basename "$r1")"
    r2=""
    sample=""

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
        echo "⚠️  No se encontró el par R2 correspondiente a '$fname'. Se omite."
    fi
done

if [ ${#MUESTRAS[@]} -eq 0 ]; then
    echo "‼️  No se detectaron pares de lecturas válidos en '$SEQ_DIR'."
    echo "    Nombres reconocidos: muestra_R1.fastq.gz/muestra_R2.fastq.gz,"
    echo "    muestra_r1.fastq.gz/muestra_r2.fastq.gz, o muestra_1.fastq.gz/muestra_2.fastq.gz"
    exit 1
fi

echo "Muestras detectadas (${#MUESTRAS[@]}):"
for s in "${!MUESTRAS[@]}"; do echo "  - $s"; done

# --- Función: ensambla UNA muestra; nunca mata el script si falla ---
procesar_muestra() {
    local sample="$1" sample_dir="$2" config_file="$3" results_dir="$4"

    (
        cd "$sample_dir" || exit 1

        echo "  [1/3] Generando script de ensamblado con MaSuRCA..."
        masurca "$(basename "$config_file")" || exit 1

        if [ ! -f "assemble.sh" ]; then
            echo "  ‼️  No se generó 'assemble.sh' para '$sample'."
            exit 1
        fi
        chmod +x assemble.sh

        echo "  [2/3] Ejecutando ensamblado de novo (esto puede tardar horas)..."
        ./assemble.sh || exit 1

        echo "  [3/3] Buscando 'primary.genome.scf.fasta'..."
        FINAL="$(find . -name "primary.genome.scf.fasta" | head -n 1)"
        if [ -z "$FINAL" ]; then
            echo "  ‼️  No se encontró 'primary.genome.scf.fasta' para '$sample'."
            exit 1
        fi

        cp "$FINAL" "$results_dir/${sample}.fasta"
        echo "  ✅ Copiado a: $results_dir/${sample}.fasta"
    )
}

# --- Paso 4: Ensamblar cada muestra detectada ---
EXITOSAS=()
FALLIDAS=()

for SAMPLE in "${!MUESTRAS[@]}"; do
    IFS='|' read -r R1 R2 <<< "${MUESTRAS[$SAMPLE]}"
    SAMPLE_DIR="$PROJECT_DIR/$SAMPLE"
    mkdir -p "$SAMPLE_DIR"
    CONFIG_FILE="$SAMPLE_DIR/masurca_config.txt"

    echo ""
    echo "=============================================================================="
    echo " Procesando muestra: $SAMPLE"
    echo " R1: $R1"
    echo " R2: $R2"
    echo " Carpeta de trabajo (output): $SAMPLE_DIR"
    echo "=============================================================================="

    cat > "$CONFIG_FILE" <<EOF
DATA
PE= pe $PE_MEAN $PE_STDEV $R1 $R2
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

    if procesar_muestra "$SAMPLE" "$SAMPLE_DIR" "$CONFIG_FILE" "$RESULTS_DIR"; then
        EXITOSAS+=("$SAMPLE")
    else
        FALLIDAS+=("$SAMPLE")
        echo "⚠️  La muestra '$SAMPLE' falló. Se continúa con la siguiente..."
    fi
done

# --- Resumen final ---
echo ""
echo "=============================================================================="
echo " RESUMEN DEL LOTE"
echo "=============================================================================="
echo "Ensambladas correctamente (${#EXITOSAS[@]}):"
for s in "${EXITOSAS[@]}"; do echo "  ✅ $s -> $RESULTS_DIR/${s}.fasta"; done

if [ ${#FALLIDAS[@]} -gt 0 ]; then
    echo ""
    echo "Con errores (${#FALLIDAS[@]}):"
    for s in "${FALLIDAS[@]}"; do echo "  ❌ $s (revisa '$PROJECT_DIR/$s' y el log)"; done
fi

echo ""
echo "Log completo: $LOG_FILE"
echo "=============================================================================="
echo ""
echo "Sugerencia para lotes grandes (corre en segundo plano sin preguntas):"
echo "  nohup ./run_pipeline.sh -l ${UBICACION,,} -n $PROJECT_NAME -y > /dev/null 2>&1 &"
