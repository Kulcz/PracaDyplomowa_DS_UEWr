# komunikaty po angielsku
Sys.setenv(LANG = "en")

# Pakiety 
library(tidyverse)
# opcje theme dla ggplot
# https://benjaminlouis-stat.fr/en/blog/2020-05-21-astuces-ggplot-rmarkdown/
library(ggplot2)
theme_ben <- function(base_size = 14) {
  theme_bw(base_size = base_size) %+replace%
    theme(
      # tytul
      plot.title = element_text(size = 16, colour = "#7F3D17", face = "bold", margin = margin(0,0,5,0), hjust = 0.5),
      # Obszar, w którym znajduje się wykres
      panel.grid.minor = element_blank(),
      panel.border = element_blank(),
      # Osie
      axis.title = element_text(size = 14, face = "plain"),
      axis.text = element_text(size = 14, face = "plain"),
      axis.line = element_line(color = "black", arrow = arrow(length = unit(0.3, "lines"), type = "closed")),
      axis.title.x = element_text(size = 14),
      axis.title.y = element_text(size = 14, angle = 90),
      # Legenda
      legend.title = element_text(size = 14, face = "bold"),
      legend.text = element_text(size = 14, face = "bold"),
      legend.key = element_rect(fill = "transparent", colour = NA),
      legend.key.size = unit(1.5, "lines"),
      legend.background = element_rect(fill = "transparent", colour = NA),
      # Etykiety w przypadku fasetowania
      strip.background = element_rect(fill = "#17252D", color = "#17252D"),
      strip.text = element_text(size = 12, face = "bold", color = "white", margin = margin(5,0,5,0)))}
# Changing the default theme
theme_set(theme_ben())
library(reader)
library(rio)
library(agricolae)
library(corrplot)
library(RColorBrewer)
library(gridExtra)
library(openxlsx)
library(ragg)#graphic devices for R based on the AGG https://ragg.r-lib.org/
library(PerformanceAnalytics)
library(car)
library(devtools)
library(statxp)#install_github('Cogitos/statxp')
library(xtable)
library(Hmisc)
library(htmltools) #install.packages("htmltools")
library(mlmCorrs) #devtools::install_github("bbjonz/mlmCorrs")
library(htmlTable)
library(ggpmisc)
library(ggpubr)
library(ggthemes)
library(kableExtra)
library(flextable)
library(reshape2)
library(patchwork)
library(psych)

# odczytanie danych z pliku Excela
smolice <- import("Dane/2023_Smolice_wszystkie_odmiany.xlsx")
names(smolice)

# #wybor doswiadczenia
# smolice <- smolice %>% filter(id == "id_4")
# smolice

# wybór zmiennych ilościowych do analizy !!!
tabela_sm_SAVI <- smolice %>% select(sucha_masa, SAVI_22_05_2023, SAVI_29_06_2023, 
                                          SAVI_04_07_2023, SAVI_18_08_2023, SAVI_25_08_2023, 
                                          SAVI_01_09_2023, SAVI_21_09_2023)
tabela_sm_SAVI

# charakterystyka zmiennych
zmienne_opis_SAVI <- psych::describe(tabela_sm_SAVI) 
zmienne_opis_SAVI <- as.data.frame(zmienne_opis_SAVI ) %>% 
                    rownames_to_column() %>% 
                    mutate_if(is.numeric, ~round(., 2))
colnames(zmienne_opis_SAVI)[colnames(zmienne_opis_SAVI) == 'rowname'] <- 'Zmienna'
zmienne_opis_SAVI


zmienne_opis_SAVI <- flextable(zmienne_opis_SAVI)
zmienne_opis_SAVI <- autofit(zmienne_opis_SAVI)
zmienne_opis_SAVI <- bg(zmienne_opis_SAVI, j = "Zmienna", bg = "deepskyblue1", part = "all")
zmienne_opis_SAVI <- bg(zmienne_opis_SAVI, bg = "wheat", part = "header") 
zmienne_opis_SAVI <- delete_columns(zmienne_opis_SAVI, j = c("trimmed", "mad", "vars", "skew", "kurtosis", "se"))
zmienne_opis_SAVI



# wizualizacja zmiennych

SM_boxplot_SAVI <- tabela_sm_SAVI %>% select(sucha_masa)

SM_boxplot_SAVI <- ggplot(data = SM_boxplot_SAVI, aes(y = sucha_masa)) + 
                  geom_boxplot(color="blue", fill="orange", alpha=0.2) + 
                  scale_x_discrete() +
                  labs(title = "Sucha masa w kukurydzy", y = "%")
SM_boxplot_SAVI


rys_boxplot_SAVI <- tabela_sm_SAVI %>% select(-sucha_masa)

SAVI_boxplot <- ggplot(data = melt(rys_boxplot_SAVI), aes(x = variable, y = value)) +
               geom_boxplot(aes(fill=variable))+
               labs(x = "") +
               labs(y = "") +
  theme(axis.text.x = element_text(face="bold", 
                     color="#993333", size=12, angle = 90),
                     legend.position="none")
