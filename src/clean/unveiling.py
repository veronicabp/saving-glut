from utils import * 

def load_national_income():
	file = os.path.join(raw_folder, 'fred', 'MKTGNIUSA646NWDB.csv')
	natincome = pd.read_csv(file)
	natincome['Date'] = pd.to_datetime(natincome['DATE'])
	natincome['year'] = natincome.Date.dt.year
	natincome = natincome.rename(columns={'MKTGNIUSA646NWDB':'national_income'})
	natincome['national_income'] = (natincome.national_income/1e9)
	natincome = natincome[['year', 'national_income']]
	return natincome

def get_wealth_shares(df, wealth_data, relations_dict):
	# Merge with dina shares
	df.fillna(0, inplace=True)
	df = pd.merge(df, wealth_data, on='year')

	# Create amounts held by houeshold percentiles over time
	df['amount_held'] = 0
	for wealth_key in relations_dict:
		for ff_key in relations_dict[wealth_key]:
			df['amount_held'] += df[wealth_key] * df[ff_key]

	df = df[['primary_asset','year','percentile','amount_held','national_income']]
	df['share_held'] = df['amount_held']/df['national_income']
	return df

def get_dina_asset_shares():
	file = os.path.join(raw_folder, 'dina', 'usdina19622019.dta')
	df = pd.read_stata(file)

	df['percentile'] = pd.cut(df['wealth_ptile'], 
					  bins=[0, 90, 99, 100], 
					  labels=[90, 9, 1],
					  right=True)

	df['returns'] = np.round(df['dweght']/1e5)

	df = df.drop(columns='equity')
	df = df.rename(columns={'hwbus':'bus', 'hwpen':'pens', 'hwequ':'equity'})

	variables = ['taxbond', 'currency','equity','bus','pens','muni']
	df = df[variables + ['year','percentile', 'returns']]

	for var in variables:
		df[f'{var}_w'] = df[var] * df['returns']

	df = df.copy() # Reduce fragmentation

	# Collapse by percentile groups
	df = df.groupby(['year', 'percentile'], observed=True)[[f'{var}_w' for var in variables]].sum().reset_index()

	# Get share of total 
	for var in variables:
		df[f'sz{var}'] = df.groupby(['year'])[f'{var}_w'].transform('sum')
		df[f'sz{var}sh'] = df[f'{var}_w']/df[f'sz{var}']
		df = df.drop(columns={f'{var}_w', f'sz{var}'})

	return df

def get_mufu_split():
	full_df = pd.read_csv(os.path.join(raw_folder, 'fof', 'fof.csv'))
	df = full_df[(full_df.FREQ==203)&(full_df.SERIES_PREFIX=='LM')].copy()

	df['TIME_PERIOD'] = pd.to_datetime(df['TIME_PERIOD'])
	df['year'] = df.TIME_PERIOD.dt.year
	df['SERIES_NAME'] = df['SERIES_NAME'].str.replace('.','').str.lower()

	df = df[['SERIES_NAME','year','OBS_VALUE']]
	df = df.pivot(index='year', columns='SERIES_NAME', values='OBS_VALUE').reset_index()

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

	df = df[['year', 'a_mufu_equ_sh', 'a_mufu_bnd_sh', 'a_mufu_mun_sh']]

	return df

def map_using_dina(df):
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

	# Separate mutual fund shares
	mufu = get_mufu_split()
	df = pd.merge(df, mufu, on='year')
	mufu_types = {'Equity':'equ', 'Bond':'bnd', 'Municipal':'mun'}
	for key in mufu_types:
		df[f'Mutual Fund Shares ({key})'] = df['Mutual Fund Shares'] * df[f'a_mufu_{mufu_types[key]}_sh']

	return get_wealth_shares(df, get_dina_asset_shares(), dina_relations)

