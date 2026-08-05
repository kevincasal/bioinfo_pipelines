#!/bin/bash

# ==============================================================================
# ------------------------------------------------------------------------------
# Script:          setup_bioinfo_env.sh
# Descripción:     Instalación de Conda y creación segmentada de entornos 
#                  bioinformáticos (FastQC, MultiQC, Kraken2, Shovill, 
#                  SPAdes, QUAST, Prokka, MaSuRCA).
# ------------------------------------------------------------------------------
# AUTOR:           [KEVIN JOSUE CASAL ARROYO]
# CARGO:           [ANALISTA ZONAL DE LABORATORIO DE VIGILANCIA EPIDEMIOLÓGICA Y REFERENCIA NACIONAL 2 / Especialista en Bioinformática]
# DEPARTAMENTO:    [Cordinación zonal 9-INSPI]
# CONTACTO / EMAIL: [kevincasal0@gmail.com]
# FECHA:           Agosto 2026
# VERSIÓN:         1.0.1
# ------------------------------------------------------------------------------
# DERECHOS DE AUTOR Y LICENCIA:
# (c) 2026 [Tu Nombre completo] / INSPI. Todos los derechos reservados.
# Desarrollado para uso institucional en las plataformas del INSPI.
# Prohibida su redistribución o modificación no autorizada sin citar al autor.
# ==============================================================================

set -e # Detener el script si ocurre un error irrecuperable

# --- BANNER DE AUTORÍA EN PANTALLA ---
echo "=============================================================================="
echo " Script de Automatización de Entornos Bioinformáticos"
echo " Desarrollado por: [Kevin Josue Casal ARROYO] <[kevincasal0@gmail.com]>"
echo " Versión 1.0.0 (2026)"
echo "=============================================================================="
sleep 2

CONDA_DIR="$HOME/miniconda3"

echo "=== [Paso 1] Descarga e Instalación de Miniconda ==="
cd ~
if [ ! -d "$CONDA_DIR" ]; then
    wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O miniconda.sh
    bash miniconda.sh -b -p $CONDA_DIR
    rm miniconda.sh
else
    echo "Miniconda ya está instalado en $CONDA_DIR. Omitiendo descarga."
fi

echo "=== [Paso 2] Carga Directa de Binarios de Conda en Memoria ==="
source "$CONDA_DIR/etc/profile.d/conda.sh"
conda activate base

echo "=== [Paso 3] Aceptación de TOS y Configuración de Canales Abiertos ==="
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main || true
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r || true

conda config --remove channels defaults || true
conda config --add channels conda-forge
conda config --add channels bioconda
conda config --set channel_priority strict

echo "=== [Paso 4] Actualización de Conda desde Conda-Forge ==="
conda update -n base -c conda-forge conda -y

source "$CONDA_DIR/etc/profile.d/conda.sh"
conda activate base

echo "=== [Paso 5 y 6] Creación e Instalación: FastQC ==="
conda create -n fastqc_env -y
conda run -n fastqc_env conda install -c bioconda -c conda-forge fastqc -y

echo "=== [Paso 7 y 8] Creación e Instalación: MultiQC ==="
conda create -n multiqc_env -y
conda run -n multiqc_env conda install -c bioconda -c conda-forge multiqc -y

echo "=== [Paso 9 y 10] Creación e Instalación: Kraken2 ==="
conda create -n kraken2_env -y
conda run -n kraken2_env conda install -c bioconda -c conda-forge kraken2 -y

echo "=== [Paso 11 y 12] Creación e Instalación: Shovill ==="
conda create -n shovill_bacterias_env -y
conda run -n shovill_bacterias_env conda install -c bioconda -c conda-forge shovill -y

echo "=== [Paso 13 y 14] Creación e Instalación: SPAdes ==="
conda create -n spades_env -y
conda run -n spades_env conda install -c bioconda -c conda-forge spades -y

echo "=== [Paso 15 y 16] Creación e Instalación: QUAST ==="
conda create -n quast_env -y
conda run -n quast_env conda install -c bioconda -c conda-forge quast -y

echo "=== [Paso 17 y 18] Creación e Instalación: Prokka ==="
conda create -n prokka_env -y
conda run -n prokka_env conda install -c bioconda -c conda-forge prokka -y

echo "=== [Paso 19 y 20] Creación e Instalación: MaSuRCA ==="
conda create -n masurca_env -y
conda run -n masurca_env conda install -c bioconda -c conda-forge masurca -y

echo "=============================================================================="
echo " Proceso completado exitosamente."
echo " Desarrollado por: [Kevin Josué Casal A.] | INSPI 2026"
echo "=============================================================================="
