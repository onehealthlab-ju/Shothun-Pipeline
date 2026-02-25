#!/bin/bash

################################################################################
# Script: 03_taxonomic_profiling.sh
# Description: Taxonomic classification using Kraken2, Bracken, and MetaPhlAn
# Author: Seqera AI
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
OUTPUT_DIR="${PROJECT_DIR}/taxonomic_profiling"
KRAKEN_DIR="${OUTPUT_DIR}/kraken2"
BRACKEN_DIR="${OUTPUT_DIR}/bracken"
METAPHLAN_DIR="${OUTPUT_DIR}/metaphlan"
KRONA_DIR="${OUTPUT_DIR}/krona"
LOGS_DIR="${OUTPUT_DIR}/logs"

# Create directories
mkdir -p "${KRAKEN_DIR}" "${BRACKEN_DIR}" "${METAPHLAN_DIR}" "${KRONA_DIR}" "${LOGS_DIR}"

# Computational resources
THREADS=8

# Database paths (update based on your setup)
KRAKEN2_DB="${HOME}/metagenomics_databases/kraken2/standard"
METAPHLAN_DB="${HOME}/metagenomics_databases/metaphlan"

# Bracken parameters
BRACKEN_READ_LEN=150  # Adjust based on your sequencing read length
BRACKEN_LEVEL="S"     # Species level (can be D,P,C,O,F,G,S)

################################################################################
# ACTIVATE CONDA ENVIRONMENT
################################################################################

log_info "Activating conda environment..."
eval "$(conda shell.bash hook)"
conda activate shotgun-metagenomics-pipeline

################################################################################
# CHECK DATABASES
################################################################################

log_info "Checking database availability..."

if [[ ! -d "${KRAKEN2_DB}" ]]; then
    log_warning "Kraken2 database not found: ${KRAKEN2_DB}"
    log_info "Kraken2 analysis will be skipped"
    SKIP_KRAKEN=true
else
    log_success "Kraken2 database found"
    SKIP_KRAKEN=false
fi

if [[ ! -d "${METAPHLAN_DB}" ]]; then
    log_warning "MetaPhlAn database not found: ${METAPHLAN_DB}"
    log_info "MetaPhlAn analysis will be skipped"
    SKIP_METAPHLAN=true
else
    log_success "MetaPhlAn database found"
    SKIP_METAPHLAN=false
fi

################################################################################
# STEP 1: Kraken2 Taxonomic Classification
################################################################################

