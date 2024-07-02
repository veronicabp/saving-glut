import sys
sys.path.append('')
from utils import * 

def collapse_dina(filename='dina.csv', tag='', sort='hweal', variables=['taxbond', 'currency','equity','bus','fi','pens','muni', 'ownerhome', 'ownermort', 'nonmort', 'poinc','peinc','dicsh','gov_surplus','gov_consumption'], bins=np.array([.9, .99, 1]), labels=np.array([90, 9, 1])):
	'''
	Function to collapse DINA data on wealth and income and aggregate at the percentile level

	filename (str)			: name of collapsed output file
	tag (str)				: indicates which version of the DINA data should be used
	sort (str)				: indicates whether percentiles should be sorted by wealth or income
	variables (list[str])	: list of variables to keep
	bins (np.array)			: array of percentiles to create
	labels (np.array)		: names of percentile bins
	'''
	file = os.path.join(raw_folder, 'dina', f'usdina19622019{tag}.dta')
	df = pd.read_stata(file)

	percentile_series = df.groupby('year').apply(lambda x: pd.Series(get_percentile_group(x, col=sort,  weight='dweght', quantiles=bins/bins[-1], quantile_labels=labels), index=x.index))
	df['Percentile'] = percentile_series.droplevel(0)

	df['returns'] = np.round(df['dweght']/1e5)
	df = df.drop(columns='equity')
	df = df.rename(columns={'year':'Year','hwbus':'bus', 'hwpen':'pens', 'hwequ':'equity', 'hwfix':'fi', 'colexp':'gov_consumption'})
	df['gov_surplus'] = df['govin'] + df['prisupgov']

	# Save observation counts
	counts = df.groupby(['Year','Percentile']).size().reset_index().rename(columns={0:'obs_count'})

	# Get weighted sum
	df = weighted_sum_collapse(df, ['Year', 'Percentile'], variables, 'returns')
	df = df.merge(counts, on=['Year','Percentile'])

	# Interpolate missing years (1963 & 1965)
	df.sort_values(['Year', 'Percentile'], inplace=True)
	idx = -1
	for year in [1963, 1965]:
		for percentile in labels:
			new_row = (np.array(df[(df.Year==year+1)&(df.Percentile==percentile)]) + np.array(df[(df.Year==year-1)&(df.Percentile==percentile)]))/2
			if len(new_row)>0:
				df.loc[idx] = new_row[0]
				idx-=1
	df.reset_index(drop=True, inplace=True)
	df.sort_values(['Year', 'Percentile'], inplace=True)

	# Calculate totals and shares
	for var in variables:
		df[f'sz{var}'] = df.groupby(['Year'])[var].transform('sum')
		df[f'sz{var}sh'] = df[var]/df[f'sz{var}']

	# Calculate share for misc category
	df['szfash'] = (df['equity']+df['fi']+df['bus']+df['pens'])/(df['szequity']+df['szfi']+df['szbus']+df['szpens'])

	df.to_csv(os.path.join(working_folder, filename), index=False)

def main():
	# Collapse DINA data (both regular and PSZ version) by wealth and income percentiles
	i = 1
	for tag in ['', 'psz']:
		for sort in ['hweal', 'poinc']:
			filename = f'dina{tag}_{sort}sort.csv'
			collapse_dina(filename=filename, tag=tag, sort=sort)
			print(f'Saved {i}.')
			i += 1

	# Collapse into 100 bins
	quantiles = np.linspace(1,100,100)
	collapse_dina(filename='dina_hwealsort_100.csv',tag='', sort='hweal', bins=quantiles, labels=quantiles)
	print(f'Saved {i}.')
	i+=1

	# Separate the top 1% into 5 bins
	quantiles = np.concatenate((np.linspace(1,99,99),np.linspace(99.2,100,5)))
	collapse_dina(filename='dina_hwealsort_granular.csv',tag='', sort='hweal', bins=quantiles, labels=quantiles)
	print(f'Saved {i}.')

if __name__=="__main__":
	main()

