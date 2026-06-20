# LTeX: enabled=false
# ============================================================
# 12 - Dynamika rozwoju potencjalu naukowego (WERSJA OMEGA-PSIR)
#
# Wariant "do pracy" analizy z 11_dynamika_rozwoju.R. Roznice:
#  - Zrodlo: listy publikacji CRIS Omega-PSIR (scrape_publications.py), NIE OpenAlex.
#  - 100% proby (brak biasu matchu OpenAlex - kluczowa przewaga, zwlaszcza URK).
#  - Pelny katalog (polskie czasopisma, ksiazki, konferencje niewidoczne w OpenAlex).
#  - Bonus: produktywnosc wazona punktami MEiN (sum_pkt), gdzie dostepne.
#
# Definicja rozwoju (wybor uzytkownika): PRODUKTYWNOSC = output/rok.
#
# Ograniczenia (zachowane z wersji OpenAlex):
#  - Survivorship/dorastanie kohorty: tylko obecnie zatrudnieni -> wariant
#    "kohorta ustalona" (first_pub <= 2010).
#  - Rok biezacy niepelny -> uciety. CAGR liczony na oknie wewnetrznym.
#  - Uwaga: tempo (CAGR, indeks) jest niezmiennicze wzgledem stalej liczebnosci,
#    wiec porownanie miedzyuczelniane tempa jest odporne.
#
# Input:  Dane/raw/publications_omega/pub_years.csv, Dane/master/profiles_features.csv
# Output: output/dynamika_omega.rds, output/dynamika_omega_cagr.csv,
#         Wykresy/dynamika/1{1,2,3,4}_omega_*.png
# ============================================================

library(dplyr)
library(tidyr)
library(ggplot2)
library(readr)
library(here)
library(fs)

dir_create(here("Wykresy", "dynamika"))

UCZ_LEVELS <- c("upwr", "sggw", "urk", "uwm")
UCZ_LABELS <- c(upwr = "UPWr", sggw = "SGGW", urk = "URK", uwm = "UWM")
pal <- c(upwr = "#1b9e77", sggw = "#d95f02", urk = "#7570b3", uwm = "#e7298a")

YR_NOW   <- 2026L   # rok referencyjny pracy - przypiety (bylo Sys.Date()); zamraza YR_MAX=2025 i TREND_MAX=2024 zgodnie z 11_dynamika_rozwoju.R
YR_MIN   <- 2006L; YR_MAX <- YR_NOW - 1L          # rok biezacy niepelny -> precz
TREND_MIN <- 2008L; TREND_MAX <- YR_NOW - 2L      # okno trendu (brzeg obciety)
BASE_YEARS <- 2008:2010

# --- Dane ---
pub <- read_csv(here("Dane", "raw", "publications_omega", "pub_years.csv"),
                show_col_types = FALSE) %>%
  filter(rok >= YR_MIN, rok <= YR_MAX) %>%
  mutate(uczelnia = factor(uczelnia, levels = UCZ_LEVELS))

# Denominator: liczba autorow z danymi per uczelnia (aktywni badacze w probie)
n_aut <- pub %>% distinct(uczelnia, author_id) %>% count(uczelnia, name = "n_autorow")
cat("Autorzy z publikacjami per uczelnia (denominator):\n"); print(n_aut)

# Pierwszy rok publikacji per autor (kohorta)
first_pub <- pub %>% group_by(author_id) %>%
  summarise(first_pub = min(rok), .groups = "drop")

# ============================================================
# 1) Szereg: publikacje (i punkty) per rok, per autor
# ============================================================
ts <- pub %>%
  group_by(uczelnia, rok) %>%
  summarise(n_pub = sum(n_pub), sum_pkt = sum(sum_pkt, na.rm = TRUE),
            pkt_dostepne = any(!is.na(sum_pkt)), .groups = "drop") %>%
  complete(uczelnia, rok = YR_MIN:YR_MAX,
           fill = list(n_pub = 0, sum_pkt = 0, pkt_dostepne = FALSE)) %>%
  left_join(n_aut, by = "uczelnia") %>%
  mutate(pub_per_autor = n_pub / n_autorow,
         pkt_per_autor = sum_pkt / n_autorow)

