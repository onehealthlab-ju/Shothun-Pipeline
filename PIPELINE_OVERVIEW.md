# Shotgun Metagenomics Pipeline - Complete Package

## 📦 Package Contents

This package provides a complete, production-ready shotgun metagenomics analysis pipeline with:

### Core Files

1. **environment.yml** - Conda environment with all required tools
2. **run_metagenomics_pipeline.sh** - Main pipeline script (single sample)
3. **setup_pipeline.sh** - Database setup and configuration
4. **run_batch_samples.sh** - Batch processing for multiple samples
5. **test_pipeline.sh** - Test script to verify installation
6. **samples_list_template.txt** - Template for batch processing
7. **README_QUICKSTART.md** - Detailed usage guide

---

## 🚀 Quick Start (3 Steps)

### Step 1: Setup Environment and Databases

```bash
# Make scripts executable (already done)
chmod +x *.sh

# Run setup (interactive - choose which databases to download)
bash setup_pipeline.sh
```

**Time required:** 2-6 hours (depending on database selections)
**Disk space:** 50-150 GB (depending on databases)

### Step 2: Test the Pipeline

```bash
# Run test with synthetic data to verify everything works
bash test_pipeline.sh
```

**Time required:** 5-10 minutes
**Output:** test_run/results/

### Step 3: Analyze Your Data

**Option A: Single Sample**
```bash
# Edit configuration in run_metagenomics_pipeline.sh (lines 20-50)
# Then run:
bash run_metagenomics_pipeline.sh
```

**Option B: Multiple Samples (Batch)**
```bash
# Create sample list (tab-separated)
# Format: sample_id<TAB>read1.fastq.gz<TAB>read2.fastq.gz

# Run batch processing
bash run_batch_samples.sh my_samples.txt
```

---

## 📊 Pipeline Workflow

```
Raw FASTQ Files
      ↓
┌─────────────────────────────────────────┐
│  1. Quality Control (FastQC)           │
└─────────────────────────────────────────┘
      ↓
┌─────────────────────────────────────────┐
│  2. Preprocessing (fastp)               │
│     - Adapter trimming                  │
│     - Quality filtering                 │
└─────────────────────────────────────────┘
      ↓
┌─────────────────────────────────────────┐
│  3. Host Removal (Bowtie2)              │
└─────────────────────────────────────────┘
      ↓
      ├──────────────────────────────────┬──────────────────────────────────┐
      ↓                                  ↓                                  ↓
┌─────────────────┐          ┌──────────────────────┐        ┌─────────────────────┐
│ 4. Taxonomic    │          │ 6. Functional        │        │ 7. Assembly         │
│    Profiling    │          │    Profiling         │        │    (MEGAHIT)        │
│    - Kraken2    │          │    - HUMAnN3         │        └─────────────────────┘
│    - Bracken    │          │    - Gene families   │                  ↓
│    - MetaPhlAn  │          │    - Pathways        │        ┌─────────────────────┐
└─────────────────┘          └──────────────────────┘        │ 8. Binning          │
      ↓                                  ↓                    │    - MetaBAT2       │
┌─────────────────┐          ┌──────────────────────┐        │    - MaxBin2        │
│ 5. Krona Charts │          │ Pathway abundance    │        └─────────────────────┘
└─────────────────┘          └──────────────────────┘                  ↓
                                                              ┌─────────────────────┐
                                                              │ 9. MAG Quality      │
                                                              │    (CheckM)         │
                                                              └─────────────────────┘
                                                                        ↓
                                                              ┌─────────────────────┐
                                                              │ 10. Annotation      │
                                                              │     - Prodigal      │
                                                              │     - eggNOG        │
                                                              └─────────────────────┘
                                                                        ↓
                             ┌───────────────────────────────────────────────────────┐
                             │         11. MultiQC Report & Visualization            │
                             └───────────────────────────────────────────────────────┘
```

---

## 🗂️ Output Structure

