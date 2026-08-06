#!/bin/bash

# ==============================================================================
# ------------------------------------------------------------------------------
# Script:          setup_bioinfo_env.sh
# Descripción:     Instalación de Miniforge (Conda + Mamba) y creación 
#                  segmentada de entornos bioinformáticos (FastQC, MultiQC, 
#                  Kraken2, Shovill, BUSCO, QUAST, Bakta, MaSuRCA).
# ------------------------------------------------------------------------------
# AUTOR:           [KEVIN JOSUE CASAL ARROYO]
# CARGO:           [ANALISTA ZONAL DE LABORATORIO DE VIGILANCIA EPIDEMIOLÓGICA Y REFERENCIA NACIONAL 2 / Especialista en Bioinformática]
# DEPARTAMENTO:    [Cordinación zonal 9-INSPI]
# CONTACTO / EMAIL: [kevincasal0@gmail.com]
# FECHA:           Agosto 2026
# VERSIÓN:         1.2.0 (migrado a Mamba/Miniforge)
# ==============================================================================

set -euo pipefail  # Detener el script ante errores, variables no definidas o fallos en pipes

# --- BANNER DE AUTORÍA EN PANTALLA ---
echo "=============================================================================="
echo " Script de Automatización de Entornos Bioinformáticos (Mamba/Miniforge)"
echo " Desarrollado por: [Kevin Josue Casal ARROYO] <[kevincasal0@gmail.com]>"
echo " Versión 1.2.0 (2026)"
echo "=============================================================================="
sleep 2

CONDA_DIR="$HOME/miniforge3"
LOG_FILE="$HOME/setup_bioinfo_env_$(date +%Y%m%d_%H%M%S).log"

# Registrar toda la salida en un log, además de mostrarla en pantalla
exec > >(tee -a "$LOG_FILE") 2>&1

# --- Trap para reportar en qué línea falló el script, si algo sale mal ---
trap 'echo "‼️  ERROR en la línea $LINENO. Revisa el log: $LOG_FILE"' ERR

echo "=== [Paso 1] Descarga e Instalación de Miniforge (incluye Mamba) ==="
cd ~
if [ ! -d "$CONDA_DIR" ]; then
    ARCH="$(uname -m)"
    INSTALLER="Miniforge3-Linux-${ARCH}.sh"
    wget "https://github.com/conda-forge/miniforge/releases/latest/download/${INSTALLER}" -O miniforge.sh
    bash miniforge.sh -b -p "$CONDA_DIR"
    rm miniforge.sh
else
    echo "Miniforge ya está instalado en $CONDA_DIR. Omitiendo descarga."
fi

echo "=== [Paso 2] Carga de Conda/Mamba en la Sesión Actual ==="
source "$CONDA_DIR/etc/profile.d/conda.sh"
source "$CONDA_DIR/etc/profile.d/mamba.sh"
conda activate base

echo "=== [Paso 3] Configuración de Canales ==="
# Miniforge ya usa conda-forge por defecto (sin canal 'defaults' de Anaconda,
# por lo que no se requiere aceptar TOS de Anaconda).
conda config --add channels conda-forge
conda config --add channels bioconda
conda config --set channel_priority strict

echo "=== [Paso 4] Actualización de Mamba y Conda base ==="
mamba update -n base -c conda-forge mamba conda -y

# --- Función auxiliar para crear e instalar un entorno de forma uniforme ---
# Uso: crear_entorno <nombre_env> <paquete_conda> [restricción_python]
crear_entorno() {
    local env_name="$1"
    local package="$2"
    local python_spec="${3:-}"   # Ej: "python=3.11" (opcional)

    echo "--- Creando entorno: $env_name ${python_spec:+(fijando $python_spec)} ---"

    if mamba env list | grep -qE "^${env_name}\s"; then
        echo "El entorno '$env_name' ya existe. Omitiendo creación."
    else
        if [ -n "$python_spec" ]; then
            mamba create -n "$env_name" -y "$python_spec"
        else
            mamba create -n "$env_name" -y
        fi
    fi

    echo "--- Instalando '$package' en $env_name ---"
    mamba install -n "$env_name" -c bioconda -c conda-forge "$package" -y

    echo "--- Verificando instalación de $package ---"
    conda run -n "$env_name" "$package" --version 2>/dev/null \
        || conda run -n "$env_name" "$package" --help >/dev/null 2>&1 \
        || echo "  (No se pudo verificar automáticamente la versión de $package, revisa manualmente)"
}

echo "=== [Paso 5-6] FastQC ==="
crear_entorno "fastqc_env" "fastqc"

echo "=== [Paso 7-8] MultiQC ==="
crear_entorno "multiqc_env" "multiqc"

echo "=== [Paso 9-10] Kraken2 ==="
crear_entorno "kraken2_env" "kraken2"

echo "=== [Paso 11-12] Shovill ==="
crear_entorno "shovill_bacterias_env" "shovill"

echo "=== [Paso 13-14] BUSCO (requiere Python 3.11) ==="
crear_entorno "busco_env" "busco" "python=3.11"

echo "=== [Paso 15-16] QUAST ==="
crear_entorno "quast_env" "quast"

echo "=== [Paso 17-18] Bakta (requiere Python 3.11) ==="
crear_entorno "bakta_env" "bakta" "python=3.11"

echo "=== [Paso 19-20] MaSuRCA ==="
crear_entorno "masurca_env" "masurca"

source ~/miniforge3/etc/profile.d/conda.sh && conda init bash && source ~/.bashrc && conda env list

echo "=============================================================================="
echo " Proceso completado exitosamente."
echo " Log completo guardado en: $LOG_FILE"
echo " Desarrollado por: [Kevin Josué Casal A.] | 
echo "=============================================================================="
