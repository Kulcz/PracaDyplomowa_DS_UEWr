

from semanticscholar import SemanticScholar
sch = SemanticScholar()
paper = sch.get_paper('10.1016/j.jafr.2024.101013')
paper.title
print(paper.title)