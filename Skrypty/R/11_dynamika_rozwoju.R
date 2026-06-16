# LTeX: enabled=false
# ============================================================
# 11 - Dynamika rozwoju potencjalu naukowego uczelni (PROTOTYP / OpenAlex)
#
# Pytanie: ktora z 4 uczelni rozwija sie szybciej pod wzgledem
# PRODUKTYWNOSCI (output/rok)? Definicja przyjeta przez uzytkownika.
#
# UWAGA - to PROTOTYP na danych OpenAlex. Ograniczenia (jawne):
#  - Bias pokrycia: match per uczelnia SGGW 89.3 / UPWr 79.7 / URK 77.8 /
#    UWM 67.1% (URK naprawiony z 47.5%). Liczby BEZWZGLEDNE per uczelnia sa
#    wiec nieporownywalne. Dlatego:
#    (a) normalizujemy per zmatchowany autor (output intensity),
#    (b) glowny wniosek o TEMPIE opieramy na wzroscie WZGLEDNYM (index = 100
#        w okresie bazowym) i na CAGR z regresji log-liniowej - te miary sa
#        odporne na STALY w czasie bias liczebnosci.
#  - Survivorship / "dorastanie kohorty": widzimy tylko obecnie zatrudnionych;
#    wzrost outputu po czesci odzwierciedla wchodzenie mlodej kadry w produktywnosc,
#    nie sam rozwoj instytucji. Robustness: wariant "kohorta ustalona" (first_pub<=2010).
#  - 2026 niepelny -> uciete. Analiza na 2006-2025 (trend na 2008-2024).
#
# Input:  Dane/openalex/publications.csv, Dane/openalex/author_match.csv
# Output: output/dynamika.rds, output/dynamika_cagr.csv,
#         Wykresy/dynamika/0{1,2,3}_*.png
# ============================================================

library(dplyr)
library(tidyr)
library(ggplot2)
library(readr)
library(here)
library(fs)
library(broom)

dir_create(here("Wykresy", "dynamika"))

UCZ_LEVELS <- c("upwr", "sggw", "urk", "uwm")
UCZ_LABELS <- c(upwr = "UPWr", sggw = "SGGW", urk = "URK", uwm = "UWM")
YR_MIN <- 2006L; YR_MAX <- 2025L          # 2026 niepelny -> precz
TREND_MIN <- 2008L; TREND_MAX <- 2024L    # okno trendu (brzegi obciete)
BASE_YEARS <- 2008:2010                   # okres bazowy dla indeksu = 100

# --- Dane ---
pubs  <- read_csv(here("Dane", "openalex", "publications.csv"), show_col_types = FALSE)
match <- read_csv(here("Dane", "openalex", "author_match.csv"), show_col_types = FALSE)

# Mapowanie autor OpenAlex -> uczelnia (tylko zaakceptowane matche)
auth_ucz <- match %>%
  filter(match_accepted) %>%
  transmute(anchor_author_id = openalex_id,
            uczelnia = factor(uczelnia, levels = UCZ_LEVELS))

# Denominatory: liczba zmatchowanych autorow per uczelnia
n_matched <- auth_ucz %>% count(uczelnia, name = "n_autorow")
cat("Zmatchowani autorzy per uczelnia (denominator normalizacji):\n")
print(n_matched)

# Pierwszy rok publikacji per autor (proxy "wieku akademickiego" -> kohorta)
first_pub <- pubs %>%
  filter(!is.na(publication_year)) %>%
  group_by(anchor_author_id) %>%
  summarise(first_pub = min(publication_year), .groups = "drop")

# --- Prace z przypisana uczelnia, w oknie lat ---
pw <- pubs %>%
  filter(!is.na(publication_year),
         publication_year >= YR_MIN, publication_year <= YR_MAX) %>%
  inner_join(auth_ucz, by = "anchor_author_id") %>%
  left_join(first_pub, by = "anchor_author_id")

# UWAGA: praca wspolautorska 2 osob z tej samej uczelni liczona raz na autora
# -> tu liczymy "publikacje-autora" (kazdy zmatchowany autor wnosi swoje prace).
# To wlasciwa jednostka dla outputu per autor.

# ============================================================
# 1) Output per rok i per zmatchowany autor
# ============================================================
ts <- pw %>%
  count(uczelnia, publication_year, name = "n_pub") %>%
  complete(uczelnia, publication_year = YR_MIN:YR_MAX, fill = list(n_pub = 0)) %>%
  left_join(n_matched, by = "uczelnia") %>%
  mutate(pub_per_autor = n_pub / n_autorow)

# Indeks wzgledny: srednia okresu bazowego = 100 (per uczelnia)
base_lvl <- ts %>%
  filter(publication_year %in% BASE_YEARS) %>%
  group_by(uczelnia) %>%
  summarise(base = mean(pub_per_autor), .groups = "drop")
ts <- ts %>%
  left_join(base_lvl, by = "uczelnia") %>%
  mutate(index = 100 * pub_per_autor / base)

# ============================================================
# 2) Tempo wzrostu: regresja log-liniowa -> CAGR per uczelnia
#    log(pub_per_autor) ~ rok ; nachylenie b -> CAGR = exp(b)-1
# ============================================================
fit_cagr <- function(d) {
  d <- d %>% filter(publication_year >= TREND_MIN, publication_year <= TREND_MAX,
                    pub_per_autor > 0)
  m <- lm(log(pub_per_autor) ~ publication_year, data = d)
  ci <- confint(m)["publication_year", ]
  tibble(slope = coef(m)["publication_year"],
         cagr = exp(coef(m)["publication_year"]) - 1,
         cagr_lo = exp(ci[1]) - 1, cagr_hi = exp(ci[2]) - 1,
         r2 = summary(m)$r.squared)
}
cagr_tbl <- ts %>% group_by(uczelnia) %>% group_modify(~ fit_cagr(.x)) %>% ungroup()

