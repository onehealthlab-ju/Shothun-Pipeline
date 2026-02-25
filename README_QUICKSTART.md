# Shotgun Metagenomics Pipeline - Quick Start Guide

## Overview

This pipeline performs comprehensive shotgun metagenomics analysis from raw reads to functional annotation, including:

1. **Quality Control** - FastQC, MultiQC
2. **Read Preprocessing** - Trimming, filtering, host removal
3. **Taxonomic Profiling** - Kraken2, Bracken, MetaPhlAn
4. **Functional Profiling** - HUMAnN3
5. **Assembly** - MEGAHIT
6. **Binning** - MetaBAT2, MaxBin2
7. **MAG Quality** - CheckM
8. **Annotation** - Prodigal, eggNOG-mapper
9. **Visualization** - Krona charts, MultiQC reports

---

## Installation

### Step 1: Setup Environment and Databases

```bash
# Make scripts executable
chmod +x setup_pipeline.sh run_metagenomics_pipeline.sh

# Run setup (this will take several hours depending on selected databases)
bash setup_pipeline.sh
```

The setup script will:
- Create conda environment from `environment.yml`
- Download and configure required databases
- Verify all tools are installed correctly

### Step 2: Activate Environment

```bash
conda activate shotgun-metagenomics-pipeline
```

---

## Quick Start

### Prepare Your Data

1. Create a `rawdata` directory and place your FASTQ files:

```bash
mkdir -p rawdata
# Copy your files as: rawdata/sample01_R1.fastq.gz and rawdata/sample01_R2.fastq.gz
```

2. Edit `run_metagenomics_pipeline.sh` configuration section (lines 20-50):

```bash
# Required edits:
SAMPLE_ID="your_sample_name"
HOST_GENOME="/path/to/host_genome/human_genome"  # From setup
KRAKEN2_DB="/path/to/kraken2_db"                 # From setup
HUMANN_DB="/path/to/humann_db"                   # From setup
CHECKM_DB="/path/to/checkm_data"                 # From setup
GTDBTK_DB="/path/to/gtdbtk_data"                 # From setup

# Adjust computational resources:
THREADS=16          # Number of CPU cores
MEMORY="64"         # Memory in GB
```

### Run the Pipeline

```bash
# Run complete pipeline
bash run_metagenomics_pipeline.sh
```

The pipeline will create a `results` directory with all outputs.

---

## Pipeline Steps in Detail

### Step 1: Quality Control (5-10 min)
- Runs FastQC on raw reads
- Generates HTML reports

**Output:** `results/qc/`

### Step 2: Preprocessing (10-30 min)
- Trims adapters and low-quality bases
- Removes short reads (<50bp by default)
- Generates fastp HTML report

**Output:** `results/preprocessing/`

### Step 3: Host Removal (30-60 min)
- Aligns reads to host genome (if provided)
- Extracts non-host reads for downstream analysis

**Output:** `results/preprocessing/*nonhost.fastq.gz`

### Step 4: Kraken2 Taxonomic Profiling (10-30 min)
- Classifies reads taxonomically
- Refines abundances with Bracken

**Output:** `results/taxonomic_profiling/*.kraken2.report`

### Step 5: MetaPhlAn Profiling (30-60 min)
- Marker-gene based taxonomic profiling
- Generates relative abundance tables

**Output:** `results/taxonomic_profiling/*.metaphlan.profile.txt`

### Step 6: HUMAnN Functional Profiling (1-3 hours)
- Identifies metabolic pathways
- Quantifies gene families and pathway abundances

**Output:** `results/functional_profiling/`

### Step 7: Assembly (2-6 hours)
- Assembles reads into contigs using MEGAHIT
- Minimum contig length: 1000bp

**Output:** `results/assembly/*_contigs.fa`

### Step 8: Assembly QC (5-10 min)
- Assesses assembly quality with QUAST
- Generates statistics report

**Output:** `results/assembly/*_quast/`

### Step 9: Read Mapping (30-90 min)
- Maps reads back to assembly
- Calculates contig coverage

**Output:** `results/assembly/*_mapped_sorted.bam`

### Step 10-11: Binning (1-3 hours)
- Bins contigs into MAGs using MetaBAT2 and MaxBin2
- Uses coverage and compositional information

**Output:** `results/binning/*_bin*.fa`

### Step 12: CheckM Quality (1-2 hours)
- Assesses bin completeness and contamination
- Identifies high-quality MAGs (>90% complete, <5% contamination)

**Output:** `results/binning/*_checkm_results.txt`

### Step 13: Gene Prediction (10-30 min)
- Predicts genes with Prodigal
- Generates protein and nucleotide sequences

**Output:** `results/annotation/*_proteins.faa`

### Step 14: Functional Annotation (2-4 hours)
- Annotates proteins with eggNOG-mapper
- Assigns COG, KEGG, GO terms

**Output:** `results/annotation/*_eggnog.emapper.annotations`

### Step 15-16: Visualization (5-10 min)
- Creates Krona charts for taxonomic composition
- Generates MultiQC report integrating all QC metrics

**Output:** `results/visualization/`

---

## Output Directory Structure

