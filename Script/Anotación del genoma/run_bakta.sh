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
#       --force-output    Permite sobrescribir la carpeta de salida si ya existe
#       --skip-amr-update Omite la sincronización automática de AMRFinderPlus
#       --max-retries    Intentos de descarga ante fallos de red (default: 5)
#       --retry-delay    Segundos de espera entre reintentos (default: 20, crece con backoff)
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
FORCE_OUTPUT=false
SKIP_AMR_UPDATE=false
ENV_NAME="bakta_env"
MAX_RETRIES=5
RETRY_DELAY=20   # segundos; crece con cada intento (backoff)
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
        --force-output)      FORCE_OUTPUT=true; shift ;;
        --skip-amr-update)    SKIP_AMR_UPDATE=true; shift ;;
        --max-retries)        MAX_RETRIES="$2"; shift 2 ;;
        --retry-delay)        RETRY_DELAY="$2"; shift 2 ;;
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
    select opcion in "light" "full" "skip"; do
        case "$opcion" in
            light|full|skip) DB_TYPE="$opcion"; break ;;
            *) echo "Opción inválida, elige 1 (light), 2 (full) o 3 (skip)." ;;
        esac
    done
else
    case "$DB_TYPE" in
        light|full|skip) ;;
        *) echo "‼️  --db-type debe ser 'light', 'full' o 'skip', recibido: '$DB_TYPE'"; exit 1 ;;
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

descargar_db_con_reintentos() {
    local intento=1
    local espera="$RETRY_DELAY"

    while [ "$intento" -le "$MAX_RETRIES" ]; do
        echo "Descargando base de datos tipo '$DB_TYPE' en '$DB_PATH' (intento $intento/$MAX_RETRIES) ..."

        # Limpiar restos de una descarga parcial/corrupta antes de reintentar
        rm -rf "$DB_PATH"
        mkdir -p "$DB_PATH"

        if bakta_db download --output "$DB_PATH" --type "$DB_TYPE"; then
            echo "✅ Descarga completada correctamente."
            return 0
        fi

        echo "⚠️  Falló el intento $intento (posible corte de red o timeout de Zenodo)."

        if [ "$intento" -eq "$MAX_RETRIES" ]; then
            echo "‼️  Se agotaron los $MAX_RETRIES intentos de descarga."
            echo "    Sugerencias:"
            echo "      - Verifica tu conexión a internet / VPN institucional."
            echo "      - Intenta en otro horario (Zenodo puede estar saturado)."
            echo "      - Vuelve a correr el script con --max-retries y --retry-delay más altos."
            return 1
        fi

        echo "    Reintentando en ${espera}s..."
        sleep "$espera"
        intento=$((intento + 1))
        espera=$((espera * 2))   # backoff exponencial
    done
}

if [ "$DB_TYPE" = "skip" ]; then
    echo "Descarga de base de datos omitida por el usuario."
elif [ "$DB_READY" = false ]; then
    if ! descargar_db_con_reintentos; then
        exit 1
    fi
fi

# --- Paso 2.5: Actualizar base de datos interna de AMRFinderPlus ---
# Bakta necesita que la DB de AMRFinderPlus (incluida en db-light/db-full)
# esté sincronizada con la versión instalada de 'amrfinder'; si no, falla
# más adelante con: "amrfinder error! error code: 1".
echo "=== [Paso 2.5] Sincronizando base de datos de AMRFinderPlus ==="
AMRFINDER_DB="$DB_PATH/amrfinderplus-db"
if [ "$SKIP_AMR_UPDATE" = false ] && [ -d "$AMRFINDER_DB" ]; then
    if amrfinder_update --force_update --database "$AMRFINDER_DB"; then
        echo "✅ AMRFinderPlus actualizado correctamente."
    else
        echo "⚠️  No se pudo actualizar AMRFinderPlus automáticamente."
        echo "    Puedes intentarlo manualmente con:"
        echo "    amrfinder_update --force_update --database $AMRFINDER_DB"
    fi
else
    echo "Se omite la actualización de AMRFinderPlus (--skip-amr-update o carpeta no encontrada)."
fi

# --- Paso 3: Ejecutar Bakta ---
echo "=== [Paso 3] Ejecutando anotación con Bakta ==="
# No se crea $OUTPUT_DIR de antemano: Bakta la crea él mismo y falla si ya existe.

BAKTA_ARGS=(--db "$DB_PATH" --output "$OUTPUT_DIR" --threads "$THREADS")
if [ "$FORCE_OUTPUT" = true ]; then
    BAKTA_ARGS+=(--force)
fi

bakta "${BAKTA_ARGS[@]}" "$INPUT_FASTA"

echo "=============================================================================="
echo " Anotación completada exitosamente."
echo " Resultados en: $OUTPUT_DIR"
echo " Log completo:  $LOG_FILE"
echo "=============================================================================="