# Recent vs early (odpornosciowo, bez modelu)
rec_early <- ts %>%
  mutate(faza = case_when(publication_year %in% 2011:2014 ~ "early",
                          publication_year %in% 2021:2024 ~ "recent",
                          TRUE ~ NA_character_)) %>%
  filter(!is.na(faza)) %>%
  group_by(uczelnia, faza) %>%
  summarise(m = mean(pub_per_autor), .groups = "drop") %>%
  pivot_wider(names_from = faza, values_from = m) %>%
  mutate(recent_vs_early = recent / early)

cagr_tbl <- cagr_tbl %>% left_join(rec_early, by = "uczelnia")
cat("\n=== Tempo rozwoju produktywnosci (output/autor) ===\n")
print(cagr_tbl %>% mutate(across(where(is.numeric), ~round(.x, 3))))

# ============================================================
# 3) Robustness: kohorta ustalona (first_pub <= 2010)
#    eliminuje artefakt "dorastania" mlodej kadry
# ============================================================
ts_estab <- pw %>%
  filter(first_pub <= 2010) %>%
  count(uczelnia, publication_year, name = "n_pub") %>%
  complete(uczelnia, publication_year = YR_MIN:YR_MAX, fill = list(n_pub = 0))
n_estab <- pw %>% filter(first_pub <= 2010) %>%
  distinct(uczelnia, anchor_author_id) %>% count(uczelnia, name = "n_autorow")
ts_estab <- ts_estab %>% left_join(n_estab, by = "uczelnia") %>%
  mutate(pub_per_autor = n_pub / n_autorow)
cagr_estab <- ts_estab %>% group_by(uczelnia) %>% group_modify(~ fit_cagr(.x)) %>%
  ungroup() %>% transmute(uczelnia, cagr_kohorta_ustalona = cagr)
cagr_tbl <- cagr_tbl %>% left_join(cagr_estab, by = "uczelnia")

# ============================================================
# WYKRESY
# ============================================================
lab_u <- function(x) UCZ_LABELS[as.character(x)]
pal <- c(upwr = "#1b9e77", sggw = "#d95f02", urk = "#7570b3", uwm = "#e7298a")

# 01 - trajektorie output/autor
p1 <- ggplot(ts, aes(publication_year, pub_per_autor, color = uczelnia)) +
  geom_line(linewidth = 0.9) + geom_point(size = 1.4) +
  scale_color_manual(values = pal, labels = UCZ_LABELS, name = "Uczelnia") +
  labs(title = "Produktywnosc: publikacje na zmatchowanego autora rocznie",
       subtitle = "Zrodlo: OpenAlex (prototyp). Poziomy obciazone biasem pokrycia - patrz tempo (fig 02-03).",
       x = NULL, y = "Publikacje / autor / rok") +
  theme_minimal(base_size = 12)
ggsave(here("Wykresy", "dynamika", "01_output_per_autor.png"), p1,
       width = 9, height = 5.5, dpi = 200)

# 02 - wzrost wzgledny (index = 100 w 2008-2010)
p2 <- ggplot(ts, aes(publication_year, index, color = uczelnia)) +
  geom_hline(yintercept = 100, linetype = "dashed", color = "grey60") +
  geom_line(linewidth = 0.9) + geom_point(size = 1.4) +
  scale_color_manual(values = pal, labels = UCZ_LABELS, name = "Uczelnia") +
  labs(title = "Tempo rozwoju: wzrost wzgledny produktywnosci",
       subtitle = paste0("Indeks = 100 dla sredniej ", min(BASE_YEARS), "-", max(BASE_YEARS),
                         ". Miara odporna na staly bias liczebnosci."),
       x = NULL, y = "Indeks (baza = 100)") +
  theme_minimal(base_size = 12)
ggsave(here("Wykresy", "dynamika", "02_wzrost_wzgledny.png"), p2,
       width = 9, height = 5.5, dpi = 200)

# 03 - CAGR per uczelnia z CI
p3 <- ggplot(cagr_tbl, aes(reorder(uczelnia, cagr), cagr, fill = uczelnia)) +
  geom_col(width = 0.65) +
  geom_errorbar(aes(ymin = cagr_lo, ymax = cagr_hi), width = 0.2) +
  geom_text(aes(label = scales::percent(cagr, accuracy = 0.1)), vjust = -0.6, size = 3.6) +
  scale_fill_manual(values = pal, guide = "none") +
  scale_x_discrete(labels = UCZ_LABELS) +
  scale_y_continuous(labels = scales::percent) +
  labs(title = "Roczne tempo wzrostu produktywnosci (CAGR)",
       subtitle = paste0("Regresja log-liniowa, ", TREND_MIN, "-", TREND_MAX,
                         ". Slupki bledow = 95% CI."),
       x = NULL, y = "CAGR (output/autor)") +
  theme_minimal(base_size = 12)
ggsave(here("Wykresy", "dynamika", "03_cagr.png"), p3,
       width = 8, height = 5, dpi = 200)

# --- Zapis ---
saveRDS(list(ts = ts, cagr = cagr_tbl, n_matched = n_matched,
             params = list(yr = c(YR_MIN, YR_MAX), trend = c(TREND_MIN, TREND_MAX),
                           base = BASE_YEARS)),
        here("output", "dynamika.rds"))
write_csv(cagr_tbl, here("output", "dynamika_cagr.csv"))

cat("\nZapisano: output/dynamika.rds, output/dynamika_cagr.csv, Wykresy/dynamika/0{1,2,3}_*.png\n")
