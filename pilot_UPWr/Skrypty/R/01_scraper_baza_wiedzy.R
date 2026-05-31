# ============================================================
# Baza Wiedzy (UPWR / SGGW) – FULL (Selenium + klik-next) + PARSOWANIE HTML (rvest)
# - ETAP 1: zbiera author_id z przefiltrowanych wyników (klik-next + stop gdy brak postępu)
# - ETAP 2: pobiera profil i metryki z HTML po etykietach (dt/dd lub tekst węzłów)
# - Debug: gdy nic nie złapie, zapisuje HTML do OUT_DIR/debug_html/
# ============================================================

# Ustawienie Uczelni z ktorej bedą zbierane dane
Sys.setenv(UNI = "UPWR")
#Sys.setenv(UNI = "SGGW")

pkgs <- c("RSelenium", "stringr", "openxlsx", "rvest", "xml2")
to_install <- pkgs[!sapply(pkgs, requireNamespace, quietly = TRUE)]
if (length(to_install) > 0) install.packages(to_install)

library(RSelenium)
library(stringr)
library(openxlsx)
library(rvest)
library(xml2)

# ---------- Ustawienia ----------
CH_HOST <- "127.0.0.1"
CH_PORT <- 9515L
CH_PATH <- "/wd/hub"

UNI <- toupper(Sys.getenv("UNI", unset = "UPWR"))
if (!(UNI %in% c("UPWR", "SGGW"))) stop("Obsługiwane wartości UNI: UPWR, SGGW")

UNIVERSITY_CONFIG <- list(
  UPWR = list(
    code = "upwr",
    name = "UPWR",
    results_url = "https://bazawiedzy.upwr.edu.pl/search/author?ps=20&t=simple&showRel=false&lang=pl&qp=authorprofile_keywords%253D%2526academicDegree%253Aterm%253D%2526member%253Aactivitytype%253D%2526team%253Aactivitytype%253D%2526otheractivity%253Aactivitytype%253D%2526pracownik_all%253Dtrue%2526specialization%253Aterm%253D%2526activityDiscipline%253Aterm%253D&cid=544&p=wgq&pn=1",
    author_link_css = "a[href*='/info/author/']",
    author_id_regex = "/info/author/([^?/#]+)",
    profile_url = function(author_id) sprintf("https://bazawiedzy.upwr.edu.pl/info/author/%s?lang=pl&r=publication&tab=main", author_id)
  ),
  SGGW = list(
    code = "sggw",
    name = "SGGW",
    # W razie potrzeby podmień przez env RESULTS_URL:
    # Sys.setenv(RESULTS_URL = "https://.../search/author?...")
    results_url = "https://bazawiedzy.sggw.edu.pl/search/author",
    author_link_css = "a[href*='/info/author/']",
    author_id_regex = "/info/author/([^?/#]+)",
    profile_url = function(author_id) sprintf("https://bazawiedzy.sggw.edu.pl/info/author/%s?lang=pl&r=publication&tab=main", author_id)
  )
)
CFG <- UNIVERSITY_CONFIG[[UNI]]
URL_RESULTS <- Sys.getenv("RESULTS_URL", unset = CFG$results_url)

OUT_DIR <- file.path("output_bibliometria")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
DEBUG_DIR <- file.path(OUT_DIR, "debug_html")
dir.create(DEBUG_DIR, recursive = TRUE, showWarnings = FALSE)

timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
OUT_XLSX <- file.path(OUT_DIR, paste0(CFG$code, "_profiles_metrics_HTML_", timestamp, ".xlsx"))
OUT_CSV  <- file.path(OUT_DIR, paste0(CFG$code, "_profiles_metrics_HTML_", timestamp, ".csv"))

WAIT_RESULTS <- 2
WAIT_PROFILE <- 6
MAX_NEXT_CLICKS <- 300
AUTOSAVE_EVERY <- 10

