from utils import * 
from python_code.fof_savings import *

def get_unfunded_pension_wealth():
	'''
	Function to load unfunded pension wealth as described in text
	'''

	df = pd.read_stata(os.path.join(raw_folder, 'fof', 'LQpanel_2022Q2.dta'))
	df['date'] = pd.to_datetime(df['quarter'])
	df['Year'] = df.date.dt.year
	df = df[df.date.dt.quarter==4]
	
	df = df.rename(columns={'fl153050005a':'finact_pens', 'fl593073045q':'finact_pens_uf'})
	return df[['Year','finact_pens','finact_pens_uf']]
	
def load_dfa(mappings):
	'''
	Function to load DFA data on asset holdings by wealth percentile
	'''
	file = os.path.join(raw_folder, 'dfa', 'dfa-networth-levels-detail.csv')
	df = pd.read_csv(file)

	# Keep one entry per year
	df['Year'] = df['Date'].str.slice(0,4).astype(int)
	df = df[df.Date.str.endswith('Q4')]

	# Combine bottom 90
	df['Percentile'] = df['Category'].replace({'Bottom50': 90, 'Next40': 90, 'Top1':1, 'Next9':9})
	df = df.groupby(['Year', 'Percentile']).sum().reset_index()

	#Exclude unfunded pension wealth
	unfunded_pensions = get_unfunded_pension_wealth()
	df = df.merge(unfunded_pensions, on='Year')
	df['Pensions Total'] = df.groupby(['Year'])['Pension entitlements'].transform('sum')
	df['Pensions Exc. Unfund'] = df['Pensions Total'] - df['finact_pens_uf']
	df['Pension entitlements'] = df['Pension entitlements'] * df['Pensions Exc. Unfund']/df['Pensions Total']
	df = df.drop(columns=['Pensions Total','Pensions Exc. Unfund', 'finact_pens', 'finact_pens_uf', 'Date', 'Category'])

	variables = [col for col in df.columns if col not in ['Year', 'Percentile']]
	for var in variables:
	    df[f'{var}_tot'] = df.groupby(['Year'])[var].transform('sum')
	    df[var] = df[var]/df[f'{var}_tot']
	    df = df.drop(columns=f'{var}_tot')
	    
	df = df.rename(columns={col: col.title() for col in df.columns})
	dfa_categories = list(mappings[~mappings['DFA Category'].isna()]['DFA Category'].unique())

	df = df[['Year','Percentile']+dfa_categories]
	    
	df = df.melt(id_vars=['Year','Percentile'], value_vars=dfa_categories, var_name='DFA Category', value_name='Percentile Share')     
	return df

def map_to_wealth_percentiles(df, shares=None, name='DINA', relations=dina_relations):
	'''
	Function to map FOF wealth data to percentile holdings and aggregate at the percentile level
	'''
	df = df.merge(shares, on=[f'{name} Category','Year'])

	df.rename(columns={'Amount':'Total Amount'}, inplace=True)
	df['Amount'] = df['Total Amount'] * df['Subcategory Share'] * df['Percentile Share']

	# Collapse
	df = df.groupby(['Primary Asset', 'Final Holder', 'Percentile', 'Year'], observed=True).agg({'Amount':'sum', 'NationalInc':'mean'}).reset_index()
	df[f'{name}Wealth2NI'] = df['Amount']/df['NationalInc']
	df[f'{name}Wealth'] = df['Amount']
	df.drop(columns=['Amount','NationalInc'], inplace=True)
	return df

def map_to_wealth_percentiles_wrapper(unveiled_by_instrument, fof):
	'''
	Function to get wealth data at the percentile level, based on both DINA and DFA data on percentile shares of asset holdings
	'''

	# Load useful datasets 
	mappings = pd.read_csv(os.path.join(raw_folder, 'personal', 'fof_distributional_relations.csv'))
	mappings = mappings[mappings['Is Asset']==1]
	subcategory_shares = get_subcategory_shares(fof)

	# Set all instrument names to title case
	df = unveiled_by_instrument.copy()
	df['Instrument'] = df.apply(lambda row: row.Instrument.title(), axis=1)

	# Combine miscellaneous instruments
	df.loc[df.Instrument.str.contains('Miscellaneous'), 'Instrument'] = 'Miscellaneous Financial Claims'
 
	# Keep only data for households
	df = df[['Primary Asset', 'Final Holder', 'Instrument', 'Year', 'Amount']].groupby(['Primary Asset', 'Final Holder', 'Instrument', 'Year']).sum()['Amount'].reset_index()
	df = df[df['Final Holder']=='Households and Nonprofit Organizations']

	# Merge data
	df = pd.merge(df, load_national_income(), on='Year')
	df = df.merge(mappings, left_on='Instrument', right_on='Description', how='inner')
	df = df.merge(subcategory_shares, on=['Description', 'Subcategory','Year'], how='left')
	df.loc[df['Subcategory Share'].isna(), 'Subcategory Share'] = 1

	metadata = {
		'DINA': (load_dina(mappings), dina_relations),
		'DFA': (load_dfa(mappings), dfa_relations)
	}

	results = []
	for key in metadata:
		result = map_to_wealth_percentiles(df.copy(), name=key, shares=metadata[key][0], relations=metadata[key][1])
		results.append(result)

	return results[0], results[1]

