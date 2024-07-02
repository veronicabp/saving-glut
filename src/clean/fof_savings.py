import sys
sys.path.append('')
from utils import *

def construct_new_series(fof, mappings):
	'''
	Function to construct a new FOF varible based on two other existing variables

	fof (pd.DataFrame)		: DataFrame with Flow of Funds data
	mappings (pd.DataFrame)	: DataFrame with new variables to be constructed
	'''
	# Construct series when they do not exist 
	for series in mappings.SERIES_NAME.unique():
		if '-' in series:
			first = series.split('-')[0]
			second = series.split('-')[1]

			new_rows = fof[fof.SERIES_NAME.isin([first, second])].copy()
			new_rows.loc[new_rows.SERIES_NAME==second, 'Amount'] *= -1
			new_rows['SERIES_NAME'] = series 
			new_rows['Description'] = list(mappings[mappings.SERIES_NAME==series].Description)[0]
			new_rows = new_rows.groupby(['SERIES_NAME','Year', 'Description'])['Amount'].sum().reset_index()

			fof = pd.concat([fof, new_rows])
	fof.sort_values(by=['SERIES_NAME','Year'], inplace=True)
	return fof

def get_mufu_shares(df):
	'''
	Function to allocate mutual fund wealth to the different types of mutual funds (equity, bonds, and municipal bonds)

	df (pd.DataFrame)	: Flow of funds data
	'''
	# Set missing as nan (which are recorded as zeros)
	df.replace(0, np.nan, inplace=True)

	# Add new calculated columns
	df['Equity'] = (df['LM654091600.A'] + df['LM654092603.A']) / (df['LM654090000.A'] - df['LM654091403.A'])
	df['Bond'] = (df['LM654091303.A'] + df['LM654091203.A'] - df['LM653062003.A']) / (df['LM654090000.A'] - df['LM654091403.A'])
	df['Municipal'] = df['LM653062003.A'] / (df['LM654090000.A'] - df['LM654091403.A'])

	# Normalize to sum to 1
	total_sh = df['Equity'] + df['Bond'] + df['Municipal']
	df['Equity'] /= total_sh
	df['Bond'] /= total_sh
	df['Municipal'] /= total_sh

	# Interpolate in missing years
	df['temp'] = df['LM653064100.A']/df['LM654090000.A']

	# Filter out rows where either 'Equity' or 'temp' is NaN
	df_for_interp = df[df[['Equity', 'temp']].notna().all(axis=1)]

	# Sort data by 'temp' if not already sorted; important for interpolation
	df_for_interp = df_for_interp.sort_values('temp')

	# Create interpolation function
	interp_func = interp1d(df_for_interp['temp'], df_for_interp['Equity'], kind='linear', fill_value='extrapolate')

	# Apply the interpolation function to the full range of 'temp' in original DataFrame
	df['Equity_ipol'] = interp_func(df['temp'])

	# Replace original column with interpolated values where original is missing
	df.loc[df['Equity'].isnull(), 'Equity'] = df['Equity_ipol']

	df['temp2'] = (df['Bond'] / (df['Municipal'] + df['Bond'])).mean()
	# Conditional replacements
	df.loc[df['Bond'].isnull(), 'Bond'] = (1 - df['Equity']) * df['temp2']

	# Update 'Municipal' based on new 'Bond'
	df['Municipal'] = 1 - df['Bond'] - df['Equity']

	df = df[['Year', 'Equity', 'Bond', 'Municipal']]
	return df

def get_mmf_shares(df):
	'''
	Function to allocate money markey fund wealth to the different types

	df (pd.DataFrame)	: Flow of funds data
	'''
	df['Municipal'] = df['FL633062000.A']/df['FL634090005.A']
	df['Municipal'] = df['Municipal'].fillna(0)
	df['Other'] = 1 - df['Municipal']

	return df[['Year', 'Municipal', 'Other']]