def get_unfunded_pension_wealth():
	df = pd.read_stata(os.path.join(raw_folder, 'fof', 'LQpanel_2022Q2.dta'))
	df['date'] = pd.to_datetime(df['quarter'])
	df['year'] = df.date.dt.year
	df = df[df.date.dt.quarter==4]
	
	df = df.rename(columns={'fl153050005a':'finact_pens', 'fl593073045q':'finact_pens_uf'})
	return df[['year','finact_pens','finact_pens_uf']]
	
def get_dfa_asset_shares():
    file = os.path.join(raw_folder, 'dfa', 'dfa-networth-levels-detail.csv')
    df = pd.read_csv(file)

    # Keep one entry per year
    df['year'] = df['Date'].str.slice(0,4).astype(int)
    df = df[df.Date.str.endswith('Q4')]

    # Combine bottom 90
    df['percentile'] = df['Category'].replace({'Bottom50': 90, 'Next40': 90, 'Top1':1, 'Next9':9})
    df = df.groupby(['year', 'percentile']).sum().reset_index()

    #Exclude unfunded pension wealth
    unfunded_pensions = get_unfunded_pension_wealth()
    df = df.merge(unfunded_pensions, on='year')
    df['Pensions Total'] = df.groupby(['year'])['Pension entitlements'].transform('sum')
    df['Pensions Exc. Unfund'] = df['Pensions Total'] - df['finact_pens_uf']
    df['Pension entitlements'] = df['Pension entitlements'] * df['Pensions Exc. Unfund']/df['Pensions Total']
    df = df.drop(columns=['Pensions Total','Pensions Exc. Unfund', 'finact_pens', 'finact_pens_uf', 'Date', 'Category'])

    variables = [col for col in df.columns if col not in ['year', 'percentile']]
    for var in variables:
        df[f'{var}_tot'] = df.groupby(['year'])[var].transform('sum')
        df[var] = df[var]/df[f'{var}_tot']
        df = df.drop(columns=f'{var}_tot')

    df = df.rename(columns={col:f'{col} - dfa' for col in variables})

    return df

dfa = get_dfa_asset_shares()
def map_using_dfa(df):
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

	return get_wealth_shares(df, get_dfa_asset_shares(), dfa_relations)

def map_to_wealth_percentiles(unveiled_by_instrument):

	df = pd.merge(unveiled_by_instrument, load_national_income(), on='year')

	# Reshape wide
	df = df[['primary_asset', 'final_holder', 'instrument', 'year', 'amount','national_income']].groupby(['primary_asset', 'final_holder', 'instrument', 'year','national_income']).sum()['amount'].reset_index()
	df = df.pivot_table(index=['primary_asset','final_holder','year','national_income'], columns='instrument', values='amount', aggfunc='first').reset_index()
	df = df[df.final_holder=='Households and Nonprofit Organizations']

	dina = map_using_dina(df)
	# dina = pd.DataFrame()
	dfa = map_using_dfa(df)

	return dina, dfa

def make_net(df, category='Rest of World'):
	for date in tqdm(df.Date.unique()):
		for sector in df.Holder.unique():
			issuer_series = (df.Issuer==category)&(df.Holder==sector)&(df.Date==date)
			holder_series = (df.Holder==category)&(df.Issuer==sector)&(df.Date==date) 
			
			row_liabs  = df[issuer_series].Amount.item() if len(df[issuer_series])>0 else 0
			row_assets = df[holder_series].Amount.item() if len(df[holder_series])>0 else 0

			if row_liabs > row_assets:
				to_subtract = row_assets
			else:
				to_subtract = row_liabs

			df.loc[issuer_series, 'Amount'] -= to_subtract
			df.loc[holder_series, 'Amount'] -= to_subtract
	return df

def construct_Omega(df, m=0, k=0, p=0, sectors=[], epsilon=1e-3):
	# Create M matrix
	M = np.zeros((p,p))
	for i, issuer in enumerate(sectors):
		for j, holder in enumerate(sectors):
			amt = df[(df.Issuer==issuer)&(df.Holder==holder)].pct_issued.sum()
			M[i,j] = amt
	
	# Iterate to get Omega
	delta = np.ones((p,p))
	Omega_bar = M.copy()

	count = 2
	while delta.max() > epsilon:
		delta = np.linalg.matrix_power(M, count)
		Omega_bar += delta
		count += 1
	Omega = Omega_bar[:k, k:]
	return Omega