def make_net(df, category='Rest of World'):
	'''
	Function to calculate net asset holdings for a particular sector that issues and holds US wealth
	'''
	for year in tqdm(df.Year.unique()):
		for sector in df.Holder.unique():
			issuer_series = (df.Issuer==category)&(df.Holder==sector)&(df.Year==year)
			holder_series = (df.Holder==category)&(df.Issuer==sector)&(df.Year==year) 
			
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
	'''
	Function to construct a matrix detailing the share of debt issued by each intermediary and held directly or indirectly by final asset owners
	'''

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
	'''
	Function to construct a matrix of direct holdings of primary assets by final holders
	'''
	M = np.zeros((d1, d2))
	for i, issuer in enumerate(issuers):
		for j, holder in enumerate(holders):
			amt = df[(df.Issuer==issuer)&(df.Holder==holder)].pct_issued.sum()
			M[i,j] = amt 
			
	return M

def construct_matrices(df, primary_assets=['Households and Nonprofit Organizations', 'Federal Government', 'Nonfinancial Non-Corporate Business', 'Nonfinancial Corporate Business', 'Non-Financial Assets'], final_holders=['Households and Nonprofit Organizations', 'Rest of World', 'Federal Government', 'State and Local Governments']):
	'''
	Function to construct the main matrices necessary to run the unveiing exercise
	'''

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
	'''
	Function to extract the level of debt issued for each primary asset
	'''

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
	'''
	Function to calculate a matrix containing the share of each primary asset that can be traced to each final asset holder
	'''
	return np.matmul(W, Omega) + D

def unveil(df, primary_assets=[], final_holders=[]):
	'''
	Function to unveil wealth holdings in each year
	'''
	dfs = []
	for year in tqdm(sorted(df.Year.unique())):
		Omega, D, W = construct_matrices(df[df.Year==year], primary_assets=primary_assets, final_holders=final_holders)
		A = calculate_A(Omega, D, W)

		# Store in a data frame
		data = {'Primary Asset':[], 'Final Holder':[], 'Share':[], 'Year':[]}
		for i, asset in enumerate(primary_assets):
			for j, holder in enumerate(final_holders):
				data['Primary Asset'].append(asset)
				data['Final Holder'].append(holder)
				data['Share'].append(A[i,j])
				data['Year'].append(year)
		new_df = pd.DataFrame(data)
		dfs.append(new_df)

	return pd.concat(dfs)

