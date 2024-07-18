
***** Load FOF data *****
import delimited "$raw/fof/fof.csv", clear
keep if freq==203 & inlist(series_prefix, "FL", "LM") // Keep annual data in levels

gen year=year(date(time_period, "YMD"))
rename obs_value amount

keep series_name year amount
keep if year>=1950

// Set missing as 0
gegen series_num = group(series_name)
xtset series_num year
tsfill, full
replace amount = 0 if missing(amount)

gsort series_num -series_name
by series_num: replace series_name=series_name[1]
gsort series_name year
save "$working/fof.dta", replace

***** Calculate subcategory shares *****

use "$working/fof.dta", clear
drop series_num
replace series_name = subinstr(series_name, ".A", "", .)

// Need to conduct the reshape by parts since it is very big 
local N = _N
forv i=1/6 {
	di (`i'-1)*(`N')/6
	preserve 
		keep if _n>=(`i'-1)*(`N')/6 & _n<=(`i')*(`N')/6
		reshape wide amount, i(year) j(series_name) string
		rename amount* *
		tempfile part`i'
		save `part`i''
	restore
}

use `part1', clear
forv i=2/6 {
	merge 1:1 year using `part`i'', nogen
}

save "$working/fof_wide.dta", replace

use "$working/fof_wide.dta", clear
// Mutual fund shares 
gen mufu_equ_a_sh = (LM654091600 + LM654092603) / (LM654090000 - LM654091403)
gen mufu_bnd_a_sh = (LM654091303 + LM654091203 - LM653062003) / (LM654090000 - LM654091403)
gen mufu_mun_a_sh = LM653062003 / (LM654090000 - LM654091403)

gen tot = (mufu_equ_a_sh+mufu_bnd_a_sh+mufu_mun_a_sh)
foreach var of varlist mufu_* {
	replace `var'= `var'/tot
}
drop tot

// /interpolate in missing years
gen temp = LM653064100/LM654090000
ipolate mufu_equ_a_sh temp, gen(mufu_equ_a_sh_ipol) epolate
replace mufu_equ_a_sh = mufu_equ_a_sh_ipol if mi(mufu_equ_a_sh)
egen temp2 = mean(mufu_bnd_a_sh/(mufu_mun_a_sh+mufu_bnd_a_sh))
replace mufu_bnd_a_sh = (1 - mufu_equ_a_sh)*temp2 if mi(mufu_bnd_a_sh)
replace mufu_mun_a_sh = 1 - mufu_bnd_a_sh - mufu_equ_a_sh
drop temp* mufu_equ_a_sh_ipol

// Pension shares
gen pens_equ_a_sh = (LM593064105 + mufu_equ_a_sh*LM593064205)/FL594090005
gen pens_fix_a_sh = 1 - pens_equ_a_sh

// Life insurance shares
gen lins_equ_a_sh =  (LM543064105 + mufu_equ_a_sh*LM543064205)/FL544090005
gen lins_fix_a_sh = 1 - lins_equ_a_sh

// Money market fund shares
gen mmfs_mun_a_sh = FL633062000/FL634090005
replace mmfs_mun_a_sh = 0 if missing(mmfs_mun_a_sh)
gen mmfs_oth_a_sh = 1 - mmfs_mun_a_sh

// IRA asset shares
gen iras_fix_a_sh = (FL573020033 + FL573030033 + FL573034055 + LM573061133 + FL573061733 + FL573063033 + FL573065033 + LM573064255 * (mufu_bnd_a_sh + mufu_mun_a_sh)) / (FL573020033 + FL573030033 + FL573034055 + LM573061133 + FL573061733 + FL573063033 + FL573065033 + LM573064133 + LM573064255)
gen iras_equ_a_sh = (LM573064133 + LM573064255 * mufu_equ_a_sh) / (FL573020033 + FL573030033 + FL573034055 + LM573061133 + FL573061733 + FL573063033 + FL573065033 + LM573064133 + LM573064255)

// IRA liability shares
gen iras_chk_l_sh = FL573020033
gen iras_tsd_l_sh = FL573030033
gen iras_mmf_l_sh = FL573034055
gen iras_gse_l_sh = FL573061733
gen iras_cfb_l_sh = FL573063033
gen iras_mor_l_sh = FL573065033
gen iras_sec_l_sh = FL573061133
gen iras_ceq_l_sh = LM573064133

foreach tag in equ bnd mun {
	gen iras_mufu`tag'_l_sh = mufu_`tag'_a_sh * LM573064255
}

egen tot = rsum(iras*_l_sh)
foreach var of varlist iras*_l_sh {
	replace `var' = `var'/tot
}
drop tot

rename *_sh sh* 
keep year sh*
reshape long sh, i(year) j(desc) string

gen isasset = strpos(desc, "_a")!=0 // Identify if share belongs to an asset or liability
// Extract asset name
gen description = "IRA" if strpos(desc, "iras_")
replace description = "Life Insurance Reserves" if strpos(desc, "lins_")
replace description = "Mutual Fund Shares" if strpos(desc, "mufu_")
replace description = "Pension Entitlements" if strpos(desc, "pens_")
replace description = "Money Market Fund Shares" if strpos(desc, "mmfs_")

// Extract subcategory name
gen subcategory = "Equity" 				if strpos(desc, "_equ_")
replace subcategory = "Bond" 			if strpos(desc, "_bnd_")
replace subcategory = "Municipal" 		if strpos(desc, "_mun_")
replace subcategory = "Fixed" 			if strpos(desc, "_fix_")
replace subcategory = "Other" 			if strpos(desc, "_oth_")
replace subcategory = "Checkable Deposits And Currency" 	if strpos(desc, "_chk_")
replace subcategory = "Time And Savings Deposits" 			if strpos(desc, "_tsd_")
replace subcategory = "Money Market Fund Shares" 			if strpos(desc, "_mmf_")
replace subcategory = "Agency- and GSE-Backed Securities" 	if strpos(desc, "_gse_")
replace subcategory = "Corporate And Foreign Bonds" 		if strpos(desc, "_cfb_")
replace subcategory = "Home Mortgages" 						if strpos(desc, "_mor_")
replace subcategory = "Treasury Securities" 				if strpos(desc, "_sec_")
replace subcategory = "Corporate Equities" 					if strpos(desc, "_ceq_")
replace subcategory = "Mutual Fund Shares; Equity" 			if strpos(desc, "_mufuequ_")
replace subcategory = "Mutual Fund Shares; Bond" 			if strpos(desc, "_mufubnd_")
replace subcategory = "Mutual Fund Shares; Municipal" 		if strpos(desc, "_mufumun_")

drop desc
rename sh subcategory_share
save "$working/subcategory_shares.dta", replace

***** Load inflation for known fields *****

// Housing inflation
use "$raw/JST/JSTdatasetR6.dta", clear
keep if country=="USA" & !missing(housing_capgain)
keep year housing_capgain 
rename housing_capgain pi10
gen pi90 = pi10
reshape long pi, i(year) j(infl_percentile_group)
gen inflationcategory = "JST_housing_capgain"
tempfile housing_pi
save `housing_pi'

// Debt writedowns + zero inflation category
use "$raw/callreport/debtwritedown.dta", clear
keep year ZIP*10 ZIP*90
reshape long ZIP_mdebt_wd ZIP_cdebt_wd, i(year) j(infl_percentile_group)
rename *_wd val*
gen valZERO = 0
reshape long val, i(year infl_percentile_group) j(inflationcategory) string 
rename val pi 
replace pi = pi*-1

append using `housing_pi'
save "$working/known_inflation.dta", replace

***** Load DINA data *****
capture program drop load_dina
program define load_dina
	syntax, [tag(string)]
	local tag "`tag'"

	use "$working/dina_hwealsort`tag'.dta", clear
	keep year percentile percentile_cuts sztaxbondsh szfash szmunish szcurrencysh szequitysh szbussh szpenssh szownermortsh sznonmortsh szownerhomesh
	rename sz* percentile_sharesz* 
	reshape long percentile_share, i(year percentile) j(dinacategory) string
	save "$working/distributional_data_temp.dta", replace
end 

capture program drop load_dfa
program define load_dfa
	syntax, [tag(string)]
	// TO DO
	di "TO DO"
end

***** Calculate savings *****
capture program drop calculate_savings
program define calculate_savings
	syntax, [tag(string)] [distributional_data_name(string)]
	local tag "`tag'"
	local distributional_data_name "`distributional_data_name'"
	
	// First, get DINA data
	if "`distributional_data_name'"=="DINA" {
		load_dina, tag("`tag'")
	}
	else {
		load_dfa, tag("`tag'")
		local dd_tag "_dfa"
	}
	
	import delimited "$raw/personal/fof_distributional_relations.csv", clear

	// Collapse rows with multiple series
	expand 2 if strpos(series_name, "-"), gen(idx)
	gsort series_name subcategory  idx
	replace series_name = regexs(1) if regexm(series_name, "(-(FL|LM).+\.A)") & idx==1
	replace series_name = regexs(0) if regexm(series_name, "(FL|LM).+\.A-") & idx==0
	replace series_name = subinstr(series_name, "-", "", .)

	gen invert = idx==1
	drop idx

	joinby series_name using "$working/fof.dta"

	replace amount = -amount if invert==1 
	gcollapse (sum) amount, by(description subcategory isasset inflationcategory dinacategory year) 

	// Remove 2019 and later because we don't have debt writedown data
	drop if year>=2019

	// Merge subcategory shares
	merge 1:1 description subcategory isasset year using "$working/subcategory_shares.dta", keep(master match) nogen
	replace subcategory_share = 1 if missing(subcategory_share)

	// Merge dina data
	di "Merging with DINA"
	joinby year dinacategory using "$working/distributional_data_temp.dta"

	// Calculate share of each asset held by each group
	rename amount total_amount
	gen amount = total_amount * subcategory_share * percentile_share
	replace amount = -amount if !isasset // Set liabilities as negative

	// Merge inflation 
	gen infl_percentile_group = 10 if percentile_cuts>90
	replace infl_percentile_group = 90 if percentile_cuts<=90
	merge m:1 inflationcategory year infl_percentile_group using "$working/known_inflation.dta", keep(master match) nogen

	gen asset_name = description  
	replace asset_name = description + "; " + subcategory if !missing(subcategory)
	keep asset_name percentile year amount pi description subcategory isasset
	order asset_name percentile year amount pi

	gegen g=group(asset_name percentile)
	xtset g year

	gen L_amount = L.amount
	drop if year==1962 // Drop first year (can't calculate saving)

	// Calculate savings and residual inflation
	merge m:1 year using "$working/nipa_tables.dta", keep(match) keepusing(NetPrivSav NationalInc) nogen
	replace NetPrivSav = NetPrivSav*1000 // Put in millions of USD 
	replace NationalInc = NationalInc*1000 

	gen saving = amount - L_amount * (pi+1)
	gen amount_oth = amount if missing(pi)
	gen L_amount_oth = L_amount if missing(pi)

	gegen tot_saving = total(saving), by(year)
	gegen tot_amt_oth = total(amount_oth), by(year)
	gegen tot_L_amt_oth = total(L_amount_oth), by(year)

	gen resid_saving = NetPrivSav - tot_saving 
	gen pi_oth = (tot_amt_oth - resid_saving)/tot_L_amt_oth - 1
	replace pi = pi_oth if missing(pi)

	gen FOF`dd_tag'saving = amount - L_amount * (pi+1)
	gen d_wealth = amount - L_amount 
	gen valuation = d_wealth - FOFsaving

	foreach var of varlist FOF`dd_tag'saving d_wealth valuation {
		gen `var'2NI = `var'/NationalInc
	}
	
	label var FOFsaving "Saving (calculated using wealth approach)"
	label var FOFsaving2NI "Saving as a share of national income (calculated using wealth approach)"
	label var d_wealth "Change in wealth"
	label var d_wealth2NI "Change in wealth as a share of national income"
	label var valuation "Asset valuation increases"
	label var valuation2NI "Asset valuation increases as a share of national income"
	label var percentile "Wealth percentile"
	label var asset_name "Name of financial or non-financial asset"
	label var isasset "(1) = asset, (0) = liability"

	preserve 
		keep FOFsaving* d_wealth* valuation* year percentile asset_name isasset
		save "$clean/fof_savings_by_asset`tag'`dd_tag'.dta", replace
	restore

	gcollapse (sum) FOFsaving2NI d_wealth2NI valuation2NI, by(year percentile)
	
	label var FOFsaving2NI "Saving as a share of national income (calculated using wealth approach)"
	label var d_wealth2NI "Change in wealth as a share of national income"
	label var valuation2NI "Asset valuation increases as a share of national income"
	
	save "$clean/fof_savings`tag'`dd_tag'.dta", replace
end 

calculate_savings, tag("") distributional_data_name("DINA")
calculate_savings, tag("_p100") distributional_data_name("DINA")
