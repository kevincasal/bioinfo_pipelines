#!/bin/bash
# =====================================================================
# PIPELINE DE EVALUACIÓN DE ENSAMBLADO CON QUAST
# =====================================================================
set -e

# --- INICIALIZACIÓN Y ACTIVACIÓN DEL ENTORNO DE CONDA ---
CONDA_BASE=$(conda info --base 2>/dev/null || echo "$HOME/miniconda3")
if [ -f "$CONDA_BASE/etc/profile.d/conda.sh" ]; then
    source "$CONDA_BASE/etc/profile.d/conda.sh"
else
    eval "$(conda shell.bash hook)"
fi

echo "Activando el entorno de Conda: quast_env..."
conda activate quast_env

# Configuración de archivos de entrada y salida
ASSEMBLY_FILE="archivo_salida_masurca.genome.scf.fasta"  # Archivo de salida típico de MaSuRCA
# Si no usas referencia, deja REFERENCE=""
REFERENCE="" 
OUTPUT_DIR="quast_results"
THREADS=8

echo "====================================================================="
echo "[1/3] Verificando archivos y ejecutando QUAST..."
echo "====================================================================="

# Verificar que el archivo de ensamblado exista
if [ ! -f "$ASSEMBLY_FILE" ]; then
    # Buscar alternativamente si está en el directorio raíz como final.genome.scf.fasta
    if [ -f "final.genome.scf.fasta" ]; then
        ASSEMBLY_FILE="final.genome.scf.fasta"
    else
        echo "ERROR: No se encontró el archivo de ensamblado ($ASSEMBLY_FILE)."
        echo "Asegúrate de especificar la ruta correcta de tu archivo .fasta"
        exit 1
    fi
fi

# Construir el comando de QUAST
QUAST_CMD="quast.py $ASSEMBLY_FILE -o $OUTPUT_DIR -t $THREADS --min-contig 500"

if [ -n "$REFERENCE" ] && [ -f "$REFERENCE" ]; then
    QUAST_CMD="$QUAST_CMD -r $REFERENCE"
fi

# Ejecutar QUAST
$QUAST_CMD

echo ""
echo "====================================================================="
echo "[2/3] Extrayendo métricas clave desde QUAST..."
echo "====================================================================="

REPORT_TXT="$OUTPUT_DIR/report.txt"

if [ ! -f "$REPORT_TXT" ]; then
    echo "ERROR: No se encontró el reporte de QUAST en $REPORT_TXT"
    exit 1
fi

# Función para extraer valores del reporte
get_metric() {
    grep "^$1" "$REPORT_TXT" | awk -F'|' '{print $2}' | tr -d ' '
}

TOTAL_LENGTH=$(get_metric "Total length (>= 0 bp)")
N50=$(get_metric "N50")
NUM_CONTIGS=$(get_metric "# contigs (>= 0 bp)")
N_PER_100KB=$(get_metric "# N's per 100 kbp")

echo "Resumen de Métricas Obtenidas:"
echo " - Tamaño Total del Ensamblado : $TOTAL_LENGTH pb"
echo " - Contig / Scaffold N50       : $N50 pb"
echo " - Número Total de Contigs     : $NUM_CONTIGS"
echo " - N's por 100 kb              : $N_PER_100KB"
echo ""

echo "====================================================================="
echo "[3/3] EVALUACIÓN DE CALIDAD DEL ENSAMBLADO"
echo "====================================================================="

# Inicializar banderas de calidad
SCORE=0
WARNINGS=()

# Convertir tamaño total a número para evaluación
SIZE_NUM=$(echo "$TOTAL_LENGTH" | tr -d ' ')

# 1. EVALUACIÓN SEGÚN TAMAÑO (Virus vs. Bacteria)
if [ "$SIZE_NUM" -lt 1000000 ]; then
    # --- EVALUACIÓN BACTERIÓFAGOS / VIRUS (< 1 Mb) ---
    echo "Categoría detectada: Genoma Viral / Bacteriófago"
    
    # N50 ideal para virus
    if [ "$N50" -ge 20000 ]; then
        echo "  [OK] N50 ($N50 pb) - Excelente continuidad para un genoma viral."
        SCORE=$((SCORE+1))
    else
        WARNINGS+=("N50 bajo ($N50 pb) para virus. Un virus ideal debería estar en 1-3 contigs.")
    fi

    # Número de contigs para virus
    if [ "$NUM_CONTIGS" -le 5 ]; then
        echo "  [OK] Contigs ($NUM_CONTIGS) - Altamente ensamblado (casi completo/circular)."
        SCORE=$((SCORE+1))
    else
        WARNINGS+=("Elevado número de contigs ($NUM_CONTIGS) para un genoma viral.")
    fi

else
    # --- EVALUACIÓN BACTERIAS (1 Mb - 10 Mb) ---
    echo "Categoría detectada: Genoma Bacteriano"

    # Evaluacion de N50 en bacterias
    if [ "$N50" -ge 100000 ]; then
        echo "  [OK] N50 ($N50 pb) - Alta continuidad (>= 100 kb)."
        SCORE=$((SCORE+1))
    elif [ "$N50" -ge 50000 ]; then
        echo "  [MEDIO] N50 ($N50 pb) - Aceptable pero moderadamente fragmentado."
    else
        WARNINGS+=("N50 bajo ($N50 pb). Ensamblado muy fragmentado para bacterias.")
    fi

    # Evaluacion de número de contigs
    if [ "$NUM_CONTIGS" -le 50 ]; then
        echo "  [OK] Número de contigs ($NUM_CONTIGS) - Bajo nivel de fragmentación."
        SCORE=$((SCORE+1))
    elif [ "$NUM_CONTIGS" -le 150 ]; then
        echo "  [MEDIO] Número de contigs ($NUM_CONTIGS) - Nivel medio de fragmentación."
    else
        WARNINGS+=("Número excesivo de contigs ($NUM_CONTIGS). Revisa posibles contaminaciones o baja cobertura.")
    fi
fi

# 2. EVALUACIÓN DE N'S (Gaps)
# Convertir flotante a entero aproximado para bash
N_INT=$(printf "%.0f" "$N_PER_100KB" 2>/dev/null || echo 0)

if [ "$N_INT" -le 500 ]; then
    echo "  [OK] N's por 100 kb ($N_PER_100KB) - Mínimo porcentaje de gaps no resueltos."
    SCORE=$((SCORE+1))
else
    WARNINGS+=("Elevada presencia de Ns ($N_PER_100KB por 100 kb). El andamiaje dejó muchos gaps.")
fi

echo ""
echo "---------------------------------------------------------------------"
echo "VERDICTO FINAL:"
if [ ${#WARNINGS[@]} -eq 0 ]; then
    echo " EXCELENTE ENSAMBLADO: Cumple con los estándares de alta calidad para datos Illumina."
elif [ "$SCORE" -ge 2 ]; then
    echo " ENSAMBLADO BUENO / ACEPTABLE: Apto para análisis downstream (anotación/pangenómica)."
    echo " Advertencias a considerar:"
    for w in "${WARNINGS[@]}"; do
        echo "   - $w"
    done
else
    echo " ENSAMBLADO DEFICIENTE / POBRE: Se recomienda no usar para análisis definitivos sin re-procesar."
    echo " Razones:"
    for w in "${WARNINGS[@]}"; do
        echo "   - $w"
    done
fi
echo "---------------------------------------------------------------------"
echo "El informe HTML interactivo completo está disponible en: $OUTPUT_DIR/report.html"
