# LTeX: enabled=false
# ============================================================
# 07b - Typologia rozszerzona: k-means k=3 (wariant eksploracyjny)
# Cel: sprawdzic, czy bogatsza typologia (k=3) ujawnia grupe "wschodzacych
#      gwiazd" (mala liczba publikacji, wysoka intensywnosc jakosciowa IF/pub).
# Uwaga: k=2 (07) pozostaje rozwiazaniem glownym (silhouette). To wariant
#      eksploracyjny z RECZNIE wymuszonym k=3.
# Input:  Dane/master/profiles_features.csv
# Output: output/klaster_profile_k3.csv, output/clusters_k3.rds,
#         Wykresy/klastrowanie/0{8,9}_k3_*.png
# ============================================================

library(dplyr)
library(tidyr)
library(ggplot2)
library(readr)
library(here)
library(fs)
library(factoextra)

set.seed(42)

df <- read_csv(here("Dane", "master", "profiles_features.csv"), show_col_types = FALSE)

cechy_klaster <- c("h_index_wos", "sum_IF", "if_per_pub", "n_pub")

df <- df %>%
  mutate(
    uczelnia   = factor(uczelnia, levels = c("upwr", "sggw", "urk", "uwm")),
    stanowisko = factor(stanowisko,
                        levels = c("asystent", "adiunkt", "profesor uczelni", "profesor"))
  ) %>%
  drop_na(all_of(cechy_klaster))

X <- df %>% select(all_of(cechy_klaster)) %>% scale()

PLOT_DIR <- here("Wykresy", "klastrowanie"); dir_create(PLOT_DIR)
OUT_DIR  <- here("output");                   dir_create(OUT_DIR)

K <- 3L
km <- kmeans(X, centers = K, nstart = 50, iter.max = 50)
df$klaster <- factor(km$cluster)

# Profile klastrow w skali oryginalnej + FWCI opisowo (post-hoc, nie cecha klastrowania)
profile <- df %>%
  group_by(klaster) %>%
  summarise(
    n = n(),
    across(all_of(cechy_klaster), ~ round(mean(.x, na.rm = TRUE), 2)),
    mean_fwci = round(mean(mean_fwci, na.rm = TRUE), 2),
    .groups = "drop"
  )
cat("=== Profile klastrow k=3 (skala oryginalna; mean_fwci opisowo) ===\n")
print(profile)
write_csv(profile, file.path(OUT_DIR, "klaster_profile_k3.csv"))

# Heatmapa centroidow (z-scores)
centr_std <- as.data.frame(km$centers) %>%
  mutate(klaster = factor(seq_len(nrow(km$centers)))) %>%
  pivot_longer(-klaster, names_to = "cecha", values_to = "z")
p_centroidy <- ggplot(centr_std, aes(x = klaster, y = cecha, fill = z)) +
  geom_tile() +
  geom_text(aes(label = sprintf("%.2f", z)), size = 3.5) +
  scale_fill_gradient2(low = "#3C5488", mid = "white", high = "#E64B35", midpoint = 0) +
  labs(title = "Centroidy klastrow (z-scores, k = 3)", x = "Klaster", y = NULL, fill = "z") +
  theme_minimal(base_size = 12)
ggsave(file.path(PLOT_DIR, "09_k3_centroidy_heatmap.png"), p_centroidy,
       width = 7, height = 5, dpi = 200)

# Klastry na PCA
p_clust <- fviz_cluster(list(data = X, cluster = km$cluster),
                        geom = "point", ellipse.type = "convex", palette = "Set2") +
  labs(title = "Klastry k-means (k = 3) w przestrzeni PC1-PC2")
ggsave(file.path(PLOT_DIR, "08_k3_kmeans_clusters.png"), p_clust,
       width = 9, height = 7, dpi = 200)

# Walidacja zewnetrzna
cramers_v <- function(tab) {
  chi <- suppressWarnings(chisq.test(tab)); n <- sum(tab); k <- min(dim(tab))
  sqrt(as.numeric(chi$statistic) / (n * (k - 1)))
}
ct_ucz  <- table(klaster = df$klaster, uczelnia = df$uczelnia)
df_stan <- df %>% filter(!is.na(stanowisko)) %>% mutate(stanowisko = droplevels(stanowisko))
ct_stan <- table(klaster = df_stan$klaster, stanowisko = df_stan$stanowisko)
cat("\n=== chi2 (k=3) klaster vs uczelnia / stanowisko ===\n")
cat(sprintf("vs uczelnia : V = %.3f (p = %.4g)\n",
            cramers_v(ct_ucz), suppressWarnings(chisq.test(ct_ucz))$p.value))
cat(sprintf("vs stanowisko: V = %.3f (p = %.4g)\n",
            cramers_v(ct_stan), suppressWarnings(chisq.test(ct_stan))$p.value))
print(ct_stan)

saveRDS(list(kmeans = km, df = df, profile = profile,
             cramers_v = list(ucz = cramers_v(ct_ucz), stan = cramers_v(ct_stan))),
        file.path(OUT_DIR, "clusters_k3.rds"))
cat("\nZapisano: output/klaster_profile_k3.csv, output/clusters_k3.rds, Wykresy/klastrowanie/0{8,9}_k3_*.png\n")