SAVI_boxplot


# rysunki regresji dla suchej masy i wskaźnika roślinnego

gg_SAVI_22_05_2023 <- ggplot(data =tabela_sm_SAVI, aes(y = sucha_masa, x = SAVI_22_05_2023))+
                     geom_point(size=2, col= "blue")+
                     geom_smooth(method="lm", se=TRUE, fullrange=TRUE, level=0.95)+
                     stat_cor(label.y = 48, size = 5) +
                     stat_regline_equation(label.y = 47, size = 5) +
                     labs(x="SAVI") +
                     labs(y="sucha masa (%)") +
                     ggtitle("SAVI_22_05_2023")+
                     theme_ben() 
gg_SAVI_22_05_2023



gg_SAVI_29_06_2023 <- ggplot(data =tabela_sm_SAVI, aes(y = sucha_masa, x = SAVI_29_06_2023))+
                     geom_point(size=2, col= "blue")+
                     geom_smooth(method="lm", se=TRUE, fullrange=TRUE, level=0.95)+
                     stat_cor(label.y = 48, size = 5) +
                     stat_regline_equation(label.y = 47, size = 5) +
                     labs(x="SAVI") +
                     labs(y="sucha masa (%)") +
                     ggtitle("SAVI_29_06_2023") +
                     theme_ben()
gg_SAVI_29_06_2023


gg_SAVI_04_07_2023 <- ggplot(data =tabela_sm_SAVI, aes(y = sucha_masa, x = SAVI_04_07_2023))+
                     geom_point(size=2, col= "blue")+
                     geom_smooth(method="lm", se=TRUE, fullrange=TRUE, level=0.95)+
                     stat_cor(label.y = 48, size = 5) +
                     stat_regline_equation(label.y = 47, size = 5) +
                     labs(x="SAVI") +
                     labs(y="sucha masa (%)") +
                     ggtitle("SAVI_04_07_2023") +
                     theme_ben()
gg_SAVI_04_07_2023


gg_SAVI_18_08_2023 <- ggplot(data =tabela_sm_SAVI, aes(y = sucha_masa, x = SAVI_18_08_2023))+
                     geom_point(size=2, col= "blue")+
                     geom_smooth(method="lm", se=TRUE, fullrange=TRUE, level=0.95)+
                     stat_cor(label.y = 48, size = 5) +
                     stat_regline_equation(label.y = 47, size = 5) +
                     labs(x="SAVI") +
                     labs(y="sucha masa (%)")+
                     ggtitle("SAVI_18_08_2023") +
                     theme_ben()
gg_SAVI_18_08_2023


gg_SAVI_25_08_2023 <- ggplot(data =tabela_sm_SAVI, aes(y = sucha_masa, x = SAVI_25_08_2023))+
                     geom_point(size=2, col= "blue")+
                     geom_smooth(method="lm", se=TRUE, fullrange=TRUE, level=0.95)+
                     stat_cor(label.y = 48, size = 5) +
                     stat_regline_equation(label.y = 47, size = 5) +
                     labs(x="SAVI") +
                     labs(y="sucha masa (%)") +
                     ggtitle("SAVI_25_08_2023") +
                     theme_ben()
gg_SAVI_25_08_2023


gg_SAVI_01_09_2023 <- ggplot(data =tabela_sm_SAVI, aes(y = sucha_masa, x = SAVI_01_09_2023))+
                     geom_point(size=2, col= "blue")+
                     geom_smooth(method="lm", se=TRUE, fullrange=TRUE, level=0.95)+
                     stat_cor(label.y = 48, size = 5) +
                     stat_regline_equation(label.y = 47, size = 5) +
                     labs(x="SAVI") +
                     labs(y="sucha masa (%)") +
                     ggtitle("SAVI_01_09_2023") +
                     theme_ben()
gg_SAVI_01_09_2023


gg_SAVI_21_09_2023 <- ggplot(data = tabela_sm_SAVI, aes(y = sucha_masa, x = SAVI_21_09_2023))+
                     geom_point(size=2, col= "blue")+
                     geom_smooth(method="lm", se=TRUE, fullrange=TRUE, level=0.95)+
                     stat_cor(label.y = 48, size = 5) +
                     stat_regline_equation(label.y = 47, size = 5) +
                     labs(x="SAVI") +
                     labs(y="sucha masa (%)")+
                     ggtitle("SAVI_21_09_2023") +
                     theme_ben()
gg_SAVI_21_09_2023 

# obliczenie korelacji za pomocą  funkcji chart.correlation
names(tabela_sm_SAVI) <- c("sucha masa", "SAVI - 22.05.2023", "SAVI - 29.06.2023", "SAVI - 04.07.2023",
                                "SAVI - 18.08.2023", "SAVI -25.08.2023", "SAVI - 01.09.2023", "SAVI - 21.09.2023")

