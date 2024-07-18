 
macro drop _all 
clear all
set maxvar 100000
 
global dropbox "/Users/veronicabackerperal/Dropbox (Princeton)"
global home "$dropbox/Princeton/saving-glut"

global data "$home/data"
global raw "$data/raw"
global working "$data/working"
global clean "$data/clean"

global overleaf "$dropbox/Apps/Overleaf/Saving Glut of the Rich"
global fig "$overleaf/Figures"
global tab "$overleaf/Tables"

set scheme plotplainblind


cd "$home/src/clean"
do load_nipa_tables
do dina_shares
do nipa_savings
do fof_savings

cd "$home/src/analysis"
do analysis
