# Saving Glut of the Rich

## Code Description

### Cleaning
1. `dina_shares.py`: Load raw DINA income and wealth data and collapse by wealth percentiles.
2. `nipa_savings.py`: Construct saving based on 'income minus consumption' approach using DINA and CBO data on income
3. `fof_savings.py`: Construct saving based on 'wealth' approach using Flow of Funds data on assets and liabilities
4. `unveiling.py`: Unveil wealth holdings based on algorithm described in the text using Flow of Funds data
5. `scf_panel.do`: Translation of SAS code from the SCF to clean raw SCF panel data for 1983 to 1989

### Analysis
1. `analysis.ipynb`: Code to produce main tables and figures in the text
2. `scf_analysis.ipynb`: Code to produce extra figures using SCF data
