# LTeX: enabled=false
# ============================================================
# 02 - Czyszczenie i analiza danych: Wydzial Przyrodniczo-Technologiczny
# ============================================================

library(multcomp)
library(multcompView)
library(emmeans)
library(car)
library(dunn.test)
library(dplyr)
library(tidyr)
library(ggplot2)
library(stringr)
library(readr)
library(corrplot)
library(openxlsx)

# ---------- 1. Wczytanie danych ----------
df_raw <- read.csv("output_bibliometria/upwr_profiles_metrics_HTML_20260306_075402.csv",
                    stringsAsFactors = FALSE)

cat("Wczytano rekordow:", nrow(df_raw), "\n")

# ---------- 2. Filtracja: tylko Wydz. Przyrodniczo-Technologiczny ----------
df <- df_raw %>%
  filter(wydzial == "Wydział Przyrodniczo-Technologiczny")

cat("Po filtracji (WPT):", nrow(df), "\n")

# ---------- 3. Usuwanie kolumn technicznych ----------
df <- df %>%
  dplyr::select(-author_id, -url, -error)

# ---------- 4. Braki danych - raport ----------
cat("\n=== BRAKI DANYCH ===\n")
braki <- colSums(is.na(df))
braki_pct <- round(100 * braki / nrow(df), 1)
braki_df <- data.frame(kolumna = names(braki), brak_n = braki, brak_pct = braki_pct)
print(braki_df)

# ---------- 5. Standaryzacja stanowisk ----------
df <- df %>%
  mutate(stanowisko = case_when(
    stanowisko == "profesor Uczelni" ~ "profesor uczelni",
    !is.na(stanowisko) ~ tolower(stanowisko),
    TRUE ~ NA_character_
  ))

cat("\n=== STANOWISKA (po standaryzacji) ===\n")
print(table(df$stanowisko, useNA = "ifany"))

cat("\n=== JEDNOSTKI (katedry) ===\n")
print(sort(table(df$jednostka), decreasing = TRUE))

# ============================================================
# ETAP 3: ANALIZA
# ============================================================

metryki <- c("h_index_wos", "sum_IF", "sum_MEiN")

# ---------- 6. Statystyki opisowe - ogolne ----------
cat("\n=== STATYSTYKI OPISOWE (caly wydzial) ===\n")
stats_ogolne <- df %>%
  summarise(across(all_of(metryki), list(
    n     = ~sum(!is.na(.)),
    mean  = ~mean(., na.rm = TRUE),
    sd    = ~sd(., na.rm = TRUE),
    min   = ~min(., na.rm = TRUE),
    q25   = ~quantile(., 0.25, na.rm = TRUE),
    median = ~median(., na.rm = TRUE),
    q75   = ~quantile(., 0.75, na.rm = TRUE),
    max   = ~max(., na.rm = TRUE)
  ))) %>%
  pivot_longer(everything(),
               names_to = c("metryka", "stat"),
               names_pattern = "(.+)_([^_]+)$") %>%
  pivot_wider(names_from = stat, values_from = value)

print(as.data.frame(stats_ogolne), digits = 2)

# ---------- 7. Statystyki per stanowisko ----------
cat("\n=== STATYSTYKI PER STANOWISKO ===\n")
stats_stanowisko <- df %>%
  filter(!is.na(stanowisko)) %>%
  group_by(stanowisko) %>%
  summarise(
    n = n(),
    across(all_of(metryki), list(
      mean   = ~mean(., na.rm = TRUE),
      median = ~median(., na.rm = TRUE)
    )),
    .groups = "drop"
  )

print(as.data.frame(stats_stanowisko), digits = 2)

# ---------- 8. Statystyki per jednostka (katedra) ----------
cat("\n=== STATYSTYKI PER JEDNOSTKA ===\n")
stats_jednostka <- df %>%
  filter(!is.na(jednostka)) %>%
  group_by(jednostka) %>%
  summarise(
    n = n(),
    across(all_of(metryki), list(
      mean   = ~mean(., na.rm = TRUE),
      median = ~median(., na.rm = TRUE)
    )),
    .groups = "drop"
  ) %>%
  arrange(desc(n))

