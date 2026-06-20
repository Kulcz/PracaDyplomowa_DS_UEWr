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
        # Pozycja Y litery CLD: tuz nad gornym wasem boksa (q75 + 1.5*IQR, ucietym
        # do faktycznego maksimum), plus maly margines 5% wysokosci - zabieg czysto
        # geometryczny, zeby etykieta wisiala nad wasem a nie na nim.
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
               # Pasek DUZYCH liter CLD pod boksami: wspolne Y odsuniete o 8%
               # rozpietosci danych ponizej minimum (jeden poziom dla wszystkich).
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

  # Czytelna legenda: klaster o najwyzszej sredniej centroidzie = "wysoki dorobek".
  # rowMeans (srednia po WSZYSTKICH zestandaryzowanych metrykach), a nie pojedyncza
  # metryka - bo metryki sa silnie skorelowane (blok skumulowanego impactu) i klaster
  # "wysoki" dominuje na calym wektorze; usrednienie jest odporne na to, ktora metryka
  # akurat rozdziela klastry najmocniej.
  centers_mean <- rowMeans(clust$kmeans$centers)
  hi    <- which.max(centers_mean)
  lo    <- setdiff(seq_along(centers_mean), hi)
  lab_hi <- sprintf("%d: wysoki dorobek", hi)
  lab_lo <- sprintf("%s: pozostali", paste(lo, collapse = ","))
  klaster_lab <- factor(ifelse(clust$kmeans$cluster == hi, lab_hi, lab_lo),
                        levels = c(lab_hi, lab_lo))

  p3a <- fviz_pca_ind(
    clust$pca,
    geom = "point",
    pointshape = 21, pointsize = 1.8, alpha.ind = 0.5,
    fill.ind = klaster_lab,
    palette = "Set2",
    addEllipses = TRUE, ellipse.type = "convex", ellipse.alpha = 0.08,
    legend.title = "Klaster"
  ) + labs(title = sprintf("PCA + klastry k-means (k = %d)", clust$k_opt)) +
      theme_praca

  # Heatmapa centroidow (dawny fig_03b) usunieta 2026-06-18: redundantna z
  # Tabela 3 (centroidy w skali oryginalnej) i wierszem "Pula" Tabeli 4 (z-score).
  ggsave(file.path(PLOT_DIR, "fig_03a_klastry.png"), p3a,
         width = 8, height = 6, dpi = 300)
  cat("[OK] fig_03a_klastry.png\n")
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
         subtitle = "klasy niezbalansowane (10% high-impact): niska czułość mimo wysokiego AUC",
         x = NULL, y = "Wartość", fill = "Model") +
    theme_praca

  # Opisowe etykiety predyktorow zamiast surowych nazw technicznych:
  etykiety_zmiennych <- c(
    n_pub                       = "Liczba publikacji",
    n_unique_coauthors          = "Liczba unikalnych współautorów",
    avg_authors_per_pub         = "Średnia liczba autorów na publikację",
    mean_fwci                   = "Średni FWCI",
    uczelnia_upwr               = "Uczelnia: UPWr",
    stanowisko_profesor         = "Stanowisko: profesor",
    uczelnia_uwm                = "Uczelnia: UWM",
    stanowisko_profesor.uczelni = "Stanowisko: profesor uczelni",
    uczelnia_urk                = "Uczelnia: URK",
    stanowisko_unknown          = "Stanowisko: brak danych"
  )

  # Kategoria cechy (kolor) - wprost ilustruje teze: produktywnosc i wspolpraca
  # waza wiecej niz cechy formalne (uczelnia, stanowisko).
  kat_zmiennych <- c(
    n_pub                       = "Produktywność",
    n_unique_coauthors          = "Współpraca i cytowania",
    avg_authors_per_pub         = "Współpraca i cytowania",
    mean_fwci                   = "Współpraca i cytowania",
    uczelnia_upwr               = "Cechy formalne",
    stanowisko_profesor         = "Cechy formalne",
    uczelnia_uwm                = "Cechy formalne",
    stanowisko_profesor.uczelni = "Cechy formalne",
    uczelnia_urk                = "Cechy formalne",
    stanowisko_unknown          = "Cechy formalne"
  )
  poziomy_kat <- c("Produktywność", "Współpraca i cytowania",
                   "Cechy formalne")

  p4b <- mdl$vip_rf %>% slice_max(Importance, n = 10) %>%
    mutate(
      Kategoria = factor(dplyr::coalesce(kat_zmiennych[as.character(Variable)], "Inne"),
                         levels = poziomy_kat),
      Variable  = dplyr::coalesce(etykiety_zmiennych[as.character(Variable)],
                                  as.character(Variable))
    ) %>%
    ggplot(aes(x = reorder(Variable, Importance), y = Importance, fill = Kategoria)) +
    geom_col() + coord_flip() +
    scale_fill_manual(values = c(
      "Produktywność"                          = "#3C5488",
      "Współpraca i cytowania"                 = "#00A087",
      "Cechy formalne"  = "#E64B35")) +
    labs(title = "Najważniejsze predyktory w modelu Random Forest",
         x = NULL, y = "Ważność zmiennej", fill = "Kategoria cechy") +
    theme_praca +
    theme(legend.position = "bottom",
          plot.title   = element_text(face = "bold", size = 16),
          axis.text    = element_text(size = 13),
          axis.title.x = element_text(size = 14),
          legend.text  = element_text(size = 12),
          legend.title = element_text(size = 13))

  # Tylko wykres waznosci cech (p4b). Wykres metryk (p4a) pominiety:
  # dublowal tabele tbl-modele (te same metryki, modele i liczby).
  ggsave(file.path(PLOT_DIR, "fig_04b_waznosc.png"), p4b,
         width = 11, height = 6.2, dpi = 300)
  cat("[OK] fig_04b_waznosc.png\n")
}

