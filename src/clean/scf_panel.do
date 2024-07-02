
************* 1983 panel data *************
global dir "/Users/veronicabackerperal/Dropbox (Princeton)/Princeton/saving-glut"
global data "$dir/data"
global raw "$data/raw"
global working "/$data/working"
global clean "$data/clean"

local vars "ageh bnd savbnd liqcer mfun pen life ofin vehi onfin house oest hdebt pdebt ffa* tinc"

use "$raw/scf/scfpluswith2019", clear
keep if year==1983 
keep if impnum==1

rename id idlong
gen id=real(substr(idlong,5,10))

// Make nominal
foreach var of varlist `vars'{
	if "`var'"=="`ageh'" {
		continue
	}
	replace `var' = `var'*CPI
}

keep id `vars'
rename * *1983

merge 1:m id1983 using "$raw/scf/SCFpanelidmatch", keep(match) nogen
save "$working/panel1983.dta", replace

************* 1989 panel data *************
use "$raw/scf/scf_1983-1989_panel/scf89p.dta", clear

sort xx1 x1
by xx1: keep if _n==1
gen id1983=x40013
gen id1989=xx1
sort id1989

// Identify cases where head/spouse has changed
gen hh_change = x40018==1 | x27202==2 | x27202==3

***** Converted from SAS code: https://www.federalreserve.gov/econres/files/bulletin.macro.txt
gen income=max(x5729,0)
gen age=x14

// Assets 

gen checking = max(0,x3506)*(x3507==5)+max(0,x3510)*(x3511==5)+max(0,x3514)*(x3515==5)+max(0,x3518)*(x3519==5)+max(0,x3522)*(x3523==5)+max(0,x3526)*(x3527==5)+max(0,x3529)*(x3527==5)

gen saving = max(0,x3804)+max(0,x3807)+max(0,x3810)+max(0,x3813)+max(0,x3816)+max(0,x3818)

gen mma = max(0,x3506)*((x3507==1))+max(0,x3510)*((x3511==1))+max(0,x3514)*((x3515==1))+max(0,x3518)*((x3519==1))+max(0,x3522)*((x3523==1))+max(0,x3526)*((x3527==1))+max(0,x3529)*((x3527==1))+max(0,x3706)+max(0,x3711)+max(0,x3716)+max(0,x3718)

gen call = max(0, x3930)
gen prepaid = 0

gen liq = checking + saving + mma + call + prepaid

gen cds = max(0, x3721)

gen STMUTF =(x3821==1)*max(0,x3822)
gen TFBMUTF =(x3823==1)*max(0,x3824)
gen GBMUTF =(x3825==1)*max(0,x3826)
gen OBMUTF =(x3827==1)*max(0,x3828)
gen COMUTF =(x3829==1)*max(0,x3830)
gen nmmf = STMUTF+TFBMUTF+GBMUTF+OBMUTF+COMUTF

gen stocks = max(0,x3915)

gen NOTxBND =x3910
gen MORTBND =x3906
gen GOVTBND =x3908
gen OBND =x3912
gen bond = NOTxBND+MORTBND+GOVTBND+OBND

gen IRAKH = max(0,x3610)+max(0,x3620)+max(0,x3630)

gen THRIFT = 0
local PTYPE x4216 x4316 x4416 x4816 x4916 x5016
local PAMT  x4226 x4326 x4426 x4826 x4926 x5026
local PBOR  x4227 x4327 x4427 x4827 x4927 x5027
local PWIT  x4231 x4331 x4431 x4831 x4931 x5031
local PALL  x4234 x4334 x4434 x4834 x4934 x5034

* Loop through the arrays
forvalues I = 1/6 {
    * Define hold variable
	cap drop HOLD
    gen HOLD = max(0, `: word `I' of `PAMT'') * (inlist(`: word `I' of `PTYPE'', 1, 2, 7, 11, 12, 18) | `: word `I' of `PBOR'' == 1 | `: word `I' of `PWIT'' == 1)
    replace THRIFT = THRIFT + HOLD
}

