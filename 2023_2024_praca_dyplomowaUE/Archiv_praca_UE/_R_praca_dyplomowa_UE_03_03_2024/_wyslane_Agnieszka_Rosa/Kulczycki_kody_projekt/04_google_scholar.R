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
  geom_text(aes(label=cumulative_cites), size=3)+
  labs(y="Skumulowane cytowania")+
  labs(x="Lata pracy")+
  theme_bw()+
  theme( plot.title = element_text(size=14, hjust = 0.5),
         legend.position="top",
         legend.title = element_text(colour="black", size=8, face="bold"),
         legend.text = element_text(colour="black", size=8,face="bold"),
         axis.text.x = element_text(face="bold", color="#993333", size=14),
         axis.title.x = element_text(size = 12),
         axis.text.y = element_text(size = 12),
         axis.title.y = element_text(size = 12))
p + guides(size = FALSE)
