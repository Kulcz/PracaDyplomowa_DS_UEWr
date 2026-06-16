# LTeX: enabled=false
# ============================================================
# 00 - Orkiestracja calego pipeline analitycznego (warstwa R)
#
# Uruchamia skrypty 02-14 w kolejnosci zaleznosci i na koniec walidacje liczb.
# Uruchamiac z cwd = root projektu (sciezki przez here()):
#   Rscript Skrypty/R/00_run_all.R
#
# PREREKWIZYTY (kroki reczne / spoza warstwy R, NIE odpalane tutaj):
#   - ETAP 1+2 scrapingu Omega-PSIR: Skrypty/Python/scrape.py (reczny filtr w UI)
#     -> Dane/raw/<uczelnia>_rolnictwo_i_ogrodnictwo_<timestamp>.csv
#   - Listy publikacji do dynamiki: Skrypty/Python/scrape_publications.py
#     -> Dane/raw/publications_omega/pub_years.csv  (potrzebne dla skryptu 12)
#
# KROKI SIECIOWE (OpenAlex API, wolne ~kilkanascie min, wymagaja lacza):
#   03 (match) i 04 (works). Domyslnie POMIJANE jesli artefakty istnieja.
#   Wymus pelny przebieg:  RUN_NETWORK=1 Rscript Skrypty/R/00_run_all.R
# ============================================================

suppressMessages(library(here))

RUN_NETWORK <- nzchar(Sys.getenv("RUN_NETWORK"))
RENDER      <- nzchar(Sys.getenv("RENDER_QMD"))

run_step <- function(path, label) {
  cat(sprintf("\n========== %s : %s ==========\n", label, path))
  t0 <- Sys.time()
  source(here("Skrypty", "R", path), local = new.env(), echo = FALSE)
  cat(sprintf("[OK] %s (%.0fs)\n", label, as.numeric(difftime(Sys.time(), t0, units = "secs"))))
}

# ---- Warstwa 0: przygotowanie danych ----
run_step("02_czyszczenie.R", "02 czyszczenie")

# Kroki sieciowe (OpenAlex) - pomijane jesli artefakty juz sa
match_ok <- file.exists(here("Dane", "openalex", "author_match.csv"))
works_ok <- file.exists(here("Dane", "openalex", "publications.csv"))
if (RUN_NETWORK || !match_ok) run_step("03_openalex_match.R", "03 match OpenAlex") else
  cat("\n[SKIP] 03 match - author_match.csv istnieje (RUN_NETWORK=1 by wymusic)\n")
if (RUN_NETWORK || !works_ok) run_step("04_openalex_works.R", "04 works OpenAlex") else
  cat("\n[SKIP] 04 works - publications.csv istnieje (RUN_NETWORK=1 by wymusic)\n")

run_step("05_features.R", "05 features (master)")

# ---- Warstwa 1: EDA + statystyka ----
run_step("06_eda_anova.R", "06 EDA + testy")

# ---- Warstwa 2: klastrowanie ----
run_step("07_klastrowanie_pca.R", "07 klastrowanie k=2 + PCA")
run_step("07b_klastrowanie_k3.R", "07b wariant k=3")

# ---- Warstwa 3: modele ----
run_step("08_modele_predykcja.R", "08 model ilosciowy (high_impact)")
run_step("14_model_jakosc.R",     "14 model jakosciowy (FWCI>1)")

# ---- Warstwa 4: sieci ----
run_step("09_sieci_wspolautorstwa.R", "09 sieci + Louvain")

# ---- Warstwa dynamiki ----
run_step("11_dynamika_rozwoju.R", "11 dynamika OpenAlex")
run_step("12_dynamika_omega.R",   "12 dynamika Omega-PSIR")
run_step("13_fig_dynamika_porownanie.R", "13 figura porownania dynamiki (fig_06)")

# ---- Figury do pracy ----
run_step("10_wykresy_pracy.R", "10 figury do pracy (fig_01-05)")

# ---- Walidacja liczb ----
cat("\n########## WALIDACJA ##########\n")
source(here("Skrypty", "R", "validate_outputs.R"), local = new.env())

# ---- Opcjonalny render pracy ----
if (RENDER) {
  cat("\n========== RENDER praca.qmd ==========\n")
  system2("quarto", c("render", here("Praca", "praca.qmd")))
}

cat("\n[KONIEC] Pipeline 02-14 uruchomiony.\n")