# ---------- Helpery ----------
to_num_pl <- function(x) {
  if (is.na(x) || !nzchar(x)) return(NA_real_)
  x <- gsub("\u00a0", " ", x, fixed = TRUE)  # NBSP
  as.numeric(gsub(",", ".", x))
}

extract_author_id <- function(url) {
  m <- str_match(url, CFG$author_id_regex)
  if (is.na(m[1,2])) NA_character_ else m[1,2]
}

profile_url <- function(author_id) {
  CFG$profile_url(author_id)
}

# --- wyniki: author_id ---
get_author_ids_from_results <- function(remDr) {
  links <- remDr$findElements("css selector", CFG$author_link_css)
  if (length(links) == 0) return(character())
  hrefs <- unlist(lapply(links, function(a) a$getElementAttribute("href")), use.names = FALSE)
  ids <- vapply(hrefs, extract_author_id, character(1))
  unique(ids[!is.na(ids) & nzchar(ids)])
}

# --- klik next ---
click_next <- function(remDr) {
  css_try <- c(
    "a[rel='next']",
    "a[aria-label*='Nast']",
    "a[title*='Nast']",
    "li.next a",
    ".pagination li.next a"
  )
  for (css in css_try) {
    els <- try(remDr$findElements("css selector", css), silent = TRUE)
    if (!inherits(els, "try-error") && length(els) > 0) {
      ok <- try(els[[1]]$clickElement(), silent = TRUE)
      if (!inherits(ok, "try-error")) return(TRUE)
    }
  }
  xpath_try <- c(
    "//a[contains(@aria-label,'Nast')]",
    "//a[contains(@title,'Nast')]",
    "//a[@rel='next']",
    "//li[contains(@class,'next')]/a"
  )
  for (xp in xpath_try) {
    els <- try(remDr$findElements("xpath", xp), silent = TRUE)
    if (!inherits(els, "try-error") && length(els) > 0) {
      ok <- try(els[[1]]$clickElement(), silent = TRUE)
      if (!inherits(ok, "try-error")) return(TRUE)
    }
  }
  FALSE
}

# --- pobierz HTML ---
get_page_html <- function(remDr) {
  remDr$getPageSource()[[1]]
}

# --- ekstrakcja wartości "po etykiecie" z HTML (bardzo odporne) ---
# Działa dla układów typu <dt>Etykieta</dt><dd>Wartość</dd> oraz gdy etykieta jest w dowolnym węźle obok wartości.
get_value_by_label <- function(doc, label_regex) {
  # XPath 1.0 (libxml2) nie wspiera matches(), więc filtrujemy regex w R.
  nodes <- html_elements(doc, xpath = "//*[self::dt or self::th or self::div or self::span]")
  if (length(nodes) == 0) return(NA_character_)

  node_txt <- str_squish(html_text2(nodes))
  idx <- which(grepl(label_regex, node_txt, ignore.case = TRUE, perl = TRUE))[1]
  if (!is.na(idx)) {
    dt <- nodes[[idx]]
    # spróbuj sibling dd/td/div/span jako wartość
    sib <- html_element(dt, xpath = "following-sibling::*[1]")
    if (!is.na(sib)) {
      val <- html_text2(sib)
      val <- str_squish(val)
      if (nzchar(val)) return(val)
    }
    # fallback: następny element w DOM
    nxt <- html_element(dt, xpath = "following::*[1]")
    if (!is.na(nxt)) {
      val <- html_text2(nxt)
      val <- str_squish(val)
      if (nzchar(val)) return(val)
    }
  }
  NA_character_
}

# --- nazwa profilu: h1 lub title ---
get_profile_name <- function(doc) {
  h1 <- html_element(doc, "h1")
  if (!is.na(h1)) {
    t <- str_squish(html_text2(h1))
    if (nzchar(t)) return(t)
  }
  ttl <- html_element(doc, "title")
  if (!is.na(ttl)) {
    t <- str_squish(html_text2(ttl))
    # często w title jest "Profil osoby – X – Uniwersytet..."
    t2 <- str_match(t, "Profil osoby\\s*[–—-]\\s*(.+?)\\s*[–—-]\\s*Uniwersytet")[,2]
    if (!is.na(t2) && nzchar(t2)) return(str_squish(t2))
    if (nzchar(t)) return(t)
  }
  NA_character_
}

