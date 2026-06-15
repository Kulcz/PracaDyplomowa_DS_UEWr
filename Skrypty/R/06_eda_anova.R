# LTeX: enabled=false
# ============================================================
# 06 - EDA + statystyka klasyczna (warstwa 1 z planu DS)
# 2-czynnikowa analiza: uczelnia x stanowisko, z auto-wyborem testu.
#
# Decyzje metodyczne (2026-06-13):
#  - Czynniki: uczelnia (4) x stanowisko (3: adiunkt / profesor uczelni /
#    profesor). Poziom "asystent" wykluczony - n=26, brak w UWM (0) i UPWr (1),
#    komorek interakcji nie da sie estymowac.
#  - kategoria MEiN (A/B+) jest WSPOLLINIOWA z uczelnia (UWM = jedyny B+),
#    wiec NIE wchodzi do modelu (byloby aliased). Raportowana wylacznie
#    opisowo; confounding uczelnia<->kategoria do sekcji Ograniczenia.
#  - Metryki MEiN (sum_MEiN, if_to_mein) maja SGGW = 100% NA -> dla tych
#    metryk analiza automatycznie redukuje sie do 3 uczelni (droplevels).
#    Liczba uczelni i n raportowane per metryka.
# Input:  Dane/master/profiles_features.csv
# Output: Wykresy/eda/*.png, output/eda_summary.rds, output/eda_opisowe*.csv
# ============================================================

library(dplyr)
library(tidyr)
library(ggplot2)
library(readr)
library(here)
library(fs)
library(emmeans)
library(multcomp)
library(multcompView)
library(car)
library(dunn.test)

stopifnot(file_exists(here("Dane", "master", "profiles_features.csv")))
df <- read_csv(here("Dane", "master", "profiles_features.csv"), show_col_types = FALSE)

STANOWISKA <- c("adiunkt", "profesor uczelni", "profesor")
STAN_LABELS <- c(adiunkt = "adiunkt", `profesor uczelni` = "prof. uczelni",
                 profesor = "profesor")

# Wymuszamy faktoryzacje (csv tego nie zachowuje) i wykluczamy asystentow + NA.
df <- df %>%
  mutate(
    uczelnia   = factor(uczelnia, levels = c("upwr", "sggw", "urk", "uwm")),
    kategoria  = factor(kategoria, levels = c("A", "B+")),
    stanowisko = factor(stanowisko, levels = STANOWISKA)  # asystent + NA -> NA
  ) %>%
  filter(!is.na(stanowisko))

cat(sprintf("[DANE] n = %d po wykluczeniu asystentow i NA stanowiska\n", nrow(df)))
print(table(df$uczelnia, df$stanowisko))

PLOT_DIR <- here("Wykresy", "eda"); dir_create(PLOT_DIR)
OUT_DIR  <- here("output");          dir_create(OUT_DIR)

metryki <- c("h_index_wos", "sum_IF", "if_per_pub", "n_pub", "sum_MEiN", "if_to_mein")
metryki_labels <- c(
  h_index_wos = "h-index (WoS)",
  sum_IF      = "Sumaryczny IF",
  if_per_pub  = "IF na publikacje",
  n_pub       = "Liczba publikacji",
  sum_MEiN    = "Sumaryczna punktacja MEiN",
  if_to_mein  = "IF / MEiN (proxy internacjonalizacji)"
)
# Metryki o niepelnym pokryciu uczelni (raportowane osobno w opisie wynikow).
metryki_mein <- c("sum_MEiN", "if_to_mein")  # SGGW = 100% NA

theme_eda <- theme_minimal(base_size = 13) +
  theme(
    plot.title    = element_text(face = "bold", size = 15, margin = margin(b = 4)),
    plot.subtitle = element_text(color = "grey40", size = 11, margin = margin(b = 12)),
    strip.text    = element_text(face = "bold", size = 11),
    panel.grid.minor = element_blank(),
    plot.margin   = margin(12, 12, 12, 12)
  )

paleta_uczelnia  <- c(upwr = "#3C5488", sggw = "#E64B35", urk = "#00A087", uwm = "#F39B7F")
paleta_stanowisko <- c(adiunkt = "#91D1C2", `profesor uczelni` = "#4DBBD5",
                       profesor = "#3C5488")

