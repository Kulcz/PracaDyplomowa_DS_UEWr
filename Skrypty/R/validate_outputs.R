# LTeX: enabled=false
# ============================================================
# validate_outputs.R - kontrola kluczowych liczb pipeline'u
#
# Sprawdza, czy artefakty zgadzaja sie z liczbami raportowanymi w pracy.
# Zwraca status 0 (wszystko OK) lub 1 (rozjazd) -> przydatne w 00_run_all.R
# i przed finalnym commitem. Uruchamiac z cwd = root projektu.
#   Rscript Skrypty/R/validate_outputs.R
# ============================================================

suppressMessages({library(here); library(readr); library(dplyr)})

fails <- 0L
chk <- function(label, actual, expected, tol = 0) {
  ok <- if (tol > 0) abs(actual - expected) <= tol else isTRUE(all.equal(actual, expected))
  cat(sprintf("[%s] %-42s oczek=%s  jest=%s\n",
              if (ok) "OK " else "!!!", label, format(expected), format(actual)))
  if (!ok) fails <<- fails + 1L
  invisible(ok)
}

# 1) Master dataset: 462 x 30
pf <- read_csv(here("Dane", "master", "profiles_features.csv"), show_col_types = FALSE)
chk("profiles_features rows", nrow(pf), 462)
chk("profiles_features cols", ncol(pf), 30)

# 2) Match OpenAlex: 367 / 462
am <- read_csv(here("Dane", "openalex", "author_match.csv"), show_col_types = FALSE)
chk("OpenAlex match accepted", sum(am$match_accepted, na.rm = TRUE), 367)

# 3) Klastrowanie: n = 449, k = 2
cl <- readRDS(here("output", "clusters.rds"))
chk("klastrowanie n", nrow(cl$df), 449)
chk("klastrowanie k_opt", cl$k_opt, 2)

# 4) Siec: giant component 265 wezlow, modularnosc ~0.856
nm <- readRDS(here("output", "network_metrics.rds"))
chk("siec giant component V", as.integer(nm$global_stats[["V"]]), 265)
chk("siec modularnosc Louvain", round(nm$modularity, 3), 0.856, tol = 0.002)

# 5) Model jakosciowy: prevalencja FWCI>1 ~ 0.639 (234/366)
mj <- readRDS(here("output", "model_jakosc.rds"))
chk("model jakosci prevalencja", round(mj$prevalence, 3), 0.639, tol = 0.002)

# 6) Model ilosciowy: target high_impact istnieje
mr <- readRDS(here("output", "model_results.rds"))
chk("model ilosciowy ma test_metrics", !is.null(mr$test_metrics), TRUE)

cat(sprintf("\n=> %s (%d rozjazdow)\n",
            if (fails == 0L) "WALIDACJA OK" else "WALIDACJA: WYKRYTO ROZJAZDY", fails))
if (!interactive()) quit(status = if (fails == 0L) 0L else 1L)
