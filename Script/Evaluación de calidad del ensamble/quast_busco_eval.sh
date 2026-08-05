#!/bin/bash
# =====================================================================
# PIPELINE INTEGRADO DE EVALUACIÓN MULTI-MÉTRICA (QUAST + BUSCO)
# =====================================================================
set -e

# --- INICIALIZACIÓN DE CONDA ---
CONDA_BASE=$(conda info --base 2>/dev/null || echo "$HOME/miniconda3")
if [ -f "$CONDA_BASE/etc/profile.d/conda.sh" ]; then
    source "$CONDA_BASE/etc/profile.d/conda.sh"
else
    eval "$(conda shell.bash hook)"
fi

# Configuración
ASSEMBLY_FILE="primary.genome.scf.fasta"
REFERENCE=""  # Deja en blanco para De Novo o pon la ruta a tu referencia FASTA
QUAST_OUTPUT_DIR="quast_results"
BUSCO_OUTPUT_DIR="busco_results"
THREADS=8
BUSCO_LINEAGE="bacteria_odb12.2"

# Localizar archivo
if [ ! -f "$ASSEMBLY_FILE" ]; then
    if [ -f "final.genome.scf.fasta" ]; then ASSEMBLY_FILE="final.genome.scf.fasta";
    elif [ -f "Test.fasta" ]; then ASSEMBLY_FILE="Test.fasta";
    else echo "ERROR: No se encontró $ASSEMBLY_FILE"; exit 1; fi
fi

echo "====================================================================="
echo "[1/4] Ejecutando QUAST en quast_env..."
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
echo "[2/4] Ejecutando BUSCO en busco_env..."
echo "====================================================================="
conda activate busco_env
rm -rf "$BUSCO_OUTPUT_DIR"
busco -i "$ASSEMBLY_FILE" -m genome -o "$BUSCO_OUTPUT_DIR" -c "$THREADS" -l "$BUSCO_LINEAGE"
conda deactivate

echo ""
echo "====================================================================="
echo "[3/4] Extracción y Análisis Multi-Métrica"
echo "====================================================================="

REPORT_TXT="$QUAST_OUTPUT_DIR/report.txt"
if [ ! -f "$REPORT_TXT" ]; then echo "ERROR: Falta report.txt"; exit 1; fi

# Función auxiliar para extracción robusta desde report.txt
get_quast_val() {
    local key="$1"
    local val=$(awk -F'|' -v k="$key" '$1 ~ k {print $2}' "$REPORT_TXT" | head -n 1 | tr -d ' ')
    echo "${val:-0}"
}

# 1. Extracción de métricas QUAST
TOTAL_LEN=$(get_quast_val "^Total length \(>= 0 bp\)")
NUM_CONTIGS=$(get_quast_val "^# contigs \(>= 0 bp\)")
N50=$(get_quast_val "^N50")
LARGEST_CONTIG=$(get_quast_val "^Largest contig")
GC_CONTENT=$(get_quast_val "^GC \(\%\)")
NS_100KB=$(get_quast_val "^# N's per 100 kbp")

# Métricas condicionales si hay referencia
MISASSEMBLIES=$(get_quast_val "^# misassemblies")
MISMATCHES=$(get_quast_val "^# mismatches per 100 kbp")

# 2. Extracción de métricas BUSCO
BUSCO_SUMMARY=$(find "$BUSCO_OUTPUT_DIR" -name "short_summary*.txt" | head -n 1)
BUSCO_C="0"
if [ -f "$BUSCO_SUMMARY" ]; then
    BUSCO_C=$(grep -oP 'C:\K[0-9.]+(?=%|\s)' "$BUSCO_SUMMARY" | head -n 1 || echo "0")
fi

echo "--- RESUMEN DE MÉTRICAS EXTRAÍDAS ---"
echo " 1. Tamaño Total     : $TOTAL_LEN pb"
echo " 2. Nº de Contigs    : $NUM_CONTIGS"
echo " 3. Valor N50        : $N50 pb"
echo " 4. Contig más largo : $LARGEST_CONTIG pb"
echo " 5. Contenido GC     : $GC_CONTENT %"
echo " 6. Gaps (N's/100kb) : $NS_100KB"
if [ -n "$REFERENCE" ] && [ -f "$REFERENCE" ]; then
    echo " 7. Misassemblies    : $MISASSEMBLIES"
    echo " 8. Mismatches/100kb : $MISMATCHES"
fi
echo " 9. BUSCO Completo   : $BUSCO_C %"

echo ""
echo "====================================================================="
echo "[4/4] EVALUACIÓN PONDERADA DEL ENSAMBLADO"
echo "====================================================================="

