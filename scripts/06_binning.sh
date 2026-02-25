#!/bin/bash

################################################################################
# Script: 06_binning.sh
# Description: Metagenomic binning with MetaBAT2, MaxBin2, and bin refinement
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
CONTIGS_DIR="${PROJECT_DIR}/assembly/filtered_contigs"
READS_DIR="${PROJECT_DIR}/host_removed"
OUTPUT_DIR="${PROJECT_DIR}/binning"
BAM_DIR="${OUTPUT_DIR}/bam_files"
METABAT_DIR="${OUTPUT_DIR}/metabat2_bins"
MAXBIN_DIR="${OUTPUT_DIR}/maxbin2_bins"
REFINED_DIR="${OUTPUT_DIR}/refined_bins"
CHECKM_DIR="${OUTPUT_DIR}/checkm_quality"
LOGS_DIR="${OUTPUT_DIR}/logs"

# Create directories
mkdir -p "${BAM_DIR}" "${METABAT_DIR}" "${MAXBIN_DIR}" "${REFINED_DIR}" "${CHECKM_DIR}" "${LOGS_DIR}"

# Computational resources
THREADS=8

################################################################################
# ACTIVATE CONDA ENVIRONMENT
################################################################################

log_info "Activating conda environment..."
eval "$(conda shell.bash hook)"
conda activate shotgun-metagenomics-pipeline

################################################################################
# STEP 1: Select Assembly and Index Contigs
################################################################################

log_info "====================================================================="
log_info "  STEP 1: Selecting Assembly for Binning"
log_info "====================================================================="