def construct_direct_holdings(df, d1=0, d2=0, issuers=[], holders=[]):
	M = np.zeros((d1, d2))
	for i, issuer in enumerate(issuers):
		for j, holder in enumerate(holders):
			amt = df[(df.Issuer==issuer)&(df.Holder==holder)].pct_issued.sum()
			M[i,j] = amt 
			
	return M

def construct_matrices(df, primary_assets=['Households and Nonprofit Organizations', 'Federal Government', 'Nonfinancial Non-Corporate Business', 'Nonfinancial Corporate Business', 'Non-Financial Assets'], final_holders=['Households and Nonprofit Organizations', 'Rest of World', 'Federal Government', 'State and Local Governments']):
	intermediaries = list((set(df.Issuer.unique()) | set(df.Holder.unique()))-set(final_holders)) 
	sectors = intermediaries + final_holders # Sort so that final holders are at the end
	
	n = len(primary_assets)
	m = len(final_holders)
	k = len(intermediaries)
	p = len(sectors) # m+k

	Omega = construct_Omega(df[~df.Issuer.isin(final_holders)], m=m, k=k, p=p, sectors=sectors)
	D = construct_direct_holdings(df, d1=n, d2=m, issuers=primary_assets, holders=final_holders)
	W = construct_direct_holdings(df, d1=n, d2=k, issuers=primary_assets, holders=intermediaries)
	
	return Omega, D, W

def get_level(df, primary_assets=['Households and Nonprofit Organizations', 'Federal Government', 'Nonfinancial Non-Corporate Business', 'Nonfinancial Corporate Business', 'Non-Financial Assets'], final_holders=['Households and Nonprofit Organizations', 'Rest of World', 'Federal Government', 'State and Local Governments']):
	n = len(primary_assets)
	
	L = np.zeros((n, 1))
	for i, asset in enumerate(primary_assets):
		amt = df[df.Issuer==asset].Amount.sum()
		
		# For business assets, we need to subtract out the share that is backed by household or government debt
		if 'Business' in asset:
			Omega_b, D_b, W_b = construct_matrices(df, final_holders=final_holders + [asset])
			A_b = calculate_A(Omega_b, D_b, W_b)[:, -1] # Get shares of each asset that end up in business sector
			
			for j, other_asset in enumerate(primary_assets):
				if other_asset in ['Households and Nonprofit Organizations', 'Federal Government']:
					amt_oth = df[df.Issuer==other_asset].Amount.sum()
					amt -= A_b[j] * amt_oth
				
		L[i,0] = amt
		
	return L

def calculate_A(Omega, D, W):
	return np.matmul(W, Omega) + D

def unveil(df, primary_assets=[], final_holders=[]):
	dfs = []
	for date in tqdm(sorted(df.Date.unique())):
		Omega, D, W = construct_matrices(df[df.Date==date], primary_assets=primary_assets, final_holders=final_holders)
		A = calculate_A(Omega, D, W)

		# Store in a data frame
		data = {'primary_asset':[], 'final_holder':[], 'share':[], 'date':[]}
		for i, asset in enumerate(primary_assets):
			for j, holder in enumerate(final_holders):
				data['primary_asset'].append(asset)
				data['final_holder'].append(holder)
				data['share'].append(A[i,j])
				data['date'].append(date)
		new_df = pd.DataFrame(data)
		dfs.append(new_df)

	return pd.concat(dfs)