# ---------- 1a. Statystyki opisowe per (uczelnia x stanowisko) ----------
opisowe <- df %>%
  pivot_longer(all_of(metryki), names_to = "metryka", values_to = "x") %>%
  filter(!is.na(x)) %>%
  group_by(metryka, uczelnia, stanowisko) %>%
  summarise(
    n      = n(),
    mean   = round(mean(x), 2),
    median = round(median(x), 2),
    sd     = round(sd(x), 2),
    iqr    = round(IQR(x), 2),
    .groups = "drop"
  )

write_csv(opisowe, file.path(OUT_DIR, "eda_opisowe.csv"))
cat("[OPISOWE] zapisano", file.path(OUT_DIR, "eda_opisowe.csv"), "\n")

# ---------- 1b. Opis kategorii MEiN (A vs B+) - WYLACZNIE opisowo ----------
# kategoria jest wspolliniowa z uczelnia (UWM=B+, reszta=A), wiec nie
# modelujemy jej; podajemy srednie/mediany jako material do Dyskusji.
opisowe_kategoria <- df %>%
  pivot_longer(all_of(metryki), names_to = "metryka", values_to = "x") %>%
  filter(!is.na(x)) %>%
  group_by(metryka, kategoria) %>%
  summarise(
    n      = n(),
    mean   = round(mean(x), 2),
    median = round(median(x), 2),
    sd     = round(sd(x), 2),
    .groups = "drop"
  )
write_csv(opisowe_kategoria, file.path(OUT_DIR, "eda_opisowe_kategoria.csv"))
cat("[OPISOWE] zapisano", file.path(OUT_DIR, "eda_opisowe_kategoria.csv"),
    "(kategoria tylko opisowo - confounding z uczelnia)\n")

# ---------- 2. Rozklady metryk (fasetowane per metryka, fill = uczelnia) ----------
df_long <- df %>%
  pivot_longer(all_of(metryki), names_to = "metryka", values_to = "wartosc") %>%
  filter(!is.na(wartosc)) %>%
  mutate(metryka = dplyr::recode(metryka, !!!metryki_labels))

p_density <- ggplot(df_long, aes(x = wartosc, fill = uczelnia)) +
  geom_density(alpha = 0.5, color = NA) +
  facet_wrap(~metryka, scales = "free", ncol = 3) +
  scale_fill_manual(values = paleta_uczelnia) +
  labs(title = "Rozkłady metryk bibliometrycznych per uczelnia",
       x = NULL, y = "Gęstość") +
  theme_eda +
  theme(legend.position = "bottom")

ggsave(file.path(PLOT_DIR, "01_rozklady_per_uczelnia.png"),
       p_density, width = 12, height = 7, dpi = 200)

# ---------- 3. Heatmapa korelacji metryk ----------
cor_m <- cor(df[, metryki], use = "pairwise.complete.obs")
cor_long <- as.data.frame(as.table(cor_m)) %>%
  rename(x = Var1, y = Var2, r = Freq)

p_cor <- ggplot(cor_long, aes(x, y, fill = r)) +
  geom_tile() +
  geom_text(aes(label = sprintf("%.2f", r)), size = 4) +
  scale_fill_gradient2(low = "#3C5488", mid = "white", high = "#E64B35",
                       midpoint = 0, limits = c(-1, 1)) +
  labs(title = "Macierz korelacji metryk", x = NULL, y = NULL) +
  theme_eda + theme(axis.text.x = element_text(angle = 30, hjust = 1))

ggsave(file.path(PLOT_DIR, "02_korelacje.png"),
       p_cor, width = 8, height = 7, dpi = 200)

# ---------- 4. 2-czynnikowa analiza: uczelnia x stanowisko ----------
# Strategia: per metryka diagnostyka -> auto-wybor:
#   ANOVA parametryczna (interakcja) + emmeans(Tukey) + CLD per komorka
#   Kruskal-Wallis na interaction(uczelnia, stanowisko) + Dunn + CLD per komorka
# Przy metrykach MEiN (SGGW=NA) droplevels redukuje uczelnia do 3 poziomow.
cat("\n=== DIAGNOSTYKA ZALOZEN (2-CZYNNIKOWA: uczelnia x stanowisko) ===\n")
test_info <- list()
cld_all   <- data.frame()
anova_tables <- list()
metryka_uczelnie <- list()  # ktore uczelnie weszly per metryka

