# LTeX: enabled=false
# ============================================================
# 10 - Finalne figury kompozytowe do pracy dyplomowej
# Strategia: nie liczymy nic od nowa, tylko wczytujemy artefakty
# RDS z 06-09 i renderujemy spójne figury do Wykresy/praca/.
#
# Decyzje metodyczne (2026-06-13):
#  - Zmienna grupujaca: stanowisko / uczelnia (dyscyplina usunieta).
#  - (fig_01 'proba analityczna' usunieta 2026-06-16: dublowala Tabele 1 w pracy
#    i liczyla n warunkowo na h_index_wos, co rozjezdzalo sie z pelnym n tabeli.)
#  - Fig 2: metryki pelnego pokrycia (h_index_wos, sum_IF, n_pub), bez sum_MEiN
#    (SGGW=NA); facet metryka ~ uczelnia, os = stanowisko.
#  - Fig 5: community × uczelnia (ARI/NMI uczelnia to glowny wynik warstwy 4).
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

STANOWISKA <- c("adiunkt", "profesor uczelni", "profesor")

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
  "adiunkt" = "#91D1C2", "profesor uczelni" = "#4DBBD5", "profesor" = "#3C5488"
)
stan_labs <- c(adiunkt = "adiunkt", `profesor uczelni` = "prof. ucz.", profesor = "profesor")

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
# Fig 2 (a-c): Boxploty metryk pelnego pokrycia, OSOBNO per metryka
#   (uczelnia x stanowisko). 3 osobne pliki -> czytelniej + latwiejsze
#   formatowanie pracy (kazda figura wstawiana niezaleznie).
#   Litery CLD (z eda_summary.rds, Dunn-Bonferroni; skrypt 06):
#     male (nad)  = stanowiska w obrebie uczelni      (cld_within)
#     DUZE (pod)  = uczelnie w obrebie stanowiska      (cld_ucz_within)
#   Wspolna litera = brak istotnej roznicy.
# ============================================================
feat_path <- here("Dane", "master", "profiles_features.csv")
if (file_exists(feat_path)) {
  df_feat <- read_csv(feat_path, show_col_types = FALSE) %>%
    mutate(
      uczelnia   = factor(uczelnia, levels = c("upwr","sggw","urk","uwm")),
      stanowisko = factor(stanowisko, levels = STANOWISKA)
    ) %>%
    filter(!is.na(stanowisko))

  metryki_labs <- c(h_index_wos = "h-index (WoS)", sum_IF = "Sumaryczny IF",
                    n_pub = "Liczba publikacji")
  fig_files <- c(h_index_wos = "fig_02a_hindex.png", sum_IF = "fig_02b_sumif.png",
                 n_pub = "fig_02c_npub.png")
  ucz_labs <- c(upwr = "UPWr", sggw = "SGGW", urk = "URK", uwm = "UWM")
  DODGE <- 0.8

  for (mk in names(metryki_labs)) {
    mlab <- metryki_labs[[mk]]
    d1 <- df_feat %>% filter(!is.na(.data[[mk]])) %>%
      transmute(uczelnia, stanowisko, y = .data[[mk]])

    # male litery: stanowiska w obrebie uczelni (nad gornym wasem)
    small_layer <- NULL
    if (!is.null(eda) && !is.null(eda$cld_within)) {
      cldw <- eda$cld_within %>% filter(metryka == mlab) %>%
        mutate(uczelnia   = factor(uczelnia, levels = c("upwr","sggw","urk","uwm")),
               stanowisko = factor(stanowisko, levels = STANOWISKA))
      cld_plot <- d1 %>% group_by(uczelnia, stanowisko) %>%
        summarise(q75 = quantile(y, 0.75), iqr = IQR(y), vmax = max(y), .groups = "drop") %>%
        mutate(y_lab = pmin(q75 + 1.5 * iqr, vmax) + 0.05 * max(vmax)) %>%
        left_join(cldw, by = c("uczelnia", "stanowisko"))
      small_layer <- geom_text(
        data = cld_plot, aes(x = uczelnia, y = y_lab, label = .group, group = stanowisko),
        position = position_dodge(width = DODGE), vjust = 0, size = 4.2,
        fontface = "bold", color = "#08519C", inherit.aes = FALSE)  # NIEBIESKIE = stanowiska
    }

    # DUZE litery: uczelnie w obrebie stanowiska (pasek pod boxami)
    big_layer <- NULL
    if (!is.null(eda) && !is.null(eda$cld_ucz_within)) {
      cldu <- eda$cld_ucz_within %>% filter(metryka == mlab) %>%
        mutate(uczelnia   = factor(uczelnia, levels = c("upwr","sggw","urk","uwm")),
               stanowisko = factor(stanowisko, levels = STANOWISKA),
               y_lo = min(d1$y) - 0.08 * diff(range(d1$y)))
      big_layer <- geom_text(
        data = cldu, aes(x = uczelnia, y = y_lo, label = .group, group = stanowisko),
        position = position_dodge(width = DODGE), vjust = 1, size = 4.6,
        fontface = "bold", color = "#1B7837", inherit.aes = FALSE)  # ZIELONE = uczelnie
    }

    p <- ggplot(d1, aes(x = uczelnia, y = y, fill = stanowisko)) +
      geom_boxplot(outlier.size = 0.5, alpha = 0.85, position = position_dodge(width = DODGE)) +
      small_layer + big_layer +
      scale_fill_manual(values = paleta_stan, labels = stan_labs) +
      scale_x_discrete(labels = ucz_labs) +
      labs(title = mlab,
           subtitle = "małe NIEBIESKIE (nad): stanowiska w obrębie uczelni; DUŻE ZIELONE (pod): uczelnie w obrębie stanowiska",
           x = NULL, y = NULL, fill = "Stanowisko") +
      theme_praca +
      theme(legend.position = "bottom",
            plot.title      = element_text(face = "bold", size = 16),
            plot.subtitle   = element_text(color = "grey40", size = 11, margin = margin(b = 8)),
            axis.text.x     = element_text(size = 14, face = "bold"),
            axis.text.y     = element_text(size = 13),
            legend.text     = element_text(size = 13),
            legend.title    = element_text(size = 14),
            legend.key.size = unit(0.9, "lines"))

    ggsave(file.path(PLOT_DIR, fig_files[[mk]]), p, width = 8.5, height = 5.4, dpi = 300)
    cat(sprintf("[OK] %s\n", fig_files[[mk]]))
  }
}