def unveil_wrapper(fwtw_matrix, primary_assets=['Households and Nonprofit Organizations', 'Federal Government', 'Nonfinancial Non-Corporate Business', 'Nonfinancial Corporate Business', 'Non-Financial Assets'], final_holders=['Households and Nonprofit Organizations', 'Rest of World', 'Federal Government', 'State and Local Governments']):
	fwtw_matrix['Date'] = pd.to_datetime(fwtw_matrix['Date'])
	fwtw_matrix['year'] = fwtw_matrix.Date.dt.year
	fwtw_matrix = fwtw_matrix[fwtw_matrix.Holder!='Instrument Discrepancies Sector'] # Remove discrepancies sector

	fwtw_matrix = fwtw_matrix.groupby(['Issuer', 'Holder', 'Instrument', 'Date']).mean()['Amount'].reset_index()
	df = fwtw_matrix.groupby(['Issuer', 'Holder', 'Date']).sum()['Amount'].reset_index()

	# Make holdings of rest of the world net
	df = make_net(df, category='Rest of World')
	intermediaries = list((set(df.Issuer.unique()) | set(df.Holder.unique()))-set(final_holders)) 

	# Create share issued
	df['total_issued'] = df.groupby(['Issuer','Date'])['Amount'].transform('sum')
	df.loc[df.total_issued==0, 'total_issued'] = 1 
	df['pct_issued'] = df.Amount/df.total_issued

	# Store levels of primary assets issued
	data = {'primary_asset':[], 'date':[], 'level':[]}
	for date in tqdm(sorted(df.Date.unique())):
		L = get_level(df[df.Date==date], primary_assets=primary_assets, final_holders=final_holders)
		for i, asset in enumerate(primary_assets):
			data['primary_asset'].append(asset)
			data['date'].append(date)
			data['level'].append(L[i,0])
			
	levels = pd.DataFrame(data)

	###############################
	# 1. Unveil in aggregate 
	###############################
	output = unveil(df, primary_assets=primary_assets, final_holders=final_holders)
	output = pd.merge(output, levels, on=['date', 'primary_asset'])
	output['amount'] = output.level * output.share
	output['year'] = output['date'].dt.year

	##############################################################
	# 2. Unveil by instrument (for percentile distribution)
	##############################################################
	df_sector = df.copy()
	df_sector.loc[df_sector.Holder.isin(final_holders), 'Holder'] = df_sector['Issuer'] + ' - ' + df_sector['Holder']
	final_holders_sector = final_holders + [f'{a} - {b}' for a in df.Issuer.unique() for b in final_holders]

	output_sector = unveil(df_sector, primary_assets=primary_assets, final_holders=final_holders_sector)
	output_sector[['intermediary', 'final_holder']] = output_sector['final_holder'].str.split(' - ', expand=True)
	output_sector = output_sector[~output_sector.final_holder.isna()]

	# Allocate to instruments through which final holders directly hold debt
	instrument_shares = fwtw_matrix.copy()
	instrument_shares['Total'] = instrument_shares.groupby(['Issuer','Holder','Date'])['Amount'].transform('sum')
	instrument_shares['sub_share'] = instrument_shares.Amount/instrument_shares.Total
	instrument_shares.rename(columns={'Issuer':'intermediary', 'Holder':'final_holder', 'Instrument':'instrument', 'Date':'date'}, inplace=True)
	instrument_shares = instrument_shares[['intermediary', 'final_holder', 'instrument', 'date', 'sub_share']]

	output_by_instrument = pd.merge(output_sector, instrument_shares, on=['date','intermediary', 'final_holder'])
	output_by_instrument['share'] = output_by_instrument.share * output_by_instrument.sub_share
	output_by_instrument.drop(columns=['sub_share'], inplace=True)
	
	# Merge in level
	output_by_instrument = pd.merge(output_by_instrument, levels, on=['date', 'primary_asset'])
	output_by_instrument['amount'] = output_by_instrument.level * output_by_instrument.share
	output_by_instrument['year'] = output_by_instrument['date'].dt.year

	return output, output_by_instrument

def redistribute_rows(matrix, constrained, row_totals_sub, col_totals_sub):
	discrepancy = np.sum(matrix, axis=0) - col_totals_sub

	# Create proportions by which to scale rows
	proportions = np.abs(row_totals_sub.reshape(-1, 1)) * constrained
	row_sum = np.sum(proportions, axis=0)
	row_sum = np.where(row_sum == 0, 1, row_sum)
	proportions = proportions / row_sum

	adjustment = proportions * discrepancy
	matrix = matrix - adjustment
	
	return matrix, np.abs(adjustment).max()

