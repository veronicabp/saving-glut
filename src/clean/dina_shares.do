capture program drop collapse_dina
program define collapse_dina
    syntax, nbins(integer) sortvar(string) cutoffs(string) [tag(string)]

    // Capture input options
    local nbins = `nbins'
    local filename "`filename'"
    local sortvar "`sortvar'"
	local cutoffs "`cutoffs'"
	local tag "`tag'"

    // Define variables
    local variables "taxbond currency equity bus fi pens muni ownerhome ownermort nonmort poinc peinc dicsh gov_surplus gov_consumption"

    // Load data
    use "$raw/dina/usdina19622019`tag'.dta", clear
    
	// Collapse into percentile bins
	qui: fasterxtile perc_temp = `sortvar' [aw=dweght], nq(`nbins') by(year)
	gen percentile = .
	foreach cut in `cutoffs' {
		qui: replace percentile = `cut' if perc_temp<=`cut' & percentile==.
	}
	qui: replace percentile = percentile * 100/`nbins'

    // Create returns and other variables
    gen returns = round(dweght / 1e5)
	gen gov_surplus = govin + prisupgov
    drop equity

    rename hwbus bus
    rename hwpen pens
    rename hwequ equity
    rename hwfix fi
    rename colexp gov_consumption
	
	qui: gcollapse (sum) `variables' (count) obs_count=returns [fw=returns], by(year percentile)

	format gov_consumption  %20.0fc
	list gov_consumption if year == 1980
	
    // Interpolate missing years (1963 & 1965)
    qui: xtset percentile year
	qui: tsfill, full
	
	foreach var of varlist `variables' {
		qui: ipolate `var' year, by(percentile) gen(i_`var')
		qui: replace `var' = i_`var'
	}
	qui: drop i_*
	
	list gov_consumption if year == 1980
	
    // Calculate totals and shares
    foreach var of varlist `variables' {
		qui: gegen sz`var' = total(`var'), by(year)
        qui: gen sz`var'sh = `var' / sz`var'
    }

    // Calculate share for misc category
    qui: gen szfash = (equity + fi + bus + pens) / (szequity + szfi + szbus + szpens)
end

********* Collapse DINA by welaht and income percentiles
local i = 1

foreach tag in "" "psz" {
	foreach sort in "hweal" "poinc" {
		collapse_dina, nbins(100) sortvar("`sort'") cutoffs("90 99 100") tag("`tag'")
		
		gen percentile_cuts = percentile
		
		replace percentile=1 if percentile==100
		replace percentile=9 if percentile==99
		
		save "$working/dina`tag'_`sort'sort.dta", replace
		di "Saved `i'."
		local i = `i' + 1
	}
}

// Collapse into 100 bins
local cutoffs
forvalues n = 1/100 {
    local cutoffs `cutoffs' `n'
}
collapse_dina, nbins(100) sortvar("hweal") cutoffs("`cutoffs'") tag("")
gen percentile_cuts = percentile
save "$working/dina_hwealsort_p100.dta", replace
di "Saved `i'."
