# LTeX: enabled=false
# ============================================================
# 06 - EDA + statystyka klasyczna (warstwa 1 z planu DS)
# Cel: opis, rozklady, korelacje, 2-czynnikowa ANOVA/KW (dyscyplina x uczelnia)
# Input:  Dane/master/profiles_features.csv
# Output: Wykresy/eda/*.png, output/eda_summary.rds
# ============================================================

library(dplyr)
library(tidyr)
library(ggplot2)
library(readr)
library(here)
library(emmeans)
library(multcomp)
library(multcompView)
library(car)
library(dunn.test)

df <- read_csv(here("Dane", "master", "profiles_features.csv"), show_col_types = FALSE)

# ---------- 1. Statystyki opisowe per dyscyplina x uczelnia ----------
metryki <- c("h_index_wos", "sum_IF", "sum_MEiN", "if_per_pub", "if_to_mein")
# TODO: tabela srednia/mediana/SD per komorka macierzy

# ---------- 2. Rozklady + korelacje ----------
# TODO: histogramy fasetowane (dyscyplina), heatmapa korelacji

# ---------- 3. 2-czynnikowa ANOVA / model mieszany ----------
# Reuse wzorzec z UPWr_bibliometria/Skrypty/R/02_czyszczenie_analiza_WPT.R:195-295
# Diagnostyka Shapiro-Wilk + Levene -> auto-wybor (ANOVA vs KW + Dunn)
# Dla 2 czynnikow: aov(metryka ~ stanowisko * dyscyplina) lub equivalent KW per komorka
# CLD z literami grup jednorodnych (multcompLetters)

cat("TODO: implementacja warstwy 1 (tydzien 6 harmonogramu)\n")
