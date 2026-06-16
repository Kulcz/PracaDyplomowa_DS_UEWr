from scholarly import scholarly

# Retrieve the author's data, fill-in, and print
from scholarly import scholarly

print(next(scholarly.search_author('Grzegorz Kulczycki')))



# Retrieve the author's data, fill-in, and print
search_query = scholarly.search_author('Grzegorz Kulczycki')
author = scholarly.fill(next(search_query))
print(author)

# Print the titles of the author's publications
print([pub['bib']['title'] for pub in author['publications']])

# Take a closer look at the first publication
pub = scholarly.fill(author['publications'][0])
print(pub)

def get_author(Grzegorz_Kulczycki):
    # Retrieve the author's data, fill-in, and print
    search_query = scholarly.search_author(author_name)
    author = next(search_query).fill()
    return author