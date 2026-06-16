import s2
from requests import Session

session = Session()
session.headers = {'x-api-key': "prvXStDFku731CaJlUdWXa0aJtFKCOCU1FbdGCMs"}
pid = "10.3390/agronomy12051076"
paper = s2.api.get_paper(paperId=pid, session=session)
author = s2.api.get_author(authorId="113275711")
print(paper)
print(author)
# paper = s2.api.get_paper(paperId=pid, api_key = "prvXStDFku731CaJlUdWXa0aJtFKCOCU1FbdGCMs")

paperIds = [p.paperId for p in author.papers]
papers = []
for pid in paperIds:
    paper = s2.api.get_paper(
        paperId=pid,
        retries=2,
        wait=150,
        params=dict(include_unknown_references=True)
    )
    papers += [paper]
    print(papers)