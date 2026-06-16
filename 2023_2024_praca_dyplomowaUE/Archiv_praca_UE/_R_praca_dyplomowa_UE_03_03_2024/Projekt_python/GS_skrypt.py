from bs4 import BeautifulSoup
import requests

headers = {"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_11_3) AppleWebKit/537.36 (KHTML, like Gecko)Chrome/100.0.4896.127 Safari/537.36"}
url = "https://scholar.google.com/scholar?hl=en&as_sdt=0%2C5&q=%22elemental+sulphur+fertilization%22+%7Esulfur&oq="

response = requests.get(url,headers=headers)
response.encoding = 'utf-8'
soup = BeautifulSoup(response.content, 'lxml')

for item in soup.select('[data-lid]'):
    print(item)
    print(item.select('h3')[0].get_text())
    print(item.select('a')[0]['href'])
    print(item.select('.gs_rs')[0].get_text())
    print(item.select('.gs_a')[0].get_text())
    print(item.select('.gs_nph+ a')[0].get_text())
    print('----------------------------------')