# List available assemblies
log_info "Available assemblies:"
ls -1 "${CONTIGS_DIR}"/*.fa 2>/dev/null || {
    log_error "No assembly files found in ${CONTIGS_DIR}"
    log_info "Please run: bash scripts/05_assembly.sh"
    exit 1
}

echo ""
read -p "Enter sample name (or 'all' for all samples): " selected_sample

if [[ "$selected_sample" == "all" ]]; then
    CONTIGS_FILES=("${CONTIGS_DIR}"/*.fa)
    log_info "Processing all samples: ${#CONTIGS_FILES[@]} assemblies"
else
    # Find matching assembly (either MEGAHIT or SPAdes)
    MEGAHIT_FILE="${CONTIGS_DIR}/${selected_sample}_megahit_contigs.fa"
    SPADES_FILE="${CONTIGS_DIR}/${selected_sample}_spades_contigs.fa"
    
    if [[ -f "$MEGAHIT_FILE" && -f "$SPADES_FILE" ]]; then
        read -p "Both MEGAHIT and SPAdes assemblies found. Select: (1) MEGAHIT, (2) SPAdes: " asm_choice
        case $asm_choice in
            1) CONTIGS_FILES=("$MEGAHIT_FILE") ;;
            2) CONTIGS_FILES=("$SPADES_FILE") ;;
            *) log_error "Invalid choice"; exit 1 ;;
        esac
    elif [[ -f "$MEGAHIT_FILE" ]]; then
        CONTIGS_FILES=("$MEGAHIT_FILE")
        log_info "Using MEGAHIT assembly"
    elif [[ -f "$SPADES_FILE" ]]; then
        CONTIGS_FILES=("$SPADES_FILE")
        log_info "Using SPAdes assembly"
    else
        log_error "No assembly found for sample: ${selected_sample}"
        exit 1
    fi
fi

################################################################################
# STEP 2: Index Contigs and Map Reads
################################################################################

log_info "====================================================================="
log_info "  STEP 2: Mapping Reads to Assemblies"
log_info "====================================================================="

for CONTIGS_FILE in "${CONTIGS_FILES[@]}"; do
    # Extract sample and assembler info
    FILENAME=$(basename "$CONTIGS_FILE")
    if [[ "$FILENAME" =~ (.+)_megahit_contigs\.fa ]]; then
        SAMPLE="${BASH_REMATCH[1]}"
        ASSEMBLER="megahit"
    elif [[ "$FILENAME" =~ (.+)_spades_contigs\.fa ]]; then
        SAMPLE="${BASH_REMATCH[1]}"
        ASSEMBLER="spades"
    else
        log_warning "Could not parse filename: $FILENAME, skipping..."
        continue
    fi
    
    log_info "Processing sample: ${SAMPLE} (${ASSEMBLER})"
    
    # Input reads
    R1="${READS_DIR}/${SAMPLE}_1.nonhost.fastq.gz"
    R2="${READS_DIR}/${SAMPLE}_2.nonhost.fastq.gz"
    
    if [[ ! -f "$R1" || ! -f "$R2" ]]; then
        log_warning "Reads not found for ${SAMPLE}, skipping..."
        continue
    fi
    
    # Index contigs with BWA
    log_info "  Indexing contigs..."
    bwa index "$CONTIGS_FILE" 2>&1 | tee "${LOGS_DIR}/${SAMPLE}_${ASSEMBLER}_bwa_index.log"
    
    # Map reads to contigs
    log_info "  Mapping reads with BWA..."
    SAM_FILE="${BAM_DIR}/${SAMPLE}_${ASSEMBLER}.sam"
    BAM_FILE="${BAM_DIR}/${SAMPLE}_${ASSEMBLER}.bam"
    SORTED_BAM="${BAM_DIR}/${SAMPLE}_${ASSEMBLER}.sorted.bam"
    
    bwa mem \
        -t ${THREADS} \
        "$CONTIGS_FILE" \
        "$R1" "$R2" \
        > "$SAM_FILE" \
        2>&1 | tee "${LOGS_DIR}/${SAMPLE}_${ASSEMBLER}_bwa_mem.log"
    
    # Convert to BAM and sort
    log_info "  Converting to BAM and sorting..."
    samtools view -@ ${THREADS} -bS "$SAM_FILE" > "$BAM_FILE"
    samtools sort -@ ${THREADS} "$BAM_FILE" -o "$SORTED_BAM"
    samtools index "$SORTED_BAM"
    
    # Clean up intermediate files
    rm -f "$SAM_FILE" "$BAM_FILE"
    
    log_success "  Mapping completed for ${SAMPLE}"
done

log_success "Read mapping completed for all samples"

################################################################################
# STEP 3: Calculate Contig Depth with MetaBAT2
################################################################################

log_info "====================================================================="
log_info "  STEP 3: Calculating Contig Depth"
log_info "====================================================================="

for SORTED_BAM in "${BAM_DIR}"/*.sorted.bam; do
    BASENAME=$(basename "$SORTED_BAM" | sed 's/.sorted.bam//')
    
    log_info "Calculating depth for: ${BASENAME}"
    
    DEPTH_FILE="${BAM_DIR}/${BASENAME}_depth.txt"
    
    jgi_summarize_bam_contig_depths \
        --outputDepth "$DEPTH_FILE" \
        "$SORTED_BAM" \
        2>&1 | tee "${LOGS_DIR}/${BASENAME}_depth.log"
    
    log_success "  Depth file: ${DEPTH_FILE}"
done

log_success "Depth calculation completed"

################################################################################
# STEP 4: Binning with MetaBAT2
################################################################################

log_info "====================================================================="
log_info "  STEP 4: Binning with MetaBAT2"
log_info "====================================================================="

for CONTIGS_FILE in "${CONTIGS_FILES[@]}"; do
    FILENAME=$(basename "$CONTIGS_FILE")
    if [[ "$FILENAME" =~ (.+)_megahit_contigs\.fa ]]; then
        SAMPLE="${BASH_REMATCH[1]}"
        ASSEMBLER="megahit"
    elif [[ "$FILENAME" =~ (.+)_spades_contigs\.fa ]]; then
        SAMPLE="${BASH_REMATCH[1]}"
        ASSEMBLER="spades"
    else
        continue
    fi
    
    DEPTH_FILE="${BAM_DIR}/${SAMPLE}_${ASSEMBLER}_depth.txt"
    
    if [[ ! -f "$DEPTH_FILE" ]]; then
        log_warning "Depth file not found for ${SAMPLE}, skipping..."
        continue
    fi
    
    log_info "Running MetaBAT2 on: ${SAMPLE} (${ASSEMBLER})"
    
    METABAT_OUT="${METABAT_DIR}/${SAMPLE}_${ASSEMBLER}"
    
    metabat2 \
        -i "$CONTIGS_FILE" \
        -a "$DEPTH_FILE" \
        -o "${METABAT_OUT}/bin" \
        -t ${THREADS} \
        --minContig 2500 \
        --minCVSum 1.0 \
        --saveCls \
        --seed 42 \
        2>&1 | tee "${LOGS_DIR}/${SAMPLE}_${ASSEMBLER}_metabat2.log"
    
    # Count bins
    NUM_BINS=$(find "${METABAT_OUT}" -name "bin.*.fa" 2>/dev/null | wc -l)
    log_success "  MetaBAT2 generated ${NUM_BINS} bins for ${SAMPLE}"
done

log_success "MetaBAT2 binning completed"

################################################################################
# STEP 5: Binning with MaxBin2
################################################################################

log_info "====================================================================="
log_info "  STEP 5: Binning with MaxBin2"
log_info "====================================================================="

for CONTIGS_FILE in "${CONTIGS_FILES[@]}"; do
    FILENAME=$(basename "$CONTIGS_FILE")
    if [[ "$FILENAME" =~ (.+)_megahit_contigs\.fa ]]; then
        SAMPLE="${BASH_REMATCH[1]}"
        ASSEMBLER="megahit"
    elif [[ "$FILENAME" =~ (.+)_spades_contigs\.fa ]]; then
        SAMPLE="${BASH_REMATCH[1]}"
        ASSEMBLER="spades"
    else
        continue
    fi
    
    SORTED_BAM="${BAM_DIR}/${SAMPLE}_${ASSEMBLER}.sorted.bam"
    
    if [[ ! -f "$SORTED_BAM" ]]; then
        log_warning "BAM file not found for ${SAMPLE}, skipping..."
        continue
    fi
    
    log_info "Running MaxBin2 on: ${SAMPLE} (${ASSEMBLER})"
    
    # Create abundance file for MaxBin2
    ABUND_FILE="${BAM_DIR}/${SAMPLE}_${ASSEMBLER}_abundance.txt"
    pileup.sh \
        in="$SORTED_BAM" \
        out="${ABUND_FILE}" \
        2>&1 | tee "${LOGS_DIR}/${SAMPLE}_${ASSEMBLER}_pileup.log"
    
    MAXBIN_OUT="${MAXBIN_DIR}/${SAMPLE}_${ASSEMBLER}"
    mkdir -p "$MAXBIN_OUT"
    
    run_MaxBin.pl \
        -contig "$CONTIGS_FILE" \
        -abund "$ABUND_FILE" \
        -out "${MAXBIN_OUT}/bin" \
        -thread ${THREADS} \
        -min_contig_length 2500 \
        2>&1 | tee "${LOGS_DIR}/${SAMPLE}_${ASSEMBLER}_maxbin2.log"
    
    # Count bins
    NUM_BINS=$(find "${MAXBIN_OUT}" -name "bin.*.fasta" 2>/dev/null | wc -l)
    log_success "  MaxBin2 generated ${NUM_BINS} bins for ${SAMPLE}"
done

log_success "MaxBin2 binning completed"

################################################################################
# STEP 6: Bin Quality Assessment with CheckM
################################################################################

log_info "====================================================================="
log_info "  STEP 6: Bin Quality Assessment (CheckM)"
log_info "====================================================================="

# Assess MetaBAT2 bins
if ls "${METABAT_DIR}"/*/*.fa 1> /dev/null 2>&1; then
    log_info "Running CheckM on MetaBAT2 bins..."
    
    checkm lineage_wf \
        -t ${THREADS} \
        -x fa \
        "${METABAT_DIR}" \
        "${CHECKM_DIR}/metabat2" \
        2>&1 | tee "${LOGS_DIR}/checkm_metabat2.log"
    
    # Generate summary
    checkm qa \
        "${CHECKM_DIR}/metabat2/lineage.ms" \
        "${CHECKM_DIR}/metabat2" \
        -o 2 \
        -f "${CHECKM_DIR}/metabat2_summary.tsv" \
        --tab_table
    
    log_success "  CheckM results: ${CHECKM_DIR}/metabat2_summary.tsv"
