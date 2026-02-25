#!/bin/bash

################################################################################
# Script: 04_functional_profiling.sh
# Description: Functional profiling with HUMAnN3 (gene families and pathways)
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
OUTPUT_DIR="${PROJECT_DIR}/functional_profiling"
HUMANN_RAW="${OUTPUT_DIR}/humann_raw"
HUMANN_NORM="${OUTPUT_DIR}/humann_normalized"
HUMANN_MERGED="${OUTPUT_DIR}/humann_merged"
LOGS_DIR="${OUTPUT_DIR}/logs"

# Create directories
mkdir -p "${HUMANN_RAW}" "${HUMANN_NORM}" "${HUMANN_MERGED}" "${LOGS_DIR}"

# Computational resources
THREADS=8

# Database paths (update based on your setup)
HUMANN_DB="${HOME}/metagenomics_databases/humann"
METAPHLAN_DB="${HOME}/metagenomics_databases/metaphlan"

################################################################################
# ACTIVATE CONDA ENVIRONMENT
################################################################################

log_info "Activating conda environment..."
eval "$(conda shell.bash hook)"
conda activate shotgun-metagenomics-pipeline

################################################################################
# CHECK DATABASES
################################################################################

log_info "Checking HUMAnN database availability..."

if [[ ! -d "${HUMANN_DB}" ]]; then
    log_error "HUMAnN database not found: ${HUMANN_DB}"
    log_info "Please run: bash scripts/00_setup_databases.sh"
    exit 1
fi

# Configure HUMAnN to use databases
humann_config --update database_folders nucleotide "${HUMANN_DB}/chocophlan"
humann_config --update database_folders protein "${HUMANN_DB}/uniref"
humann_config --update database_folders utility_mapping "${HUMANN_DB}/utility_mapping"

log_success "HUMAnN databases configured"

################################################################################
# STEP 1: Concatenate Paired-end Reads
################################################################################

log_info "====================================================================="
log_info "  STEP 1: Preparing Input (Concatenating Paired Reads)"
log_info "====================================================================="

CONCAT_DIR="${OUTPUT_DIR}/concatenated_reads"
mkdir -p "${CONCAT_DIR}"

