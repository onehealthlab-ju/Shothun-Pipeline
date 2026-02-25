# 🚀 Getting Started Checklist

Use this checklist to ensure your pipeline is ready to run!

---

## ✅ Pre-Flight Checklist

### 1️⃣ System Requirements
- [ ] Linux operating system (Ubuntu 20.04+ recommended)
- [ ] At least 8 CPU cores available (16+ recommended)
- [ ] At least 32 GB RAM (64+ GB recommended)
- [ ] At least 500 GB free disk space
- [ ] Stable internet connection (for database downloads)

### 2️⃣ Software Installation
- [ ] Conda or Mamba installed
  ```bash
  conda --version  # Should show version number
  ```
- [ ] Git installed
  ```bash
  git --version    # Should show version number
  ```

### 3️⃣ Pipeline Setup
- [ ] Repository cloned
  ```bash
  git clone <repository-url>
  cd shotgun-metagenomics-pipeline
  ```
- [ ] Conda environment created
  ```bash
  conda env create -f environment.yml
  ```
- [ ] Environment activated
  ```bash
  conda activate shotgun-metagenomics-pipeline
  ```
- [ ] Scripts are executable
  ```bash
  chmod +x scripts/*.sh *.sh
  ```

### 4️⃣ Database Setup (First Time Only)
- [ ] Databases downloaded successfully
  ```bash
  bash scripts/00_setup_databases.sh
  ```
- [ ] Verify database locations:
  - [ ] Kraken2 database exists
    ```bash
    ls -lh databases/kraken2/
    ```
  - [ ] MetaPhlAn database exists
    ```bash
    metaphlan --version --bowtie2db databases/metaphlan
    ```
  - [ ] HUMAnN databases exist
    ```bash
    ls -lh databases/humann/chocophlan/
    ls -lh databases/humann/uniref/
    ```
  - [ ] Host genome exists
    ```bash
    ls -lh databases/host_genome/*.bt2
    ```

### 5️⃣ Data Preparation
- [ ] Raw FASTQ files ready
- [ ] Files follow naming convention: `{sample}_1.fastq.gz` and `{sample}_2.fastq.gz`
- [ ] Files placed in `raw_fastq/` directory
  ```bash
  ls -lh raw_fastq/
  ```
- [ ] At least 10M paired reads per sample (20M+ recommended)
- [ ] Paired-end reads (R1 and R2 for each sample)

### 6️⃣ Disk Space Verification
Check available space:
```bash
df -h .
```
- [ ] At least 100 GB free for databases
- [ ] At least 10-20 GB free per sample for analysis
- [ ] Additional space for results (10-50 GB depending on samples)

---

## 🎯 Quick Verification Tests

### Test 1: Environment is Working
```bash
conda activate shotgun-metagenomics-pipeline
fastqc --version      # Should show FastQC version
kraken2 --version     # Should show Kraken2 version
metaphlan --version   # Should show MetaPhlAn version
```
**Expected**: All commands should output version numbers without errors

### Test 2: Databases are Configured
```bash
# Test Kraken2
kraken2 --db databases/kraken2 --report /dev/null /dev/null

# Test MetaPhlAn
metaphlan --bowtie2db databases/metaphlan --help | head -5
```
**Expected**: No error messages about missing databases

### Test 3: Sample Data Exists
```bash
# Count samples
ls raw_fastq/*_1.fastq.gz | wc -l
ls raw_fastq/*_2.fastq.gz | wc -l
```
**Expected**: Equal number of R1 and R2 files

### Test 4: Read Counts (Optional)
```bash
# Check read count for first sample
zcat raw_fastq/*_1.fastq.gz | head -1000 | wc -l
```
**Expected**: Number divisible by 4 (FASTQ format)

---

## 🚀 Ready to Run!

Once all boxes are checked, choose your execution method:

### Option A: Interactive Full Pipeline (Recommended for beginners)
```bash
bash run_metagenomics_pipeline.sh
```

### Option B: Step-by-Step Manual Execution (For experienced users)
```bash
# Run each step individually
bash scripts/01_qc_trim.sh
bash scripts/02_host_removal.sh
bash scripts/03_taxonomic_profiling.sh
bash scripts/04_functional_profiling.sh
bash scripts/05_assembly.sh
bash scripts/06_binning.sh
```

### Option C: Batch Processing (For multiple samples)
```bash
# Create sample list
ls raw_fastq/*_1.fastq.gz | sed 's/_1.fastq.gz//' | sed 's/raw_fastq\///' > samples.txt

# Run batch
bash run_batch_samples.sh samples.txt
```

---

## ⏱️ Estimated Timeline

For a **single sample** (20M paired reads, 8 CPUs, 32 GB RAM):

