library(scholar)
library(tidyverse)
library(gridExtra)

Kulczycki <- "RNDE9-wAAAAJ&hl"  
Sacala <- "jkj3pCQAAAAJ&hl" 
Lejcus <- "XNRUNHsAAAAJ&hl" 
Pietr <- "L6MYKCQAAAAJ&hl" 

Kulczycki.profile <- get_profile(Kulczycki)
Sacala.profile <- get_profile(Sacala)
Lejcus.profile <- get_profile(Lejcus)
Pietr.profile <- get_profile(Pietr)

Kulczycki.profile
Sacala.profile
Lejcus.profile
Pietr.profile

# Ile artykułów opublikowali?
Kulczycki.num <- get_num_articles(Kulczycki)
Sacala.num <- get_num_articles(Sacala)
Lejcus.num <- get_num_articles(Lejcus)
Pietr.num <- get_num_articles(Pietr)


num <- data.frame (Ilosc  = c(Kulczycki.num, Sacala.num, Lejcus.num, Pietr.num),
                  Osoba= c("Kulczycki", "Sacala", "Lejcus", "Pietr"))

ggplot(num, aes(x=Osoba, y=Ilosc, col = Ilosc, fill = Osoba)) + 
            geom_col()+
            scale_fill_brewer(palette = "BrBG")+
            geom_text(aes(label=Ilosc), position = position_stack(vjust = 1.1), size=8)+
            theme( plot.title = element_text(size=14, hjust = 0.5),
                   axis.text.x = element_text(face="bold", color="#993333", size=14),
                   axis.title.x = element_text(size = 12),
                   axis.text.y = element_text(size = 14),
                   axis.title.y = element_text(size = 14))

##################################################################################


ids <- c("RNDE9-wAAAAJ&hl", "jkj3pCQAAAAJ&hl","L6MYKCQAAAAJ&hl" )
df <- compare_scholars(ids)
df <- na.omit(df)
p <- ggplot(df, aes(x=year, y=total, group = name)) + 
  geom_line(aes(colour = name, size= 0.01)) +
  scale_fill_brewer(palette = "BrBG")+
  geom_text(aes(label=total), size=3)+
  theme_bw() + 
  theme( plot.title = element_text(size=14, hjust = 0.5),
         legend.position="top",
         legend.title = element_text(colour="black", size=10, face="bold"),
         legend.text = element_text(colour="black", size=14,face="bold"),
         axis.text.x = element_text(face="bold", color="#993333", size=14),
         axis.title.x = element_text(size = 12),
         axis.text.y = element_text(size = 14),
         axis.title.y = element_text(size = 14))
p + guides(shape = guide_legend(override.aes = list(size = 5)))
p + guides(size = FALSE)


############################################################################

ids <- c("B7vSqZsAAAAJ", "qj74uXkAAAAJ")
df_2 <- compare_scholar_careers(ids)
df_2 <- na.omit(df_2)
p <- ggplot(df_2, aes(x=year, y=total, group = name)) + 
  geom_line(aes(colour = name, size= 0.01)) +
  scale_fill_brewer(palette = "BrBG")+
  geom_text(aes(label=total), size=3)+
  theme_bw() + 
  theme( plot.title = element_text(size=14, hjust = 0.5),
         legend.position="top",
         legend.title = element_text(colour="black", size=10, face="bold"),
         legend.text = element_text(colour="black", size=14,face="bold"),
         axis.text.x = element_text(face="bold", color="#993333", size=14),
         axis.title.x = element_text(size = 12),
         axis.text.y = element_text(size = 14),
         axis.title.y = element_text(size = 14))
p + guides(shape = guide_legend(override.aes = list(size = 5)))
p + guides(size = FALSE)



#########################################################################################################
library(scholar)
library(plyr)
library(ggplot2)

ids <- c("RNDE9-wAAAAJ&hl", "jkj3pCQAAAAJ&hl","L6MYKCQAAAAJ&hl" , "XNRUNHsAAAAJ&hl")
df_3 <- compare_scholar_careers(ids)

## Add cumulative citation
df_3 <- ddply(.data = df_3,
            .variables = c("id"),
            .fun = transform,
            cumulative_cites = cumsum(cites))
## Plot
p <- ggplot(df_3, aes(x = career_year, y = cumulative_cites)) +
  geom_line(aes(colour = name)) +
  scale_fill_brewer(palette = "BrBG")+
  geom_text(aes(label=cumulative_cites), size=3.5)+
  theme_bw()+
  theme( plot.title = element_text(size=14, hjust = 0.5),
         legend.position="top",
         legend.title = element_text(colour="black", size=8, face="bold"),
         legend.text = element_text(colour="black", size=11,face="bold"),
         axis.text.x = element_text(face="bold", color="#993333", size=14),
         axis.title.x = element_text(size = 12),
         axis.text.y = element_text(size = 14),
         axis.title.y = element_text(size = 14))
p + guides(shape = guide_legend(override.aes = list(size = 5)))
p + guides(size = FALSE)








