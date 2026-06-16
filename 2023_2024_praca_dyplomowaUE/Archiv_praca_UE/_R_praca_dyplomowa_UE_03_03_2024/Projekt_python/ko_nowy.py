import pandas as pd
import requests
from bs4 import BeautifulSoup as bs
from tqdm import tqdm
from tabulate import tabulate

pd.set_option('display.max_columns', None)
pd.set_option('display.max_colwidth', 40)

big_df = pd.DataFrame()
headers = {
    'accept-language': 'en-US,en;q=0.9, pl-PL',
    'x-requested-with': 'XHR',
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/105.0.0.0 Safari/537.36'
}
s = requests.Session()
s.headers.update(headers)

payload = {'json': '1'}

for x in tqdm(range(0, 500, 100)):
    url = f'https://scholar.google.com/citations?hl=en&user=RNDE9-wAAAAJ&hl&cstart={x}&pagesize=100'
    r = s.post(url, data=payload)
    soup = bs(r.json()['B'], 'html.parser')
    works = [(x.get_text(), 'https://scholar.google.com' + x.get('href')) for x in soup.select('a') if 'javascript:void(0)' not in x.get('href') and len(x.get_text()) > 7]
    df = pd.DataFrame(works, columns = ['Paper', 'Link'])
    big_df = pd.concat([big_df, df], axis=0, ignore_index=True)
limited_df = big_df.head(20)
print(tabulate(limited_df, showindex=False, headers=big_df.columns))

# Specify the file path where you want to save the CSV file
csv_file_path = 'output.csv'

# Save big_df to a CSV file with UTF-8 encoding
big_df.to_csv(csv_file_path, index=False, encoding='utf-8')

print(f"DataFrame successfully saved to {csv_file_path}")