def unveil_wrapper(fwtw_matrix, primary_assets=['Households and Nonprofit Organizations', 'Federal Government', 'Nonfinancial Non-Corporate Business', 'Nonfinancial Corporate Business', 'Non-Financial Assets'], final_holders=['Households and Nonprofit Organizations', 'Rest of World', 'Federal Government', 'State and Local Governments']):
	'''
	Wrapper function to prepare data for unveiling algorithm and apply the algorithm. First, the algorithm is run fully to get total wealth of each type held by each sector. Next, the algorithm is adjusted to get the instruments through which wealth is held.
	'''

	fwtw_matrix = fwtw_matrix[fwtw_matrix.Holder!='Instrument Discrepancies Sector'] # Remove discrepancies sector
	fwtw_matrix = fwtw_matrix.groupby(['Issuer', 'Holder', 'Instrument', 'Year']).mean()['Amount'].reset_index()
	df = fwtw_matrix.groupby(['Issuer', 'Holder', 'Year']).sum()['Amount'].reset_index()

	# Make holdings of rest of the world net
	df = make_net(df, category='Rest of World')
	intermediaries = list((set(df.Issuer.unique()) | set(df.Holder.unique()))-set(final_holders)) 

	# Create share issued
	df['total_issued'] = df.groupby(['Issuer','Year'])['Amount'].transform('sum')
	df.loc[df.total_issued==0, 'total_issued'] = 1 
	df['pct_issued'] = df.Amount/df.total_issued

	# Store levels of primary assets issued
	data = {'Primary Asset':[], 'Year':[], 'Level':[]}
	for year in tqdm(sorted(df.Year.unique())):
	    L = get_level(df[df.Year==year], primary_assets=primary_assets, final_holders=final_holders)
	    for i, asset in enumerate(primary_assets):
	        data['Primary Asset'].append(asset)
	        data['Year'].append(year)
	        data['Level'].append(L[i,0])

	levels = pd.DataFrame(data)

	###############################
	# 1. Unveil in aggregate 
	###############################
	output = unveil(df, primary_assets=primary_assets, final_holders=final_holders)
	output = pd.merge(output, levels, on=['Year', 'Primary Asset'])
	output['Amount'] = output.Level * output.Share

	##############################################################
	# 2. Unveil by instrument (for percentile distribution)
	##############################################################
	df_sector = df.copy()
	df_sector.loc[df_sector.Holder.isin(final_holders), 'Holder'] = df_sector['Issuer'] + ' - ' + df_sector['Holder']
	final_holders_sector = final_holders + [f'{a} - {b}' for a in df.Issuer.unique() for b in final_holders]

	output_sector = unveil(df_sector, primary_assets=primary_assets, final_holders=final_holders_sector)
	output_sector[['Intermediary', 'Final Holder']] = output_sector['Final Holder'].str.split(' - ', expand=True)
	output_sector = output_sector[~output_sector['Final Holder'].isna()]

	# Allocate to instruments through which final holders directly hold debt
	instrument_shares = fwtw_matrix.copy()
	instrument_shares['Total'] = instrument_shares.groupby(['Issuer','Holder','Year'])['Amount'].transform('sum')
	instrument_shares['sub_share'] = instrument_shares.Amount/instrument_shares.Total
	instrument_shares.rename(columns={'Issuer':'Intermediary', 'Holder':'Final Holder',}, inplace=True)
	instrument_shares = instrument_shares[['Intermediary', 'Final Holder', 'Instrument', 'Year', 'sub_share']]

	output_by_instrument = pd.merge(output_sector, instrument_shares, on=['Year','Intermediary', 'Final Holder'])
	output_by_instrument['Share'] = output_by_instrument.Share * output_by_instrument.sub_share
	output_by_instrument.drop(columns=['sub_share'], inplace=True)

	# Merge in level
	output_by_instrument = pd.merge(output_by_instrument, levels, on=['Year', 'Primary Asset'])
	output_by_instrument['Amount'] = output_by_instrument.Level * output_by_instrument.Share
	
	return output, output_by_instrument

def redistribute_rows(matrix, constrained, row_totals_sub, col_totals_sub):
	'''
	Function to re-scale matrix so that columns sum to total
	'''
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
	'''
	Function to re-scale matrix so that rows sum to total
	'''
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
	'''
	Function to fill unknown elements of a matrix semi-proportionately so that known cells and column/row totals are satisfied
	'''

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
	'''
	Function to fill a matrix proportionately so that row and column totals match known vectors
	'''
	n = len(row_totals)
	m = len(col_totals)
	matrix = np.array([[row_totals[i] * col_totals[j] / row_totals.sum() for j in range(m)] for i in range(n)])
	return matrix

def normalize_duplicates(sub):
	'''
	Function to distribute fields which should be applied to multiple cells
	'''
	# For the data in the middle of the matrix, if a single series belongs to multiple columns, asign it proportionally
	dup = sub[(~sub.Exact)&(sub.Sign=='Positive')]
	dup = dup[dup.duplicated(subset='SERIES_NAME')]
	for series in dup.SERIES_NAME.unique():
		issuers_dup=sub[sub.SERIES_NAME==series].Issuer.unique()
		holders_dup=sub[sub.SERIES_NAME==series].Holder.unique()

		if len(issuers_dup)>1:
			tot = sub[(sub.Issuer.isin(issuers_dup))&(sub.Holder=='All Sectors')].Amount.sum()
			if tot==0:
				continue
			for issuer_dup in issuers_dup:
				sub.loc[(sub.Issuer==issuer_dup)&(sub.SERIES_NAME==series), 'Amount'] *= sub[(sub.Issuer==issuer_dup)&(sub.Holder=='All Sectors')].Amount.sum()/tot
		if len(holders_dup)>1:
			tot = sub[(sub.Holder.isin(holders_dup))&(sub.Issuer=='All Sectors')].Amount.sum()
			if tot==0:
				continue
			for holder_dup in holders_dup:
				sub.loc[(sub.Holder==holder_dup)&(sub.SERIES_NAME==series), 'Amount'] *= sub[(sub.Holder==holder_dup)&(sub.Issuer=='All Sectors')].Amount.sum()/tot
	return sub

