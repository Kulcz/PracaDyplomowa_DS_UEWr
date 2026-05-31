# LTeX: enabled=false
# ============================================================
# 05 - Analiza szeregow czasowych: publikacje i punkty MEiN rocznie
# Wydzial Przyrodniczo-Technologiczny (WPT)
# ============================================================
# Wejscie: output_bibliometria/WPT_publikacje_rocznie.csv (ze skryptow 04+06)
# Stanowisko/jednostka dolaczane po author_id z surowego CSV.
# ============================================================

library(dplyr)
library(tidyr)
library(ggplot2)
library(scales)

# ---------- Wczytanie i polaczenie ----------
roczne <- read.csv("output_bibliometria/WPT_publikacje_rocznie.csv", stringsAsFactors = FALSE)
raw <- read.csv("output_bibliometria/upwr_profiles_metrics_HTML_20260306_075402.csv",
                stringsAsFactors = FALSE)

meta <- raw %>%
  dplyr::select(author_id, stanowisko, jednostka) %>%
  mutate(stanowisko = case_when(
    stanowisko == "profesor Uczelni" ~ "profesor uczelni",
    !is.na(stanowisko) ~ tolower(stanowisko),
    TRUE ~ "nieokreślone"
  ))

df <- roczne %>% left_join(meta, by = "author_id")

ROK_BIEZACY <- as.integer(format(Sys.Date(), "%Y"))   # 2026 - rok niepelny
REFORMA     <- 2019L   # Ustawa 2.0: nowa skala punktow (100/140/200) - zlamanie szeregu
# Punkty analizujemy TYLKO od reformy (porownywalna skala); publikacje - pelny zakres.

PLOT_DIR <- "Wykresy/WPT/szeregi_czasowe"
dir.create(PLOT_DIR, recursive = TRUE, showWarnings = FALSE)

# ---------- Motyw i palety (spojne z 02/03) ----------
theme_biblio <- theme_minimal(base_size = 13) +
  theme(
    plot.title = element_text(face = "bold", size = 15, margin = margin(b = 4)),
    plot.subtitle = element_text(color = "grey40", size = 11, margin = margin(b = 12)),
    panel.grid.minor = element_blank(),
    plot.margin = margin(12, 12, 12, 12),
    legend.position = "bottom"
  )

paleta_stan <- c(
  "adiunkt"          = "#56B4E9",
  "profesor uczelni" = "#009E73",
  "profesor"         = "#CC79A7",
  "asystent"         = "#E69F00",
  "nieokreślone"     = "grey70"
)
paleta_jedn <- c("#3C5488", "#E64B35", "#00A087", "#F39B7F",
                 "#4DBBD5", "#8491B4", "#91D1C2", "#DC0000", "#7E6148")

jednostka_short <- function(x) {
  x %>%
    sub("Instytut ", "Inst. ", .) %>%
    sub("Katedra ", "Kat. ", .) %>%
    sub(", Żywienia Roślin i Ochrony Środowiska", "", .) %>%
    sub("Produkcji Roślinnej", "Prod. Rośl.", .) %>%
    sub("Inżynierii Rolniczej", "Inż. Rolniczej", .) %>%
    sub("Genetyki, Hodowli Roślin i Nasiennictwa", "Genetyki i Hodowli", .) %>%
    sub("Botaniki i Ekologii Roślin", "Botaniki i Ekologii", .)
}

subt_partial <- sprintf("Wydział Przyrodniczo-Technologiczny, UPWr (rok %d niepełny — stan na %s)",
                        ROK_BIEZACY, format(Sys.Date(), "%Y-%m-%d"))
subt_reforma <- sprintf("WPT, UPWr — okres po reformie (Ustawa 2.0, %d–%d); rok %d niepełny",
                        REFORMA, ROK_BIEZACY, ROK_BIEZACY)
breaks_reforma <- REFORMA:ROK_BIEZACY

