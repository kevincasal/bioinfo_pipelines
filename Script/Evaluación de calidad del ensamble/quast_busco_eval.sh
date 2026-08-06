#!/bin/bash

# ==============================================================================
# ------------------------------------------------------------------------------
# Script:          quast_busco_eval.sh
# Descripción:     Evaluación multi-métrica (QUAST + BUSCO) para todas las
#                  muestras de un proyecto generado con run_pipeline.sh.
#                  Reutiliza:
#                    - Los ensamblados finales en <proyecto>/ensamblados_finales/
#                    - Las lecturas paired-end originales en <proyecto>/secuencias/
#                  QUAST corre con las lecturas PE (-1/-2) para obtener métricas
#                  de mapeo/cobertura, además de las métricas de contigüidad.
#                  Este script SOLO evalúa; no ensambla ni anota.
# ------------------------------------------------------------------------------
# AUTOR:           [KEVIN JOSUE CASAL ARROYO]
# CARGO:           [ANALISTA ZONAL DE LABORATORIO DE VIGILANCIA EPIDEMIOLÓGICA Y REFERENCIA NACIONAL 2 / Especialista en Bioinformática]
# DEPARTAMENTO:    [Cordinación zonal 9-INSPI]
# CONTACTO / EMAIL: [kevincasal0@gmail.com]
# FECHA:           Agosto 2026
# VERSIÓN:         2.0.0 (multi-muestra, integración con run_pipeline.sh)
# ------------------------------------------------------------------------------
# USO:
#   ./quast_busco_eval.sh [opciones]
#
# OPCIONES:
#   -l, --location       "escritorio" o "documentos" (dónde está el proyecto)
#   -n, --project-name    Nombre de la carpeta del proyecto (la misma que
#                        usaste en run_pipeline.sh)
#   -p, --project-dir     Ruta completa al proyecto (alternativa a -l/-n)
#   -r, --reference       Ruta a un genoma de referencia (opcional, se aplica
#                        a todas las muestras)
#   -t, --threads        Hilos a usar (default: 8)
#       --lineage        Linaje de BUSCO (default: bacteria_odb12.2)
#       --no-reads       No pasar las lecturas FASTQ a QUAST, aunque existan
#   -h, --help           Muestra esta ayuda
#
# EJEMPLOS:
#   ./quast_busco_eval.sh -l escritorio -n lote_agosto2026
#   ./quast_busco_eval.sh -p /home/usuario/Desktop/lote_agosto2026 -t 16
# ------------------------------------------------------------------------------
# DERECHOS DE AUTOR Y LICENCIA:
# (c) 2026 [Tu Nombre completo] / INSPI. Todos los derechos reservados.
# Desarrollado para uso institucional en las plataformas del INSPI.
# Prohibida su redistribución o modificación no autorizada sin citar al autor.
# ==============================================================================

set -uo pipefail
# Sin 'set -e' global: si una muestra falla, se reporta y se sigue con las demás.

# --- Valores por defecto ---
LOCATION_ARG=""
PROJECT_NAME_ARG=""
PROJECT_DIR_ARG=""
REFERENCE=""
THREADS=8
BUSCO_LINEAGE="bacteria_odb12.2"
USE_READS=true
LOG_FILE="./quast_busco_eval_$(date +%Y%m%d_%H%M%S).log"

mostrar_ayuda() {
    grep -E '^#( |$)' "$0" | sed -n '/USO:/,/^# -----/p' | sed 's/^# \{0,1\}//;/^-----/d'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -l|--location)      LOCATION_ARG="$2"; shift 2 ;;
        -n|--project-name)   PROJECT_NAME_ARG="$2"; shift 2 ;;
        -p|--project-dir)    PROJECT_DIR_ARG="$2"; shift 2 ;;
        -r|--reference)      REFERENCE="$2"; shift 2 ;;
        -t|--threads)        THREADS="$2"; shift 2 ;;
        --lineage)           BUSCO_LINEAGE="$2"; shift 2 ;;
        --no-reads)          USE_READS=false; shift ;;
        -h|--help)            mostrar_ayuda ;;
        *) echo "Opción desconocida: $1"; mostrar_ayuda ;;
    esac
done

exec > >(tee -a "$LOG_FILE") 2>&1