# ============================================================
# Fig 4c: Waznosc cech modelu JAKOSCIOWEGO (cel: mean_fwci > 1).
#   Pokazuje, ze przy predykcji jakosci dominuja cechy wspolpracy,
#   a wiek akademicki / liczba publikacji / cechy formalne sa nisko.
# ============================================================
mdl_q <- try_load("model_jakosc.rds")
if (!is.null(mdl_q) && !is.null(mdl_q$vip_rf)) {
  etykiety_q <- c(
    avg_authors_per_pub         = "Średnia liczba autorów na publikację",
    n_unique_coauthors          = "Liczba unikalnych współautorów",
    wiek_akad                   = "Wiek akademicki",
    n_pub                       = "Liczba publikacji",
    uczelnia_upwr               = "Uczelnia: UPWr",
    uczelnia_urk                = "Uczelnia: URK",
    uczelnia_uwm                = "Uczelnia: UWM",
    stanowisko_profesor         = "Stanowisko: profesor",
    stanowisko_profesor.uczelni = "Stanowisko: profesor uczelni",
    stanowisko_asystent         = "Stanowisko: asystent",
    stanowisko_unknown          = "Stanowisko: brak danych"
  )
  kat_q <- c(
    avg_authors_per_pub = "Współpraca naukowa",
    n_unique_coauthors  = "Współpraca naukowa",
    wiek_akad           = "Wiek akademicki",
    n_pub               = "Produktywność",
    uczelnia_upwr = "Cechy formalne", uczelnia_urk = "Cechy formalne",
    uczelnia_uwm = "Cechy formalne", stanowisko_profesor = "Cechy formalne",
    stanowisko_profesor.uczelni = "Cechy formalne", stanowisko_asystent = "Cechy formalne",
    stanowisko_unknown = "Cechy formalne"
  )
  poziomy_q <- c("Współpraca naukowa", "Wiek akademicki", "Produktywność", "Cechy formalne")

  p4c <- mdl_q$vip_rf %>% slice_max(Importance, n = 10) %>%
    mutate(
      Kategoria = factor(dplyr::coalesce(kat_q[as.character(Variable)], "Inne"),
                         levels = poziomy_q),
      Variable  = dplyr::coalesce(etykiety_q[as.character(Variable)],
                                  as.character(Variable))
    ) %>%
    ggplot(aes(x = reorder(Variable, Importance), y = Importance, fill = Kategoria)) +
    geom_col() + coord_flip() +
    scale_fill_manual(values = c(
      "Współpraca naukowa" = "#00A087",
      "Wiek akademicki"    = "#F39B7F",
      "Produktywność"      = "#3C5488",
      "Cechy formalne"     = "#E64B35")) +
    labs(title = "Najważniejsze predyktory jakości dorobku (model FWCI > 1)",
         x = NULL, y = "Ważność zmiennej", fill = "Kategoria cechy") +
    guides(fill = guide_legend(nrow = 2)) +
    theme_praca +
    theme(legend.position = "bottom",
          plot.title   = element_text(face = "bold", size = 15),
          axis.text    = element_text(size = 13),
          axis.title.x = element_text(size = 14),
          legend.text  = element_text(size = 12),
          legend.title = element_text(size = 13))

  ggsave(file.path(PLOT_DIR, "fig_04c_waznosc_jakosc.png"), p4c,
         width = 11, height = 6.2, dpi = 300)
  cat("[OK] fig_04c_waznosc_jakosc.png\n")
}

