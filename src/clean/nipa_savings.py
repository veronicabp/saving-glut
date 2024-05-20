from utils import * 

def load_cbo():
    cbo = pd.read_excel(os.path.join(raw_folder, 'cbo', '58353-supplemental-data.xlsx'), sheet_name='10. Household Income Shares', header=10, skiprows=range(11,98), skipfooter=6)
    cbo.rename(columns={'Top 1 Percent':1, 'Year':'Year'}, inplace=True)
    cbo[9] = cbo['91st to 95th Percentiles'] + cbo['96th to 99th Percentiles']
    cbo[90] = 100 - cbo[1] - cbo[9]
    cbo = cbo[['Year',1,9,90]]
    cbo = pd.melt(cbo, id_vars=['Year'], value_vars=[1,9,90],var_name='Percentile', value_name='CBOshare')
    cbo['CBOshare'] /= 100
    return cbo

def get_consumption(df, base_year=2010, tag='DINA'):
    # Get average consumption shares from Fisher data
    fisher = pd.read_stata(os.path.join(raw_folder, 'fisher', 'Yfisherfinal.dta')).rename(columns={'year':'Year'})
    fisher = fisher[fisher.Year>=2004] # Keep post-2004 shares
    fisher = pd.melt(fisher, id_vars=['Year'], value_vars=['fisher1', 'fisher9', 'fisher90'],var_name='Percentile', value_name='value')
    fisher['Percentile'] = fisher['Percentile'].str.extract('(\d+)').astype(int)
    fisher = fisher.groupby('Percentile').mean()['value']

    # Assume consumption-to-income shares are constant over time
    base_year_income = df[df['Year']==base_year].set_index('Percentile')[f'{tag}income']
    base_year_consumption = df[df['Year']==base_year]['PersConsEx'].mean()
        
    df[f'{tag}consumption'] = df.apply(lambda row: fisher[row['Percentile']] * base_year_consumption * row[f'{tag}income']/base_year_income[row['Percentile']], axis=1)
    df[f'{tag}consumption2NI'] = df[f'{tag}consumption']/df['NationalInc']
    
    return df

def main():

	# National accounts
	nipa = load_nipa_tables() 

	# Get DINA percentiles from microdata
	dina = load_data('dinapsz_poincsort.csv', folder='working')

	# Calculate income based on DINA
	df = dina.merge(nipa, on='Year')
	df['DINAincome2NI'] = df['szpoincsh'] - df['szgov_consumptionsh'] * df['GovConsEx']/df['NationalInc']  - df['szgov_surplussh'] * df['GovSaving']/df['NationalInc']
	df['DINAincome'] = df['DINAincome2NI'] * df['NationalInc']

	# Calculate income based on CBO
	cbo = load_cbo()
	df = df.merge(cbo, on=['Year', 'Percentile'], how='outer')
	df['CBOincome2NI'] = df['CBOshare'] * (df['NationalInc']-df['GovConsEx']-df['GovSaving'])/df['NationalInc']
	df['CBOincome'] = df['CBOincome2NI'] * df['NationalInc']

	# Construct consumption and saving
	for tag in ['DINA', 'CBO']:
	    df = get_consumption(df, tag=tag)
	    df[f'{tag}saving'] = df[f'{tag}income'] - df[f'{tag}consumption']
	    df[f'{tag}saving2NI'] = df[f'{tag}saving']/df['NationalInc']

	df = df[['Year', 'Percentile', 'DINAsaving2NI', 'CBOsaving2NI']]
	df.to_csv(os.path.join(clean_folder, 'nipa_savings.csv'), index=False)

main()