def get_pension_shares(df):
	'''
	Function to allocate pension wealth to the different types

	df (pd.DataFrame)	: Flow of funds data
	'''
	mufu = get_mufu_shares(df)
	mufu = mufu.rename(columns={col: f'{col} MUFU' for col in mufu.columns if col!='Year'})
	df = df.merge(mufu, on='Year')

	df['Equity'] = (df['LM593064105.A'] + df['Equity MUFU']*df['LM593064205.A'])/df['FL594090005.A']
	df['Fixed'] = 1 - df['Equity']

	return df[['Year', 'Equity', 'Fixed']]

def get_life_insurance_shares(df):
	'''
	Function to allocate life insurance wealth to the different types

	df (pd.DataFrame)	: Flow of funds data
	'''
	mufu = get_mufu_shares(df)
	mufu = mufu.rename(columns={col: f'{col} MUFU' for col in mufu.columns if col!='Year'})
	df = df.merge(mufu, on='Year')

	df['Equity'] = (df['LM543064105.A'] + df['Equity MUFU']*df['LM543064205.A'])/df['FL544090005.A']
	df['Fixed'] = 1 - df['Equity']

	return df[['Year', 'Equity', 'Fixed']]

def get_ira_asset_shares(df):
	'''
	Function to allocate IRA wealth to the different types

	df (pd.DataFrame)	: Flow of funds data
	'''
	mufu = get_mufu_shares(df)
	mufu = mufu.rename(columns={col: f'{col} MUFU' for col in mufu.columns if col!='Year'})
	df = df.merge(mufu, on='Year')

	df['Fixed'] = (df['FL573020033.A'] + df['FL573030033.A'] + df['FL573034055.A'] + df['LM573061133.A'] + df['FL573061733.A'] + df['FL573063033.A'] + df['FL573065033.A'] + df['LM573064255.A'] * (df['Bond MUFU'] + df['Municipal MUFU'])) / (df['FL573020033.A'] + df['FL573030033.A'] + df['FL573034055.A'] + df['LM573061133.A'] + df['FL573061733.A'] + df['FL573063033.A'] + df['FL573065033.A'] + df['LM573064133.A'] + df['LM573064255.A'])
	df['Equity'] = (df['LM573064133.A'] + df['LM573064255.A'] * df['Equity MUFU']) / (df['FL573020033.A'] + df['FL573030033.A'] + df['FL573034055.A'] + df['LM573061133.A'] + df['FL573061733.A'] + df['FL573063033.A'] + df['FL573065033.A'] + df['LM573064133.A'] + df['LM573064255.A'])

	return df[['Year', 'Equity', 'Fixed']]

def get_ira_liab_shares(df):
	'''
	Function to allocate IRA liabilities to the different types

	df (pd.DataFrame)	: Flow of funds data
	'''
	IRA_dict = {
		'FL573020033.A':'Checkable Deposits And Currency',
		'FL573030033.A':'Time And Savings Deposits',
		'FL573034055.A':'Money Market Fund Shares',
		'FL573061733.A':'Agency- and GSE-Backed Securities',
		'FL573063033.A':'Corporate And Foreign Bonds',
		'FL573065033.A':'Home Mortgages',
		'FL573061133.A':'Treasury Securities',
		'LM573064133.A':'Corporate Equities',
		'LM573064255.A':'Mutual Fund Shares'
	}

	# Split mutual fund liabilities
	mufu = get_mufu_shares(df)
	mufu_cols = [col for col in mufu.columns if col!='Year']

	df = df[['Year']+list(IRA_dict.keys())]
	df = df.rename(columns=IRA_dict)
	df = df.merge(mufu, on='Year')

	for col in mufu_cols:
		df[f'Mutual Fund Shares; {col}'] = df['Mutual Fund Shares'] * df[col]
		df = df.drop(columns=col)
	df = df.drop(columns='Mutual Fund Shares')

	df['Total'] = df[[col for col in df.columns if col!='Year']].sum(axis=1)
	for col in df.columns:
		if col=='Year':
			continue
		df[col] = df[col]/df['Total']
	df = df.drop(columns='Total')
	return df