* Initialize PMOP variable
gen PMOP = .
replace PMOP = x4436 if (x4436 > 0) & (inlist(x4216, 1, 2, 7, 11, 12, 18) | inlist(x4316, 1, 2, 7, 11, 12, 18) | inlist(x4416, 1, 2, 7, 11, 12, 18) | x4231 == 1 | x4331 == 1 | x4431 == 1 | x4227 == 1 | x4327 == 1 | x4427 == 1 )
replace PMOP = 0 if missing(PMOP) & (x4436 > 0) & (x4216 != 0 & x4316 != 0 & x4416 != 0 & x4231 != 0 & x4331 != 0 & x4431 != 0)
replace PMOP = x4436 if missing(PMOP) & (x4436 > 0)
replace PMOP = 0 if missing(PMOP)
replace THRIFT = THRIFT + PMOP

replace PMOP = .
replace PMOP = x5036 if (x5036 > 0) & (inlist(x4816, 1, 2, 7, 11, 12, 18) | inlist(x4916, 1, 2, 7, 11, 12, 18) | inlist(x5016, 1, 2, 7, 11, 12, 18) | x4831 == 1 | x4931 == 1 | x5031 == 1 | x4827 == 1 | x4927 == 1 | x5027 == 1)
replace PMOP = 0 if missing(PMOP) & (x5036 > 0) & (x4816 != 0 & x4916 != 0 & x5016 != 0 & x4831 != 0 & x4931 != 0 & x5031 != 0)
replace PMOP = x5036 if missing(PMOP) & (x5036 > 0)
replace PMOP = 0 if missing(PMOP)
replace THRIFT = THRIFT + PMOP

gen FUTPEN=max(0,x5604)+max(0,x5612)+max(0,x5620)+max(0,x5628)+max(0,x5636)+max(0,x5644)

gen retqliq = IRAKH+THRIFT+FUTPEN

gen savbnd = x3902

gen cashli = max(0, x4006)

gen othma = max(0,x3942)

local l "61, 62, 63, 64, 65, 66, 71, 72, 73, 74, 77, 80, 81, -7"
gen othfin = x4018 + x4022 * inlist(x4020, `l') + x4026 * inlist(x4024, `l') + x4030 * inlist(x4028, `l')

gen fin=liq+cds+nmmf+stocks+bond+retqliq+savbnd+cashli+othma+othfin

// Non-financial
gen vehic = max(0,x8166)+max(0,x8167)+max(0,x8168)+max(0,x2422)+max(0,x2506)+max(0,x2606)+max(0,x2623)

replace x507=9000 if x507>9000
gen houses = x604+x614+x623+x716+((10000-max(0,x507))/10000)*(x513+x526)

local l "12, 14, 21, 22, 25, 40, 41, 42, 43, 44, 49, 50, 52, 999"
gen oresre = max(x1405, x1409) + max(x1505, x1509) + max(x1605, x1609) + max(0, x1619) + (inlist(x1703, `l') * max(0, x1706) * (x1705 / 10000)) + (inlist(x1803, `l') * max(0, x1806) * (x1805 / 10000)) + (inlist(x1903, `l') * max(0, x1906) * (x1905 / 10000)) + max(0, x2002)

