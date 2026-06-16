#wymagane bibloteki
library(scholar)
library(tidyverse)
library(ggplot2)

# id  użytkowników
Kulczycki <- "RNDE9-wAAAAJ&hl"  
Sacala <- "jkj3pCQAAAAJ&hl" 
Lejcus <- "XNRUNHsAAAAJ&hl" 
Pietr <- "L6MYKCQAAAAJ&hl" 

# Ile artykułów opublikowali?
Kulczycki.num <- get_num_articles(Kulczycki)
Sacala.num <- get_num_articles(Sacala)
Lejcus.num <- get_num_articles(Lejcus)
Pietr.num <- get_num_articles(Pietr)

# utworzenie ramki danych
num <- data.frame (Ilosc = c(Kulczycki.num, 
                             Sacala.num, 
                             Lejcus.num, 
                             Pietr.num),
                   Osoba= c("Kulczycki", "Sacala", "Lejcus", "Pietr"))

# wizualizacja ilości cytowań
ggplot(num, aes(x=Osoba, y=Ilosc, fill = Osoba)) + 
  geom_col()+
  theme_bw() + 
  scale_fill_brewer(palette = "BrBG")+
  geom_text(aes(label=Ilosc),position=position_stack(vjust=1.1),size=6)+
  theme( plot.title = element_text(size=14, hjust = 0.5),
         legend.position='none',
         axis.title.x=element_blank(),
         axis.text.x = element_text(face="bold", color="#993333", size=14),
         axis.text.y = element_text(size = 14),
         axis.title.y = element_text(size = 14))