```
results/
├── qc/
│   ├── sample_R1_fastqc.html
│   └── sample_R2_fastqc.html
│
├── preprocessing/
│   ├── sample_R1.clean.fastq.gz
│   ├── sample_R2.clean.fastq.gz
│   ├── sample_R1.nonhost.fastq.gz
│   ├── sample_R2.nonhost.fastq.gz
│   └── sample_fastp.html
│
├── taxonomic_profiling/
│   ├── sample.kraken2.report
│   ├── sample.bracken.species
│   └── sample.metaphlan.profile.txt
│
├── functional_profiling/
│   ├── sample_genefamilies_relab.tsv
│   ├── sample_pathabundance_relab.tsv
│   └── sample_pathcoverage.tsv
│
├── assembly/
│   ├── sample_contigs.fa
│   ├── sample_quast/
│   │   └── report.txt
│   └── sample_mapped_sorted.bam
│
├── binning/
│   ├── sample_bin.1.fa
│   ├── sample_bin.2.fa
│   ├── ...
│   └── sample_checkm_results.txt
│
├── annotation/
│   ├── sample_proteins.faa
│   ├── sample_genes.gff
│   └── sample_eggnog.emapper.annotations
│
├── visualization/
│   ├── sample_multiqc_report.html  ← **START HERE**
│   └── sample_krona.html
│
└── sample_pipeline_summary.txt
```

---

## 💻 System Requirements

### Minimum Configuration
- **CPU:** 8 cores
- **RAM:** 32 GB
- **Storage:** 100 GB + database space
- **OS:** Linux (Ubuntu 20.04+, CentOS 7+)

### Recommended Configuration
- **CPU:** 16-32 cores
- **RAM:** 64-128 GB
- **Storage:** 500 GB SSD
- **OS:** Linux with conda installed

### Software Requirements
- Conda/Miniconda (≥4.10)
- Bash (≥4.0)
- Internet connection (for database downloads)

---

## 📋 Database Requirements

| Database | Size | Required For | Setup Time |
|----------|------|--------------|------------|
| Kraken2 Standard | ~8 GB | Taxonomic profiling | 30-60 min |
| Kraken2 PlusPF | ~35 GB | Extended taxonomic profiling | 2-3 hours |
| MetaPhlAn | ~3 GB | Marker-based profiling | 15-30 min |
| HUMAnN | ~20 GB | Functional profiling | 1-2 hours |
| CheckM | ~300 MB | MAG quality assessment | 5-10 min |
| GTDB-Tk | ~85 GB | MAG taxonomy | 2-3 hours |
| Host Genome | ~3 GB | Host removal | 30-60 min |

**Total:** 50-150 GB depending on selections

---

## ⏱️ Expected Runtime

### Single Sample (10M paired-end reads)

| Step | Time (16 cores) | Time (32 cores) |
|------|-----------------|-----------------|
| QC | 5-10 min | 3-5 min |
| Preprocessing | 10-15 min | 5-10 min |
| Host Removal | 15-30 min | 10-15 min |
| Taxonomic Profiling | 20-40 min | 10-20 min |
| Functional Profiling | 1-2 hours | 30-60 min |
| Assembly | 2-4 hours | 1-2 hours |
| Binning | 1-2 hours | 30-60 min |
| Annotation | 1-2 hours | 30-60 min |
| **Total** | **6-12 hours** | **3-6 hours** |

*Times vary based on data complexity, quality, and system I/O performance*

---

## 🎯 Key Output Files

### For Quick Assessment
1. **results/visualization/sample_multiqc_report.html**
   - Overall quality metrics
   - Read statistics
   - Assembly quality
   
2. **results/sample_pipeline_summary.txt**
   - High-level summary
   - Key statistics
   - File locations

### For Taxonomic Analysis
3. **results/taxonomic_profiling/sample.kraken2.report**
   - Detailed taxonomic classification
   - Read counts per taxon
   
4. **results/taxonomic_profiling/sample.bracken.species**
   - Refined species-level abundances
   
5. **results/visualization/sample_krona.html**
   - Interactive taxonomic tree

### For Functional Analysis
6. **results/functional_profiling/sample_pathabundance_relab.tsv**
   - Metabolic pathway abundances
   - KEGG pathway coverage

### For MAG Analysis
7. **results/binning/sample_checkm_results.txt**
   - Completeness and contamination scores
   - Identifies high-quality MAGs

8. **results/assembly/sample_contigs.fa**
   - Assembled contigs for downstream analysis

---

## 🔧 Configuration

### Essential Settings (in run_metagenomics_pipeline.sh)

