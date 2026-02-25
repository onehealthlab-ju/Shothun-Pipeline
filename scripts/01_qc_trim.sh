#!/bin/bash

################################################################################
# Script: 01_qc_trim.sh
# Description: Quality control and read trimming for shotgun metagenomics
# Author: Md. Jubayer Hossain
# Date: 2026-02-25
################################################################################

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored messages
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

################################################################################
# CONFIGURATION
################################################################################

# Project directory (assuming script is in scripts/ subdirectory)
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Input/Output directories
RAW_FASTQ_DIR="${PROJECT_DIR}/raw_fastq"
TRIMMED_DIR="${PROJECT_DIR}/trimmed_fastq"
QC_DIR="${PROJECT_DIR}/qc_reports"
RAW_QC_DIR="${QC_DIR}/raw_reports"
TRIMMED_QC_DIR="${QC_DIR}/trimmed_reports"
MULTIQC_DIR="${QC_DIR}/multiqc_reports"

# Create output directories
mkdir -p "${TRIMMED_DIR}"
mkdir -p "${RAW_QC_DIR}"
mkdir -p "${TRIMMED_QC_DIR}"
mkdir -p "${MULTIQC_DIR}"

# Computational resources
THREADS=8  # Adjust based on your system

# Quality filtering parameters
MIN_LENGTH=50         # Minimum read length after trimming
MIN_QUALITY=20        # Minimum base quality (Q20 = 99% accuracy)
WINDOW_SIZE=4         # Sliding window size for quality trimming
MEAN_QUALITY=20       # Mean quality in sliding window

################################################################################
# ACTIVATE CONDA ENVIRONMENT
################################################################################

log_info "Activating conda environment..."
if conda env list | grep -q "shotgun-metagenomics-pipeline"; then
    eval "$(conda shell.bash hook)"
    conda activate shotgun-metagenomics-pipeline
    log_success "Environment activated"
else
    log_error "Environment 'shotgun-metagenomics-pipeline' not found"
    log_info "Please run: conda env create -f ${PROJECT_DIR}/environment.yml"
    exit 1
fi

################################################################################
# STEP 1: Quality Control of Raw Reads (FastQC)
################################################################################

log_info "====================================================================="
log_info "  STEP 1: Quality Control of Raw Reads"
log_info "====================================================================="

