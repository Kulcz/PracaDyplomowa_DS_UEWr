from scholar import ScholarQuerier, ScholarSettings

# Create a ScholarQuerier object
querier = ScholarQuerier()

# Create a ScholarSettings object
settings = ScholarSettings()

# Set the desired number of results (default is 10)
settings.set_num_page_results(5)

# Send query to Google Scholar
querier.send_query('artificial intelligence')

# Get the list of articles
articles = querier.articles

# Print the titles and URLs of the first 5 articles
for article in articles[:5]:
    print("Title:", article['title'])
    print("URL:", article['url'])
    print()
