
**** Load CBO income data ****
import excel "$raw/cbo/58353-supplemental-data.xlsx", sheet("10. Household Income Shares") clear
drop if _n<=98 | _n>=140

rename A year 
rename K p91_95
rename L p96_99
rename M p1 

keep year p*
destring, replace

gen p9 = p91_95 + p96_99
drop p91_95 p96_99
gen p90 = 100 - p9 - p1

reshape long p, i(year) j(percentile)
gen CBOshare = p / 100
drop p
save "$working/cbo.dta", replace

***** Load Fisher data *****
use "$raw/fisher/Yfisherfinal.dta", clear
keep if year >= 2004
reshape long fisher, i(year) j(percentile)
collapse (mean) cons_share = fisher, by(percentile)
save "$working/fisher.dta", replace

****** Merge data ******
use "$working/nipa_tables.dta", clear 
merge 1:m year using "$working/dinapsz_poincsort.dta", keep(match) nogen 
merge 1:1 year percentile using "$working/cbo.dta", nogen

gen DINAincome2NI = szpoincsh - szgov_consumptionsh * GovConsEx / NationalInc - szgov_surplussh * GovSaving / NationalInc
gen DINAincome = DINAincome2NI * NationalInc

gen CBOincome2NI = CBOshare * (NationalInc - GovConsEx - GovSaving) / NationalInc
gen CBOincome = CBOincome2NI * NationalInc

// Calculate saving
preserve 
	keep if year==2010 
	merge 1:1 percentile using "$working/fisher.dta", nogen
	gen DINAcons2inc = PersConsEx * cons_share / DINAincome 
	gen CBOcons2inc = PersConsEx * cons_share / CBOincome 
	keep percentile *cons2inc
	
	tempfile cons2inc
	save `cons2inc'
restore

keep DINAincome* CBOincome* year percentile PersConsEx NationalInc
merge m:1 percentile using `cons2inc', keep(match) nogen
reshape wide DINAincome* CBOincome* *cons2inc, i(year) j(percentile)

foreach tag in DINA CBO {
	foreach p in 1 9 {
		gen `tag'consumption`p' = `tag'cons2inc`p' * `tag'income`p'
	}
	// Set consumption of bottom 90 as residual
	gen `tag'consumption90 = PersConsEx - `tag'consumption1 - `tag'consumption9
	
	foreach p in 1 9 90 {
		gen `tag'saving2NI`p' = (`tag'income`p' - `tag'consumption`p')/NationalInc
	}
}

keep year *saving* 
reshape long DINAsaving2NI CBOsaving2NI, i(year) j(percentile)

label var DINAsaving2NI "Saving as a share of national income (calculated using DINA income)"
label var CBOsaving2NI "Saving as a share of national income (calculated using CBO income)"

save "$clean/nipa_savings.dta", replace
