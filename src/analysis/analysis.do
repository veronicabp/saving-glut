*Setting paths
macro drop _all 
clear all
set maxvar 100000
 
global dropbox "C:\Users\am3000.SPI-8VS5N34\Princeton Dropbox\Amil Mumssen"

global home "$dropbox\Princeton\saving-glut-test"

global data "$home\data"
global raw "$data\raw"
global working "$data\working"
global clean "$data\clean"


global overleaf "$dropbox\Apps\Overleaf\Saving Glut of the Rich Test"
global fig "$overleaf\Figures"
global tab "$overleaf\Tables"




set scheme plotplainblind

*Create simplified nipa_tables dataset
use "$working\nipa_tables", clear

keep year NationalInc

save natinc.dta, replace

*Function for weighted mean 
program define weighted_mean, rclass 
    * Syntax to capture two variable names
    syntax varlist(min=3 max=3)
    
    * Parse the input variables
    local var1 : word 1 of `varlist'
    local var2 : word 2 of `varlist'
	local var3 : word 3 of `varlist'
	
	confirm variable `var1'
	confirm variable `var2'
	
	*Create weighted mean 
	tempvar temp_weighted temp_weight_sum temp_value_total wmean
    gen `temp_weighted' = `var1' * `var2'
	egen double `temp_weight_sum' = total(`var2')
	egen double `temp_value_total' = total(`temp_weighted') 
	gen `wmean' = `temp_value_total' / `temp_weight_sum'
	
	* Determine the maximum percentile where value <= weighted mean
    tempvar temp_filter p_wmean 
    gen `temp_filter' = `var1' <= `wmean'
	egen `p_wmean' = max(`var3') if `temp_filter'
    
    
	*Output variables of interest
	return scalar wmean = `wmean'
    return scalar p_wmean = `p_wmean'
	
end


