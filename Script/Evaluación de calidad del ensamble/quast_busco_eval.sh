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
REFERENCE=""  # Ruta a genoma de referencia si se dispone de uno
QUAST_OUTPUT_DIR="quast_results"
BUSCO_OUTPUT_DIR="busco_results"
THREADS=8
BUSCO_LINEAGE="bacteria_odb12.2"

# Verificar existencia del archivo
if [ ! -f "$ASSEMBLY_FILE" ]; then
    if [ -f "CA.mr.41.15.15.0.02/final.genome.scf.fasta" ]; then 
        ASSEMBLY_FILE="CA.mr.41.15.15.0.02/final.genome.scf.fasta"
    elif [ -f "final.genome.scf.fasta" ]; then 
        ASSEMBLY_FILE="final.genome.scf.fasta"
    elif [ -f "Test.fasta" ]; then 
        ASSEMBLY_FILE="Test.fasta"
    else 
        echo "ERROR: No se encontró el archivo '$ASSEMBLY_FILE'."
        exit 1
    fi
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
if [ ! -f "$REPORT_TXT" ]; then echo "ERROR: Falta $REPORT_TXT"; exit 1; fi

# Función de extracción limpia: Extrae solo el ÚLTIMO elemento numérico/cadena de la línea
parse_quast_clean() {
    local key="$1"
    local line=$(grep -E "$key" "$REPORT_TXT" | head -n 1)
    if [ -n "$line" ]; then
        # Extraer únicamente el último campo separado por espacios o tabulaciones
        echo "$line" | awk '{print $NF}' | tr -d ' \t\r'
    else
        echo "0"
    fi
}

# 1. Extracción limpia de métricas de QUAST
TOTAL_LEN=$(parse_quast_clean "^Total length \(>= 0 bp\)")
[ "$TOTAL_LEN" = "0" ] && TOTAL_LEN=$(parse_quast_clean "^Total length")

NUM_CONTIGS=$(parse_quast_clean "^# contigs \(>= 0 bp\)")
[ "$NUM_CONTIGS" = "0" ] && NUM_CONTIGS=$(parse_quast_clean "^# contigs")

N50=$(parse_quast_clean "^N50")
LARGEST_CONTIG=$(parse_quast_clean "^Largest contig")
GC_CONTENT=$(parse_quast_clean "^GC \(\%\)")
NS_100KB=$(parse_quast_clean "^# N's per 100 kbp")

MISASSEMBLIES=$(parse_quast_clean "^# misassemblies")
MISMATCHES=$(parse_quast_clean "^# mismatches per 100 kbp")

# 2. Extracción de BUSCO
BUSCO_SUMMARY=$(find "$BUSCO_OUTPUT_DIR" -name "short_summary*.txt" | head -n 1)
BUSCO_C="0"
if [ -n "$BUSCO_SUMMARY" ] && [ -f "$BUSCO_SUMMARY" ]; then
    BUSCO_C=$(grep -oP 'C:\K[0-9.]+(?=%|\s)' "$BUSCO_SUMMARY" | head -n 1 || echo "0")
fi

echo "--- RESUMEN DE MÉTRICAS OBTENIDAS ---"
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

# Limpieza estricta para garantizar valores numéricos puros en Bash
SIZE_NUM=$(echo "$TOTAL_LEN" | sed 's/[^0-9]//g')
N50_NUM=$(echo "$N50" | sed 's/[^0-9]//g')
CONTIGS_NUM=$(echo "$NUM_CONTIGS" | sed 's/[^0-9]//g')
LARGEST_NUM=$(echo "$LARGEST_CONTIG" | sed 's/[^0-9]//g')
BUSCO_NUM=${BUSCO_C%.*}

# Valores por defecto de seguridad si están vacíos
SIZE_NUM=${SIZE_NUM:-0}
N50_NUM=${N50_NUM:-0}
CONTIGS_NUM=${CONTIGS_NUM:-0}
LARGEST_NUM=${LARGEST_NUM:-0}
BUSCO_NUM=${BUSCO_NUM:-0}

