import os
import numpy as np
import pandas as pd 
import matplotlib.pyplot as plt
from tqdm import tqdm
from tabulate import tabulate
import re 
import statsmodels.api as sm
from scipy.interpolate import interp1d

# Deal with warnings
import warnings
from pandas.errors import PerformanceWarning, SettingWithCopyWarning
warnings.filterwarnings('ignore', category=PerformanceWarning)
warnings.filterwarnings('ignore', category=SettingWithCopyWarning)
pd.set_option('future.no_silent_downcasting', True)

# Paths 
dropbox = "/Users/veronicabackerperal/Dropbox (Princeton)"
project_folder = os.path.join(dropbox, 'Princeton', 'saving-glut')
code_folder = os.path.join(project_folder, 'code')
data_folder = os.path.join(project_folder, 'data')
raw_folder = os.path.join(data_folder, 'raw')
clean_folder = os.path.join(data_folder, 'clean')
working_folder = os.path.join(data_folder, 'working')

overleaf = os.path.join(dropbox, 'Apps', 'Overleaf', 'Saving Glut of the Rich') 
figures_folder= os.path.join(overleaf, 'Figures')
tables_folder= os.path.join(overleaf, 'Tables')

dina_relations = {
	'sztaxbondsh':[
		'Agency- and GSE-Backed Securities', 
		'Corporate and Foreign Bonds', 
		'Time and Savings Deposits', 
		'Money Market Fund Shares',
		'Other Loans and Advances', 
		'Identified Miscellaneous Financial Claims - Part I',
		'Identified Miscellaneous Financial Claims - Part II',
		'Mutual Fund Shares (Bond)',
		'Treasury Securities',
		# Add all uncategorized fields to this category:
		'Multifamily Residential Mortgages',
		'Commercial Mortgages',
		'Home Mortgages',
		'Farm Mortgages',
		'U.S. Official Reserve Assets and SDR Allocations',
		'Municipal Securities',
		'Federal Funds and Security Repurchase Agreements',
		'U.S. Deposits in Foreign Countries',
		'Consumer Credit'
		],
	'szcurrencysh':['Checkable Deposits and Currency'],
	'szequitysh':[
		'Corporate Equities', 
		'Mutual Fund Shares (Equity)'
		],
	'szbussh':["Proprietors' Equity in Noncorporate Business"],
	'szpenssh':[
		'Pension Entitlements', 
		'Life Insurance Reserves'
		],
	'szmunish':['Mutual Fund Shares (Municipal)'],
	### Real estate
	'szownerhomesh':['Real Estate'],
	### Liabilities
	'szownermortsh':['Home Mortgages (Liabilities)'],
	'sznonmortsh':['Consumer Credit (Liabilities)','Depository Institution Loans (Liabilities)','Other Loans (Liabilities)','Life Insurance (Liabilities)']
}

dfa_relations = {
	'Checkable deposits and currency - dfa':['Checkable Deposits and Currency'],
	'Corporate and foreign bonds - dfa': ['Corporate and Foreign Bonds'],
	'Corporate equities and mutual fund shares - dfa': ['Corporate Equities', 'Mutual Fund Shares'],
	'Debt securities - dfa': ['Agency- and GSE-Backed Securities'],
	'Equity in noncorporate business - dfa': ["Proprietors' Equity in Noncorporate Business"],
	'Mortgages - dfa': ['Home Mortgages'],
	'Life insurance reserves - dfa': ['Life Insurance Reserves'],
	'Miscellaneous assets - dfa': ['Identified Miscellaneous Financial Claims - Part I', 'Identified Miscellaneous Financial Claims - Part II'],
	'Money market fund shares - dfa': ['Money Market Fund Shares'],
	'Other loans and advances (Liabilities) - dfa': ['Other Loans and Advances'],
	'Pension entitlements - dfa': ['Pension Entitlements'],
	'Time deposits and short-term investments - dfa': ['Time and Savings Deposits']
}

def weighted_sum_collapse(df, group, variables, weight):
    df = df[group + variables + [weight]] 
    
    for var in variables:
        df[f'{var}_w'] = df[var] * df[weight]

    # Collapse by percentile groups
    df = df.groupby(group, observed=True)[[f'{var}_w' for var in variables]].sum().reset_index()
    df = df.rename(columns={f'{var}_w':var for var in variables})
    return df

def get_percentiles(df, field='poinc_ptile'):
	percentiles = pd.cut(df[field], 
					  bins=[0, 90, 99, 100], 
					  labels=[90, 9, 1],
					  right=True).astype(int)
	return percentiles

def get_fof():
    df = pd.read_csv(os.path.join(raw_folder, 'fof', 'fof.csv'))
    
    # Keep annual data 
    df = df[df.FREQ==203]

    df['TIME_PERIOD'] = pd.to_datetime(df['TIME_PERIOD'])
    df['Year'] = df.TIME_PERIOD.dt.year

    df.rename(columns={'OBS_VALUE':'Amount'}, inplace=True)
    
    df = df[['SERIES_NAME','Year','Description','Amount']]
    
    # Expand to fill missing values with 0s 
    multi_index = pd.MultiIndex.from_product([df['SERIES_NAME'].unique(), df['Year'].unique()], names=['SERIES_NAME', 'Year'])
    df = df.set_index(['SERIES_NAME', 'Year']).reindex(multi_index)

    # Fill missing 'amount' values with 0
    df['Amount'] = df['Amount'].fillna(0).astype(int)
    df['Description'] = df.groupby('SERIES_NAME')['Description'].transform(lambda x: x.ffill().bfill())
    
    df = df.reset_index()
    df.sort_values(by=['SERIES_NAME','Year'], inplace=True)

    return df