SCORE=0
WARNINGS=()

# Conversión a enteros para comparaciones lógicas
SIZE_NUM=${TOTAL_LEN%.*}
N50_NUM=${N50%.*}
CONTIGS_NUM=${NUM_CONTIGS%.*}
LARGEST_NUM=${LARGEST_CONTIG%.*}
BUSCO_NUM=${BUSCO_C%.*}

# A. EVALUACIÓN DE TAMAÑO Y TIPO DE ORGANISMO
echo "[A] Tamaño del Ensamblado:"
if [ "$SIZE_NUM" -ge 1000000 ] && [ "$SIZE_NUM" -le 10000000 ]; then
    echo "  -> Rango concordante con genoma bacteriano ($((SIZE_NUM/1000000)) Mb)."
    SCORE=$((SCORE+1))
else
    WARNINGS+=("Tamaño inusual ($TOTAL_LEN pb) para un aislado bacteriano estándar.")
fi

# B. CONTINUIDAD (N50, Contigs, Contig más largo)
echo "[B] Continuidad y Fragmentación:"
if [ "$N50_NUM" -ge 100000 ]; then
    echo "  -> N50 Alto ($N50 pb >= 100 kb). Excelente para Illumina."
    SCORE=$((SCORE+2))
elif [ "$N50_NUM" -ge 30000 ]; then
    echo "  -> N50 Aceptable ($N50 pb)."
    SCORE=$((SCORE+1))
else
    WARNINGS+=("N50 muy bajo ($N50 pb). Ensamblado altamente fragmentado.")
fi

if [ "$CONTIGS_NUM" -le 50 ]; then
    echo "  -> Bajo número de contigs ($NUM_CONTIGS contigs <= 50)."
    SCORE=$((SCORE+2))
elif [ "$CONTIGS_NUM" -le 150 ]; then
    echo "  -> Número de contigs moderado ($NUM_CONTIGS contigs)."
    SCORE=$((SCORE+1))
else
    WARNINGS+=("Número de contigs elevado ($NUM_CONTIGS contigs).")
fi

if [ "$LARGEST_NUM" -ge 200000 ]; then
    echo "  -> Contig mayor representativo ($LARGEST_CONTIG pb >= 200 kb)."
    SCORE=$((SCORE+1))
fi

# C. CALIDAD DE SECUENCIA Y INTEGRIDAD (GC, Gaps, BUSCO)
echo "[C] Integridad Génica y Composición:"
if [ "$BUSCO_NUM" -ge 95 ]; then
    echo "  -> BUSCO Excelente ($BUSCO_C% >= 95%). Casi 100% de genes esenciales detectados."
    SCORE=$((SCORE+3))
elif [ "$BUSCO_NUM" -ge 80 ]; then
    echo "  -> BUSCO Bueno ($BUSCO_C%)."
    SCORE=$((SCORE+1))
else
    WARNINGS+=("BUSCO bajo ($BUSCO_C%). Faltan marcadores génicos conservados.")
fi

# D. ERRORES ESTRUCTURALES (Solo con referencia)
if [ -n "$REFERENCE" ] && [ -f "$REFERENCE" ]; then
    echo "[D] Errores de Ensamblado (Vs Referencia):"
    MIS_NUM=${MISASSEMBLIES%.*}
    if [ "$MIS_NUM" -eq 0 ]; then
        echo "  -> Sin reordenamientos ni misassemblies detectados."
        SCORE=$((SCORE+1))
    else
        WARNINGS+=("Se detectaron $MISASSEMBLIES misassemblies respecto a la referencia.")
    fi
fi

echo ""
echo "---------------------------------------------------------------------"
echo "VERDICTO FINAL:"
if [ "$SCORE" -ge 6 ]; then
    echo " STATUS: ENSAMBLADO DE ALTA CALIDAD (DE NOVO DRAFT EXCELENTE)"
    echo " El genoma posee gran continuidad, completitud génica superior al 95% y baja fragmentación."
elif [ "$SCORE" -ge 4 ]; then
    echo " STATUS: ENSAMBLADO BUENO / ACEPTABLE"
    echo " Apto para análisis bioinformáticos generales."
else
    echo " STATUS: ENSAMBLADO DEFICIENTE"
    echo " Se recomienda re-procesar las lecturas primarias o ajustar parámetros de ensamblado."
fi

if [ ${#WARNINGS[@]} -gt 0 ]; then
    echo ""
    echo " Observaciones / Advertencias:"
    for w in "${WARNINGS[@]}"; do echo "   - $w"; done
fi
echo "---------------------------------------------------------------------"
