from semanticscholar import SemanticScholar
# Ustaw klucz API
api_key = "prvXStDFku731CaJlUdWXa0aJtFKCOCU1FbdGCMs"
# Utwórz obiekt SemanticScholar z użyciem klucza API
sch = SemanticScholar(api_key=api_key)
# Zdefiniuj zapytanie
query = 'elemental sulphur fertilizer'
# Przeszukaj bazę danych Semantic Scholar
results = sch.search_paper(query)
# Wyświetl pierwsze 5 wyników
print(f'{results.total} results.')
print("First 5 occurrences:")
if results.total > 0:
    for i, paper in enumerate(results[:5], 1):
        authors = [author.name for author in paper.authors]
        print(f"{i}. Title: {paper.title}")
        print(f"    Authors: {', '.join(authors)}")
        print(f"    Year: {paper.year}")