/***************************************************************************/
/*+-*+-*+-*+-*- MEDIA SLANT REPLICATION (Text Analysis 2020) --*+-*+-*+-*+-*/
/***************************************************************************/

global maindir "E:/Dropbox/_Pre-Doc/NLP_Class_Preparation/David/python_prac3"
global datadir "E:/Dropbox/_Pre-Doc/NLP_Class_Preparation/David/python_prac3/data"
global tempdir "E:/Dropbox/_Pre-Doc/NLP_Class_Preparation/David/python_prac3/temp"

clear all
set more off

/***************************************************************************//*
This do file replications the computation of immigration-specific media slant 
of NewsLibrary articles released yearly. This replicates the method developed
by Gentzkow and Shapiro (2010).

The process below can be summarized in a series of steps:

1 - Of the 500 phrases that are most predictive of the speakers' affiliation to
	the Republican party, the code keeps the ones encountered in NewsLibrary 
	articles at least 10 times (these result in 369 phrases)

2 - For each phrase `p' and each congressperson `c', the code computes the
	relative frequency of the phrase in Congressional speech

3 - The code then regresses the relative frequency on an indicator for the 
	congressperson's party, obtaining phrase-specific intercept and slope 
	coefficients `a' and `b'
		- # Regresions   = # Top Phrases
		- # Observations = # Congresspeople

4 - Next, the code computes the relative frequency of each phrase in NewsLibrary
	articles released in a given year.

5 - Finally, for each newspaper we regress its relative immigrant-related phrase
	frequency (substracting `a') on all phrase-specific `b' obtained above (measures
	the phrase's ideological load). The resulting coeficient estimates reflect
	the time-varying measure of slant.
	
*//***************************************************************************/

* Baseline temporary dta
save $tempdir/SLANT_alpha_beta_coefs_NLnps, empty replace
save $tempdir/phrases_list_NLnps, empty replace
save $tempdir/SLANT_FINAL_AP_NLnps, empty replace


/*1st step: keep only phrases that are used more than 10 times over the whole period in the NL articles*/
/*First, append all the processed year CSVs for NewsLibrary*/

/*Small fix on the 2013 CSV file: drop 1 of the preprocessed obs which is weird*/
import delimited using "$datadir/NL_processed_np/NL_processed_np_2013.csv", clear varn(1)
set more off
desc n
tab n, m
capture drop if n != "1"
destring n, replace
export delimited using "$datadir/NL_processed_np/NL_processed_np_2013.csv", replace 

/*Append everything*/
clear*
save "$datadir/NL_processed_np/NL_processed_np_allyears.dta", empty replace
set more off
local nl_processed_csvs: dir "$datadir/NL_processed_np/" files "*.csv"

foreach f of local nl_processed_csvs {
    import delimited using "$datadir/NL_processed_np/`f'", clear varn(1)
    
    append using "$datadir/NL_processed_np/NL_processed_np_allyears.dta"
    save "$datadir/NL_processed_np/NL_processed_np_allyears.dta", replace
}

use "$datadir/NL_processed_np/NL_processed_np_allyears.dta", clear

/*Drop the Congress phrases that appear less than 10 times in the NewsLibrary newspaper articles dataset over the whole period*/
/* SLOW */
import delimited using "$datadir/top_500_speech_phrases.csv", clear varn(1)
set more off
gen n=1

