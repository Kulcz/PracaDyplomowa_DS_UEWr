# LTeX: enabled=false
# ============================================================
# 06 - Doratowanie profili UCIETYCH (>200 publikacji) przez Selenium
# ============================================================
# Profile z >200 pozycjami nie miesci1y sie na jednej stronie (limit portalu
# ps<=200, paginacja stanowa JSF). Tu uzywamy RSelenium + chromedriver:
# klikamy ".ui-paginator-next" i zbieramy WSZYSTKIE strony, parsujac kazda.
# Strony sa rozlaczne (paginacja po pozycjach) -> konkatenacja bez dublowania.
# Wynik scalany do WPT_publikacje_rocznie.csv (capped -> FALSE, dane pelne).
#
# WYMAGA: dzialajacego chromedriver na 127.0.0.1:9515 (uruchom przed skryptem).
# ============================================================

suppressMessages(library(RSelenium))

OUT_CSV  <- "output_bibliometria/WPT_publikacje_rocznie.csv"
PS         <- 200
YEAR_MIN   <- 1990L
YEAR_MAX   <- as.integer(format(Sys.Date(), "%Y"))
WAIT_NAV   <- 6      # s po navigate
WAIT_CLICK <- 5      # s po kliknieciu next
MAX_PAGES  <- 40     # bezpiecznik

pub_url <- function(author_id) {
  sprintf("https://bazawiedzy.upwr.edu.pl/info/author/%s?r=publication&ps=%d&tab=publications&lang=pl",
          author_id, PS)
}

count_rowentry <- function(src) {
  g <- gregexpr('<div class="rowEntry">', src, fixed = TRUE)[[1]]
  if (g[1] == -1L) 0L else length(g)
}

# Parser jak w 04: rok (header0) + punkty (header1) per rowEntry
parse_page <- function(src) {
  pat <- paste0('resultListHeader0">\\s*\\d{4}',
                '|resultListHeader1">\\s*\\d+\\s*<',
                '|<div class="rowEntry">')
  toks <- regmatches(src, gregexpr(pat, src, perl = TRUE))[[1]]
  if (length(toks) == 0) return(data.frame(rok = integer(), punkty = integer()))
  cy <- NA_integer_; cp <- NA_integer_; yr <- integer(0); pt <- integer(0)
  for (tok in toks) {
    if (grepl("resultListHeader0", tok, fixed = TRUE)) {
      cy <- as.integer(sub('.*">\\s*(\\d{4}).*', "\\1", tok))
    } else if (grepl("resultListHeader1", tok, fixed = TRUE)) {
      cp <- as.integer(sub('.*">\\s*(\\d+).*', "\\1", tok))
    } else { yr <- c(yr, cy); pt <- c(pt, cp) }
  }
  df <- data.frame(rok = yr, punkty = pt)
  df <- df[!is.na(df$rok) & df$rok >= YEAR_MIN & df$rok <= YEAR_MAX, , drop = FALSE]
  df$punkty[is.na(df$punkty)] <- 0L
  df
}

# sygnatura strony (do wykrycia braku postepu)
page_sig <- function(src) {
  doi <- regmatches(src, gregexpr("DOI:[^ <\"]+", src))[[1]]
  paste0(count_rowentry(src), "|", paste(head(doi, 3), collapse = ","))
}

# czekaj az lista (rowEntry) i paginator sie wyrenderuja
wait_initial <- function(remDr, timeout = 20) {
  src <- remDr$getPageSource()[[1]]
  for (k in seq_len(timeout)) {
    if (count_rowentry(src) > 0 &&
        length(remDr$findElements("css selector", ".ui-paginator-next")) > 0) break
    Sys.sleep(1); src <- remDr$getPageSource()[[1]]
  }
  src
}

# Zbierz wszystkie strony dla jednego autora.
# complete = TRUE tylko gdy dotarlismy do wylaczonego NEXT (ostatnia strona).
scrape_all_pages <- function(remDr, author_id) {
  remDr$navigate(pub_url(author_id)); Sys.sleep(WAIT_NAV)
  src <- wait_initial(remDr)
  rows <- list(); n_pages <- 0L; complete <- FALSE
  repeat {
    prev_sig <- page_sig(src)
    rows[[length(rows) + 1]] <- parse_page(src)
    n_pages <- n_pages + 1L

    nxt <- remDr$findElements("css selector", ".ui-paginator-next:not(.ui-state-disabled)")
    if (length(nxt) == 0) { complete <- TRUE; break }   # NEXT wylaczony = ostatnia strona
    if (n_pages >= MAX_PAGES) break                     # bezpiecznik (complete=FALSE)

    nxt[[1]]$clickElement()
    # czekaj az tresc sie zmieni (AJAX zaladuje kolejna strone)
    changed <- FALSE
    for (k in seq_len(20)) {
      Sys.sleep(1); s2 <- remDr$getPageSource()[[1]]
      if (count_rowentry(s2) > 0 && page_sig(s2) != prev_sig) { src <- s2; changed <- TRUE; break }
    }
    if (!changed) break                                 # nie udalo sie przejsc (complete=FALSE)
  }
  list(df = do.call(rbind, rows), pages = n_pages, complete = complete)
}

