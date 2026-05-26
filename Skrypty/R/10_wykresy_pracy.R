# LTeX: enabled=false
# ============================================================
# 10 - Finalne figury kompozytowe do pracy dyplomowej
# Strategia: nie liczymy nic od nowa, tylko wczytujemy artefakty
# RDS z 06-09 i renderujemy spójne figury do Wykresy/praca/.
# REFACTOR PENDING (2026-05-26): facet_grid metryka ~ dyscyplina ->
# metryka ~ stanowisko (lub uczelnia). Fig 1 (heatmap dyscyplina × uczelnia)
# zmienic na heatmap stanowisko × uczelnia. Fig 5 (community vs dyscyplina) ->
# community vs stanowisko.
# Każda figura = jedna obserwacja w pracy (1-2 panele max).
# Brak danego RDS -> dana figura jest pomijana (cat).
# ============================================================

library(dplyr)
library(tidyr)
library(ggplot2)
library(readr)
library(here)
library(fs)
library(patchwork)

OUT_DIR  <- here("output")
PLOT_DIR <- here("Wykresy", "praca"); dir_create(PLOT_DIR)

# ---------- Wspólne style ----------
theme_praca <- theme_minimal(base_size = 12) +
  theme(
    plot.title    = element_text(face = "bold", size = 13, margin = margin(b = 4)),
    plot.subtitle = element_text(color = "grey40", size = 10, margin = margin(b = 10)),
    strip.text    = element_text(face = "bold", size = 10),
    panel.grid.minor = element_blank(),
    plot.margin   = margin(8, 8, 8, 8)
  )

paleta_uczelnia <- c(upwr = "#3C5488", sggw = "#E64B35", urk = "#00A087", uwm = "#F39B7F")
paleta_stan <- c(
  "asystent" = "#999999", "adiunkt" = "#56B4E9",
  "profesor uczelni" = "#009E73", "profesor" = "#CC79A7"
)

# ---------- Helper: bezpieczne wczytanie ----------
try_load <- function(filename) {
  p <- file.path(OUT_DIR, filename)
  if (!file_exists(p)) { cat(sprintf("[SKIP] brak %s\n", p)); return(NULL) }
  readRDS(p)
}

eda     <- try_load("eda_summary.rds")
clust   <- try_load("clusters.rds")
mdl     <- try_load("model_results.rds")
net     <- try_load("network_metrics.rds")

# ============================================================
# Fig 1: Próba badawcza (n per komórka 3×4)
# ============================================================
if (!is.null(eda)) {
  n_komorka <- eda$opisowe %>%
    filter(metryka == metryka[1]) %>%   # unikatowy n per (dysc × ucz)
    select(dyscyplina, uczelnia, n)

  p1 <- ggplot(n_komorka, aes(x = uczelnia, y = dyscyplina, fill = n)) +
    geom_tile() +
    geom_text(aes(label = n), color = "white", fontface = "bold", size = 4) +
    scale_fill_gradient(low = "#9DB0CE", high = "#1F3864") +
    labs(title = "Liczebność próby (3 dyscypliny × 4 uczelnie)",
         x = NULL, y = NULL, fill = "n") +
    theme_praca

  ggsave(file.path(PLOT_DIR, "fig_01_proba.png"),
         p1, width = 8, height = 4.5, dpi = 300)
  cat("[OK] fig_01_proba.png\n")
}

# ============================================================
# Fig 2: Boxploty kluczowych metryk per dyscyplina × uczelnia
# (3 metryki — sum_IF, sum_MEiN, h_index_wos — w jednym panelu kompozytowym)
# ============================================================
if (!is.null(eda)) {
  # Reuse opisowe + cld_all do uproszczonych boxplotow
  # (alternatywa: wczytac df bezposrednio z profiles_features.csv)
  feat_path <- here("Dane", "master", "profiles_features.csv")
  if (file_exists(feat_path)) {
    df_feat <- read_csv(feat_path, show_col_types = FALSE) %>%
      mutate(
        uczelnia   = factor(uczelnia, levels = c("upwr","sggw","urk","uwm")),
        dyscyplina = factor(dyscyplina)
      )

    metryki_key <- c("sum_IF", "sum_MEiN", "h_index_wos")
    metryki_labs <- c(sum_IF = "Sumaryczny IF",
                      sum_MEiN = "Punktacja MEiN",
                      h_index_wos = "h-index (WoS)")

    df_long <- df_feat %>%
      pivot_longer(all_of(metryki_key), names_to = "metryka", values_to = "y") %>%
      filter(!is.na(y)) %>%
      mutate(metryka = factor(metryki_labs[metryka], levels = unname(metryki_labs)))

    p2 <- ggplot(df_long, aes(x = uczelnia, y = y, fill = uczelnia)) +
      geom_boxplot(outlier.size = 0.5, alpha = 0.85) +
      facet_grid(metryka ~ dyscyplina, scales = "free_y", switch = "y") +
      scale_fill_manual(values = paleta_uczelnia) +
      labs(title = "Metryki bibliometryczne: 3 dyscypliny × 4 uczelnie",
           x = NULL, y = NULL) +
      theme_praca +
      theme(legend.position = "none",
            strip.placement = "outside",
            axis.text.x = element_text(angle = 30, hjust = 1))

    ggsave(file.path(PLOT_DIR, "fig_02_metryki_box.png"),
           p2, width = 11, height = 9, dpi = 300)
    cat("[OK] fig_02_metryki_box.png\n")
  }
}