tempfile phrases_data
   save `phrases_data', replace

forval nn = 1/500 {

	use `phrases_data', clear
	keep if _n == `nn'
	merge 1:m n using "$datadir/NL_processed_np/NL_processed_np_allyears.dta"

	    gen mm = 0
	replace mm = 1 if strpos(preproc_nl_articles, phrase) >0

	collapse (sum) mm, by(phrase chi2)
	duplicates drop
	
	keep if mm >= 10
	
	gen n = 1
	
	drop mm
	
	append using $tempdir/phrases_list_NLnps
	        save $tempdir/phrases_list_NLnps, replace
		}
		
/*Checking: 369 phrases.*/
use $tempdir/phrases_list_NLnps, clear
		
************************************************************
/*2nd step: Get the betas and alphas of the regression of phrases on ideology*/		
*** match each to each speech 

import delimited using $datadir/Speech_processed.csv, clear varn(1)
set more off

gen n=1

joinby n using $tempdir/phrases_list_NLnps

    gen phrase_found = 0 
replace phrase_found = 1 if strpos(preproc_speech, phrase)>0
tab phrase_found, m

collapse (sum) phrase_found, by(speaker party_ phrase chi2)

**** total phrase frquency by congressman
bys speaker: egen total_freq = total(phrase_found)

gen relative_freq = phrase_found/ total_freq

su relative_freq, d

gen party = 0
replace party = 1 if party_ == "R"

**** for each phrase: obtain intercept and slope from regression on party 
set more off
levelsof phrase, local(phrases)
foreach phr of local phrases {

	preserve

	keep if phrase == "`phr'"
	
	reg relative_freq  party 

	regsave 

	gen phrase = "`phr'"
	
	append using $tempdir/SLANT_alpha_beta_coefs_NLnps
 	        save $tempdir/SLANT_alpha_beta_coefs_NLnps, replace
	restore	
	sleep 250 // Necessary to prevent loop from trampling upon itself
			}

/*4th-5th step*/
use $tempdir/SLANT_alpha_beta_coefs_NLnps, clear	
set more off

keep var coef phrase
duplicates report phrase
*duplicates drop phrase var, force
count if var == ""
*keep if var == "party"

reshape wide coef, i(phrase) j(var)	string	
				
rename coef_cons alpha
rename coefparty beta	

save $tempdir/SLANT_alpha_beta_coefs_NLnps, replace
		
**** Read in NewsLibrary newspaper articles for each year and after pre-processing text + with date variable			
use "$datadir/NL_processed_np/NL_processed_np_allyears.dta", clear
set more off
*tab npname1, m
levelsof year, local(yys)
*local yys 2015 2016 2017
*levelsof npname1, local(nps)

foreach yy of local yys {
use "$datadir/NL_processed_np/NL_processed_np_allyears.dta", clear
set more off
keep if year == `yy'
levelsof npname1, local(nps)
	foreach np of local nps {
	preserve

		*keep if year == `yy' & npname1 == "`np'"
		keep if npname1 == "`np'"

		joinby n using $tempdir/phrases_list_NLnps

			gen phrase_found = 0 
		replace phrase_found = 1 if strpos(preproc_nl_articles, phrase)>0

		collapse (sum) phrase_found, by(phrase)

		**** total phrase frequency by q
		egen total_freq = total(phrase_found)

		gen relative_freq = phrase_found/ total_freq

		merge m:1 phrase using $tempdir/SLANT_alpha_beta_coefs_NLnps

		drop _merge

		*** regress relative_freq - alpha on beta

		gen y = relative_freq - alpha 
		replace y = 0 if total_freq == 0

		reg y  beta 

		regsave beta

		gen year = `yy'
		gen np = "`np'"
		
		append using $tempdir/SLANT_FINAL_AP_NLnps
	 	        save $tempdir/SLANT_FINAL_AP_NLnps, replace

		restore	
			}
}

/*Do some checks*/
use $tempdir/SLANT_FINAL_AP_NLnps, clear
set more off
order year np, first
sort year np

duplicates report
tab year, m

count if coef == 0
count if stderr == 0
count if r2 == .

replace coef = . if r2 == .
replace stderr = . if r2 == .

save, replace

/*Merge back to a newspaper dataset in order to get the AP intensity variable*/
use "$datadir/NL_processed_np/NL_processed_np_allyears.dta", clear
set more off

capt drop un_np
by npname1 year, sort: gen un_np = _n == 1
tab un_np, m
keep if un_np == 1

order year npname1, first
sort year npname1

keep year npname1 source
save "$datadir/NL_APintensity_per_year.dta", replace

/*Do the merge*/
use $tempdir/SLANT_FINAL_AP_NLnps, clear
set more off
rename np npname1
merge 1:1 year npname1 using "$datadir/NL_APintensity_per_year.dta"

li if _merge == 2 /*The Pittsburg Morning Sun (Pittsburg, Kansas) in 2013 is the only unmatched from using.*/

drop _merge

save, replace

/* Exercise 1: Plot these coefficients either as year aggregates or as time series.
/* Exercise 2: Repeat this exercise but excluding phrases containing the word 'illegal' from the list of top phrases. Compare results. 