for (m in metryki) {
  df_m <- df %>%
    filter(!is.na(.data[[m]]), !is.na(stanowisko), !is.na(uczelnia)) %>%
    mutate(uczelnia = droplevels(uczelnia), stanowisko = droplevels(stanowisko))

  df_m$komorka <- interaction(df_m$uczelnia, df_m$stanowisko, drop = TRUE)
  metryka_uczelnie[[m]] <- levels(df_m$uczelnia)

  if (nrow(df_m) < 20 ||
      nlevels(df_m$uczelnia) < 2 || nlevels(df_m$stanowisko) < 2 ||
      nlevels(df_m$komorka) < 4) {
    cat(sprintf("\n--- %s --- POMINIETO (n=%d, uczelni=%d, stanowisk=%d, komorek=%d)\n",
                metryki_labels[m], nrow(df_m), nlevels(df_m$uczelnia),
                nlevels(df_m$stanowisko), nlevels(df_m$komorka)))
    next
  }

  form_full <- as.formula(paste(m, "~ uczelnia * stanowisko"))
  mod <- aov(form_full, data = df_m)

  cat(sprintf("\n--- %s --- (n=%d, uczelnie: %s)\n",
              metryki_labels[m], nrow(df_m),
              paste(levels(df_m$uczelnia), collapse = ", ")))

  # Shapiro-Wilk na resztach (probka, jesli n > 5000 R wywala blad)
  res <- residuals(mod)
  res_sample <- if (length(res) > 5000) sample(res, 5000) else res
  sw <- shapiro.test(res_sample)
  cat(sprintf("Shapiro-Wilk (reszty, n=%d): W = %.4f, p = %.4f %s\n",
              length(res_sample), sw$statistic, sw$p.value,
              ifelse(sw$p.value < 0.05, "-> ODRZUCONA normalnosc", "-> OK")))

  # Levene na pelnej interakcji (komorki)
  lev <- leveneTest(as.formula(paste(m, "~ komorka")), data = df_m)
  lev_p <- lev$`Pr(>F)`[1]
  cat(sprintf("Levene (%d komorek): F = %.4f, p = %.4f %s\n",
              nlevels(df_m$komorka), lev$`F value`[1], lev_p,
              ifelse(lev_p < 0.05, "-> ODRZUCONA jednorodnosc", "-> OK")))

  use_nonparam <- (sw$p.value < 0.05) || (lev_p < 0.05)

  if (!use_nonparam) {
    cat(">> Zalozenia spelnione -> 2-way ANOVA + Tukey HSD na interakcji\n")
    print(summary(mod))
    anova_tables[[m]] <- summary(mod)[[1]]

    emm <- emmeans(mod, ~ uczelnia * stanowisko)
    cld_result <- cld(emm, Letters = letters, adjust = "tukey") %>%
      as.data.frame() %>%
      mutate(.group = trimws(.group))

    test_info[[m]] <- "2-way ANOVA + Tukey HSD"
  } else {
    cat(">> Zalozenia naruszone -> Kruskal-Wallis na komorkach + Dunn(Bonferroni)\n")
    kw <- kruskal.test(as.formula(paste(m, "~ komorka")), data = df_m)
    cat(sprintf("Kruskal-Wallis: chi2 = %.2f, df = %d, p = %.6g\n",
                kw$statistic, kw$parameter, kw$p.value))

    dunn_res <- dunn.test(df_m[[m]], df_m$komorka,
                          method = "bonferroni", altp = TRUE, kw = FALSE)

    # Budujemy macierz p i CLD przez multcompLetters
    levs <- levels(droplevels(df_m$komorka))
    pmat <- matrix(1, length(levs), length(levs), dimnames = list(levs, levs))
    for (i in seq_along(dunn_res$comparisons)) {
      pair <- strsplit(dunn_res$comparisons[i], " - ")[[1]]
      if (all(pair %in% levs)) {
        pmat[pair[1], pair[2]] <- dunn_res$altP.adjusted[i]
        pmat[pair[2], pair[1]] <- dunn_res$altP.adjusted[i]
      }
    }

    pair_vec <- setNames(
      as.vector(pmat[lower.tri(pmat)]),
      apply(combn(levs, 2), 2, paste, collapse = "-")
    )
    cld_letters <- multcompLetters(pair_vec, threshold = 0.05)

    medians <- df_m %>%
      group_by(uczelnia, stanowisko) %>%
      summarise(emmean = median(.data[[m]], na.rm = TRUE), .groups = "drop") %>%
      mutate(komorka = interaction(uczelnia, stanowisko, drop = TRUE))

    cld_result <- data.frame(
      komorka = names(cld_letters$Letters),
      .group  = as.character(cld_letters$Letters),
      stringsAsFactors = FALSE
    ) %>%
      left_join(medians, by = "komorka")

    test_info[[m]] <- "Kruskal-Wallis (komorki) + Dunn-Bonferroni"
  }

  cld_result$metryka <- metryki_labels[m]
  cld_all <- bind_rows(cld_all, cld_result)
}

