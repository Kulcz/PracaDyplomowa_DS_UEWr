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

#wybor doswiadczenia
smolice <- smolice %>% filter(id == "id_5")
smolice

# wybór zmiennych ilościowych do analizy !!!
tabela_sm_NDVI <- smolice %>% select(sucha_masa, NDVI_22_05_2023, NDVI_29_06_2023, 
                                          NDVI_04_07_2023, NDVI_18_08_2023, NDVI_25_08_2023, 
                                          NDVI_01_09_2023, NDVI_21_09_2023)
tabela_sm_NDVI

# charakterystyka zmiennych
zmienne_opis_NDVI <- psych::describe(tabela_sm_NDVI) 
zmienne_opis_NDVI <- as.data.frame(zmienne_opis_NDVI ) %>% 
                    rownames_to_column() %>% 
                    mutate_if(is.numeric, ~round(., 2))
colnames(zmienne_opis_NDVI)[colnames(zmienne_opis_NDVI) == 'rowname'] <- 'Zmienna'
zmienne_opis_NDVI


zmienne_opis_NDVI <- flextable(zmienne_opis_NDVI)
zmienne_opis_NDVI <- autofit(zmienne_opis_NDVI)
zmienne_opis_NDVI <- bg(zmienne_opis_NDVI, j = "Zmienna", bg = "deepskyblue1", part = "all")
zmienne_opis_NDVI <- bg(zmienne_opis_NDVI, bg = "wheat", part = "header") 
zmienne_opis_NDVI <- delete_columns(zmienne_opis_NDVI, j = c("trimmed", "mad", "vars", "skew", "kurtosis", "se"))
zmienne_opis_NDVI



# wizualizacja zmiennych

SM_boxplot_NDVI <- tabela_sm_NDVI %>% select(sucha_masa)

SM_boxplot_NDVI <- ggplot(data = SM_boxplot_NDVI, aes(y = sucha_masa)) + 
                  geom_boxplot(color="blue", fill="orange", alpha=0.2) + 
                  scale_x_discrete() +
                  labs(title = "Sucha masa w kukurydzy", y = "%")
SM_boxplot_NDVI


rys_boxplot_NDVI <- tabela_sm_NDVI %>% select(-sucha_masa)

NDVI_boxplot <- ggplot(data = melt(rys_boxplot_NDVI), aes(x = variable, y = value)) +
               geom_boxplot(aes(fill=variable))+
               labs(x = "") +
               labs(y = "") +
  theme(axis.text.x = element_text(face="bold", 
                     color="#993333", size=12, angle = 90),
                     legend.position="none")
NDVI_boxplot


# rysunki regresji dla suchej masy i wskaźnika roślinnego

gg_NDVI_22_05_2023 <- ggplot(data =tabela_sm_NDVI, aes(y = sucha_masa, x = NDVI_22_05_2023))+
                     geom_point(size=2, col= "blue")+
                     geom_smooth(method="lm", se=TRUE, fullrange=TRUE, level=0.95)+
                     stat_cor(label.y = 48, size = 5) +
                     stat_regline_equation(label.y = 47, size = 5) +
                     labs(x="NDVI") +
                     labs(y="sucha masa (%)") +
                     ggtitle("NDVI_22_05_2023")+
                     theme_ben() 
gg_NDVI_22_05_2023



gg_NDVI_29_06_2023 <- ggplot(data =tabela_sm_NDVI, aes(y = sucha_masa, x = NDVI_29_06_2023))+
                     geom_point(size=2, col= "blue")+
                     geom_smooth(method="lm", se=TRUE, fullrange=TRUE, level=0.95)+
                     stat_cor(label.y = 48, size = 5) +
                     stat_regline_equation(label.y = 47, size = 5) +
                     labs(x="NDVI") +
                     labs(y="sucha masa (%)") +
                     ggtitle("NDVI_29_06_2023") +
                     theme_ben()
gg_NDVI_29_06_2023


gg_NDVI_04_07_2023 <- ggplot(data =tabela_sm_NDVI, aes(y = sucha_masa, x = NDVI_04_07_2023))+
                     geom_point(size=2, col= "blue")+
                     geom_smooth(method="lm", se=TRUE, fullrange=TRUE, level=0.95)+
                     stat_cor(label.y = 48, size = 5) +
                     stat_regline_equation(label.y = 47, size = 5) +
                     labs(x="NDVI") +
                     labs(y="sucha masa (%)") +
                     ggtitle("NDVI_04_07_2023") +
                     theme_ben()
gg_NDVI_04_07_2023


gg_NDVI_18_08_2023 <- ggplot(data =tabela_sm_NDVI, aes(y = sucha_masa, x = NDVI_18_08_2023))+
                     geom_point(size=2, col= "blue")+
                     geom_smooth(method="lm", se=TRUE, fullrange=TRUE, level=0.95)+
                     stat_cor(label.y = 48, size = 5) +
                     stat_regline_equation(label.y = 47, size = 5) +
                     labs(x="NDVI") +
                     labs(y="sucha masa (%)")+
                     ggtitle("NDVI_18_08_2023") +
                     theme_ben()
gg_NDVI_18_08_2023