clean_profile_name <- function(x) {
  if (is.na(x)) return(NA_character_)
  x <- str_squish(x)
  x <- str_replace(x, "^Profil osoby\\s*[–—-]\\s*", "")
  x <- str_replace(x, "\\s*[–—-]\\s*Uniwersytet.*$", "")
  x <- str_squish(x)
  if (!nzchar(x)) NA_character_ else x
}

clean_org_fragment <- function(x) {
  if (is.na(x)) return(NA_character_)
  x <- str_squish(x)
  x <- str_replace(
    x,
    "\\s*(Wydział\\b|Strona\\s+domowa:|Email\\b|Profil\\b|Publikacje\\b|ORCID\\b|Google\\s+Scholar\\b).*",
    ""
  )
  x <- str_squish(x)
  if (!nzchar(x)) NA_character_ else x
}

clean_position <- function(x) {
  if (is.na(x)) return(NA_character_)
  x <- str_squish(x)
  x <- str_replace(
    x,
    "\\s*(Jednostka\\b|Wydział\\b|Strona\\s+domowa:|Email\\b|Profil\\b|Publikacje\\b|ORCID\\b|Google\\s+Scholar\\b).*",
    ""
  )
  x <- str_squish(x)
  if (!nzchar(x)) NA_character_ else x
}

# --- jednostka / wydział: próbuj po etykietach, a jeśli nie ma, to z tekstu strony ---
get_unit_faculty <- function(doc) {
  page_txt <- str_squish(html_text2(doc))

  # jednostka – często występuje jako "Instytut ..." bez etykiety
  unit <- get_value_by_label(doc, "Instytut|Katedra|Zakład|Centrum")
  if (is.na(unit)) {
    unit <- str_match(page_txt, "((?:Instytut|Katedra|Zakład|Centrum)[^\\n]{0,160})")[,2]
  }
  unit <- clean_org_fragment(unit)

  faculty <- get_value_by_label(doc, "Wydział")
  if (is.na(faculty)) {
    faculty <- str_match(page_txt, "(Wydział[^\\n]{0,140})")[,2]
  }

  # Odetnij typowe "doklejki" z menu/karty kontaktowej.
  if (!is.na(faculty)) {
    faculty <- str_replace(
      faculty,
      "\\s*(Strona\\s+domowa:|Email\\b|Profil\\b|Publikacje\\b|ORCID\\b|Google\\s+Scholar\\b).*",
      ""
    )
  }

  list(
    jednostka = ifelse(is.na(unit), NA_character_, str_squish(unit)),
    wydzial   = ifelse(is.na(faculty), NA_character_, str_squish(faculty))
  )
}

get_position <- function(doc) {
  page_txt <- str_squish(html_text2(doc))

  pos <- get_value_by_label(doc, "Stanowisko")
  if (is.na(pos)) {
    pos <- str_match(
      page_txt,
      "(?i)(?:Stanowisko\\s*[:\\-]?\\s*)(Profesor(?:\\s+uczelni)?|Profesor\\s+nadzwyczajny|Profesor\\s+zwyczajny|Adiunkt(?:\\s+badawczo-dydaktyczny)?|Asystent|Wykładowca|Starszy\\s+wykładowca|Kierownik\\s+katedry|Doktorant)"
    )[,2]
  }
  if (is.na(pos)) {
    pos <- str_match(
      page_txt,
      "(?i)\\b(Profesor(?:\\s+uczelni)?|Profesor\\s+nadzwyczajny|Profesor\\s+zwyczajny|Adiunkt(?:\\s+badawczo-dydaktyczny)?|Asystent|Wykładowca|Starszy\\s+wykładowca|Kierownik\\s+katedry|Doktorant)\\b"
    )[,2]
  }

  clean_position(pos)
}

