library(scholar)

id <- 'Gcf0uQ8AAAAJ&hl'

kulczycki <- get_profile(id)

kulczycki$name


# Compare Feynman and Stephen Hawking
ids <- c('Gcf0uQ8AAAAJ&hl', 'jkj3pCQAAAAJ&h')

# Get a data frame comparing the number of citations to their work in
# a given year 
compare_scholars(ids)

# Compare their career trajectories, based on year of first citation
compare_scholar_careers(ids)
plot(ids)


# Define the id for Richard Feynman
id <- 'B7vSqZsAAAAJ'

# Get his profile and print his name
l <- get_profile(id)
l$name 

# Get his citation history, i.e. citations to his work in a given year 
get_citation_history(id)

# Get his publications (a large data frame)
get_publications(id)

library(scholar)
coauthor_network <- get_coauthors('L6MYKCQAAAAJ')
plot_coauthors(coauthor_network, size_labels = 5)







