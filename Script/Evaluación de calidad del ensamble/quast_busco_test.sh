#!/bin/bash
# =====================================================================
# PIPELINE INTEGRADO DE EVALUACIÓN DE ENSAMBLADO (QUAST + BUSCO)
# =====================================================================
set -e

# --- INICIALIZACIÓN DE CONDA ---
CONDA_BASE=$(conda info --base 2>/dev/null || echo "$HOME/miniconda3")
if [ -f "$CONDA_BASE/etc/profile.d/conda.sh" ]; then
    source "$CONDA_BASE/etc/profile.d/conda.sh"
else
    eval "$(conda shell.bash hook)"
fi

# Configuración general
ASSEMBLY_FILE="CA/primary.genome.scf.fasta" # Cambiar o asegurar la ruta de tu FASTA
REFERENCE="" 
QUAST_OUTPUT_DIR="quast_results"
BUSCO_OUTPUT_DIR="busco_results"
THREADS=8
BUSCO_LINEAGE="bacteria_odb12.2"

# Verificar que el archivo de ensamblado exista antes de iniciar
if [ ! -f "$ASSEMBLY_FILE" ]; then
    if [ -f "final.genome.scf.fasta" ]; then
        ASSEMBLY_FILE="final.genome.scf.fasta"
    elif [ -f "Test.fasta" ]; then
        ASSEMBLY_FILE="Test.fasta"
    else
        echo "ERROR: No se encontró el archivo de ensamblado ($ASSEMBLY_FILE)."
        exit 1
    fi
fi

echo "====================================================================="
echo "[1/4] Ejecutando QUAST en el entorno quast_env..."
echo "====================================================================="

conda activate quast_env

QUAST_CMD="quast.py $ASSEMBLY_FILE -o $QUAST_OUTPUT_DIR -t $THREADS --min-contig 500"
if [ -n "$REFERENCE" ] && [ -f "$REFERENCE" ]; then
    QUAST_CMD="$QUAST_CMD -r $REFERENCE"
fi

$QUAST_CMD

conda deactivate

echo ""
echo "====================================================================="
echo "[2/4] Ejecutando BUSCO en el entorno busco_env..."
echo "====================================================================="

conda activate busco_env

# Borrar directorio previo de BUSCO si existe para evitar conflictos de sobreescritura
rm -rf "$BUSCO_OUTPUT_DIR"

busco -i "$ASSEMBLY_FILE" \
      -m genome \
      -o "$BUSCO_OUTPUT_DIR" \
      -c "$THREADS" \
      -l "$BUSCO_LINEAGE"

conda deactivate

echo ""
echo "====================================================================="
echo "[3/4] Extrayendo métricas de QUAST y BUSCO..."
echo "====================================================================="

REPORT_TXT="$QUAST_OUTPUT_DIR/report.txt"
if [ ! -f "$REPORT_TXT" ]; then
    echo "ERROR: No se encontró el reporte de QUAST en $REPORT_TXT"
    exit 1
fi