extract_metric_value <- function(page_txt, label_regex, num_regex = "[0-9]+(?:[\\.,][0-9]+)?", max_gap = 120) {
  patterns <- c(
    sprintf("(?is)(?:%s)\\s*[:=]?\\s*(%s)", label_regex, num_regex),
    sprintf("(?is)(?:%s).{0,%d}?(%s)", label_regex, max_gap, num_regex),
    sprintf("(?is)(%s)\\s*[:=]?\\s*(?:%s)", num_regex, label_regex),
    sprintf("(?is)(%s).{0,%d}?(?:%s)", num_regex, max_gap, label_regex)
  )
  for (p in patterns) {
    m <- str_match(page_txt, p)
    if (!is.na(m[1,2]) && nzchar(m[1,2])) return(m[1,2])
  }
  NA_character_
}

# --- bibliometria: po etykietach ---
parse_profile_html <- function(html) {
  doc <- read_html(html)
  page_txt <- str_squish(html_text2(doc))

  profil <- clean_profile_name(get_profile_name(doc))
  stanowisko <- get_position(doc)
  uf <- get_unit_faculty(doc)

  h_scopus <- get_value_by_label(doc, "h-?index\\s*\\(\\s*Cytowania\\s*Scopus\\s*\\)")
  h_wos    <- get_value_by_label(doc, "h-?index\\s*\\(\\s*Cytowania\\s*WoS\\s*\\)")
  sum_if   <- get_value_by_label(doc, "Sumaryczny\\s*IF")
  sum_snip <- get_value_by_label(doc, "Sumaryczny\\s*SNIP")
  sum_mein <- get_value_by_label(doc, "Sumaryczna\\s*punktacja\\s*MEiN")

  # Fallback: gdy etykieta i wartość są w jednej linii/bloku HTML.
  if (is.na(h_scopus)) {
    h_scopus <- extract_metric_value(
      page_txt,
      "(?:h-?index[^a-zA-Z0-9]{0,25}(?:scopus|cytowania\\s*scopus)|(?:scopus|cytowania\\s*scopus)[^a-zA-Z0-9]{0,25}h-?index)",
      "[0-9]+",
      80
    )
  }
  if (is.na(h_wos)) {
    h_wos <- extract_metric_value(
      page_txt,
      "(?:h-?index[^a-zA-Z0-9]{0,25}(?:wos|web\\s*of\\s*science|cytowania\\s*wos)|(?:wos|web\\s*of\\s*science|cytowania\\s*wos)[^a-zA-Z0-9]{0,25}h-?index)",
      "[0-9]+",
      80
    )
  }
  if (is.na(sum_if)) {
    sum_if <- extract_metric_value(
      page_txt,
      "(?:sumaryczny\\s*if|if\\s*sumaryczny)",
      "[0-9]+(?:[\\.,][0-9]+)?",
      80
    )
  }
  if (is.na(sum_snip)) {
    sum_snip <- extract_metric_value(
      page_txt,
      "(?:sumaryczny\\s*snip|snip\\s*sumaryczny)",
      "[0-9]+(?:[\\.,][0-9]+)?",
      80
    )
  }
  if (is.na(sum_mein)) {
    sum_mein <- extract_metric_value(
      page_txt,
      "(?:sumaryczna\\s*punktacja\\s*(?:mein|mnisw)|punktacja\\s*(?:mein|mnisw))",
      "[0-9][0-9 ]*",
      120
    )
  }

  data.frame(
    profil = profil,
    stanowisko = stanowisko,
    jednostka = uf$jednostka,
    wydzial = uf$wydzial,
    h_index_scopus = suppressWarnings(as.numeric(gsub("\\D", "", h_scopus))),
    h_index_wos    = suppressWarnings(as.numeric(gsub("\\D", "", h_wos))),
    sum_IF = suppressWarnings(to_num_pl(str_match(sum_if, "([0-9]+(?:[\\.,][0-9]+)?)")[,2])),
    sum_SNIP = suppressWarnings(to_num_pl(str_match(sum_snip, "([0-9]+(?:[\\.,][0-9]+)?)")[,2])),
    sum_MEiN = suppressWarnings(as.numeric(gsub(" ", "", str_match(sum_mein, "([0-9 ]+)")[,2]))),
    stringsAsFactors = FALSE
  )
}