base_lvl <- ts %>% filter(rok %in% BASE_YEARS) %>%
  group_by(uczelnia) %>% summarise(base = mean(pub_per_autor), .groups = "drop")
ts <- ts %>% left_join(base_lvl, by = "uczelnia") %>%
  mutate(index = 100 * pub_per_autor / base)

# ============================================================
# 2) Tempo: CAGR z regresji log-liniowej
# ============================================================
fit_cagr <- function(d, yvar = "pub_per_autor") {
  d <- d %>% filter(rok >= TREND_MIN, rok <= TREND_MAX, .data[[yvar]] > 0)
  if (nrow(d) < 4) return(tibble(cagr = NA, cagr_lo = NA, cagr_hi = NA, r2 = NA))
  m <- lm(log(d[[yvar]]) ~ d$rok)
  ci <- confint(m)[2, ]
  tibble(cagr = exp(coef(m)[2]) - 1, cagr_lo = exp(ci[1]) - 1,
         cagr_hi = exp(ci[2]) - 1, r2 = summary(m)$r.squared)
}
cagr_tbl <- ts %>% group_by(uczelnia) %>% group_modify(~ fit_cagr(.x)) %>% ungroup()

# recent vs early
rec_early <- ts %>%
  mutate(faza = case_when(rok %in% 2011:2014 ~ "early",
                          rok %in% (YR_MAX-3):YR_MAX ~ "recent", TRUE ~ NA)) %>%
  filter(!is.na(faza)) %>% group_by(uczelnia, faza) %>%
  summarise(m = mean(pub_per_autor), .groups = "drop") %>%
  pivot_wider(names_from = faza, values_from = m) %>%
  mutate(recent_vs_early = recent / early)
cagr_tbl <- cagr_tbl %>% left_join(rec_early, by = "uczelnia")

# 3) Robustness: kohorta ustalona (first_pub <= 2010)
estab_ids <- first_pub %>% filter(first_pub <= 2010) %>% pull(author_id)
ts_estab <- pub %>% filter(author_id %in% estab_ids) %>%
  group_by(uczelnia, rok) %>% summarise(n_pub = sum(n_pub), .groups = "drop") %>%
  complete(uczelnia, rok = YR_MIN:YR_MAX, fill = list(n_pub = 0)) %>%
  left_join(pub %>% filter(author_id %in% estab_ids) %>%
              distinct(uczelnia, author_id) %>% count(uczelnia, name = "n_autorow"),
            by = "uczelnia") %>%
  mutate(pub_per_autor = n_pub / n_autorow)
cagr_estab <- ts_estab %>% group_by(uczelnia) %>% group_modify(~ fit_cagr(.x)) %>%
  ungroup() %>% transmute(uczelnia, cagr_kohorta_ustalona = cagr)
cagr_tbl <- cagr_tbl %>% left_join(cagr_estab, by = "uczelnia")

cat("\n=== Tempo rozwoju produktywnosci (Omega-PSIR) ===\n")
print(cagr_tbl %>% mutate(across(where(is.numeric), ~round(.x, 3))))

# ============================================================
# WYKRESY
# ============================================================
# 11 - trajektorie output/autor
p1 <- ggplot(ts, aes(rok, pub_per_autor, color = uczelnia)) +
  geom_line(linewidth = 0.9) + geom_point(size = 1.4) +
  scale_color_manual(values = pal, labels = UCZ_LABELS, name = "Uczelnia") +
  labs(title = "Produktywnosc: publikacje na badacza rocznie (Omega-PSIR)",
       subtitle = "Pelny katalog CRIS, 100% proby. Bez biasu pokrycia OpenAlex.",
       x = NULL, y = "Publikacje / badacz / rok") +
  theme_minimal(base_size = 12)