/*

**************************************************************************
		**** SECTION 3: Top 1% Savings and their Absorption ****
**************************************************************************
	


**** Figure 2: Savings by wealth percentile ****

use "$clean/fof_savings.dta", clear 
merge 1:1 year percentile using "$clean/nipa_savings.dta"
drop if year<1963


preserve
	// Collapse into five-year bins and take difference
	gen year5=(round(year, 5)-1965)/5
	gcollapse FOFsaving2NI DINAsaving2NI CBOsaving2NI (first) year5first=year (last) year5last=year, by(percentile year5)
	gen year5label = substr(string(year5first),3,4) + "-" + substr(string(year5last),3,4)
	labmask year5, values(year5label)

	foreach var of varlist FOFsaving2NI DINAsaving2NI CBOsaving2NI {
		gen `var'_base = `var' if year5==3
		ereplace `var'_base = mean(`var'_base), by(percentile)
		gen `var'_diff = `var' - `var'_base
	}

	foreach p in 1 9 90{
		twoway connected FOFsaving2NI_diff DINAsaving2NI_diff CBOsaving2NI_diff year5 if percentile==`p', ///
			lp(dash solid longdash) lc(dkgreen maroon navy) lw(thick thick thick) ///
			msymbol(D T S) mc(dkgreen maroon navy) ///
			ylabel(,labsize(large)) xtitle("") xlabel(0 1 2 3 4 5 6 7 8 9 10 11, valuelabel labsize(medsmall)) ///
			ytitle("Scaled by national income" "(relative to 78-82)", size(large)) ///
			legend(order(1 "Wealth-based approach (net saving)" 2 "Income less consumption approach, DINA" 3 "Income less consumption, CBO") rows(3) position(6))
			graph export "$fig/asaving`p'.png", replace
	}

restore


**** Table 1: Savings by the Top 1%  and Table 3: Dissaving by the Next 9%/Bottom 90% ****
preserve
	// Collapse by period 
	gen period=0 if year>=1963 & year<=1982
	replace period=1 if year>=1983 & year<=1997
	replace period = 2 if year>=1998 & year<=2007
	replace period = 3 if year>=2008 & year<=2019
	
	gcollapse FOFsaving2NI DINAsaving2NI CBOsaving2NI (first) periodfirst=year (last) periodlast=year, by(percentile period)
	gen periodlabel = substr(string(periodfirst),3,4) + "-" + substr(string(periodlast),3,4)
	labmask period, values(periodlabel)


	foreach var of varlist FOFsaving2NI DINAsaving2NI CBOsaving2NI {
		gen `var'_base = `var' if period==0
		ereplace `var'_base = mean(`var'_base), by(percentile)
		gen `var'_diff = `var' - `var'_base
	}

	* Loop through each variable and adjust values close to zero
	foreach var in DINAsaving2NI CBOsaving2NI FOFsaving2NI DINAsaving2NI_diff 		CBOsaving2NI_diff FOFsaving2NI_diff {
		replace `var' = 0 if `var' < 0 & `var' > -0.0005
	}

	foreach p in 1 9 90{
		eststo clear
		tabstat DINAsaving2NI CBOsaving2NI FOFsaving2NI DINAsaving2NI_diff CBOsaving2NI_diff FOFsaving2NI_diff if percentile==`p', statistics(mean) by(period) nototal save
		tabstatmat tab_glut
		matrix tab_glut = tab_glut
		frmttable using "$tab/asaving`p'.tex", replace nocenter fragment statmat(tab_glut) sdec(3)  ///
			rtitle("63-82"\"83-97"\"98-07"\"08-19") ///
			ctitles("", "\underline{\hspace{1.6cm}}\underline{Levels}\underline{\hspace{1.6cm}}", "", "", ///
			"\underline{\hspace{1.2cm}}\underline{Relative to 63-82}\underline{\hspace{1.2cm}}", "", "" \ ///
			"Period", "DINA", "CBO", "Wealth-based", "DINA", "CBO", "Wealth-based") ///
			multicol(1,2,3;1,5,3) tex
	}
restore


**** Figure 3: Net Domestic Investment, Current Account Surplus, Government Saving ****

use "$working\nipa_tables.dta", clear
	
keep if year>=1963  & year <= 2019 
keep year NetInvDomestic2NI NetExGoodsAndServicesROW2NI GovSaving2NI
gen GovBorrowing2NI=-1*GovSaving2NI
gen year5 = ((year-1963)-mod((year-1963),5))/5
replace year5=. if year==1962
replace year5=10 if year>=2018 & year <= 2019 
	
foreach var of varlist NetInvDomestic2NI NetExGoodsAndServicesROW2NI GovBorrowing2NI{
	egen `var'mean=mean(`var'), by(year5)
	gen t=`var'mean if year5==3
	egen t2=min(t)
	gen `var'diff=`var'mean-t2
	drop t2 t
}


bys year5 (year): egen year5first = first(year)
bys year5 (year): gen year5last = year[_N]
gen year5label = substr(string(year5first),3,4) + "-" + substr(string(year5last),3,4)
labmask year5, values(year5label)
drop year5first year5last year5label

	# delimit ;
	graph twoway connected NetInvDomestic2NIdiff NetExGoodsAndServicesROW2NIdiff GovBorrowing2NIdiff year5,
		lp(solid dash longdash) lc(sienna teal purple) lw(thick thick thick)
		msymbol(D T S) mc(sienna teal purple)
		ylabel(-0.08(0.02)0.08,labsize(large)) xtitle("") xlabel(0 1 2 3 4 5 6 7 8 9 10, valuelabel labsize(medsmall)) yscale(titlegap(*-5))
		ytitle("Scaled by national income" "(relative to 78-82)", size(large))
		legend(order(1 "Net domestic investment" 2 "Current account surplus" 3 "-1*Government saving") rows(3) position(6));
	# delimit cr
	graph export "$fig\afig3.png", replace

	

**** Table 2: Traditional Channels of Absorption ****	

use "$working\nipa_tables.dta", clear

keep year NetInvDomestic2NI NetExGoodsAndServicesROW2NI GovSaving2NI
gen period=0 if year>=1963 & year<=1982
replace period=1 if year>=1983 & year<=1997
replace period = 2 if year>=1998 & year<=2007
replace period = 3 if year>=2008 & year<=2019
gen GovBorrowing2NI=-1*GovSaving2NI

foreach var of varlist NetInvDomestic2NI NetExGoodsAndServicesROW2NI GovBorrowing2NI {
	egen t=mean(`var') if period==0
	egen `var'0=min(t)
	gen `var'_dif=`var'-`var'0
	replace `var'_dif = 0 if period==0
	drop t `var'0
}


bys period (year): egen periodfirst = first(year)
bys period (year): gen periodlast = year[_N]
gen periodlabel = substr(string(periodfirst),3,4) + "-" + substr(string(periodlast),3,4)
labmask period, values(periodlabel)
drop periodfirst periodlast periodlabel

tabstat NetInvDomestic2NI NetExGoodsAndServicesROW2NI GovBorrowing2NI NetInvDomestic2NI_dif NetExGoodsAndServicesROW2NI_dif GovBorrowing2NI_dif, statistics(mean) by(period) nototal save
tabstatmat tab_trad_
	
matrix tab_trad_ = tab_trad_

	frmttable using "$tab\atab2.tex", replace nocenter fragment statmat(tab_trad_) sdec(3)  ///
		rtitle("63-82"\"83-97"\"98-07"\"08-19") ///
		ctitles("", "\underline{\hspace{1.6cm}}\underline{Levels}\underline{\hspace{1.6cm}}", "", "", ///
		"\underline{\hspace{1.2cm}}\underline{Relative to 63-82}\underline{\hspace{1.2cm}}", "", "" \ ///
		"Period", "$ I^n$", "$ F$", "$ -S^g$", "$ I^n$", ///
		"$ F$", "$-S^g$") ///
		multicol(1,2,3;1,5,3) tex


**** Figure 4: Saving Across the distribution ****


use "$clean\fof_savings.dta", clear

merge 1:1 year percentile using "$clean\nipa_savings.dta"

drop _merge 




keep FOFsaving2NI DINAsaving2NI CBOsaving2NI d_wealth2NI valuation2NI year percentile 

reshape wide FOFsaving2NI DINAsaving2NI CBOsaving2NI d_wealth2NI valuation2NI, i(year) j(percentile)

gen year5 = ((year-1963)-mod((year-1963),5))/5
replace year5=. if year==1962
replace year5=10 if year>=2018 & year<=2019
bys year5 (year): egen year5first = first(year)
bys year5 (year): gen year5last = year[_N]
gen year5label = substr(string(year5first),3,4) + "-" + substr(string(year5last),3,4)
labmask year5, values(year5label)
drop year5first year5last year5label


collapse (mean) FOFsaving2NI1 FOFsaving2NI9 FOFsaving2NI90 DINAsaving2NI1 DINAsaving2NI9 DINAsaving2NI90 CBOsaving2NI1 CBOsaving2NI9 CBOsaving2NI90, by(year5)




foreach var of varlist FOFsaving2NI1 FOFsaving2NI9 FOFsaving2NI90 DINAsaving2NI1 DINAsaving2NI9 DINAsaving2NI90 CBOsaving2NI1 CBOsaving2NI9 CBOsaving2NI90 {
    gen `var'_base = `var' if year5 == 3
	egen `var'_base_base = mean(`var'_base)
    gen `var'_diff = `var' - `var'_base_base
}




	
	# delimit ;
	graph twoway connected DINAsaving2NI1_diff DINAsaving2NI9_diff DINAsaving2NI90_diff year5,
		lp(dash solid longdash) lc(navy dkgreen maroon) lw(thick thick thick)
		msymbol(D T S) mc(navy dkgreen maroon)
		ylabel(-0.1(0.05)0.05,labsize(large)) xtitle("") xlabel(0 1 2 3 4 5 6 7 8 9 10, valuelabel labsize(medsmall)) yscale(titlegap(*-5))
		ytitle("Scaled by national income" "(relative to 78-82)", size(large))
		legend(order(1 "top 1%" 2 "next 9%" 3 "bottom 90%") rows(3) pos(7) ring(0)) 
		name(g1, replace);
		
	# delimit cr
	graph export "$fig\afig4a.png", replace

	# delimit ;
	graph twoway connected CBOsaving2NI1_diff CBOsaving2NI9_diff CBOsaving2NI90_diff year5,
		lp(dash solid longdash) lc(navy dkgreen maroon) lw(thick thick thick)
		msymbol(D T S) mc(navy dkgreen maroon)
		ylabel(-0.1(0.05)0.05,labsize(large)) xtitle("") xlabel(0 1 2 3 4 5 6 7 8 9 10, valuelabel labsize(medsmall)) yscale(titlegap(*-5))
		ytitle("Scaled by national income" "(relative to 78-82)", size(large))
		legend(order(1 "top 1%" 2 "next 9%" 3 "bottom 90%") rows(3) pos(7) ring(0)) 
		name(g1, replace);
		
	# delimit cr
	graph export "$fig\afig4b.png", replace
	
	# delimit ;
	graph twoway connected FOFsaving2NI1_diff FOFsaving2NI9_diff FOFsaving2NI90_diff year5,
		lp(dash solid longdash) lc(navy dkgreen maroon) lw(thick thick thick)
		msymbol(D T S) mc(navy dkgreen maroon)
		ylabel(-0.1(0.05)0.05,labsize(large)) xtitle("") xlabel(0 1 2 3 4 5 6 7 8 9 10, valuelabel labsize(medsmall)) yscale(titlegap(*-5))
		ytitle("Scaled by national income" "(relative to 78-82)", size(large))
		legend(order(1 "top 1%" 2 "next 9%" 3 "bottom 90%") rows(3) pos(7) ring(0)) 
		name(g1, replace);
		
	# delimit cr
	graph export "$fig\afig4c.png", replace

	

**** Figure X: Saving within cohort ****

use "$raw\mss2021jh\Yjhscfplus.dta", clear 


egen sav_10=rsum(sav???_10)
egen sav_90=rsum(sav???_40 sav???_50)
sort year
gen yearlag=year[_n-1]+1
bys yeargroup (year): egen yearfirst = first(yearlag)
bys yeargroup (year): gen yearlast = year[_N]
gen yeargrouplabel = string(yearfirst) + "-" + string(yearlast)
collapse (mean) sav_?0, by(yeargroup yeargrouplabel)

foreach var of varlist sav_?0{
		replace `var'=. if `var'==0
}
labmask yeargroup, values(yeargrouplabel)
order yeargroup sav_?0
	# delimit ;
		graph twoway scatter sav_10 sav_90 yeargroup,
			xtitle("")
			ytitle("Scaled by national income") c(l l l l l l l)
			m(i i i i i i i i)
			lw(thick thick thick thick thick thick thick)
			lp(solid dash longdash shortdash longdash_dot shortdash_dot dot)
			lc(navy maroon)
			xlabel(1960 1970 1980 1990 2000 2010 2020, valuelabel labsize(small))
			ylabel(-0.04 0 0.04 0.08, labsize(medium))
			legend(order(
			1 "Savings by top 10% (within-cohort)"
			2 "Savings by bottom 90% (within-cohort)"
			)
			rows(2) position(6));
	# delimit cr
	graph export "$fig\afigx.png", replace



**** Figure 5: Absorption of Accumulated Savings by the Top 1% ****

use "$clean/fof_savings.dta", clear 
sort year
merge 1:1 year percentile using "$clean/nipa_savings.dta"
drop if year <= 1962
drop _merge
keep FOFsaving2NI DINAsaving2NI CBOsaving2NI d_wealth2NI valuation2NI year percentile 
reshape wide FOFsaving2NI DINAsaving2NI CBOsaving2NI d_wealth2NI valuation2NI, i(year) j(percentile)

*Merge with nipa_tables

merge 1:1 year using "$working\nipa_tables.dta"

keep if year>=1973 & year<=2019

gen FOFsaving2NI99 = FOFsaving2NI9 + FOFsaving2NI90

* bring everything over to one side (top1 + bot99 - I + F - G + e = 0)
	foreach var of varlist NetExGoodsAndServicesROW2NI NetInvDomestic2NI  StatisticalDiscrepancy2NI {
		replace `var' = -1*`var'
	}

	cap drop check?
	egen checkn = rowtotal(FOFsaving2NI1 FOFsaving2NI99 NetExGoodsAndServicesROW2NI NetInvDomestic2NI  GovSaving2NI)
	gen RStasticalDiscrepancy2NI = -1* checkn
	keep FOFsaving2NI1 FOFsaving2NI99 NetExGoodsAndServicesROW2NI NetInvDomestic2NI  GovSaving2NI RStasticalDiscrepancy2NI year 

	foreach var of varlist NetInvDomestic2NI NetExGoodsAndServicesROW2NI RStasticalDiscrepancy2NI FOFsaving2NI1 FOFsaving2NI99 GovSaving2NI  {
		egen `var'_pre = mean(`var') if year>=1973 & year<=1982
		ereplace `var'_pre = min(`var'_pre)
		gen `var'_d = `var'-`var'_pre
		drop `var'_pre
	}
	collapse (sum) *_d if year>=1983
	rename *_d *
	
	la var NetInvDomestic2NI "I"
	la var NetExGoodsAndServicesROW2NI "F"
	la var RStasticalDiscrepancy2NI "{&epsilon}"
	la var FOFsaving2NI1 `"Top 1% " Saving Glut"'
	la var FOFsaving2NI99 "Bottom 99% Saving"
	la var GovSaving2NI `"Government " Saving"'
	
	# delimit ;
	graph bar (asis) FOFsaving2NI1 NetExGoodsAndServicesROW2NI NetInvDomestic2NI
		FOFsaving2NI99 GovSaving2NI RStasticalDiscrepancy2NI,
		bargap(50) legend(off) blab(name, size(small)) yscale(r(-2.4(1)1.6)) ylabel(-2 -1 0 1)
		bar(1, color(dknavy))
		bar(2, color(dknavy*0.8))
		bar(3, color(dknavy*0.6))
		bar(4, color(maroon))
		bar(5, color(maroon*0.8))
		bar(6, color(maroon*0.6))
		name(`saving', replace);
	# delimit cr
	graph export "$fig\afig5.png", replace



**** Table 4: Valuation Effects ****

use "$clean/fof_savings.dta", clear 
sort year
merge 1:1 year percentile using "$clean/nipa_savings.dta"
drop if year <= 1962




drop _merge 
keep FOFsaving2NI DINAsaving2NI CBOsaving2NI d_wealth2NI valuation2NI year percentile 
reshape wide FOFsaving2NI DINAsaving2NI CBOsaving2NI d_wealth2NI valuation2NI, i(year) j(percentile) 

cap drop period
gen period=0 if year>=1963 & year<=1982
replace period=1 if year>=1983 & year<=1997
replace period = 2 if year>=1998 & year<=2007
replace period = 3 if year>=2008 & year<=2019


bys period (year): egen periodfirst = first(year)
bys period (year): gen periodlast = year[_N]
gen periodlabel = substr(string(periodfirst),3,4) + "-" + substr(string(periodlast),3,4)
labmask period, values(periodlabel)
drop periodfirst periodlast periodlabel

collapse (mean) FOFsaving2NI1 FOFsaving2NI9 FOFsaving2NI90 d_wealth2NI1 valuation2NI1 d_wealth2NI9 valuation2NI9 d_wealth2NI90 valuation2NI90, by(period)


foreach var of varlist  FOFsaving2NI1 FOFsaving2NI9 FOFsaving2NI90 d_wealth2NI1 valuation2NI1 d_wealth2NI9 valuation2NI9 d_wealth2NI90 valuation2NI90 {
	
	gen `var'_base = `var' if period==0
	egen `var'_base_base = mean(`var'_base)
    gen `var'_diff = `var' - `var'_base_base
	replace `var'_diff = 0 if period==0
	drop `var'_base `var'_base_base
	
}

tabstat FOFsaving2NI1 d_wealth2NI1 valuation2NI1 FOFsaving2NI1_diff d_wealth2NI1_diff valuation2NI1_diff, statistics(mean) by(period) nototal save

tabstatmat tab_glut2

matrix tab_glut2 = tab_glut2

frmttable using "$tab\atab4a", replace nocenter fragment statmat(tab_glut2) sdec(3) ///
    rtitle("63-82"\"83-97"\"98-07"\"08-19") ///
    ctitles("", "Top 1\%", "", "", "", "", "" \ ///
    "", "\underline{\hspace{1.6cm}}\underline{Levels}\underline{\hspace{1.6cm}}", "", "", ///
    "\underline{\hspace{1.2cm}}\underline{Relative to 63-82}\underline{\hspace{1.2cm}}", "", "" \ ///
    "Period", "$\Theta$", "$\Delta$ NW", "$\Delta$ V", "$\Theta$", ///
    "$\Delta$ NW", "$\Delta$ V") ///
    multicol(1,2,6;2,2,3;2,5,3) tex
	

tabstat FOFsaving2NI9 d_wealth2NI9 valuation2NI9 FOFsaving2NI9_diff d_wealth2NI9_diff valuation2NI9_diff, statistics(mean) by(period) nototal save

tabstatmat tab_glut3

matrix tab_glut3 = tab_glut3

frmttable using "$tab\atab4b", replace nocenter fragment statmat(tab_glut3) sdec(3) ///
    rtitle("63-82"\"83-97"\"98-07"\"08-19") ///
    ctitles("", "Next 9\%", "", "", "", "", "" \ ///
    "", "\underline{\hspace{1.6cm}}\underline{Levels}\underline{\hspace{1.6cm}}", "", "", ///
    "\underline{\hspace{1.2cm}}\underline{Relative to 63-82}\underline{\hspace{1.2cm}}", "", "" \ ///
    "Period", "$\Theta$", "$\Delta$ NW", "$\Delta$ V", "$\Theta$", ///
    "$\Delta$ NW", "$\Delta$ V") ///
    multicol(1,2,6;2,2,3;2,5,3) tex

tabstat FOFsaving2NI90 d_wealth2NI90 valuation2NI90 FOFsaving2NI90_diff d_wealth2NI90_diff valuation2NI90_diff, statistics(mean) by(period) nototal save

tabstatmat tab_glut4

matrix tab_glut4 = tab_glut4

frmttable using "$tab\atab4c", replace nocenter fragment statmat(tab_glut4) sdec(3) ///
    rtitle("63-82"\"83-97"\"98-07"\"08-19") ///
    ctitles("", "Bottom 90\%", "", "", "", "", "" \ ///
    "", "\underline{\hspace{1.6cm}}\underline{Levels}\underline{\hspace{1.6cm}}", "", "", ///
    "\underline{\hspace{1.2cm}}\underline{Relative to 63-82}\underline{\hspace{1.2cm}}", "", "" \ ///
    "Period", "$\Theta$", "$\Delta$ NW", "$\Delta$ V", "$\Theta$", ///
    "$\Delta$ NW", "$\Delta$ V") ///
    multicol(1,2,6;2,2,3;2,5,3) tex





**** Table 5: Decomposing Savings ****

use "$clean/fof_savings_by_asset.dta", clear

replace isasset = 2 if asset_name == "Real Estate"

collapse (sum) FOFsaving2NI, by(year percentile isasset)


reshape wide FOFsaving2NI, i(year percentile) j(isasset)
reshape wide FOFsaving2NI0 FOFsaving2NI1 FOFsaving2NI2, i(year) j(percentile)
 
gen period=0 if year>=1963 & year<=1982
replace period= 1 if year>=1983 & year<=1997
replace period = 2 if year>=1998 & year<=2007
replace period = 3 if year>=2008 & year<=2019

bys period (year): egen periodfirst = first(year)
bys period (year): gen periodlast = year[_N]
gen periodlabel = substr(string(periodfirst),3,4) + "-" + substr(string(periodlast),3,4)
labmask period, values(periodlabel)
drop periodfirst periodlast periodlabel

collapse (mean) FOFsaving2NI01 FOFsaving2NI11 FOFsaving2NI21 FOFsaving2NI09 FOFsaving2NI19 FOFsaving2NI29 FOFsaving2NI090 FOFsaving2NI190 FOFsaving2NI290, by(period)

rename FOFsaving2NI01 FOFsaving2NIDebt1 
rename FOFsaving2NI09 FOFsaving2NIDebt9
rename FOFsaving2NI090 FOFsaving2NIDebt90
rename FOFsaving2NI11 FOFsaving2NIFA1 
rename FOFsaving2NI19 FOFsaving2NIFA9
rename FOFsaving2NI190 FOFsaving2NIFA90
rename FOFsaving2NI21 FOFsaving2NIRE1 
rename FOFsaving2NI29 FOFsaving2NIRE9
rename FOFsaving2NI290 FOFsaving2NIRE90

gen FOFsaving2NItot1 = FOFsaving2NIDebt1+FOFsaving2NIFA1+FOFsaving2NIRE1
gen FOFsaving2NItot9 = FOFsaving2NIDebt9+FOFsaving2NIFA9+FOFsaving2NIRE9
gen FOFsaving2NItot90 = FOFsaving2NIDebt90+FOFsaving2NIFA90+FOFsaving2NIRE90

foreach var of varlist FOFsaving2NItot1 FOFsaving2NItot9 FOFsaving2NItot90 FOFsaving2NIDebt1 FOFsaving2NIDebt9 FOFsaving2NIDebt90 FOFsaving2NIFA1 FOFsaving2NIFA9 FOFsaving2NIFA90 FOFsaving2NIRE1 FOFsaving2NIRE9 FOFsaving2NIRE90 {
		egen `var'_pre = mean(`var') if period==0
		ereplace `var'_pre = min(`var'_pre)
		gen `var'_d = `var'-`var'_pre
		replace `var'_d = 0 if period==0
		drop `var'_pre
	}

*Top 1% Table
tabstat FOFsaving2NItot1 FOFsaving2NIFA1 FOFsaving2NIRE1 FOFsaving2NIDebt1 FOFsaving2NItot1_d FOFsaving2NIFA1_d FOFsaving2NIRE1_d FOFsaving2NIDebt1_d, statistics(mean) by(period) nototal save

tabstatmat tab_glut5

matrix tab_glut5 = tab_glut5

frmttable using "$tab\atab5a", replace nocenter fragment statmat(tab_glut5) sdec(3) ///
			rtitle("63-82"\"83-97"\"98-07"\"08-19") ///
			ctitles("", "Top 1\%", "", "", "", "", "", "", "" \ ///
			"", "\underline{\hspace{1.6cm}}\underline{Levels}\underline{\hspace{1.6cm}}", "", "", "", ///
			"\underline{\hspace{1.2cm}}\underline{Relative to 63-82}\underline{\hspace{1.2cm}}", "", "", "" \ ///
			"Period", "$\Theta$", "$\Theta^{FA}$", "$\Theta^{RE}$", "$ D$", "$\Theta$", ///
			"$\Theta^{FA}$", "$\Theta^{RE}$", "D") ///
			multicol(1,2,7;2,2,4;2,6,4) tex
			
*Next 9% Table
tabstat FOFsaving2NItot9 FOFsaving2NIFA9 FOFsaving2NIRE9 FOFsaving2NIDebt9 FOFsaving2NItot9_d FOFsaving2NIFA9_d FOFsaving2NIRE9_d FOFsaving2NIDebt9_d, statistics(mean) by(period) nototal save

tabstatmat tab_glut6

matrix tab_glut6 = tab_glut6

frmttable using "$tab\atab5b", replace nocenter fragment statmat(tab_glut6) sdec(3) ///
			rtitle("63-82"\"83-97"\"98-07"\"08-19") ///
			ctitles("", "Next 9\%", "", "", "", "", "", "", "" \ ///
			"", "\underline{\hspace{1.6cm}}\underline{Levels}\underline{\hspace{1.6cm}}", "", "", "", ///
			"\underline{\hspace{1.2cm}}\underline{Relative to 63-82}\underline{\hspace{1.2cm}}", "", "", "" \ ///
			"Period", "$\Theta$", "$\Theta^{FA}$", "$\Theta^{RE}$", "$ D$", "$\Theta$", ///
			"$\Theta^{FA}$", "$\Theta^{RE}$", "D") ///
			multicol(1,2,7;2,2,4;2,6,4) tex

*Bottom 90% Table
tabstat FOFsaving2NItot90 FOFsaving2NIFA90 FOFsaving2NIRE90 FOFsaving2NIDebt90 FOFsaving2NItot90_d FOFsaving2NIFA90_d FOFsaving2NIRE90_d FOFsaving2NIDebt90_d, statistics(mean) by(period) nototal save

tabstatmat tab_glut7

matrix tab_glut7 = tab_glut7

frmttable using "$tab\atab5c", replace nocenter fragment statmat(tab_glut7) sdec(3) ///
			rtitle("63-82"\"83-97"\"98-07"\"08-19") ///
			ctitles("", "Bottom 90\%", "", "", "", "", "", "", "" \ ///
			"", "\underline{\hspace{1.6cm}}\underline{Levels}\underline{\hspace{1.6cm}}", "", "", "", ///
			"\underline{\hspace{1.2cm}}\underline{Relative to 63-82}\underline{\hspace{1.2cm}}", "", "", "" \ ///
			"Period", "$\Theta$", "$\Theta^{FA}$", "$\Theta^{RE}$", "$ D$", "$\Theta$", ///
			"$\Theta^{FA}$", "$\Theta^{RE}$", "D") ///
			multicol(1,2,7;2,2,4;2,6,4) tex			




**** Table 5b: Decomposing Savings (with added columns) ****

use "$clean/fof_savings_by_asset.dta", clear

tostring isasset, replace 

replace isasset = "RE" if asset_name == "Real Estate"

replace isasset = "D" if isasset == "0"

replace isasset = "FX" if inlist(asset_name, "Total Mortgages", "Pension Entitlements; Fixed", "Mutual Fund Shares; Municipal", "Treasury Securities", "Money Market Fund Shares; Municipal", "Mutual Fund Shares; Bond", "Agency- And Gse-Backed Securities")
replace isasset = "FX" if inlist(asset_name,"Corporate And Foreign Bonds", "Life Insurance Reserves; Fixed", "Time And Savings Deposits", "Municipal Securities", "Agency- And GSE-Backed Securities", "Other Loans And Advances", "IRA; Fixed")

replace isasset = "EQ" if inlist(asset_name, "Mutual Fund Shares; Equity", "Pension Entitlements; Equity", "Corporate Equities", "Proprietors' Equity In Noncorporate Business", "IRA; Equity", "Life Insurance Reserves; Equity")

*replace isasset = "EQ" if inlist(asset_name, "Mutual Fund Shares; Equity", "Pension Entitlements; Equity", "Corporate Equities", "Proprietors' Equity In Noncorporate Business", "IRA; Equity", "Life Insurance Reserves; Equity", "Checkable Deposits And Currency")

replace isasset = "FX" if inlist(asset_name, "Money Market Fund Shares; Other", "Foreign Deposits", "Miscellaneous Financial Claims", "Checkable Deposits And Currency")

*replace isasset = "FX" if inlist(asset_name, "Money Market Fund Shares; Other", "Foreign Deposits", "Miscellaneous Financial Claims")

drop if (isasset != "RE" & isasset != "D" & isasset != "FX" & isasset != "EQ")
 
collapse (sum) FOFsaving2NI, by(year percentile isasset)


reshape wide FOFsaving2NI, i(year percentile) j(isasset) string 

reshape wide FOFsaving2NIRE FOFsaving2NID FOFsaving2NIFX FOFsaving2NIEQ, i(year) j(percentile)




 
gen period=0 if year>=1963 & year<=1982
replace period= 1 if year>=1983 & year<=1997
replace period = 2 if year>=1998 & year<=2007
replace period = 3 if year>=2008 & year<=2019

bys period (year): egen periodfirst = first(year)
bys period (year): gen periodlast = year[_N]
gen periodlabel = substr(string(periodfirst),3,4) + "-" + substr(string(periodlast),3,4)
labmask period, values(periodlabel)
drop periodfirst periodlast periodlabel

collapse (mean) FOFsaving2NIRE1 FOFsaving2NID1 FOFsaving2NIFX1 FOFsaving2NIEQ1 FOFsaving2NIRE9 FOFsaving2NID9 FOFsaving2NIFX9 FOFsaving2NIEQ9 FOFsaving2NIRE90 FOFsaving2NID90 FOFsaving2NIFX90 FOFsaving2NIEQ90, by(period)

gen FOFsaving2NIFA1 = FOFsaving2NIFX1 + FOFsaving2NIEQ1
gen FOFsaving2NIFA9 = FOFsaving2NIFX9 + FOFsaving2NIEQ9
gen FOFsaving2NIFA90 = FOFsaving2NIFX90 + FOFsaving2NIEQ90

gen FOFsaving2NITot1 = FOFsaving2NIFA1 + FOFsaving2NIRE1 + FOFsaving2NID1
gen FOFsaving2NITot9 = FOFsaving2NIFA9 + FOFsaving2NIRE9 + FOFsaving2NID9
gen FOFsaving2NITot90 = FOFsaving2NIFA90 + FOFsaving2NIRE90 + FOFsaving2NID90

save temp5.dta, replace 

use "$working\dina_hwealsort.dta", clear 

drop percentile_cuts 
merge 1:1 year percentile using "$clean\fof_savings.dta"
drop _merge 

gen FOFsaving2DI = (FOFsaving) / (dicsh/1e6)

keep year percentile FOFsaving2DI dicsh

 





*Group into percentile bins


gen period=0 if year>=1963 & year<=1982
replace period= 1 if year>=1983 & year<=1997
replace period = 2 if year>=1998 & year<=2007
replace period = 3 if year>=2008 & year<=2019

bys period (year): egen periodfirst = first(year)
bys period (year): gen periodlast = year[_N]
gen periodlabel = substr(string(periodfirst),3,4) + "-" + substr(string(periodlast),3,4)
labmask period, values(periodlabel)
drop periodfirst periodlast periodlabel
drop if missing(period)



collapse (mean) FOFsaving2DI dicsh, by(percentile period)

egen total_dicsh = total(dicsh), by(period)

gen shdicsh = dicsh/total_dicsh 
drop dicsh total_dicsh
reshape wide FOFsaving2DI shdicsh, i(period) j(percentile)
merge 1:1 period using temp5.dta 

/*
use "$clean\fof_savings.dta", clear

merge 1:1 percentile year using "$working\dina_hwealsort.dta"
keep if !missing(FOFsaving)
keep FOFsaving dicsh year percentile equity 
gen FOFsaving2EQ = FOFsaving/(equity/1e6) 
gen FOFsaving2DI = FOFsaving/(dicsh/1e6) 

gen period=0 if year>=1963 & year<=1982
replace period= 1 if year>=1983 & year<=1997
replace period = 2 if year>=1998 & year<=2007
replace period = 3 if year>=2008 & year<=2019

bys period (year): egen periodfirst = first(year)
bys period (year): gen periodlast = year[_N]
gen periodlabel = substr(string(periodfirst),3,4) + "-" + substr(string(periodlast),3,4)
labmask period, values(periodlabel)
drop periodfirst periodlast periodlabel
drop if missing(period)  
drop year 

collapse (mean) FOFsaving2DI FOFsaving2EQ equity dicsh, by(period percentile)

egen total_equity = total(equity), by(period)

gen shequity = equity/total_equity

gen testvar = shequity * FOFsaving2EQ
sort percentile period 
 


use "$clean\fof_savings_by_asset.dta", clear 
tostring isasset, replace  

replace isasset = "RE" if asset_name == "Real Estate"

replace isasset = "D" if isasset == "0"

replace isasset = "FX" if inlist(asset_name, "Total Mortgages", "Pension Entitlements; Fixed", "Mutual Fund Shares; Municipal", "Treasury Securities", "Money Market Fund Shares; Municipal", "Mutual Fund Shares; Bond", "Agency- And Gse-Backed Securities")
replace isasset = "FX" if inlist(asset_name,"Corporate And Foreign Bonds", "Life Insurance Reserves; Fixed", "Time And Savings Deposits", "Municipal Securities", "Agency- And GSE-Backed Securities", "Other Loans And Advances", "IRA; Fixed")

replace isasset = "EQ" if inlist(asset_name, "Mutual Fund Shares; Equity", "Pension Entitlements; Equity", "Corporate Equities", "Proprietors' Equity In Noncorporate Business", "IRA; Equity", "Life Insurance Reserves; Equity")

replace isasset = "FX" if inlist(asset_name, "Money Market Fund Shares; Other", "Foreign Deposits", "Miscellaneous Financial Claims", "Checkable Deposits And Currency")

*replace isasset = 

keep if isasset == "EQ"

keep FOFsaving percentile year 

collapse (sum) FOFsaving, by(percentile year)

merge 1:1 percentile year using "$working\dina_hwealsort.dta"

keep if !missing(FOFsaving)
keep FOFsaving dicsh year percentile equity 

gen period=0 if year>=1963 & year<=1982
replace period= 1 if year>=1983 & year<=1997
replace period = 2 if year>=1998 & year<=2007
replace period = 3 if year>=2008 & year<=2019

bys period (year): egen periodfirst = first(year)
bys period (year): gen periodlast = year[_N]
gen periodlabel = substr(string(periodfirst),3,4) + "-" + substr(string(periodlast),3,4)
labmask period, values(periodlabel)
drop periodfirst periodlast periodlabel
drop if missing(period)  
drop year 

collapse (mean) FOFsaving equity dicsh, by(period percentile)

gen FOFsaving2EQ = FOFsaving/(dicsh/1e6)

egen total_equity = total(equity), by(period)

gen shequity = equity/total_equity

egen total_dicsh = total(equity), by(period)

gen shdicsh = dicsh/total_dicsh 

gen testvar= shequity * FOFsaving2EQ
sort percentile period 

*/



