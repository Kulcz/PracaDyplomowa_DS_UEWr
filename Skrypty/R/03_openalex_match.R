# LTeX: enabled=false
# ============================================================
# 03 - Matching profili Omega-PSIR do OpenAlex Author ID
# Strategia: search po (imie+nazwisko, ROR uczelni) -> fuzzy match
# Input:  Dane/master/profiles_clean.csv
# Output: Dane/openalex/author_match.csv (+ raport match_rate)
# ============================================================

library(dplyr)
library(stringr)
library(purrr)
library(httr2)
library(jsonlite)
library(stringdist)
library(readr)
library(fs)
library(here)

# ROR-y 4 uczelni Omega-PSIR w dyscyplinie rolnictwo i ogrodnictwo (FINAL 2026-05-26).
# Zweryfikowane 2026-05-24 via api.ror.org.
# Why 4 Omega-PSIR a nie 4A: test kompletności 2026-05-26 wykazal DSpace UP Poznan
# pokazuje ~10-15% rzeczywistego dorobku autorow vs Omega-PSIR ~250-300%. Mieszanie
# tych systemow w analizie ilosciowej zafalszowalo by porownania miedzyuczelniane.
ROR <- c(
  upwr = "05cs8k179",   # Wroclaw University of Environmental and Life Sciences
  sggw = "05srvzs48",   # Warsaw University of Life Sciences (SGGW)
  urk  = "012dxyr07",   # University of Agriculture in Krakow
  uwm  = "05s4feg49"    # University of Warmia and Mazury in Olsztyn
  # up_poznan = "04g6bbq64"  # DSpace, w archiwum (zob. _archive/)
)

OPENALEX_BASE <- "https://api.openalex.org"
MAILTO <- "grzegorz.kulczycki@gmail.com"  # polite pool
SIM_THRESHOLD <- 0.85                     # akceptacja Jaro-Winkler
AUTOSAVE_EVERY <- 50

OUT_DIR  <- here("Dane", "openalex")
OUT_FILE <- file.path(OUT_DIR, "author_match.csv")
dir_create(OUT_DIR)

stopifnot(file_exists(here("Dane", "master", "profiles_clean.csv")))
profiles <- read_csv(here("Dane", "master", "profiles_clean.csv"), show_col_types = FALSE)

# ---------- Helper: pojedyncze zapytanie ----------
search_openalex_author <- function(name, ror) {
  req <- request(paste0(OPENALEX_BASE, "/authors")) |>
    req_url_query(
      search = name,
      filter = paste0("affiliations.institution.ror:", ror),
      `per-page` = 25,
      mailto = MAILTO
    ) |>
    req_retry(max_tries = 3) |>
    req_throttle(rate = 10 / 1)  # 10 req/s

  resp <- tryCatch(req_perform(req), error = function(e) NULL)
  if (is.null(resp)) return(NULL)
  resp_body_json(resp)$results
}

# ---------- Helper: dopasowanie fuzzy ----------
best_match <- function(name, candidates) {
  if (length(candidates) == 0) return(NULL)
  names_cand <- map_chr(candidates, "display_name", .default = NA)
  d <- stringdist(tolower(name), tolower(names_cand), method = "jw")
  i <- which.min(d)
  list(
    openalex_id = candidates[[i]]$id,
    matched_name = names_cand[i],
    similarity = 1 - d[i]
  )
}

# ---------- Helper: czyszczenie nazwy do searcha ----------
# Omega-PSIR zwraca "prof. dr hab. inż. Jan Kowalski" — OpenAlex search lepiej radzi sobie
# z czystym "Jan Kowalski" niż z prefiksami tytulow naukowych.
clean_name_for_search <- function(x) {
  if (is.na(x) || !nzchar(x)) return(NA_character_)
  x <- str_replace_all(x, "(?i)\\b(prof|dr|hab|inz|inż|mgr|lic|emer|m\\.sc|ph\\.?d)\\.?", "")
  x <- str_squish(x)
  if (!nzchar(x)) NA_character_ else x
}

