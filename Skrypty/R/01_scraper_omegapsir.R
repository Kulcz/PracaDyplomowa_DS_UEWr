# ============================================================
# Baza Wiedzy Omega-PSIR (UPWR / SGGW / URK / UWM) – FULL
# Selenium + klik-next + PARSOWANIE HTML (rvest)
# - ETAP 1: zbiera author_id z przefiltrowanych wyników (klik-next + stop gdy brak postępu)
# - ETAP 2: pobiera profil i metryki z HTML po etykietach (dt/dd lub tekst węzłów)
# - Debug: gdy nic nie złapie, zapisuje HTML do OUT_DIR/debug_html/
#

# UŻYCIE:
# Sys.setenv(UNI = "URK") 
# Sys.setenv(DYSCYPLINA = "rolnictwo_i_ogrodnictwo")
# source("Skrypty/R/01_scraper_omegapsir.R")
# ============================================================

# Uczelnia: ustaw przed source() — Sys.setenv(UNI = "UPWR" | "SGGW" | "URK" | "UWM")
# Default (gdy nie ustawiono): UPWR
if (!nzchar(Sys.getenv("UNI"))) Sys.setenv(UNI = "UPWR")

pkgs <- c("httr2", "jsonlite", "stringr", "openxlsx", "rvest", "xml2", "base64enc")
to_install <- pkgs[!sapply(pkgs, requireNamespace, quietly = TRUE)]
if (length(to_install) > 0) install.packages(to_install)

library(httr2)
library(jsonlite)
library(stringr)
library(openxlsx)
library(rvest)
library(xml2)
library(base64enc)
# RSelenium 1.7.10 ma regresję parsowania W3C WebDriver z Chrome 148+
# (sessionId zwraca NA → operacje na sesji wybuchają). Idziemy bezpośrednio
# do chromedriver przez WebDriver HTTP API.

# ---------- Ustawienia ----------
CH_HOST <- "127.0.0.1"
CH_PORT <- 9515L
WD_BASE <- sprintf("http://%s:%d", CH_HOST, CH_PORT)
ELEMENT_KEY <- "element-6066-11e4-a52e-4f735466cecf"  # W3C identyfikator

# ---------- Mini WebDriver client (httr2) ----------
wd_post <- function(path, body = list()) {
  request(paste0(WD_BASE, path)) |>
    req_method("POST") |>
    req_body_json(body, auto_unbox = TRUE) |>
    req_timeout(30) |>
    req_perform()
}
wd_get <- function(path) {
  request(paste0(WD_BASE, path)) |>
    req_timeout(30) |>
    req_perform()
}
wd_del <- function(path) {
  request(paste0(WD_BASE, path)) |>
    req_method("DELETE") |>
    req_timeout(30) |>
    req_perform()
}
wd_val <- function(resp) {
  fromJSON(resp_body_string(resp), simplifyVector = FALSE)$value
}

wd_new_session <- function() {
  body <- list(capabilities = list(alwaysMatch = list(
    browserName = "chrome",
    `goog:chromeOptions` = list(args = list("--no-sandbox", "--disable-gpu"))
  )))
  v <- wd_val(wd_post("/session", body))
  v$sessionId
}
wd_navigate     <- function(sid, url) wd_post(sprintf("/session/%s/url", sid), list(url = url))
wd_current_url  <- function(sid) wd_val(wd_get(sprintf("/session/%s/url", sid)))
wd_page_source  <- function(sid) wd_val(wd_get(sprintf("/session/%s/source", sid)))
wd_screenshot   <- function(sid, file) {
  b64 <- wd_val(wd_get(sprintf("/session/%s/screenshot", sid)))
  writeBin(base64enc::base64decode(b64), file)
}
wd_find_elements <- function(sid, using, value) {
  els <- wd_val(wd_post(sprintf("/session/%s/elements", sid),
                        list(using = using, value = value)))
  vapply(els, function(e) e[[ELEMENT_KEY]], character(1))
}
wd_click <- function(sid, element_id) {
  wd_post(sprintf("/session/%s/element/%s/click", sid, element_id), list())
}
wd_quit <- function(sid) try(wd_del(sprintf("/session/%s", sid)), silent = TRUE)