# Extraer métricas clave de QUAST
TOTAL_LENGTH=$(awk -F'|' '/^Total length \(>= 0 bp\)/ {print $2}' "$REPORT_TXT" | tr -d ' ')
N50=$(awk -F'|' '/^N50/ {print $2}' "$REPORT_TXT" | tr -d ' ')
NUM_CONTIGS=$(awk -F'|' '/^# contigs \(>= 0 bp\)/ {print $2}' "$REPORT_TXT" | tr -d ' ')
NS_100KB=$(awk -F'|' '/^# N'\''s per 100 kbp/ {print $2}' "$REPORT_TXT" | tr -d ' ')

N50_INT=${N50%.*}
CONTIGS_INT=${NUM_CONTIGS%.*}

echo "Métricas de QUAST:"
echo " - Tamaño Total : $TOTAL_LENGTH pb"
echo " - N50          : $N50 pb"
echo " - Contigs      : $NUM_CONTIGS"
echo " - N's / 100 kb : $NS_100KB"

# Buscar dinámicamente el archivo short_summary de BUSCO generado
BUSCO_SUMMARY=$(find "$BUSCO_OUTPUT_DIR" -name "short_summary*.txt" | head -n 1)

BUSCO_C="N/A"
BUSCO_S="N/A"
BUSCO_D="N/A"
BUSCO_COMPLETE_INT=0

if [ -f "$BUSCO_SUMMARY" ]; then
    BUSCO_C=$(grep -oP 'C:\K[0-9.]+(?=%|\s)' "$BUSCO_SUMMARY" | head -n 1 || echo "0")
    BUSCO_S=$(grep -oP 'S:\K[0-9.]+(?=%|\s)' "$BUSCO_SUMMARY" | head -n 1 || echo "0")
    BUSCO_D=$(grep -oP 'D:\K[0-9.]+(?=%|\s)' "$BUSCO_SUMMARY" | head -n 1 || echo "0")
    BUSCO_COMPLETE_INT=${BUSCO_C%.*}
    
    echo ""
    echo "Métricas de BUSCO ($BUSCO_LINEAGE):"
    echo " - Completitud (C)      : ${BUSCO_C}%"
    echo " - Copia Única (S)      : ${BUSCO_S}%"
    echo " - Duplicados (D)       : ${BUSCO_D}%"
else
    echo ""
    echo "ADVERTENCIA: No se pudo localizar el archivo de resumen de BUSCO."
fi

echo ""
echo "====================================================================="
echo "[4/4] EVALUACIÓN INTEGRADA DE CALIDAD"
echo "====================================================================="

SCORE=0
WARNINGS=()

# Evaluación de N50
if [ "$N50_INT" -ge 100000 ]; then
    echo "  [OK] N50 ($N50 pb) - Excelente continuidad para genoma bacteriano."
    SCORE=$((SCORE+2))
elif [ "$N50_INT" -ge 30000 ]; then
    echo "  [OK] N50 ($N50 pb) - Continuidad aceptable para datos Illumina."
    SCORE=$((SCORE+1))
else
    WARNINGS+=("N50 bajo ($N50 pb). Ensamblado fragmentado.")
fi

# Evaluación de Contigs
if [ "$CONTIGS_INT" -le 50 ]; then
    echo "  [OK] Número de contigs ($NUM_CONTIGS) - Bajo nivel de fragmentación."
    SCORE=$((SCORE+2))
elif [ "$CONTIGS_INT" -le 150 ]; then
    echo "  [MEDIO] Número de contigs ($NUM_CONTIGS) - Fragmentación moderada."
    SCORE=$((SCORE+1))
else
    WARNINGS+=("Número elevado de contigs ($NUM_CONTIGS).")
fi

# Evaluación de BUSCO
if [ "$BUSCO_COMPLETE_INT" -ge 95 ]; then
    echo "  [OK] BUSCO (${BUSCO_C}%) - Integridad génica completa y excelente."
    SCORE=$((SCORE+2))
elif [ "$BUSCO_COMPLETE_INT" -ge 80 ]; then
    echo "  [MEDIO] BUSCO (${BUSCO_C}%) - Integridad génica aceptable."
    SCORE=$((SCORE+1))
else
    WARNINGS+=("BUSCO bajo (${BUSCO_C}%). Falta información génica conservada.")
fi

echo ""
echo "---------------------------------------------------------------------"
echo "VERDICTO FINAL DE CALIDAD:"
if [ "$SCORE" -ge 5 ]; then
    echo " EXCELENTE ENSAMBLADO: Genoma bacteriano de alta calidad (Continuidad y BUSCO óptimos)."
elif [ "$SCORE" -ge 3 ]; then
    echo " ENSAMBLADO BUENO / ACEPTABLE: Apto para análisis downstream."
    for w in "${WARNINGS[@]}"; do echo "   - $w"; done
else
    echo " ENSAMBLADO DEFICIENTE / REVISAR"
    for w in "${WARNINGS[@]}"; do echo "   - $w"; done
fi
echo "---------------------------------------------------------------------"