fi

# Assess MaxBin2 bins
if ls "${MAXBIN_DIR}"/*/*.fasta 1> /dev/null 2>&1; then
    log_info "Running CheckM on MaxBin2 bins..."
    
    checkm lineage_wf \
        -t ${THREADS} \
        -x fasta \
        "${MAXBIN_DIR}" \
        "${CHECKM_DIR}/maxbin2" \
        2>&1 | tee "${LOGS_DIR}/checkm_maxbin2.log"
    
    # Generate summary
    checkm qa \
        "${CHECKM_DIR}/maxbin2/lineage.ms" \
        "${CHECKM_DIR}/maxbin2" \
        -o 2 \
        -f "${CHECKM_DIR}/maxbin2_summary.tsv" \
        --tab_table
    
    log_success "  CheckM results: ${CHECKM_DIR}/maxbin2_summary.tsv"
fi

log_success "CheckM quality assessment completed"

################################################################################
# STEP 7: Generate Summary Report
################################################################################

log_info "====================================================================="
log_info "  STEP 7: Generating Summary Report"
log_info "====================================================================="

SUMMARY_FILE="${OUTPUT_DIR}/binning_summary.txt"

cat > "${SUMMARY_FILE}" << EOF
================================================================================
Metagenomic Binning Summary Report
Generated: $(date)
================================================================================

Project Directory: ${PROJECT_DIR}
Contigs Directory: ${CONTIGS_DIR}
Reads Directory:   ${READS_DIR}
Output Directory:  ${OUTPUT_DIR}

Binning Parameters:
  - Threads:         ${THREADS}
  - Min contig:      2500 bp
  - Binners:         MetaBAT2, MaxBin2

================================================================================
Binning Results Summary:
================================================================================

EOF

# Count bins per sample
for SAMPLE_DIR in "${METABAT_DIR}"/*; do
    if [[ -d "$SAMPLE_DIR" ]]; then
        SAMPLE=$(basename "$SAMPLE_DIR")
        NUM_BINS=$(find "$SAMPLE_DIR" -name "bin.*.fa" 2>/dev/null | wc -l)
        
        echo "Sample: ${SAMPLE}" >> "${SUMMARY_FILE}"
        echo "  MetaBAT2 bins: ${NUM_BINS}" >> "${SUMMARY_FILE}"
    fi
done

echo "" >> "${SUMMARY_FILE}"

for SAMPLE_DIR in "${MAXBIN_DIR}"/*; do
    if [[ -d "$SAMPLE_DIR" ]]; then
        SAMPLE=$(basename "$SAMPLE_DIR")
        NUM_BINS=$(find "$SAMPLE_DIR" -name "bin.*.fasta" 2>/dev/null | wc -l)
        
        echo "Sample: ${SAMPLE}" >> "${SUMMARY_FILE}"
        echo "  MaxBin2 bins: ${NUM_BINS}" >> "${SUMMARY_FILE}"
    fi
done

cat >> "${SUMMARY_FILE}" << EOF

================================================================================
Output Files:
================================================================================

Read Mapping:
  - BAM files:      ${BAM_DIR}
  - Depth files:    ${BAM_DIR}/*_depth.txt

MetaBAT2 Bins:
  - Directory:      ${METABAT_DIR}
  - Bins:           */bin.*.fa
  - CheckM results: ${CHECKM_DIR}/metabat2_summary.tsv