foreach var of varlist FOFsaving2DI* shdicsh* FOFsaving2NI* {
		egen `var'_pre = mean(`var') if period==0
		ereplace `var'_pre = min(`var'_pre)
		gen `var'_d = `var'-`var'_pre
		replace `var'_d = 0 if period==0
		drop `var'_pre
	}

drop _merge 

*Top 1%
tabstat FOFsaving2DI1 shdicsh1 FOFsaving2NITot1 FOFsaving2NIFA1 FOFsaving2NIFX1 FOFsaving2NIEQ1 shdicsh1 FOFsaving2NIRE1 FOFsaving2NID1 FOFsaving2DI1_d shdicsh1_d FOFsaving2NITot1_d FOFsaving2NIFA1_d FOFsaving2NIFX1_d FOFsaving2NIEQ1_d shdicsh1_d FOFsaving2NIRE1_d FOFsaving2NID1_d, statistics(mean) by(period) nototal save

tabstatmat tab_glut12

matrix tab_glut12 = tab_glut12 

frmttable using "$tab\atab5ia.tex", replace nocenter fragment statmat(tab_glut12) sdec(3) ///
			rtitle("63-82"\"83-97"\"98-07"\"08-19") ///
			ctitles("", "Top 1\%", "", "", "", "", "", "", "", "", "", "", "", "","","","","","","","" \ ///
			"", "\underline{\hspace{3.5cm}}\underline{Levels}\underline{\hspace{3.5cm}}", "", "", "", "", "", "" ,"",  ///
			"", "\underline{\hspace{3.5cm}}\underline{Relative to 63-82}\underline{\hspace{3.5cm}}", "", "", "", "", "", "", "", \ ///
			"Period", "S", "$\alpha^{DI}$", "$\Theta$", "$\Theta^{FA}$", "$\Theta^{Fix}$", "$\Theta^{Equ}$", "$\alpha^{equ} S^{\pi}$","$\Theta^{RE}$", "D", ///
					  "S", "$\alpha^{DI}$", "$\Theta$", "$\Theta^{FA}$", "$\Theta^{Fix}$", "$\Theta^{Equ}$", "$\alpha^{equ} S^{\pi}$","$\Theta^{RE}$", "D") ///
			multicol(1,2,19;2,2,9;2,11,9) tex

