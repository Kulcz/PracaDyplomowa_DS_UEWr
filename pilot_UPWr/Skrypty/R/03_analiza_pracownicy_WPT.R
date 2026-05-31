# LTeX: enabled=false
# ============================================================
# 03 - Analiza indywidualna pracownikow: Wydz. Przyrodniczo-Technologiczny
# ============================================================

library(dplyr)
library(tidyr)
library(ggplot2)
library(stringr)
library(readr)
library(openxlsx)

# ---------- 1. Wczytanie danych ----------
df <- read.csv("output_bibliometria/WPT_oczyszczone.csv", stringsAsFactors = FALSE)
cat("Wczytano rekordow:", nrow(df), "\n")

# ---------- 2. Definicje ----------
metryki <- c("h_index_wos", "sum_IF", "sum_MEiN")

metryki_labels <- c(
  h_index_wos = "h-index (WoS)",
  sum_IF      = "Sumaryczny IF",
  sum_MEiN    = "Punktacja MEiN"
)

metryki_dirs <- c(
  h_index_wos = "h_index_wos",
  sum_IF      = "sumaryczny_IF",
  sum_MEiN    = "punktacja_MEiN"
)

paleta_stan <- c(
  "adiunkt"          = "#56B4E9",
  "profesor uczelni" = "#009E73",
  "profesor"         = "#CC79A7"
)

TOP_N <- 15

PLOT_DIR <- "Wykresy/WPT/pracownicy"
dir.create(PLOT_DIR, recursive = TRUE, showWarnings = FALSE)

theme_biblio <- theme_minimal(base_size = 13) +
  theme(
    plot.title = element_text(face = "bold", size = 15, margin = margin(b = 4)),
    plot.subtitle = element_text(color = "grey40", size = 11, margin = margin(b = 12)),
    strip.text = element_text(face = "bold", size = 11),
    panel.grid.minor = element_blank(),
    panel.grid.major.y = element_blank(),
    plot.margin = margin(12, 12, 12, 12)
  )

# ---------- 3. Skrocenie nazw jednostek ----------
df <- df %>%
  mutate(
    jednostka_short = jednostka %>%
      str_replace("Katedra ", "Kat. ") %>%
      str_replace("Instytut ", "Inst. ") %>%
      str_replace(", Żywienia Roślin i Ochrony Środowiska", "") %>%
      str_replace("Produkcji Roślinnej", "Prod. Rośl.") %>%
      str_replace("Inżynierii Rolniczej", "Inż. Rolniczej")
  )

# Skrocenie nazwisk: "Imie Nazwisko" -> "I. Nazwisko"
df <- df %>%
  mutate(
    profil_short = str_replace(profil, "^(\\p{L})\\p{L}+\\s", "\\1. ")
  )

# ---------- 4. Standaryzacja stanowisk ----------
df <- df %>%
  mutate(stanowisko = case_when(
    stanowisko == "profesor Uczelni" ~ "profesor uczelni",
    !is.na(stanowisko) ~ tolower(stanowisko),
    TRUE ~ NA_character_
  ))

# ============================================================
# 5. TOP-15 RANKINGI (lollipop charts)
# ============================================================
cat("\n=== TOP-15 RANKINGI ===\n")