gg_NDVI_25_08_2023 <- ggplot(data =tabela_sm_NDVI, aes(y = sucha_masa, x = NDVI_25_08_2023))+
                     geom_point(size=2, col= "blue")+
                     geom_smooth(method="lm", se=TRUE, fullrange=TRUE, level=0.95)+
                     stat_cor(label.y = 48, size = 5) +
                     stat_regline_equation(label.y = 47, size = 5) +
                     labs(x="NDVI") +
                     labs(y="sucha masa (%)") +
                     ggtitle("NDVI_25_08_2023") +
                     theme_ben()
gg_NDVI_25_08_2023


gg_NDVI_01_09_2023 <- ggplot(data =tabela_sm_NDVI, aes(y = sucha_masa, x = NDVI_01_09_2023))+
                     geom_point(size=2, col= "blue")+
                     geom_smooth(method="lm", se=TRUE, fullrange=TRUE, level=0.95)+
                     stat_cor(label.y = 48, size = 5) +
                     stat_regline_equation(label.y = 47, size = 5) +
                     labs(x="NDVI") +
                     labs(y="sucha masa (%)") +
                     ggtitle("NDVI_01_09_2023") +
                     theme_ben()
gg_NDVI_01_09_2023


gg_NDVI_21_09_2023 <- ggplot(data = tabela_sm_NDVI, aes(y = sucha_masa, x = NDVI_21_09_2023))+
                     geom_point(size=2, col= "blue")+
                     geom_smooth(method="lm", se=TRUE, fullrange=TRUE, level=0.95)+
                     stat_cor(label.y = 48, size = 5) +
                     stat_regline_equation(label.y = 47, size = 5) +
                     labs(x="NDVI") +
                     labs(y="sucha masa (%)")+
                     ggtitle("NDVI_21_09_2023") +
                     theme_ben()
gg_NDVI_21_09_2023 

# obliczenie korelacji za pomocą  funkcji chart.correlation
names(tabela_sm_NDVI) <- c("sucha masa", "NDVI - 22.05.2023", "NDVI - 29.06.2023", "NDVI - 04.07.2023",
                                "NDVI - 18.08.2023", "NDVI -25.08.2023", "NDVI - 01.09.2023", "NDVI - 21.09.2023")

# jpeg(file="Rysunki/NDVI_id4_chart.jpeg", quality = 100, width= 20, height= 20, unit="cm", res = 200)
# chart.Correlation(tabela_sm_NDVI, histogram=TRUE, pch = "+", method = "pearson")
# dev.off()

# http://www.sthda.com/english/wiki/elegant-correlation-table-using-xtable-r-package
cor_sm_NDVI <- round(cor(tabela_sm_NDVI), 2)
cor_sm_NDVI

# Dolna i górna trójkątna część macierzy korelacji
# Aby uzyskać dolną lub górną część macierzy korelacji, można użyć funkcji R lower.tri() lub upper.tri(). 
# lower.tri(x, diag = FALSE)
# upper.tri(x, diag = FALSE)
# x: jest macierzą korelacji - diag: jeśli TRUE, przekątna nie jest uwzględniana w wyniku.

upper.tri(cor_sm_NDVI)

# Ukryj górny trójkąt
upper_NDVI <- cor_sm_NDVI
upper_NDVI[upper.tri(cor_sm_NDVI)] <- " "
upper_NDVI <- as.data.frame(upper_NDVI)
upper_NDVI


tabela <- xtable(upper_NDVI)
htmlTable(tabela)

# Funkcja corstars

# x is a matrix containing the data
# method : correlation method. "pearson"" or "spearman"" is supported
# removeTriangle : remove upper or lower triangle
# results :  if "html" or "latex"
# the results will be displayed in html or latex format

corstars_NDVI <- function(x, method=c("pearson", "spearman"), removeTriangle=c("upper", "lower"),
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

tabela_NDVI <- corstars_NDVI(tabela_sm_NDVI, method = "pearson") %>% 
              rownames_to_column()
colnames(tabela_NDVI)[colnames(tabela_NDVI) == 'rowname'] <- 'Macierz korelacji'
tabela_NDVI  
htmlTable(tabela_NDVI)


# tabela_NDVI <- corstars(tabela_sm_NDVI, method = "pearson") %>% 
#           rownames_to_column()
# colnames(tabela_NDVI)[colnames(tabela_NDVI) == 'rowname'] <- 'Macierz korelacji'
# tabela_NDVI
# htmlTable(tabela_NDVI)

tabela_flex_NDVI <- flextable(tabela_NDVI)
# tabela_flex <- autofit(tabela_flex)
tabela_flex_NDVI <- bg(tabela_flex_NDVI , j = "sucha masa", bg = "chartreuse3", part = "all")
tabela_flex_NDVI <- bold(tabela_flex_NDVI, j = "sucha masa", bold = TRUE, part = "body")
tabela_flex_NDVI <- bg(tabela_flex_NDVI , bg = "wheat", part = "header")
tabela_flex_NDVI <- footnote(x = tabela_flex_NDVI , i = 1:5, j = 1:5, ref_symbols = " ",
                  value = as_paragraph("Poziomy istotności: p < .0001 ‘****’; p < .001 ‘***’, p < .01 ‘**’, p < .05 ‘*’ "))
tabela_flex_NDVI

