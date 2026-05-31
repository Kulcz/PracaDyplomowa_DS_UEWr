# LTeX: enabled=false
# ============================================================
# 04 - Scraper listy publikacji (szeregi czasowe): rok + punkty MEiN
# Wydzial Przyrodniczo-Technologiczny (WPT)
# ============================================================
# Render JS bez Selenium: Chrome headless --dump-dom.
# Lista tab=publications grupowana: rok (header0) -> punkty (header1) -> wpisy.
# Wynik: long-format profil x rok x {n_publikacji, suma_pkt}.
# Tylko base R (brak zaleznosci od pakietow renv).
# ============================================================

# ---------- Ustawienia ----------
LIMIT      <- Inf        # prototyp: 3 profile. Pelny przebieg: Inf
PS         <- 200        # max akceptowane przez portal (dozwolone: 20/50/100/200)
VT_BUDGET  <- 15000      # ms na render JS w chrome headless
DELAY_SEC  <- 1.5        # przerwa miedzy profilami (grzecznosc)
SAVE_EVERY <- 10         # autosave co N profili
MAX_TRIES  <- 3          # ponowienia gdy lista sie nie dorenderuje (rosnacy budzet)
RESUME     <- TRUE       # pomin profile juz obecne w OUT_CSV (wznawianie)
YEAR_MIN  <- 1990L
YEAR_MAX  <- as.integer(format(Sys.Date(), "%Y"))

CHROME <- Sys.which("google-chrome")
if (!nzchar(CHROME)) CHROME <- Sys.which("chromium")
stopifnot(nzchar(CHROME))

RAW_CSV   <- "output_bibliometria/upwr_profiles_metrics_HTML_20260306_075402.csv"
OUT_CSV   <- "output_bibliometria/WPT_publikacje_rocznie.csv"
DEBUG_DIR <- "output_bibliometria/debug_html"
dir.create(DEBUG_DIR, recursive = TRUE, showWarnings = FALSE)

pub_url <- function(author_id) {
  sprintf("https://bazawiedzy.upwr.edu.pl/info/author/%s?r=publication&ps=%d&tab=publications&lang=pl",
          author_id, PS)
}