def rescale_interior(sub, issuers, holders, row_totals, col_totals):
	'''
	Function to rescale columns that sum to more than the known total
	'''
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
	'''
	Function to create matrices with known cell values
	'''
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
	'''
	Function to create matrices of liabilities issued and held by each sector through each instrument, subject to the proportionality assumption described in the text as well as to known constraints
	'''
	output = df.groupby(['Issuer', 'Holder', 'Instrument','Year']).sum()['Amount'].reset_index()
	proportional_output = output.copy()
	allocated_columwise = output.copy()
	
	df = df[(~df.SERIES_NAME.isna())]

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

def fill_fwtw_matrix(relationships, full_df):
	'''
	Function to get missing relationships between lenders/borrowers/instruments for each year. Prepares data and applies `create_matrix' to each year
	'''
	
	full_df['Amount'] = pd.to_numeric(full_df['Amount'], errors='coerce')
	full_df['Amount'] = full_df['Amount']/1000 # Units in billions of USD

	# Merge into relationships data, keeping only
	df = pd.merge(relationships, full_df, on=['SERIES_NAME', 'Year'], how='left')
	df.loc[df.SERIES_NAME=='0', 'Amount'] = 0
	df.loc[df.Sign=='Negative', 'Amount'] = - df.Amount

	# If liabilities are negative, add them to assets
	for i, row in tqdm(df[(df.Amount<0)&(df.Sign=='Positive')&(df.Holder!='Instrument Discrepancies Sector')].iterrows()):

		new_row = row.copy()
		new_row['Holder'] = row.Issuer
		new_row['Issuer'] = row.Holder
		new_row['Amount'] = -row.Amount
		df = pd.concat([df, pd.DataFrame([new_row.values], columns=df.columns)])

		df = df[~((df.Instrument==row.Instrument)&(df.Holder==row.Holder)&(df.Issuer==row.Issuer)&(df.SERIES_NAME==row.SERIES_NAME)&(df.Year==row.Year))].copy()

	# Set all instrument discrepancy values within the matrix as unknown
	df.loc[(df.Holder=='Instrument Discrepancies Sector')&(df.Issuer!='All Sectors'), 'Amount'] = np.nan

	# Create matrices
	matrices, proportional_matrices, columnwise_matrices = [], [], []
	for year in tqdm(df.Year.unique()):
		matrix, proportional_matrix, columnwise_matrix = create_matrix(df[df.Year==year])
		matrices.append(matrix)
		proportional_matrices.append(proportional_matrix)
		columnwise_matrices.append(columnwise_matrix)

	# Combine
	output = pd.concat(matrices)
	output = output[output.Amount > 0]
	output = output[(output.Issuer!='All Sectors')&(output.Holder!='All Sectors')]
	return output

def load_fwtw_relationships():
	'''
	Function to load known relationships between flow of funds sectors and store in a DataFrame
	'''

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
		'SERIES_NAME':[],
		'Year':[],
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
						data['SERIES_NAME'].append(series)
						data['Exact'].append(exact)
						data['Year'].append(year)
	df = pd.DataFrame(data)
	df.loc[~df.SERIES_NAME.isin(['0', 'nan']), 'SERIES_NAME'] = 'FL' + df.SERIES_NAME + '.A'
	df = df[~((df.SERIES_NAME=='nan')&((df.Issuer=='All Sectors')|(df.Holder=='All Sectors')))]
	return df

def main():

	# 0. Load flow of funds data, which will be used several times
	fof = get_fof()

	# 1. Load FWTW relationships between intermediaries
	print('Step 1:')
	fwtw_relationships = load_fwtw_relationships()
	fwtw_relationships.to_csv(os.path.join(working_folder, 'fwtw_relationships.csv'), index=False)

	fwtw_relationships = pd.read_csv(os.path.join(working_folder, 'fwtw_relationships.csv'))

	# 2. Fill missing values in matrix using algorithm
	print('Step 2:')
	fwtw_matrix = fill_fwtw_matrix(fwtw_relationships, fof)
	fwtw_matrix.to_csv(os.path.join(working_folder, 'fwtw_matrix.csv'), index=False)


	# 3. Run unveiling algorithm
	print('Step 3:')
	unveiled, unveiled_by_instrument = unveil_wrapper(fwtw_matrix)
	unveiled.to_csv(os.path.join(clean_folder, 'unveiled.csv'), index=False)
	unveiled_by_instrument.to_csv(os.path.join(clean_folder, 'unveiled_by_instrument.csv'), index=False)

	# 4. Map to wealth percentiles

	print('Step 4:')
	dina_unveiled, dfa_unveiled = map_to_wealth_percentiles_wrapper(unveiled_by_instrument, fof)
	dina_unveiled.to_csv(os.path.join(clean_folder, 'dina_unveiled.csv'), index=False)
	dfa_unveiled.to_csv(os.path.join(clean_folder, 'dfa_unveiled.csv'), index=False)


if __name__=="__main__":
	main()