echo "=============================================================================="
echo " Evaluación Multi-Métrica de Ensamblados (QUAST + BUSCO)"
echo " INSPI 2026"
echo "=============================================================================="

# --- Paso 0: Inicializar Conda ---
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

# --- Paso 1: Localizar la carpeta del proyecto (la misma de run_pipeline.sh) ---
echo ""
echo "=== [Paso 1] Localizando carpeta del proyecto ==="

if [ -n "$PROJECT_DIR_ARG" ]; then
    PROJECT_DIR="$PROJECT_DIR_ARG"
else
    if [ -n "$LOCATION_ARG" ]; then
        case "${LOCATION_ARG,,}" in
            escritorio|desktop) UBICACION="Escritorio" ;;
            documentos|documents) UBICACION="Documentos" ;;
            *) echo "‼️  --location debe ser 'escritorio' o 'documentos'"; exit 1 ;;
        esac
    else
        echo "¿Dónde está la carpeta del proyecto?"
        select UBICACION in "Escritorio" "Documentos"; do
            case "$UBICACION" in
                Escritorio|Documentos) break ;;
                *) echo "Opción inválida, elige 1 (Escritorio) o 2 (Documentos)." ;;
            esac
        done
    fi

    if [ "$UBICACION" = "Escritorio" ]; then
        [ -d "$HOME/Desktop" ] && BASE_DIR="$HOME/Desktop" || BASE_DIR="$HOME/Escritorio"
    else
        [ -d "$HOME/Documents" ] && BASE_DIR="$HOME/Documents" || BASE_DIR="$HOME/Documentos"
    fi

    if [ -n "$PROJECT_NAME_ARG" ]; then
        PROJECT_NAME="$PROJECT_NAME_ARG"
    else
        read -rp "Nombre de la carpeta del proyecto: " PROJECT_NAME
    fi
    PROJECT_DIR="$BASE_DIR/$PROJECT_NAME"
fi

SEQ_DIR="$PROJECT_DIR/secuencias"
ASM_DIR="$PROJECT_DIR/ensamblados_finales"
EVAL_DIR="$PROJECT_DIR/evaluaciones"

if [ ! -d "$PROJECT_DIR" ] || [ ! -d "$ASM_DIR" ]; then
    echo "‼️  No se encontró la estructura esperada en '$PROJECT_DIR'."
    echo "    Se esperaba encontrar la carpeta: $ASM_DIR"
    echo "    ¿Corriste primero run_pipeline.sh sobre este proyecto?"
    exit 1
fi

mkdir -p "$EVAL_DIR"
echo "Proyecto      : $PROJECT_DIR"
echo "Ensamblados   : $ASM_DIR"
echo "Lecturas (PE) : $SEQ_DIR"
echo "Evaluaciones  : $EVAL_DIR"

# --- Función: dado un nombre de muestra, busca su par R1/R2 en $SEQ_DIR ---
buscar_lecturas() {
    local sample="$1"
    local r1="" r2=""

    for cand in "$SEQ_DIR/${sample}_R1"*.fastq.gz "$SEQ_DIR/${sample}_R1"*.fq.gz \
                "$SEQ_DIR/${sample}_r1"*.fastq.gz "$SEQ_DIR/${sample}_r1"*.fq.gz \
                "$SEQ_DIR/${sample}_1.fastq.gz" "$SEQ_DIR/${sample}_1.fq.gz"; do
        [ -f "$cand" ] || continue
        r1="$cand"
        case "$cand" in
            *_R1*) r2="${cand/_R1/_R2}" ;;
            *_r1*) r2="${cand/_r1/_r2}" ;;
            *_1.*) r2="${cand/_1./_2.}" ;;
        esac
        break
    done

    if [ -n "$r1" ] && [ -f "$r2" ]; then
        echo "${r1}|${r2}"
    else
        echo ""
    fi
}

# --- Función de extracción limpia desde report.txt de QUAST ---
parse_quast_clean() {
    local report="$1" key="$2"
    local line
    line=$(grep -E "$key" "$report" | head -n 1)
    if [ -n "$line" ]; then
        echo "$line" | awk '{print $NF}' | tr -d ' \t\r'
    else
        echo "0"
    fi
}