log_info "Running FastQC on raw reads..."
fastqc \
    --threads ${THREADS} \
    --outdir "${RAW_QC_DIR}" \
    "${RAW_FASTQ_DIR}"/*.fastq.gz

log_success "FastQC completed on raw reads"

################################################################################
# STEP 2: Trimming and Filtering with fastp
################################################################################

log_info "====================================================================="
log_info "  STEP 2: Read Trimming and Filtering"
log_info "====================================================================="

# Find all sample pairs
for R1 in "${RAW_FASTQ_DIR}"/*_1.fastq.gz; do
    # Get sample name
    SAMPLE=$(basename "$R1" | sed 's/_1.fastq.gz//')
    R2="${RAW_FASTQ_DIR}/${SAMPLE}_2.fastq.gz"
    
    # Check if R2 exists
    if [[ ! -f "$R2" ]]; then
        log_warning "Pair not found for ${SAMPLE}, skipping..."
        continue
    fi
    
    log_info "Processing sample: ${SAMPLE}"
    
    # Output files
    TRIM_R1="${TRIMMED_DIR}/${SAMPLE}_1.trimmed.fastq.gz"
    TRIM_R2="${TRIMMED_DIR}/${SAMPLE}_2.trimmed.fastq.gz"
    JSON_REPORT="${TRIMMED_DIR}/${SAMPLE}_fastp.json"
    HTML_REPORT="${TRIMMED_DIR}/${SAMPLE}_fastp.html"
    
    # Run fastp
    log_info "  Running fastp..."
    fastp \
        --in1 "$R1" \
        --in2 "$R2" \
        --out1 "$TRIM_R1" \
        --out2 "$TRIM_R2" \
        --thread ${THREADS} \
        --qualified_quality_phred ${MIN_QUALITY} \
        --length_required ${MIN_LENGTH} \
        --cut_front \
        --cut_tail \
        --cut_window_size ${WINDOW_SIZE} \
        --cut_mean_quality ${MEAN_QUALITY} \
        --detect_adapter_for_pe \
        --correction \
        --overrepresentation_analysis \
        --json "$JSON_REPORT" \
        --html "$HTML_REPORT" \
        2>&1 | tee "${TRIMMED_DIR}/${SAMPLE}_fastp.log"
    
    log_success "  Trimming completed for ${SAMPLE}"
    
    # Get basic statistics
    TOTAL_READS=$(zcat "$R1" | wc -l | awk '{print $1/4}')
    CLEAN_READS=$(zcat "$TRIM_R1" | wc -l | awk '{print $1/4}')
    RETAINED_PCT=$(echo "scale=2; $CLEAN_READS / $TOTAL_READS * 100" | bc)
    
    log_info "  Statistics for ${SAMPLE}:"
    log_info "    Total reads:    ${TOTAL_READS}"
    log_info "    Retained reads: ${CLEAN_READS} (${RETAINED_PCT}%)"
    
done

log_success "All samples trimmed successfully"

################################################################################
# STEP 3: Quality Control of Trimmed Reads (FastQC)
################################################################################

log_info "====================================================================="
log_info "  STEP 3: Quality Control of Trimmed Reads"
log_info "====================================================================="

log_info "Running FastQC on trimmed reads..."
fastqc \
    --threads ${THREADS} \
    --outdir "${TRIMMED_QC_DIR}" \
    "${TRIMMED_DIR}"/*.trimmed.fastq.gz

log_success "FastQC completed on trimmed reads"

################################################################################
# STEP 4: Aggregate QC Reports with MultiQC
################################################################################

log_info "====================================================================="
log_info "  STEP 4: Aggregating QC Reports"
log_info "====================================================================="

# MultiQC for raw reads
log_info "Creating MultiQC report for raw reads..."
multiqc \
    "${RAW_QC_DIR}" \
    --outdir "${MULTIQC_DIR}/raw" \
    --filename raw_reads_multiqc_report.html \
    --title "Raw Reads QC Report" \
    --force

# MultiQC for trimmed reads
log_info "Creating MultiQC report for trimmed reads..."
multiqc \
    "${TRIMMED_QC_DIR}" \
    --outdir "${MULTIQC_DIR}/trimmed" \
    --filename trimmed_reads_multiqc_report.html \
    --title "Trimmed Reads QC Report" \
    --force

# MultiQC for fastp reports
log_info "Creating MultiQC report for fastp statistics..."
multiqc \
    "${TRIMMED_DIR}" \
    --outdir "${MULTIQC_DIR}/fastp" \
    --filename fastp_multiqc_report.html \
    --title "Fastp Trimming Statistics" \
    --force

log_success "MultiQC reports generated"

################################################################################
# STEP 5: Generate Summary Statistics
################################################################################

log_info "====================================================================="
log_info "  STEP 5: Summary Statistics"
log_info "====================================================================="

SUMMARY_FILE="${QC_DIR}/qc_summary.txt"

cat > "${SUMMARY_FILE}" << EOF
================================================================================
QC and Trimming Summary Report
Generated: $(date)
================================================================================

Project Directory: ${PROJECT_DIR}
Raw Reads: ${RAW_FASTQ_DIR}
Trimmed Reads: ${TRIMMED_DIR}

Parameters Used:
  - Minimum length: ${MIN_LENGTH} bp
  - Minimum quality: Q${MIN_QUALITY}
  - Window size: ${WINDOW_SIZE}
  - Mean quality: Q${MEAN_QUALITY}
  - Threads: ${THREADS}

================================================================================
Sample Statistics:
================================================================================

EOF

# Add per-sample statistics
for R1 in "${RAW_FASTQ_DIR}"/*_1.fastq.gz; do
    SAMPLE=$(basename "$R1" | sed 's/_1.fastq.gz//')
    TRIM_R1="${TRIMMED_DIR}/${SAMPLE}_1.trimmed.fastq.gz"
    
    if [[ -f "$TRIM_R1" ]]; then
        TOTAL_READS=$(zcat "$R1" | wc -l | awk '{print $1/4}')
        CLEAN_READS=$(zcat "$TRIM_R1" | wc -l | awk '{print $1/4}')
        RETAINED_PCT=$(echo "scale=2; $CLEAN_READS / $TOTAL_READS * 100" | bc)
        
        cat >> "${SUMMARY_FILE}" << EOF
Sample: ${SAMPLE}
  Total raw reads:      ${TOTAL_READS}
  Trimmed reads:        ${CLEAN_READS}
  Retention rate:       ${RETAINED_PCT}%

EOF
    fi
done

cat >> "${SUMMARY_FILE}" << EOF
================================================================================
Output Files:
================================================================================

QC Reports:
  - Raw reads FastQC:       ${RAW_QC_DIR}
  - Trimmed reads FastQC:   ${TRIMMED_QC_DIR}
  - MultiQC reports:        ${MULTIQC_DIR}

Trimmed Reads:
  - Location:               ${TRIMMED_DIR}
  - Format:                 *_1.trimmed.fastq.gz, *_2.trimmed.fastq.gz

Key Files to Review:
  - ${MULTIQC_DIR}/raw/raw_reads_multiqc_report.html
  - ${MULTIQC_DIR}/trimmed/trimmed_reads_multiqc_report.html
  - ${MULTIQC_DIR}/fastp/fastp_multiqc_report.html

================================================================================
Next Steps:
================================================================================

1. Review MultiQC reports to assess data quality
2. Check that retention rates are acceptable (typically >70%)
3. Proceed to host removal: bash scripts/02_host_removal.sh

================================================================================
EOF

log_success "Summary report generated: ${SUMMARY_FILE}"

# Display summary
cat "${SUMMARY_FILE}"

################################################################################
# COMPLETION
################################################################################

log_success "====================================================================="
log_success "  QC and Trimming Pipeline Completed!"
log_success "====================================================================="

log_info "Review the following reports:"
log_info "  1. Raw reads:    ${MULTIQC_DIR}/raw/raw_reads_multiqc_report.html"
log_info "  2. Trimmed reads: ${MULTIQC_DIR}/trimmed/trimmed_reads_multiqc_report.html"
log_info "  3. Fastp stats:   ${MULTIQC_DIR}/fastp/fastp_multiqc_report.html"
log_info "  4. Summary:       ${SUMMARY_FILE}"

log_info ""
log_info "Next step: bash scripts/02_host_removal.sh"