# ============================================================
# Fig 5: Sieć współautorstwa (Louvain) + heatmap zgodności z uczelnią
# ============================================================
if (!is.null(net)) {
  library(igraph); library(tidygraph); library(ggraph)

  tg <- as_tbl_graph(net$graph)

  ucz_labs <- c(upwr = "UPWr", sggw = "SGGW", urk = "URK", uwm = "UWM")

  # Panel A: siec kolorowana UCZELNIA (legenda) - widac, ze skupiska
  # Louvain sa jednouczelniane. Wielkosc wezla = stopien (degree).
  p5a <- ggraph(tg, layout = "stress") +
    geom_edge_link(alpha = 0.12, color = "grey50") +
    geom_node_point(aes(color = uczelnia, size = degree), alpha = 0.9) +
    scale_color_manual(values = paleta_uczelnia, labels = ucz_labs, name = "Uczelnia") +
    scale_size(range = c(1, 6), guide = "none") +
    labs(title = sprintf("Sieć współautorstwa (modularność Q = %.3f)", net$modularity)) +
    guides(color = guide_legend(override.aes = list(size = 5))) +
    theme_void(base_size = 13) +
    theme(plot.background = element_rect(fill = "white", color = NA),
          plot.title    = element_text(face = "bold", size = 15, hjust = 0.5),
          plot.margin   = margin(10, 10, 10, 10),
          legend.position = "bottom",
          legend.text   = element_text(size = 13),
          legend.title  = element_text(size = 14))

  ggsave(file.path(PLOT_DIR, "fig_05a_siec.png"), p5a,
         width = 9, height = 8, dpi = 300)
  cat("[OK] fig_05a_siec.png\n")

  # Panel B: heatmapa spolecznosc x uczelnia. Spolecznosci uporzadkowane
  # wg wielkosci (najwieksze u gory), etykiety 0% ukryte dla czytelnosci.
  ct <- net$crosstabs$ucz %>% as.data.frame()
  sizes <- ct %>% group_by(community) %>% summarise(n = sum(Freq), .groups = "drop")
  lev <- sizes %>% arrange(n) %>% pull(community) %>% as.character()
  size_lookup <- setNames(sizes$n, as.character(sizes$community))
  ct <- ct %>%
    group_by(community) %>%
    # Klasyfikacja spolecznosci: sum(pct > 0) liczy, ILE uczelni ma niezerowy udzial
    # w danej spolecznosci. > 1 uczelnia -> spolecznosc MIESZANA (wspolautorstwo
    # miedzyuczelniane); dokladnie 1 uczelnia -> jednouczelniana.
    mutate(typ = if (sum(pct > 0) > 1) "Mieszana (współpraca międzyuczelniana)"
                 else "Jednouczelniana") %>%
    ungroup() %>%
    mutate(
      community = factor(as.character(community), levels = lev),
      typ = factor(typ, levels = c("Jednouczelniana", "Mieszana (współpraca międzyuczelniana)")),
      lab = ifelse(pct > 0, sprintf("%.0f%%", 100 * pct), "")
    )
  n_comm <- length(lev)
  # Kolor wg typu spolecznosci: czerwien = jednouczelniana, turkus = mieszana
  # (wspolpraca miedzy uczelniami). Intensywnosc (alpha) = udzial uczelni.
  p5b <- ggplot(ct, aes(x = uczelnia, y = community)) +
    geom_tile(data = function(d) dplyr::filter(d, pct > 0),
              aes(fill = typ, alpha = pct), color = "grey70", linewidth = 0.3) +
    # wyraziste poziome linie rozdzielajace spolecznosci (wiersze)
    geom_hline(yintercept = seq(0.5, n_comm + 0.5, by = 1),
               color = "grey45", linewidth = 0.5) +
    geom_text(aes(label = lab), size = 4.4) +
    scale_fill_manual(values = c(
      "Jednouczelniana"                        = "#E64B35",
      "Mieszana (współpraca międzyuczelniana)" = "#00A087"),
      name = "Typ społeczności") +
    scale_alpha(range = c(0.35, 1), guide = "none") +
    scale_x_discrete(labels = ucz_labs) +
    scale_y_discrete(labels = function(x) paste0("nr ", x, "  (", size_lookup[x], " osób)")) +
    labs(title = "Zgodność społeczności współautorstwa z uczelnią",
         subtitle = sprintf("każdy wiersz to jedna społeczność (od najmniejszej u dołu); wartość = udział danej uczelni\nARI = %.3f, NMI = %.3f",
                            net$ari$ucz, net$nmi$ucz),
         x = NULL, y = "Społeczność (liczba członków)") +
    guides(fill = guide_legend(nrow = 2, override.aes = list(alpha = 1))) +
    theme_praca +
    theme(plot.title    = element_text(face = "bold", size = 18),
          plot.subtitle = element_text(size = 13, color = "grey40", margin = margin(b = 8)),
          axis.text.y   = element_text(size = 15),
          axis.text.x   = element_text(size = 17, face = "bold"),
          axis.title.y  = element_text(size = 15),
          legend.position = "bottom",
          legend.text   = element_text(size = 13),
          legend.title  = element_text(size = 14))

  ggsave(file.path(PLOT_DIR, "fig_05b_spolecznosci.png"), p5b,
         width = 10.5, height = 12, dpi = 300)
  cat("[OK] fig_05b_spolecznosci.png\n")
}

# ============================================================
# Fig 6 (opcjonalna): Composite summary — jeśli wszystko jest
# ============================================================
have_all <- !is.null(eda) && !is.null(clust) && !is.null(mdl) && !is.null(net)
if (have_all) {
  cat("[INFO] wszystkie 4 RDS dostępne — composite 2x2 pominięty (5 osobnych figur jest czytelniejsze)\n")
}

cat(sprintf("\nWykresy zapisane: %s\n", PLOT_DIR))
