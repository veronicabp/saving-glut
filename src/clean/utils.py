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
from pandas.errors import PerformanceWarning
warnings.filterwarnings('ignore', category=PerformanceWarning)
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
