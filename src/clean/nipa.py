from utils import * 

def load_nipa_table(file_name):
    # Read from csv
    df = pd.read_csv(file_name, skiprows=3, index_col=2).drop(columns=['Line','Unnamed: 1'])
    df = df[~df.index.isna()]
    # Pivot table so fields are columns
    df = pd.melt(df.reset_index(names='field'), id_vars='field', value_vars=df.columns, var_name='year', value_name='value')
    df['value'] = pd.to_numeric(df['value'], errors='coerce')
    df = pd.pivot_table(df, values='value', index='year', columns=['field']).reset_index()
    
    df.rename(columns={col:col.strip() for col in df.columns}, inplace=True)
    return df 

def load_nipa_tables():
    file_names = [os.path.join(raw_folder,'nipa',file) for file in os.listdir(os.path.join(raw_folder,'nipa')) if file.endswith('.csv')]
    for i, file_name in enumerate(file_names):
        if i==0:
            nipa = load_nipa_table(file_name)
        else:
            nipa = nipa.merge(load_nipa_table(file_name), on='year')
    
    nipa['year'] = nipa['year'].astype(int)
    
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

def load_dina(file='usdina19622019psz.dta'):
    df = pd.read_stata(os.path.join(raw_folder, 'dina', 'usdina19622019psz.dta'))
    df['percentile'] = get_percentiles(df, field='poinc_ptile')
    df['returns'] = np.round(df['dweght']/1e5)
    
    # Define new variables 
    df = df.rename(columns={'colexp':'gov_consumption'})
    df['gov_surplus'] = df['govin'] + df['prisupgov']
    return df

def load_cbo():
    cbo = pd.read_excel(os.path.join(raw_folder, 'cbo', '58353-supplemental-data.xlsx'), sheet_name='10. Household Income Shares', header=10, skiprows=range(11,98), skipfooter=6)
    cbo.rename(columns={'Top 1 Percent':1, 'Year':'year'}, inplace=True)
    cbo[9] = cbo['91st to 95th Percentiles'] + cbo['96th to 99th Percentiles']
    cbo[90] = 100 - cbo[1] - cbo[9]
    cbo = cbo[['year',1,9,90]]
    cbo = pd.melt(cbo, id_vars=['year'], value_vars=[1,9,90],var_name='percentile', value_name='CBOshare')
    cbo['CBOshare'] /= 100
    return cbo

def collapse_dina(dina, variables=['poinc', 'gov_consumption', 'gov_surplus']):
    return weighted_sum_collapse(dina, ['year', 'percentile'], variables, 'returns')

def get_dina_shares(df, variables=['poinc','gov_surplus','gov_consumption']): 
    # Interpolate in missing years
    df.sort_values(['year', 'percentile'], inplace=True)
    idx = -1
    for year in [1963, 1965]:
        for percentile in [1, 9, 90]:
            new_row = (np.array(df[(df.year==year+1)&(df.percentile==percentile)]) + np.array(df[(df.year==year-1)&(df.percentile==percentile)]))/2
            df.loc[idx] = new_row[0]
            idx-=1
    df.reset_index(drop=True, inplace=True)
    df.sort_values(['year', 'percentile'], inplace=True)

    # Aggregate and get shares 
    for var in variables:
        df[f'{var}_tot'] = df.groupby(['year'])[var].transform('sum')
        df[f'{var}_sh'] = df[var]/df[f'{var}_tot']

    return df[['year','percentile'] + [col for col in df.columns if col.endswith('_sh')]]

def get_consumption(df, base_year=2010, tag='DINA'):
    # Get average consumption shares from Fisher data
    fisher = pd.read_stata(os.path.join(raw_folder, 'fisher', 'Yfisherfinal.dta'))
    fisher = fisher[fisher.year>=2004] # Keep post-2004 shares
    fisher = pd.melt(fisher, id_vars=['year'], value_vars=['fisher1', 'fisher9', 'fisher90'],var_name='percentile', value_name='value')
    fisher['percentile'] = fisher['percentile'].str.extract('(\d+)').astype(int)
    fisher = fisher.groupby('percentile').mean()['value']

    # Assume consumption-to-income shares are constant over time
    base_year_income = df[df['year']==base_year].set_index('percentile')[f'{tag}income']
    base_year_consumption = df[df['year']==base_year]['PersConsEx'].mean()
        
    df[f'{tag}consumption'] = df.apply(lambda row: fisher[row['percentile']] * base_year_consumption * row[f'{tag}income']/base_year_income[row['percentile']], axis=1)
    df[f'{tag}consumption2NI'] = df[f'{tag}consumption']/df['NationalInc']
    
    return df

def calculate_dina_saving():

	# National accounts
	nipa = load_nipa_tables() 

	# Get DINA percentiles from microdata
	dina = load_dina()
	dina_collapsed = collapse_dina(dina)
	get_dina_shares(dina_collapsed)

	# Calculate income based on DINA
	df = dina_collapsed.merge(nipa, on='year')
	df['DINAincome2NI'] = df['poinc_sh'] - df['gov_consumption_sh'] * df['GovConsEx']/df['NationalInc']  - df['gov_surplus_sh'] * df['GovSaving']/df['NationalInc']
	df['DINAincome'] = df['DINAincome2NI'] * df['NationalInc']

	# Calculate income based on CBO
	cbo = load_cbo()
	df = df.merge(cbo, on=['year', 'percentile'], how='outer')
	df['CBOincome2NI'] = df['CBOshare'] * (df['NationalInc']-df['GovConsEx']-df['GovSaving'])/df['NationalInc']
	df['CBOincome'] = df['CBOincome2NI'] * df['NationalInc']

	# Construct consumption and saving
	for tag in ['DINA', 'CBO']:
	    df = get_consumption(df, tag=tag)
	    df[f'{tag}saving'] = df[f'{tag}income'] - df[f'{tag}consumption']
	    df[f'{tag}saving2NI'] = df[f'{tag}saving']/df['NationalInc']

	df = df[['year', 'percentile', 'DINAsaving2NI', 'CBOsaving2NI']]
	df.to_csv(os.path.join(clean_folder, 'nipa_savings.csv'), index=False)


calculate_dina_saving()
