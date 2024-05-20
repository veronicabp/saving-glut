from utils import * 

def collapse_dina(tag='', sort='wealth', variables=['taxbond', 'currency','equity','bus','pens','muni', 'ownerhome', 'ownermort', 'nonmort', 'poinc','gov_surplus','gov_consumption']):
	file = os.path.join(raw_folder, 'dina', f'usdina19622019{tag}.dta')
	df = pd.read_stata(file)
	df['Percentile'] = get_percentiles(df, field=f'{sort}_ptile')
	df['returns'] = np.round(df['dweght']/1e5)

	df = df.drop(columns='equity')
	df = df.rename(columns={'year':'Year','hwbus':'bus', 'hwpen':'pens', 'hwequ':'equity', 'colexp':'gov_consumption'})
	df['gov_surplus'] = df['govin'] + df['prisupgov']

	# Get weighted sum
	df = weighted_sum_collapse(df, ['Year', 'Percentile'], variables, 'returns')

	# Interpolate missing years (1963 & 1965)
	df.sort_values(['Year', 'Percentile'], inplace=True)
	idx = -1
	for year in [1963, 1965]:
		for percentile in [1, 9, 90]:
			new_row = (np.array(df[(df.Year==year+1)&(df.Percentile==percentile)]) + np.array(df[(df.Year==year-1)&(df.Percentile==percentile)]))/2
			df.loc[idx] = new_row[0]
			idx-=1
	df.reset_index(drop=True, inplace=True)
	df.sort_values(['Year', 'Percentile'], inplace=True)

	# Calculate totals and shares
	for var in variables:
		df[f'sz{var}'] = df.groupby(['Year'])[var].transform('sum')
		df[f'sz{var}sh'] = df[var]/df[f'sz{var}']

	df.to_csv(os.path.join(working_folder, f'dina{tag}_{sort}sort.csv'), index=False)


i = 1
for tag in ['', 'psz']:
	for sort in ['wealth', 'poinc']:
		collapse_dina(tag=tag, sort=sort)
		print(f'Saved {i}.')
		i += 1