def redistribute_cols(matrix, constrained, row_totals_sub, col_totals_sub):
	discrepancy = np.sum(matrix, axis=1) - row_totals_sub

	# Create proportions by which to scale rows
	proportions = col_totals_sub * constrained
	col_sum = np.sum(proportions, axis=1).reshape(-1, 1)
	col_sum = np.where(col_sum == 0, 1, col_sum)
	
	proportions = proportions / col_sum
	
	# Redistribute discrepancy
	adjustment = proportions * discrepancy.reshape(-1, 1)
	
	matrix = matrix - adjustment
	return matrix, np.abs(adjustment).max()

def fill_matrix(row_totals, col_totals, known, constrained, niter=1000):

	n = len(row_totals)
	m = len(col_totals)
	
	# Matrix total
	total = row_totals.sum()
	known_row_totals = np.sum(known, axis=1)
	known_col_totals = np.sum(known, axis=0)
	
	# If known values already satisfy conditions, then we're done:
	if np.allclose(row_totals, known_row_totals) or np.allclose(col_totals, known_col_totals):
		return known
	
	# Subtract known values
	row_totals_sub = row_totals - known_row_totals
	col_totals_sub = col_totals - known_col_totals
	
	# Start of with proportional matrix
	matrix = fill_proportionately(row_totals_sub, col_totals_sub)
	
	# Block constrained values
	matrix = matrix * constrained

	# Fill matrix 
	delta = 1 
	count = 0
	redistribute = 'rows'
	while delta > 0.01:
		
		if redistribute == 'rows':
			matrix, delta = redistribute_rows(matrix, constrained, row_totals_sub, col_totals_sub)
			redistribute = 'cols'
			
		elif redistribute == 'cols':
			matrix, delta = redistribute_cols(matrix, constrained, row_totals_sub, col_totals_sub)
			redistribute = 'rows'
		
		count += 1 
		if count==niter:
			# If cannot solve recursively, just return fully proportional case
			return fill_proportionately(row_totals_sub, col_totals_sub)

	# Add back in known values 
	matrix = matrix + known 
	return matrix

def fill_proportionately(row_totals, col_totals):
	n = len(row_totals)
	m = len(col_totals)
	matrix = np.array([[row_totals[i] * col_totals[j] / row_totals.sum() for j in range(m)] for i in range(n)])
	return matrix

def normalize_duplicates(sub):
	# For the data in the middle of the matrix, if a single series belongs to multiple columns, asign it proportionally
	dup = sub[(~sub.Exact)&(sub.Sign=='Positive')]
	dup = dup[dup.duplicated(subset='Series_Name')]
	for series in dup.Series_Name.unique():
		issuers_dup=sub[sub.Series_Name==series].Issuer.unique()
		holders_dup=sub[sub.Series_Name==series].Holder.unique()

		if len(issuers_dup)>1:
			tot = sub[(sub.Issuer.isin(issuers_dup))&(sub.Holder=='All Sectors')].Amount.sum()
			if tot==0:
				continue
			for issuer_dup in issuers_dup:
				sub.loc[(sub.Issuer==issuer_dup)&(sub.Series_Name==series), 'Amount'] *= sub[(sub.Issuer==issuer_dup)&(sub.Holder=='All Sectors')].Amount.sum()/tot
		if len(holders_dup)>1:
			tot = sub[(sub.Holder.isin(holders_dup))&(sub.Issuer=='All Sectors')].Amount.sum()
			if tot==0:
				continue
			for holder_dup in holders_dup:
				sub.loc[(sub.Holder==holder_dup)&(sub.Series_Name==series), 'Amount'] *= sub[(sub.Holder==holder_dup)&(sub.Issuer=='All Sectors')].Amount.sum()/tot
	return sub