*Next 9%
tabstat FOFsaving2DI9 shdicsh9 FOFsaving2NITot9 FOFsaving2NIFA9 FOFsaving2NIFX9 FOFsaving2NIEQ9 shdicsh9 FOFsaving2NIRE9 FOFsaving2NID9 FOFsaving2DI9_d shdicsh9_d FOFsaving2NITot9_d FOFsaving2NIFA9_d FOFsaving2NIFX9_d FOFsaving2NIEQ9_d shdicsh9_d FOFsaving2NIRE9_d FOFsaving2NID9_d, statistics(mean) by(period) nototal save

tabstatmat tab_glut13

matrix tab_glut13 = tab_glut13 

frmttable using "$tab\atab5ib.tex", replace nocenter fragment statmat(tab_glut13) sdec(3) ///
			rtitle("63-82"\"83-97"\"98-07"\"08-19") ///
			ctitles("", "Top 1\%", "", "", "", "", "", "", "", "", "", "", "", "","","","","","","","" \ ///
			"", "\underline{\hspace{3.5cm}}\underline{Levels}\underline{\hspace{3.5cm}}", "", "", "", "", "", "" ,"",  ///
			"", "\underline{\hspace{3.5cm}}\underline{Relative to 63-82}\underline{\hspace{3.5cm}}", "", "", "", "", "", "", "", \ ///
			"Period", "S", "$\alpha^{DI}$", "$\Theta$", "$\Theta^{FA}$", "$\Theta^{Fix}$", "$\Theta^{Equ}$", "$\alpha^{equ} S^{\pi}$","$\Theta^{RE}$", "D", ///
					  "S", "$\alpha^{DI}$", "$\Theta$", "$\Theta^{FA}$", "$\Theta^{Fix}$", "$\Theta^{Equ}$", "$\alpha^{equ} S^{\pi}$","$\Theta^{RE}$", "D") ///
			multicol(1,2,19;2,2,9;2,11,9) tex
			
*Bottom 90%
tabstat FOFsaving2DI90 shdicsh90 FOFsaving2NITot90 FOFsaving2NIFA90 FOFsaving2NIFX90 FOFsaving2NIEQ90 shdicsh90 FOFsaving2NIRE90 FOFsaving2NID90 FOFsaving2DI90_d shdicsh90_d FOFsaving2NITot90_d FOFsaving2NIFA90_d FOFsaving2NIFX90_d FOFsaving2NIEQ90_d shdicsh90_d FOFsaving2NIRE90_d FOFsaving2NID90_d, statistics(mean) by(period) nototal save

tabstatmat tab_glut14

matrix tab_glut14 = tab_glut14 

frmttable using "$tab\atab5ic.tex", replace nocenter fragment statmat(tab_glut14) sdec(3) ///
			rtitle("63-82"\"83-97"\"98-07"\"08-19") ///
			ctitles("", "Top 1\%", "", "", "", "", "", "", "", "", "", "", "", "","","","","","","","" \ ///
			"", "\underline{\hspace{3.5cm}}\underline{Levels}\underline{\hspace{3.5cm}}", "", "", "", "", "", "" ,"",  ///
			"", "\underline{\hspace{3.5cm}}\underline{Relative to 63-82}\underline{\hspace{3.5cm}}", "", "", "", "", "", "", "", \ ///
			"Period", "S", "$\alpha^{DI}$", "$\Theta$", "$\Theta^{FA}$", "$\Theta^{Fix}$", "$\Theta^{Equ}$", "$\alpha^{equ} S^{\pi}$","$\Theta^{RE}$", "D", ///
					  "S", "$\alpha^{DI}$", "$\Theta$", "$\Theta^{FA}$", "$\Theta^{Fix}$", "$\Theta^{Equ}$", "$\alpha^{equ} S^{\pi}$","$\Theta^{RE}$", "D") ///
			multicol(1,2,19;2,2,9;2,11,9) tex




**************************************************************************
				**** SECTION 4: Unveiling Results ****
**************************************************************************

	
**** Figure 6: Unveiling Results ****

import delimited "$clean\unveiled_by_instrument.csv", clear


*Assign Instruments into larger groups
gen instrument_large = ""

* Depository and Cash
replace instrument_large = "Depository and Cash" if inlist(instrument, "Checkable Deposits and Currency", "Time and Savings Deposits", "Treasury Securities", "Money Market Fund Shares")

* Corporate
replace instrument_large = "Corporate" if inlist(instrument, "Corporate Equities", "Corporate and Foreign Bonds", "Mutual Fund Shares")

* Non-Corporate
replace instrument_large = "Non-Corporate" if inlist(instrument, "Proprietors' Equity in Noncorporate Business")

* Pass-Through
replace instrument_large = "Pass-Through" if inlist(instrument, "Agency- and GSE-Backed Securities")

* Insurance
replace instrument_large = "Insurance" if inlist(instrument, "Pension Entitlements", "Life Insurance Reserves")

* Other Assets
replace instrument_large = "Other Assets" if inlist(instrument, "Municipal Securities", "Other Loans and Advances", "U.S. Official Reserve Assets and SDR Allocations", "Non-Financial Assets", "U.S. Deposits in Foreign Countries", "Consumer Credit")
replace instrument_large = "Other Assets" if inlist(instrument, "Federal Funds and Security Repurchase Agreements", "Net Interbank Transactions", "Taxes Payable by Businesses", "Open Market Paper", "Direct Investment", "Home Mortgages")
replace instrument_large = "Other Assets" if inlist(instrument, "Commercial Mortgages", "Multifamily Residential Mortgages", "Farm Mortgages", "Trade Credit", "Identified Miscellaneous Financial Claims - Part I", "Identified Miscellaneous Financial Claims - Part II", "Unidentified Miscellaneous Financial Claims")


*Collapse data by primary asset and groups

gen group = ""
replace group = finalholder if finalholder != "Households and Nonprofit Organizations"
replace group = instrument_large if finalholder == "Households and Nonprofit Organizations"

collapse (sum) amount, by(primaryasset group year)

*Scale by Income
merge m:1 year using natinc.dta 

gen wealth2ni = amount/NationalInc





drop _merge 

replace group = "DandC" if group == "Depository and Cash"
replace group = "Cor" if group == "Corporate"
replace group = "NCor" if group == "Non-Corporate"
replace group = "PT" if group == "Pass-Through"
replace group = "Ins" if group == "Insurance"
replace group = "OA" if group == "Other Assets"
replace group = "FedG" if group == "Federal Government"
replace group = "SLG" if group == "State and Local Governments"
replace group = "ROW" if group == "Rest of World"

drop if group == ""
drop amount NationalInc


*Reshape to have seperate columns for each group within every primaryasset-year 
reshape wide wealth2ni, i(primaryasset year) j(group) string

drop if year == 2022

*Convert to percents
foreach var of varlist _all {
    if "`var'" != "primaryasset" & "`var'" != "year" {
        quietly: replace `var' = `var' * 100 
    }
}


gen cum_DandC = wealth2niDandC
gen cum_Cor = cum_DandC + wealth2niCor
gen cum_NCor = cum_Cor + wealth2niNCor
gen cum_PT = cum_NCor + wealth2niPT
gen cum_Ins = cum_PT + wealth2niIns
gen cum_OA = cum_Ins + wealth2niOA
gen cum_ROW = cum_OA + wealth2niROW
gen cum_FedG = cum_ROW + wealth2niFedG
gen cum_SLG = cum_FedG + wealth2niSLG


*Household Figure

preserve 
keep if primaryasset == "Households and Nonprofit Organizations"



graph twoway (area cum_SLG year, color(purple)) ///
             (area cum_FedG year, color(orange)) ///
             (area cum_ROW year, color(khaki)) ///
             (area cum_OA year, color(red)) ///
             (area cum_Ins year, color(pink)) ///
             (area cum_PT year, color(green)) ///
             (area cum_NCor year, color(teal)) ///
             (area cum_Cor year, color(navy)) ///
             (area cum_DandC year, color(blue)), ///
             legend(order(1 "State and Local Governments" 2 "Federal Government" 3 "Rest of World" 4 "Other Assets" 5 "Insurance" 6 "Pass-Through" 7 "Non-Corporate" 8 "Corporate" 9 "Depository and Cash") rows(2) position(1) size(*.7)) ///
			 ylabel(0(20)120, labsize(small)) ///
             ytitle("Households and Nonprofit Organizations Debt Held as % of National Income", size(small))
graph export "$fig\afig6a.png", replace

restore 


*Federal Government Figure
preserve 

keep if primaryasset == "Federal Government"



graph twoway (area cum_SLG year, color(purple)) ///
             (area cum_FedG year, color(orange)) ///
             (area cum_ROW year, color(khaki)) ///
             (area cum_OA year, color(red)) ///
             (area cum_Ins year, color(pink)) ///
             (area cum_PT year, color(green)) ///
             (area cum_NCor year, color(teal)) ///
             (area cum_Cor year, color(navy)) ///
             (area cum_DandC year, color(blue)), ///
             legend(order(1 "State and Local Governments" 2 "Federal Government" 3 "Rest of World" 4 "Other Assets" 5 "Insurance" 6 "Pass-Through" 7 "Non-Corporate" 8 "Corporate" 9 "Depository and Cash") rows(2) position(1) size(*.7)) ///
			 ylabel(0(20)140, labsize(small)) ///
             ytitle("Federal Government Debt Held as % of National Income", size(small))
graph export "$fig\afig6b.png", replace

restore


*Nonfinancial Corporate Business Figure

preserve 
keep if primaryasset == "Nonfinancial Corporate Business"



graph twoway (area cum_SLG year, color(purple)) ///
             (area cum_FedG year, color(orange)) ///
             (area cum_ROW year, color(khaki)) ///
             (area cum_OA year, color(red)) ///
             (area cum_Ins year, color(pink)) ///
             (area cum_PT year, color(green)) ///
             (area cum_NCor year, color(teal)) ///
             (area cum_Cor year, color(navy)) ///
             (area cum_DandC year, color(blue)), ///
             legend(order(1 "State and Local Governments" 2 "Federal Government" 3 "Rest of World" 4 "Other Assets" 5 "Insurance" 6 "Pass-Through" 7 "Non-Corporate" 8 "Corporate" 9 "Depository and Cash") rows(2) position(1) size(*.7)) ///
			 ylabel(0(50)400, labsize(small)) ///
             ytitle("Nonfinancial Corporate Business Debt Held as % of National Income", size(small))
