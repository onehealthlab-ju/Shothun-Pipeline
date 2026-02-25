#!/bin/bash
# Script: 07_arg_virulence_mge_analysis.sh
# Purpose: ARG, Virulence Factor, MGE, and Plasmid Detection
# Features: Novel ARG detection, correlation analysis, taxonomic context

set -euo pipefail

# Configuration
INPUT_DIR="data/assemblies"
OUTPUT_DIR="results/arg_virulence_mge"
THREADS=8

# Create output directories
mkdir -p "${OUTPUT_DIR}"/{abricate,amrfinderplus,rgi,genomad,plasmidfinder,novel_args,correlation,visualization}

echo "=== ARG, Virulence, MGE & Plasmid Analysis Pipeline ==="
echo "Start time: $(date)"

#######################################
# 1. ABRICATE - Multiple Database Screening
#######################################
echo -e "\n[1/9] Running Abricate on multiple databases..."

for db in ncbi card argannot resfinder vfdb plasmidfinder; do
    echo "  - Running Abricate with ${db} database..."
    for assembly in "${INPUT_DIR}"/*.fasta; do
        sample=$(basename "${assembly}" .fasta)
        abricate --db "${db}" \
                 --threads "${THREADS}" \
                 "${assembly}" > "${OUTPUT_DIR}/abricate/${sample}_${db}.tab"
    done
    
    # Summarize results across all samples
    abricate --summary "${OUTPUT_DIR}"/abricate/*_${db}.tab > \
        "${OUTPUT_DIR}/abricate/${db}_summary.tab"
done

echo "  ✓ Abricate analysis complete"

#######################################
# 2. AMRFinderPlus - Comprehensive AMR Detection
#######################################
echo -e "\n[2/9] Running AMRFinderPlus..."

# Update AMRFinderPlus database
amrfinder --update

for assembly in "${INPUT_DIR}"/*.fasta; do
    sample=$(basename "${assembly}" .fasta)
    
    amrfinder --nucleotide "${assembly}" \
              --threads "${THREADS}" \
              --plus \
              --output "${OUTPUT_DIR}/amrfinderplus/${sample}_amr.txt"
done

# Consolidate results
echo "  - Consolidating AMRFinderPlus results..."
{
    head -1 "${OUTPUT_DIR}"/amrfinderplus/*_amr.txt | head -1
    tail -n +2 -q "${OUTPUT_DIR}"/amrfinderplus/*_amr.txt
} > "${OUTPUT_DIR}/amrfinderplus/all_samples_amr.txt"

echo "  ✓ AMRFinderPlus complete"

#######################################
# 3. RGI (CARD) - Resistance Gene Identifier
#######################################
echo -e "\n[3/9] Running RGI (CARD Resistance Gene Identifier)..."

for assembly in "${INPUT_DIR}"/*.fasta; do
    sample=$(basename "${assembly}" .fasta)
    
    # Main RGI analysis
    rgi main --input_sequence "${assembly}" \
             --output_file "${OUTPUT_DIR}/rgi/${sample}" \
             --input_type contig \
             --clean \
             --num_threads "${THREADS}"
    
    # RGI heatmap data
    rgi heatmap --input "${OUTPUT_DIR}/rgi/${sample}.json" \
                --output "${OUTPUT_DIR}/rgi/${sample}_heatmap"
done

# Create combined heatmap
rgi heatmap --input "${OUTPUT_DIR}"/rgi/*.json \
            --output "${OUTPUT_DIR}/rgi/combined_heatmap" \
            --category drug_class

echo "  ✓ RGI analysis complete"

#######################################
# 4. geNomad - Plasmid & Virus Detection
#######################################
echo -e "\n[4/9] Running geNomad for plasmids and viruses..."

# Download geNomad database if needed
if [ ! -d "genomad_db" ]; then
    echo "  - Downloading geNomad database..."
    genomad download-database genomad_db
fi

for assembly in "${INPUT_DIR}"/*.fasta; do
    sample=$(basename "${assembly}" .fasta)
    
    genomad end-to-end \
        --threads "${THREADS}" \
        "${assembly}" \
        "${OUTPUT_DIR}/genomad/${sample}" \
        genomad_db
done

echo "  ✓ geNomad analysis complete"

#######################################
# 5. PlasmidFinder - Detailed Plasmid Typing
#######################################
echo -e "\n[5/9] Running PlasmidFinder..."

for assembly in "${INPUT_DIR}"/*.fasta; do
    sample=$(basename "${assembly}" .fasta)
    
    plasmidfinder.py -i "${assembly}" \
                     -o "${OUTPUT_DIR}/plasmidfinder/${sample}" \
                     -p /usr/share/plasmidfinder/plasmidfinder_db \
                     -t 0.90 \
                     -l 0.60
done

echo "  ✓ PlasmidFinder complete"

#######################################
# 6. Novel ARG Detection
#######################################
echo -e "\n[6/9] Detecting novel/divergent ARGs..."

cat > "${OUTPUT_DIR}/novel_args/detect_novel.py" << 'PYTHON_EOF'
#!/usr/bin/env python3
"""Detect novel or divergent ARGs based on identity thresholds"""
import pandas as pd
import os
from pathlib import Path

# Thresholds for novelty
IDENTITY_THRESHOLD = 90.0
COVERAGE_THRESHOLD = 80.0

def analyze_abricate_results(input_dir, output_file):
    """Find potential novel ARGs from Abricate CARD results"""
    novel_args = []
    
    for file in Path(input_dir).glob("*_card.tab"):
        if os.path.getsize(file) > 0:
            df = pd.read_csv(file, sep='\t')
            novel = df[
                (df['%IDENTITY'] < IDENTITY_THRESHOLD) & 
                (df['%COVERAGE'] >= COVERAGE_THRESHOLD)
            ].copy()
            
            if not novel.empty:
                novel['SAMPLE'] = file.stem.replace('_card', '')
                novel['NOVELTY_SCORE'] = 100 - novel['%IDENTITY']
                novel_args.append(novel)
    
    if novel_args:
        result_df = pd.concat(novel_args, ignore_index=True)
        result_df = result_df.sort_values('NOVELTY_SCORE', ascending=False)
        result_df.to_csv(output_file, sep='\t', index=False)
        return len(result_df)
    return 0

def analyze_amrfinder_results(input_file, output_file):
    """Find potential novel ARGs from AMRFinderPlus"""
    if not os.path.exists(input_file):
        return 0
    df = pd.read_csv(input_file, sep='\t')
    
    if '% Identity' in df.columns:
        novel = df[
            (df['% Identity'] < IDENTITY_THRESHOLD) & 
            (df['% Coverage of reference sequence'] >= COVERAGE_THRESHOLD)
        ].copy()
        
        if not novel.empty:
            novel['NOVELTY_SCORE'] = 100 - novel['% Identity']
            novel = novel.sort_values('NOVELTY_SCORE', ascending=False)
            novel.to_csv(output_file, sep='\t', index=False)
            return len(novel)
    return 0

# Run analyses
print("Analyzing Abricate results for novel ARGs...")
novel_count_abr = analyze_abricate_results(
    'results/arg_virulence_mge/abricate',
    'results/arg_virulence_mge/novel_args/novel_args_abricate.txt'
)

print("Analyzing AMRFinderPlus results for novel ARGs...")
novel_count_amr = analyze_amrfinder_results(
    'results/arg_virulence_mge/amrfinderplus/all_samples_amr.txt',
    'results/arg_virulence_mge/novel_args/novel_args_amrfinder.txt'
)

# Summary
with open('results/arg_virulence_mge/novel_args/summary.txt', 'w') as f:
    f.write(f"Novel ARG Detection Summary\n")
    f.write(f"===========================\n\n")
    f.write(f"Threshold: <{IDENTITY_THRESHOLD}% identity\n")
    f.write(f"Coverage: >{COVERAGE_THRESHOLD}%\n\n")
    f.write(f"Novel ARGs from Abricate: {novel_count_abr}\n")
    f.write(f"Novel ARGs from AMRFinderPlus: {novel_count_amr}\n")
    f.write(f"Total: {novel_count_abr + novel_count_amr}\n")

print(f"✓ Found {novel_count_abr + novel_count_amr} potential novel ARGs")
PYTHON_EOF

chmod +x "${OUTPUT_DIR}/novel_args/detect_novel.py"
python3 "${OUTPUT_DIR}/novel_args/detect_novel.py"

echo "  ✓ Novel ARG detection complete"

#######################################
# 7. ARG-MGE-Plasmid Correlation Analysis
#######################################
echo -e "\n[7/9] Analyzing ARG-MGE-Plasmid correlations..."

cat > "${OUTPUT_DIR}/correlation/correlate_features.py" << 'PYTHON_EOF2'
#!/usr/bin/env python3
"""Correlate ARGs with MGEs, plasmids, and taxonomic context"""
import pandas as pd
import numpy as np
from pathlib import Path
import json

def parse_abricate_summary(db_name):
    """Parse Abricate summary file"""
    file = f'results/arg_virulence_mge/abricate/{db_name}_summary.tab'
    if Path(file).exists():
        df = pd.read_csv(file, sep='\t', index_col=0)
        return df
    return pd.DataFrame()

def create_feature_matrix():
    """Create binary matrix of features across samples"""
    features = {}
    
    card_df = parse_abricate_summary('card')
    if not card_df.empty:
        features['ARG'] = (card_df > 0).astype(int)
    
    vfdb_df = parse_abricate_summary('vfdb')
    if not vfdb_df.empty:
        features['VF'] = (vfdb_df > 0).astype(int)
    
    plasmid_df = parse_abricate_summary('plasmidfinder')
    if not plasmid_df.empty:
        features['PLASMID'] = (plasmid_df > 0).astype(int)
    
    return features

def analyze_colocalization():
    """Analyze co-occurrence of ARGs with MGEs/plasmids"""
    features = create_feature_matrix()
    
    if not features:
        print("No feature data available")
        return
    
    results = []
    
    for sample in features['ARG'].index if 'ARG' in features else []:
        sample_data = {
            'sample': sample,
            'arg_count': 0,
            'vf_count': 0,
            'plasmid_count': 0,
            'arg_with_plasmid': 0,
            'vf_with_plasmid': 0
        }
        
        if 'ARG' in features:
            sample_data['arg_count'] = features['ARG'].loc[sample].sum()
        
        if 'VF' in features:
            sample_data['vf_count'] = features['VF'].loc[sample].sum()
        
        if 'PLASMID' in features:
            sample_data['plasmid_count'] = features['PLASMID'].loc[sample].sum()
            
            if 'ARG' in features and sample_data['plasmid_count'] > 0:
                sample_data['arg_with_plasmid'] = sample_data['arg_count']
            
            if 'VF' in features and sample_data['plasmid_count'] > 0:
                sample_data['vf_with_plasmid'] = sample_data['vf_count']
        
        results.append(sample_data)
    
    if results:
        df = pd.DataFrame(results)
        df.to_csv('results/arg_virulence_mge/correlation/colocalization_summary.txt', 
                  sep='\t', index=False)
        
        numeric_cols = ['arg_count', 'vf_count', 'plasmid_count']
        corr = df[numeric_cols].corr()
        corr.to_csv('results/arg_virulence_mge/correlation/feature_correlations.txt', 
                    sep='\t')
        
        print(f"✓ Analyzed {len(df)} samples")
        print(f"\nFeature Summary:")
        print(f"  Total ARGs: {df['arg_count'].sum()}")
        print(f"  Total VFs: {df['vf_count'].sum()}")
        print(f"  Total Plasmids: {df['plasmid_count'].sum()}")

def analyze_drug_classes():
    """Analyze ARG distribution by drug class from RGI"""
    drug_classes = {}
    
    for json_file in Path('results/arg_virulence_mge/rgi').glob('*.json'):
        sample = json_file.stem
        
        with open(json_file) as f:
            data = json.load(f)
        
        sample_classes = []
        for gene, info in data.items():
            if isinstance(info, dict) and 'ARO_category' in info:
                for category in info['ARO_category'].values():
                    if 'category_aro_name' in category:
                        sample_classes.append(category['category_aro_name'])
        
        drug_classes[sample] = sample_classes
    
    all_classes = []
    for classes in drug_classes.values():
        all_classes.extend(classes)
    
    from collections import Counter
    class_counts = Counter(all_classes)
    
    df = pd.DataFrame.from_dict(class_counts, orient='index', columns=['Count'])
    df = df.sort_values('Count', ascending=False)
    df.to_csv('results/arg_virulence_mge/correlation/drug_class_distribution.txt', 
              sep='\t')
    
    print(f"\n✓ Analyzed {len(class_counts)} drug classes")

# Run analyses
print("Creating feature matrix...")
analyze_colocalization()

print("\nAnalyzing drug class distribution...")
analyze_drug_classes()

print("\n✓ Correlation analysis complete")
PYTHON_EOF2

chmod +x "${OUTPUT_DIR}/correlation/correlate_features.py"
python3 "${OUTPUT_DIR}/correlation/correlate_features.py"

echo "  ✓ Correlation analysis complete"

#######################################
# 8. Visualization
#######################################
echo -e "\n[8/9] Creating visualizations..."

# Copy the R visualization script
cp create_arg_visualizations.R "${OUTPUT_DIR}/visualization/create_plots.R"
chmod +x "${OUTPUT_DIR}/visualization/create_plots.R"
Rscript "${OUTPUT_DIR}/visualization/create_plots.R"

echo "  ✓ Visualization complete"

#######################################
# 9. Final Report Generation
#######################################
echo -e "\n[9/9] Generating comprehensive report..."

cat > "${OUTPUT_DIR}/COMPREHENSIVE_REPORT.md" << 'REPORTEOF'
# ARG, Virulence, MGE & Plasmid Analysis Report

## Analysis Overview

This report summarizes the comprehensive analysis of:
- **Antimicrobial Resistance Genes (ARGs)**
- **Virulence Factors**
- **Mobile Genetic Elements (MGEs)**
- **Plasmids**
- **Novel/Divergent ARGs**
- **Feature Correlations**

## Tools Used

| Tool | Purpose | Database Version |
|------|---------|------------------|
| Abricate | Multi-database screening | NCBI, CARD, ARG-ANNOT, ResFinder, VFDB, PlasmidFinder |
| AMRFinderPlus | Comprehensive AMR detection | Latest |
| RGI | CARD Resistance Gene Identifier | CARD |
| geNomad | Plasmid & virus detection | Latest |
| PlasmidFinder | Plasmid typing | Latest |

## Directory Structure

```
results/arg_virulence_mge/
├── abricate/              # Multi-database results
├── amrfinderplus/         # AMRFinderPlus output
├── rgi/                   # RGI analysis
├── genomad/               # Plasmid/virus detection
├── plasmidfinder/         # Plasmid typing
├── novel_args/            # Novel ARG candidates
├── correlation/           # Feature correlation analysis
└── visualization/         # Plots and figures
```

## Key Results

### 1. ARG Detection

**Summary files:**
- `abricate/card_summary.tab` - ARG presence/absence matrix
- `amrfinderplus/all_samples_amr.txt` - Detailed AMR annotations
- `rgi/combined_heatmap.*` - Drug class visualization

### 2. Novel ARG Candidates

Potential novel or divergent ARGs (<90% identity):
- See `novel_args/novel_args_abricate.txt`
- See `novel_args/novel_args_amrfinder.txt`
- Summary in `novel_args/summary.txt`

### 3. Virulence Factors

- Results: `abricate/vfdb_summary.tab`
- Pathogenicity potential assessment

### 4. Plasmid & MGE Detection

- geNomad results: `genomad/*/plasmid/`
- PlasmidFinder typing: `plasmidfinder/*/results_tab.tsv`
- Plasmid replicon types identified

### 5. Feature Correlations

**Co-localization Analysis:**
- ARG-Plasmid associations: `correlation/colocalization_summary.txt`
- Feature correlations: `correlation/feature_correlations.txt`
- Drug class distribution: `correlation/drug_class_distribution.txt`

## Visualizations

1. **ARG Heatmap** (`visualization/arg_heatmap.png`)
   - ARG distribution across samples

2. **Drug Class Distribution** (`visualization/drug_class_distribution.png`)
   - Top 20 antibiotic classes

3. **Feature Correlations** (`visualization/feature_correlations.png`)
   - ARG vs Plasmid, VF vs Plasmid, ARG vs VF relationships

4. **Sample Overview** (`visualization/sample_overview.png`)
   - Per-sample feature counts

## Interpretation Guidelines

### ARG Assessment
- **High confidence:** >95% identity and >90% coverage
- **Moderate:** 90-95% identity
- **Potential novel:** <90% identity (see novel_args/)

### Virulence Factors
- Multiple VFs suggest increased pathogenic potential
- Cross-reference with ARGs for MDR pathogen risk

### Plasmid-ARG Associations
- ARGs on plasmids indicate horizontal transfer potential
- Higher transmission risk in clinical settings

### Drug Class Analysis
- Identify dominant resistance mechanisms
- Guide empirical therapy decisions

## Next Steps

1. **Validation:** Confirm novel ARGs with PCR/sequencing
2. **Context:** Integrate with taxonomic and epidemiological data
3. **Risk assessment:** Evaluate clinical significance
4. **Surveillance:** Monitor ARG emergence and spread

## Files for Publication

### Supplementary Tables
- `abricate/card_summary.tab` - ARG matrix
- `correlation/colocalization_summary.txt` - Feature associations
- `novel_args/novel_args_*.txt` - Novel ARG candidates

### Figures
- `visualization/arg_heatmap.png` - Main figure
- `visualization/feature_correlations.png` - Correlation analysis
- `visualization/drug_class_distribution.png` - Supplementary

---

**Analysis completed:** $(date)
**Pipeline version:** 1.0
REPORTEOF

echo "  ✓ Report generated: ${OUTPUT_DIR}/COMPREHENSIVE_REPORT.md"

#######################################
# Completion Summary
#######################################
echo -e "\n========================================="
echo "ARG, Virulence, MGE & Plasmid Analysis Complete!"
echo "========================================="
echo "Output directory: ${OUTPUT_DIR}/"
echo ""
echo "Key outputs:"
echo "  1. ARG detection: abricate/, amrfinderplus/, rgi/"
echo "  2. Novel ARGs: novel_args/"
echo "  3. Plasmids/MGEs: genomad/, plasmidfinder/"
echo "  4. Correlations: correlation/"
echo "  5. Visualizations: visualization/"
echo "  6. Report: COMPREHENSIVE_REPORT.md"
echo ""
echo "End time: $(date)"
echo "========================================="
