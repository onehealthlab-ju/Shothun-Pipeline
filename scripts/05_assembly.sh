#!/bin/bash

################################################################################
# Script: 05_assembly.sh
# Description: De novo metagenomic assembly using MEGAHIT and SPAdes
# Author: Md. Jubayer Hossain
# Date: 2026-02-25
################################################################################

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

################################################################################
# CONFIGURATION
################################################################################

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Input/Output directories
INPUT_DIR="${PROJECT_DIR}/host_removed"
OUTPUT_DIR="${PROJECT_DIR}/assembly"
MEGAHIT_DIR="${OUTPUT_DIR}/megahit"
SPADES_DIR="${OUTPUT_DIR}/spades"
STATS_DIR="${OUTPUT_DIR}/assembly_stats"
FILTERED_DIR="${OUTPUT_DIR}/filtered_contigs"
LOGS_DIR="${OUTPUT_DIR}/logs"

# Create directories
mkdir -p "${MEGAHIT_DIR}" "${SPADES_DIR}" "${STATS_DIR}" "${FILTERED_DIR}" "${LOGS_DIR}"

# Computational resources
THREADS=8
MEMORY_GB=32  # Adjust based on available RAM

# Assembly parameters
MIN_CONTIG_LENGTH=500  # Minimum contig length to keep (bp)

################################################################################
# ACTIVATE CONDA ENVIRONMENT
################################################################################

log_info "Activating conda environment..."
eval "$(conda shell.bash hook)"
conda activate shotgun-metagenomics-pipeline

################################################################################
# ASSEMBLY TOOL SELECTION
################################################################################

log_info "====================================================================="
log_info "  Metagenomic Assembly Pipeline"
log_info "====================================================================="

cat << EOF

Available assemblers:
  1) MEGAHIT (fast, memory-efficient, recommended for large datasets)
  2) SPAdes metaSPAdes mode (slower, more accurate, good for low-complexity)
  3) Both (compare assemblies)

EOF

read -p "Select assembler (1/2/3) [default: 1]: " assembler_choice
assembler_choice=${assembler_choice:-1}

RUN_MEGAHIT=false
RUN_SPADES=false

case $assembler_choice in
    1) RUN_MEGAHIT=true ;;
    2) RUN_SPADES=true ;;
    3) RUN_MEGAHIT=true; RUN_SPADES=true ;;
    *) log_error "Invalid choice"; exit 1 ;;
esac

################################################################################
# STEP 1: MEGAHIT Assembly
################################################################################

