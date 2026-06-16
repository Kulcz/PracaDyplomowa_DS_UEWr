from semanticscholar import SemanticScholar
sch = SemanticScholar()
results = sch.search_paper('elemental sulphur fertilization')
counter = 1
print("Wyniki wyszukiwania 10 pierwszych rekordów: ")
for index, item in enumerate(results):
    # Print the number and title of the paper
    print(f"{index+1}. {item.title}")
    counter += 1
    if counter > 10:
        break