for (m in metryki) {

  df_top <- df %>%
    filter(!is.na(.data[[m]])) %>%
    arrange(desc(.data[[m]])) %>%
    head(TOP_N) %>%
    mutate(profil_short = factor(profil_short, levels = rev(profil_short)))

  cat("\nTop-15", metryki_labels[m], ":\n")
  print(df_top %>% dplyr::select(profil, stanowisko, jednostka_short, !!sym(m)))

  # Kolor wedlug stanowiska (NA = szary)
  p <- ggplot(df_top, aes(x = .data[[m]], y = profil_short, color = stanowisko)) +
    geom_segment(aes(x = 0, xend = .data[[m]], yend = profil_short),
                 linewidth = 0.8, show.legend = FALSE) +
    geom_point(size = 3.5) +
    scale_color_manual(values = paleta_stan, na.value = "grey50",
                       name = "Stanowisko") +
    labs(
      title = paste0("Top-", TOP_N, ": ", metryki_labels[m]),
      subtitle = "Wydział Przyrodniczo-Technologiczny, UPWr",
      x = metryki_labels[m],
      y = NULL
    ) +
    theme_biblio +
    theme(
      panel.grid.major.x = element_line(color = "grey90"),
      axis.text.y = element_text(size = 11),
      legend.position = "bottom"
    )

  fname <- paste0("01_top15_", metryki_dirs[m], ".png")
  ggsave(file.path(PLOT_DIR, fname), p, width = 10, height = 7, dpi = 200)
  cat("Zapisano:", file.path(PLOT_DIR, fname), "\n")
}

# ============================================================
# 6. PROFIL RADAROWY TOP-10 (facetowany wykres radarowy)
# ============================================================
cat("\n=== PROFIL RADAROWY TOP-10 ===\n")

# Ranking laczny: srednia rang z 3 metryk
df_ranks <- df %>%
  filter(!is.na(h_index_wos), !is.na(sum_IF), !is.na(sum_MEiN)) %>%
  mutate(
    rank_h   = rank(-h_index_wos, ties.method = "average"),
    rank_IF  = rank(-sum_IF, ties.method = "average"),
    rank_MEiN = rank(-sum_MEiN, ties.method = "average"),
    rank_mean = (rank_h + rank_IF + rank_MEiN) / 3
  ) %>%
  arrange(rank_mean)

top10 <- df_ranks %>% head(10)

cat("Top-10 (srednia rang):\n")
print(top10 %>% dplyr::select(profil, stanowisko, h_index_wos, sum_IF, sum_MEiN, rank_mean))

# Normalizacja 0-1 dla wykresu radarowego (na calym zbiorze)
df_norm <- df_ranks %>%
  mutate(
    h_index_wos_n = (h_index_wos - min(h_index_wos)) / (max(h_index_wos) - min(h_index_wos)),
    sum_IF_n      = (sum_IF - min(sum_IF)) / (max(sum_IF) - min(sum_IF)),
    sum_MEiN_n    = (sum_MEiN - min(sum_MEiN)) / (max(sum_MEiN) - min(sum_MEiN))
  )

top10_norm <- df_norm %>%
  head(10) %>%
  dplyr::select(profil_short, h_index_wos_n, sum_IF_n, sum_MEiN_n) %>%
  pivot_longer(-profil_short, names_to = "metryka", values_to = "wartosc") %>%
  mutate(metryka = dplyr::recode(metryka,
    h_index_wos_n = "h-index\n(WoS)",
    sum_IF_n      = "Sumaryczny\nIF",
    sum_MEiN_n    = "Punktacja\nMEiN"
  ))

p_radar <- ggplot(top10_norm, aes(x = metryka, y = wartosc, group = profil_short)) +
  geom_polygon(fill = "#3C5488", alpha = 0.15, color = "#3C5488", linewidth = 0.8) +
  geom_point(color = "#3C5488", size = 2) +
  coord_polar() +
  facet_wrap(~profil_short, ncol = 5) +
  scale_y_continuous(limits = c(0, 1), breaks = c(0, 0.5, 1)) +
  labs(
    title = "Profil bibliometryczny Top-10 pracowników",
    subtitle = "Wydział Przyrodniczo-Technologiczny, UPWr (wartości znormalizowane 0–1)",
    x = NULL, y = NULL
  ) +
  theme_biblio +
  theme(
    axis.text.y = element_text(size = 7, color = "grey50"),
    axis.text.x = element_text(size = 9, face = "bold"),
    strip.text = element_text(size = 10, face = "bold"),
    panel.grid.major.x = element_line(color = "grey80"),
    panel.grid.major.y = element_line(color = "grey85")
  )

ggsave(file.path(PLOT_DIR, "04_profil_radarowy_top10.png"), p_radar,
       width = 14, height = 7, dpi = 200)