# Wykonanie JavaScript w przeglądarce — niezbędne dla PrimeFaces paginatora,
# gdzie zwykły WebDriver click bywa ignorowany przez event delegation.
wd_execute <- function(sid, script, args = list()) {
  resp <- request(sprintf("%s/session/%s/execute/sync", WD_BASE, sid)) |>
    req_method("POST") |>
    req_body_json(list(script = script, args = args), auto_unbox = TRUE) |>
    req_timeout(30) |>
    req_perform()
  fromJSON(resp_body_string(resp), simplifyVector = FALSE)$value
}

UNI <- toupper(Sys.getenv("UNI", unset = "UPWR"))
SUPPORTED_UNI <- c("UPWR", "SGGW", "URK", "UWM")
if (!(UNI %in% SUPPORTED_UNI)) {
  stop(sprintf("Obsługiwane wartości UNI: %s", paste(SUPPORTED_UNI, collapse = ", ")))
}

# Wszystkie 4 uczelnie potwierdzone jako Omega-PSIR (audyt 2026-05-24).
# Struktura URL ujednolicona: <base>/search/author?... + <base>/info/author/<id>
UNIVERSITY_CONFIG <- list(
  UPWR = list(
    code = "upwr",
    name = "UPWR",
    base_url = "https://bazawiedzy.upwr.edu.pl",
    # URL z aktywnym query string z filtrem rolnictwa+ogrodnictwa do podmiany.
    # Default poniżej = generyczny endpoint; w tygodniu 1 zastąpić URL-em po manualnym
    # ustawieniu filtra w przeglądarce + skopiowaniu z paska adresu (DevTools/Network).
    results_url = "https://bazawiedzy.upwr.edu.pl/search/author?ps=20&t=simple&showRel=false&lang=pl&qp=authorprofile_keywords%253D%2526academicDegree%253Aterm%253D%2526member%253Aactivitytype%253D%2526team%253Aactivitytype%253D%2526otheractivity%253Aactivitytype%253D%2526pracownik_all%253Dtrue%2526specialization%253Aterm%253D%2526activityDiscipline%253Aterm%253D&cid=544&p=wgq&pn=1",
    author_link_css = "a[href*='/info/author/']",
    author_id_regex = "/info/author/([^?/#]+)",
    profile_url = function(author_id) sprintf("https://bazawiedzy.upwr.edu.pl/info/author/%s?lang=pl&r=publication&tab=main", author_id)
  ),
  SGGW = list(
    # 2026-05-24: stara domena bazawiedzy.sggw.edu.pl zwraca 404 (redirect na www.sggw.edu.pl/404/),
    # baza została przeniesiona pod bw.sggw.edu.pl (ten sam silnik Omega-PSIR).
    code = "sggw",
    name = "SGGW",
    base_url = "https://bw.sggw.edu.pl",
    results_url = "https://bw.sggw.edu.pl/search/author?ps=20&t=simple&lang=pl",
    author_link_css = "a[href*='/info/author/']",
    author_id_regex = "/info/author/([^?/#]+)",
    profile_url = function(author_id) sprintf("https://bw.sggw.edu.pl/info/author/%s?lang=pl&r=publication&tab=main", author_id)
  ),
  URK = list(
    code = "urk",
    name = "URK",
    base_url = "https://repo.ur.krakow.pl",
    results_url = "https://repo.ur.krakow.pl/search/author?ps=20&t=simple&lang=pl",
    author_link_css = "a[href*='/info/author/']",
    author_id_regex = "/info/author/([^?/#]+)",
    profile_url = function(author_id) sprintf("https://repo.ur.krakow.pl/info/author/%s?lang=pl&r=publication&tab=main", author_id)
  ),
  UWM = list(
    code = "uwm",
    name = "UWM",
    base_url = "https://bazawiedzy.uwm.edu.pl",
    results_url = "https://bazawiedzy.uwm.edu.pl/search/author?ps=20&t=simple&lang=pl",
    author_link_css = "a[href*='/info/author/']",
    author_id_regex = "/info/author/([^?/#]+)",
    profile_url = function(author_id) sprintf("https://bazawiedzy.uwm.edu.pl/info/author/%s?lang=pl&r=publication&tab=main", author_id)
  )
)
CFG <- UNIVERSITY_CONFIG[[UNI]]
URL_RESULTS <- Sys.getenv("RESULTS_URL", unset = CFG$results_url)

