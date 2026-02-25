#!/bin/bash

################################################################################
# Script: 00_setup_databases.sh
# Description: Download and setup all required databases for metagenomics
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

# Base directory for all databases
DB_BASE_DIR="${HOME}/metagenomics_databases"

# Individual database directories
KRAKEN2_DIR="${DB_BASE_DIR}/kraken2"
METAPHLAN_DIR="${DB_BASE_DIR}/metaphlan"
HUMANN_DIR="${DB_BASE_DIR}/humann"
CHECKM_DIR="${DB_BASE_DIR}/checkm"
GTDBTK_DIR="${DB_BASE_DIR}/gtdbtk"
HOST_GENOME_DIR="${DB_BASE_DIR}/host_genome"

# Create base directory
mkdir -p "${DB_BASE_DIR}"

################################################################################
# ACTIVATE CONDA ENVIRONMENT
################################################################################

log_info "Activating conda environment..."
if conda env list | grep -q "sm-pipeline"; then
    eval "$(conda shell.bash hook)"
    conda activate shotgun-metagenomics-pipeline
    log_success "Environment activated"
else
    log_error "Environment 'shotgun-metagenomics-pipeline' not found"
    log_info "Please run: conda env create -f environment.yml"
    exit 1
fi

################################################################################
# FUNCTION: Download Kraken2 Database
################################################################################

setup_kraken2() {
    log_info "Setting up Kraken2 database..."
    
    echo ""
    echo "Kraken2 Database Options:"
    echo "  1) Standard (8 GB)       - archaea, bacteria, viral, plasmid, human, UniVec_Core"
    echo "  2) PlusPF (35 GB)        - Standard + protozoa, fungi"
    echo "  3) PlusPFP (100 GB)      - PlusPF + plant"
    echo "  4) Skip Kraken2 database"
    echo ""
    read -p "Select Kraken2 database [1-4]: " kraken_choice
    
    case $kraken_choice in
        1)
            DB_NAME="standard"
            mkdir -p "${KRAKEN2_DIR}/${DB_NAME}"
            log_info "Downloading Kraken2 Standard database (8 GB)..."
            kraken2-build --download-taxonomy --db "${KRAKEN2_DIR}/${DB_NAME}"
            kraken2-build --download-library archaea --db "${KRAKEN2_DIR}/${DB_NAME}"
            kraken2-build --download-library bacteria --db "${KRAKEN2_DIR}/${DB_NAME}"
            kraken2-build --download-library viral --db "${KRAKEN2_DIR}/${DB_NAME}"
            kraken2-build --download-library plasmid --db "${KRAKEN2_DIR}/${DB_NAME}"
            kraken2-build --download-library human --db "${KRAKEN2_DIR}/${DB_NAME}"
            kraken2-build --download-library UniVec_Core --db "${KRAKEN2_DIR}/${DB_NAME}"
            kraken2-build --build --db "${KRAKEN2_DIR}/${DB_NAME}"
            log_success "Kraken2 Standard database installed"
            ;;
        2)
            DB_NAME="pluspf"
            mkdir -p "${KRAKEN2_DIR}/${DB_NAME}"
            log_info "Downloading Kraken2 PlusPF database (35 GB)..."
            kraken2-build --download-taxonomy --db "${KRAKEN2_DIR}/${DB_NAME}"
            for lib in archaea bacteria viral plasmid human UniVec_Core protozoa fungi; do
                kraken2-build --download-library $lib --db "${KRAKEN2_DIR}/${DB_NAME}"
            done
            kraken2-build --build --db "${KRAKEN2_DIR}/${DB_NAME}"
            log_success "Kraken2 PlusPF database installed"
            ;;
        3)
            DB_NAME="pluspfp"
            mkdir -p "${KRAKEN2_DIR}/${DB_NAME}"
            log_info "Downloading Kraken2 PlusPFP database (100 GB)..."
            kraken2-build --download-taxonomy --db "${KRAKEN2_DIR}/${DB_NAME}"
            for lib in archaea bacteria viral plasmid human UniVec_Core protozoa fungi plant; do
                kraken2-build --download-library $lib --db "${KRAKEN2_DIR}/${DB_NAME}"
            done
            kraken2-build --build --db "${KRAKEN2_DIR}/${DB_NAME}"
            log_success "Kraken2 PlusPFP database installed"
            ;;
        4)
            log_warning "Skipping Kraken2 database"
            return
            ;;
        *)
            log_error "Invalid choice"
            return
            ;;
    esac
    
    # Save database path
    echo "KRAKEN2_DB=${KRAKEN2_DIR}/${DB_NAME}" >> "${DB_BASE_DIR}/database_config.txt"
}

