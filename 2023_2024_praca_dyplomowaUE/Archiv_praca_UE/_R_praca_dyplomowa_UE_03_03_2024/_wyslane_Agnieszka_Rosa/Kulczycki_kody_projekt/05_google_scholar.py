# import modułów
import pandas as pd #biblioteka do pracy z danymi tabelarycznymi
import requests #biblioteka do wykonywania zapytań HTTP
from bs4 import BeautifulSoup as bs #przetwarzania dokumentów HTML
from tabulate import tabulate #wyświetlania danych w postaci tabel
from rich.console import Console

pd.set_option('display.max_columns', None) #kolumny w ramkach danych pandas
pd.set_option('display.max_colwidth', 65) #maksymalnej szerokości kolumny
big_df = pd.DataFrame()# inicjalizacja pustej ramki danych
# definicja nagłówków i sesji HTTP
headers = {
    'accept-language': 'en-US,en;q=0.9, pl-PL',
    'x-requested-with': 'XHR',
    'User-Agent':
    'Mozilla/5.0(Windows NT 10.0; Win64; x64),like Gecko)Chrome/105.0.0.0 Safari/537.36'
}
s = requests.Session()
s.headers.update(headers)
payload = {'json': '1'}
for x in range(0, 500, 100): # iteracja x po zakresie od 0 do 500 z krokiem 100
    # zdefiniowanie linku strony dla profilu naukowca
    url = f'https://scholar.google.com/citations?hl=en&user=RNDE9-wAAAAJ&hl&cstart={x}&pagesize=100'
    r = s.post(url, data=payload)
    # zastosowanie parsera html
    soup = bs(r.json()['B'], 'html.parser') #analiza strony przy użyciu BeautifulSoup
    works = [(x.get_text(), 'https://scholar.google.com' + x.get('href'))
             for x in soup.select('a') if 'javascript:void(0)' not in x.get('href')
             and len(x.get_text()) > 7] #pobranie informacji dla elementów HTML
# utworzenie ramki danych z pobranych informacji
    df = pd.DataFrame(works, columns=['Paper', 'Link'])
    big_df = pd.concat([big_df, df], axis=0, ignore_index=True)
# zapisanie wyników do pliku csv
csv_file_path = 'output.csv'
big_df.to_csv(csv_file_path, index=False, encoding='utf-8')
# ograniczenie wyników na konsoli do 10
limited_df = big_df.head(10)
# wyświetlenie wyników w postaci tabeli
print(limited_df)
