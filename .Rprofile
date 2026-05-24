# Aktywacja renv (tylko jeśli istnieje)
if (file.exists("renv/activate.R")) {
  source("renv/activate.R")
  cat("✓ renv aktywowane\n")
}

# Ustawienia domyślne
options(
  repos = c(CRAN = "https://cloud.r-project.org/"),
  stringsAsFactors = FALSE,
  encoding = "UTF-8",
  scipen = 999,  # Wyłącz notację naukową
  width = 120    # Szerokość konsoli
)

# Informacja o projekcie
cat("\n════════════════════════════════════════════\n")
cat("📊 Projekt:", basename(getwd()), "\n")
cat("📅 Data:", format(Sys.Date(), "%Y-%m-%d"), "\n")
cat("🔧 R version:", R.version$version.string, "\n")
cat("════════════════════════════════════════════\n\n")

# Sprawdź czy renv jest zainstalowane
if (!requireNamespace("renv", quietly = TRUE)) {
  cat("⚠️  renv nie jest zainstalowane.\n")
  cat("   Uruchom: install.packages('renv')\n")
  cat("   Następnie: renv::init()\n\n")
}