def rescale_interior(sub, issuers, holders, row_totals, col_totals):
	# If the middle of the matrix sums up to more than the total, re-scale appropriately (this really only happens for ABS corporate bonds -- need to figure out why) 
	for i, issuer in enumerate(issuers):
		tot = col_totals[i]
		sum_tot = sub[(sub.Issuer==issuer)&(sub.Holder!='All Sectors')].Amount.sum()

		if abs(sum_tot) > abs(tot) and issuer!='All Sectors':
			sub.loc[(sub.Issuer==issuer)&(sub.Holder!='All Sectors'), 'Amount'] *= tot/sum_tot

	for i, holder in enumerate(holders):
		if holder in ['Instrument Discrepancies Sector']:
			continue
		tot = row_totals[i]
		sum_tot = sub[(sub.Holder==holder)&(sub.Issuer!='All Sectors')].Amount.sum()

		if abs(sum_tot) > abs(tot):
			sub.loc[(sub.Holder==holder)&(sub.Issuer!='All Sectors'), 'Amount'] *= tot/sum_tot
	return sub

def create_helper_matrices(sub, issuers, holders):
	n = len(holders)
	m = len(issuers)
		
	known = np.zeros((n,m))
	constrained = np.ones((n,m))
	for i, holder in enumerate(holders):
		for j, issuer in enumerate(issuers):
			data = sub[(sub.Holder==holder)&(sub.Issuer==issuer)]
			if len(data.index)>0:
				known[i,j] = data.Amount.sum()
				constrained[i,j] = int(not data.Exact.sum())
	return known, constrained

def create_matrix(df):
	output = df.groupby(['Issuer', 'Holder', 'Instrument','Date']).sum()['Amount'].reset_index()
	proportional_output = output.copy()
	allocated_columwise = output.copy()
	
	df = df[(~df.Series_Name.isna())]

	instruments = df.Instrument.unique()
	for instrument in instruments:
		
		sub = df[df.Instrument==instrument].copy()
		issuers = sub[sub.Issuer!='All Sectors'].Issuer.unique()
		holders = sub[sub.Holder!='All Sectors'].Holder.unique()
		
		# Get row and column totals 
		row_totals = np.array([sub[(sub.Issuer=='All Sectors')&(sub.Holder==holder)].Amount.sum() for holder in holders])
		col_totals = np.array([sub[(sub.Holder=='All Sectors')&(sub.Issuer==issuer)].Amount.sum() for issuer in issuers])
	
		if round(row_totals.sum()) != round(col_totals.sum()):     
			print("\nTOTALS DON'T MATCH!")
			
		# If totals sum to zero, just set the matrix to zero 
		if row_totals.sum()==0:
			matrix, proportional_matrix, allocated_columwise_matrix = np.zeros((len(row_totals), len(col_totals))), np.zeros((len(row_totals), len(col_totals))), np.zeros((len(row_totals), len(col_totals)))
		else:
			sub = normalize_duplicates(sub)
			sub = rescale_interior(sub, issuers, holders, row_totals, col_totals)

			# Create supplementary matrices from constraints
			known, constrained = create_helper_matrices(sub, issuers, holders)
			matrix = fill_matrix(row_totals, col_totals, known, constrained)
			proportional_matrix = fill_proportionately(row_totals, col_totals)
			allocated_columwise_matrix = fill_matrix(row_totals, col_totals, known * (constrained==0), constrained, niter=1)
			
		# Fill in data frame with values from matrix 
		for i, holder in enumerate(holders):
			for j, issuer in enumerate(issuers):
				output.loc[(output.Instrument==instrument)&(output.Issuer==issuer)&(output.Holder==holder), 'Amount'] = matrix[i, j]
				proportional_output.loc[(proportional_output.Instrument==instrument)&(proportional_output.Issuer==issuer)&(proportional_output.Holder==holder), 'Amount'] = proportional_matrix[i, j]
				allocated_columwise.loc[(allocated_columwise.Instrument==instrument)&(allocated_columwise.Issuer==issuer)&(allocated_columwise.Holder==holder), 'Amount'] = allocated_columwise_matrix[i, j]
		
	return output, proportional_output, allocated_columwise