cat("\n=== PODSUMOWANIE TESTOW ===\n")
for (m in names(test_info))
  cat(sprintf("  %-38s : %s  [%d uczelni]\n", metryki_labels[m], test_info[[m]],
              length(metryka_uczelnie[[m]])))

# ---------- 5. Boxploty (metryka x uczelnia, os = stanowisko) z literami CLD ----------
df_box <- df %>%
  pivot_longer(all_of(metryki), names_to = "metryka", values_to = "wartosc") %>%
  filter(!is.na(wartosc)) %>%
  mutate(metryka_label = dplyr::recode(metryka, !!!metryki_labels))

# Pozycja liter = gorny was per komorka
whisker_vals <- df_box %>%
  group_by(metryka_label, uczelnia, stanowisko) %>%
  summarise(
    q75  = quantile(wartosc, 0.75, na.rm = TRUE),
    iqr  = IQR(wartosc, na.rm = TRUE),
    vmax = max(wartosc, na.rm = TRUE),
    y_w  = pmin(q75 + 1.5 * iqr, vmax),
    .groups = "drop"
  )

cld_for_plot <- cld_all %>%
  rename(metryka_label = metryka) %>%
  left_join(whisker_vals, by = c("metryka_label", "uczelnia", "stanowisko"))

p_box <- ggplot(df_box, aes(x = stanowisko, y = wartosc, fill = stanowisko)) +
  geom_boxplot(outlier.size = 0.6, alpha = 0.85) +
  geom_text(data = cld_for_plot,
            aes(x = stanowisko, y = y_w, label = .group),
            vjust = -0.4, fontface = "bold", size = 3.2, inherit.aes = FALSE) +
  facet_grid(metryka_label ~ uczelnia, scales = "free_y", switch = "y") +
  scale_fill_manual(values = paleta_stanowisko, labels = STAN_LABELS) +
  scale_x_discrete(labels = STAN_LABELS) +
  labs(title = "Metryki bibliometryczne: uczelnia × stanowisko",
       subtitle = "Litery: grupy jednorodne (CLD) per metryka; metryki MEiN bez SGGW (100% NA)",
       x = NULL, y = NULL) +
  theme_eda +
  theme(legend.position = "none",
        strip.placement = "outside",
        axis.text.x = element_text(angle = 30, hjust = 1))

ggsave(file.path(PLOT_DIR, "03_boxploty_cld.png"),
       p_box, width = 14, height = 18, dpi = 200)

# ---------- 6. Zapis sumaryczny ----------
saveRDS(
  list(
    opisowe           = opisowe,
    opisowe_kategoria = opisowe_kategoria,
    test_info         = test_info,
    cld_all           = cld_all,
    anova_tables      = anova_tables,
    correlations      = cor_m,
    metryka_uczelnie  = metryka_uczelnie
  ),
  file.path(OUT_DIR, "eda_summary.rds")
)

cat(sprintf("\nZapisano: %s\nWykresy: %s\n",
            file.path(OUT_DIR, "eda_summary.rds"), PLOT_DIR))