local l "1, 2, 3, 4, 5, 6, 7, 10, 11, 13, 15, 24, 45, 46, 47, 48, 51, 53, -7"
gen nnresre = (inlist(x1703, `l') * max(0, x1706) * (x1705 / 10000)) ///
		+ (inlist(x1803, `l') * max(0, x1806) * (x1805 / 10000)) ///
		+ (inlist(x1903, `l') * max(0, x1906) * (x1905 / 10000)) ///
		+ max(0, x2012) ///
		- (inlist(x1703, `l') * x1715 * (x1705 / 10000)) ///
		- (inlist(x1803, `l') * x1815 * (x1805 / 10000)) ///
		- (inlist(x1903, `l') * x1915 * (x1905 / 10000)) - x2016
		
gen flag781 = nnresre!=0
replace nnresre = nnresre - (x2723 * (x2710 == 78)) - (x2740 * (x2727 == 78)) - (x2823 * (x2810 == 78)) - (x2840 * (x2827 == 78)) - (x2923 * (x2910 == 78)) - (x2940 * (x2927 == 78)) if nnresre!=0

replace x507=9000 if x507>9000
replace x507=0 if x507<0
gen farmbus = (x507/10000)*(x513+x526-x805-x905-x1005 - x1108*(x1103==1) - x1119*(x1114==1) - x1130*(x1125==1) )

// Take farm portion out of real estate variables
foreach var of varlist x805 x808 x813 x905 x908 x913 x1005 x1008 x1013 {
	replace `var' = `var'*((10000-x507)/10000)
}

replace x1108 = x1108*((10000-x507)/10000) if x1103==1
replace x1109 = x1109*((10000-x507)/10000) if x1103==1

replace x1119 = x1119*((10000-x507)/10000) if x1114==1
replace x1120 = x1120*((10000-x507)/10000) if x1114==1

replace x1130 = x1130*((10000-x507)/10000) if x1125==1
replace x1131 = x1131*((10000-x507)/10000) if x1125==1

gen bus = max(0, x3129) + max(0, x3124) - max(0, x3126) * (x3127 == 5) + max(0, x3121) * inlist(x3122, 1, 6) + max(0, x3229) + max(0, x3224) - max(0, x3226) * (x3227 == 5) + max(0, x3221) * inlist(x3222, 1, 6) + max(0, x3329) + max(0, x3324) - max(0, x3326) * (x3327 == 5) + max(0, x3321) * inlist(x3322, 1, 6) + max(0, x3335) + farmbus + max(0, x3408) + max(0, x3412) + max(0, x3416) + max(0, x3420) + max(0, x3424) + max(0, x3428)

gen othnfin = x4022+x4026+x4030-othfin+x4018
	  
gen nfin=vehic+houses+oresre+nnresre+bus+othnfin

gen asset=fin+nfin

// Liabilities
gen mrthel = x805+x905+x1005+x1108*(x1103==1)+x1119*(x1114==1)+x1130*(x1125==1)+max(0,x1136)*(x1108*(x1103==1)+x1119*(x1114==1)+x1130*(x1125==1))/(x1108+x1119+x1130) if (x1108+x1119+x1130)>=1
replace mrthel = x805+x905+x1005 + 0.5*(max(0,x1136))*(houses>0) if (x1108+x1119+x1130)<1

local values = "12, 14, 21, 22, 25, 40, 41, 42, 43, 44, 49, 50, 52, 53, 999"
gen mort1 = inlist(x1703, `values') * x1715 * (x1705 / 10000)
gen mort2 = inlist(x1803, `values') * x1815 * (x1805 / 10000)
gen mort3 = inlist(x1903, `values') * x1915 * (x1905 / 10000)

gen resdbt = x1417 + x1517 + x1617 + x1621 + mort1 + mort2 + mort3 + x2006

replace resdbt = resdbt + (x2723 * (x2710 == 78)) + (x2740 * (x2727 == 78)) + (x2823 * (x2810 == 78)) + (x2840 * (x2827 == 78)) + (x2923 * (x2910 == 78)) + (x2940 * (x2927 == 78)) if flag781!=1 & oresre>0
gen flag782 = flag781!=1 & oresre>0

replace resdbt = resdbt + (x2723 * (x2710 == 67)) + (x2740 * (x2727 == 67)) + (x2823 * (x2810 == 67)) + (x2840 * (x2827 == 67)) + (x2923 * (x2910 == 67)) + (x2940 * (x2927 == 67)) if oresre>0
gen flag67 = oresre>0

gen othloc = x1108 * (x1103 != 1) + x1119 * (x1114 != 1) + x1130 * (x1125 != 1) + max(0, x1136) * (x1108 * (x1103 != 1) + x1119 * (x1114 != 1) + x1130 * (x1125 != 1))/(x1108+x1119+x1130) if (x1108+x1119+x1130)>=1
replace othloc = ((houses<=0)+.5*(houses>0))*(max(0,x1136)) if (x1108+x1119+x1130)<1

gen ccbal = max(0,x427)+max(0,x413)+max(0,x421)+max(0,x430)+max(0,x424)

gen install = x2218+x2318+x2418+x2424+x2519+x2619+x2625+x1044+x1215+x1219

replace install = install + (x2723 * (x2710 == 78)) + (x2740 * (x2727 == 78)) + (x2823 * (x2810 == 78)) + (x2840 * (x2827 == 78)) + (x2923 * (x2910 == 78)) + (x2940 * (x2927 == 78)) if flag781==0 & flag782==0

replace install = install + (x2723 * (x2710 == 67)) + (x2740 * (x2727 == 67)) + (x2823 * (x2810 == 67)) + (x2840 * (x2827 == 67)) + (x2923 * (x2910 == 67)) + (x2940 * (x2927 == 67)) if flag67==0

replace install = install + (x2723 * (x2710 != 67 & x2710 != 78)) + (x2740 * (x2727 != 67 & x2727 != 78)) + (x2823 * (x2810 != 67 & x2810 != 78)) + (x2840 * (x2827 != 67 & x2827 != 78)) + (x2923 * (x2910 != 67 & x2910 != 78)) + (x2940 * (x2927 != 67 & x2927 != 78))

gen outpen1 = max(0, x4229) * (x4230 == 5)
gen outpen2 = max(0, x4329) * (x4330 == 5)
gen outpen3 = max(0, x4429) * (x4430 == 5)
gen outpen4 = max(0, x4829) * (x4830 == 5)
gen outpen5 = max(0, x4929) * (x4930 == 5)
gen outpen6 = max(0, x5029) * (x5030 == 5)
gen outmarg = max(0, x3932)

gen odebt=outpen1+outpen2+outpen4+outpen5+max(0,x4010)+max(0,x4032)+outmarg

gen hdebt=mrthel+resdbt
gen pdebt=othloc+ccbal+install+odebt
gen debt=hdebt+pdebt

// Net worth
gen networth=asset-debt

rename x1 case_id 
rename xx1 id 

drop x* j* k*

// Convert to SCFplus variables
gen ageh = age
gen tinc = income
gen ffanw = networth
gen ffafin = fin
gen ffanfin = nfin
gen ffabus = bus
gen house = houses
gen oest = oresre+nnresre
gen vehi = vehic
gen onfin = othnfin
gen ffaequ = stocks
gen liqcer = liq + cds
gen bnd = bond
gen mfun = nmmf
gen ofin = othfin+othma
gen life = cashli
gen pen = retqliq

keep id1989 hh_change wgt* `vars'
foreach var of varlist `vars' {
	rename `var' `var'1989
}

merge 1:1 id1989 using "$raw/scf/SCFpanelidmatch", keep(match) nogen
save "$working/panel1989.dta", replace

// Merge
use "$working/panel1989.dta", clear 
merge 1:1 id1983 id1989 using "$working/panel1983.dta", keep(match) nogen

// Create networth measure that aligns with FOF
foreach year in 1983 1989 {
	gen nw`year'=bnd`year'+savbnd`year'+liqcer`year'+ffaequ`year'+mfun`year'+pen`year'+life`year'+ofin`year'+ffabus`year'+house`year'-hdebt`year'-pdebt`year'
}

foreach var in nw tinc {
	foreach year in 1983 1989 {
		fasterxtile percentile_`var'`year' = `var'`year' [aw=wgt0296], nq(100)
	}
	gen `var'av = (`var'1983+`var'1989)/2
	fasterxtile percentile_`var'av = `var'av [aw=wgt0296], nq(100)
}

// keep if ageh1983>=30 & ageh1983<=65 & hh_change==0 & tinc1983>1000 & tinc1989>1000

export delimited "$clean/scf_panel.csv", replace

