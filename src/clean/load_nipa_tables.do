
****** Load NIPA data ******

cap program drop load_nipa_table
program define load_nipa_table
    args file_name
    // Read from CSV
	di "`file_name'"
    qui: import delimited "`file_name'", clear case(lower) varnames(4)
	
    qui: drop line v2
	rename year field
    qui: drop if missing(field)
	
	foreach var of varlist v* {
		local lab: variable label `var'
		rename `var' v`lab'
	}
	
	qui: destring v*, replace force
	qui: replace field = strtrim(field)
	qui: replace field = substr(field, 1, 29)
	qui: gduplicates tag field , gen(dup)
	qui: drop if dup>0
	drop dup

    qui: reshape long v, i(field) j(year)
    qui: drop if missing(v)

    // Reshape data from long to wide format
    qui: reshape wide v, i(year) j(field) string
    qui: drop if missing(year)
    rename v* *
end

// Loop through all files
local files : dir "$raw/nipa/" files "*.csv"
local count = 0
foreach file of local files {
	di "`file'"
	if `count' == 0 {
		load_nipa_table "$raw/nipa/`file'"
		local count = 1
	}
	else {
		load_nipa_table "$raw/nipa/`file'"
		merge 1:1 year using `tmp', nogen
	}
	tempfile tmp
	save `tmp'
}

// Create derived variables
replace InflowTransfersFromROW = 0 if missing(InflowTransfersFromROW)
gen ROW = InflowIncomeReceiptsFromROW + InflowTransfersFromROW - OutflowIncPaymentsToROW - OutflowTransferToROW
gen NationalInc = GDP + ROW + StatisticalDiscrepancy - ConsFixedCap

gen GovDeficit = (GovConsEx + GovIntPayments + Subsidies4 + GovTransPayments - GovCurrentTaxReceipts - GovContribToSSI - GovAssetInc - GovCurrTransferReceipts - GovCurrSurplusEnterprise)
replace GovDeficit = (GovConsEx + GovIntPayments + Subsidies4 + GovTransPayments - GovCurrentTaxReceipts - GovContribToSSI - GovAssetInc - GovCurrTransferReceipts) if missing(GovDeficit)
gen GovSaving = -1 * GovDeficit

gen NetExGoodsAndServicesROW = -NetExGoodsAndServices + ROW
gen NetInvDomestic = GrossInvDomestic - ConsFixedCap

gen GrossSavingBus = SavingBus + ConsFixedCapDomBus
gen GrossSavingPers = SavingPers + ConsFixedCapHouseholdsAndInst

gen NetPrivSav = SavingBus + SavingPers

foreach col of varlist * {
	gen `col'2NI = `col' / NationalInc
}

save "$working/nipa_tables.dta", replace