if [[ "$RUN_MEGAHIT" == true ]]; then
    log_info "====================================================================="
    log_info "  STEP 1A: MEGAHIT Assembly"
    log_info "====================================================================="
    
    for R1 in "${INPUT_DIR}"/*_1.nonhost.fastq.gz; do
        SAMPLE=$(basename "$R1" | sed 's/_1.nonhost.fastq.gz//')
        R2="${INPUT_DIR}/${SAMPLE}_2.nonhost.fastq.gz"
        
        if [[ ! -f "$R2" ]]; then
            log_warning "Pair not found for ${SAMPLE}, skipping..."
            continue
        fi
        
        log_info "Running MEGAHIT on sample: ${SAMPLE}"
        log_warning "  This may take 1-4 hours depending on data size and complexity"
        
        MEGAHIT_OUT="${MEGAHIT_DIR}/${SAMPLE}"
        
        # Remove old output if exists
        if [[ -d "$MEGAHIT_OUT" ]]; then
            rm -rf "$MEGAHIT_OUT"
        fi
        
        megahit \
            -1 "$R1" \
            -2 "$R2" \
            -o "$MEGAHIT_OUT" \
            --num-cpu-threads ${THREADS} \
            --memory ${MEMORY_GB}e9 \
            --min-contig-len ${MIN_CONTIG_LENGTH} \
            --k-min 21 \
            --k-max 141 \
            --k-step 12 \
            --out-prefix "${SAMPLE}" \
            2>&1 | tee "${LOGS_DIR}/${SAMPLE}_megahit.log"
        
        log_success "  MEGAHIT completed for ${SAMPLE}"
        
        # Copy final contigs
        cp "${MEGAHIT_OUT}/${SAMPLE}.contigs.fa" "${FILTERED_DIR}/${SAMPLE}_megahit_contigs.fa"
    done
    
    log_success "MEGAHIT assembly completed for all samples"
fi

################################################################################
# STEP 2: SPAdes metaSPAdes Assembly
################################################################################

if [[ "$RUN_SPADES" == true ]]; then
    log_info "====================================================================="
    log_info "  STEP 1B: metaSPAdes Assembly"
    log_info "====================================================================="
    
    for R1 in "${INPUT_DIR}"/*_1.nonhost.fastq.gz; do
        SAMPLE=$(basename "$R1" | sed 's/_1.nonhost.fastq.gz//')
        R2="${INPUT_DIR}/${SAMPLE}_2.nonhost.fastq.gz"
        
        if [[ ! -f "$R2" ]]; then
            continue
        fi
        
        log_info "Running metaSPAdes on sample: ${SAMPLE}"
        log_warning "  This may take 2-8 hours (slower but more accurate than MEGAHIT)"
        
        SPADES_OUT="${SPADES_DIR}/${SAMPLE}"
        
        metaspades.py \
            -1 "$R1" \
            -2 "$R2" \
            -o "$SPADES_OUT" \
            -t ${THREADS} \
            -m ${MEMORY_GB} \
            2>&1 | tee "${LOGS_DIR}/${SAMPLE}_spades.log"
        
        log_success "  metaSPAdes completed for ${SAMPLE}"
        
        # Filter and copy contigs
        if [[ -f "${SPADES_OUT}/contigs.fasta" ]]; then
            # Filter by length using awk
            awk -v minlen=${MIN_CONTIG_LENGTH} '
                /^>/ {if (seq_len >= minlen && seq != "") print seq_header "\n" seq; 
                      seq_header=$0; seq=""; seq_len=0; next}
                {seq=seq $0; seq_len+=length($0)}
                END {if (seq_len >= minlen && seq != "") print seq_header "\n" seq}
            ' "${SPADES_OUT}/contigs.fasta" > "${FILTERED_DIR}/${SAMPLE}_spades_contigs.fa"
        fi
    done
    
    log_success "metaSPAdes assembly completed for all samples"
fi

################################################################################
# STEP 3: Assembly Statistics
################################################################################

log_info "====================================================================="
log_info "  STEP 2: Computing Assembly Statistics"
log_info "====================================================================="

# Function to calculate assembly stats
calculate_stats() {
    local FASTA=$1
    local SAMPLE=$2
    local ASSEMBLER=$3
    local STATS_FILE="${STATS_DIR}/${SAMPLE}_${ASSEMBLER}_stats.txt"
    
    log_info "Calculating stats for: ${SAMPLE} (${ASSEMBLER})"
    
    # Use awk to calculate statistics
    awk '
        BEGIN {
            total_length=0; 
            num_contigs=0; 
            max_len=0;
        }
        /^>/ {next}
        {
            len=length($0);
            total_length+=len;
            lengths[num_contigs]=len;
            if (len>max_len) max_len=len;
            num_contigs++;
        }
        END {
            # Sort lengths in descending order
            n=asort(lengths, sorted_lengths);
            
            # Calculate N50
            cumsum=0;
            n50=0;
            for (i=n; i>=1; i--) {
                cumsum+=sorted_lengths[i];
                if (cumsum >= total_length/2) {
                    n50=sorted_lengths[i];
                    break;
                }
            }
            
            # Calculate L50 (number of contigs comprising N50)
            cumsum=0;
            l50=0;
            for (i=n; i>=1; i--) {
                cumsum+=sorted_lengths[i];
                l50++;
                if (cumsum >= total_length/2) break;
            }
            
            # Calculate mean and median
            mean=total_length/num_contigs;
            if (num_contigs % 2 == 0) {
                median=(sorted_lengths[n/2] + sorted_lengths[n/2+1])/2;
            } else {
                median=sorted_lengths[(n+1)/2];
            }
            
            printf "Assembly Statistics: '"$SAMPLE"' ('"$ASSEMBLER"')\n";
            printf "================================================================================\n";
            printf "Number of contigs:    %d\n", num_contigs;
            printf "Total assembly size:  %d bp (%.2f Mbp)\n", total_length, total_length/1e6;
            printf "Longest contig:       %d bp (%.2f kbp)\n", max_len, max_len/1e3;
            printf "Mean contig length:   %.0f bp\n", mean;
            printf "Median contig length: %d bp\n", median;
            printf "N50:                  %d bp\n", n50;
            printf "L50:                  %d contigs\n", l50;
        }
    ' "$FASTA" > "$STATS_FILE"
    
    cat "$STATS_FILE"
    echo ""
}

# Calculate stats for MEGAHIT assemblies
if [[ "$RUN_MEGAHIT" == true ]]; then
    for FASTA in "${FILTERED_DIR}"/*_megahit_contigs.fa; do
        SAMPLE=$(basename "$FASTA" | sed 's/_megahit_contigs.fa//')
        calculate_stats "$FASTA" "$SAMPLE" "megahit"
    done
fi

# Calculate stats for SPAdes assemblies
if [[ "$RUN_SPADES" == true ]]; then
    for FASTA in "${FILTERED_DIR}"/*_spades_contigs.fa; do
        SAMPLE=$(basename "$FASTA" | sed 's/_spades_contigs.fa//')
        calculate_stats "$FASTA" "$SAMPLE" "spades"
    done
fi

################################################################################
# STEP 4: Assembly Quality Check with QUAST
################################################################################

log_info "====================================================================="
log_info "  STEP 3: Assembly Quality Assessment (QUAST)"
log_info "====================================================================="

QUAST_DIR="${OUTPUT_DIR}/quast_reports"
mkdir -p "${QUAST_DIR}"

# Run QUAST on MEGAHIT assemblies
if [[ "$RUN_MEGAHIT" == true ]]; then
    log_info "Running QUAST on MEGAHIT assemblies..."
    
    MEGAHIT_CONTIGS=(${FILTERED_DIR}/*_megahit_contigs.fa)
    
    if [[ ${#MEGAHIT_CONTIGS[@]} -gt 0 ]]; then
        quast.py \
            "${MEGAHIT_CONTIGS[@]}" \
            -o "${QUAST_DIR}/megahit" \
            --threads ${THREADS} \
            --min-contig ${MIN_CONTIG_LENGTH} \
            --no-plots \
            2>&1 | tee "${LOGS_DIR}/quast_megahit.log"
        
        log_success "  QUAST report: ${QUAST_DIR}/megahit/report.html"
    fi
fi

# Run QUAST on SPAdes assemblies
if [[ "$RUN_SPADES" == true ]]; then
    log_info "Running QUAST on metaSPAdes assemblies..."
    
    SPADES_CONTIGS=(${FILTERED_DIR}/*_spades_contigs.fa)
    
    if [[ ${#SPADES_CONTIGS[@]} -gt 0 ]]; then
        quast.py \
            "${SPADES_CONTIGS[@]}" \
            -o "${QUAST_DIR}/spades" \
            --threads ${THREADS} \
            --min-contig ${MIN_CONTIG_LENGTH} \
            --no-plots \
            2>&1 | tee "${LOGS_DIR}/quast_spades.log"
        
        log_success "  QUAST report: ${QUAST_DIR}/spades/report.html"
    fi
fi

log_success "QUAST quality assessment completed"

################################################################################
# STEP 5: Generate Summary Report
################################################################################

log_info "====================================================================="
log_info "  STEP 4: Generating Summary Report"
log_info "====================================================================="

SUMMARY_FILE="${OUTPUT_DIR}/assembly_summary.txt"

cat > "${SUMMARY_FILE}" << EOF
================================================================================
Metagenomic Assembly Summary Report
Generated: $(date)
================================================================================

Project Directory: ${PROJECT_DIR}
Input Directory:   ${INPUT_DIR}
Output Directory:  ${OUTPUT_DIR}

Assembly Parameters:
  - Threads:             ${THREADS}
  - Memory:              ${MEMORY_GB} GB
  - Min contig length:   ${MIN_CONTIG_LENGTH} bp

Assemblers Used:
  - MEGAHIT:     $([ "$RUN_MEGAHIT" == true ] && echo "Yes" || echo "No")
  - metaSPAdes:  $([ "$RUN_SPADES" == true ] && echo "Yes" || echo "No")

================================================================================
Assembly Statistics Summary:
================================================================================

EOF

# Include per-sample stats
for STATS in "${STATS_DIR}"/*_stats.txt; do
    if [[ -f "$STATS" ]]; then
        cat "$STATS" >> "${SUMMARY_FILE}"
        echo "" >> "${SUMMARY_FILE}"
    fi
done

cat >> "${SUMMARY_FILE}" << EOF
================================================================================
Output Files:
================================================================================

Filtered Contigs (≥${MIN_CONTIG_LENGTH} bp):
  - Directory: ${FILTERED_DIR}
  - MEGAHIT:   *_megahit_contigs.fa
  - SPAdes:    *_spades_contigs.fa

Assembly Statistics:
  - Directory: ${STATS_DIR}
  - Files:     *_stats.txt

QUAST Reports:
  - MEGAHIT:   ${QUAST_DIR}/megahit/report.html
  - SPAdes:    ${QUAST_DIR}/spades/report.html

Raw Assembly Output:
  - MEGAHIT:   ${MEGAHIT_DIR}
  - SPAdes:    ${SPADES_DIR}

Logs:
  - Directory: ${LOGS_DIR}

================================================================================
Assembly Quality Guidelines:
================================================================================

Good metagenomic assembly typically has:
  - N50:               >1,000 bp (higher is better)
  - Total assembly:    10-100 Mbp (depends on complexity and depth)
  - Longest contig:    >10 kbp (indicates good assembly)
  - Number of contigs: Varies widely (lower is generally better)

High-quality assemblies:
  - Human gut microbiome: N50 >5 kbp, total >50 Mbp
  - Environmental samples: Highly variable, depends on diversity

Poor assembly indicators:
  - Very low N50 (<500 bp)
  - No contigs >10 kbp
  - Very high number of short contigs

If assembly quality is poor:
  1. Check sequencing depth (may need more reads)
  2. Review read quality (may need better trimming)
  3. Consider sample complexity (high diversity = harder assembly)

================================================================================
MEGAHIT vs metaSPAdes:
================================================================================

MEGAHIT advantages:
  - Faster (1-4 hours)
  - Lower memory requirements
  - Good for high-complexity, high-diversity samples
  - Recommended for large datasets

metaSPAdes advantages:
  - More accurate assemblies
  - Better for low-complexity samples
  - Produces longer contigs
  - Better error correction
  - Slower (2-8 hours) and more memory-intensive

Recommendation:
  - Start with MEGAHIT for quick results
  - Use metaSPAdes for in-depth analysis or if MEGAHIT results are poor
  - Compare both if resources permit

================================================================================
Next Steps:
================================================================================

1. Review assembly statistics and QUAST reports
2. Open QUAST HTML reports in web browser for detailed assessment
3. Proceed to binning: bash scripts/06_binning.sh

Note: Filtered contigs (≥${MIN_CONTIG_LENGTH} bp) will be used for downstream analysis

================================================================================
EOF

log_success "Summary report generated: ${SUMMARY_FILE}"
cat "${SUMMARY_FILE}"

################################################################################
# COMPLETION
################################################################################

log_success "====================================================================="
log_success "  Assembly Pipeline Completed!"
log_success "====================================================================="

log_info "Key outputs:"
log_info "  - Filtered contigs: ${FILTERED_DIR}"
log_info "  - Statistics:       ${STATS_DIR}"
log_info "  - QUAST reports:    ${QUAST_DIR}"
log_info "  - Summary:          ${SUMMARY_FILE}"
log_info ""
log_info "Next step: bash scripts/06_binning.sh"