# ============================================================
# 1. OGOLEM: publikacje i punkty / rok
# ============================================================
wpt_rok <- df %>%
  group_by(rok) %>%
  summarise(publikacje = sum(n_publikacji),
            punktowane = sum(n_punktowane),
            punkty = sum(suma_pkt), .groups = "drop") %>%
  mutate(zero_pkt = publikacje - punktowane)

# Stos: publikacje punktowane (>0) vs 0-punktowe (konferencje/popularne)
pub_long <- wpt_rok %>%
  dplyr::select(rok, punktowane, zero_pkt) %>%
  pivot_longer(c(punktowane, zero_pkt), names_to = "typ", values_to = "n") %>%
  mutate(typ = factor(dplyr::recode(typ,
            punktowane = "punktowane (>0 pkt)",
            zero_pkt   = "0 pkt (konf./popularne)"),
          levels = c("0 pkt (konf./popularne)", "punktowane (>0 pkt)")))

p1 <- ggplot(pub_long, aes(x = rok, y = n, fill = typ)) +
  geom_col(alpha = 0.9) +
  geom_vline(xintercept = ROK_BIEZACY - 0.5, linetype = "dashed", color = "grey60") +
  scale_fill_manual(values = c("punktowane (>0 pkt)" = "#3C5488",
                               "0 pkt (konf./popularne)" = "grey75"),
                    name = NULL) +
  scale_x_continuous(breaks = pretty_breaks(10)) +
  labs(title = "Liczba publikacji rocznie wg punktacji",
       subtitle = subt_partial, x = NULL, y = "Liczba publikacji") +
  theme_biblio
ggsave(file.path(PLOT_DIR, "01_publikacje_rok.png"), p1, width = 11, height = 5.5, dpi = 200)

p2 <- ggplot(filter(wpt_rok, rok >= REFORMA), aes(x = rok, y = punkty)) +
  geom_col(fill = "#E64B35", alpha = 0.85) +
  geom_vline(xintercept = ROK_BIEZACY - 0.5, linetype = "dashed", color = "grey60") +
  scale_x_continuous(breaks = breaks_reforma) +
  scale_y_continuous(labels = label_number(big.mark = " ")) +
  labs(title = "Suma punktów MEiN rocznie", subtitle = subt_reforma,
       x = NULL, y = "Punkty MEiN") +
  theme_biblio
ggsave(file.path(PLOT_DIR, "02_punkty_rok.png"), p2, width = 11, height = 5.5, dpi = 200)

# ============================================================
# 2. PER STANOWISKO (skladane pola)
# ============================================================
stan_order <- c("profesor", "profesor uczelni", "adiunkt", "asystent", "nieokreślone")
df_stan <- df %>%
  mutate(stanowisko = factor(stanowisko, levels = stan_order)) %>%
  group_by(rok, stanowisko) %>%
  summarise(publikacje = sum(n_publikacji), punktowane = sum(n_punktowane),
            punkty = sum(suma_pkt), .groups = "drop")

p3 <- ggplot(df_stan, aes(x = rok, y = publikacje, fill = stanowisko)) +
  geom_area(alpha = 0.85, color = "white", linewidth = 0.2) +
  scale_fill_manual(values = paleta_stan, name = "Stanowisko") +
  scale_x_continuous(breaks = pretty_breaks(10)) +
  labs(title = "Liczba publikacji rocznie wg stanowiska", subtitle = subt_partial,
       x = NULL, y = "Liczba publikacji") +
  theme_biblio
ggsave(file.path(PLOT_DIR, "03_publikacje_rok_stanowisko.png"), p3, width = 11, height = 6, dpi = 200)

p4 <- ggplot(filter(df_stan, rok >= REFORMA), aes(x = rok, y = punkty, fill = stanowisko)) +
  geom_area(alpha = 0.85, color = "white", linewidth = 0.2) +
  scale_fill_manual(values = paleta_stan, name = "Stanowisko") +
  scale_x_continuous(breaks = breaks_reforma) +
  scale_y_continuous(labels = label_number(big.mark = " ")) +
  labs(title = "Suma punktów MEiN rocznie wg stanowiska", subtitle = subt_reforma,
       x = NULL, y = "Punkty MEiN") +
  theme_biblio