# ============================================================
# Fig 1b: Macierz korelacji metryk (podrozdzial "Struktura korelacyjna")
#   Uporzadkowana tak, by uwidocznic blok skumulowanego impactu
#   {h-index, sum_IF, sum_MEiN} (r 0,82-0,95) oraz luzno z nim zwiazane
#   n_pub (objetosc) i if_per_pub (os jakosci, ujemnie z n_pub).
# ============================================================
if (!is.null(eda) && !is.null(eda$correlations)) {
  ord <- c("h_index_wos", "sum_IF", "sum_MEiN", "n_pub", "if_per_pub", "if_to_mein")
  lab <- c(h_index_wos = "h-index (WoS)", sum_IF = "Sum. IF", sum_MEiN = "Sum. MEiN",
           n_pub = "Liczba publ.", if_per_pub = "IF / publ.", if_to_mein = "IF / MEiN")
  cm <- eda$correlations[ord, ord]
  cor_long <- as.data.frame(as.table(cm)) %>%
    setNames(c("x", "y", "r")) %>%
    mutate(x = factor(lab[as.character(x)], levels = unname(lab[ord])),
           y = factor(lab[as.character(y)], levels = rev(unname(lab[ord]))))
  p_cor <- ggplot(cor_long, aes(x, y, fill = r)) +
    geom_tile(color = "white", linewidth = 0.6) +
    geom_text(aes(label = sprintf("%.2f", r)), size = 4.2) +
    scale_fill_gradient2(low = "#3C5488", mid = "white", high = "#E64B35",
                         midpoint = 0, limits = c(-1, 1)) +
    coord_fixed() +
    labs(title = "Macierz korelacji wskaźników bibliometrycznych",
         x = NULL, y = NULL, fill = "r") +
    theme_praca +
    theme(axis.text.x  = element_text(angle = 30, hjust = 1, size = 12),
          axis.text.y  = element_text(size = 12),
          plot.title   = element_text(face = "bold", size = 15))
  ggsave(file.path(PLOT_DIR, "fig_01b_korelacje.png"), p_cor,
         width = 8, height = 6.8, dpi = 300)
  cat("[OK] fig_01b_korelacje.png\n")
}