```
results/
├── qc/                           # FastQC reports
├── preprocessing/                # Clean reads
├── taxonomic_profiling/          # Kraken2, Bracken, MetaPhlAn results
├── functional_profiling/         # HUMAnN gene families and pathways
├── assembly/                     # Contigs, BAM files, QUAST reports
├── binning/                      # MAG bins and CheckM results
├── annotation/                   # Predicted genes and annotations
├── visualization/                # Krona charts and MultiQC reports
└── sample01_pipeline_summary.txt # Overall summary statistics
```

---

## Key Output Files

| File | Description |
|------|-------------|
| `results/visualization/sample01_multiqc_report.html` | Overall QC summary |
| `results/visualization/sample01_krona.html` | Interactive taxonomic tree |
| `results/taxonomic_profiling/sample01.kraken2.report` | Taxonomic abundances |
| `results/taxonomic_profiling/sample01.metaphlan.profile.txt` | MetaPhlAn profile |
| `results/functional_profiling/sample01_pathabundance_relab.tsv` | Pathway abundances |
| `results/assembly/sample01_contigs.fa` | Assembled contigs |
| `results/binning/sample01_checkm_results.txt` | MAG quality metrics |
| `results/annotation/sample01_eggnog.emapper.annotations` | Functional annotations |

---

## Computational Requirements

### Minimum Requirements:
- **CPU:** 8 cores
- **RAM:** 32 GB
- **Storage:** 100 GB (depends on database size)
- **Time:** 6-12 hours per sample

### Recommended Requirements:
- **CPU:** 16-32 cores
- **RAM:** 64-128 GB
- **Storage:** 500 GB
- **Time:** 3-6 hours per sample

### Database Sizes:
- Kraken2 Standard: ~8 GB
- Kraken2 PlusPF: ~35 GB
- MetaPhlAn: ~3 GB
- HUMAnN: ~20 GB
- CheckM: ~300 MB
- GTDB-Tk: ~85 GB

---

## Running Multiple Samples

To process multiple samples, you can create a batch script:

```bash
#!/bin/bash

SAMPLES=("sample01" "sample02" "sample03")

for SAMPLE in "${SAMPLES[@]}"; do
    echo "Processing ${SAMPLE}..."
    
    # Update SAMPLE_ID in the pipeline script
    sed -i "s/SAMPLE_ID=.*/SAMPLE_ID=\"${SAMPLE}\"/" run_metagenomics_pipeline.sh
    
    # Run pipeline
    bash run_metagenomics_pipeline.sh
    
    echo "Completed ${SAMPLE}"
done
```

---

## Troubleshooting

### Issue: Out of Memory
**Solution:** Reduce `THREADS` or increase `MEMORY` in configuration

### Issue: Database not found
**Solution:** Check paths in configuration section match your `setup_pipeline.sh` installation

### Issue: Missing tools
**Solution:** 
```bash
conda activate shotgun-metagenomics-pipeline
conda install -c bioconda <tool_name>
```

### Issue: Slow performance
**Solution:** 
- Increase `THREADS` value
- Use faster disk (SSD) for databases
- Consider using smaller databases (e.g., Kraken2 Standard instead of PlusPF)

### Issue: CheckM fails
**Solution:**
```bash
# Reset CheckM database path
echo /path/to/checkm_data | checkm data setRoot
```

---

## Advanced Options

### Skipping Steps

Comment out unwanted sections in `run_metagenomics_pipeline.sh`:

```bash
# Skip host removal by commenting out Step 3
# if [ -f "${HOST_GENOME}.1.bt2" ]; then
#     ... host removal code ...
# fi
```

### Custom Parameters

Edit parameters in the configuration section:

```bash
MIN_READ_LENGTH=75        # Stricter read length filter
MIN_QUALITY=25            # Higher quality threshold
THREADS=32                # More parallel processing
```

### Alternative Assemblers

Replace MEGAHIT with metaSPAdes for higher quality assembly:

```bash
# In Step 7, replace megahit command with:
spades.py \
    --meta \
    -1 ${CLEAN_R1} \
    -2 ${CLEAN_R2} \
    -o ${RESULTS_DIR}/assembly/${SAMPLE_ID}_spades \
    -t ${THREADS} \
    -m $((${MEMORY}))
```

---

## Tips for Best Results

1. **Quality Matters:** Start with high-quality sequencing data (Q30 > 80%)
2. **Sequencing Depth:** Aim for 10-50M paired-end reads per sample
3. **Host Removal:** Always remove host DNA for human/animal samples
4. **Database Selection:** Use appropriate databases for your sample type
5. **Validation:** Always check MultiQC and assembly quality reports
6. **Replicates:** Process biological replicates to assess reproducibility

---

## Citation

If you use this pipeline, please cite the tools:

- FastQC: Andrews (2010)
- fastp: Chen et al. (2018)
- Kraken2: Wood et al. (2019)
- MetaPhlAn: Beghini et al. (2021)
- HUMAnN: Franzosa et al. (2018)
- MEGAHIT: Li et al. (2015)
- MetaBAT2: Kang et al. (2019)
- CheckM: Parks et al. (2015)
- MultiQC: Ewels et al. (2016)

---

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review tool documentation in conda environment
3. Check log files in `results/` directory
4. Contact your bioinformatics support team

---

## License

This pipeline template is provided as-is for research use.
Individual tools have their own licenses - please review before commercial use.