graph export "$fig\afig6c.png", replace

restore 

*Nonfinancial Non-Corporate Business Figure

preserve 
keep if primaryasset == "Nonfinancial Non-Corporate Business"



graph twoway (area cum_SLG year, color(purple)) ///
             (area cum_FedG year, color(orange)) ///
             (area cum_ROW year, color(khaki)) ///
             (area cum_OA year, color(red)) ///
             (area cum_Ins year, color(pink)) ///
             (area cum_PT year, color(green)) ///
             (area cum_NCor year, color(teal)) ///
             (area cum_Cor year, color(navy)) ///
             (area cum_DandC year, color(blue)), ///
             legend(order(1 "State and Local Governments" 2 "Federal Government" 3 "Rest of World" 4 "Other Assets" 5 "Insurance" 6 "Pass-Through" 7 "Non-Corporate" 8 "Corporate" 9 "Depository and Cash") rows(2) position(1) size(*.7)) ///
			 ylabel(0(20)120, labsize(small)) ///
             ytitle("Nonfinancial Non-Corporate Business Debt Held as % of National Income", size(small))
graph export "$fig\afig6d.png", replace

restore
			 




**** Figure 7: Unveiling Results by Wealth Percentile ****

import delimited "$clean\dina_unveiled.csv", clear 

	
keep if (primaryasset == "Federal Government" | primaryasset == "Households and Nonprofit Organizations")

replace primaryasset = "FG" if primaryasset == "Federal Government"
replace primaryasset = "HH" if primaryasset == "Households and Nonprofit Organizations"
tostring percentile, replace
drop finalholder
drop dinawealth 

reshape wide dinawealth2ni, i(year primaryasset) j(percentile) string
reshape wide dinawealth2ni1 dinawealth2ni9 dinawealth2ni90, i(year) j(primaryasset) string

gen dinawealth2ni1both = dinawealth2ni1FG + dinawealth2ni1HH
gen dinawealth2ni9both = dinawealth2ni9FG + dinawealth2ni9HH
gen dinawealth2ni90both = dinawealth2ni90FG + dinawealth2ni90HH

*Top 1% Figure
# delimit ;
	graph twoway connected dinawealth2ni1HH dinawealth2ni9HH dinawealth2ni90HH year,
		lp(solid solid solid) lc(green orange purple) lw(thick thick thick)
		msymbol(D T S) mc(green orange purple)
		ylabel(.05(.05).30,labsize(large)) xtitle("") xlabel(1960 1980 2000 2020, valuelabel labsize(medsmall)) yscale(titlegap(*-5))
		ytitle("Scaled by national income", size(large))
		legend(order(1 "Top 1%" 2 "Next 9%" 3 "Bottom 90%") rows(3) position(4) size(medium));
# delimit cr
graph export "$fig\afig7a.png", replace

*Next 9% Figure
# delimit ;
	graph twoway connected dinawealth2ni1FG dinawealth2ni9FG dinawealth2ni90FG year,
		lp(solid solid solid) lc(green orange purple) lw(thick thick thick)
		msymbol(D T S) mc(green orange purple)
		ylabel(.05(.05).35,labsize(large)) xtitle("") xlabel(1960 1980 2000 2020, valuelabel labsize(medsmall)) yscale(titlegap(*-5))
		ytitle("Scaled by national income", size(large))
		legend(order(1 "Top 1%" 2 "Next 9%" 3 "Bottom 90%") rows(3) position(4) size(medium));
# delimit cr
graph export "$fig\afig7b.png", replace

*Bottom 90% Figure
# delimit ;
	graph twoway connected dinawealth2ni1both dinawealth2ni9both dinawealth2ni90both year,
		lp(solid solid solid) lc(green orange purple) lw(thick thick thick)
		msymbol(D T S) mc(green orange purple)
		ylabel(.1(.1).50,labsize(large)) xtitle("") xlabel(1960 1980 2000 2020, valuelabel labsize(medsmall)) yscale(titlegap(*-5))
		ytitle("Scaled by national income", size(large))
		legend(order(1 "Top 1%" 2 "Next 9%" 3 "Bottom 90%") rows(3) position(4) size(medium));
# delimit cr
graph export "$fig\afig7c.png", replace





**************************************************************************
	**** SECTION 5: Saving in debt across the wealth distribution ****
**************************************************************************

**** Table 6: How Much Financial Asset Accumulation is Claim on Household and Government Debt? ****

import delimited "$clean\dina_unveiled.csv", clear

merge m:1 year using "$working\nipa_tables.dta"

* Sort your data by the group identifiers and the Year
sort primaryasset finalholder percentile year
by primaryasset finalholder percentile: gen l_dinawealth = dinawealth[_n-1]
keep primaryasset finalholder percentile year dinawealth l_dinawealth NationalInc
gen d_dinawealth = dinawealth - l_dinawealth
gen d_dinawealth2ni = d_dinawealth / NationalInc

drop finalholder
drop dinawealth
drop l_dinawealth
drop d_dinawealth
drop NationalInc
replace primaryasset = "FG" if primaryasset == "Federal Government"
replace primaryasset = "HH" if primaryasset == "Households and Nonprofit Organizations"
replace primaryasset = "NFA" if primaryasset == "Non-Financial Assets"
replace primaryasset = "NFC" if primaryasset == "Nonfinancial Corporate Business"
replace primaryasset = "NFNC" if primaryasset == "Nonfinancial Non-Corporate Business"
drop if percentile == .


reshape wide d_dinawealth2ni, i(year percentile) j(primaryasset) string
keep if year >= 1963

gen total = d_dinawealth2niFG + d_dinawealth2niHH + d_dinawealth2niNFA + d_dinawealth2niNFC + d_dinawealth2niNFNC
gen hhfg = d_dinawealth2niFG + d_dinawealth2niHH

keep year percentile d_dinawealth2niHH d_dinawealth2niFG hhfg

save asset2.dta, replace

use "$clean/fof_savings_by_asset.dta", clear

replace isasset = 2 if asset_name == "Real Estate"

collapse (sum) FOFsaving2NI, by(year percentile isasset)


reshape wide FOFsaving2NI, i(year percentile) j(isasset)

merge 1:1 year percentile using asset2.dta

keep year percentile FOFsaving2NI1 d_dinawealth2niHH d_dinawealth2niFG hhfg 

rename FOFsaving2NI FA 
rename d_dinawealth2niHH hh 
rename d_dinawealth2niFG fg 

gen period=0 if year>=1963 & year<=1982
replace period= 1 if year>=1983 & year<=1997
replace period = 2 if year>=1998 & year<=2007
replace period = 3 if year>=2008 & year<=2019

bys period (year): egen periodfirst = first(year)
bys period (year): gen periodlast = year[_N]
gen periodlabel = substr(string(periodfirst),3,4) + "-" + substr(string(periodlast),3,4)
labmask period, values(periodlabel)
drop periodfirst periodlast periodlabel 

collapse (mean) FA hh fg hhfg, by (period percentile)
reshape wide FA hh fg hhfg, i(period) j(percentile)

*Top 1% 
tabstat FA1 hh1 fg1 hhfg1, statistics(mean) by(period) nototal save
tabstatmat tab_glut9
matrix tab_glut9 = tab_glut9

	#delimit;
	frmttable using "$tab\atab6a.tex", replace nocenter fragment statmat(tab_glut9) sdec(3) 
		rtitle("63-82"\"83-97"\"98-07"\"08-19")
		ctitles("Top 1\%", "", "", "", "" \ ///
		"Time Period" "$\Theta^{FA}$" "$\Theta^{HHD}$" "$\Theta^{GOVD}$" "$\Theta^{HHD} +  \Theta^{GOVD}$") 
		multicol(1,1,5) tex;
	#delimit cr;
	
*Next 9% 
tabstat FA9 hh9 fg9 hhfg9, statistics(mean) by(period) nototal save
tabstatmat tab_glut10
matrix tab_glut10 = tab_glut10

	#delimit;
	frmttable using "$tab\atab6b.tex", replace nocenter fragment statmat(tab_glut10) sdec(3) 
		rtitle("63-82"\"83-97"\"98-07"\"08-19")
		ctitles("Next 9\%", "", "", "", "" \ ///
		"Time Period" "$\Theta^{FA}$" "$\Theta^{HHD}$" "$\Theta^{GOVD}$" "$\Theta^{HHD} +  \Theta^{GOVD}$") 
		multicol(1,1,5) tex;
	#delimit cr;
	
*Bottom 90% 
tabstat FA90 hh90 fg90 hhfg90, statistics(mean) by(period) nototal save
tabstatmat tab_glut11
matrix tab_glut11 = tab_glut11

	#delimit;
	frmttable using "$tab\atab6c.tex", replace nocenter fragment statmat(tab_glut11) sdec(3) 
		rtitle("63-82"\"83-97"\"98-07"\"08-19")
		ctitles("Bottom 90\%", "", "", "", "" \ ///
		"Time Period" "$\Theta^{FA}$" "$\Theta^{HHD}$" "$\Theta^{GOVD}$" "$\Theta^{HHD} +  \Theta^{GOVD}$") 
		multicol(1,1,5) tex;
	#delimit cr;
	


**** Table 7: Net Household Debt Positions ****

import delimited "$clean\dina_unveiled.csv", clear

merge m:1 year using "$working\nipa_tables.dta"

* Sort your data by the group identifiers and the Year
sort primaryasset finalholder percentile year
by primaryasset finalholder percentile: gen l_dinawealth = dinawealth[_n-1]
keep primaryasset finalholder percentile year dinawealth l_dinawealth NationalInc
gen d_dinawealth = dinawealth - l_dinawealth
gen d_dinawealth2ni = d_dinawealth / NationalInc

drop finalholder
drop dinawealth
drop l_dinawealth
drop d_dinawealth
drop NationalInc
replace primaryasset = "FG" if primaryasset == "Federal Government"
replace primaryasset = "HH" if primaryasset == "Households and Nonprofit Organizations"
replace primaryasset = "NFA" if primaryasset == "Non-Financial Assets"
replace primaryasset = "NFC" if primaryasset == "Nonfinancial Corporate Business"
replace primaryasset = "NFNC" if primaryasset == "Nonfinancial Non-Corporate Business"
drop if percentile == .


reshape wide d_dinawealth2ni, i(year percentile) j(primaryasset) string
keep if year >= 1963

gen total = d_dinawealth2niFG + d_dinawealth2niHH + d_dinawealth2niNFA + d_dinawealth2niNFC + d_dinawealth2niNFNC
gen hhfg = d_dinawealth2niFG + d_dinawealth2niHH
save asset1.dta, replace

*Get liabilities

use "$clean\fof_savings_by_asset.dta", clear 
keep if isasset==0 & strpos(asset_name, "IRA")==0
gen D = FOFsaving2NI
collapse (sum) D, by(year percentile)

merge 1:1 year percentile using asset1.dta

gen nhhd = d_dinawealth2niHH + D 

keep year percentile D d_dinawealth2niHH nhhd


gen period=0 if year>=1963 & year<=1982
replace period= 1 if year>=1983 & year<=1997
replace period = 2 if year>=1998 & year<=2007
replace period = 3 if year>=2008 & year<=2019

bys period (year): egen periodfirst = first(year)
bys period (year): gen periodlast = year[_N]
gen periodlabel = substr(string(periodfirst),3,4) + "-" + substr(string(periodlast),3,4)
labmask period, values(periodlabel)
drop periodfirst periodlast periodlabel 


collapse (mean) D d_dinawealth2niHH nhhd, by(period percentile)

reshape wide D d_dinawealth2niHH nhhd, i(period) j(percentile)


tabstat D90 d_dinawealth2niHH90 nhhd90 D9 d_dinawealth2niHH9 nhhd9 D1 d_dinawealth2niHH1 nhhd1, statistics(mean) by(period) nototal save
tabstatmat tab_glut8
matrix tab_glut8 = tab_glut8 

frmttable using "$tab\atab7.tex", replace nocenter fragment statmat(tab_glut8) ///
		sdec(3) rtitle("63-82"\"83-97"\"98-07"\"08-19") ctitles("", "Bottom 90\%", "", "", "Next 9\%", "", "", "Top1\%", "", "" \ ///
		"Period", "$ D$" "$\Theta^{HHD}$" "$\Theta^{NHHD}$" "$ D$" "$\Theta^{HHD}$" "$\Theta^{NHHD}$" ///
		"$ D$" "$\Theta^{HHD}$" "$\Theta^{NHHD}$") multicol(1,2,3;1,5,3;1,8,3) tex	



