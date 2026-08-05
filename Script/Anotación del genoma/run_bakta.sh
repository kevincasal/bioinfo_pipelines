#!/bin/bash

# ==============================================================================
# ------------------------------------------------------------------------------
# Script:          run_bakta.sh
# Descripción:     Automatización de la anotación genómica con Bakta.
#                  Activa el entorno conda 'bakta_env', descarga la base de
#                  datos (light o full) si no existe, y ejecuta la anotación
#                  sobre un genoma ensamblado (.fasta).
# ------------------------------------------------------------------------------
# AUTOR:           [KEVIN JOSUE CASAL ARROYO]
# CARGO:           [ANALISTA ZONAL DE LABORATORIO DE VIGILANCIA EPIDEMIOLÓGICA Y REFERENCIA NACIONAL 2 / Especialista en Bioinformática]
# DEPARTAMENTO:    [Cordinación zonal 9-INSPI]
# CONTACTO / EMAIL: [kevincasal0@gmail.com]
# FECHA:           Agosto 2026
# VERSIÓN:         1.0.0
# ------------------------------------------------------------------------------
# USO:
#   ./run_bakta.sh -i genoma.fasta [opciones]
#
# OPCIONES:
#   -i, --input       Ruta al archivo FASTA del genoma a anotar (obligatorio)
#   -o, --output       Carpeta de resultados (default: ./bakta_results)
#   -t, --threads       Número de procesadores a usar (default: 8)
#   -d, --db-path       Ruta donde está o se descargará la base de datos
#                       (default: $HOME/bakta_db)
#       --db-type       Tipo de base de datos: light | full
#                       (si no se especifica, se preguntará interactivamente)
#       --force-download  Fuerza la descarga de la DB aunque ya exista
#   -e, --env           Nombre del entorno conda (default: bakta_env)
#   -h, --help          Muestra esta ayuda
#
# EJEMPLOS:
#   ./run_bakta.sh -i ensamble.fasta
#   ./run_bakta.sh -i ensamble.fasta --db-type light -t 16 -o resultados_muestra1
# ==============================================================================

set -euo pipefail

# --- Valores por defecto ---
INPUT_FASTA=""
OUTPUT_DIR="./bakta_results"
THREADS=8
DB_PATH="$HOME/bakta_db"
DB_TYPE=""
FORCE_DOWNLOAD=false
ENV_NAME="bakta_env"
LOG_FILE="./run_bakta_$(date +%Y%m%d_%H%M%S).log"

# --- Función de ayuda ---
mostrar_ayuda() {
    grep -E '^#( |$)' "$0" | sed -n '/USO:/,/^# -----/p' | sed 's/^# \{0,1\}//;/^-----/d'
    exit 0
}

# --- Parseo de argumentos ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        -i|--input)          INPUT_FASTA="$2"; shift 2 ;;
        -o|--output)         OUTPUT_DIR="$2"; shift 2 ;;
        -t|--threads)        THREADS="$2"; shift 2 ;;
        -d|--db-path)        DB_PATH="$2"; shift 2 ;;
        --db-type)           DB_TYPE="$2"; shift 2 ;;
        --force-download)    FORCE_DOWNLOAD=true; shift ;;
        -e|--env)             ENV_NAME="$2"; shift 2 ;;
        -h|--help)            mostrar_ayuda ;;
        *) echo "Opción desconocida: $1"; mostrar_ayuda ;;
    esac
done

exec > >(tee -a "$LOG_FILE") 2>&1
trap 'echo "‼️  ERROR en la línea $LINENO. Revisa el log: $LOG_FILE"' ERR

echo "=============================================================================="
echo " Automatización de Anotación Genómica con Bakta"
echo " INSPI 2026"
echo "=============================================================================="

# --- Validación: archivo de entrada obligatorio ---
if [ -z "$INPUT_FASTA" ]; then
    echo "‼️  Debes especificar el genoma de entrada con -i/--input"
    mostrar_ayuda
fi

if [ ! -f "$INPUT_FASTA" ]; then
    echo "‼️  El archivo '$INPUT_FASTA' no existe."
    exit 1
fi

# --- Validación / selección interactiva del tipo de base de datos ---
if [ -z "$DB_TYPE" ]; then
    echo "¿Qué tipo de base de datos de Bakta deseas usar?"
    select opcion in "light" "full"; do
        case "$opcion" in
            light|full) DB_TYPE="$opcion"; break ;;
            *) echo "Opción inválida, elige 1 (light) o 2 (full)." ;;
        esac
    done
else
    case "$DB_TYPE" in
        light|full) ;;
        *) echo "‼️  --db-type debe ser 'light' o 'full', recibido: '$DB_TYPE'"; exit 1 ;;
    esac
fi

echo "--- Configuración ---"
echo "  Genoma de entrada : $INPUT_FASTA"
echo "  Carpeta de salida : $OUTPUT_DIR"
echo "  Hilos (threads)   : $THREADS"
echo "  Ruta de la DB     : $DB_PATH"
echo "  Tipo de DB        : $DB_TYPE"
echo "  Entorno conda     : $ENV_NAME"
echo "----------------------"

# --- Paso 1: Localizar e inicializar Conda/Mamba ---
echo "=== [Paso 1] Activando entorno conda '$ENV_NAME' ==="

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
conda activate "$ENV_NAME"

# --- Paso 2: Descargar la base de datos (si hace falta) ---
echo "=== [Paso 2] Verificando base de datos de Bakta ==="

DB_READY=false
if [ -f "$DB_PATH/version.json" ] && [ "$FORCE_DOWNLOAD" = false ]; then
    echo "La base de datos ya existe en '$DB_PATH'. Omitiendo descarga."
    DB_READY=true
fi

if [ "$DB_READY" = false ]; then
    echo "Descargando base de datos tipo '$DB_TYPE' en '$DB_PATH' ..."
    mkdir -p "$DB_PATH"
    bakta_db download --output "$DB_PATH" --type "$DB_TYPE"
fi

# --- Paso 3: Ejecutar Bakta ---
echo "=== [Paso 3] Ejecutando anotación con Bakta ==="
mkdir -p "$OUTPUT_DIR"

bakta \
    --db "$DB_PATH" \
    --output "$OUTPUT_DIR" \
    --threads "$THREADS" \
    "$INPUT_FASTA"

echo "=============================================================================="
echo " Anotación completada exitosamente."
echo " Resultados en: $OUTPUT_DIR"
echo " Log completo:  $LOG_FILE"
echo "=============================================================================="
