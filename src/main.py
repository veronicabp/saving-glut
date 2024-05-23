from utils import *

def run_python(file, folder='clean'):
	start = time.time()

	print(f"\n\n\n{file}")
	print('-'*30)
	print("\n\n")
	file_path = os.path.join(folder, file)
	subprocess.run(['python3',file_path])

	end = time.time()

	print(f'>>Time Elapsed: {np.round(end-start)} seconds.')


run_python('dina_shares.py')
run_python('nipa_savings.py')
run_python('fof_savings.py')
run_python('unveiling.py')