# --- Función: evalúa UNA muestra (QUAST + BUSCO + veredicto) ---
evaluar_muestra() {
    local sample="$1" assembly="$2"
    local sample_eval_dir="$EVAL_DIR/$sample"
    local quast_out="$sample_eval_dir/quast_results"
    local busco_out="$sample_eval_dir/busco_results"

    mkdir -p "$sample_eval_dir"

    echo ""
    echo "====================================================================="
    echo " Muestra: $sample"
    echo "====================================================================="

    # --- Lecturas PE (opcional) ---
    local pares="" r1="" r2=""
    if [ "$USE_READS" = true ]; then
        pares="$(buscar_lecturas "$sample")"
        if [ -n "$pares" ]; then
            IFS='|' read -r r1 r2 <<< "$pares"
            echo "Lecturas PE encontradas:"
            echo "  R1: $r1"
            echo "  R2: $r2"
        else
            echo "⚠️  No se encontraron lecturas PE para '$sample' en '$SEQ_DIR'; QUAST correrá solo con el ensamblado."
        fi
    fi

    # --- [1/2] QUAST ---
    echo ""
    echo "[1/2] Ejecutando QUAST (quast_env)..."
    conda activate quast_env || { echo "‼️  No se pudo activar quast_env"; return 1; }

    QUAST_ARGS=("$assembly" -o "$quast_out" -t "$THREADS" --min-contig 500)
    if [ -n "$r1" ] && [ -n "$r2" ]; then
        QUAST_ARGS+=(-1 "$r1" -2 "$r2")
    fi
    if [ -n "$REFERENCE" ] && [ -f "$REFERENCE" ]; then
        QUAST_ARGS+=(-r "$REFERENCE")
    fi

    if ! quast.py "${QUAST_ARGS[@]}"; then
        echo "‼️  QUAST falló para '$sample'."
        conda deactivate
        return 1
    fi
    conda deactivate

    # --- [2/2] BUSCO ---
    echo ""
    echo "[2/2] Ejecutando BUSCO (busco_env)..."
    conda activate busco_env || { echo "‼️  No se pudo activar busco_env"; return 1; }

    rm -rf "$busco_out"
    if ! busco -i "$assembly" -m genome -o "$(basename "$busco_out")" \
               --out_path "$sample_eval_dir" -c "$THREADS" -l "$BUSCO_LINEAGE"; then
        echo "‼️  BUSCO falló para '$sample'."
        conda deactivate
        return 1
    fi
    conda deactivate

    # --- Extracción y veredicto ---
    local report_txt="$quast_out/report.txt"
    if [ ! -f "$report_txt" ]; then
        echo "‼️  Falta $report_txt"
        return 1
    fi

    local total_len num_contigs n50 largest_contig gc_content misassemblies
    total_len=$(parse_quast_clean "$report_txt" "^Total length \(>= 0 bp\)")
    [ "$total_len" = "0" ] && total_len=$(parse_quast_clean "$report_txt" "^Total length")
    num_contigs=$(parse_quast_clean "$report_txt" "^# contigs \(>= 0 bp\)")
    [ "$num_contigs" = "0" ] && num_contigs=$(parse_quast_clean "$report_txt" "^# contigs")
    n50=$(parse_quast_clean "$report_txt" "^N50")
    largest_contig=$(parse_quast_clean "$report_txt" "^Largest contig")
    gc_content=$(parse_quast_clean "$report_txt" "^GC \(\%\)")
    misassemblies=$(parse_quast_clean "$report_txt" "^# misassemblies")

    local busco_summary busco_c="0"
    busco_summary=$(find "$busco_out" -name "short_summary*.txt" | head -n 1)
    if [ -n "$busco_summary" ] && [ -f "$busco_summary" ]; then
        busco_c=$(grep -oP 'C:\K[0-9.]+(?=%|\s)' "$busco_summary" | head -n 1 || echo "0")
    fi

    echo ""
    echo "--- RESUMEN: $sample ---"
    echo "  Tamaño Total     : $total_len pb"
    echo "  Nº de Contigs    : $num_contigs"
    echo "  Valor N50        : $n50 pb"
    echo "  Contig más largo : $largest_contig pb"
    echo "  Contenido GC     : $gc_content %"
    [ -n "$REFERENCE" ] && [ -f "$REFERENCE" ] && echo "  Misassemblies    : $misassemblies"
    echo "  BUSCO Completo   : $busco_c %"

    # --- Puntaje ponderado ---
    local score=0
    local warnings=()
    local size_num n50_num contigs_num largest_num busco_num
    size_num=$(echo "$total_len" | sed 's/[^0-9]//g'); size_num=${size_num:-0}
    n50_num=$(echo "$n50" | sed 's/[^0-9]//g'); n50_num=${n50_num:-0}
    contigs_num=$(echo "$num_contigs" | sed 's/[^0-9]//g'); contigs_num=${contigs_num:-0}
    largest_num=$(echo "$largest_contig" | sed 's/[^0-9]//g'); largest_num=${largest_num:-0}
    busco_num=${busco_c%.*}; busco_num=${busco_num:-0}

    [ "$size_num" -ge 1000000 ] && [ "$size_num" -le 10000000 ] && score=$((score+1)) || warnings+=("Tamaño inusual ($total_len pb)")
    if [ "$n50_num" -ge 100000 ]; then score=$((score+2)); elif [ "$n50_num" -ge 30000 ]; then score=$((score+1)); else warnings+=("N50 bajo ($n50 pb)"); fi
    if [ "$contigs_num" -gt 0 ] && [ "$contigs_num" -le 50 ]; then score=$((score+2)); elif [ "$contigs_num" -le 150 ]; then score=$((score+1)); else warnings+=("Nº de contigs elevado ($num_contigs)"); fi
    [ "$largest_num" -ge 200000 ] && score=$((score+1))
    if [ "$busco_num" -ge 95 ]; then score=$((score+3)); elif [ "$busco_num" -ge 80 ]; then score=$((score+1)); else warnings+=("BUSCO bajo ($busco_c%)"); fi

    local veredicto
    if [ "$score" -ge 6 ]; then veredicto="ALTA CALIDAD"
    elif [ "$score" -ge 4 ]; then veredicto="BUENO/ACEPTABLE"
    else veredicto="DEFICIENTE / REVISAR"; fi

    echo "  VEREDICTO        : $veredicto (score=$score)"
    if [ ${#warnings[@]} -gt 0 ]; then
        for w in "${warnings[@]}"; do echo "    ⚠️  $w"; done
    fi

    # Guarda una línea resumen para la tabla final
    echo "$sample|$total_len|$n50|$num_contigs|$busco_c|$veredicto" >> "$EVAL_DIR/resumen_lote.tsv"
}

# --- Paso 2: Evaluar cada ensamblado encontrado ---
echo ""
echo "=== [Paso 2] Evaluando muestras ==="

mapfile -t ASM_FILES < <(find "$ASM_DIR" -maxdepth 1 -name "*.fasta" | sort)
if [ ${#ASM_FILES[@]} -eq 0 ]; then
    echo "‼️  No se encontraron ensamblados (*.fasta) en '$ASM_DIR'."
    exit 1
fi

: > "$EVAL_DIR/resumen_lote.tsv"
EXITOSAS=()
FALLIDAS=()

for asm in "${ASM_FILES[@]}"; do
    sample="$(basename "$asm" .fasta)"
    if evaluar_muestra "$sample" "$asm"; then
        EXITOSAS+=("$sample")
    else
        FALLIDAS+=("$sample")
        echo "⚠️  La evaluación de '$sample' falló. Se continúa con la siguiente..."
    fi
done

# --- Resumen final del lote ---
echo ""
echo "=============================================================================="
echo " RESUMEN DEL LOTE"
echo "=============================================================================="
printf "%-15s %-14s %-12s %-10s %-8s %-20s\n" "MUESTRA" "TAMAÑO(pb)" "N50(pb)" "CONTIGS" "BUSCO%" "VEREDICTO"
while IFS='|' read -r s tot n50 nc busco ver; do
    printf "%-15s %-14s %-12s %-10s %-8s %-20s\n" "$s" "$tot" "$n50" "$nc" "$busco" "$ver"
done < "$EVAL_DIR/resumen_lote.tsv"

if [ ${#FALLIDAS[@]} -gt 0 ]; then
    echo ""
    echo "Muestras con errores (${#FALLIDAS[@]}): ${FALLIDAS[*]}"
fi

echo ""
echo "Tabla completa guardada en: $EVAL_DIR/resumen_lote.tsv"
echo "Log completo: $LOG_FILE"
echo "=============================================================================="
