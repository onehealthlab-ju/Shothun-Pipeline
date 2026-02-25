# Shotgun Metagenomics Pipeline

A comprehensive, production-ready pipeline for shotgun metagenomic sequencing data analysis. This pipeline provides end-to-end analysis from raw reads to metagenome-assembled genomes (MAGs), with automated quality control, taxonomic profiling, functional annotation, assembly, and binning.

## 📋 Table of Contents

- [Features](#features)
- [Pipeline Workflow](#pipeline-workflow)
- [Requirements](#requirements)
- [Quick Start](#quick-start)
- [Detailed Usage](#detailed-usage)
- [Output Structure](#output-structure)
- [Advanced Options](#advanced-options)
- [Troubleshooting](#troubleshooting)
- [Citation](#citation)

## ✨ Features

### Comprehensive Analysis Pipeline
- **Quality Control**: FastQC and Trim Galore for read quality assessment and trimming
- **Host Removal**: Bowtie2-based removal of host contamination
- **Taxonomic Profiling**: Dual approach with Kraken2/Bracken and MetaPhlAn4
- **Functional Profiling**: HUMAnN3 for gene families and pathway abundance
- **Assembly**: Choice of MEGAHIT (fast) or metaSPAdes (accurate)
- **Binning**: MetaBAT2 and MaxBin2 for MAG recovery
- **Quality Assessment**: CheckM for bin quality evaluation

### Production-Ready Features
- ✅ **Automated database setup** - One-command database download and configuration
- ✅ **Interactive execution** - User-friendly prompts and progress tracking
- ✅ **Comprehensive logging** - Detailed logs for every step
- ✅ **Resource management** - Configurable CPU and memory usage
- ✅ **Error handling** - Graceful failure recovery and clear error messages
- ✅ **Batch processing** - Process multiple samples automatically
- ✅ **Quality metrics** - Detailed statistics and reports at each step

## 🔬 Pipeline Workflow

```
Raw FASTQ Reads
      ↓
[1] Quality Control (FastQC + Trim Galore)
      ↓
[2] Host Removal (Bowtie2)
      ↓
      ├─→ [3] Taxonomic Profiling (Kraken2/Bracken + MetaPhlAn)
      │
      ├─→ [4] Functional Profiling (HUMAnN3)
      │
      └─→ [5] Assembly (MEGAHIT/metaSPAdes)
            ↓
          [6] Binning (MetaBAT2 + MaxBin2)
            ↓
          MAGs (Metagenome-Assembled Genomes)
```

### Pipeline Scripts

1. **`00_setup_databases.sh`** - Download and configure all required databases
   - Kraken2 standard database
   - MetaPhlAn4 marker database
   - HUMAnN3 databases (ChocoPhlAn, UniRef90)
   - Host genome reference (human by default)

2. **`01_quality_control.sh`** - Quality assessment and read trimming
   - Raw read quality with FastQC
   - Adapter trimming with Trim Galore
   - Post-trim quality check
   - MultiQC summary report

3. **`02_host_removal.sh`** - Remove host contamination
   - Align reads to host genome with Bowtie2
   - Separate host and non-host reads
   - Generate alignment statistics

4. **`03_taxonomic_profiling.sh`** - Microbial community composition
   - Kraken2 taxonomic classification
   - Bracken abundance estimation
   - MetaPhlAn marker-based profiling
   - Krona interactive visualizations

5. **`04_functional_profiling.sh`** - Functional potential analysis
   - HUMAnN3 gene family quantification
   - Pathway abundance and coverage
   - Normalization and regrouping (GO, KEGG, Pfam)
   - Merged tables across samples

6. **`05_assembly.sh`** - De novo assembly
   - MEGAHIT (fast, memory-efficient)
   - metaSPAdes (slower, more accurate)
   - Assembly statistics (N50, L50, etc.)
   - QUAST quality reports

7. **`06_binning.sh`** - Genome binning
   - Read mapping to assemblies
   - MetaBAT2 binning
   - MaxBin2 binning
   - CheckM quality assessment

## 📦 Requirements

### System Requirements
- **OS**: Linux (Ubuntu 20.04+ recommended)
- **CPU**: 8+ cores (16+ recommended)
- **RAM**: 32 GB minimum (64+ GB recommended for large datasets)
- **Storage**: 500+ GB free space for databases and results

### Software Requirements
- Conda or Mamba
- Git

All bioinformatics tools are automatically installed via the provided conda environment.

## 🚀 Quick Start

### 1. Clone the Repository

```bash
git clone <repository-url>
cd shotgun-metagenomics-pipeline
```

### 2. Set Up Environment

```bash
# Create conda environment
conda env create -f environment.yml
conda activate shotgun-metagenomics-pipeline

# Or use provided script
bash setup_pipeline.sh
```

### 3. Download Databases (First Time Only)

```bash
bash scripts/00_setup_databases.sh
```

**Note**: Database downloads require ~100-200 GB storage and may take 2-6 hours.

### 4. Prepare Your Data

Place your paired-end FASTQ files in the `raw_fastq` directory:

```bash
mkdir -p raw_fastq
# Copy or link your files
cp /path/to/your/sample_1.fastq.gz raw_fastq/
cp /path/to/your/sample_2.fastq.gz raw_fastq/
```

File naming convention: `{sample}_1.fastq.gz` and `{sample}_2.fastq.gz`

### 5. Run the Pipeline

#### Option A: Full Pipeline (Recommended for first-time users)

```bash
bash run_metagenomics_pipeline.sh
```

This interactive script will:
- Guide you through the entire pipeline
- Allow you to skip completed steps
- Provide progress updates and summaries

#### Option B: Individual Steps (For experienced users)

```bash
# Step 1: Quality Control
bash scripts/01_quality_control.sh

# Step 2: Host Removal
bash scripts/02_host_removal.sh

# Step 3: Taxonomic Profiling
bash scripts/03_taxonomic_profiling.sh

# Step 4: Functional Profiling
bash scripts/04_functional_profiling.sh

# Step 5: Assembly
bash scripts/05_assembly.sh

# Step 6: Binning
bash scripts/06_binning.sh
```

#### Option C: Batch Processing Multiple Samples

```bash
# Create samples list
cat > samples.txt << EOF
sample1
sample2
sample3
EOF

# Run batch processing
bash run_batch_samples.sh samples.txt
```

## 📊 Output Structure

```
shotgun-metagenomics-pipeline/
├── raw_fastq/                  # Input raw reads
├── qc_raw/                     # Raw read quality reports
├── trimmed_fastq/              # Quality-trimmed reads
├── qc_trimmed/                 # Trimmed read quality reports
├── host_removed/               # Host-depleted reads
│   ├── *.nonhost.fastq.gz     # Non-host reads (use these!)
│   ├── *.host.fastq.gz        # Host reads
│   └── alignment_stats/       # Host removal statistics
├── taxonomic_profiling/        # Taxonomic analysis results
│   ├── kraken2/               # Kraken2 reports
│   ├── bracken/               # Bracken species abundances
│   ├── metaphlan/             # MetaPhlAn profiles
│   └── krona/                 # Interactive Krona charts
├── functional_profiling/       # Functional analysis results
│   ├── humann_raw/            # Raw HUMAnN3 output
│   ├── humann_normalized/     # Normalized tables
│   └── humann_merged/         # Multi-sample comparisons
├── assembly/                   # Assembly results
│   ├── megahit/               # MEGAHIT assemblies
│   ├── spades/                # metaSPAdes assemblies
│   ├── filtered_contigs/      # Filtered contigs (≥500 bp)
│   ├── assembly_stats/        # N50, L50 statistics
│   └── quast_reports/         # QUAST quality reports
└── binning/                    # Binning results
    ├── metabat2_bins/         # MetaBAT2 MAGs
    ├── maxbin2_bins/          # MaxBin2 MAGs
    └── checkm_quality/        # CheckM quality reports
```

## 🔧 Detailed Usage

### Database Setup

The first time you run the pipeline, you must download the required databases:

```bash
bash scripts/00_setup_databases.sh
```

**Options available:**
1. **Kraken2 database size**:
   - Standard: ~60 GB (recommended for most uses)
   - MiniKraken: ~8 GB (faster, less comprehensive)
   - PlusPF: ~140 GB (includes protozoa, fungi)

2. **Host genome**:
   - Human (GRCh38)
   - Mouse (GRCm39)
   - Custom (provide your own)

3. **HUMAnN databases**:
   - Full UniRef90: ~20 GB
   - Diamond UniRef90: ~15 GB (faster searches)

### Quality Control

```bash
bash scripts/01_quality_control.sh
```

**What it does:**
- Runs FastQC on raw reads
- Trims adapters and low-quality bases with Trim Galore
- Re-runs FastQC on trimmed reads
- Generates MultiQC summary reports

**Key outputs:**
- `qc_raw/multiqc_report.html` - Pre-trimming quality summary
- `qc_trimmed/multiqc_report.html` - Post-trimming quality summary
- `trimmed_fastq/*.trimmed.fastq.gz` - Clean reads for downstream analysis

**Typical quality metrics:**
- >20 million paired reads per sample
- Phred score >30 for >95% of bases
- <5% adapter content after trimming

### Host Removal

```bash
bash scripts/02_host_removal.sh
```

**What it does:**
- Aligns reads to host genome with Bowtie2
- Separates host and non-host (microbial) reads
- Calculates host contamination percentages

**Key outputs:**
- `*.nonhost.fastq.gz` - Microbial reads (use for all downstream analyses!)
- `*.host.fastq.gz` - Host reads (for QC purposes)
- `host_removal_summary.txt` - Contamination statistics

**Typical contamination levels:**
- Human stool: 50-99% human DNA
- Environmental samples: <5% host DNA
- Mock communities: <1% contamination

### Taxonomic Profiling

```bash
bash scripts/03_taxonomic_profiling.sh
```

**What it does:**
- Kraken2: Fast k-mer based classification
- Bracken: Re-estimates abundances at species level
- MetaPhlAn: Marker gene-based profiling
- Krona: Interactive taxonomic charts

**Key outputs:**
- `kraken2/*.kraken2.report` - Full taxonomic breakdown
- `bracken/*.bracken.S` - Species-level abundances
- `metaphlan/merged_abundance_table.txt` - Multi-sample comparison
- `krona/*.krona.html` - **Interactive visualization** (open in browser!)

**How to interpret:**
- Krona charts: Click taxonomic groups to drill down
- High-quality samples: >70% reads classified
- Check for expected taxa based on sample type

### Functional Profiling

```bash
bash scripts/04_functional_profiling.sh
```

**What it does:**
- Quantifies gene family abundances (UniRef90)
- Maps genes to metabolic pathways (MetaCyc)
- Calculates pathway completeness
- Regroups to GO, KEGG, and Pfam

**Key outputs:**
- `humann_raw/*_genefamilies.tsv` - Gene family abundances
- `humann_raw/*_pathabundance.tsv` - Pathway abundances
- `humann_merged/all_samples_pathabundance_relab.tsv` - **Start here for comparisons!**

**Typical results:**
- Well-sequenced gut microbiome: 5,000-15,000 gene families
- Core metabolic pathways: >200 detected
- Pathway coverage: >50% for major pathways

**Note**: HUMAnN3 can take 1-3 hours per sample. Plan accordingly!

### Assembly

```bash
bash scripts/05_assembly.sh
```

**Assembler choices:**
1. **MEGAHIT** (recommended for most users)
   - Fast: 1-4 hours per sample
   - Memory-efficient: ~32 GB RAM
   - Good for high-diversity samples

2. **metaSPAdes** (for high-quality assemblies)
   - Slower: 2-8 hours per sample
   - More accurate: produces longer contigs
   - Better error correction

3. **Both** (compare assemblies)

**Key outputs:**
- `filtered_contigs/*_contigs.fa` - Assembled contigs (≥500 bp)
- `assembly_stats/*_stats.txt` - N50, L50, mean length
- `quast_reports/*/report.html` - Quality assessment

**Good assembly metrics:**
- N50: >1,000 bp (>5,000 bp is excellent)
- Longest contig: >10 kbp
- Total assembly: 10-100 Mbp (sample-dependent)

### Binning

```bash
bash scripts/06_binning.sh
```

**What it does:**
- Maps reads back to assemblies
- Bins contigs using MetaBAT2 and MaxBin2
- Assesses bin quality with CheckM

**Key outputs:**
- `metabat2_bins/*/bin.*.fa` - MetaBAT2 MAGs
- `maxbin2_bins/*/bin.*.fasta` - MaxBin2 MAGs
- `checkm_quality/*_summary.tsv` - **Quality metrics** (start here!)

**Bin quality criteria:**
- **High-quality**: >90% complete, <5% contamination
- **Medium-quality**: 50-90% complete, <10% contamination
- **Low-quality**: <50% complete or >10% contamination

**Typical results:**
- Human gut: 10-50 bins per sample
- High-quality bins: 5-15 per sample
- Bin sizes: 2-6 Mbp (typical bacterial genome)

## 🎛️ Advanced Options

### Configuring Resources

Edit the `THREADS` and `MEMORY_GB` variables in each script:

```bash
# In scripts/05_assembly.sh
THREADS=16           # Use 16 CPU cores
MEMORY_GB=64         # Use 64 GB RAM
```

### Custom Databases

Update database paths in scripts:

```bash
# In scripts/02_host_removal.sh
HOST_GENOME="/path/to/custom/genome"

# In scripts/03_taxonomic_profiling.sh
KRAKEN2_DB="/path/to/custom/kraken2/db"
```

### Adjusting Quality Thresholds

```bash
# In scripts/01_quality_control.sh
QUALITY_CUTOFF=20    # Minimum Phred score
MIN_LENGTH=50        # Minimum read length after trimming

# In scripts/05_assembly.sh
MIN_CONTIG_LENGTH=1000  # Keep longer contigs only

# In scripts/06_binning.sh
--minContig 5000     # Larger contigs for binning
```

### Running Individual Samples

```bash
# Process specific sample for a single step
bash scripts/03_taxonomic_profiling.sh sample_name
```

## 🐛 Troubleshooting

### Common Issues and Solutions

#### 1. Database Download Fails

**Problem**: Network timeout or incomplete download

**Solution**:
```bash
# Resume incomplete downloads
bash scripts/00_setup_databases.sh
# The script will detect existing files and resume
```

#### 2. Out of Memory Errors

**Problem**: Assembly or HUMAnN crashes with memory errors

**Solution**:
```bash
# Reduce threads to free up memory
THREADS=4
MEMORY_GB=16

# Or use MEGAHIT instead of metaSPAdes
# MEGAHIT is much more memory-efficient
```

#### 3. Low Classification Rates

**Problem**: <30% of reads classified by Kraken2

**Possible causes**:
- Low sequencing quality (check FastQC reports)
- High host contamination (check host removal stats)
- Unusual sample type (may need different database)

**Solution**:
```bash
# Try larger Kraken2 database (PlusPF)
# Verify host removal was successful
# Check for low-complexity reads
```

#### 4. Few or No Bins Recovered

**Problem**: Binning produces 0-2 bins

**Possible causes**:
- Low sequencing depth (<5M reads)
- Poor assembly quality (low N50)
- Very high sample diversity

**Solution**:
```bash
# Check assembly quality first
less assembly/assembly_stats/*_stats.txt

# If N50 < 500 bp, assembly is too fragmented
# May need deeper sequencing or co-assembly
```

#### 5. HUMAnN Takes Too Long

**Problem**: HUMAnN runs for >6 hours per sample

**Solution**:
```bash
# Reduce input size by subsampling
seqtk sample -s100 input_R1.fq.gz 0.5 | gzip > subsampled_R1.fq.gz
seqtk sample -s100 input_R2.fq.gz 0.5 | gzip > subsampled_R2.fq.gz

# Or use Diamond UniRef (faster searches)
humann_config --update database_folders protein /path/to/uniref_diamond
```

### Getting Help

If you encounter issues not covered here:

1. Check the log files in `*/logs/` directories
2. Review the relevant summary report (`*_summary.txt`)
3. Consult tool documentation:
   - [Kraken2](https://github.com/DerrickWood/kraken2/wiki)
   - [HUMAnN](https://huttenhower.sph.harvard.edu/humann/)
   - [MEGAHIT](https://github.com/voutcn/megahit)
   - [MetaBAT2](https://bitbucket.org/berkeleylab/metabat)

## 📝 Best Practices

### Sample Preparation
- **Sequencing depth**: Aim for 20-50M paired reads per sample
- **Read length**: 150 bp paired-end is ideal
- **Biological replicates**: Include at least 3 replicates per condition
- **Controls**: Include negative controls and mock communities

### Quality Control
- Always run FastQC and review reports before analysis
- Trim adapters and low-quality bases (Phred <20)
- Remove host contamination for microbial-focused analyses
- Check for batch effects in multi-sample studies

### Analysis Strategy
1. **Start with profiling**: Taxonomic and functional profiling are fast
2. **Assembly is optional**: Only needed for MAG recovery or novel gene discovery
3. **Binning requires good assemblies**: N50 >1 kbp recommended
4. **Compare tools**: Kraken2 and MetaPhlAn often give complementary results

### Resource Planning
- **Profiling**: 2-4 hours per sample, 8 CPUs, 32 GB RAM
- **HUMAnN**: 1-3 hours per sample, 8 CPUs, 16 GB RAM
- **Assembly**: 1-4 hours (MEGAHIT) or 2-8 hours (metaSPAdes), 8+ CPUs, 32-64 GB RAM
- **Binning**: 2-4 hours per sample, 8 CPUs, 32 GB RAM

## 📚 Citation

If you use this pipeline in your research, please cite the individual tools:

- **FastQC**: Andrews S. (2010). FastQC: a quality control tool for high throughput sequence data.
- **Trim Galore**: Krueger F. (2015). Trim Galore: a wrapper tool around Cutadapt and FastQC.
- **Bowtie2**: Langmead B, Salzberg SL. (2012). Fast gapped-read alignment with Bowtie 2. Nature Methods.
- **Kraken2**: Wood DE, Lu J, Langmead B. (2019). Improved metagenomic analysis with Kraken 2. Genome Biology.
- **Bracken**: Lu J, et al. (2017). Bracken: estimating species abundance in metagenomics data. PeerJ Computer Science.
- **MetaPhlAn**: Blanco-Míguez A, et al. (2023). Extending and improving metagenomic taxonomic profiling with uncharacterized species using MetaPhlAn 4. Nature Biotechnology.
- **HUMAnN**: Beghini F, et al. (2021). Integrating taxonomic, functional, and strain-level profiling of diverse microbial communities with bioBakery 3. eLife.
- **MEGAHIT**: Li D, et al. (2015). MEGAHIT: an ultra-fast single-node solution for large and complex metagenomics assembly via succinct de Bruijn graph. Bioinformatics.
- **SPAdes**: Nurk S, et al. (2017). metaSPAdes: a new versatile metagenomic assembler. Genome Research.
- **MetaBAT2**: Kang DD, et al. (2019). MetaBAT 2: an adaptive binning algorithm for robust and efficient genome reconstruction from metagenome assemblies. PeerJ.
- **MaxBin2**: Wu YW, et al. (2016). MaxBin 2.0: an automated binning algorithm to recover genomes from multiple metagenomic datasets. Bioinformatics.
- **CheckM**: Parks DH, et al. (2015). CheckM: assessing the quality of microbial genomes recovered from isolates, single cells, and metagenomes. Genome Research.

## 📄 License

This pipeline is provided under the MIT License. See LICENSE file for details.

## 🤝 Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Submit a pull request with clear description

## 📧 Contact

For questions, suggestions, or bug reports, please open an issue on GitHub.
