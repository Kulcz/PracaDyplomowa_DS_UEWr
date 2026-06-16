# LTeX: enabled=false
# ============================================================
# 13 - Figura porownawcza dynamiki: OpenAlex vs Omega-PSIR
# Zestawia CAGR produktywnosci per uczelnia z dwoch zrodel, by pokazac,
# ze pelne pokrycie CRIS rozwarstwia i przestawia ranking wzgledem OpenAlex.
# Input:  output/dynamika_cagr.csv (OpenAlex), output/dynamika_omega_cagr.csv
# Output: Wykresy/praca/fig_06_dynamika_porownanie.png
# ============================================================

library(dplyr)
library(ggplot2)
library(readr)
library(here)
library(scales)

UCZ_LEVELS <- c("upwr", "sggw", "urk", "uwm")
UCZ_LABELS <- c(upwr = "UPWr", sggw = "SGGW", urk = "URK", uwm = "UWM")

oa <- read_csv(here("output", "dynamika_cagr.csv"), show_col_types = FALSE) %>%
  transmute(uczelnia, cagr, cagr_lo, cagr_hi, zrodlo = "OpenAlex")
om <- read_csv(here("output", "dynamika_omega_cagr.csv"), show_col_types = FALSE) %>%
  transmute(uczelnia, cagr, cagr_lo, cagr_hi, zrodlo = "Omega-PSIR (pełny katalog)")

dat <- bind_rows(oa, om) %>%
  mutate(uczelnia = factor(uczelnia, levels = UCZ_LEVELS),
         zrodlo   = factor(zrodlo, levels = c("OpenAlex", "Omega-PSIR (pełny katalog)")))

p <- ggplot(dat, aes(uczelnia, cagr, fill = zrodlo)) +
  geom_col(position = position_dodge(width = 0.75), width = 0.7) +
  geom_errorbar(aes(ymin = cagr_lo, ymax = cagr_hi),
                position = position_dodge(width = 0.75), width = 0.2, color = "grey30") +
  geom_text(aes(label = percent(cagr, accuracy = 0.1)),
            position = position_dodge(width = 0.75), vjust = -0.5, size = 3.2) +
  geom_hline(yintercept = 0, color = "grey50") +
  scale_x_discrete(labels = UCZ_LABELS) +
  scale_y_continuous(labels = percent) +
  scale_fill_manual(values = c("OpenAlex" = "#7fb3d5",
                               "Omega-PSIR (pełny katalog)" = "#1b6ca8"),
                    name = "Źródło danych") +
  labs(title = "Tempo rozwoju produktywności (CAGR output na badacza) z dwóch źródeł",
       subtitle = "Pełne pokrycie CRIS rozwarstwia i przestawia ranking względem OpenAlex. Słupki błędów = 95% CI.",
       x = NULL, y = "CAGR (output / badacz)") +
  theme_minimal(base_size = 12) +
  theme(legend.position = "top")

ggsave(here("Wykresy", "praca", "fig_06_dynamika_porownanie.png"), p,
       width = 9, height = 5.5, dpi = 200)
cat("Zapisano: Wykresy/praca/fig_06_dynamika_porownanie.png\n")