# jpeg(file="Rysunki/SAVI_id4_chart.jpeg", quality = 100, width= 20, height= 20, unit="cm", res = 200)
# chart.Correlation(tabela_sm_SAVI, histogram=TRUE, pch = "+", method = "pearson")
# dev.off()

# http://www.sthda.com/english/wiki/elegant-correlation-table-using-xtable-r-package
cor_sm_SAVI <- round(cor(tabela_sm_SAVI), 2)
cor_sm_SAVI

# Dolna i górna trójkątna część macierzy korelacji
# Aby uzyskać dolną lub górną część macierzy korelacji, można użyć funkcji R lower.tri() lub upper.tri(). 
# lower.tri(x, diag = FALSE)
# upper.tri(x, diag = FALSE)
# x: jest macierzą korelacji - diag: jeśli TRUE, przekątna nie jest uwzględniana w wyniku.

upper.tri(cor_sm_SAVI)

# Ukryj górny trójkąt
upper_SAVI <- cor_sm_SAVI
upper_SAVI[upper.tri(cor_sm_SAVI)] <- " "
upper_SAVI <- as.data.frame(upper_SAVI)
upper_SAVI


tabela <- xtable(upper_SAVI)
htmlTable(tabela)

# Funkcja corstars

# x is a matrix containing the data
# method : correlation method. "pearson"" or "spearman"" is supported
# removeTriangle : remove upper or lower triangle
# results :  if "html" or "latex"
# the results will be displayed in html or latex format

corstars_SAVI <- function(x, method=c("pearson", "spearman"), removeTriangle=c("upper", "lower"),
                               result=c("none", "html", "latex")){
  #Compute correlation matrix
  require(Hmisc)
  x <- as.matrix(x)
  correlation_matrix<-rcorr(x, type=method[1])
  R <- correlation_matrix$r # Matrix of correlation coeficients
  p <- correlation_matrix$P # Matrix of p-value 
  
  ## Define notions for significance levels; spacing is important.
  mystars <- ifelse(p < .0001, "****", ifelse(p < .001, "*** ", ifelse(p < .01, "**  ", ifelse(p < .05, "*   ", "    "))))
  
  ## trunctuate the correlation matrix to two decimal
  R <- format(round(cbind(rep(-1.11, ncol(x)), R), 2))[,-1]
  
  ## build a new matrix that includes the correlations with their apropriate stars
  Rnew <- matrix(paste(R, mystars, sep=""), ncol=ncol(x))
  diag(Rnew) <- paste(diag(R), " ", sep="")
  rownames(Rnew) <- colnames(x)
  colnames(Rnew) <- paste(colnames(x), "", sep="")
  
  ## remove upper triangle of correlation matrix
  if(removeTriangle[1]=="upper"){
    Rnew <- as.matrix(Rnew)
    Rnew[upper.tri(Rnew, diag = TRUE)] <- ""
    Rnew <- as.data.frame(Rnew)
  }
  
  ## remove lower triangle of correlation matrix
  else if(removeTriangle[1]=="lower"){
    Rnew <- as.matrix(Rnew)
    Rnew[lower.tri(Rnew, diag = TRUE)] <- ""
    Rnew <- as.data.frame(Rnew)
  }
  
  ## remove last column and return the correlation matrix
  Rnew <- cbind(Rnew[1:length(Rnew)-1])
  if (result[1]=="none") return(Rnew)
  else{
    if(result[1]=="html") print(xtable(Rnew), type="html")
    else print(xtable(Rnew), type="latex") 
  }
} 

tabela_SAVI <- corstars_SAVI(tabela_sm_SAVI, method = "pearson") %>% 
              rownames_to_column()
colnames(tabela_SAVI)[colnames(tabela_SAVI) == 'rowname'] <- 'Macierz korelacji'
tabela_SAVI  
htmlTable(tabela_SAVI)


# tabela_SAVI <- corstars(tabela_sm_SAVI, method = "pearson") %>% 
#           rownames_to_column()
# colnames(tabela_SAVI)[colnames(tabela_SAVI) == 'rowname'] <- 'Macierz korelacji'
# tabela_SAVI
# htmlTable(tabela_SAVI)

tabela_flex_SAVI <- flextable(tabela_SAVI)
# tabela_flex <- autofit(tabela_flex)
tabela_flex_SAVI <- bg(tabela_flex_SAVI , j = "sucha masa", bg = "chartreuse3", part = "all")
tabela_flex_SAVI <- bold(tabela_flex_SAVI, j = "sucha masa", bold = TRUE, part = "body")
tabela_flex_SAVI <- bg(tabela_flex_SAVI , bg = "wheat", part = "header")
tabela_flex_SAVI <- footnote(x = tabela_flex_SAVI , i = 1:5, j = 1:5, ref_symbols = " ",
                  value = as_paragraph("Poziomy istotności: p < .0001 ‘****’; p < .001 ‘***’, p < .01 ‘**’, p < .05 ‘*’ "))
tabela_flex_SAVI