ggsave(here("Wykresy", "dynamika", "11_omega_output_per_autor.png"), p1,
       width = 9, height = 5.5, dpi = 200)

# 12 - wzrost wzgledny
p2 <- ggplot(ts, aes(rok, index, color = uczelnia)) +
  geom_hline(yintercept = 100, linetype = "dashed", color = "grey60") +
  geom_line(linewidth = 0.9) + geom_point(size = 1.4) +
  scale_color_manual(values = pal, labels = UCZ_LABELS, name = "Uczelnia") +
  labs(title = "Tempo rozwoju: wzrost wzgledny produktywnosci (Omega-PSIR)",
       subtitle = paste0("Indeks = 100 dla sredniej ", min(BASE_YEARS), "-", max(BASE_YEARS), "."),
       x = NULL, y = "Indeks (baza = 100)") +
  theme_minimal(base_size = 12)
ggsave(here("Wykresy", "dynamika", "12_omega_wzrost_wzgledny.png"), p2,
       width = 9, height = 5.5, dpi = 200)

# 13 - CAGR z CI
p3 <- ggplot(cagr_tbl, aes(reorder(uczelnia, cagr), cagr, fill = uczelnia)) +
  geom_col(width = 0.65) +
  geom_errorbar(aes(ymin = cagr_lo, ymax = cagr_hi), width = 0.2) +
  geom_text(aes(label = scales::percent(cagr, accuracy = 0.1)), vjust = -0.6, size = 3.6) +
  scale_fill_manual(values = pal, guide = "none") +
  scale_x_discrete(labels = UCZ_LABELS) + scale_y_continuous(labels = scales::percent) +
  labs(title = "Roczne tempo wzrostu produktywnosci (CAGR, Omega-PSIR)",
       subtitle = paste0("Regresja log-liniowa, ", TREND_MIN, "-", TREND_MAX, ". 95% CI."),
       x = NULL, y = "CAGR (output/badacz)") +
  theme_minimal(base_size = 12)
ggsave(here("Wykresy", "dynamika", "13_omega_cagr.png"), p3, width = 8, height = 5, dpi = 200)

# 14 - produktywnosc wazona MEiN (tylko gdy punkty dostepne dla uczelni)
ts_pkt <- ts %>% group_by(uczelnia) %>% filter(any(pkt_dostepne)) %>% ungroup()
if (nrow(ts_pkt) > 0) {
  p4 <- ggplot(ts_pkt, aes(rok, pkt_per_autor, color = uczelnia)) +
    geom_line(linewidth = 0.9) + geom_point(size = 1.4) +
    scale_color_manual(values = pal, labels = UCZ_LABELS, name = "Uczelnia") +
    labs(title = "Produktywnosc wazona: punkty MEiN na badacza rocznie",
         subtitle = "Tylko uczelnie eksponujace punkty per publikacja w CRIS.",
         x = NULL, y = "Punkty MEiN / badacz / rok") +
    theme_minimal(base_size = 12)
  ggsave(here("Wykresy", "dynamika", "14_omega_pkt_per_autor.png"), p4,
         width = 9, height = 5.5, dpi = 200)
}

# --- Zapis ---
saveRDS(list(ts = ts, cagr = cagr_tbl, n_autorow = n_aut,
             params = list(yr = c(YR_MIN, YR_MAX), trend = c(TREND_MIN, TREND_MAX))),
        here("output", "dynamika_omega.rds"))
write_csv(cagr_tbl, here("output", "dynamika_omega_cagr.csv"))
cat("\nZapisano: output/dynamika_omega.rds, output/dynamika_omega_cagr.csv, Wykresy/dynamika/1*_omega_*.png\n")