**** Figure 8: Net Household Debt across Wealth Distribution Relative to 1982 ****
import delimited "$clean\dina_unveiled.csv", clear 

keep if primaryasset == "Households and Nonprofit Organizations" 
keep year percentile dinawealth2ni 
rename dinawealth2ni HHDAsset2NI

save asset3.dta, replace
use "$clean\fof_savings_by_asset.dta", clear 


keep if (isasset==0  & (asset_name == "Consumer Credit" | asset_name == "Home Mortgages"))

gen HHDLiab2NI = amount/NationalInc 

collapse (sum) HHDLiab2NI, by(year percentile)

merge 1:1 year percentile using asset3.dta 
gen HHDNet2NI = HHDAsset2NI +  HHDLiab2NI

drop _merge HHDAsset2NI HHDLiab2NI
reshape wide HHDNet2NI, i(year) j(percentile)

foreach var of varlist HHDNet2NI1 HHDNet2NI9 HHDNet2NI90 {
		egen `var'_pre = mean(`var') if year==1982
		ereplace `var'_pre = min(`var'_pre)
		gen `var'_d = `var'-`var'_pre
		drop `var'_pre
	
	}

drop HHDNet2NI1 HHDNet2NI9 HHDNet2NI90

gen zero = 0


# delimit ;
graph twoway (scatter HHDNet2NI1_d HHDNet2NI9_d HHDNet2NI90_d zero year, 
	connect(l l l l) lp(solid dash longdash dash) lc(purple teal navy gray) 
	lw(thick thick thick) msymbol(Dh Oh X i) mcolor(purple teal navy)),
	xlabel(, labsize(medium)) 
	ylabel(-.4(.2).2,labsize(medium)) yscale(titlegap(*-5))
	ytitle("Net Household Debt Position, Scaled by NI", size(medium))
	xtitle("") 
	legend(order(1 "Top 1%" 2 "Next 9%" 3 "Bottom 90%") size(medium) rows(1) position(6));
# delimit cr

graph export "$fig/afig8.png", replace






**** Figure 10: Safe Asset Demand: Who Holds U.S. Government and Household Debt? ****

import delimited "$clean\unveiled.csv", clear

collapse (sum) amount, by(primaryasset year)

gen Final_Holder = "Total"

* Save the summary as a temporary file and reload the original data
tempfile summary
save "`summary'", replace
import delimited "$clean\unveiled.csv", clear

* Append the summary data to the original data
append using "`summary'"

gen percentile = 100

keep if finalholder != "Households and Nonprofit Organizations"

replace finalholder = "Total" if Final_Holder == "Total"

drop Final_Holder

keep if (primaryasset == "Federal Government" | primaryasset == "Households and Nonprofit Organizations")



collapse (sum) amount, by(finalholder percentile year)

merge m:1 year using natinc.dta


sort finalholder percentile year


by finalholder percentile: gen l_amount = amount[_n-1]

gen Sav2ni = (amount - l_amount)/NationalInc

gen Hold2ni = amount/NationalInc

save asset4.dta, replace

import delimited "$clean\dina_unveiled.csv", clear 

rename dinawealth amount

keep if (primaryasset == "Federal Government" | primaryasset == "Households and Nonprofit Organizations")

collapse (sum) amount, by(finalholder percentile year)

merge m:1 year using natinc.dta


sort finalholder percentile year

by finalholder percentile: gen l_amount = amount[_n-1]

gen Sav2ni = (amount - l_amount)/NationalInc

gen Hold2ni = amount/NationalInc

append using asset4.dta

save fig9set.dta, replace

replace finalholder = "Top1" if percentile == 1

replace finalholder = "ROW" if finalholder == "Rest of World"

keep  if (finalholder == "Top1" | finalholder == "ROW")

keep finalholder year Hold2ni 
reshape wide Hold2ni, i(year) j(finalholder) string


 


# delimit ;
graph twoway (scatter Hold2niROW Hold2niTop1 year, 
	connect(l l) lp(longdash dash) lc(purple navy) 
	lw(thick thick) msymbol(Oh Oh) mcolor(purple navy)),
	xlabel(, labsize(large)) 
	ylabel(0(.2).6,labsize(large)) yscale(titlegap(*-5))
	ytitle("Scaled by NI", size(large))
	xtitle("") 
	legend(order(1 "Rest of world" 2 "Top 1%") size(large) rows(1) position(6));
# delimit cr

graph export "$fig/afig10.png", replace



**** Figure 9: Sources of Financing for Rise in Government and Household Debt ****

use fig9set.dta, clear

replace finalholder = "Top 1%" if percentile == 1
replace finalholder = "Next 9%" if percentile == 9
replace finalholder = "Bottom 90%" if percentile == 90

gen year_group = "1983-2019" if year >= 1983 & year <= 2019
replace year_group = "1963-1982" if year >= 1963 & year < 1983

collapse (mean) Sav2ni, by(year_group finalholder)

drop if year_group == ""

replace year_group = "base" if year_group == "1963-1982"
replace year_group = "actual" if year_group == "1983-2019"



reshape wide Sav2ni, i(finalholder) j(year_group) string

gen Sav2ni_diff = Sav2niactual - Sav2nibase

replace finalholder = "Federal Gov." if finalholder == "Federal Government"
replace finalholder = "State & Local Gov." if finalholder == "State and Local Governments"
replace finalholder = "RoW" if finalholder == "Rest of World"
gen order = .
replace order = 1 if finalholder == "Total"
replace order = 2 if finalholder == "RoW"
replace order = 3 if finalholder == "Top 1%"
replace order = 4 if finalholder == "Next 9%"
replace order = 5 if finalholder == "Bottom 90%"
replace order = 6 if finalholder == "Federal Gov."
replace order = 7 if finalholder == "State & Local Gov."


keep finalholder Sav2ni_diff order 
sort order 

# delimit ;
graph twoway (bar Sav2ni_diff order if order==1, color(dkorange) barwidth(0.6))
    (bar Sav2ni_diff order if order==2, color(dkgreen) barwidth(0.6))
    (bar Sav2ni_diff order if order==3, color(dknavy) barwidth(0.6))
    (bar Sav2ni_diff order if order==4, color(teal) barwidth(0.6))
    (bar Sav2ni_diff order if order==5, color(maroon) barwidth(0.6))
    (bar Sav2ni_diff order if order==6, color(purple) barwidth(0.6))
    (bar Sav2ni_diff order if order==7, color(gray) barwidth(0.6))
    ,
    xlabel(1 2 3 4 5 6 7, valuelabel labsize(small))
    xtitle("")
    legend(off) 
    ytitle("Scaled by national income")
	ylabel(-0.015(.005)0.02,labsize(small)) yscale(titlegap(*-5)) 
    xlabel(1 "Total" 2 "RoW" 3 "Top 1%" 4 "Next 9%" 5 "Bottom 90%" 6 "Govt." 7 "Other")
    ;
# delimit cr
graph export "$fig/afig9.png", replace




**************************************************************************
				**** SECTION 7: Addendum to SGR ****
**************************************************************************	

**** Figure 24: Sectoral gross savings to GDP in OECD countries ****

use "$raw\oecd\oecd_sna_ckn2017.dta", clear 

preserve 
keep if year >= 1980

collapse (mean) c_fin-gsave_total2ndispincpriv, by(year)

keep year gsave_hh2gdp_total gsave_corp2gdp_total gsave_gov2gdp_total

gen zero = 0

twoway (line gsave_hh2gdp_total year, color(green) lwidth(thick)) ///
       (line gsave_corp2gdp_total year, color(red) lpattern(solid) lwidth(thick)) ///
       (line gsave_gov2gdp_total year, color(blue) lpattern(solid) lwidth(thick)) ///
	   (line zero year, color(black) lpattern(solid)), ///
       title("Gross saving in OECD countries") ///
	   ylabel(-.025(.025)0.15, labsize(small)) ///
       xtitle("") ///
       ytitle("As a share of GDP") ///
       legend(order(1 "Households" 2 "Corporations" 3 "Government") rows(3) position(6))
	   
graph export "$fig/afig24.png", replace	   

restore 

**** Figure 25: Sectoral gross savings to GDP in OECD and Norway ****

preserve 

keep if (year >= 1980 & country == "Norway")

rename gsave_hh2gdp_total gsave_hh2gdp_total_nor
rename gsave_corp2gdp_total gsave_corp2gdp_total_nor
rename gsave_gov2gdp_total gsave_gov2gdp_total_nor

keep gsave_hh2gdp_total_nor gsave_corp2gdp_total_nor gsave_gov2gdp_total_nor year 

save withnorway.dta, replace

restore 

preserve 
keep if (year >= 1980 & country != "Norway")

collapse (mean) gsave_hh2gdp_total gsave_corp2gdp_total gsave_gov2gdp_total, by(year)

rename gsave_hh2gdp_total gsave_hh2gdp_total_other
rename gsave_corp2gdp_total gsave_corp2gdp_total_other
rename gsave_gov2gdp_total gsave_gov2gdp_total_other

merge 1:1 year using withnorway.dta

gen zero = 0
* Graph for OECD without Norway
twoway (line gsave_hh2gdp_total_other year, color(green) lwidth(thick) lpattern(solid)) ///
       (line gsave_corp2gdp_total_other year, color(red) lwidth(thick) lpattern(solid)) ///
       (line gsave_gov2gdp_total_other year, color(blue) lwidth(thick) lpattern(solid)) ///
	   (line zero year, color(black) lpattern(solid)), /// 
       title("OECD w/o Norway") ///
	   ylabel(-.1(0.05).25, labsize(small)) ///
       ytitle("") xtitle("") ///
       legend(order(1 "Households" 2 "Corporations" 3 "Government") rows(3) position(6))
graph save oecd_wo_norway.gph, replace

* Graph for Norway
twoway (line gsave_hh2gdp_total_nor year, color(green) lwidth(thick) lpattern(solid)) ///
       (line gsave_corp2gdp_total_nor year, color(red) lwidth(thick) lpattern(solid)) ///
       (line gsave_gov2gdp_total_nor year, color(blue) lwidth(thick) lpattern(solid)) ///
	   (line zero year, color(black) lpattern(solid)), ///
       title("Norway") ///
	   ylabel(-.1(0.05).25, labsize(small)) ///
       ytitle("")  xtitle("") ///
       legend(order(1 "Households" 2 "Corporations" 3 "Government") rows(3) position(6))
graph save norway.gph, replace

* Combine the graphs
graph combine oecd_wo_norway.gph norway.gph, cols(2) 

graph export "$fig/afig25.png", replace

restore 



**** Figure 26: Effective savings rate by wealth group ****

use "$raw\oecd\oecd_sna_ckn2017.dta", clear

keep if country == "United States"

merge 1:1 year using "$raw\dfa\dfa_us_shwealth_bywealthgroup_a.dta"
drop _merge 
merge 1:1 year using "$raw\dfa\dfa_us_shwealth_byincomegroup_a.dta"
drop _merge 
merge m:1 year iso3 using "$raw\wid\wid_wealth_income_oecd.dta"

keep if year >= 1980

keep if _merge == 3

keep t1shwealth_equ_corp t10shwealth_equ_corp t1ishwealth_equ_corp t20ishwealth_equ_corp nsave_corp nsave_hh ndispinc_hh t1shinc_ptax t10shinc_ptax t1ishinc_ptax t20ishinc_ptax nsave_hh2ndispinc_hh year 

*Extend shwealth for missing years

foreach var in t1shwealth_equ_corp t10shwealth_equ_corp t1ishwealth_equ_corp t20ishwealth_equ_corp {
    * Find the earliest year with non-missing data for the current variable
    su year if !missing(`var'), detail
    local first_year = r(min)

    * Get the value from the earliest year with non-missing data
    su `var' if year == `first_year', meanonly
    local first_value = r(mean)

    * Replace missing values for years before 1989 with the first available value
    replace `var' = `first_value' if missing(`var')
}


*Calculate Net Saving 
gen t1nsave_corp = t1shwealth_equ_corp * nsave_corp
gen t10nsave_corp = t10shwealth_equ_corp * nsave_corp
gen t1insave_corp = t1ishwealth_equ_corp * nsave_corp
gen t20insave_corp = t20ishwealth_equ_corp * nsave_corp

gen t1nsave_hh = t1shinc_ptax * nsave_hh
gen t10nsave_hh = t10shinc_ptax * nsave_hh
gen t1insave_hh = t1ishinc_ptax * nsave_hh
gen t20insave_hh = t20ishinc_ptax * nsave_hh

*Calculate Disposable income 
gen t1ndispinc_hh = t1shinc_ptax * ndispinc_hh 
gen t10ndispinc_hh = t10shinc_ptax * ndispinc_hh 
gen t1indispinc_hh = t1ishinc_ptax * ndispinc_hh 
gen t20indispinc_hh = t20ishinc_ptax * ndispinc_hh 

*Calculate Effective Saving Rates

foreach var in hh corp {
	gen t1esave_rate_`var' = t1nsave_`var' / t1ndispinc_hh
	gen t10esave_rate_`var' = t10nsave_`var' / t10ndispinc_hh
	gen t1iesave_rate_`var' = t1insave_`var' / t1indispinc_hh
	gen t20iesave_rate_`var' = t20insave_`var' / t20indispinc_hh
	
}
gen t1esave_rate = t1esave_rate_hh + t1esave_rate_corp
gen t10esave_rate = t10esave_rate_hh + t10esave_rate_corp
gen t1iesave_rate = t1iesave_rate_hh + t1iesave_rate_corp
gen t20iesave_rate = t20iesave_rate_hh + t20iesave_rate_corp

keep t1esave_rate t10esave_rate t1iesave_rate t20iesave_rate nsave_hh2ndispinc_hh year 

twoway (line t1esave_rate year, color(red) lwidth(thick) lpattern(solid)) ///
       (line t10esave_rate year, color(teal) lwidth(thick) lpattern(solid)) ///
       (line nsave_hh2ndispinc_hh year, color(purple) lwidth(thick) lpattern(solid)), ///
       title("United States") ///
       ylabel(0(0.1).3, labsize(medium)) ///
       ytitle("") ///
       xtitle("") ///
       legend(order(1 "Top 1% Wealth: Effective Net Saving Rate" 2 "Top 10% Wealth: Effective Net Saving Rate" 3 "Net Saving HH / Net HH Disp Income") rows(3) position(6))

graph export "$fig/afig26.png", replace

**** Figure 27: Effective savings rate by income group ****


twoway (line t1iesave_rate year, color(red) lwidth(thick) lpattern(solid)) ///
       (line t20iesave_rate year, color(teal) lwidth(thick) lpattern(solid)) ///
       (line nsave_hh2ndispinc_hh year, color(purple) lwidth(thick) lpattern(solid)), ///
       title("United States") ///
       ylabel(0(0.1).3, labsize(medium)) ///
       ytitle("") ///
       xtitle("") ///
       legend(order(1 "Top 1% Income: Effective Net Saving Rate" 2 "Top 20% Income: Effective Net Saving Rate" 3 "Net Saving HH / Net HH Disp Income") rows(3) position(6))

graph export "$fig/afig27.png", replace




**** Figure 28: Saving to disposable income by wealth percentile ****

use "$working\dina_hwealsort_p100.dta", clear 

merge 1:1 year percentile using "$clean\fof_savings_p100.dta"
drop _merge 
gen FOFsaving2DI = (FOFsaving) / (dicsh/1e6)

save latefigures.dta, replace 



gen period = 0

replace period = 1 if (year >= 1963 & year <=1982)
replace period = 2 if (year >= 1983 & year <=1997)
replace period = 3 if (year >= 1998 & year <=2019)
drop if period == 0



collapse (mean) FOFsaving2DI dicsh, by(period percentile)


reshape wide FOFsaving2DI dicsh, i(percentile) j(period)


weighted_mean FOFsaving2DI1 dicsh1 percentile 

local wmean1 = r(wmean)
local p_wmean1 = r(p_wmean)


weighted_mean FOFsaving2DI2 dicsh2 percentile 

local wmean2 = r(wmean)
local p_wmean2 = r(p_wmean)


weighted_mean FOFsaving2DI3 dicsh3 percentile 

local wmean3 = r(wmean)
local p_wmean3 = r(p_wmean)


keep if percentile >= 40

twoway (line FOFsaving2DI1 percentile, color(red) lwidth(thick) lpattern(solid)) ///
       (line FOFsaving2DI2 percentile, color(teal) lwidth(thick) lpattern(solid)) ///
       (line FOFsaving2DI3 percentile, color(purple) lwidth(thick) lpattern(solid)) ///
	   (scatteri `wmean1' `p_wmean1' , color(red) msymbol(circle) msize(medium)) ///
       (scatteri `wmean2' `p_wmean2' , color(teal) msymbol(circle) msize(medium)) ///
       (scatteri `wmean3' `p_wmean3' , color(purple) msymbol(circle) msize(medium)), ///
       title("United States") ///
       ylabel(-0.1(0.1)0.6, labsize(small)) ///
       ytitle("") ///
       xtitle("") ///
	   legend(order(4 "Aggregate Saving to Aggregate Disp. Income: 63-82" ///
                    5 "Aggregate Saving to Aggregate Disp. Income: 83-97" ///
                    6 "Aggregate Saving to Aggregate Disp. Income: 98-19" ///
                    1 "Saving to Disp. Inc. of Wealth Perc.: 63-82" ///
                    2 "Saving to Disp. Inc. of Wealth Perc.: 83-97" ///
                    3 "Saving to Disp. Inc. of Wealth Perc.: 98-19") ///
              rows(6) position(6))
graph export "$fig/afig28.png", replace




**** Figure 30-31: Household and corporate savings to disposable income  I and II ****

use "$clean\fof_savings_by_asset_p100.dta", clear

keep if inflationcategory == "OTH"


collapse (sum) FOFsaving percentile_share, by(year percentile)

rename FOFsaving corpsavingalt

merge m:1 year using "$working\nipa_tables.dta"
drop _merge 

keep corpsavingalt percentile_share year percentile NationalInc SavingBus

gen corpsaving = percentile_share * SavingBus 

 
merge 1:1 year percentile using latefigures.dta

keep year percentile corpsaving corpsavingalt dicsh FOFsaving2DI
foreach var in "" "alt"{
	gen corpsaving`var'2DI = corpsaving`var'/ dicsh 
	gen hhsaving`var'2DI = FOFsaving2DI - corpsaving`var'2DI
}

gen period = 0

replace period = 1 if (year >= 1963 & year <=1982)
replace period = 2 if (year >= 1983 & year <=1997)
replace period = 3 if (year >= 1998 & year <=2018)
drop if period == 0

collapse (mean) corpsaving2DI corpsavingalt2DI hhsaving2DI hhsavingalt2DI dicsh, by(period percentile)

reshape wide corpsaving2DI corpsavingalt2DI hhsaving2DI hhsavingalt2DI dicsh, i(percentile) j(period)

*Find weighted means
weighted_mean corpsaving2DI1 dicsh1 percentile 
local wmean_corp1 =  r(wmean)
local p_wmean_corp1 = r(p_wmean)

weighted_mean corpsaving2DI2 dicsh2 percentile 
local wmean_corp2 =  r(wmean)
local p_wmean_corp2 = r(p_wmean)

weighted_mean corpsaving2DI3 dicsh3 percentile 
local wmean_corp3 =  r(wmean)
local p_wmean_corp3 = r(p_wmean)


weighted_mean corpsavingalt2DI1 dicsh1 percentile 
local wmean_corpalt1 =  r(wmean)
local p_wmean_corpalt1 = r(p_wmean)

weighted_mean corpsavingalt2DI2 dicsh2 percentile 
local wmean_corpalt2 =  r(wmean)
local p_wmean_corpalt2 = r(p_wmean)
display `wmean_corpalt2'
display `p_wmean_corpalt2'

weighted_mean corpsavingalt2DI3 dicsh3 percentile 
local wmean_corpalt3 =  r(wmean)
local p_wmean_corpalt3 = r(p_wmean)


weighted_mean hhsaving2DI1 dicsh1 percentile 
local wmean_hh1 =  r(wmean)
local p_wmean_hh1 = r(p_wmean)

weighted_mean hhsaving2DI2 dicsh2 percentile 
local wmean_hh2 =  r(wmean)
local p_wmean_hh2 = r(p_wmean)

weighted_mean hhsaving2DI3 dicsh3 percentile 
local wmean_hh3 =  r(wmean)
local p_wmean_hh3 = r(p_wmean)


weighted_mean hhsavingalt2DI1 dicsh1 percentile 
local wmean_hhalt1 =  r(wmean)
local p_wmean_hhalt1 = r(p_wmean)

weighted_mean hhsavingalt2DI2 dicsh2 percentile 
local wmean_hhalt2 =  r(wmean)
local p_wmean_hhalt2 = r(p_wmean)

weighted_mean hhsavingalt2DI3 dicsh3 percentile 
local wmean_hhalt3 =  r(wmean)
local p_wmean_hhalt3 = r(p_wmean)


keep if percentile >= 40


twoway (line hhsaving2DI1 percentile, color(red) lwidth(thick) lpattern(solid)) ///
       (line hhsaving2DI2 percentile, color(teal) lwidth(thick) lpattern(solid)) ///
       (line hhsaving2DI3 percentile, color(purple) lwidth(thick) lpattern(solid)) ///
	   (scatteri `wmean_hh1' `p_wmean_hh1' , color(red) msymbol(circle) msize(medium)) ///
       (scatteri `wmean_hh2' `p_wmean_hh2' , color(teal) msymbol(circle) msize(medium)) ///
       (scatteri `wmean_hh3' `p_wmean_hh3' , color(purple) msymbol(circle) msize(medium)), ///
       title("HH Saving to Disp Income") ///
       ylabel(-0.1(0.1)0.5, labsize(small)) ///
       ytitle("") ///
       xtitle("") ///
	   legend(order(1 "HH Saving to Disp. Inc. of Wealth Perc.: 63-82" ///
                    2 "HH Saving to Disp. Inc. of Wealth Perc.: 83-97" ///
                    3 "HH Saving to Disp. Inc. of Wealth Perc.: 98-19") ///
              rows(3) position(6))

graph save hhsaving.gph, replace

twoway (line hhsavingalt2DI1 percentile, color(red) lwidth(thick) lpattern(solid)) ///
       (line hhsavingalt2DI2 percentile, color(teal) lwidth(thick) lpattern(solid)) ///
       (line hhsavingalt2DI3 percentile, color(purple) lwidth(thick) lpattern(solid)) ///
	   (scatteri `wmean_hhalt1' `p_wmean_hhalt1' , color(red) msymbol(circle) msize(medium)) ///
       (scatteri `wmean_hhalt2' `p_wmean_hhalt2' , color(teal) msymbol(circle) msize(medium)) ///
       (scatteri `wmean_hhalt3' `p_wmean_hhalt3' , color(purple) msymbol(circle) msize(medium)), ///
       title("HH Saving to Disp Income") ///
       ylabel(-0.1(0.1)0.5, labsize(small)) ///
       ytitle("") ///
       xtitle("") ///
	   legend(order(1 "HH Saving to Disp. Inc. of Wealth Perc.: 63-82" ///
                    2 "HH Saving to Disp. Inc. of Wealth Perc.: 83-97" ///
                    3 "HH Saving to Disp. Inc. of Wealth Perc.: 98-19") ///
              rows(3) position(6))

graph save hhsavingalt.gph, replace


twoway (line corpsaving2DI1 percentile, color(red) lwidth(thick) lpattern(solid)) ///
       (line corpsaving2DI2 percentile, color(teal) lwidth(thick) lpattern(solid)) ///
       (line corpsaving2DI3 percentile, color(purple) lwidth(thick) lpattern(solid)) ///
	   (scatteri `wmean_corp1' `p_wmean_corp1' , color(red) msymbol(circle) msize(medium)) ///
       (scatteri `wmean_corp2' `p_wmean_corp2' , color(teal) msymbol(circle) msize(medium)) ///
       (scatteri `wmean_corp3' `p_wmean_corp3' , color(purple) msymbol(circle) msize(medium)), ///
       title("Corp Saving to Disp Income") ///
       ylabel(-0.00000000(0.0000000005)0.000000002, labsize(small)) ///
       ytitle("") ///
       xtitle("") ///
	   legend(order(1 "Corp. Saving to Disp. Inc. of Wealth Perc.: 63-82" ///
                    2 "Corp. Saving to Disp. Inc. of Wealth Perc.: 83-97" ///
                    3 "Corp. Saving to Disp. Inc. of Wealth Perc.: 98-19") ///
              rows(3) position(6))

graph save corpsaving.gph, replace



twoway (line corpsavingalt2DI1 percentile, color(red) lwidth(thick) lpattern(solid)) ///
       (line corpsavingalt2DI2 percentile, color(teal) lwidth(thick) lpattern(solid)) ///
       (line corpsavingalt2DI3 percentile, color(purple) lwidth(thick) lpattern(solid)) ///
	   (scatteri `wmean_corpalt1' `p_wmean_corpalt1' , color(red) msymbol(circle) msize(medium)) ///
       (scatteri `wmean_corpalt2' 99 , color(teal) msymbol(circle) msize(medium)) ///
       (scatteri `wmean_corpalt3' `p_wmean_corpalt3' , color(purple) msymbol(circle) msize(medium)), ///
       title("Corp Saving to Disp Income") ///
       ylabel(-0.0000001(0.00000005)0.0000002, labsize(small)) ///
       ytitle("") ///
       xtitle("") ///
	   legend(order(1 "Corp. Saving to Disp. Inc. of Wealth Perc.: 63-82" ///
                    2 "Corp. Saving to Disp. Inc. of Wealth Perc.: 83-97" ///
                    3 "Corp. Saving to Disp. Inc. of Wealth Perc.: 98-19") ///
              rows(3) position(6))

graph save corpsavingalt.gph, replace


*Figure 30
graph combine hhsaving.gph corpsaving.gph, cols(2)
graph export "$fig/afig30.png", replace


*Figure 31
graph combine hhsavingalt.gph corpsavingalt.gph, cols(2)
graph export "$fig/afig31.png", replace




**** Figure 29: Average observation count by wealth percentile ****


import delimited "$working\dina_hwealsort_100amil.csv", clear
sort  year percentile 

* Create a new variable for modified Percentile values (optional)
gen percentile_mod = percentile
replace percentile_mod = ceil(percentile/10)*10 - 5 if percentile <= 40

collapse (sum) obs_count, by(year percentile_mod)

collapse (mean) obs_count, by(percentile_mod)

twoway (line obs_count percentile_mod, color(purple)), ///
	   title("United States") ///
       ylabel(0(10000)80000, labsize(small)) ///
       ytitle("Average observation count") ///
       xtitle("Wealth percentile") 

graph export "$fig/afig29.png", replace 


*
**** Figure 32: Corporate savings by wealth group ****

use "$raw\oecd\oecd_sna_ckn2017.dta", clear
keep if country == "United States"
merge 1:1 year using "$raw\dfa\dfa_us_shwealth_bywealthgroup_a.dta"
tab year if _merge == 2 // just 2021 is missing from our OECD data
drop if _merge == 2
drop _merge
merge 1:1 year iso3 using "$raw\wid\wid_wealth_income_oecd.dta", keep(matched) nogen
* Extend the shwealth variables back to 1980 by considering the value is constant and equal to first observation in 1989
	preserve 
		keep *shwealth* 
		ds 
		local vars `r(varlist)'
	restore
	foreach var of varlist `vars' {
		local first_year = year[1]
		replace `var' = `var'[1989 - `first_year' + 1] if year < 1989
	}

* Construct distributed saving variables using wealth groups only 
	local groups "t1 t10"
	foreach group of local groups {
		
		gen `group'nsave_corp		          = `group'shwealth_equ_corp * nsave_corp         
		gen `group'nsave_hh				      = `group'shinc_ptax      * nsave_hh           
		gen `group'ndispinc_hh			      = `group'shinc_ptax      * ndispinc_hh          
		gen `group'esave_rate_hh			  = (							`group'nsave_hh ) / `group'ndispinc_hh
		gen `group'esave_rate_corp			  = (`group'nsave_corp							) / `group'ndispinc_hh
		gen `group'esave_rate				  = (`group'nsave_corp       +	`group'nsave_hh ) / `group'ndispinc_hh

	}

* Construct distributed corporate saving variables using wealth groups only 
	local groups "t1 next9 bot90"
	foreach group of local groups {
		
		gen `group'shgsave_corp2gdp_total    = `group'shwealth_equ_corp * gsave_corp2gdp_total 
		gen `group'shgsave_corp2ndispincpriv = `group'shwealth_equ_corp * gsave_corp2ndispincpriv
		
	}

label variable t1esave_rate   "Top 1% Wealth: Effective net saving rate"
label variable t10esave_rate  "Top 10% Wealth: Effective net saving rate"
label variable t1shgsave_corp2gdp_total      "Top 1% Wealth"
label variable next9shgsave_corp2gdp_total   "Next 9% Wealth"
label variable bot90shgsave_corp2gdp_total   "Bottom 90% Wealth"
label variable t1shgsave_corp2ndispincpriv      "Top 1% Wealth"
label variable next9shgsave_corp2ndispincpriv   "Next 9% Wealth"
label variable bot90shgsave_corp2ndispincpriv   "Bottom 90% Wealth"

keep if year >= 1980
		#delimit ;
		twoway line t1shgsave_corp2gdp_total next9shgsave_corp2gdp_total bot90shgsave_corp2gdp_total
						 year , color(red teal purple) lp(solid solid solid ) lw(medthick medthick medthick medthick medthick medthick) 
								 ytitle("Gross corporate saving to GDP", color(black) size(medsmall)) 
								 xtitle("", size(medsmall)) 
								 name(g1, replace)
								 title("", size(medium))
								 graphregion(color(white)) plotregion(color(white))	
								 legend(
										rows(3) size(small) position(6))
								  
							  ;
		#delimit cr
	save g1.gph, replace

	#delimit ;
		twoway line  t1shgsave_corp2ndispincpriv next9shgsave_corp2ndispincpriv bot90shgsave_corp2ndispincpriv
						 year , color(red teal purple) lp(solid solid solid) lw(medthick medthick medthick ) 
								 ytitle("Gross corporate saving to Net Priv. Disp. Income", color(black) size(medsmall)) 
								 xtitle("", size(medsmall)) 
								 name(g2, replace)
								 title("", size(medium))
								 graphregion(color(white)) plotregion(color(white))	
								 legend(
										rows(3) size(small) position(6))
							  ;
		#delimit cr
	save g2.gph, replace 
	
graph combine g1 g2, cols(2) ycommon title("United States")

graph export "$fig/afig32.png", replace







**** Figure 33: Financial assets held by non-financial firms ****

import delimited "$raw\fof\fof.csv", clear 


*Get fof function 

keep if freq == 203

gen date_var = date(time_period, "YMD") 

format date_var %td


gen year = year(date_var)

rename obs_value amount 

keep series_name year description amount 


*Fill in missing values for amount and description 
levelsof series_name, local(series)
levelsof year, local(years)

gen one = 1
save fofcombination1.dta, replace

clear 
set obs `: word count `series''
gen series_name = ""
local i = 1
foreach s of local series {
    replace series_name = "`s'" in `i'
    local i = `i' + 1
}

gen one = 1

save fofcombination2.dta, replace

clear
set obs `: word count `years''
gen year = .
local i = 1
foreach y of local years {
    replace year = `y' in `i'
    local i = `i' + 1
}
gen one = 1

joinby one using fofcombination2.dta
drop one

merge 1:1 year series_name using fofcombination1.dta

replace amount = 0 if missing(amount)

sort series_name year 
local changes = 1
while `changes' > 0 {
    quietly {
        * Capture the number of missing values before the operation
        count if missing(description)
        local before = r(N)

        * Perform the backward fill
        bysort series_name (year): replace description = description[_n+1] if missing(description)

        * Capture the number of missing values after the operation
        count if missing(description)
        local after = r(N)
    }
    * Determine if any changes were made
    local changes = `before' - `after'
}

* Loop over forward fill until no more changes are made
local changes = 1
while `changes' > 0 {
    quietly {
        * Capture the number of missing values before the operation
        count if missing(description)
        local before = r(N)

        * Perform the forward fill
        bysort series_name (year): replace description = description[_n-1] if missing(description)

        * Capture the number of missing values after the operation
        count if missing(description)
        local after = r(N)
    }
    * Determine if any changes were made
    local changes = `before' - `after'
}

sort series_name year 


keep if inlist(series_name, "FL104090005.A", "FL114090005.A", "FA896140001.A", "FL102000005.A", "FL112000005.A") 
replace series_name = "FL104090005A" if series_name == "FL104090005.A"
replace series_name = "FL114090005A" if series_name == "FL114090005.A"
replace series_name = "FA896140001A" if series_name == "FA896140001.A"
replace series_name = "FL102000005A" if series_name == "FL102000005.A"
replace series_name = "FL112000005A" if series_name == "FL112000005.A"

drop _merge description one 
reshape wide amount, i(year) j(series_name) string

gen totl_assets = amountFL102000005A + amountFL112000005A
gen nfc_atotlfin2NI =  amountFL104090005A/amountFA896140001A
gen nfnc_atotlfin2NI = amountFL114090005A/amountFA896140001A
gen nfc_nfnc_atotlfin2NI = (amountFL104090005A + amountFL114090005A)/amountFA896140001A
gen nfc_atotlfin2atotl_both = amountFL104090005A/totl_assets 
gen nfnc_atotlfin2atotl_both = amountFL114090005A/totl_assets
gen nfc_nfnc_atotlfin2atotl_both = (amountFL104090005A + amountFL114090005A)/totl_assets


keep if year >= 1945


twoway (line nfc_atotlfin2atotl_both year, color(green) lwidth(thick) lpattern(dash)) ///
       (line nfnc_atotlfin2atotl_both year, color(maroon) lwidth(thick) lpattern(longdash)) ///
       (line nfc_nfnc_atotlfin2atotl_both year, color(navy) lwidth(thick) lpattern(solid)), ///
       ylabel(, labsize(small)) ///
       ytitle("Financial assets as a share of non-financial firms") ///
       xtitle("") ///
	   legend(order(1 "Corporate" 2 "Non-Corporate" 3 "All Financial Firms") position(6) rows(3))
	   
graph save assetsbynf1.gph, replace


twoway (line nfc_atotlfin2NI year, color(green) lwidth(thick) lpattern(dash)) ///
       (line nfnc_atotlfin2NI year, color(maroon) lwidth(thick) lpattern(longdash)) ///
       (line nfc_nfnc_atotlfin2NI year, color(navy) lwidth(thick) lpattern(solid)), ///
       ylabel(, labsize(small)) ///
       ytitle("Financial assets as a share of national income") ///
       xtitle("") ///
	   legend(order(1 "Corporate" 2 "Non-Corporate" 3 "All Financial Firms") position(6) rows(3))
	   
graph save assetsbynf2.gph, replace

graph combine assetsbynf1.gph assetsbynf2.gph, cols(2)

graph export "$fig/afig33.png", replace




**** Figure 34: Gross and Net Savings in the Private Sector ****

use "$working\nipa_tables.dta", clear 

keep if year >= 1960

keep year GrossSavingBus2NI SavingBus2NI ConsFixedCapDomBus2NI GrossSavingPers2NI SavingPers2NI ConsFixedCapHouseholdsAndInst2NI


twoway (line GrossSavingBus2NI year, color(navy) lwidth(thick) lpattern(solid)) ///
       (line SavingBus2NI year, color(green) lwidth(thick) lpattern(solid)) ///
       (line ConsFixedCapDomBus2NI year, color(maroon) lwidth(thick) lpattern(dash)), ///
	   title("Business") ///
       ylabel(, labsize(small)) ///
       ytitle("As a share of national income") ///
       xtitle("") ///
	   xline(1976, lcolor(gray) lwidth(medium) lpattern(solid)) ///
	   legend(order(1 "Gross Saving" 2 "Net Saving" 3 "Consumption and Fixed Capital") position(6) rows(3))
	   
graph save grnetsavpriv1.gph, replace


twoway (line GrossSavingPers2NI year, color(navy) lwidth(thick) lpattern(solid)) ///
       (line SavingPers2NI year, color(green) lwidth(thick) lpattern(solid)) ///
       (line ConsFixedCapHouseholdsAndInst2NI year, color(maroon) lwidth(thick) lpattern(dash)), ///
	   title("HH and NPISH") ///
       ylabel(, labsize(small)) ///
       ytitle("As a share of national income") ///
       xtitle("") ///
	   xline(1976, lcolor(gray) lwidth(medium) lpattern(solid)) ///
	   legend(order(1 "Gross Saving" 2 "Net Saving" 3 "Consumption and Fixed Capital") position(6) rows(3))
	   
graph save grnetsavpriv2.gph, replace

graph combine grnetsavpriv1.gph grnetsavpriv2.gph, cols(2)

graph export "$fig/afig34.png", replace













