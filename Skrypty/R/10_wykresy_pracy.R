# LTeX: enabled=false
# ============================================================
# 10 - Finalne wykresy + tabele do pracy dyplomowej
# Reuse wzorca theme_biblio z UPWr_bibliometria/Skrypty/R/02_czyszczenie_analiza_WPT.R:156-164
# ============================================================

library(ggplot2)
library(dplyr)
library(patchwork)

theme_praca <- theme_minimal(base_size = 13) +
  theme(
    plot.title = element_text(face = "bold", size = 15, margin = margin(b = 4)),
    plot.subtitle = element_text(color = "grey40", size = 11, margin = margin(b = 12)),
    strip.text = element_text(face = "bold", size = 11),
    panel.grid.minor = element_blank(),
    plot.margin = margin(12, 12, 12, 12)
  )

# Wspolna paleta dla uczelni
paleta_uczelnia <- c(
  upwr = "#3C5488",
  sggw = "#E64B35",
  urk  = "#00A087",
  uwm  = "#F39B7F"
)

# Wspolna paleta dla stanowisk (Okabe-Ito-podobna)
paleta_stan <- c(
  "asystent"         = "#999999",
  "adiunkt"          = "#56B4E9",
  "profesor uczelni" = "#009E73",
  "profesor"         = "#CC79A7"
)

# TODO: konsolidacja kluczowych wykresow z 06-09 do pojedynczych plikow finalnych
# TODO: figury kompozytowe (patchwork) dla zwiezlej prezentacji w pracy