has_any_data <- function(rec) {
  any(!is.na(rec$profil),
      !is.na(rec$jednostka),
      !is.na(rec$wydzial),
      !is.na(rec$h_index_scopus),
      !is.na(rec$h_index_wos),
      !is.na(rec$sum_IF),
      !is.na(rec$sum_MEiN))
}

# --- szybka detekcja stron nienależących do profilu (logowanie / blokada) ---
looks_like_block_page <- function(html) {
  doc <- read_html(html)
  ttl_node <- html_element(doc, "title")
  ttl <- if (is.na(ttl_node)) "" else tolower(str_squish(html_text2(ttl_node)))
  txt <- tolower(str_squish(html_text2(doc)))
  has_password_input <- grepl("type\\s*=\\s*['\"]password['\"]", tolower(html), perl = TRUE)

  title_block <- grepl("logowanie|zaloguj|login|sign in|captcha|cloudflare|access denied|forbidden", ttl, perl = TRUE)
  text_block <- grepl("captcha|cloudflare|access denied|forbidden|too many requests|403|401", txt, perl = TRUE)

  isTRUE(title_block || text_block || has_password_input)
}

# --- pobierz rekord profilu (z retry i debug dump) ---
get_profile_record <- function(remDr, author_id, wait_sec = WAIT_PROFILE) {
  url <- profile_url(author_id)
  remDr$navigate(url)
  Sys.sleep(wait_sec)

  html <- get_page_html(remDr)
  rec <- parse_profile_html(html)

  # retry jeśli kompletnie pusto
  if (!has_any_data(rec)) {
    Sys.sleep(3)
    html <- get_page_html(remDr)
    rec <- parse_profile_html(html)
  }

  if (looks_like_block_page(html) && !has_any_data(rec)) {
    warning(sprintf("Podejrzenie strony logowania/blokady dla %s", author_id), call. = FALSE)
  }

  # jeśli nadal pusto, zapisz debug HTML
  if (!has_any_data(rec)) {
    dbg_file <- file.path(DEBUG_DIR, paste0(author_id, ".html"))
    writeLines(html, dbg_file, useBytes = TRUE)
  }

  rec$author_id <- author_id
  rec$url <- url
  rec
}

save_outputs <- function(df, out_csv, out_xlsx) {
  write.csv(df, out_csv, row.names = FALSE, fileEncoding = "UTF-8")

  wb <- createWorkbook()
  addWorksheet(wb, "profiles_metrics")
  writeData(wb, "profiles_metrics", df)
  setColWidths(wb, "profiles_metrics", cols = 1:ncol(df), widths = "auto")
  saveWorkbook(wb, out_xlsx, overwrite = TRUE)
}

# ============================================================
# START
# ============================================================
cat(sprintf("\n[CONFIG] UNI=%s | URL_RESULTS=%s\n", CFG$name, URL_RESULTS))

remDr <- remoteDriver(CH_HOST, port = CH_PORT, browserName = "chrome", path = CH_PATH)
remDr$open()
remDr$navigate(URL_RESULTS)
Sys.sleep(WAIT_RESULTS)

cat("\n--- OKNO CHROME OTWARTE ---\n")
cat("Ustaw filtry w panelu po lewej i kliknij 'Filtruj' (np. Liczba pozycji: 148).\n\n")
invisible(readline(prompt = "Gdy filtry są ustawione i zastosowane, wciśnij ENTER w konsoli R... "))

