#!/bin/bash

################################################################################
# Script: 02_host_removal.sh
# Description: Remove host (e.g., human) contamination from metagenomic reads
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

# Project directory
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Input/Output directories
INPUT_DIR="${PROJECT_DIR}/trimmed_fastq"
OUTPUT_DIR="${PROJECT_DIR}/host_removed"
STATS_DIR="${OUTPUT_DIR}/alignment_stats"
LOGS_DIR="${OUTPUT_DIR}/logs"

# Create output directories
mkdir -p "${OUTPUT_DIR}"
mkdir -p "${STATS_DIR}"
mkdir -p "${LOGS_DIR}"

# Computational resources
THREADS=8

# Host genome reference (Bowtie2 index)
# Update this path based on your setup from 00_setup_databases.sh
HOST_GENOME="${HOME}/metagenomics_databases/host_genome/human/human_genome"

# Check if host genome exists
if [[ ! -f "${HOST_GENOME}.1.bt2" ]]; then
    log_error "Host genome index not found: ${HOST_GENOME}"
    log_info "Please run: bash scripts/00_setup_databases.sh"
    log_info "Or update HOST_GENOME path in this script"
    exit 1
fi

################################################################################
# ACTIVATE CONDA ENVIRONMENT
################################################################################

log_info "Activating conda environment..."
eval "$(conda shell.bash hook)"
conda activate shotgun-metagenomics-pipeline

################################################################################
# STEP 1: Host Read Removal with Bowtie2
################################################################################

log_info "====================================================================="
log_info "  Host DNA Removal Pipeline"
log_info "====================================================================="

log_info "Host genome: ${HOST_GENOME}"
log_info "Input directory: ${INPUT_DIR}"
log_info "Output directory: ${OUTPUT_DIR}"
log_info "Threads: ${THREADS}"
echo ""

