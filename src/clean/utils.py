import os
import numpy as np
import pandas as pd 
import matplotlib.pyplot as plt
from tqdm import tqdm
from tabulate import tabulate
import re 
import statsmodels.api as sm
from scipy.interpolate import interp1d
import time
import subprocess
from statsmodels.stats.weightstats import DescrStatsW

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


def weighted_quantile(values, weights, quantiles):
    sorter = np.argsort(values)
    values = values[sorter]
    weights = weights[sorter]
    cumulative_weights = np.cumsum(weights) - 0.5 * weights
    cumulative_weights /= cumulative_weights[-1]
    
    quantile_values = np.interp(quantiles, cumulative_weights, values)
    return quantile_values

def get_percentile_group(df, col='networth1983', weight='weight', quantiles=np.linspace(0, 1, 100), quantile_labels=np.arange(100)):
    quantile_values = weighted_quantile(df[col].to_numpy(), df[weight].to_numpy(), quantiles)
    indices = np.searchsorted(quantile_values, df[col], side='left')
    result = quantile_labels[indices]
    return result

def load_data(file_name, folder='clean'):
	file_path = os.path.join(data_folder, folder, file_name)
	if file_name.endswith('.csv'):
		return pd.read_csv(file_path)
	elif file_name.endswith('.dta'):
		return pd.read_stata(file_path)
	else:
		return pd.DataFrame()

def save_data(df, file_name, folder='clean'):
	file_path = os.path.join(data_folder, folder, file_name)
	if file_name.endswith('.csv'):
		df.to_csv(file_path, index=False)
	elif file_name.endswith('.dta'):
		df.to_stata(file_path, write_index=False)
	else:
		print('Could not save. Unknown file type.')

def weighted_sum_collapse(df, group, variables, weight):
	df = df[group + variables + [weight]] 
	
	for var in variables:
		df[f'{var}_w'] = df[var] * df[weight]

	# Collapse by percentile groups
	df = df.groupby(group, observed=True)[[f'{var}_w' for var in variables]].sum().reset_index()
	df = df.rename(columns={f'{var}_w':var for var in variables})
	return df

def get_percentiles(df, field='poinc_ptile', bins=[0, 90, 99, 100], labels=[90, 9, 1]):
	percentiles = pd.cut(df[field], bins=bins, labels=labels, right=True).astype(int)
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

def load_national_income():
	natinc = load_nipa_tables()[['Year','NationalInc']]
	return natinc

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

	nipa['NetExGoodsAndServicesROW'] = -nipa['NetExGoodsAndServices'] + nipa['ROW']
	nipa['NetInvDomestic'] = nipa['GrossInvDomestic'] - nipa['ConsFixedCap']

	nipa['GrossSavingBus'] = nipa['SavingBus'] + nipa['ConsFixedCapDomBus']
	nipa['GrossSavingPers'] = nipa['SavingPers'] + nipa['ConsFixedCapHouseholdsAndInst']

	for col in nipa.columns[1:]:
		nipa[f'{col}2NI'] = nipa[col]/nipa['NationalInc']

	return nipa

def sum_with_nan(series):
    if series.isnull().any():
        return np.nan
    else:
        return series.sum()

def weighted_mean(df, value_col, weight_col):
    DS = DescrStatsW(df[value_col], weights=df[weight_col])
    return DS.mean

def weighted_median(df, value_col, weight_col):
    DS = DescrStatsW(df[value_col], weights=df[weight_col])
    return DS.quantile(0.5)[0.5]