def fill_fwtw_matrix(relationships):
	# Load values
	file = os.path.join(raw_folder, 'fof', 'fof.csv')
	full_df = pd.read_csv(file)

	full_df = full_df[['SERIES_NAME', 'SERIES_PREFIX', 'SERIES_TYPE', 'OBS_VALUE', 'TIME_PERIOD', 'Description']]
	full_df = full_df.rename(columns={'OBS_VALUE':'Amount', 'TIME_PERIOD':'Date', 'SERIES_NAME':'Series_Name', 'SERIES_PREFIX':'Prefix', 'SERIES_TYPE':'Type'})
	full_df['Amount'] = pd.to_numeric(full_df['Amount'], errors='coerce')
	full_df['Amount'] = full_df['Amount']/1000 # Units in billions of USD

	# Merge into relationships data, keeping only
	df = pd.merge(relationships, full_df, on=['Series_Name', 'Date'], how='left')
	df.loc[df.Series_Name=='0', 'Amount'] = 0
	df.loc[df.Sign=='Negative', 'Amount'] = - df.Amount

	# If liabilities are negative, add them to assets
	for i, row in tqdm(df[(df.Amount<0)&(df.Sign=='Positive')&(df.Holder!='Instrument Discrepancies Sector')].iterrows()):

		new_row = row.copy()
		new_row['Holder'] = row.Issuer
		new_row['Issuer'] = row.Holder
		new_row['Amount'] = -row.Amount
		df = pd.concat([df, pd.DataFrame([new_row.values], columns=df.columns)])

		df = df[~((df.Instrument==row.Instrument)&(df.Holder==row.Holder)&(df.Issuer==row.Issuer)&(df.Series_Name==row.Series_Name)&(df.Date==row.Date))].copy()

	# Set all instrument discrepancy values within the matrix as unknown
	df.loc[(df.Holder=='Instrument Discrepancies Sector')&(df.Issuer!='All Sectors'), 'Amount'] = np.nan

	# Create matrices
	matrices, proportional_matrices, columnwise_matrices = [], [], []
	for date in tqdm(df.Date.unique()):
		matrix, proportional_matrix, columnwise_matrix = create_matrix(df[df.Date==date])
		matrices.append(matrix)
		proportional_matrices.append(proportional_matrix)
		columnwise_matrices.append(columnwise_matrix)

	# Combine
	output = pd.concat(matrices)
	output = output[output.Amount > 0]
	output = output[(output.Issuer!='All Sectors')&(output.Holder!='All Sectors')]
	return output

