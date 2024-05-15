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
		'Trade Credit',
		'Multifamily Residential Mortgages',
		'Direct Investment',
		'Open Market Paper',
		'Taxes Payable by Businesses',
		'Net Interbank Transactions',
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
	'szmunish':['Mutual Fund Shares (Municipal)']
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