# ---------- Pobranie wyrenderowanego DOM ----------
fetch_dom <- function(author_id, budget) {
  tmp <- tempfile(fileext = ".html")
  on.exit(unlink(tmp), add = TRUE)
  budget <- if (missing(budget)) VT_BUDGET else budget
  args <- c("--headless=new", "--disable-gpu", "--no-sandbox",
            sprintf("--virtual-time-budget=%d", budget),
            "--dump-dom", pub_url(author_id))
  tryCatch(
    system2(CHROME, shQuote(args), stdout = tmp, stderr = FALSE, timeout = 90),
    error = function(e) 1L
  )
  if (!file.exists(tmp)) return(NA_character_)
  html <- paste(readLines(tmp, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  if (!nzchar(html)) return(NA_character_)
  html
}

count_rowentry <- function(html) {
  g <- gregexpr('<div class="rowEntry">', html, fixed = TRUE)[[1]]
  if (g[1] == -1L) 0L else length(g)
}

# ---------- Parser: rok + punkty per publikacja ----------
# Sekwencyjny przejazd DOM: utrzymuj biezacy rok (header0) i punkty (header1);
# kazdy rowEntry dziedziczy te wartosci.
parse_publikacje <- function(html, author_id) {
  pat <- paste0(
    'resultListHeader0">\\s*\\d{4}',     # rok grupy
    '|resultListHeader1">\\s*\\d+\\s*<',  # punkty grupy
    '|<div class="rowEntry">'             # wpis publikacji
  )
  toks <- regmatches(html, gregexpr(pat, html, perl = TRUE))[[1]]
  empty <- data.frame(author_id = character(), rok = integer(),
                      punkty = integer(), stringsAsFactors = FALSE)
  if (length(toks) == 0) return(empty)

  cur_year <- NA_integer_
  cur_pts  <- NA_integer_
  years <- integer(0); pts <- integer(0)

  for (tok in toks) {
    if (grepl("resultListHeader0", tok, fixed = TRUE)) {
      cur_year <- as.integer(sub('.*">\\s*(\\d{4}).*', "\\1", tok))
    } else if (grepl("resultListHeader1", tok, fixed = TRUE)) {
      cur_pts <- as.integer(sub('.*">\\s*(\\d+).*', "\\1", tok))
    } else {                       # rowEntry
      years <- c(years, cur_year)
      pts   <- c(pts,  cur_pts)
    }
  }

  df <- data.frame(author_id = author_id, rok = years, punkty = pts,
                   stringsAsFactors = FALSE)
  df <- df[!is.na(df$rok) & df$rok >= YEAR_MIN & df$rok <= YEAR_MAX, , drop = FALSE]
  df$punkty[is.na(df$punkty)] <- 0L   # brak punktow = 0 (publikacja nadal liczona)
  df
}

# walidacja: czy header0 to faktycznie lata (a nie inny uklad grupowania)
header0_are_years <- function(html) {
  h0 <- regmatches(html, gregexpr('resultListHeader0">\\s*[^<]+', html, perl = TRUE))[[1]]
  if (length(h0) == 0) return(FALSE)
  yrs <- as.integer(regmatches(h0, regexpr("\\d{4}", h0)))
  yrs <- yrs[!is.na(yrs)]
  if (length(yrs) == 0) return(FALSE)
  mean(yrs >= YEAR_MIN & yrs <= YEAR_MAX) > 0.8
}

# ---------- Wczytanie author_id WPT ----------
d <- read.csv(RAW_CSV, stringsAsFactors = FALSE)
wpt <- d[!is.na(d$wydzial) &
         d$wydzial == "Wydział Przyrodniczo-Technologiczny" &
         !is.na(d$author_id) & nzchar(d$author_id),
         c("profil", "author_id", "sum_MEiN")]
n_all <- nrow(wpt)

# ---------- Wznawianie: pomin profile juz zrobione lub puste ----------
PUSTE_TXT <- "output_bibliometria/WPT_publikacje_puste.txt"
prev_agg <- NULL
done_ids <- character(0)
if (RESUME && file.exists(OUT_CSV)) {
  prev_agg <- read.csv(OUT_CSV, stringsAsFactors = FALSE)
  done_ids <- unique(prev_agg$author_id)
}
if (RESUME && file.exists(PUSTE_TXT)) {
  done_ids <- union(done_ids, readLines(PUSTE_TXT, warn = FALSE))
}

todo <- wpt[!(wpt$author_id %in% done_ids), ]
if (is.finite(LIMIT)) todo <- head(todo, LIMIT)
cat(sprintf("WPT profili: %d | juz zrobione: %d | do zrobienia: %d\n\n",
            n_all, length(done_ids), nrow(todo)))

# ---------- Agregacja roczna (compute) + zapis polaczony ----------
agg_compute <- function(pub_all) {
  pub_all$punktowana <- as.integer(pub_all$punkty > 0)
  a <- aggregate(cbind(n_publikacji = 1L, n_punktowane = punktowana, suma_pkt = punkty) ~
                   profil + author_id + rok, data = pub_all, FUN = sum)
  cap <- aggregate(capped ~ author_id, data = pub_all, FUN = function(x) any(x))
  a <- merge(a, cap, by = "author_id", all.x = TRUE)
  a[, c("profil", "author_id", "rok", "n_publikacji", "n_punktowane", "suma_pkt", "capped")]
}
save_combined <- function(rows, path) {
  newagg <- if (length(rows)) agg_compute(do.call(rbind, rows)) else NULL
  out <- rbind(prev_agg, newagg)
  out <- out[order(out$profil, out$rok), ]
  write.csv(out, path, row.names = FALSE, fileEncoding = "UTF-8")
  out
}

# ---------- Fetch z retry (rosnacy budzet przy pustym renderze) ----------
fetch_with_retry <- function(id) {
  for (t in seq_len(MAX_TRIES)) {
    html <- fetch_dom(id, budget = VT_BUDGET + (t - 1L) * 12000L)
    if (!is.na(html) && (count_rowentry(html) > 0 || header0_are_years(html))) {
      return(list(html = html, tries = t))
    }
    if (t < MAX_TRIES) Sys.sleep(2)
  }
  list(html = if (exists("html")) html else NA_character_, tries = MAX_TRIES)
}

# ---------- Petla po profilach ----------
all_rows <- list()
puste <- character(0)
for (i in seq_len(nrow(todo))) {
  id   <- todo$author_id[i]
  prof <- todo$profil[i]
  cat(sprintf("[%d/%d] %s\n", i, nrow(todo), prof))

  res  <- fetch_with_retry(id)
  html <- res$html

  if (is.na(html) || (count_rowentry(html) == 0 && !header0_are_years(html))) {
    cat(sprintf("  [PUSTE] brak publikacji / render po %d probach - pomijam\n", res$tries))
    writeLines(if (is.na(html)) "" else html,
               file.path(DEBUG_DIR, paste0("pub_", id, ".html")), useBytes = TRUE)
    puste <- c(puste, id)
    Sys.sleep(DELAY_SEC)
    next
  }

  pubs   <- parse_publikacje(html, id)
  n_row  <- count_rowentry(html)
  capped <- n_row >= PS
  cat(sprintf("  rowEntry: %d | sparsowane: %d | lata %s-%s | proby:%d%s\n",
              n_row, nrow(pubs),
              ifelse(nrow(pubs) > 0, min(pubs$rok), "NA"),
              ifelse(nrow(pubs) > 0, max(pubs$rok), "NA"), res$tries,
              ifelse(capped, "  [!] UCIETE (>=200)", "")))

  pubs$profil <- prof
  pubs$capped <- capped
  all_rows[[length(all_rows) + 1]] <- pubs

  if (i %% SAVE_EVERY == 0 || i == nrow(todo)) {
    save_combined(all_rows, OUT_CSV)
    cat(sprintf("  [AUTOSAVE] %d/%d -> %s\n", i, nrow(todo), OUT_CSV))
  }
  Sys.sleep(DELAY_SEC)
}

# zapisz liste pustych (do pominiecia przy kolejnym wznowieniu)
if (length(puste)) {
  old <- if (file.exists(PUSTE_TXT)) readLines(PUSTE_TXT, warn = FALSE) else character(0)
  writeLines(unique(c(old, puste)), PUSTE_TXT)
}

agg <- save_combined(all_rows, OUT_CSV)
cat(sprintf("\nZapisano: %s (%d wierszy profil-rok, %d profili)\n",
            OUT_CSV, nrow(agg), length(unique(agg$author_id))))

# ---------- Raport walidacyjny (tylko profile z tego przebiegu) ----------
if (length(all_rows) == 0) {
  cat("\nBrak nowych profili w tym przebiegu.\n")
  quit(save = "no")
}
pub_all <- do.call(rbind, all_rows)
val <- aggregate(cbind(pkt_parsed = punkty, n = 1L) ~ author_id, data = pub_all, FUN = sum)
capf <- aggregate(capped ~ author_id, data = pub_all, FUN = function(x) any(x))
val <- merge(val, capf, by = "author_id")
val <- merge(val, wpt[, c("author_id", "profil", "sum_MEiN")], by = "author_id")
val$diff <- val$pkt_parsed - val$sum_MEiN

n_capped  <- sum(val$capped)
ok        <- val[!val$capped & !is.na(val$sum_MEiN), ]
n_zgodne  <- sum(abs(ok$diff) < 1e-6)
n_rozbiez <- nrow(ok) - n_zgodne

cat("\n=== PODSUMOWANIE PRZEBIEGU ===\n")
cat(sprintf("Profili przetworzonych: %d\n", length(unique(val$author_id))))
cat(sprintf("Ucietych (>=200 pozycji, dane niepelne dla najstarszych lat): %d\n", n_capped))
cat(sprintf("Walidacja (nie-uciete): Sigma_pkt == sum_MEiN: %d zgodnych / %d rozbieznych\n",
            n_zgodne, n_rozbiez))
if (n_capped > 0) {
  cat("\nProfile UCIETE (do ewentualnego doratowania Selenium):\n")
  cc <- val[val$capped, c("profil", "n", "pkt_parsed", "sum_MEiN")]
  print(cc[order(-cc$n), ], row.names = FALSE)
}
if (n_rozbiez > 0) {
  cat("\n[UWAGA] Rozbieznosci punktow (nie-uciete) - mozliwe zle renderowanie:\n")
  rr <- ok[abs(ok$diff) >= 1e-6, c("profil", "pkt_parsed", "sum_MEiN", "diff")]
  print(rr[order(-abs(rr$diff)), ], row.names = FALSE)
}