def load_fwtw_relationships():

	# Store all excel sheets
	file = os.path.join(raw_folder, 'fof', 'my_fwtw_templates.xlsx')
	xls = pd.ExcelFile(file)

	dfs = []
	for i, sheet in enumerate(xls.sheet_names):
		df = pd.read_excel(file, sheet_name=sheet)
		if i in [1,2]:
			for j in range(i):
				df.columns = df.iloc[0]
				df = df.drop(df.index[0])
			
		dfs.append(df)

	# Extract numeric codes 
	sectors_codes = dfs[1].rename(columns={'Sector Code (in templates)':'Sector Code'})
	sectors_codes = sectors_codes.set_index('Sector Code')['Sector Name'].to_dict()
	sectors_codes[42] = 'Government-Sponsored Enterprises'
	instrument_codes = dfs[2].set_index('Instrument Code')['Instrument Name'].to_dict()

	# Convert excel sheet to Pandas dataframe
	data = {
		'Issuer':[],
		'Holder':[],
		'Instrument':[],
		'Series_Name':[],
		'Date':[],
		'Sign':[],
		'Exact':[]
	}
	for year in tqdm(range(1960, 2023)):
		for df in dfs[3:]:
			instrument = df.columns[0]

			for Issuer_Code in df.columns[1:]:
				Issuer = sectors_codes[int(re.sub(r'\.(a|b)', '', str(Issuer_Code)))]

				# Flag if half series
				split_issue = False
				other_half_issue = ''
				if '.a' in str(Issuer_Code):
					split_issue = True 
					other_half_issue = Issuer_Code.replace('.a', '.b')
				elif '.b' in str(Issuer_Code):
					split_issue = True 
					other_half_issue = Issuer_Code.replace('.b', '.a')

				for Holder_Code in list(df[instrument]):
					Holder = sectors_codes[int(re.sub(r'\.(a|b)', '', str(Holder_Code)))]

					# Flag if half series
					split_hold = False
					other_half_hold = ''
					if '.a' in str(Holder_Code):
						split_hold = True 
						other_half_hold = Holder_Code.replace('.a', '.b')
					elif '.b' in str(Holder_Code):
						split_hold = True 
						other_half_hold = Holder_Code.replace('.b', '.a')

					# Get contents for this issuer/holder
					cell = str(df[df[instrument]==Holder_Code][Issuer_Code].item())

					# Extract date from cell
					match = re.search(r'\|\s?\d{4}q[1-4]', cell)
					if match:
						match_year = int(re.search(r'\d{4}', match.group()).group())
						if year < match_year:
							cell = 'nan'
						else:      
							cell = cell.replace(match.group(), '')
					cell = cell.replace('.0', '')

					# Check if this is an exact value
					exact = Issuer_Code==89 or Holder_Code==89 or ('x' in cell and not ((split_hold and not 'x' in str(df[df[instrument]==other_half_hold][Issuer_Code].item())) or (split_issue and not 'x' in str(df[df[instrument]==Holder_Code][other_half_issue].item()))))

					# If not, extract information
					cell = cell.replace('-', '+-')
					series_codes = cell.split('+')

					for series in series_codes:
						sign = 'Negative' if '-' in str(series) else 'Positive'

						if series != 'x':
							series = series.replace('x','').replace('-', '').strip()
						elif cell=='nan':
							series = None
						else:
							series = '0'

						data['Issuer'].append(Issuer)
						data['Holder'].append(Holder)
						data['Instrument'].append(instrument)
						data['Sign'].append(sign)
						data['Series_Name'].append(series)
						data['Exact'].append(exact)
						data['Date'].append(f'{year}-12-31')
	df = pd.DataFrame(data)
	df.loc[~df.Series_Name.isin(['0', 'nan']), 'Series_Name'] = 'FL' + df.Series_Name + '.A'
	df = df[~((df.Series_Name=='nan')&((df.Issuer=='All Sectors')|(df.Holder=='All Sectors')))]
	return df

def unveil_flow_of_funds():
	# 1. Load FWTW relationships between intermediaries
	print('Step 1:')
	fwtw_relationships = load_fwtw_relationships()
	fwtw_relationships.to_csv(os.path.join(working_folder, 'fwtw_relationships.csv'), index=False)

	# 2. Fill missing values in matrix using algorithm
	print('Step 2:')
	fwtw_matrix = fill_fwtw_matrix(fwtw_relationships)
	fwtw_matrix.to_csv(os.path.join(working_folder, 'fwtw_matrix.csv'), index=False)

	# 3. Run unveiling algorithm
	print('Step 3:')
	unveiled, unveiled_by_instrument = unveil_wrapper(fwtw_matrix)
	unveiled.to_csv(os.path.join(clean_folder, 'unveiled.csv'), index=False)
	unveiled_by_instrument.to_csv(os.path.join(clean_folder, 'unveiled_by_instrument.csv'), index=False)

	# 4. Map to wealth percentiles
	print('Step 4:')
	dina_unveiled, dfa_unveiled = map_to_wealth_percentiles(unveiled_by_instrument)
	dina_unveiled.to_csv(os.path.join(clean_folder, 'dina_unveiled.csv'), index=False)
	dfa_unveiled.to_csv(os.path.join(clean_folder, 'dfa_unveiled.csv'), index=False)


unveil_flow_of_funds()