# ============================================================
# Fig 3: Klastrowanie (PCA biplot + centroidy)
# ============================================================
if (!is.null(clust)) {
  library(factoextra)

  p3a <- fviz_pca_ind(
    clust$pca,
    geom = "point",
    pointshape = 21, pointsize = 2,
    fill.ind = factor(clust$kmeans$cluster),
    palette = "Set2",
    addEllipses = TRUE, ellipse.type = "convex",
    legend.title = "Klaster"
  ) + labs(title = sprintf("PCA + klastry k-means (k = %d)", clust$k_opt)) +
      theme_praca

  centr_std <- as.data.frame(clust$kmeans$centers) %>%
    mutate(klaster = factor(seq_len(nrow(clust$kmeans$centers)))) %>%
    pivot_longer(-klaster, names_to = "cecha", values_to = "z")

  p3b <- ggplot(centr_std, aes(x = klaster, y = cecha, fill = z)) +
    geom_tile() +
    geom_text(aes(label = sprintf("%.1f", z)), size = 3) +
    scale_fill_gradient2(low = "#3C5488", mid = "white", high = "#E64B35", midpoint = 0) +
    labs(title = "Centroidy klastrów (z-score)",
         x = "Klaster", y = NULL, fill = "z") +
    theme_praca

  ggsave(file.path(PLOT_DIR, "fig_03_klastrowanie.png"),
         p3a + p3b + plot_layout(widths = c(1.4, 1)),
         width = 13, height = 6, dpi = 300)
  cat("[OK] fig_03_klastrowanie.png\n")
}

# ============================================================
# Fig 4: Modele predykcyjne (ROC + VIP)
# ============================================================
if (!is.null(mdl)) {
  library(yardstick)
  # ROC z stored fits — odtworzony z conf_mat$rf nie wystarcza, więc używamy test_metrics
  # i wyciągamy curves z fit_rf/fit_xgb (potrzeba train/test split — pomijamy reuse).
  # Najprościej: bar plot z test_metrics (model × metric).
  metrics_long <- mdl$test_metrics %>%
    filter(.metric %in% c("roc_auc", "accuracy", "sens", "spec"))

  p4a <- ggplot(metrics_long, aes(x = .metric, y = .estimate, fill = model)) +
    geom_col(position = "dodge") +
    geom_text(aes(label = sprintf("%.2f", .estimate)),
              position = position_dodge(width = 0.9),
              vjust = -0.4, size = 3.2) +
    scale_fill_manual(values = c(RF = "#3C5488", XGB = "#E64B35")) +
    ylim(0, 1.05) +
    labs(title = "Metryki test set: RF vs XGBoost",
         x = NULL, y = "Wartość", fill = "Model") +
    theme_praca

  p4b <- mdl$vip_rf %>% slice_max(Importance, n = 10) %>%
    ggplot(aes(x = reorder(Variable, Importance), y = Importance)) +
    geom_col(fill = "#3C5488") + coord_flip() +
    labs(title = "RF: ważność permutacyjna (top 10)",
         x = NULL, y = "Importance") +
    theme_praca

  ggsave(file.path(PLOT_DIR, "fig_04_modele.png"),
         p4a + p4b + plot_layout(widths = c(1, 1.2)),
         width = 13, height = 5.5, dpi = 300)
  cat("[OK] fig_04_modele.png\n")
}

# ============================================================
# Fig 5: Sieć współautorstwa (Louvain) + heatmap zgodności
# ============================================================
if (!is.null(net)) {
  library(igraph); library(tidygraph); library(ggraph)

  tg <- as_tbl_graph(net$graph)

  p5a <- ggraph(tg, layout = "stress") +
    geom_edge_link(alpha = 0.1, color = "grey40") +
    geom_node_point(aes(color = factor(community), size = degree),
                    show.legend = FALSE) +
    scale_size(range = c(0.3, 4)) +
    labs(title = sprintf("Sieć współautorstwa (Q = %.3f)", net$modularity)) +
    theme_void(base_size = 12) +
    theme(plot.title = element_text(face = "bold", size = 13))

  ct <- net$crosstabs$dysc %>% as.data.frame()
  p5b <- ggplot(ct, aes(x = dyscyplina, y = factor(community), fill = pct)) +
    geom_tile() +
    geom_text(aes(label = sprintf("%.0f%%", 100 * pct)), size = 3) +
    scale_fill_gradient(low = "white", high = "#3C5488") +
    labs(title = sprintf("Społeczność × dyscyplina (ARI = %.3f)", net$ari$dysc),
         x = NULL, y = "Społeczność", fill = "%") +
    theme_praca +
    theme(axis.text.x = element_text(angle = 30, hjust = 1))

  ggsave(file.path(PLOT_DIR, "fig_05_siec.png"),
         p5a + p5b + plot_layout(widths = c(1.4, 1)),
         width = 14, height = 7, dpi = 300)
  cat("[OK] fig_05_siec.png\n")
}

# ============================================================
# Fig 6 (opcjonalna): Composite summary 2×2 — jeśli wszystko jest
# ============================================================
have_all <- !is.null(eda) && !is.null(clust) && !is.null(mdl) && !is.null(net)
if (have_all) {
  # Jeśli wszystkie 4 RDS są, to powyższe figury są w pamięci.
  # Composite 2x2 byłby zbyt zaganiany — pomijamy. Zostawiamy 5 osobnych figur.
  cat("[INFO] wszystkie 4 RDS dostępne — composite 2x2 pominięty (5 osobnych figur jest czytelniejsze)\n")
}

cat(sprintf("\nWykresy zapisane: %s\n", PLOT_DIR))