# A. TAMAÑO
echo "[A] Tamaño del Ensamblado:"
if [ "$SIZE_NUM" -ge 1000000 ] && [ "$SIZE_NUM" -le 10000000 ]; then
    echo "  [OK] Tamaño concordante con genoma bacteriano ($((SIZE_NUM/1000000)) Mb / $TOTAL_LEN pb)."
    SCORE=$((SCORE+1))
else
    WARNINGS+=("Tamaño inusual ($TOTAL_LEN pb) para un aislado bacteriano estándar.")
fi

# B. CONTINUIDAD
echo "[B] Continuidad y Fragmentación:"
if [ "$N50_NUM" -ge 100000 ]; then
    echo "  [OK] N50 Excelente ($N50 pb >= 100 kb)."
    SCORE=$((SCORE+2))
elif [ "$N50_NUM" -ge 30000 ]; then
    echo "  [OK] N50 Aceptable ($N50 pb)."
    SCORE=$((SCORE+1))
else
    WARNINGS+=("N50 bajo ($N50 pb). Ensamblado fragmentado.")
fi

if [ "$CONTIGS_NUM" -gt 0 ] && [ "$CONTIGS_NUM" -le 50 ]; then
    echo "  [OK] Bajo número de contigs ($NUM_CONTIGS contigs <= 50)."
    SCORE=$((SCORE+2))
elif [ "$CONTIGS_NUM" -le 150 ]; then
    echo "  [MEDIO] Número de contigs moderado ($NUM_CONTIGS contigs)."
    SCORE=$((SCORE+1))
else
    WARNINGS+=("Número de contigs elevado ($NUM_CONTIGS contigs).")
fi

if [ "$LARGEST_NUM" -ge 200000 ]; then
    echo "  [OK] Contig más largo de gran tamaño ($LARGEST_CONTIG pb >= 200 kb)."
    SCORE=$((SCORE+1))
fi

# C. INTEGRIDAD GÉNICA
echo "[C] Integridad Génica y Composición:"
if [ "$BUSCO_NUM" -ge 95 ]; then
    echo "  [OK] BUSCO Excelente ($BUSCO_C% >= 95%). Genoma prácticamente completo."
    SCORE=$((SCORE+3))
elif [ "$BUSCO_NUM" -ge 80 ]; then
    echo "  [OK] BUSCO Aceptable ($BUSCO_C%)."
    SCORE=$((SCORE+1))
else
    WARNINGS+=("BUSCO bajo ($BUSCO_C%). Faltan marcadores génicos conservados.")
fi

# D. REFERENCIA (Si existe)
if [ -n "$REFERENCE" ] && [ -f "$REFERENCE" ]; then
    echo "[D] Errores de Ensamblado (vs Referencia):"
    MIS_NUM=$(echo "$MISASSEMBLIES" | sed 's/[^0-9]//g')
    MIS_NUM=${MIS_NUM:-0}
    if [ "$MIS_NUM" -eq 0 ]; then
        echo "  [OK] Sin misassemblies respecto a la referencia."
        SCORE=$((SCORE+1))
    else
        WARNINGS+=("Se detectaron $MISASSEMBLIES misassemblies respecto a la referencia.")
    fi
fi

echo ""
echo "---------------------------------------------------------------------"
echo "VERDICTO FINAL:"
if [ "$SCORE" -ge 6 ]; then
    echo " STATUS: ENSAMBLADO DE ALTA CALIDAD (DRAFT EXCELENTE)"
    echo " El genoma posee excelente continuidad, completitud génica > 95% y baja fragmentación."
elif [ "$SCORE" -ge 4 ]; then
    echo " STATUS: ENSAMBLADO BUENO / ACEPTABLE"
    echo " Apto para la mayoría de análisis genómicos downstream."
else
    echo " STATUS: ENSAMBLADO DEFICIENTE / REVISAR"
    echo " Se recomienda re-procesar las lecturas primarias."
fi

if [ ${#WARNINGS[@]} -gt 0 ]; then
    echo ""
    echo " Observaciones / Advertencias:"
    for w in "${WARNINGS[@]}"; do echo "   - $w"; done
fi
echo "---------------------------------------------------------------------"