ggsave(file.path(PLOT_DIR, "04_punkty_rok_stanowisko.png"), p4, width = 11, height = 6, dpi = 200)

# tylko publikacje PUNKTOWANE (>0 pkt) wg stanowiska - pelny zakres
p7 <- ggplot(df_stan, aes(x = rok, y = punktowane, fill = stanowisko)) +
  geom_area(alpha = 0.85, color = "white", linewidth = 0.2) +
  scale_fill_manual(values = paleta_stan, name = "Stanowisko") +
  scale_x_continuous(breaks = pretty_breaks(10)) +
  labs(title = "Liczba publikacji punktowanych (>0 pkt) rocznie wg stanowiska",
       subtitle = subt_partial, x = NULL, y = "Liczba publikacji punktowanych") +
  theme_biblio
ggsave(file.path(PLOT_DIR, "07_publikacje_punktowane_rok_stanowisko.png"), p7,
       width = 11, height = 6, dpi = 200)

# ============================================================
# 3. PER JEDNOSTKA (skladane pola; tylko ostatnie ~20 lat dla czytelnosci)
# ============================================================
df_jedn <- df %>%
  filter(!is.na(jednostka), rok >= ROK_BIEZACY - 20) %>%
  mutate(jedn = jednostka_short(jednostka)) %>%
  group_by(rok, jedn) %>%
  summarise(publikacje = sum(n_publikacji), punkty = sum(suma_pkt), .groups = "drop")

p5 <- ggplot(df_jedn, aes(x = rok, y = publikacje, fill = jedn)) +
  geom_area(alpha = 0.85, color = "white", linewidth = 0.2) +
  scale_fill_manual(values = paleta_jedn, name = "Jednostka") +
  scale_x_continuous(breaks = pretty_breaks(10)) +
  guides(fill = guide_legend(ncol = 2)) +
  labs(title = "Liczba publikacji rocznie wg jednostki",
       subtitle = paste0(subt_partial, " — ostatnie 20 lat"),
       x = NULL, y = "Liczba publikacji") +
  theme_biblio
ggsave(file.path(PLOT_DIR, "05_publikacje_rok_jednostka.png"), p5, width = 12, height = 7, dpi = 200)

p6 <- ggplot(filter(df_jedn, rok >= REFORMA), aes(x = rok, y = punkty, fill = jedn)) +
  geom_area(alpha = 0.85, color = "white", linewidth = 0.2) +
  scale_fill_manual(values = paleta_jedn, name = "Jednostka") +
  scale_x_continuous(breaks = breaks_reforma) +
  scale_y_continuous(labels = label_number(big.mark = " ")) +
  guides(fill = guide_legend(ncol = 2)) +
  labs(title = "Suma punktów MEiN rocznie wg jednostki",
       subtitle = subt_reforma,
       x = NULL, y = "Punkty MEiN") +
  theme_biblio
ggsave(file.path(PLOT_DIR, "06_punkty_rok_jednostka.png"), p6, width = 12, height = 7, dpi = 200)

# ---------- Podsumowanie ----------
cat("Zapisano 6 wykresow do:", PLOT_DIR, "\n\n")
cat("=== WPT: publikacje i punkty rocznie (ostatnie 12 lat) ===\n")
print(as.data.frame(tail(wpt_rok, 12)), row.names = FALSE)
cat(sprintf("\nLacznie (1990-%d): %d publikacji, %s pkt MEiN | %d autorow z publikacjami\n",
            ROK_BIEZACY, sum(wpt_rok$publikacje),
            format(sum(wpt_rok$punkty), big.mark = " "), length(unique(df$author_id))))
