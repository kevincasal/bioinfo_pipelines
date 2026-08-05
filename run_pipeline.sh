#!/bin/bash

# Salir inmediatamente si ocurre algún error
set -e

CONFIG_FILE="masurca_config.txt"
ASSEMBLE_SCRIPT="assemble.sh"

echo "[1/3] Generando el script de ensamblado con MaSuRCA..."

# 1. Ejecutar masurca para generar assemble.sh
masurca "$CONFIG_FILE"

# 2. Verificar que assemble.sh realmente se generó
if [ -f "$ASSEMBLE_SCRIPT" ]; then
    echo "[2/3] Script $ASSEMBLE_SCRIPT generado exitosamente."
    
    # Asegurar permisos de ejecución
    chmod +x "$ASSEMBLE_SCRIPT"
    
    echo "[3/3] Iniciando el proceso de ensamblado de novo..."
    
    # 3. Ejecutar el ensamblado
    ./"$ASSEMBLE_SCRIPT"
else
    echo "ERROR: No se pudo generar el archivo $ASSEMBLE_SCRIPT. Revisa los parámetros en $CONFIG_FILE."
    exit 1
fi