| Step | Duration | Can Skip? |
|------|----------|-----------|
| Database setup | 2-6 hours | After first time: ✅ |
| Quality control | 30 min | ❌ |
| Host removal | 1 hour | Optional for some samples |
| Taxonomic profiling | 1-2 hours | ❌ |
| Functional profiling | 1-3 hours | ❌ |
| Assembly | 1-8 hours | ✅ (if only need profiling) |
| Binning | 2-4 hours | ✅ (if only need profiling) |

**Total Time**:
- **Profiling only**: 4-7 hours
- **Full pipeline**: 8-20 hours

---

## 🔍 Common Pre-Flight Issues

### Issue: "conda: command not found"
**Solution**: Install Conda/Mamba
```bash
# Install Miniconda
wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
bash Miniconda3-latest-Linux-x86_64.sh
```

### Issue: "No space left on device"
**Solution**: Free up space or use external storage
```bash
# Check disk usage
df -h .

# Clean conda cache
conda clean --all -y

# Move databases to larger partition
mv databases /path/to/larger/partition/
ln -s /path/to/larger/partition/databases databases
```

### Issue: "Permission denied" when running scripts
**Solution**: Make scripts executable
```bash
chmod +x scripts/*.sh
chmod +x *.sh
```

### Issue: Database download fails
**Solution**: Resume download (script will skip existing files)
```bash
bash scripts/00_setup_databases.sh
```

### Issue: No FASTQ files found
**Solution**: Check naming and location
```bash
# Verify files exist
ls -lh raw_fastq/

# Check naming pattern
ls raw_fastq/*_1.fastq.gz
ls raw_fastq/*_2.fastq.gz

# Rename if needed
for f in raw_fastq/*_R1_*.fastq.gz; do
    mv "$f" "${f/_R1_/_1}"
done
```

---

## 📚 Next Steps After Completion

1. **Review Results**
   - [ ] Check MultiQC reports: `qc_trimmed/multiqc_report.html`
   - [ ] View Krona charts: `taxonomic_profiling/krona/*.html`
   - [ ] Examine bin quality: `binning/checkm_quality/*_summary.tsv`

2. **Quality Control**
   - [ ] >80% reads passed trimming
   - [ ] >50% reads classified taxonomically
   - [ ] Assembly N50 >1000 bp (if assembled)
   - [ ] >5 high-quality MAGs (if binned)

3. **Data Analysis**
   - [ ] Import abundance tables to R/Python
   - [ ] Perform statistical tests
   - [ ] Create publication figures
   - [ ] Write methods section

4. **Archive and Share**
   - [ ] Upload raw data to SRA/ENA
   - [ ] Share processed results
   - [ ] Document parameters used
   - [ ] Cite all tools properly

---

## 🆘 Need Help?

### Troubleshooting Resources:
1. **Documentation**
   - `README.md` - Complete guide
   - `EXECUTION_GUIDE.txt` - Step-by-step instructions
   - `PIPELINE_OVERVIEW.md` - Technical details

2. **Log Files**
   - Check `*/logs/*.log` for detailed error messages
   - Review `*_summary.txt` files for statistics

3. **Common Solutions**
   - Out of memory: Reduce `THREADS` in scripts
   - Database errors: Re-run `00_setup_databases.sh`
   - No output: Check log files for errors
   - Low quality: Review FastQC reports

### Still Stuck?
- Review tool documentation (links in README.md)
- Check GitHub issues
- Search for error messages online
- Consult the bioinformatics community

---

## ✨ Success Indicators

You'll know the pipeline is working correctly when:

✅ **After QC (Step 1)**:
- MultiQC report generated
- >90% bases with quality score >30
- Trimmed reads in `trimmed_fastq/`

✅ **After Host Removal (Step 2)**:
- `*.nonhost.*.fastq.gz` files created
- Host removal summary shows reasonable contamination
- Non-host reads ready for profiling

✅ **After Taxonomic Profiling (Step 3)**:
- Krona charts open in browser
- Species abundance tables created
- >50% reads classified (for most samples)

✅ **After Functional Profiling (Step 4)**:
- Gene family and pathway tables created
- Normalized abundance tables available
- Merged multi-sample comparisons ready

✅ **After Assembly (Step 5)**:
- Contigs generated with N50 >1000 bp
- QUAST report shows reasonable statistics
- Filtered contigs ready for binning

✅ **After Binning (Step 6)**:
- Multiple bins created (5-50 depending on sample)
- CheckM shows >5 high-quality MAGs
- Bins ready for annotation

---

## 🎉 You're Ready!

All boxes checked? Congratulations! You're ready to run the pipeline.

```bash
# Activate environment
conda activate shotgun-metagenomics-pipeline

# Start pipeline
bash run_metagenomics_pipeline.sh

# Sit back and let the science happen! ☕
```

**Good luck with your metagenomics analysis! 🧬🔬**

---

**Last Updated**: 2026-02-25  
**Pipeline Version**: 1.0.0