# ---------- Pojedynczy match dla 1 profilu ----------
match_one <- function(profil, uczelnia) {
  ror <- ROR[uczelnia]
  name_clean <- clean_name_for_search(profil)

  if (is.na(ror) || is.na(name_clean)) {
    return(tibble(
      candidates_n = NA_integer_, openalex_id = NA_character_,
      matched_name = NA_character_, similarity = NA_real_,
      match_accepted = FALSE, error = "missing_ror_or_name"
    ))
  }

  cands <- tryCatch(
    search_openalex_author(name_clean, ror),
    error = function(e) NULL
  )
  if (is.null(cands)) {
    return(tibble(
      candidates_n = NA_integer_, openalex_id = NA_character_,
      matched_name = NA_character_, similarity = NA_real_,
      match_accepted = FALSE, error = "api_failure"
    ))
  }

  bm <- best_match(name_clean, cands)
  if (is.null(bm)) {
    return(tibble(
      candidates_n = 0L, openalex_id = NA_character_,
      matched_name = NA_character_, similarity = NA_real_,
      match_accepted = FALSE, error = NA_character_
    ))
  }

  tibble(
    candidates_n = length(cands),
    openalex_id  = bm$openalex_id,
    matched_name = bm$matched_name,
    similarity   = bm$similarity,
    match_accepted = bm$similarity >= SIM_THRESHOLD,
    error = NA_character_
  )
}

# ---------- Resumability: wczytaj poprzednie wyniki ----------
done_ids <- character()
if (file_exists(OUT_FILE)) {
  prev <- read_csv(OUT_FILE, show_col_types = FALSE)
  done_ids <- prev$author_id[!is.na(prev$author_id)]
  cat(sprintf("[RESUME] Pominę %d profili już obsłużonych w %s\n",
              length(done_ids), OUT_FILE))
}

to_process <- profiles %>% filter(!(author_id %in% done_ids))
cat(sprintf("[START] Profili do dopasowania: %d (z %d całość)\n",
            nrow(to_process), nrow(profiles)))

# ---------- Pętla z autosave ----------
results <- vector("list", nrow(to_process))
t0 <- Sys.time()

for (i in seq_len(nrow(to_process))) {
  row <- to_process[i, ]
  rec <- match_one(row$profil, row$uczelnia)
  rec$author_id <- row$author_id
  rec$profil_clean <- clean_name_for_search(row$profil)
  rec$uczelnia <- row$uczelnia
  rec$dyscyplina <- row$dyscyplina
  results[[i]] <- rec

  if (i %% 25 == 0 || i == nrow(to_process)) {
    el <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
    eta <- el / i * (nrow(to_process) - i)
    cat(sprintf("[%d/%d] sim=%.2f acc=%s | el=%.0fs eta=%.0fs\n",
                i, nrow(to_process),
                rec$similarity %||% NA_real_,
                rec$match_accepted, el, eta))
  }

  if (i %% AUTOSAVE_EVERY == 0 || i == nrow(to_process)) {
    df_partial <- bind_rows(results[seq_len(i)])
    # merge z poprzednimi (resumability)
    if (file_exists(OUT_FILE)) {
      prev <- read_csv(OUT_FILE, show_col_types = FALSE)
      df_partial <- bind_rows(prev, df_partial) %>%
        distinct(author_id, .keep_all = TRUE)
    }
    write_csv(df_partial, OUT_FILE)
  }
}

# ---------- Raport match_rate ----------
final <- read_csv(OUT_FILE, show_col_types = FALSE)
cat("\n========== MATCH RATE ==========\n")
overall <- mean(final$match_accepted, na.rm = TRUE)
cat(sprintf("Cały zbiór : %.1f%% (%d / %d)\n",
            100 * overall, sum(final$match_accepted, na.rm = TRUE), nrow(final)))

mr_tab <- final %>%
  group_by(uczelnia, dyscyplina) %>%
  summarise(
    n = n(),
    matched = sum(match_accepted, na.rm = TRUE),
    match_rate = round(100 * matched / n, 1),
    .groups = "drop"
  )
print(mr_tab)

cat(sprintf("\nZapisano: %s\n", OUT_FILE))