# ---------- ETAP 1: author_id ----------
cat("\n[ETAP 1] Zbieram author_id...\n")
all_ids <- character()
prev_ids_on_page <- character()
no_growth <- 0

for (k in 1:MAX_NEXT_CLICKS) {
  Sys.sleep(WAIT_RESULTS)
  ids <- get_author_ids_from_results(remDr)
  if (length(ids) == 0) break

  before <- length(all_ids)
  all_ids <- unique(c(all_ids, ids))
  added <- length(all_ids) - before

  cat(sprintf("strona=%d | ids_na_stronie=%d | unikalne=%d | +%d\n",
              k, length(ids), length(all_ids), added))

  same_page <- length(prev_ids_on_page) > 0 && identical(ids, prev_ids_on_page)
  prev_ids_on_page <- ids

  if (added == 0 || same_page) no_growth <- no_growth + 1 else no_growth <- 0
  if (no_growth >= 2) break

  if (!click_next(remDr)) break
}

cat("\nZebrano profili: ", length(all_ids), "\n", sep = "")
if (length(all_ids) == 0) {
  remDr$close()
  stop("Nie zebrano żadnych profili – sprawdź filtry i listę wyników.")
}

# ---------- ETAP 2: profile ----------
cat("\n[ETAP 2] Pobieram dane z profili (HTML)...\n")
records <- vector("list", length(all_ids))

for (i in seq_along(all_ids)) {
  id <- all_ids[i]
  cat(sprintf("[%d/%d] %s\n", i, length(all_ids), id))

  records[[i]] <- tryCatch(
    get_profile_record(remDr, id),
    error = function(e) {
      data.frame(
        profil = NA_character_, stanowisko = NA_character_,
        jednostka = NA_character_, wydzial = NA_character_,
        h_index_scopus = NA_real_, h_index_wos = NA_real_,
        sum_IF = NA_real_, sum_SNIP = NA_real_, sum_MEiN = NA_real_,
        author_id = id, url = profile_url(id),
        error = conditionMessage(e),
        stringsAsFactors = FALSE
      )
    }
  )

  if ("error" %in% names(records[[i]]) && !is.na(records[[i]]$error[1])) {
    cat(sprintf("  [ERROR] %s\n", records[[i]]$error[1]))
  }

  # szybka kontrola pierwszych 5
  if (i <= 5) {
    print(records[[i]][, c("profil","jednostka","wydzial","h_index_scopus","sum_IF","sum_MEiN")])
  }

  if (i %% AUTOSAVE_EVERY == 0 || i == length(all_ids)) {
    df_partial <- do.call(rbind, records[seq_len(i)])
    if (!("error" %in% names(df_partial))) df_partial$error <- NA_character_
    df_partial <- df_partial[, c("profil","stanowisko","jednostka","wydzial",
                                 "h_index_scopus","h_index_wos","sum_IF","sum_SNIP","sum_MEiN",
                                 "author_id","url","error")]
    save_outputs(df_partial, OUT_CSV, OUT_XLSX)
    cat(sprintf("  [AUTOSAVE] zapisano %d/%d do: %s i %s\n", i, length(all_ids), OUT_CSV, OUT_XLSX))
  }
}

df <- do.call(rbind, records)
if (!("error" %in% names(df))) df$error <- NA_character_

df <- df[, c("profil","stanowisko","jednostka","wydzial",
             "h_index_scopus","h_index_wos","sum_IF","sum_SNIP","sum_MEiN",
             "author_id","url","error")]

# ---------- zapis ----------
save_outputs(df, OUT_CSV, OUT_XLSX)

  cat("\nZapisano:\nCSV : ", OUT_CSV, "\nXLSX: ", OUT_XLSX, "\n", sep = "")
  cat("Debug HTML (dla profili bez danych): ", normalizePath(DEBUG_DIR), "\n", sep = "")

remDr$close()

df