def get_subcategory_shares(fof):
	'''
	Function to split asset classes with multiple subcategories into their respective parts

	fof (pd.DataFrame)	: Flow of funds data
	'''
	fof_pivot = fof.pivot(index='Year', columns='SERIES_NAME', values='Amount').reset_index()
	dfs = []
	funcs = [get_mufu_shares,get_mmf_shares,get_pension_shares,get_life_insurance_shares,get_ira_asset_shares,get_ira_liab_shares]
	for i, asset in enumerate(['Mutual Fund Shares', 'Money Market Fund Shares', 'Pension Entitlements', 'Life Insurance Reserves', 'IRA', 'IRA Liabs']):
		new_data = funcs[i](fof_pivot)
		new_data = pd.melt(new_data, id_vars=['Year'], value_vars=[col for col in new_data.columns if col!='Year'], var_name='Subcategory', value_name='Subcategory Share')
		
		# Mark IRA liabilities as liabilities, all other as assets
		if asset=='IRA Liabs':
			new_data['Description'] = asset.replace(' Liabs', '')
			new_data['Is Asset'] = 0

		else:
			new_data['Description'] = asset
			new_data['Is Asset'] = 1

		dfs.append(new_data)

	return pd.concat(dfs)


def get_inflation(percentiles=[90,99,100], percentile_labels=[90,9,1]):
	'''
	Function to load known asset price inflation for each asset type

	percentiles (list[int])			: list of percentile bins 
	percentile_labels (list[int])	: list of percentile bin names 
	'''
	# Housing price gain
	JST = pd.read_stata(os.path.join(raw_folder, 'JST', 'JSTdatasetR6.dta'))
	JST = JST[JST.country=='USA'][['year', 'housing_capgain']].rename(columns={'year':'Year', 'housing_capgain':'Asset Inflation Rate'})
	JST['Inflation Category'] = 'JST_housing_capgain'

	# Expand to include every percentile
	JST_list = []
	for p in percentile_labels:
		temp = JST.copy()
		temp['Percentile'] = p 
		JST_list.append(temp)
	JST = pd.concat(JST_list)

	# Debt write downs
	callreport = pd.read_stata(os.path.join(raw_folder, 'callreport', 'debtwritedown.dta'))

	callreport_list = []
	for cat in ['cdebt','mdebt']:
		for i, p in enumerate(percentile_labels):
			if percentiles[i]>90:
				pgroup=10
			else:
				pgroup=90
			temp = callreport[['year',f'ZIP_{cat}_wd{pgroup}']].rename(columns={'year':'Year', f'ZIP_{cat}_wd{pgroup}':'Asset Inflation Rate'})
			temp['Inflation Category'] = f'ZIP_{cat}'
			temp['Percentile'] = p 
			callreport_list.append(temp)
	callreport = pd.concat(callreport_list)
	callreport['Asset Inflation Rate'] *= -1

	years = sorted(JST.Year.unique())
	zeros = pd.DataFrame({'Year':years*len(percentile_labels), 'Inflation Category':['ZERO']*len(years)*len(percentile_labels), 'Percentile':[p for p in percentile_labels for _ in years], 'Asset Inflation Rate':[0]*len(years)*len(percentile_labels)})

	return pd.concat([JST, callreport, zeros])

def load_dina(mappings, dinafile='dina_hwealsort.csv'):
	'''
	Function to load dina data and prepare it for merge

	mappings (pd.DataFrame)	: data with relevant variables to keep and metadata on how to match to FOF
	dinafile (str)			: name of DINA file to use
	'''
	# Load dina and reshape long
	dina = pd.read_csv(os.path.join(working_folder, dinafile))
	dina_categories = list(mappings['DINA Category'].unique())
	dina = dina[['Year','Percentile']+dina_categories]
	dina['Year'] = dina['Year'].astype(int)
	dina = pd.melt(dina, id_vars=['Year', 'Percentile'], value_vars=dina_categories, var_name='DINA Category', value_name='Percentile Share')

	# Get missing combinations
	years = dina['Year'].unique()
	percentiles = dina['Percentile'].unique()
	categories = dina['DINA Category'].unique()

	# Create a MultiIndex with all possible combinations
	multi_index = pd.MultiIndex.from_product([years, percentiles, categories], names=['Year', 'Percentile', 'DINA Category'])

	# Reindex the original dataframe to the MultiIndex
	dina.set_index(['Year', 'Percentile', 'DINA Category'], inplace=True)
	dina = dina.reindex(multi_index).reset_index()

	return dina

