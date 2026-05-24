#!/usr/bin/env Rscript
# Skrypt inicjalizacji środowiska R dla projektu PracaDyplomowa_DS_UEWr

cat("\n╔════════════════════════════════════════════╗\n")
cat("║     INICJALIZACJA ŚRODOWISKA R             ║\n")
cat("║     PracaDyplomowa_DS_UEWr                 ║\n")
cat("╚════════════════════════════════════════════╝\n\n")

# 1. Instalacja i inicjalizacja renv
if (!requireNamespace("renv", quietly = TRUE)) {
  cat("📦 Instaluję renv...\n")
  install.packages("renv", repos = "https://cloud.r-project.org/")
}

cat("🔧 Inicjalizuję renv...\n")
renv::init()

# 2. Lista pakietów do zainstalowania
packages <- c(
  # Core
  "tidyverse",      # ggplot2, dplyr, tidyr, readr, purrr, tibble, stringr, forcats
  "here",           # ścieżki niezależne od cwd
  "fs",             # operacje na plikach
  "glue",           # interpolacja stringów

  # Web scraping (Omega-PSIR)
  "RSelenium",
  "rvest",
  "xml2",

  # API klienty (OpenAlex, ORCID)
  "httr2",
  "jsonlite",
  "stringdist",     # fuzzy matching autor ↔ OpenAlex

  # Import/Export
  "readxl",
  "writexl",
  "openxlsx",

  # Statystyka klasyczna (etap EDA + ANOVA)
  "emmeans",
  "multcomp",
  "multcompView",
  "car",
  "dunn.test",
  "lme4",
  "lmerTest",       # p-values dla lme4

  # Wielowymiarowe / klastrowanie
  "FactoMineR",     # PCA
  "factoextra",     # wizualizacje + walidacja klastrowania
  "cluster",        # silhouette, gap statistic
  "corrplot",

  # Machine Learning — tidymodels stack
  "tidymodels",     # parsnip, recipes, rsample, yardstick, workflows, tune
  "ranger",         # Random Forest (szybki backend)
  "xgboost",
  "shapviz",        # SHAP wizualizacje
  "vip",            # variable importance (permutation, model-agnostic)

  # Sieci (warstwa wow — analiza współautorstwa)
  "igraph",
  "tidygraph",
  "ggraph",
  "visNetwork",     # interaktywne sieci (HTML/Shiny)

  # Orkiestracja
  "targets",
  "tarchetypes",

  # Wizualizacja
  "ggpubr",
  "patchwork",
  "scales",
  "GGally",
  "ggrepel",
  "plotly",

  # Raporty
  "knitr",
  "rmarkdown",
  "DT",
  "kableExtra",

  # Shiny (opcjonalny dashboard)
  "shiny",
  "bslib"
)

# 3. Funkcja instalująca z obsługą błędów
install_package <- function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    cat(sprintf("  📦 Instaluję %s...", pkg))
    tryCatch({
      install.packages(pkg,
                       repos = "https://cloud.r-project.org/",
                       quiet = TRUE,
                       dependencies = TRUE)
      cat(" ✓\n")
      return(TRUE)
    }, error = function(e) {
      cat(sprintf(" ❌\n     Błąd: %s\n", e$message))
      return(FALSE)
    })
  } else {
    cat(sprintf("  ✓ %s już zainstalowany\n", pkg))
    return(TRUE)
  }
}

# 4. Instalacja pakietów
cat("\n📊 Instalacja pakietów R:\n")
cat("════════════════════════════════════════════\n")

failed_packages <- c()
for (pkg in packages) {
  success <- install_package(pkg)
  if (!success) failed_packages <- c(failed_packages, pkg)
}

# 5. Podsumowanie
cat("\n════════════════════════════════════════════\n")
if (length(failed_packages) == 0) {
  cat("✅ Wszystkie pakiety zainstalowane!\n")
} else {
  cat("⚠️  Niektóre pakiety nie zostały zainstalowane:\n")
  for (pkg in failed_packages) cat(sprintf("   - %s\n", pkg))
  cat("\nSpróbuj zainstalować je ręcznie:\n")
  cat("install.packages(c(")
  cat(paste0('"', failed_packages, '"', collapse = ", "))
  cat("))\n")
}

# 6. Snapshot renv
cat("\n💾 Zapisuję snapshot renv...\n")
renv::snapshot()

cat("\n✅ Środowisko R gotowe do pracy!\n")
cat("   Użyj renv::restore() aby odtworzyć środowisko\n")
cat("   Użyj renv::snapshot() po instalacji nowych pakietów\n\n")
