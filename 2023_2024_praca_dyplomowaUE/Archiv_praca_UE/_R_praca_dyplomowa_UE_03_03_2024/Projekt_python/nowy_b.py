import s2
from requests import Session

session = Session()
session.headers = {'x-api-key': "prvXStDFku731CaJlUdWXa0aJtFKCOCU1FbdGCMs"}

# Pobranie pierwszego autora
author1 = s2.api.get_author(authorId="113275711")
print("Author 1:")
print("Name:", author1.name)

paperIds1 = [p.paperId for p in author1.papers]

print("\nPapers for Author 1:")
papers_author1 = []
for pid in paperIds1:
    paper = s2.api.get_paper(
        paperId=pid,
        retries=2,
        wait=150,
        params=dict(include_unknown_references=True)
    )
    papers_author1.append(paper)

for i, paper in enumerate(papers_author1[:5]):  # Wyświetlenie tylko 5 pierwszych rekordów dla autora 1
    print(f"  {i+1}. Title:", paper.title)
    print("     Authors:", ", ".join(author.name for author in paper.authors))
    print()

print("Liczba wszystkich publikacji dla Author 1:", len(papers_author1))

# Pobranie drugiego autora
author2 = s2.api.get_author(authorId="12961311")
print("\nAuthor 2:")
print("Name:", author2.name)

paperIds2 = [p.paperId for p in author2.papers]

print("\nPapers for Author 2:")
papers_author2 = []
for pid in paperIds2:
    paper = s2.api.get_paper(
        paperId=pid,
        retries=2,
        wait=150,
        params=dict(include_unknown_references=True)
    )
    papers_author2.append(paper)

for i, paper in enumerate(papers_author2[:5]):  # Wyświetlenie tylko 5 pierwszych rekordów dla autora 2
    print(f"  {i+1}. Title:", paper.title)
    print("     Authors:", ", ".join(author.name for author in paper.authors))
    print()

print("Liczba wszystkich publikacji dla Author 2:", len(papers_author2))