def load_data_sets():
	'''
	Function to load flow of funds data and metadata
	'''
	# Flow of funds
	fof = get_fof()

	# Metadata for FOF series
	mappings = pd.read_csv(os.path.join(raw_folder, 'personal', 'fof_distributional_relations.csv'))

	# Subdistribution of series
	subcategory_shares = get_subcategory_shares(fof)

	return fof, mappings, subcategory_shares

def calculate_savings_inflation(df, percentile_labels=[90,9,1]):
	'''
	Function to calculate savings by percentile and inflation of the residual asset class such that total savings lines up with national accounts

	df (pd.DataFrame)				: main merged data
	percentile_labels (list[int])	: percentile bin names
	'''

	# First, calculate saving and valuation gains for those where inflation is known
	df.loc[~df['Asset Inflation Rate'].isna(), 'Saving'] = df['Amount'] - (1+df['Asset Inflation Rate'])*df['L_Amount']

	# Collapse
	df['Missing Inflation'] = df['Inflation Category'] == 'OTH'
	df = df.groupby(['Percentile', 'Missing Inflation', 'Year'])[['Amount','L_Amount','Saving']].agg(sum_with_nan).reset_index()

	# Reshape Wide
	df = pd.pivot_table(df, values=['Amount','L_Amount','Saving'], index=['Year'], columns=['Missing Inflation', 'Percentile']).reset_index()
	df.set_index('Year', inplace=True)

	# Choose Pi_Equity such that total savings sums to national accounts
	nipa = load_nipa_tables().set_index('Year')
	nipa['NetPrivSav'] = nipa['SavingBus'] + nipa['SavingPers']
	df['NetPrivSav'] = nipa['NetPrivSav']*1000
	df['NationalInc'] = nipa['NationalInc']*1000

	df['resid_savings'] = df['NetPrivSav'] - df['Saving'][False].sum(axis=1)
	df['inflation_oth'] = ((df['Amount'][True].sum(axis=1) - (df['resid_savings']) )/df['L_Amount'][True].sum(axis=1)) - 1

	# Store inflation 
	inflation_oth = df['inflation_oth'].reset_index()

	new_cols = ['FOFsaving','d_Wealth','Valuation']
	for p in percentile_labels:
		df[f'FOFsaving{p}'] = (df['Saving'][False][p] + df['Amount'][True][p] - (1+df['inflation_oth'])*df['L_Amount'][True][p])

		# Also calculate valuation gains
		df[f'd_Wealth{p}'] = ((df['Amount'][True][p]+df['Amount'][False][p]) - (df['L_Amount'][True][p]+df['L_Amount'][False][p]))
		df[f'Valuation{p}'] = df[f'd_Wealth{p}']-df[f'FOFsaving{p}']

		for col in new_cols:
			df[f'{col}2NI{p}'] = df[f'{col}{p}']/df['NationalInc']

	df.columns = df.columns.get_level_values(0)
	new_cols = [f'{col}{tag}' for col in new_cols for tag in ['', '2NI']]
	df =  df[[f'{col}{p}' for col in new_cols for p in percentile_labels]]
	df = df.reset_index()

	df = pd.wide_to_long(df, stubnames=new_cols, i=['Year'], j='Percentile').reset_index()

	return df, inflation_oth