################################################################################
# FUNCTION: Download MetaPhlAn Database
################################################################################

setup_metaphlan() {
    log_info "Setting up MetaPhlAn database..."
    
    read -p "Download MetaPhlAn database? (y/n): " choice
    if [[ ! "$choice" =~ ^[Yy]$ ]]; then
        log_warning "Skipping MetaPhlAn database"
        return
    fi
    
    mkdir -p "${METAPHLAN_DIR}"
    log_info "Downloading MetaPhlAn database (~3 GB)..."
    
    # MetaPhlAn will auto-download on first run, but we can pre-download
    metaphlan --install --bowtie2db "${METAPHLAN_DIR}"
    
    log_success "MetaPhlAn database installed"
    echo "METAPHLAN_DB=${METAPHLAN_DIR}" >> "${DB_BASE_DIR}/database_config.txt"
}

################################################################################
# FUNCTION: Download HUMAnN Databases
################################################################################

setup_humann() {
    log_info "Setting up HUMAnN databases..."
    
    read -p "Download HUMAnN databases? (y/n): " choice
    if [[ ! "$choice" =~ ^[Yy]$ ]]; then
        log_warning "Skipping HUMAnN databases"
        return
    fi
    
    mkdir -p "${HUMANN_DIR}"
    log_info "Downloading HUMAnN databases (~20 GB)..."
    
    # Download ChocoPhlAn (pangenome database)
    humann_databases --download chocophlan full "${HUMANN_DIR}"
    
    # Download UniRef90 (protein database) - Diamond format
    humann_databases --download uniref uniref90_diamond "${HUMANN_DIR}"
    
    # Download utility mapping files
    humann_databases --download utility_mapping full "${HUMANN_DIR}"
    
    log_success "HUMAnN databases installed"
    echo "HUMANN_DB=${HUMANN_DIR}" >> "${DB_BASE_DIR}/database_config.txt"
}

################################################################################
# FUNCTION: Download CheckM Database
################################################################################

setup_checkm() {
    log_info "Setting up CheckM database..."
    
    read -p "Download CheckM database? (y/n): " choice
    if [[ ! "$choice" =~ ^[Yy]$ ]]; then
        log_warning "Skipping CheckM database"
        return
    fi
    
    mkdir -p "${CHECKM_DIR}"
    log_info "Downloading CheckM database (~300 MB)..."
    
    cd "${CHECKM_DIR}"
    wget -c https://data.ace.uq.edu.au/public/CheckM_databases/checkm_data_2015_01_16.tar.gz
    tar -xzf checkm_data_2015_01_16.tar.gz
    rm checkm_data_2015_01_16.tar.gz
    
    # Set CheckM data location
    checkm data setRoot "${CHECKM_DIR}"
    
    log_success "CheckM database installed"
    echo "CHECKM_DB=${CHECKM_DIR}" >> "${DB_BASE_DIR}/database_config.txt"
}

################################################################################
# FUNCTION: Download GTDB-Tk Database
################################################################################

setup_gtdbtk() {
    log_info "Setting up GTDB-Tk database..."
    
    read -p "Download GTDB-Tk database? (WARNING: ~85 GB) (y/n): " choice
    if [[ ! "$choice" =~ ^[Yy]$ ]]; then
        log_warning "Skipping GTDB-Tk database"
        return
    fi
    
    mkdir -p "${GTDBTK_DIR}"
    log_info "Downloading GTDB-Tk database (~85 GB, this will take a while)..."
    
    cd "${GTDBTK_DIR}"
    wget -c https://data.gtdb.ecogenomic.org/releases/latest/auxillary_files/gtdbtk_data.tar.gz
    tar -xzf gtdbtk_data.tar.gz
    rm gtdbtk_data.tar.gz
    
    # Set GTDB-Tk data location
    export GTDBTK_DATA_PATH="${GTDBTK_DIR}"
    echo "export GTDBTK_DATA_PATH=${GTDBTK_DIR}" >> ~/.bashrc
    
    log_success "GTDB-Tk database installed"
    echo "GTDBTK_DB=${GTDBTK_DIR}" >> "${DB_BASE_DIR}/database_config.txt"
}

################################################################################
# FUNCTION: Download Host Genome (Human)
################################################################################

