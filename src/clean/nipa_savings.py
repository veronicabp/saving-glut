import sys
sys.path.append('')
from utils import * 

def load_cbo():
    '''
    Function to load CBO data on income
    '''

    cbo = pd.read_excel(os.path.join(raw_folder, 'cbo', '58353-supplemental-data.xlsx'), sheet_name='10. Household Income Shares', header=10, skiprows=range(11,98), skipfooter=6)
    cbo.rename(columns={'Top 1 Percent':1, 'Year':'Year'}, inplace=True)
    cbo[9] = cbo['91st to 95th Percentiles'] + cbo['96th to 99th Percentiles']
    cbo[90] = 100 - cbo[1] - cbo[9]
    cbo = cbo[['Year',1,9,90]]
    cbo = pd.melt(cbo, id_vars=['Year'], value_vars=[1,9,90],var_name='Percentile', value_name='CBOshare')
    cbo['CBOshare'] /= 100
    return cbo

def get_consumption(df, base_year=2010, tag='DINA'):
    '''
    Function to calculate consumption by percentiles given certain assumptions
    '''

    # Get consumption-to-income ratio in 2010
    fisher = pd.read_stata(os.path.join(raw_folder, 'fisher', 'Yfisherfinal.dta')).rename(columns={'year':'Year'})
    fisher = fisher[fisher.Year>=2004] # Keep post-2004 shares
    fisher = pd.melt(fisher, id_vars=['Year'], value_vars=['fisher1', 'fisher9', 'fisher90'],var_name='Percentile', value_name='value')
    fisher['Percentile'] = fisher['Percentile'].str.extract('(\d+)').astype(int)
    fisher = fisher.groupby('Percentile').mean()['value'].reset_index().rename(columns={'value':'cons_share'})

    c2i = fisher.merge(df[df.Year==2010][['Percentile',f'{tag}income','PersConsEx']], on='Percentile')
    c2i['cons2inc'] = c2i.PersConsEx * c2i.cons_share / c2i[f'{tag}income']
    c2i = c2i.set_index('Percentile')['cons2inc']

    # Pivot to get consumption for each percentile
    pivot = df.pivot_table(values=f'{tag}income', index=['Year', 'PersConsEx'], columns='Percentile').reset_index().rename(columns={p: f'{tag}income{p}' for p in [1,9,90]})

    # Assume constant consumption-to-income ratio for top 10
    for p in [1,9]:
        pivot[f'{tag}consumption{p}'] = c2i[p] * pivot[f'{tag}income{p}']

    # Set consumption of bottom 90 as residual
    pivot[f'{tag}consumption90'] = pivot['PersConsEx'] - pivot[f'{tag}consumption1'] - pivot[f'{tag}consumption9']

    # Merge back with other data
    unpivot = pd.wide_to_long(pivot, [f'{tag}income', f'{tag}consumption'], i='Year', j='Percentile').reset_index().drop(columns=['PersConsEx',f'{tag}income'])
    df = df.merge(unpivot, on=['Year', 'Percentile'], how='outer')

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

if __name__=="__main__":
    main()