MaxBin2 Bins:
  - Directory:      ${MAXBIN_DIR}
  - Bins:           */bin.*.fasta
  - CheckM results: ${CHECKM_DIR}/maxbin2_summary.tsv

Logs:
  - Directory:      ${LOGS_DIR}

================================================================================
Bin Quality Criteria (CheckM):
================================================================================

High-quality bins:
  - Completeness:   >90%
  - Contamination:  <5%
  - Status:         Near-complete genome

Medium-quality bins:
  - Completeness:   50-90%
  - Contamination:  <10%
  - Status:         Useful for analysis

Low-quality bins:
  - Completeness:   <50%
  - Contamination:  >10%
  - Status:         Use with caution or discard

CheckM markers:
  - Assesses presence of single-copy marker genes
  - Completeness = % of expected markers found
  - Contamination = duplicate markers (indicates mixed bins)

================================================================================
Interpreting Results:
================================================================================

Number of bins:
  - Depends on sample complexity and sequencing depth
  - Human gut: typically 10-50 bins
  - Environmental: highly variable (5-200+ bins)

Bin size:
  - Typical bacterial genome: 2-6 Mbp
  - Bins <1 Mbp may be incomplete
  - Very large bins (>10 Mbp) may indicate contamination

If few/no bins recovered:
  1. Check sequencing depth (may need deeper sequencing)
  2. Review assembly quality (poor assembly → poor binning)
  3. Consider sample complexity (very high diversity is challenging)
  4. Try adjusting binning parameters