DYSCYPLINA <- Sys.getenv("DYSCYPLINA", unset = "all")  # do tagowania plików wyjściowych

OUT_DIR <- file.path("Dane", "raw")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
DEBUG_DIR <- file.path(OUT_DIR, "debug_html", CFG$code)
dir.create(DEBUG_DIR, recursive = TRUE, showWarnings = FALSE)

timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
file_stem <- paste0(CFG$code, "_", DYSCYPLINA, "_", timestamp)
OUT_XLSX <- file.path(OUT_DIR, paste0(file_stem, ".xlsx"))
OUT_CSV  <- file.path(OUT_DIR, paste0(file_stem, ".csv"))

WAIT_RESULTS <- 4
WAIT_PROFILE <- 6
MAX_NEXT_CLICKS <- 300
AUTOSAVE_EVERY <- 10
LIST_RETRY <- 3       # po ENTER czekamy nawet 3*WAIT_RESULTS sek na JS render listy

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
get_author_ids_from_results <- function(sid) {
  html <- tryCatch(wd_page_source(sid), error = function(e) "")
  if (!nzchar(html)) return(character())
  m <- regmatches(html, gregexpr(CFG$author_id_regex, html, perl = TRUE))[[1]]
  if (length(m) == 0) return(character())
  ids <- sub(".*/info/author/", "", m)
  ids <- sub("[?/#&].*$", "", ids)
  unique(ids[nzchar(ids)])
}

# --- Następna strona przez JS execute ---
# PrimeFaces używa event delegation + AJAX (PrimeFaces.ab). WebDriver native click
# często nie triggeruje handler. Wywołujemy `el.click()` z poziomu JS — to event
# faktycznie idzie przez listener PrimeFaces, zachowując stan filtra po stronie sesji.
go_to_next_page_js <- function(sid, verbose = TRUE) {
  script <- paste(
    "var el = document.querySelector('a.ui-paginator-next:not(.ui-state-disabled)');",
    "if (!el) return 'no-button';",
    "if (el.getAttribute('aria-disabled') === 'true') return 'disabled';",
    "el.click();",
    "return 'clicked';"
  )
  res <- tryCatch(wd_execute(sid, script),
                  error = function(e) paste0("ERR:", conditionMessage(e)))
  if (verbose) cat(sprintf("  [next-js] %s\n", res))
  isTRUE(res == "clicked")
}

# --- klik next (fallback) ---
# Omega-PSIR używa PrimeFaces paginator: <a class="ui-paginator-next">.
click_next <- function(sid, verbose = TRUE) {
  css_try <- c(
    "a.ui-paginator-next:not(.ui-state-disabled)",
    "a.ui-paginator-next",
    "a[rel='next']",
    "a[aria-label*='Nast']",
    "a[title*='Nast']",
    "li.next a",
    ".pagination li.next a"
  )
  for (css in css_try) {
    els <- tryCatch(wd_find_elements(sid, "css selector", css),
                    error = function(e) {
                      if (verbose) cat(sprintf("  [click] CSS '%s' FIND-ERR: %s\n",
                                               css, conditionMessage(e)))
                      character()
                    })
    if (verbose) cat(sprintf("  [click] CSS '%s' -> %d elem\n", css, length(els)))
    if (length(els) > 0) {
      ok <- tryCatch({ wd_click(sid, els[1]); TRUE },
                     error = function(e) {
                       if (verbose) cat(sprintf("  [click] CLICK-ERR: %s\n",
                                                conditionMessage(e)))
                       FALSE
                     })
      if (ok) {
        if (verbose) cat(sprintf("  [click] OK przez CSS '%s'\n", css))
        return(TRUE)
      }
    }
  }
  xpath_try <- c(
    "//a[contains(@class,'ui-paginator-next') and not(contains(@class,'ui-state-disabled'))]",
    "//a[contains(@aria-label,'Nast')]",
    "//a[contains(@title,'Nast')]",
    "//a[@rel='next']",
    "//li[contains(@class,'next')]/a"
  )
  for (xp in xpath_try) {
    els <- tryCatch(wd_find_elements(sid, "xpath", xp),
                    error = function(e) character())
    if (verbose) cat(sprintf("  [click] XPATH '%s' -> %d elem\n",
                             substr(xp, 1, 60), length(els)))
    if (length(els) > 0) {
      ok <- tryCatch({ wd_click(sid, els[1]); TRUE }, error = function(e) FALSE)
      if (ok) {
        if (verbose) cat(sprintf("  [click] OK przez XPath\n"))
        return(TRUE)
      }
    }
  }
  if (verbose) cat("  [click] WSZYSTKIE selektory zawiodły\n")
  FALSE
}