def get_mufu_split():
	full_df = pd.read_csv(os.path.join(raw_folder, 'fof', 'fof.csv'))
	df = full_df[(full_df.FREQ==203)&(full_df.SERIES_PREFIX=='LM')].copy()

	df['TIME_PERIOD'] = pd.to_datetime(df['TIME_PERIOD'])
	df['Year'] = df.TIME_PERIOD.dt.year
	df['SERIES_NAME'] = df['SERIES_NAME'].str.replace('.','').str.lower()

	df = df[['SERIES_NAME','Year','OBS_VALUE']]
	df = df.pivot(index='Year', columns='SERIES_NAME', values='OBS_VALUE').reset_index()

	# Add new calculated columns
	df['a_mufu_equ_sh'] = (df['lm654091600a'] + df['lm654092603a']) / (df['lm654090000a'] - df['lm654091403a'])
	df['a_mufu_bnd_sh'] = (df['lm654091303a'] + df['lm654091203a'] - df['lm653062003a']) / (df['lm654090000a'] - df['lm654091403a'])
	df['a_mufu_mun_sh'] = df['lm653062003a'] / (df['lm654090000a'] - df['lm654091403a'])

	# Normalize to sum to 1
	total_sh = df['a_mufu_equ_sh'] + df['a_mufu_bnd_sh'] + df['a_mufu_mun_sh']
	df['a_mufu_equ_sh'] /= total_sh
	df['a_mufu_bnd_sh'] /= total_sh
	df['a_mufu_mun_sh'] /= total_sh

	# Interpolate in missing years
	df['temp'] = df['lm653064100a']/df['lm654090000a']

	# Filter out rows where either 'a_mufu_equ_sh' or 'temp' is NaN
	df_for_interp = df[df[['a_mufu_equ_sh', 'temp']].notna().all(axis=1)]

	# Sort data by 'temp' if not already sorted; important for interpolation
	df_for_interp = df_for_interp.sort_values('temp')

	# Create interpolation function
	interp_func = interp1d(df_for_interp['temp'], df_for_interp['a_mufu_equ_sh'], kind='linear', fill_value='extrapolate')

	# Apply the interpolation function to the full range of 'temp' in original DataFrame
	df['a_mufu_equ_sh_ipol'] = interp_func(df['temp'])

	# Replace original column with interpolated values where original is missing
	df.loc[df['a_mufu_equ_sh'].isnull(), 'a_mufu_equ_sh'] = df['a_mufu_equ_sh_ipol']

	df['temp2'] = (df['a_mufu_bnd_sh'] / (df['a_mufu_mun_sh'] + df['a_mufu_bnd_sh'])).mean()
	# Conditional replacements
	df.loc[df['a_mufu_bnd_sh'].isnull(), 'a_mufu_bnd_sh'] = (1 - df['a_mufu_equ_sh']) * df['temp2']

	# Update 'a_mufu_mun_sh' based on new 'a_mufu_bnd_sh'
	df['a_mufu_mun_sh'] = 1 - df['a_mufu_bnd_sh'] - df['a_mufu_equ_sh']

	df = df[['Year', 'a_mufu_equ_sh', 'a_mufu_bnd_sh', 'a_mufu_mun_sh']]

	return df, {'Equity':'equ', 'Bond':'bnd', 'Municipal':'mun'}

def load_nipa_table(file_name):
    # Read from csv
    df = pd.read_csv(file_name, skiprows=3, index_col=2).drop(columns=['Line','Unnamed: 1'])
    df = df[~df.index.isna()]
    # Pivot table so fields are columns
    df = pd.melt(df.reset_index(names='field'), id_vars='field', value_vars=df.columns, var_name='Year', value_name='value')
    df['value'] = pd.to_numeric(df['value'], errors='coerce')
    df = pd.pivot_table(df, values='value', index='Year', columns=['field']).reset_index()
    
    df.rename(columns={col:col.strip() for col in df.columns}, inplace=True)
    return df 

def load_nipa_tables():
    file_names = [os.path.join(raw_folder,'nipa',file) for file in os.listdir(os.path.join(raw_folder,'nipa')) if file.endswith('.csv')]
    for i, file_name in enumerate(file_names):
        if i==0:
            nipa = load_nipa_table(file_name)
        else:
            nipa = nipa.merge(load_nipa_table(file_name), on='Year')
    
    nipa['Year'] = nipa['Year'].astype(int)
    
    # Create derived variables
    nipa.loc[nipa['InflowTransfersFromROW'].isna(), 'InflowTransfersFromROW'] = 0
    nipa['ROW'] = nipa['InflowIncomeReceiptsFromROW'] + nipa['InflowTransfersFromROW'] - nipa['OutflowIncPaymentsToROW'] - nipa['OutflowTransferToROW']

    nipa['NationalInc'] = nipa['GDP'] + nipa['ROW'] + nipa['StatisticalDiscrepancy'] - nipa['ConsFixedCap']

    nipa['GovDeficit'] = (nipa['GovConsEx'] + nipa['GovIntPayments'] + nipa['Subsidies4'] + nipa['GovTransPayments']
                        - nipa['GovCurrentTaxReceipts'] - nipa['GovContribToSSI'] - nipa['GovAssetInc']
                        - nipa['GovCurrTransferReceipts'] - nipa['GovCurrSurplusEnterprise'])
    nipa.loc[nipa['GovDeficit'].isna(), 'GovDeficit'] = (nipa['GovConsEx'] + nipa['GovIntPayments'] + nipa['Subsidies4'] 
                                                    + nipa['GovTransPayments'] - nipa['GovCurrentTaxReceipts']
                                                    - nipa['GovContribToSSI'] - nipa['GovAssetInc']
                                                    - nipa['GovCurrTransferReceipts'])
    nipa['GovSaving'] = -1*nipa['GovDeficit']
    
    return nipa