setup_host_genome() {
    log_info "Setting up host genome for removal..."
    
    echo ""
    echo "Host Genome Options:"
    echo "  1) Human (GRCh38) - ~3 GB"
    echo "  2) Mouse (GRCm39) - ~2.7 GB"
    echo "  3) Custom (provide path)"
    echo "  4) Skip host genome"
    echo ""
    read -p "Select host genome [1-4]: " host_choice
    
    case $host_choice in
        1)
            mkdir -p "${HOST_GENOME_DIR}/human"
            log_info "Downloading human reference genome (GRCh38)..."
            cd "${HOST_GENOME_DIR}/human"
            
            # Download from NCBI
            wget -c ftp://ftp.ncbi.nlm.nih.gov/genomes/all/GCA/000/001/405/GCA_000001405.15_GRCh38/seqs_for_alignment_pipelines.ucsc_ids/GCA_000001405.15_GRCh38_no_alt_analysis_set.fna.gz
            gunzip GCA_000001405.15_GRCh38_no_alt_analysis_set.fna.gz
            
            # Build Bowtie2 index
            log_info "Building Bowtie2 index..."
            bowtie2-build GCA_000001405.15_GRCh38_no_alt_analysis_set.fna human_genome
            
            log_success "Human genome installed and indexed"
            echo "HOST_GENOME=${HOST_GENOME_DIR}/human/human_genome" >> "${DB_BASE_DIR}/database_config.txt"
            ;;
        2)
            mkdir -p "${HOST_GENOME_DIR}/mouse"
            log_info "Downloading mouse reference genome (GRCm39)..."
            cd "${HOST_GENOME_DIR}/mouse"
            
            wget -c ftp://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/000/001/635/GCF_000001635.27_GRCm39/GCF_000001635.27_GRCm39_genomic.fna.gz
            gunzip GCF_000001635.27_GRCm39_genomic.fna.gz
            
            log_info "Building Bowtie2 index..."
            bowtie2-build GCF_000001635.27_GRCm39_genomic.fna mouse_genome
            
            log_success "Mouse genome installed and indexed"
            echo "HOST_GENOME=${HOST_GENOME_DIR}/mouse/mouse_genome" >> "${DB_BASE_DIR}/database_config.txt"
            ;;
        3)
            read -p "Enter path to host genome FASTA: " custom_path
            if [[ -f "$custom_path" ]]; then
                mkdir -p "${HOST_GENOME_DIR}/custom"
                cp "$custom_path" "${HOST_GENOME_DIR}/custom/host_genome.fna"
                
                log_info "Building Bowtie2 index..."
                cd "${HOST_GENOME_DIR}/custom"
                bowtie2-build host_genome.fna host_genome
                
                log_success "Custom genome indexed"
                echo "HOST_GENOME=${HOST_GENOME_DIR}/custom/host_genome" >> "${DB_BASE_DIR}/database_config.txt"
            else
                log_error "File not found: $custom_path"
            fi
            ;;
        4)
            log_warning "Skipping host genome"
            ;;
        *)
            log_error "Invalid choice"
            ;;
    esac
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
    log_info "====================================================================="
    log_info "  Metagenomics Database Setup"
    log_info "====================================================================="
    
    # Create fresh config file
    echo "# Metagenomics Database Configuration" > "${DB_BASE_DIR}/database_config.txt"
    echo "# Generated: $(date)" >> "${DB_BASE_DIR}/database_config.txt"
    echo "" >> "${DB_BASE_DIR}/database_config.txt"
    
    # Check disk space
    AVAILABLE_SPACE=$(df -BG "${DB_BASE_DIR}" | tail -1 | awk '{print $4}' | sed 's/G//')
    log_info "Available disk space: ${AVAILABLE_SPACE} GB"
    
    if [[ $AVAILABLE_SPACE -lt 50 ]]; then
        log_warning "Low disk space! Recommended: 100+ GB available"
        read -p "Continue anyway? (y/n): " continue_choice
        [[ ! "$continue_choice" =~ ^[Yy]$ ]] && exit 1
    fi
    
    # Setup databases
    setup_kraken2
    echo ""
    setup_metaphlan
    echo ""
    setup_humann
    echo ""
    setup_checkm
    echo ""
    setup_gtdbtk
    echo ""
    setup_host_genome
    
    # Summary
    echo ""
    log_success "====================================================================="
    log_success "  Database Setup Complete!"
    log_success "====================================================================="
    echo ""
    log_info "Configuration saved to: ${DB_BASE_DIR}/database_config.txt"
    log_info "Database location: ${DB_BASE_DIR}"
    echo ""
    log_info "To use these databases in your pipeline, source the config file:"
    echo "  source ${DB_BASE_DIR}/database_config.txt"
    echo ""
    log_info "Next steps:"
    echo "  1. Update database paths in your pipeline scripts"
    echo "  2. Run QC and preprocessing: bash scripts/01_qc_trim.sh"
    echo ""
}

# Run main function
main