# ---------- Wczytanie listy capped ----------
agg_old <- read.csv(OUT_CSV, stringsAsFactors = FALSE)
capped_ids <- unique(agg_old$author_id[agg_old$capped %in% c(TRUE, "TRUE")])
profil_map <- agg_old[!duplicated(agg_old$author_id),
                      c("author_id", "profil")]
cat(sprintf("Profili UCIETYCH do doratowania: %d\n\n", length(capped_ids)))
if (length(capped_ids) == 0) { cat("Brak profili capped.\n"); quit(save = "no") }

# ---------- Selenium ----------
eCaps <- list(chromeOptions = list(args = c(
  "--headless=new", "--disable-gpu", "--no-sandbox", "--window-size=1920,1080")))
remDr <- remoteDriver(remoteServerAddr = "127.0.0.1", port = 9515L,
                      browserName = "chrome", path = "", extraCapabilities = eCaps)
remDr$open(silent = TRUE)

new_list <- list()
for (i in seq_along(capped_ids)) {
  id   <- capped_ids[i]
  prof <- profil_map$profil[profil_map$author_id == id][1]
  cat(sprintf("[%d/%d] %s\n", i, length(capped_ids), prof))

  res <- tryCatch(scrape_all_pages(remDr, id),
                  error = function(e) { cat("  [ERROR]", conditionMessage(e), "\n"); NULL })
  if (is.null(res) || is.null(res$df) || nrow(res$df) == 0) { cat("  [PUSTE]\n"); next }

  df <- res$df
  df$punktowana <- as.integer(df$punkty > 0)
  a <- aggregate(cbind(n_publikacji = 1L, n_punktowane = punktowana, suma_pkt = punkty) ~ rok,
                 data = df, FUN = sum)
  a$profil <- prof; a$author_id <- id; a$capped <- !res$complete
  new_list[[length(new_list) + 1]] <- a[, c("profil","author_id","rok","n_publikacji","n_punktowane","suma_pkt","capped")]
  cat(sprintf("  strony=%d | publikacje=%d | lata %d-%d | suma_pkt=%d | kompletne=%s\n",
              res$pages, nrow(df), min(df$rok), max(df$rok), sum(df$punkty),
              ifelse(res$complete, "TAK", "NIE [!]")))
}
remDr$close()

# ---------- Scalenie do CSV ----------
new_agg <- do.call(rbind, new_list)
if (is.null(new_agg) || nrow(new_agg) == 0) stop("Nie doratowano zadnego profilu.")

done_ids <- unique(new_agg$author_id)
agg_keep <- agg_old[!(agg_old$author_id %in% done_ids), ]
agg_final <- rbind(agg_keep, new_agg)
agg_final <- agg_final[order(agg_final$profil, agg_final$rok), ]
write.csv(agg_final, OUT_CSV, row.names = FALSE, fileEncoding = "UTF-8")

cat(sprintf("\nScalono: %s\n", OUT_CSV))
cat(sprintf("Doratowano profili: %d | pozostalo capped: %d\n",
            length(done_ids), sum(agg_final$capped %in% c(TRUE, "TRUE"))))

# ---------- Walidacja: Sigma_pkt vs sum_MEiN ----------
raw <- read.csv("output_bibliometria/upwr_profiles_metrics_HTML_20260306_075402.csv",
                stringsAsFactors = FALSE)
val <- aggregate(suma_pkt ~ author_id + profil, data = new_agg, FUN = sum)
val <- merge(val, raw[, c("author_id", "sum_MEiN")], by = "author_id")
val$diff <- val$suma_pkt - val$sum_MEiN
cat("\n=== WALIDACJA doratowanych (Sigma_pkt vs sum_MEiN) ===\n")
print(val[order(-abs(val$diff)), c("profil","suma_pkt","sum_MEiN","diff")], row.names = FALSE)