cat("Zapisano:", file.path(PLOT_DIR, "04_profil_radarowy_top10.png"), "\n")

# ============================================================
# 7. SCATTER: IF vs MEiN (rozmiar = h-index, kolor = stanowisko)
# ============================================================
cat("\n=== SCATTER: IF vs MEiN ===\n")

df_scatter <- df %>%
  filter(!is.na(sum_IF), !is.na(sum_MEiN), !is.na(h_index_wos))

# Regresja liniowa: IF vs MEiN
mod_lm <- lm(sum_MEiN ~ sum_IF, data = df_scatter)
mod_sum <- summary(mod_lm)
r2 <- mod_sum$r.squared
p_val <- pf(mod_sum$fstatistic[1], mod_sum$fstatistic[2], mod_sum$fstatistic[3],
            lower.tail = FALSE)

cat(sprintf("Regresja: R² = %.3f, p = %.2e\n", r2, p_val))
cat(sprintf("  MEiN = %.2f + %.2f * IF\n", coef(mod_lm)[1], coef(mod_lm)[2]))

reg_label <- sprintf("R² = %.3f, p %s",
                     r2,
                     ifelse(p_val < 0.001, "< 0.001", sprintf("= %.3f", p_val)))

p_scatter <- ggplot(df_scatter,
                    aes(x = sum_IF, y = sum_MEiN)) +
  geom_smooth(method = "lm", formula = y ~ x,
              color = "#E64B35", fill = "#E64B35", alpha = 0.12,
              linewidth = 0.9) +
  geom_point(aes(size = h_index_wos, color = stanowisko), alpha = 0.65) +
  annotate("text", x = 200, y = 500,
           label = reg_label, hjust = 0, size = 4.5, color = "#E64B35", fontface = "bold") +
  scale_color_manual(values = paleta_stan, na.value = "grey50",
                     name = "Stanowisko") +
  scale_size_continuous(range = c(1.5, 8), name = "h-index (WoS)") +
  labs(
    title = "Sumaryczny IF vs Punktacja MEiN",
    subtitle = "Wydział Przyrodniczo-Technologiczny, UPWr (rozmiar = h-index WoS)",
    x = "Sumaryczny IF",
    y = "Punktacja MEiN"
  ) +
  theme_biblio +
  theme(
    panel.grid.major.x = element_line(color = "grey90"),
    legend.position = "right"
  )

ggsave(file.path(PLOT_DIR, "05_scatter_IF_vs_MEiN.png"), p_scatter,
       width = 10, height = 7, dpi = 200)
cat("Zapisano:", file.path(PLOT_DIR, "05_scatter_IF_vs_MEiN.png"), "\n")

# ============================================================
# 8. EKSPORT DO EXCELA
# ============================================================
cat("\n=== EKSPORT RANKINGU DO EXCELA ===\n")

wb <- createWorkbook()

# Arkusz: ranking laczny
df_ranking <- df_ranks %>%
  dplyr::select(profil, stanowisko, jednostka, h_index_wos, sum_IF, sum_MEiN, rank_mean) %>%
  mutate(rank_mean = round(rank_mean, 1)) %>%
  arrange(rank_mean)

addWorksheet(wb, "Ranking laczny")
writeData(wb, "Ranking laczny", df_ranking)

# Arkusze per metryka
for (m in metryki) {
  df_m <- df %>%
    filter(!is.na(.data[[m]])) %>%
    arrange(desc(.data[[m]])) %>%
    dplyr::select(profil, stanowisko, jednostka, !!sym(m))

  sheet_name <- metryki_labels[m]
  addWorksheet(wb, sheet_name)
  writeData(wb, sheet_name, df_m)
}

out_xlsx <- "output_bibliometria/WPT_ranking_pracownikow.xlsx"
saveWorkbook(wb, out_xlsx, overwrite = TRUE)
cat("Zapisano:", out_xlsx, "\n")

cat("\n=== GOTOWE ===\n")