for R1 in "${INPUT_DIR}"/*_1.nonhost.fastq.gz; do
    SAMPLE=$(basename "$R1" | sed 's/_1.nonhost.fastq.gz//')
    R2="${INPUT_DIR}/${SAMPLE}_2.nonhost.fastq.gz"
    
    if [[ ! -f "$R2" ]]; then
        log_warning "Pair not found for ${SAMPLE}, skipping..."
        continue
    fi
    
    log_info "Concatenating reads for sample: ${SAMPLE}"
    
    CONCAT_FILE="${CONCAT_DIR}/${SAMPLE}.concat.fastq.gz"
    
    # Concatenate R1 and R2 (HUMAnN3 works with single concatenated file)
    cat "$R1" "$R2" > "${CONCAT_FILE}"
    
    log_success "  Concatenated: ${CONCAT_FILE}"
done

log_success "Read concatenation completed"

################################################################################
# STEP 2: Run HUMAnN3
################################################################################

log_info "====================================================================="
log_info "  STEP 2: Running HUMAnN3 Functional Profiling"
log_info "====================================================================="

for CONCAT_FILE in "${CONCAT_DIR}"/*.concat.fastq.gz; do
    SAMPLE=$(basename "$CONCAT_FILE" | sed 's/.concat.fastq.gz//')
    
    log_info "Running HUMAnN3 on sample: ${SAMPLE}"
    log_warning "  This may take 1-3 hours per sample depending on data size"
    
    humann \
        --input "${CONCAT_FILE}" \
        --output "${HUMANN_RAW}" \
        --output-basename "${SAMPLE}" \
        --threads ${THREADS} \
        --metaphlan-options "--bowtie2db ${METAPHLAN_DB}" \
        --remove-temp-output \
        2>&1 | tee "${LOGS_DIR}/${SAMPLE}_humann.log"
    
    log_success "  HUMAnN3 completed for ${SAMPLE}"
done

log_success "HUMAnN3 analysis completed for all samples"

################################################################################
# STEP 3: Normalize and Regroup Tables
################################################################################

log_info "====================================================================="
log_info "  STEP 3: Normalizing and Regrouping HUMAnN3 Output"
log_info "====================================================================="

# Process each sample's gene families
for GENEFAM_FILE in "${HUMANN_RAW}"/*_genefamilies.tsv; do
    SAMPLE=$(basename "$GENEFAM_FILE" | sed 's/_genefamilies.tsv//')
    
    log_info "Processing sample: ${SAMPLE}"
    
    # Normalize gene families to CPM (copies per million)
    log_info "  Normalizing gene families to CPM..."
    humann_renorm_table \
        --input "${GENEFAM_FILE}" \
        --output "${HUMANN_NORM}/${SAMPLE}_genefamilies_cpm.tsv" \
        --units cpm
    
    # Normalize gene families to relative abundance
    log_info "  Normalizing gene families to relative abundance..."
    humann_renorm_table \
        --input "${GENEFAM_FILE}" \
        --output "${HUMANN_NORM}/${SAMPLE}_genefamilies_relab.tsv" \
        --units relab
    
    # Regroup gene families to different functional categories
    log_info "  Regrouping to GO terms..."
    humann_regroup_table \
        --input "${GENEFAM_FILE}" \
        --output "${HUMANN_NORM}/${SAMPLE}_go.tsv" \
        --groups uniref90_go
    
    log_info "  Regrouping to KEGG orthologs..."
    humann_regroup_table \
        --input "${GENEFAM_FILE}" \
        --output "${HUMANN_NORM}/${SAMPLE}_ko.tsv" \
        --groups uniref90_ko
    
    log_info "  Regrouping to Pfam domains..."
    humann_regroup_table \
        --input "${GENEFAM_FILE}" \
        --output "${HUMANN_NORM}/${SAMPLE}_pfam.tsv" \
        --groups uniref90_pfam
    
    # Normalize pathway abundance
    log_info "  Normalizing pathway abundance..."
    humann_renorm_table \
        --input "${HUMANN_RAW}/${SAMPLE}_pathabundance.tsv" \
        --output "${HUMANN_NORM}/${SAMPLE}_pathabundance_relab.tsv" \
        --units relab
    
    log_success "  Normalization completed for ${SAMPLE}"
done

log_success "Normalization and regrouping completed"

################################################################################
# STEP 4: Merge Tables Across Samples
################################################################################

log_info "====================================================================="
log_info "  STEP 4: Merging Tables Across Samples"
log_info "====================================================================="

# Merge gene families
if ls "${HUMANN_RAW}"/*_genefamilies.tsv 1> /dev/null 2>&1; then
    log_info "Merging gene families..."
    humann_join_tables \
        --input "${HUMANN_RAW}" \
        --output "${HUMANN_MERGED}/all_samples_genefamilies.tsv" \
        --file_name genefamilies.tsv
fi

# Merge normalized gene families (CPM)
if ls "${HUMANN_NORM}"/*_genefamilies_cpm.tsv 1> /dev/null 2>&1; then
    log_info "Merging normalized gene families (CPM)..."
    humann_join_tables \
        --input "${HUMANN_NORM}" \
        --output "${HUMANN_MERGED}/all_samples_genefamilies_cpm.tsv" \
        --file_name genefamilies_cpm.tsv
fi

# Merge pathway abundances
if ls "${HUMANN_RAW}"/*_pathabundance.tsv 1> /dev/null 2>&1; then
    log_info "Merging pathway abundances..."
    humann_join_tables \
        --input "${HUMANN_RAW}" \
        --output "${HUMANN_MERGED}/all_samples_pathabundance.tsv" \
        --file_name pathabundance.tsv
fi

# Merge normalized pathway abundances
if ls "${HUMANN_NORM}"/*_pathabundance_relab.tsv 1> /dev/null 2>&1; then
    log_info "Merging normalized pathway abundances..."
    humann_join_tables \
        --input "${HUMANN_NORM}" \
        --output "${HUMANN_MERGED}/all_samples_pathabundance_relab.tsv" \
        --file_name pathabundance_relab.tsv
fi

# Merge pathway coverage
if ls "${HUMANN_RAW}"/*_pathcoverage.tsv 1> /dev/null 2>&1; then
    log_info "Merging pathway coverage..."
    humann_join_tables \
        --input "${HUMANN_RAW}" \
        --output "${HUMANN_MERGED}/all_samples_pathcoverage.tsv" \
        --file_name pathcoverage.tsv
fi

log_success "Table merging completed"

################################################################################
# STEP 5: Generate Summary Statistics
################################################################################

log_info "====================================================================="
log_info "  STEP 5: Summary Statistics"
log_info "====================================================================="

SUMMARY_FILE="${OUTPUT_DIR}/functional_summary.txt"

cat > "${SUMMARY_FILE}" << EOF
================================================================================
Functional Profiling Summary Report
Generated: $(date)
================================================================================

Project Directory: ${PROJECT_DIR}
Input Directory:   ${INPUT_DIR}
Output Directory:  ${OUTPUT_DIR}

HUMAnN3 Configuration:
  - Database:     ${HUMANN_DB}
  - Threads:      ${THREADS}
  - MetaPhlAn DB: ${METAPHLAN_DB}

================================================================================
Sample Results:
================================================================================

EOF

# Add per-sample statistics
for GENEFAM_FILE in "${HUMANN_RAW}"/*_genefamilies.tsv; do
    SAMPLE=$(basename "$GENEFAM_FILE" | sed 's/_genefamilies.tsv//')
    
    # Count features
    NUM_GENEFAM=$(tail -n +2 "$GENEFAM_FILE" | wc -l)
    NUM_PATHWAYS=$(tail -n +2 "${HUMANN_RAW}/${SAMPLE}_pathabundance.tsv" | wc -l)
    
    cat >> "${SUMMARY_FILE}" << EOF
Sample: ${SAMPLE}
----------------------------------------
Gene Families Detected:   ${NUM_GENEFAM}
Pathways Detected:        ${NUM_PATHWAYS}

Output Files:
  - Gene families:         ${HUMANN_RAW}/${SAMPLE}_genefamilies.tsv
  - Pathway abundance:     ${HUMANN_RAW}/${SAMPLE}_pathabundance.tsv
  - Pathway coverage:      ${HUMANN_RAW}/${SAMPLE}_pathcoverage.tsv
  - Normalized (CPM):      ${HUMANN_NORM}/${SAMPLE}_genefamilies_cpm.tsv
  - Normalized (relab):    ${HUMANN_NORM}/${SAMPLE}_genefamilies_relab.tsv
  - GO terms:              ${HUMANN_NORM}/${SAMPLE}_go.tsv
  - KEGG orthologs:        ${HUMANN_NORM}/${SAMPLE}_ko.tsv
  - Pfam domains:          ${HUMANN_NORM}/${SAMPLE}_pfam.tsv

EOF
done

cat >> "${SUMMARY_FILE}" << EOF
================================================================================
Merged Tables (All Samples):
================================================================================

Gene Families:
  - Raw:                   ${HUMANN_MERGED}/all_samples_genefamilies.tsv
  - Normalized (CPM):      ${HUMANN_MERGED}/all_samples_genefamilies_cpm.tsv

Pathways:
  - Abundance (raw):       ${HUMANN_MERGED}/all_samples_pathabundance.tsv
  - Abundance (relab):     ${HUMANN_MERGED}/all_samples_pathabundance_relab.tsv
  - Coverage:              ${HUMANN_MERGED}/all_samples_pathcoverage.tsv

================================================================================
Output Directory Structure:
================================================================================

${OUTPUT_DIR}/
├── humann_raw/              Raw HUMAnN3 output
│   ├── *_genefamilies.tsv
│   ├── *_pathabundance.tsv
│   └── *_pathcoverage.tsv
│
├── humann_normalized/       Normalized and regrouped tables
│   ├── *_genefamilies_cpm.tsv
│   ├── *_genefamilies_relab.tsv
│   ├── *_pathabundance_relab.tsv
│   ├── *_go.tsv
│   ├── *_ko.tsv
│   └── *_pfam.tsv
│
├── humann_merged/           Merged tables across samples
│   ├── all_samples_genefamilies.tsv
│   ├── all_samples_pathabundance.tsv
│   └── all_samples_pathcoverage.tsv
│
├── concatenated_reads/      Temporary concatenated input files
└── logs/                    HUMAnN3 execution logs

================================================================================
Understanding the Output:
================================================================================

1. Gene Families (*_genefamilies.tsv):
   - UniRef90 gene family abundances
   - Stratified by species (which species contributes to each function)
   - Units: RPK (reads per kilobase)

2. Pathway Abundance (*_pathabundance.tsv):
   - MetaCyc pathway abundances
   - Calculated from gene families
   - Units: RPK

3. Pathway Coverage (*_pathcoverage.tsv):
   - Percentage of each pathway detected
   - Ranges from 0 (not detected) to 1 (complete)

4. Normalized Tables:
   - CPM: Copies per million (accounts for sequencing depth)
   - Relab: Relative abundance (proportions summing to 1)

5. Regrouped Tables:
   - GO: Gene Ontology terms
   - KO: KEGG Orthology groups
   - Pfam: Protein family domains

================================================================================
Typical Values:
================================================================================

Well-sequenced human gut microbiome:
  - Gene families:  5,000 - 15,000
  - Pathways:       200 - 600
  - Pathway coverage: >0.5 for core metabolic pathways

Environmental samples may have:
  - More gene families (higher diversity)
  - Lower pathway coverage (incomplete pathways)

================================================================================
Next Steps:
================================================================================

1. Review merged tables for comparative analysis:
   - ${HUMANN_MERGED}/all_samples_pathabundance_relab.tsv ⭐ START HERE

2. Identify differentially abundant pathways between groups

3. Visualize pathway abundances (heatmaps, bar plots)

4. Perform statistical analysis in R using the merged tables

5. Proceed to assembly: bash scripts/05_assembly.sh

================================================================================
EOF

log_success "Summary report generated: ${SUMMARY_FILE}"
cat "${SUMMARY_FILE}"

################################################################################
# COMPLETION
################################################################################

log_success "====================================================================="
log_success "  Functional Profiling Pipeline Completed!"
log_success "====================================================================="

log_info "Key outputs:"
log_info "  - Raw:       ${HUMANN_RAW}"
log_info "  - Normalized: ${HUMANN_NORM}"
log_info "  - Merged:    ${HUMANN_MERGED}"
log_info "  - Summary:   ${SUMMARY_FILE}"
log_info ""
log_info "Next step: bash scripts/05_assembly.sh"