# Process each sample
for R1 in "${INPUT_DIR}"/*_1.trimmed.fastq.gz; do
    SAMPLE=$(basename "$R1" | sed 's/_1.trimmed.fastq.gz//')
    R2="${INPUT_DIR}/${SAMPLE}_2.trimmed.fastq.gz"
    
    if [[ ! -f "$R2" ]]; then
        log_warning "Pair not found for ${SAMPLE}, skipping..."
        continue
    fi
    
    log_info "Processing sample: ${SAMPLE}"
    
    # Output files
    NONHOST_R1="${OUTPUT_DIR}/${SAMPLE}_1.nonhost.fastq.gz"
    NONHOST_R2="${OUTPUT_DIR}/${SAMPLE}_2.nonhost.fastq.gz"
    HOST_R1="${OUTPUT_DIR}/${SAMPLE}_1.host.fastq.gz"
    HOST_R2="${OUTPUT_DIR}/${SAMPLE}_2.host.fastq.gz"
    SAM_FILE="${OUTPUT_DIR}/${SAMPLE}.aligned.sam"
    
    log_info "  Aligning reads to host genome..."
    
    # Align reads to host genome
    bowtie2 \
        -x "${HOST_GENOME}" \
        -1 "$R1" \
        -2 "$R2" \
        -S "${SAM_FILE}" \
        --threads ${THREADS} \
        --very-sensitive-local \
        --un-conc-gz "${OUTPUT_DIR}/${SAMPLE}_%.nonhost.fastq.gz" \
        --al-conc-gz "${OUTPUT_DIR}/${SAMPLE}_%.host.fastq.gz" \
        2>&1 | tee "${LOGS_DIR}/${SAMPLE}_bowtie2.log"
    
    # Rename output files to match expected names
    mv "${OUTPUT_DIR}/${SAMPLE}_1.nonhost.fastq.gz" "$NONHOST_R1" 2>/dev/null || true
    mv "${OUTPUT_DIR}/${SAMPLE}_2.nonhost.fastq.gz" "$NONHOST_R2" 2>/dev/null || true
    mv "${OUTPUT_DIR}/${SAMPLE}_1.host.fastq.gz" "$HOST_R1" 2>/dev/null || true
    mv "${OUTPUT_DIR}/${SAMPLE}_2.host.fastq.gz" "$HOST_R2" 2>/dev/null || true
    
    log_success "  Alignment completed for ${SAMPLE}"
    
    # Generate alignment statistics
    log_info "  Generating alignment statistics..."
    
    # Count reads
    TRIMMED_READS=$(zcat "$R1" | wc -l | awk '{print $1/4}')
    NONHOST_READS=$(zcat "$NONHOST_R1" | wc -l | awk '{print $1/4}')
    HOST_READS=$(zcat "$HOST_R1" | wc -l | awk '{print $1/4}')
    
    HOST_PCT=$(echo "scale=2; $HOST_READS / $TRIMMED_READS * 100" | bc)
    NONHOST_PCT=$(echo "scale=2; $NONHOST_READS / $TRIMMED_READS * 100" | bc)
    
    # Save statistics
    cat > "${STATS_DIR}/${SAMPLE}_stats.txt" << EOF
Host Removal Statistics for ${SAMPLE}
Generated: $(date)

Input reads (trimmed):      ${TRIMMED_READS}
Host reads removed:         ${HOST_READS} (${HOST_PCT}%)
Non-host reads retained:    ${NONHOST_READS} (${NONHOST_PCT}%)

Files:
  - Non-host R1: ${NONHOST_R1}
  - Non-host R2: ${NONHOST_R2}
  - Host R1:     ${HOST_R1}
  - Host R2:     ${HOST_R2}
EOF
    
    log_info "  Statistics for ${SAMPLE}:"
    log_info "    Input reads:        ${TRIMMED_READS}"
    log_info "    Host reads:         ${HOST_READS} (${HOST_PCT}%)"
    log_info "    Non-host reads:     ${NONHOST_READS} (${NONHOST_PCT}%)"
    
    # Clean up SAM file (large)
    rm -f "${SAM_FILE}"
    
done

log_success "All samples processed"

################################################################################
# STEP 2: Generate Summary Report
################################################################################

log_info "====================================================================="
log_info "  Generating Summary Report"
log_info "====================================================================="

SUMMARY_FILE="${OUTPUT_DIR}/host_removal_summary.txt"

cat > "${SUMMARY_FILE}" << EOF
================================================================================
Host Removal Summary Report
Generated: $(date)
================================================================================

Project Directory: ${PROJECT_DIR}
Input Directory:   ${INPUT_DIR}
Output Directory:  ${OUTPUT_DIR}
Host Genome:       ${HOST_GENOME}

Parameters:
  - Threads:       ${THREADS}
  - Sensitivity:   very-sensitive-local

================================================================================
Sample Statistics:
================================================================================

EOF

# Aggregate statistics
for STATS in "${STATS_DIR}"/*_stats.txt; do
    if [[ -f "$STATS" ]]; then
        cat "$STATS" >> "${SUMMARY_FILE}"
        echo "" >> "${SUMMARY_FILE}"
        echo "----------------------------------------" >> "${SUMMARY_FILE}"
        echo "" >> "${SUMMARY_FILE}"
    fi
done

cat >> "${SUMMARY_FILE}" << EOF
================================================================================
Output Files:
================================================================================

Non-host reads (for downstream analysis):
  - Location: ${OUTPUT_DIR}
  - Pattern:  *_1.nonhost.fastq.gz, *_2.nonhost.fastq.gz

Host reads (for quality check):
  - Location: ${OUTPUT_DIR}
  - Pattern:  *_1.host.fastq.gz, *_2.host.fastq.gz

Statistics:
  - Per-sample: ${STATS_DIR}
  - Logs:       ${LOGS_DIR}

================================================================================
Quality Assessment:
================================================================================

Typical host contamination levels:
  - Human samples:          50-99% human DNA
  - Environmental samples:  <5% human DNA
  - Synthetic communities:  <1% contaminant DNA

If host contamination is unusually high or low:
  1. Check sample collection protocol
  2. Verify host genome reference is correct
  3. Review Bowtie2 alignment logs in ${LOGS_DIR}

================================================================================
Next Steps:
================================================================================

1. Review host removal statistics above
2. Verify non-host read counts are sufficient for analysis
3. Proceed to taxonomic profiling: bash scripts/03_taxonomic_profiling.sh

Note: Non-host reads will be used for all downstream analyses

================================================================================
EOF

log_success "Summary report generated: ${SUMMARY_FILE}"

# Display summary
cat "${SUMMARY_FILE}"

################################################################################
# STEP 3: Optional - Quality Check on Non-host Reads
################################################################################

log_info "====================================================================="
log_info "  Optional: Quality Check on Non-host Reads"
log_info "====================================================================="

read -p "Run FastQC on non-host reads? (y/n): " run_qc

if [[ "$run_qc" =~ ^[Yy]$ ]]; then
    QC_OUTPUT="${OUTPUT_DIR}/qc_nonhost"
    mkdir -p "${QC_OUTPUT}"
    
    log_info "Running FastQC on non-host reads..."
    fastqc \
        --threads ${THREADS} \
        --outdir "${QC_OUTPUT}" \
        "${OUTPUT_DIR}"/*.nonhost.fastq.gz
    
    log_info "Generating MultiQC report..."
    multiqc \
        "${QC_OUTPUT}" \
        --outdir "${QC_OUTPUT}" \
        --filename nonhost_reads_multiqc_report.html \
        --title "Non-host Reads QC Report" \
        --force
    
    log_success "QC completed: ${QC_OUTPUT}/nonhost_reads_multiqc_report.html"
fi

################################################################################
# COMPLETION
################################################################################

log_success "====================================================================="
log_success "  Host Removal Pipeline Completed!"
log_success "====================================================================="

log_info "Summary report: ${SUMMARY_FILE}"
log_info "Non-host reads: ${OUTPUT_DIR}/*.nonhost.fastq.gz"
log_info ""
log_info "Next step: bash scripts/03_taxonomic_profiling.sh"