If many low-quality bins:
  1. May indicate high strain heterogeneity
  2. Consider bin refinement with DAS Tool
  3. Try co-assembly across multiple samples

================================================================================
CheckM Results:
================================================================================

MetaBAT2 CheckM Summary:
EOF

if [[ -f "${CHECKM_DIR}/metabat2_summary.tsv" ]]; then
    cat "${CHECKM_DIR}/metabat2_summary.tsv" >> "${SUMMARY_FILE}"
else
    echo "  No CheckM results available" >> "${SUMMARY_FILE}"
fi

cat >> "${SUMMARY_FILE}" << EOF

MaxBin2 CheckM Summary:
EOF

if [[ -f "${CHECKM_DIR}/maxbin2_summary.tsv" ]]; then
    cat "${CHECKM_DIR}/maxbin2_summary.tsv" >> "${SUMMARY_FILE}"
else
    echo "  No CheckM results available" >> "${SUMMARY_FILE}"
fi

cat >> "${SUMMARY_FILE}" << EOF

================================================================================
Next Steps:
================================================================================

1. Review CheckM summaries to identify high-quality bins:
   - MetaBAT2: ${CHECKM_DIR}/metabat2_summary.tsv
   - MaxBin2:  ${CHECKM_DIR}/maxbin2_summary.tsv

2. Filter bins based on quality thresholds:
   - Keep: Completeness >50%, Contamination <10%

3. Optional bin refinement:
   - Use DAS Tool to create consensus bins from multiple binners
   - Improves bin quality by combining complementary results

4. Taxonomic classification of bins:
   - Use GTDB-Tk for taxonomic assignment
   - Provides species-level classification

5. Annotate bin genomes:
   - Use Prokka for functional annotation
   - Identify genes and metabolic pathways

6. Comparative genomics:
   - Compare bins across samples
   - Identify strain variation and gene content differences

================================================================================
EOF

log_success "Summary report generated: ${SUMMARY_FILE}"
cat "${SUMMARY_FILE}"

################################################################################
# COMPLETION
################################################################################

log_success "====================================================================="
log_success "  Binning Pipeline Completed!"
log_success "====================================================================="

log_info "Key outputs:"
log_info "  - MetaBAT2 bins: ${METABAT_DIR}"
log_info "  - MaxBin2 bins:  ${MAXBIN_DIR}"
log_info "  - CheckM results: ${CHECKM_DIR}"
log_info "  - Summary:       ${SUMMARY_FILE}"
log_info ""
log_info "Review CheckM summaries to identify high-quality MAGs!"