# --- pobierz HTML ---
get_page_html <- function(sid) wd_page_source(sid)

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
  n_pub    <- get_value_by_label(doc, "Liczba\\s*publikacji|Liczba\\s*pozycji|Wszystkie\\s*publikacje")

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
  if (is.na(n_pub)) {
    # Fallback: Omega-PSIR pokazuje liczbę publikacji w nagłówku zakładki, np. "Publikacje (145)".
    n_pub <- extract_metric_value(
      page_txt,
      "(?:liczba\\s*publikacji|liczba\\s*pozycji|wszystkie\\s*publikacje|publikacje)",
      "[0-9]+",
      80
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
    n_pub    = suppressWarnings(as.numeric(gsub("\\D", "", n_pub))),
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
      !is.na(rec$sum_MEiN),
      !is.na(rec$n_pub))
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
get_profile_record <- function(sid, author_id, wait_sec = WAIT_PROFILE) {
  url <- profile_url(author_id)
  wd_navigate(sid, url)
  Sys.sleep(wait_sec)

  html <- get_page_html(sid)
  rec <- parse_profile_html(html)

  if (!has_any_data(rec)) {
    Sys.sleep(3)
    html <- get_page_html(sid)
    rec <- parse_profile_html(html)
  }

  if (looks_like_block_page(html) && !has_any_data(rec)) {
    warning(sprintf("Podejrzenie strony logowania/blokady dla %s", author_id), call. = FALSE)
  }

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

SID <- wd_new_session()
cat(sprintf("[SESSION] WebDriver sid=%s\n", substr(SID, 1, 16)))
wd_navigate(SID, URL_RESULTS)
Sys.sleep(WAIT_RESULTS)

cat("\n--- OKNO CHROME OTWARTE ---\n")
cat("Ustaw filtry w panelu po lewej i kliknij 'Filtruj' (np. Liczba pozycji: 146).\n\n")
invisible(readline(prompt = "Gdy filtry są ustawione i zastosowane, wciśnij ENTER w konsoli R... "))

# ---------- Diagnostyka po ENTER ----------
cur_url <- tryCatch(wd_current_url(SID),         error = function(e) "<?>")
html_sz <- tryCatch(nchar(wd_page_source(SID)),  error = function(e) 0L)
cat(sprintf("\n[DIAG] aktualny URL : %s\n", cur_url))
cat(sprintf("[DIAG] rozmiar HTML : %d bajtow\n", html_sz))
screen_path <- file.path(DEBUG_DIR, "screen_after_enter.png")
tryCatch(wd_screenshot(SID, screen_path),
         error = function(e) cat("[DIAG] screenshot ERROR:", conditionMessage(e), "\n"))
if (file.exists(screen_path))
  cat(sprintf("[DIAG] screenshot   : %s\n", screen_path))

# ---------- ETAP 1: author_id ----------
cat("\n[ETAP 1] Zbieram author_id...\n")
all_ids <- character()
prev_ids_on_page <- character()
no_growth <- 0

for (k in 1:MAX_NEXT_CLICKS) {
  Sys.sleep(WAIT_RESULTS)
  ids <- get_author_ids_from_results(SID)
  for (try_n in seq_len(LIST_RETRY - 1)) {
    if (length(ids) > 0) break
    cat(sprintf("strona=%d | brak wynikow w DOM, retry %d/%d po %ds...\n",
                k, try_n, LIST_RETRY - 1, WAIT_RESULTS))
    Sys.sleep(WAIT_RESULTS)
    ids <- get_author_ids_from_results(SID)
  }
  if (length(ids) == 0) break

  before <- length(all_ids)
  all_ids <- unique(c(all_ids, ids))
  added <- length(all_ids) - before

  cat(sprintf("strona=%d | ids_na_stronie=%d | unikalne=%d | +%d\n",
              k, length(ids), length(all_ids), added))

  # Debug: zapis HTML pierwszej strony żeby zobaczyć paginator
  if (k == 1) {
    dump_path <- file.path(DEBUG_DIR, "page1_source.html")
    writeLines(wd_page_source(SID), dump_path, useBytes = TRUE)
    cat(sprintf("  [DEBUG] zapis HTML strony 1: %s\n", dump_path))
  }

  same_page <- length(prev_ids_on_page) > 0 && identical(ids, prev_ids_on_page)
  prev_ids_on_page <- ids

  if (added == 0 || same_page) no_growth <- no_growth + 1 else no_growth <- 0
  if (no_growth >= 2) break

  # Primary: PrimeFaces click przez JS. Fallback: WebDriver native click.
  moved <- go_to_next_page_js(SID)
  if (!moved) moved <- click_next(SID)
  if (!moved) break
}

cat("\nZebrano profili: ", length(all_ids), "\n", sep = "")
if (length(all_ids) == 0) {
  wd_quit(SID)
  stop("Nie zebrano żadnych profili – sprawdź filtry i listę wyników.")
}

# ---------- ETAP 2: profile ----------
cat("\n[ETAP 2] Pobieram dane z profili (HTML)...\n")
records <- vector("list", length(all_ids))

for (i in seq_along(all_ids)) {
  id <- all_ids[i]
  cat(sprintf("[%d/%d] %s\n", i, length(all_ids), id))

  records[[i]] <- tryCatch(
    get_profile_record(SID, id),
    error = function(e) {
      data.frame(
        profil = NA_character_, stanowisko = NA_character_,
        jednostka = NA_character_, wydzial = NA_character_,
        h_index_scopus = NA_real_, h_index_wos = NA_real_,
        sum_IF = NA_real_, sum_SNIP = NA_real_, sum_MEiN = NA_real_,
        n_pub = NA_real_,
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
    print(records[[i]][, c("profil","jednostka","wydzial","h_index_scopus","sum_IF","sum_MEiN","n_pub")])
  }

  if (i %% AUTOSAVE_EVERY == 0 || i == length(all_ids)) {
    df_partial <- do.call(rbind, records[seq_len(i)])
    if (!("error" %in% names(df_partial))) df_partial$error <- NA_character_
    df_partial <- df_partial[, c("profil","stanowisko","jednostka","wydzial",
                                 "h_index_scopus","h_index_wos","sum_IF","sum_SNIP","sum_MEiN","n_pub",
                                 "author_id","url","error")]
    save_outputs(df_partial, OUT_CSV, OUT_XLSX)
    cat(sprintf("  [AUTOSAVE] zapisano %d/%d do: %s i %s\n", i, length(all_ids), OUT_CSV, OUT_XLSX))
  }
}

df <- do.call(rbind, records)
if (!("error" %in% names(df))) df$error <- NA_character_

df <- df[, c("profil","stanowisko","jednostka","wydzial",
             "h_index_scopus","h_index_wos","sum_IF","sum_SNIP","sum_MEiN","n_pub",
             "author_id","url","error")]

# ---------- zapis ----------
save_outputs(df, OUT_CSV, OUT_XLSX)

  cat("\nZapisano:\nCSV : ", OUT_CSV, "\nXLSX: ", OUT_XLSX, "\n", sep = "")
  cat("Debug HTML (dla profili bez danych): ", normalizePath(DEBUG_DIR), "\n", sep = "")

wd_quit(SID)

df