```bash
# Sample Information
SAMPLE_ID="sample01"                    # Your sample name
READ1="rawdata/sample01_R1.fastq.gz"   # Path to R1
READ2="rawdata/sample01_R2.fastq.gz"   # Path to R2

# Database Paths (from setup_pipeline.sh)
HOST_GENOME="/path/to/host_genome"
KRAKEN2_DB="/path/to/kraken2_db"
HUMANN_DB="/path/to/humann_db"
CHECKM_DB="/path/to/checkm_data"
GTDBTK_DB="/path/to/gtdbtk_data"

# Computational Resources
THREADS=16          # CPU cores to use
MEMORY="64"         # RAM in GB

# Quality Filters
MIN_READ_LENGTH=50  # Minimum read length after trimming
MIN_QUALITY=20      # Minimum quality score (Q20 = 99% accuracy)
```

---

## 🐛 Troubleshooting

### Common Issues

#### 1. "Command not found" errors
```bash
# Solution: Activate conda environment
conda activate shotgun-metagenomics-pipeline
```

#### 2. "Out of memory" errors
```bash
# Solution: Reduce THREADS or increase system RAM
# Edit in pipeline script:
THREADS=8          # Use fewer cores
MEMORY="32"        # Reduce memory allocation
```

#### 3. "Database not found" errors
```bash
# Solution: Check database paths match your setup
# Verify databases exist:
ls -lh /path/to/kraken2_db
ls -lh /path/to/humann_db
```

#### 4. Pipeline stops at specific step
```bash
# Solution: Check log file for detailed error
cat results/pipeline_sample01.log | grep -i error

# Run failed step manually for debugging
# Example for Kraken2:
kraken2 --help
```

#### 5. Slow performance
```bash
# Solutions:
# - Increase THREADS value
# - Use SSD for databases and working directory
# - Use smaller database (Kraken2 Standard instead of PlusPF)
# - Ensure no other heavy processes running
```

---

## 📚 Additional Resources

### Tool Documentation
- **FastQC:** https://www.bioinformatics.babraham.ac.uk/projects/fastqc/
- **fastp:** https://github.com/OpenGene/fastp
- **Kraken2:** https://ccb.jhu.edu/software/kraken2/
- **MetaPhlAn:** https://github.com/biobakery/MetaPhlAn
- **HUMAnN:** https://github.com/biobakery/humann
- **MEGAHIT:** https://github.com/voutcn/megahit
- **MetaBAT2:** https://bitbucket.org/berkeleylab/metabat
- **CheckM:** https://github.com/Ecogenomics/CheckM

### Tutorials and Guides
- **Microbiome Analysis:** https://joey711.github.io/phyloseq/
- **Metagenomics Workflows:** https://www.ebi.ac.uk/metagenomics/
- **Data Visualization:** https://github.com/meren/anvio

---

## 📝 Citation

If you use this pipeline in your research, please cite the individual tools used.
A complete list of citations is provided in README_QUICKSTART.md

---

## 📧 Support

For issues or questions:
1. Check the troubleshooting section above
2. Review log files in `results/` directory
3. Consult individual tool documentation
4. Check tool GitHub issues pages

---

## ✅ Checklist for First Run

- [ ] Conda environment created (`bash setup_pipeline.sh`)
- [ ] At least one database downloaded
- [ ] Test pipeline passed (`bash test_pipeline.sh`)
- [ ] Raw FASTQ files in `rawdata/` directory
- [ ] Configuration edited in `run_metagenomics_pipeline.sh`
- [ ] Sufficient disk space available (>100 GB free)
- [ ] Sufficient RAM available (>32 GB)
- [ ] Environment activated (`conda activate shotgun-metagenomics-pipeline`)
- [ ] Ready to run: `bash run_metagenomics_pipeline.sh`

---

## 🎉 Getting Started Now

```bash
# 1. Setup (first time only)
bash setup_pipeline.sh

# 2. Test (verify installation)
bash test_pipeline.sh

# 3. Run on your data
# Edit run_metagenomics_pipeline.sh configuration, then:
bash run_metagenomics_pipeline.sh

# 4. View results
firefox results/visualization/sample_multiqc_report.html
```

**Good luck with your metagenomics analysis! 🧬**