def calculate_savings_by_percentile(fof, mappings, subcategory_shares, dinafile='dina_hwealsort.csv', tag='', percentiles=[90,99,100], percentile_labels=[90,9,1]):
	'''
	Main fuction to calculate savings for each percentile group based on change in wealth and asset inflation in each period

	fof (pd.DataFrame)					: Flow of funds data
	mappings (pd.DataFrame)				: Metadata to match FOF to DINA and subcategory data
	subcategory_shares (pd.DataFrame)	: Data on how FOF variables should be disaggregated into their components
	dinafile (str)						: File containing DINA data
	tag (str)							: Identifier for this particular run
	percentiles (list)					: Percentile bins by which to group
	percentile_labels (list)			: Percentile bin names
	'''

	dina = load_dina(mappings, dinafile=dinafile)
	inflation = get_inflation(percentiles=percentiles, percentile_labels=percentile_labels)

	# Merge and clean datasets
	df = construct_new_series(fof, mappings)
	df = df[df.Year!=2019] # Remove 2019, don't have debt writedown data 
	df = df.drop(columns='Description')

	df = df.merge(mappings, on='SERIES_NAME', how='inner')

	df = df.merge(subcategory_shares, on=['Description', 'Subcategory','Is Asset','Year'], how='left')
	df.loc[df['Subcategory Share'].isna(), 'Subcategory Share'] = 1

	df = df.merge(dina, on=['DINA Category','Year'])

	# Calculate share of each asset owned by each group
	df.rename(columns={'Amount':'Total Amount'}, inplace=True)
	df['Amount'] = df['Total Amount'] * df['Subcategory Share'] * df['Percentile Share']

	# For liabilities, take inverse 
	df.loc[df['Is Asset']==0, 'Amount'] *= -1

	df = df.merge(inflation, on=['Inflation Category', 'Year', 'Percentile'], how='left')

	# Generate unique name for each asset
	df['Asset Name'] = ''
	df.loc[df.Subcategory.isna(), 'Asset Name'] = df['Description']
	df.loc[~df.Subcategory.isna(), 'Asset Name'] = df['Description'] + '; ' + df['Subcategory']

	df = df.sort_values(by=['Asset Name','Is Asset','Percentile', 'Year'])
	df['L_Amount'] = df.groupby(['Asset Name', 'Is Asset', 'Percentile'])['Amount'].shift()
	df = df[df.Year>=1963]

	# Calculate savings + residual inflation:
	tot_sav, inflation_oth = calculate_savings_inflation(df.copy(), percentile_labels=percentile_labels)
	tot_sav.to_csv(os.path.join(clean_folder, f'fof_savings{tag}.csv'), index=False)

	# Calculate savings for each asset
	df = df.merge(inflation_oth, on='Year')
	df = df.merge(load_nipa_tables()[['Year','NationalInc']], on='Year')
	df['NationalInc'] = df['NationalInc'] * 1000

	df.loc[df['Inflation Category']=='OTH', 'Asset Inflation Rate'] = df['inflation_oth']
	df['FOFsaving'] = (df['Amount'] - (1+df['Asset Inflation Rate'])*df['L_Amount'])
	df['FOFsaving2NI'] = df['FOFsaving']/df['NationalInc']

	# Categorize into groups
	df.loc[df['Is Asset']==0, 'Asset Type'] = 'Liability'
	df.loc[df['Asset Name']=='Real Estate', 'Asset Type'] = 'Real Estate'
	df.loc[df['Asset Type'].isna(), 'Asset Type'] = 'Financial Asset'

	df.to_csv(os.path.join(clean_folder, f'fof_savings_by_asset{tag}.csv'), index=False)

def main():

	# Load data sets
	fof, mappings, subcategory_shares = load_data_sets()
	save_data(subcategory_shares, 'subcategory_shares.csv')

	# Main results 
	calculate_savings_by_percentile(fof, mappings, subcategory_shares)

	# For each percentile group
	calculate_savings_by_percentile(fof, mappings, subcategory_shares, dinafile='dina_hwealsort_100.csv', tag='_p100', percentiles=np.linspace(1,100,100), percentile_labels=np.arange(100)+1)

	# More granular split
	quantiles = np.round(np.concatenate((np.linspace(1,99,99),np.linspace(99.2,100,5))),2)
	calculate_savings_by_percentile(fof, mappings, subcategory_shares, dinafile='dina_hwealsort_granular.csv', tag='_granular', percentiles=quantiles, percentile_labels=quantiles)


if __name__=="__main__":
	main()