# ============================================================
# Fig 1c: Gestosci 6 metryk (uzasadnienie sciezki nieparametrycznej)
#   Silna prawoskosnosc -> odrzucenie normalnosci (Shapiro) i jednorodnosci
#   wariancji (Levene). Linia = mediana (mediana << srednia = prawoskosnosc).
# ============================================================
if (file_exists(feat_path)) {
  metr6 <- c(n_pub = "Liczba publikacji", h_index_wos = "h-index (WoS)",
             sum_IF = "Sumaryczny IF", sum_MEiN = "Sum. punktacja MEiN",
             if_per_pub = "IF na publikację", if_to_mein = "IF / MEiN")
  dens <- read_csv(feat_path, show_col_types = FALSE) %>%
    pivot_longer(all_of(names(metr6)), names_to = "metryka", values_to = "y") %>%
    filter(!is.na(y)) %>%
    mutate(metryka = factor(metr6[metryka], levels = unname(metr6)))
  med <- dens %>% group_by(metryka) %>% summarise(mediana = median(y), .groups = "drop")

  p_dens <- ggplot(dens, aes(x = y)) +
    geom_density(fill = "#4DBBD5", color = "#2C7FB8", alpha = 0.55, linewidth = 0.5) +
    geom_vline(data = med, aes(xintercept = mediana),
               linetype = "dashed", color = "#E64B35", linewidth = 0.6) +
    facet_wrap(~ metryka, ncol = 3, scales = "free") +
    labs(title = "Rozkłady wskaźników bibliometrycznych w całej próbie",
         subtitle = "Silna prawoskośność uzasadnia ścieżkę nieparametryczną; czerwona linia = mediana",
         x = NULL, y = "Gęstość") +
    theme_praca +
    theme(plot.title    = element_text(face = "bold", size = 15),
          plot.subtitle = element_text(color = "grey40", size = 10, margin = margin(b = 8)),
          strip.text    = element_text(face = "bold", size = 11),
          axis.text     = element_text(size = 9))
  ggsave(file.path(PLOT_DIR, "fig_01c_rozklady.png"), p_dens,
         width = 9, height = 5.2, dpi = 300)
  cat("[OK] fig_01c_rozklady.png\n")
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
# Fig 4: Modele predykcyjne (metryki test set + VIP)
# ============================================================
if (!is.null(mdl)) {
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
         subtitle = "klasy niezbalansowane (10% high-impact) — niska czułość mimo wysokiego AUC",
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
# Fig 5: Sieć współautorstwa (Louvain) + heatmap zgodności z uczelnią
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

  ct <- net$crosstabs$ucz %>% as.data.frame()
  p5b <- ggplot(ct, aes(x = uczelnia, y = factor(community), fill = pct)) +
    geom_tile() +
    geom_text(aes(label = sprintf("%.0f%%", 100 * pct)), size = 3) +
    scale_fill_gradient(low = "white", high = "#E64B35") +
    labs(title = sprintf("Społeczność × uczelnia (ARI = %.3f)", net$ari$ucz),
         x = NULL, y = "Społeczność", fill = "%") +
    theme_praca

  ggsave(file.path(PLOT_DIR, "fig_05_siec.png"),
         p5a + p5b + plot_layout(widths = c(1.4, 1)),
         width = 14, height = 7, dpi = 300)
  cat("[OK] fig_05_siec.png\n")
}

# ============================================================
# Fig 6 (opcjonalna): Composite summary — jeśli wszystko jest
# ============================================================
have_all <- !is.null(eda) && !is.null(clust) && !is.null(mdl) && !is.null(net)
if (have_all) {
  cat("[INFO] wszystkie 4 RDS dostępne — composite 2x2 pominięty (5 osobnych figur jest czytelniejsze)\n")
}

cat(sprintf("\nWykresy zapisane: %s\n", PLOT_DIR))
