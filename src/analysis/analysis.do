

**** Figure 1: Savings by wealth percentile ****
use "$clean/fof_savings.dta", clear 
merge 1:1 year percentile using "$clean/nipa_savings.dta"
drop if year<1963

* Part 1: Figure
preserve
	// Collapse into five-year bins and take difference
	gen year5=(round(year, 5)-1965)/5
	gcollapse FOFsaving2NI DINAsaving2NI CBOsaving2NI (first) year5first=year (last) year5last=year, by(percentile year5)
	gen year5label = substr(string(year5first),3,4) + "-" + substr(string(year5last),3,4)
	labmask year5, values(year5label)

	foreach var of varlist FOFsaving2NI DINAsaving2NI CBOsaving2NI {
		gen `var'_base = `var' if year5==5
		ereplace `var'_base = mean(`var'_base), by(percentile)
		gen `var'_diff = `var' - `var'_base
	}

	foreach p in 1 9 90{
		twoway connected FOFsaving2NI_diff DINAsaving2NI_diff CBOsaving2NI_diff year5 if percentile==`p', ///
			lp(dash solid longdash) lc(dkgreen maroon navy) lw(thick thick thick) ///
			msymbol(D T S) mc(dkgreen maroon navy) ///
			ylabel(,labsize(large)) xtitle("") xlabel(0 1 2 3 4 5 6 7 8 9, valuelabel labsize(medsmall)) ///
			ytitle("Scaled by national income" "(relative to 78-82)", size(large)) ///
			legend(order(1 "Wealth-based approach (net saving)" 2 "Income less consumption approach, DINA" 3 "Income less consumption, CBO") rows(3) position(6))
			graph export "$fig/saving`p'.png", replace
	}
restore

* Part 2: Table
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

	foreach p in 1 9 90{
		eststo clear
		tabstat DINAsaving2NI CBOsaving2NI FOFsaving2NI DINAsaving2NI_diff CBOsaving2NI_diff FOFsaving2NI_diff if percentile==`p', statistics(mean) by(period) nototal save
		tabstatmat tab_glut

		matrix tab_glut = tab_glut
		frmttable using "$tab/saving`p'.tex", replace nocenter fragment statmat(tab_glut) sdec(3)  ///
			rtitle("63-82"\"83-97"\"98-07"\"08-16") ///
			ctitles("", "\underline{\hspace{1.6cm}}\underline{Levels}\underline{\hspace{1.6cm}}", "", "", ///
			"\underline{\hspace{1.2cm}}\underline{Relative to 63-82}\underline{\hspace{1.2cm}}", "", "" \ ///
			"Period", "DINA", "CBO", "Wealth-based", "DINA", "CBO", "Wealth-based") ///
			multicol(1,2,3;1,5,3) tex
	}
restore