print(as.data.frame(stats_jednostka), digits = 2)

# ---------- 9. Korelacje ----------
cat("\n=== MACIERZ KORELACJI ===\n")
df_metryki <- df %>% dplyr::select(all_of(metryki)) %>% drop_na()
cor_matrix <- cor(df_metryki)
print(round(cor_matrix, 3))

# ---------- 10. Top-10 per metryka ----------
cat("\n=== TOP 10: h-index WoS ===\n")
print(df %>% arrange(desc(h_index_wos)) %>% head(10) %>%
        dplyr::select(profil, stanowisko, jednostka, h_index_wos))

cat("\n=== TOP 10: sum_IF ===\n")
print(df %>% arrange(desc(sum_IF)) %>% head(10) %>%
        dplyr::select(profil, stanowisko, jednostka, sum_IF))

cat("\n=== TOP 10: sum_MEiN ===\n")
print(df %>% arrange(desc(sum_MEiN)) %>% head(10) %>%
        dplyr::select(profil, stanowisko, jednostka, sum_MEiN))

# ============================================================
# ETAP 4: WIZUALIZACJA
# ============================================================

PLOT_DIR <- "Wykresy/WPT"
PLOT_DIR_ZBIORCZE <- file.path(PLOT_DIR, "zestawienia_zbiorcze")
dir.create(PLOT_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(PLOT_DIR_ZBIORCZE, recursive = TRUE, showWarnings = FALSE)

# --- Wspolny motyw i etykiety ---
metryki_labels <- c(
  h_index_wos = "h-index (WoS)",
  sum_IF      = "Sumaryczny IF",
  sum_MEiN    = "Punktacja MEiN"
)

paleta_stan <- c(
  "adiunkt"          = "#56B4E9",
  "profesor uczelni" = "#009E73",
  "profesor"         = "#CC79A7"
)

theme_biblio <- theme_minimal(base_size = 13) +
  theme(
    plot.title = element_text(face = "bold", size = 15, margin = margin(b = 4)),
    plot.subtitle = element_text(color = "grey40", size = 11, margin = margin(b = 12)),
    strip.text = element_text(face = "bold", size = 11),
    panel.grid.minor = element_blank(),
    panel.grid.major.x = element_blank(),
    plot.margin = margin(12, 12, 12, 12)
  )

# ---------- 11. Histogramy / density metryk ----------
df_long <- df %>%
  dplyr::select(profil, all_of(metryki)) %>%
  pivot_longer(cols = all_of(metryki), names_to = "metryka", values_to = "wartosc") %>%
  filter(!is.na(wartosc)) %>%
  mutate(metryka = dplyr::recode(metryka, !!!metryki_labels))

p_density <- ggplot(df_long, aes(x = wartosc)) +
  geom_histogram(aes(y = after_stat(density)), bins = 18,
                 fill = "#3C5488", color = "white", alpha = 0.75) +
  geom_density(color = "#E64B35", linewidth = 0.9, adjust = 1.2) +
  facet_wrap(~metryka, scales = "free", ncol = 3) +
  labs(title = "Rozkłady metryk bibliometrycznych",
       subtitle = "Wydział Przyrodniczo-Technologiczny, UPWr (n = 145)",
       x = NULL, y = "Gęstość") +
  theme_biblio

ggsave(file.path(PLOT_DIR_ZBIORCZE, "01_rozklady_metryk.png"), p_density, width = 12, height = 4.5, dpi = 200)
cat("\nZapisano:", file.path(PLOT_DIR_ZBIORCZE, "01_rozklady_metryk.png"), "\n")

# ---------- 12. Boxploty per stanowisko ----------
stan_order <- c("adiunkt", "profesor uczelni", "profesor")
stan_labels <- c("adiunkt" = "adiunkt", "profesor uczelni" = "profesor\nuczelni", "profesor" = "profesor")

df_stan <- df %>%
  filter(!is.na(stanowisko), stanowisko != "asystent") %>%
  mutate(stanowisko = factor(stanowisko, levels = stan_order))

# Diagnostyka zalozen ANOVA + wybor testu
cat("\n=== DIAGNOSTYKA ZALOZEN ANOVA ===\n")
cld_all <- data.frame()
test_info <- list()

for (m in metryki) {
  df_m <- df_stan %>% filter(!is.na(.data[[m]]))
  form <- as.formula(paste(m, "~ stanowisko"))
  mod <- aov(form, data = df_m)

  cat(sprintf("\n--- %s ---\n", metryki_labels[m]))

  # 1. Normalnosc reszt (Shapiro-Wilk)
  sw <- shapiro.test(residuals(mod))
  cat(sprintf("Shapiro-Wilk (reszty): W = %.4f, p = %.4f %s\n",
              sw$statistic, sw$p.value,
              ifelse(sw$p.value < 0.05, "-> ODRZUCONA normalnosc", "-> OK")))

  # 2. Jednorodnosc wariancji (Levene)
  lev <- leveneTest(form, data = df_m)
  lev_p <- lev$`Pr(>F)`[1]
  cat(sprintf("Levene (jednorodnosc wariancji): F = %.4f, p = %.4f %s\n",
              lev$`F value`[1], lev_p,
              ifelse(lev_p < 0.05, "-> ODRZUCONA jednorodnosc", "-> OK")))

  use_nonparam <- (sw$p.value < 0.05) || (lev_p < 0.05)

  if (!use_nonparam) {
    # ANOVA parametryczna + Tukey HSD
    cat("\n>> Zalozenia spelnione -> ANOVA + Tukey HSD\n")
    print(summary(mod))

    emm <- emmeans(mod, "stanowisko")
    cld_result <- cld(emm, Letters = letters, adjust = "tukey")
    cld_result <- as.data.frame(cld_result)
    cld_result$.group <- trimws(cld_result$.group)
    cat("Grupy jednorodne (Tukey HSD, p < 0.05):\n")
    print(cld_result[, c("stanowisko", "emmean", ".group")])
    test_info[[m]] <- "ANOVA + Tukey HSD"

  } else {
    # Kruskal-Wallis + Dunn post-hoc
    cat("\n>> Zalozenia naruszone -> Kruskal-Wallis + test Dunna\n")
    kw <- kruskal.test(form, data = df_m)
    cat(sprintf("Kruskal-Wallis: chi2 = %.2f, df = %d, p = %.6f\n",
                kw$statistic, kw$parameter, kw$p.value))

    # Test Dunna z korektą Bonferroniego
    dunn_res <- dunn.test(df_m[[m]], df_m$stanowisko,
                          method = "bonferroni", altp = TRUE)

    # Budowanie CLD z wynikow Dunna
    levs <- levels(df_m$stanowisko)
    n_levs <- length(levs)
    pmat <- matrix(1, n_levs, n_levs, dimnames = list(levs, levs))
    for (i in seq_along(dunn_res$comparisons)) {
      pair <- strsplit(dunn_res$comparisons[i], " - ")[[1]]
      pmat[pair[1], pair[2]] <- dunn_res$altP.adjusted[i]
      pmat[pair[2], pair[1]] <- dunn_res$altP.adjusted[i]
    }

    # Przypisanie liter na podstawie macierzy p-wartosci
    cld_letters <- multcompView::multcompLetters(
      setNames(
        as.vector(pmat[lower.tri(pmat)]),
        apply(combn(levs, 2), 2, paste, collapse = "-")
      ),
      threshold = 0.05
    )

    cld_result <- data.frame(
      stanowisko = factor(names(cld_letters$Letters), levels = levs),
      .group = as.character(cld_letters$Letters),
      stringsAsFactors = FALSE
    )

    cat("Grupy jednorodne (Dunn + Bonferroni, p < 0.05):\n")
    medians <- df_m %>%
      group_by(stanowisko) %>%
      summarise(mediana = median(.data[[m]], na.rm = TRUE), .groups = "drop")
    print(merge(cld_result, medians, by = "stanowisko"))
    test_info[[m]] <- "Kruskal-Wallis + Dunn"
  }

  # Pozycja literki = gorny was boxplotu
  whisker_vals <- df_m %>%
    group_by(stanowisko) %>%
    summarise(
      q75 = quantile(.data[[m]], 0.75, na.rm = TRUE),
      iqr = IQR(.data[[m]], na.rm = TRUE),
      vmax = max(.data[[m]], na.rm = TRUE),
      .groups = "drop"
    ) %>%
    mutate(y_whisker = pmin(q75 + 1.5 * iqr, vmax))

  cld_m <- cld_result %>%
    dplyr::select(stanowisko, .group) %>%
    left_join(whisker_vals, by = "stanowisko") %>%
    mutate(metryka = metryki_labels[m])

  cld_all <- bind_rows(cld_all, cld_m)
}

# Podsumowanie uzytych testow
cat("\n=== PODSUMOWANIE TESTOW ===\n")
for (m in metryki) {
  cat(sprintf("  %s: %s\n", metryki_labels[m], test_info[[m]]))
}

# Info do subtytulu wykresu
test_names <- unique(unlist(test_info))
subtitle_test <- paste(test_names, collapse = " / ")

# Przygotowanie danych do wykresu
df_long_stan <- df_stan %>%
  dplyr::select(stanowisko, all_of(metryki)) %>%
  pivot_longer(cols = all_of(metryki), names_to = "metryka", values_to = "wartosc") %>%
  filter(!is.na(wartosc)) %>%
  mutate(metryka = dplyr::recode(metryka, !!!metryki_labels))

# Offset nad wasem (5% zakresu per facet)
offsets <- df_long_stan %>%
  group_by(metryka) %>%
  summarise(offset = (max(wartosc, na.rm = TRUE) - min(wartosc, na.rm = TRUE)) * 0.04,
            .groups = "drop")

cld_all <- cld_all %>%
  left_join(offsets, by = "metryka") %>%
  mutate(y_label = y_whisker + offset)

p_box_stan <- ggplot(df_long_stan, aes(x = stanowisko, y = wartosc, fill = stanowisko)) +
  geom_boxplot(alpha = 0.8, outlier.shape = 21, outlier.size = 2.5, width = 0.6) +
  geom_jitter(width = 0.15, alpha = 0.3, size = 1.5, color = "grey30") +
  geom_text(data = cld_all, aes(x = stanowisko, y = y_label, label = .group),
            inherit.aes = FALSE, size = 7, fontface = "bold", color = "black") +
  scale_fill_manual(values = paleta_stan) +
  scale_x_discrete(labels = stan_labels) +
  facet_wrap(~metryka, scales = "free_y", ncol = 3) +
  labs(title = "Metryki bibliometryczne wg stanowiska",
       subtitle = paste0("Wydział Przyrodniczo-Technologiczny, UPWr (", subtitle_test, ", p < 0.05)"),
       x = NULL, y = NULL) +
  theme_biblio +
  theme(axis.text.x = element_text(size = 13, lineheight = 0.9),
        axis.text.y = element_text(size = 12),
        strip.text = element_text(face = "bold", size = 14),
        plot.title = element_text(face = "bold", size = 17),
        plot.subtitle = element_text(size = 12, color = "grey40"),
        legend.position = "none")

ggsave(file.path(PLOT_DIR_ZBIORCZE, "02_boxploty_stanowisko.png"), p_box_stan, width = 13, height = 6, dpi = 200)
cat("\nZapisano:", file.path(PLOT_DIR_ZBIORCZE, "02_boxploty_stanowisko.png"), "\n")

# ---------- 12b. Osobne wykresy per metryka ----------
metryki_dirs <- c(
  h_index_wos = "h_index_wos",
  sum_IF      = "sumaryczny_IF",
  sum_MEiN    = "punktacja_MEiN"
)

top_katedry <- df %>%
  filter(!is.na(jednostka)) %>%
  count(jednostka) %>%
  filter(n >= 5) %>%
  pull(jednostka)

jednostka_short <- c(
  "Instytut Nauk o Glebie, Żywienia Roślin i Ochrony Środowiska" = "Inst. Nauk o Glebie",
  "Instytut Agroekologii i Produkcji Roślinnej" = "Inst. Agroekologii",
  "Katedra Ogrodnictwa" = "Kat. Ogrodnictwa",
  "Instytut Inżynierii Rolniczej" = "Inst. Inż. Rolniczej",
  "Katedra Ochrony Roślin" = "Kat. Ochrony Roślin",
  "Katedra Genetyki, Hodowli Roślin i Nasiennictwa" = "Kat. Genetyki i Hodowli",
  "Katedra Botaniki i Ekologii Roślin" = "Kat. Botaniki i Ekologii"
)

paleta_jedn <- c("#3C5488", "#E64B35", "#00A087", "#F39B7F",
                 "#4DBBD5", "#8491B4", "#91D1C2")

for (m in metryki) {
  m_dir <- file.path(PLOT_DIR, metryki_dirs[m])
  dir.create(m_dir, recursive = TRUE, showWarnings = FALSE)

  m_label <- metryki_labels[m]
  m_test <- test_info[[m]]

  # Dane dla jednej metryki
  df_m_stan <- df_stan %>%
    filter(!is.na(.data[[m]])) %>%
    dplyr::select(stanowisko, all_of(m))

  cld_m <- cld_all %>% filter(metryka == m_label)

  # --- Histogram / density ---
  p_hist <- ggplot(df_m_stan, aes(x = .data[[m]])) +
    geom_histogram(aes(y = after_stat(density)), bins = 18,
                   fill = "#3C5488", color = "white", alpha = 0.75) +
    geom_density(color = "#E64B35", linewidth = 1, adjust = 1.2) +
    labs(title = paste("Rozkład:", m_label),
         subtitle = "Wydział Przyrodniczo-Technologiczny, UPWr",
         x = m_label, y = "Gęstość") +
    theme_biblio +
    theme(plot.title = element_text(face = "bold", size = 17),
          plot.subtitle = element_text(size = 12, color = "grey40"),
          axis.text = element_text(size = 12),
          axis.title = element_text(size = 13))

  ggsave(file.path(m_dir, "01_rozklad.png"), p_hist, width = 7, height = 5, dpi = 200)

  # --- Boxplot per stanowisko ---
  p_box <- ggplot(df_m_stan, aes(x = stanowisko, y = .data[[m]], fill = stanowisko)) +
    geom_boxplot(alpha = 0.8, outlier.shape = 21, outlier.size = 2.5, width = 0.55) +
    geom_jitter(width = 0.15, alpha = 0.3, size = 1.8, color = "grey30") +
    geom_text(data = cld_m, aes(x = stanowisko, y = y_label, label = .group),
              inherit.aes = FALSE, size = 8, fontface = "bold") +
    scale_fill_manual(values = paleta_stan) +
    scale_x_discrete(labels = stan_labels) +
    labs(title = paste(m_label, "wg stanowiska"),
         subtitle = paste0("Wydział Przyrodniczo-Technologiczny, UPWr (", m_test, ", p < 0.05)"),
         x = NULL, y = m_label) +
    theme_biblio +
    theme(plot.title = element_text(face = "bold", size = 17),
          plot.subtitle = element_text(size = 12, color = "grey40"),
          axis.text.x = element_text(size = 14, lineheight = 0.9),
          axis.text.y = element_text(size = 12),
          axis.title.y = element_text(size = 13),
          legend.position = "none")

  ggsave(file.path(m_dir, "02_boxplot_stanowisko.png"), p_box, width = 7, height = 6, dpi = 200)

  cat("Zapisano wykresy:", m_dir, "\n")
}

# Boxploty per jednostka z CLD generowane sa w sekcji 13c (po obliczeniu cld_jedn_all)

# ---------- 13. ANOVA / Kruskal-Wallis per jednostka ----------
cat("\n=== DIAGNOSTYKA ZALOZEN ANOVA: JEDNOSTKI ===\n")

df_jedn <- df %>%
  filter(jednostka %in% top_katedry) %>%
  mutate(
    jednostka_skr = dplyr::recode(jednostka, !!!jednostka_short),
    jednostka_skr = factor(jednostka_skr)
  )

cld_jedn_all <- data.frame()
test_info_jedn <- list()

for (m in metryki) {
  df_m <- df_jedn %>% filter(!is.na(.data[[m]]))
  form <- as.formula(paste(m, "~ jednostka_skr"))
  mod <- aov(form, data = df_m)

  cat(sprintf("\n--- %s ---\n", metryki_labels[m]))

  sw <- shapiro.test(residuals(mod))
  cat(sprintf("Shapiro-Wilk (reszty): W = %.4f, p = %.4f %s\n",
              sw$statistic, sw$p.value,
              ifelse(sw$p.value < 0.05, "-> ODRZUCONA normalnosc", "-> OK")))

  lev <- leveneTest(form, data = df_m)
  lev_p <- lev$`Pr(>F)`[1]
  cat(sprintf("Levene: F = %.4f, p = %.4f %s\n",
              lev$`F value`[1], lev_p,
              ifelse(lev_p < 0.05, "-> ODRZUCONA jednorodnosc", "-> OK")))

  use_nonparam <- (sw$p.value < 0.05) || (lev_p < 0.05)

  if (!use_nonparam) {
    cat("\n>> Zalozenia spelnione -> ANOVA + Tukey HSD\n")
    print(summary(mod))
    emm <- emmeans(mod, "jednostka_skr")
    cld_result <- as.data.frame(cld(emm, Letters = letters, adjust = "tukey"))
    cld_result$.group <- trimws(cld_result$.group)
    cat("Grupy jednorodne (Tukey HSD, p < 0.05):\n")
    print(cld_result[, c("jednostka_skr", "emmean", ".group")])
    test_info_jedn[[m]] <- "ANOVA + Tukey HSD"
  } else {
    cat("\n>> Zalozenia naruszone -> Kruskal-Wallis + test Dunna\n")
    kw <- kruskal.test(form, data = df_m)
    cat(sprintf("Kruskal-Wallis: chi2 = %.2f, df = %d, p = %.6f\n",
                kw$statistic, kw$parameter, kw$p.value))

    if (kw$p.value >= 0.05) {
      cat(">> Brak istotnych roznic miedzy jednostkami (p >= 0.05)\n")
      levs <- levels(df_m$jednostka_skr)
      cld_result <- data.frame(
        jednostka_skr = factor(levs, levels = levs),
        .group = rep("a", length(levs)),
        stringsAsFactors = FALSE
      )
      test_info_jedn[[m]] <- "Kruskal-Wallis (n.s.)"
    } else {
      dunn_res <- dunn.test(df_m[[m]], df_m$jednostka_skr,
                            method = "bonferroni", altp = TRUE)
      levs <- levels(df_m$jednostka_skr)
      n_levs <- length(levs)
      pmat <- matrix(1, n_levs, n_levs, dimnames = list(levs, levs))
      for (i in seq_along(dunn_res$comparisons)) {
        pair <- strsplit(dunn_res$comparisons[i], " - ")[[1]]
        pmat[pair[1], pair[2]] <- dunn_res$altP.adjusted[i]
        pmat[pair[2], pair[1]] <- dunn_res$altP.adjusted[i]
      }
      cld_letters <- multcompView::multcompLetters(
        setNames(
          as.vector(pmat[lower.tri(pmat)]),
          apply(combn(levs, 2), 2, paste, collapse = "-")
        ),
        threshold = 0.05
      )
      cld_result <- data.frame(
        jednostka_skr = factor(names(cld_letters$Letters), levels = levs),
        .group = as.character(cld_letters$Letters),
        stringsAsFactors = FALSE
      )
      cat("Grupy jednorodne (Dunn + Bonferroni, p < 0.05):\n")
      medians <- df_m %>%
        group_by(jednostka_skr) %>%
        summarise(mediana = median(.data[[m]], na.rm = TRUE), .groups = "drop")
      print(merge(cld_result, medians, by = "jednostka_skr"))
      test_info_jedn[[m]] <- "Kruskal-Wallis + Dunn"
    }
  }

  # Pozycja liter: prawy koniec wasa (horizontal boxplot)
  whisker_vals <- df_m %>%
    group_by(jednostka_skr) %>%
    summarise(
      q75 = quantile(.data[[m]], 0.75, na.rm = TRUE),
      iqr = IQR(.data[[m]], na.rm = TRUE),
      vmax = max(.data[[m]], na.rm = TRUE),
      .groups = "drop"
    ) %>%
    mutate(x_whisker = pmin(q75 + 1.5 * iqr, vmax))

  # Offset oparty na zakresie wąsów (bez outlierow)
  offset_val <- (max(whisker_vals$x_whisker) - min(df_m[[m]], na.rm = TRUE)) * 0.03

  cld_m <- cld_result %>%
    dplyr::select(jednostka_skr, .group) %>%
    left_join(whisker_vals, by = "jednostka_skr") %>%
    mutate(
      metryka = metryki_labels[m],
      x_label = x_whisker + offset_val
    )

  cld_jedn_all <- bind_rows(cld_jedn_all, cld_m)
}

cat("\n=== PODSUMOWANIE TESTOW (JEDNOSTKI) ===\n")
for (m in metryki) {
  cat(sprintf("  %s: %s\n", metryki_labels[m], test_info_jedn[[m]]))
}

test_names_jedn <- unique(unlist(test_info_jedn))
subtitle_test_jedn <- paste(test_names_jedn, collapse = " / ")

# ---------- 13b. Boxploty per jednostka - zbiorczy z CLD ----------
df_long_jedn <- df_jedn %>%
  dplyr::select(jednostka_skr, all_of(metryki)) %>%
  pivot_longer(cols = all_of(metryki), names_to = "metryka", values_to = "wartosc") %>%
  filter(!is.na(wartosc)) %>%
  mutate(metryka = dplyr::recode(metryka, !!!metryki_labels))

p_box_jedn <- ggplot(df_long_jedn, aes(x = reorder(jednostka_skr, wartosc, FUN = median),
                                        y = wartosc, fill = jednostka_skr)) +
  geom_boxplot(alpha = 0.8, outlier.shape = 21, outlier.size = 2, width = 0.65) +
  geom_jitter(width = 0.12, alpha = 0.25, size = 1, color = "grey30") +
  geom_text(data = cld_jedn_all,
            aes(x = jednostka_skr, y = x_label, label = .group),
            inherit.aes = FALSE, size = 4.5, fontface = "bold", hjust = 0) +
  scale_fill_manual(values = paleta_jedn) +
  facet_wrap(~metryka, scales = "free", ncol = 3) +
  coord_flip() +
  labs(title = "Metryki bibliometryczne wg jednostki",
       subtitle = paste0("Wydział Przyrodniczo-Technologiczny, UPWr (", subtitle_test_jedn, ", p < 0.05)"),
       x = NULL, y = NULL) +
  theme_biblio +
  theme(legend.position = "none",
        panel.grid.major.y = element_blank(),
        panel.grid.major.x = element_line())

ggsave(file.path(PLOT_DIR_ZBIORCZE, "03_boxploty_jednostka.png"), p_box_jedn, width = 14, height = 7, dpi = 200)
cat("Zapisano:", file.path(PLOT_DIR_ZBIORCZE, "03_boxploty_jednostka.png"), "\n")

# ---------- 13c. Indywidualne boxploty jednostek z CLD ----------
for (m in metryki) {
  m_dir <- file.path(PLOT_DIR, metryki_dirs[m])
  m_label <- metryki_labels[m]
  m_test_j <- test_info_jedn[[m]]

  df_m_jedn <- df_jedn %>% filter(!is.na(.data[[m]]))
  cld_m_j <- cld_jedn_all %>% filter(metryka == m_label)

  p_box_j <- ggplot(df_m_jedn, aes(x = reorder(jednostka_skr, .data[[m]], FUN = median),
                                     y = .data[[m]], fill = jednostka_skr)) +
    geom_boxplot(alpha = 0.8, outlier.shape = 21, outlier.size = 2, width = 0.6) +
    geom_jitter(width = 0.12, alpha = 0.3, size = 1.2, color = "grey30") +
    geom_text(data = cld_m_j,
              aes(x = jednostka_skr, y = x_label, label = .group),
              inherit.aes = FALSE, size = 5, fontface = "bold", hjust = 0) +
    scale_fill_manual(values = paleta_jedn) +
    coord_flip() +
    labs(title = paste(m_label, "wg jednostki"),
         subtitle = paste0("Wydział Przyrodniczo-Technologiczny, UPWr (", m_test_j, ", p < 0.05)"),
         x = NULL, y = m_label) +
    theme_biblio +
    theme(plot.title = element_text(face = "bold", size = 17),
          plot.subtitle = element_text(size = 12, color = "grey40"),
          axis.text = element_text(size = 12),
          axis.title.x = element_text(size = 13),
          legend.position = "none",
          panel.grid.major.y = element_blank(),
          panel.grid.major.x = element_line())

  ggsave(file.path(m_dir, "03_boxplot_jednostka.png"), p_box_j, width = 9, height = 6, dpi = 200)
  cat("Zapisano:", file.path(m_dir, "03_boxplot_jednostka.png"), "\n")
}

# ---------- 14. Mapa ciepla korelacji (ggplot2) ----------
cor_long <- as.data.frame(as.table(cor_matrix)) %>%
  rename(x = Var1, y = Var2, r = Freq) %>%
  mutate(
    x = dplyr::recode(as.character(x), !!!metryki_labels),
    y = dplyr::recode(as.character(y), !!!metryki_labels)
  )

p_cor <- ggplot(cor_long, aes(x = x, y = y, fill = r)) +
  geom_tile(color = "white", linewidth = 1.5) +
  geom_text(aes(label = sprintf("%.2f", r)), size = 4.5, fontface = "bold") +
  scale_fill_gradient2(low = "#E64B35", mid = "white", high = "#3C5488",
                       midpoint = 0, limits = c(-1, 1),
                       name = "Korelacja") +
  labs(title = "Macierz korelacji metryk bibliometrycznych",
       subtitle = "Wydział Przyrodniczo-Technologiczny, UPWr",
       x = NULL, y = NULL) +
  theme_biblio +
  theme(axis.text.x = element_text(angle = 30, hjust = 1, size = 10),
        axis.text.y = element_text(size = 10),
        panel.grid = element_blank(),
        legend.position = "right")

ggsave(file.path(PLOT_DIR_ZBIORCZE, "04_korelacje_mapa.png"), p_cor, width = 8, height = 7, dpi = 200)
cat("Zapisano:", file.path(PLOT_DIR_ZBIORCZE, "04_korelacje_mapa.png"), "\n")

# ---------- 15. Zapis oczyszczonych danych ----------
write.csv(df, "output_bibliometria/WPT_oczyszczone.csv", row.names = FALSE, fileEncoding = "UTF-8")
cat("\nZapisano oczyszczone dane: output_bibliometria/WPT_oczyszczone.csv\n")

cat("\n=== ANALIZA ZAKONCZONA ===\n")
