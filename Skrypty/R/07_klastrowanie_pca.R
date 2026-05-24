# LTeX: enabled=false
# ============================================================
# 07 - Warstwa 2 z planu DS: PCA + klastrowanie
# Cel: typologia profili bibliometrycznych (k-means + walidacja silhouette/gap)
# Input:  Dane/master/profiles_features.csv
# Output: Wykresy/klastrowanie/*.png, output/clusters.rds
# ============================================================

library(dplyr)
library(tidyr)
library(ggplot2)
library(readr)
library(here)
library(FactoMineR)
library(factoextra)
library(cluster)

df <- read_csv(here("Dane", "master", "profiles_features.csv"), show_col_types = FALSE)

# Cechy do klastrowania (standaryzowane)
cechy_klaster <- c("h_index_wos", "sum_IF", "sum_MEiN", "if_per_pub", "if_to_mein")
X <- df %>%
  select(all_of(cechy_klaster)) %>%
  drop_na() %>%
  scale()

# ---------- 1. PCA ----------
# pca <- PCA(X, graph = FALSE)
# fviz_pca_biplot(pca, habillage = df$dyscyplina, ...)

# ---------- 2. Walidacja k (silhouette + gap statistic) ----------
# fviz_nbclust(X, kmeans, method = "silhouette", k.max = 10)
# fviz_nbclust(X, kmeans, method = "gap_stat", nstart = 25, k.max = 10)

# ---------- 3. K-means + interpretacja klastrow ----------
# km <- kmeans(X, centers = k_opt, nstart = 25)
# df$klaster <- km$cluster
# Profile klastrow: srednia kazdej cechy + interpretacja jakosciowa

# ---------- 4. Porownanie Ward hierarchical ----------
# hc <- hclust(dist(X), method = "ward.D2")
# fviz_dend(hc, k = k_opt)

# ---------- 5. chi2 niezaleznosci: klaster vs dyscyplina vs uczelnia ----------
# chisq.test(table(df$klaster, df$dyscyplina))

cat("TODO: implementacja warstwy 2 (tydzien 7 harmonogramu)\n")
