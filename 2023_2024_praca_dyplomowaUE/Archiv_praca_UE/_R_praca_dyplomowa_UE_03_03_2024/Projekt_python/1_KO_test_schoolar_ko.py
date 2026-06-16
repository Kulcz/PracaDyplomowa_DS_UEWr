import csv
import requests
from bs4 import BeautifulSoup

def getScholarData():
    try:
        url = "https://www.google.com/scholar?q=sulphur soil"
        headers = {
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_11_3) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/100.0.4896.127 Safari/537.36"
        }
        response = requests.get(url, headers=headers)
        soup = BeautifulSoup(response.text, 'html.parser')

        scholar_results = []
        
        for el in soup.select(".gs_ri"):
            scholar_results.append({
                "title": el.select(".gs_rt")[0].text,
                "title_link": el.select(".gs_rt a")[0]["href"],
                "id": el.select(".gs_rt a")[0]["id"],
                "displayed_link": el.select(".gs_a")[0].text,
                "snippet": el.select(".gs_rs")[0].text.replace("\n", ""),
                "cited_by_count": el.select(".gs_nph+ a")[0].text,
                "cited_link": "https://scholar.google.com" + el.select(".gs_nph+ a")[0]["href"],
                "versions_count": el.select("a~ a+ .gs_nph")[0].text,
                "versions_link": "https://scholar.google.com" + el.select("a~ a+ .gs_nph")[0]["href"] if el.select("a~ a+ .gs_nph")[0].text else "",
            })
  
        printResults(scholar_results)
        generateCSV(scholar_results, 'scholar.csv')
      
    except Exception as e:
        print(e)

def printResults(scholar_results):
    fields_ordered = ["title", "title_link","id", "displayed_link", "snippet", "cited_by_count", "cited_link", "versions_count", "versions_link"]
    for position in scholar_results: 
        for field in fields_ordered:
            if position.get(field) is not None:
                print("{}: {}".format(field, position[field].encode('utf-8')))
        print('')  

def generateCSV(scholar_results, file_name):
    fields_ordered = ["title", "title_link", "id", "displayed_link", "snippet", "cited_by_count", "cited_link", "versions_count", "versions_link"]
    with open(file_name, 'w') as fh:
        fh.write(';'.join(fields_ordered))
        fh.write('\n')
        for position in scholar_results: 
            fields = []
            for field in fields_ordered:
                value = '' if position.get(field) is None else position[field].encode('utf-8')
                fields.append(value)
            fh.write(';'.join(fields)) 
            fh.write('\n')
    print('CSV file created: {}'.format(file_name))               

getScholarData()




