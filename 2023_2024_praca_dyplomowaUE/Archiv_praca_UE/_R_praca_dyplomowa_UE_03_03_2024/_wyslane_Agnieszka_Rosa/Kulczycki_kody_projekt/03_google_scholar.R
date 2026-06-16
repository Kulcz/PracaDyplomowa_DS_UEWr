library(scholar)
library(tidyverse)
library(ggplot2)
# id  użytkowników
ids <- c("RNDE9-wAAAAJ&hl", "jkj3pCQAAAAJ&hl",
         "L6MYKCQAAAAJ&hl","XNRUNHsAAAAJ&hl")
#utworzenie ramki danych
df <- compare_scholars(ids)
#usuniecie brakujących danych
df <- na.omit(df)
# wizualizacja ilości cytowań
p <- ggplot(df, aes(x=year, y=total, group = name)) + 
  geom_line(aes(colour = name)) +
  scale_fill_brewer(palette = "BrBG")+
  geom_text(aes(label=total), size = 2.5)+
  labs(y="Ilość cytowań")+
  labs(x="Lata")+
  theme_bw() + 
  theme( plot.title = element_text(size=14, hjust = 0.5),
         legend.position="top",
         legend.title = element_text(colour="black", size=8, face="bold"),
         legend.text = element_text(colour="black", size=8,face="bold"),
         axis.text.x = element_text(face="bold", color="#993333", size=14),
         axis.title.x = element_text(size = 12),
         axis.text.y = element_text(size = 12),
         axis.title.y = element_text(size = 12))
p + guides(size = none)