if [[ "$SKIP_KRAKEN" == false ]]; then
    log_info "====================================================================="
    log_info "  STEP 1: Kraken2 Taxonomic Classification"
    log_info "====================================================================="
    
    for R1 in "${INPUT_DIR}"/*_1.nonhost.fastq.gz; do
        SAMPLE=$(basename "$R1" | sed 's/_1.nonhost.fastq.gz//')
        R2="${INPUT_DIR}/${SAMPLE}_2.nonhost.fastq.gz"
        
        if [[ ! -f "$R2" ]]; then
            log_warning "Pair not found for ${SAMPLE}, skipping..."
            continue
        fi
        
        log_info "Running Kraken2 on sample: ${SAMPLE}"
        
        KRAKEN_OUTPUT="${KRAKEN_DIR}/${SAMPLE}.kraken2.output"
        KRAKEN_REPORT="${KRAKEN_DIR}/${SAMPLE}.kraken2.report"
        
        kraken2 \
            --db "${KRAKEN2_DB}" \
            --threads ${THREADS} \
            --paired \
            --gzip-compressed \
            --output "${KRAKEN_OUTPUT}" \
            --report "${KRAKEN_REPORT}" \
            --use-names \
            "$R1" "$R2" \
            2>&1 | tee "${LOGS_DIR}/${SAMPLE}_kraken2.log"
        
        log_success "  Kraken2 completed for ${SAMPLE}"
        
        # Compress kraken output (can be large)
        gzip "${KRAKEN_OUTPUT}"
    done
    
    log_success "Kraken2 analysis completed for all samples"
fi

################################################################################
# STEP 2: Bracken Abundance Estimation
################################################################################

if [[ "$SKIP_KRAKEN" == false ]]; then
    log_info "====================================================================="
    log_info "  STEP 2: Bracken Abundance Estimation"
    log_info "====================================================================="
    
    for KRAKEN_REPORT in "${KRAKEN_DIR}"/*.kraken2.report; do
        SAMPLE=$(basename "$KRAKEN_REPORT" | sed 's/.kraken2.report//')
        
        log_info "Running Bracken on sample: ${SAMPLE}"
        
        BRACKEN_OUTPUT="${BRACKEN_DIR}/${SAMPLE}.bracken.${BRACKEN_LEVEL}"
        BRACKEN_REPORT="${BRACKEN_DIR}/${SAMPLE}.bracken.report"
        
        bracken \
            -d "${KRAKEN2_DB}" \
            -i "${KRAKEN_REPORT}" \
            -o "${BRACKEN_OUTPUT}" \
            -w "${BRACKEN_REPORT}" \
            -r ${BRACKEN_READ_LEN} \
            -l ${BRACKEN_LEVEL} \
            -t 10 \
            2>&1 | tee "${LOGS_DIR}/${SAMPLE}_bracken.log"
        
        log_success "  Bracken completed for ${SAMPLE}"
    done
    
    log_success "Bracken analysis completed for all samples"
fi

################################################################################
# STEP 3: MetaPhlAn Profiling
################################################################################

if [[ "$SKIP_METAPHLAN" == false ]]; then
    log_info "====================================================================="
    log_info "  STEP 3: MetaPhlAn Marker-based Profiling"
    log_info "====================================================================="
    
    for R1 in "${INPUT_DIR}"/*_1.nonhost.fastq.gz; do
        SAMPLE=$(basename "$R1" | sed 's/_1.nonhost.fastq.gz//')
        R2="${INPUT_DIR}/${SAMPLE}_2.nonhost.fastq.gz"
        
        if [[ ! -f "$R2" ]]; then
            continue
        fi
        
        log_info "Running MetaPhlAn on sample: ${SAMPLE}"
        
        METAPHLAN_OUTPUT="${METAPHLAN_DIR}/${SAMPLE}.metaphlan_profile.txt"
        METAPHLAN_BT2="${METAPHLAN_DIR}/${SAMPLE}.bowtie2.bz2"
        
        metaphlan \
            "$R1","$R2" \
            --input_type fastq \
            --bowtie2db "${METAPHLAN_DB}" \
            --nproc ${THREADS} \
            --bowtie2out "${METAPHLAN_BT2}" \
            --output_file "${METAPHLAN_OUTPUT}" \
            --unknown_estimation \
            2>&1 | tee "${LOGS_DIR}/${SAMPLE}_metaphlan.log"
        
        log_success "  MetaPhlAn completed for ${SAMPLE}"
    done
    
    log_success "MetaPhlAn analysis completed for all samples"
    
    # Merge MetaPhlAn profiles
    log_info "Merging MetaPhlAn profiles..."
    merge_metaphlan_tables.py \
        "${METAPHLAN_DIR}"/*_profile.txt \
        > "${METAPHLAN_DIR}/merged_abundance_table.txt"
    
    log_success "  Merged table: ${METAPHLAN_DIR}/merged_abundance_table.txt"
fi

################################################################################
# STEP 4: Krona Visualization
################################################################################

if [[ "$SKIP_KRAKEN" == false ]]; then
    log_info "====================================================================="
    log_info "  STEP 4: Krona Interactive Visualization"
    log_info "====================================================================="
    
    for KRAKEN_REPORT in "${KRAKEN_DIR}"/*.kraken2.report; do
        SAMPLE=$(basename "$KRAKEN_REPORT" | sed 's/.kraken2.report//')
        
        log_info "Generating Krona chart for: ${SAMPLE}"
        
        KRONA_HTML="${KRONA_DIR}/${SAMPLE}.krona.html"
        
        # Convert Kraken2 report to Krona format and generate chart
        ktImportTaxonomy \
            -q 1 -t 2 -s 3 \
            "${KRAKEN_REPORT}" \
            -o "${KRONA_HTML}"
        
        log_success "  Krona chart: ${KRONA_HTML}"
    done
    
    log_success "Krona visualizations completed"
fi

################################################################################
# STEP 5: Generate Summary Statistics
################################################################################

log_info "====================================================================="
log_info "  STEP 5: Summary Statistics"
log_info "====================================================================="

SUMMARY_FILE="${OUTPUT_DIR}/taxonomic_summary.txt"

cat > "${SUMMARY_FILE}" << EOF
================================================================================
Taxonomic Profiling Summary Report
Generated: $(date)
================================================================================

Project Directory: ${PROJECT_DIR}
Input Directory:   ${INPUT_DIR}
Output Directory:  ${OUTPUT_DIR}

Tools Run:
  - Kraken2:   $([ "$SKIP_KRAKEN" == false ] && echo "Yes" || echo "No")
  - Bracken:   $([ "$SKIP_KRAKEN" == false ] && echo "Yes" || echo "No")
  - MetaPhlAn: $([ "$SKIP_METAPHLAN" == false ] && echo "Yes" || echo "No")

Parameters:
  - Threads:            ${THREADS}
  - Kraken2 database:   ${KRAKEN2_DB}
  - MetaPhlAn database: ${METAPHLAN_DB}
  - Bracken level:      ${BRACKEN_LEVEL} (Species)
  - Bracken read len:   ${BRACKEN_READ_LEN}

================================================================================
Sample Results:
================================================================================

EOF

# Add per-sample summary
for R1 in "${INPUT_DIR}"/*_1.nonhost.fastq.gz; do
    SAMPLE=$(basename "$R1" | sed 's/_1.nonhost.fastq.gz//')
    
    cat >> "${SUMMARY_FILE}" << EOF
Sample: ${SAMPLE}
----------------------------------------

EOF
    
    # Kraken2 stats
    if [[ -f "${KRAKEN_DIR}/${SAMPLE}.kraken2.report" ]]; then
        CLASSIFIED=$(grep -P "^\s+[0-9]" "${KRAKEN_DIR}/${SAMPLE}.kraken2.report" | head -1 | awk '{print $1}')
        cat >> "${SUMMARY_FILE}" << EOF
Kraken2:
  - Report:           ${KRAKEN_DIR}/${SAMPLE}.kraken2.report
  - Classified reads: ${CLASSIFIED}%

EOF
    fi
    
    # Bracken stats
    if [[ -f "${BRACKEN_DIR}/${SAMPLE}.bracken.${BRACKEN_LEVEL}" ]]; then
        NUM_TAXA=$(tail -n +2 "${BRACKEN_DIR}/${SAMPLE}.bracken.${BRACKEN_LEVEL}" | wc -l)
        cat >> "${SUMMARY_FILE}" << EOF
Bracken:
  - Output:          ${BRACKEN_DIR}/${SAMPLE}.bracken.${BRACKEN_LEVEL}
  - Taxa identified: ${NUM_TAXA} species

EOF
    fi
    
    # MetaPhlAn stats
    if [[ -f "${METAPHLAN_DIR}/${SAMPLE}.metaphlan_profile.txt" ]]; then
        NUM_SPECIES=$(grep "s__" "${METAPHLAN_DIR}/${SAMPLE}.metaphlan_profile.txt" | grep -v "t__" | wc -l)
        cat >> "${SUMMARY_FILE}" << EOF
MetaPhlAn:
  - Profile:         ${METAPHLAN_DIR}/${SAMPLE}.metaphlan_profile.txt
  - Species found:   ${NUM_SPECIES}

EOF
    fi
    
    # Krona
    if [[ -f "${KRONA_DIR}/${SAMPLE}.krona.html" ]]; then
        cat >> "${SUMMARY_FILE}" << EOF
Visualization:
  - Krona chart:     ${KRONA_DIR}/${SAMPLE}.krona.html

EOF
    fi
    
    echo "" >> "${SUMMARY_FILE}"
done

cat >> "${SUMMARY_FILE}" << EOF
================================================================================
Output Files Summary:
================================================================================

Kraken2 Results:
  - Directory:  ${KRAKEN_DIR}
  - Reports:    *.kraken2.report
  - Raw output: *.kraken2.output.gz

Bracken Results:
  - Directory:  ${BRACKEN_DIR}
  - Abundances: *.bracken.${BRACKEN_LEVEL}
  - Reports:    *.bracken.report

MetaPhlAn Results:
  - Directory:      ${METAPHLAN_DIR}
  - Profiles:       *.metaphlan_profile.txt
  - Merged table:   merged_abundance_table.txt

Krona Visualizations:
  - Directory:  ${KRONA_DIR}
  - Charts:     *.krona.html (Open in web browser)

Logs:
  - Directory:  ${LOGS_DIR}

================================================================================
Key Files to Review:
================================================================================

For each sample:
  1. Kraken2 report:    ${KRAKEN_DIR}/[SAMPLE].kraken2.report
  2. Bracken species:   ${BRACKEN_DIR}/[SAMPLE].bracken.${BRACKEN_LEVEL}
  3. MetaPhlAn profile: ${METAPHLAN_DIR}/[SAMPLE].metaphlan_profile.txt
  4. Krona chart:       ${KRONA_DIR}/[SAMPLE].krona.html ⭐ START HERE!

Comparative analysis:
  - MetaPhlAn merged:   ${METAPHLAN_DIR}/merged_abundance_table.txt

================================================================================
Next Steps:
================================================================================

1. Open Krona HTML files in web browser for interactive exploration
2. Review taxonomic composition in Kraken2/Bracken reports
3. Compare samples using MetaPhlAn merged table
4. Proceed to functional profiling: bash scripts/04_functional_profiling.sh

================================================================================
EOF

log_success "Summary report generated: ${SUMMARY_FILE}"
cat "${SUMMARY_FILE}"

################################################################################
# COMPLETION
################################################################################

log_success "====================================================================="
log_success "  Taxonomic Profiling Pipeline Completed!"
log_success "====================================================================="

log_info "Key outputs:"
log_info "  - Kraken2:   ${KRAKEN_DIR}"
log_info "  - Bracken:   ${BRACKEN_DIR}"
log_info "  - MetaPhlAn: ${METAPHLAN_DIR}"
log_info "  - Krona:     ${KRONA_DIR}"
log_info "  - Summary:   ${SUMMARY_FILE}"
log_info ""
log_info "Next step: bash scripts/04_functional_profiling.sh"
