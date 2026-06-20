# LTeX: enabled=false
# ============================================================
# 04 - Pobieranie publikacji z OpenAlex (per matched author)
# Cel: collect publications + coauthors + FWCI
# Input:  Dane/openalex/author_match.csv
# Output: Dane/openalex/publications.csv
#         Dane/openalex/coauthorship_edges.csv
# ============================================================

library(dplyr)
library(tidyr)
library(httr2)
library(purrr)
library(readr)
library(fs)
library(here)

OPENALEX_BASE <- "https://api.openalex.org"
MAILTO <- "grzegorz.kulczycki@gmail.com"
PER_PAGE <- 100
PROGRESS_EVERY <- 10   # log co N autorow

OUT_DIR     <- here("Dane", "openalex")
CACHE_DIR   <- file.path(OUT_DIR, "cache")
PUBS_FILE   <- file.path(OUT_DIR, "publications.csv")
EDGES_FILE  <- file.path(OUT_DIR, "coauthorship_edges.csv")
dir_create(CACHE_DIR)

stopifnot(file_exists(file.path(OUT_DIR, "author_match.csv")))
matches <- read_csv(file.path(OUT_DIR, "author_match.csv"), show_col_types = FALSE) %>%
  filter(match_accepted, !is.na(openalex_id))

cat(sprintf("[START] Autorów do pobrania: %d\n", nrow(matches)))

# ---------- Helper: paginated works fetch ----------
fetch_works <- function(openalex_id) {
  works <- list()
  cursor <- "*"
  repeat {
    req <- request(paste0(OPENALEX_BASE, "/works")) |>
      req_url_query(
        filter = paste0("authorships.author.id:", openalex_id),
        `per-page` = PER_PAGE,
        cursor = cursor,
        # select = lista pol zwracanych przez API. Ograniczamy ja do minimum
        # potrzebnego dalej: id/rok/doi/title do identyfikacji pracy, authorships
        # do sieci wspolautorstwa, cited_by_count do h-index. fwci (Field-Weighted
        # Citation Impact) to pole SPECYFICZNE dla OpenAlex - znormalizowany
        # wzgledem dziedziny i rocznika wskaznik cytowan, nie do policzenia lokalnie.
        # Wezsze select = mniejszy payload i szybsza odpowiedz API.
        select = "id,publication_year,doi,title,authorships,cited_by_count,fwci",
        mailto = MAILTO
      ) |>
      req_retry(max_tries = 3) |>
      req_throttle(rate = 10 / 1)

    resp <- req_perform(req)
    body <- resp_body_json(resp)
    works <- c(works, body$results)
    cursor <- body$meta$next_cursor
    # Koniec cursor pagingu: OpenAlex zwraca next_cursor dopoki sa kolejne strony,
    # a po ostatniej daje null. Stad is.null(cursor) = brak nastepnej strony.
    # length(results)==0 to dodatkowy bezpiecznik na pusta ostatnia strone, by
    # nie zapetlic sie na tym samym (potencjalnie niezmiennym) kursorze.
    if (is.null(cursor) || length(body$results) == 0) break
  }
  works
}

# ---------- Cache: 1 RDS na autora (resumability) ----------
cache_path <- function(openalex_id) {
  # OpenAlex ID ma format "https://openalex.org/A1234567890" — bierzemy ostatni segment.
  id <- sub(".*/", "", openalex_id)
  file.path(CACHE_DIR, paste0(id, ".rds"))
}

fetch_and_cache <- function(openalex_id) {
  cp <- cache_path(openalex_id)
  if (file_exists(cp)) return(readRDS(cp))
  works <- tryCatch(fetch_works(openalex_id), error = function(e) {
    message(sprintf("  [ERROR] %s: %s", openalex_id, conditionMessage(e)))
    list()
  })
  saveRDS(works, cp)
  works
}

# ---------- Ekstrakcja: 1 praca -> 1 wiersz publications + N par coauthors ----------
extract_publication_row <- function(w, anchor_id) {
  auths <- w$authorships %||% list()
  tibble(
    anchor_author_id = anchor_id,
    work_id          = w$id %||% NA_character_,
    publication_year = w$publication_year %||% NA_integer_,
    doi              = w$doi %||% NA_character_,
    # Obciecie tytulu do 250 znakow (magic number): tytul sluzy tylko do podgladu/
    # diagnostyki, a dlugie tytuly (zwlaszcza materialow konferencyjnych) bywaja
    # bardzo dlugie i niepotrzebnie rozdymalyby plik publications.csv.
    title            = (w$title %||% NA_character_) |> substr(1, 250),
    n_authors        = length(auths),
    cited_by_count   = w$cited_by_count %||% NA_integer_,
    fwci             = w$fwci %||% NA_real_
  )
}

extract_edge_rows <- function(w, anchor_id) {
  auths <- w$authorships %||% list()
  ids <- map_chr(auths, ~ .x$author$id %||% NA_character_) |> discard(is.na)
  if (length(ids) < 2) return(tibble())
  # nieskierowane krawędzie (anchor_id, coauthor) — agregacja do edge listy na końcu
  # setdiff usuwa anchora z listy autorow pracy: bez tego powstalaby self-petla
  # (anchor-anchor); zaraz przy okazji deduplikuje ewentualne powtorzenie anchora
  # w authorships, zostawiajac tylko faktycznych wspolautorow.
  others <- setdiff(ids, anchor_id)
  if (length(others) == 0) return(tibble())
  tibble(
    author_a = anchor_id,
    author_b = others,
    work_id  = w$id %||% NA_character_
  )
}

# ---------- Pętla po autorach ----------
all_pubs  <- vector("list", nrow(matches))
all_edges <- vector("list", nrow(matches))
t0 <- Sys.time()

for (i in seq_len(nrow(matches))) {
  oid <- matches$openalex_id[i]
  works <- fetch_and_cache(oid)

  all_pubs[[i]]  <- map_dfr(works, extract_publication_row, anchor_id = oid)
  all_edges[[i]] <- map_dfr(works, extract_edge_rows,       anchor_id = oid)

  if (i %% PROGRESS_EVERY == 0 || i == nrow(matches)) {
    el  <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
    eta <- el / i * (nrow(matches) - i)
    cat(sprintf("[%d/%d] works=%d | el=%.0fs eta=%.0fs\n",
                i, nrow(matches), length(works), el, eta))
  }
}

# ---------- Publications.csv ----------
pubs_df <- bind_rows(all_pubs)
write_csv(pubs_df, PUBS_FILE)
cat(sprintf("\nZapisano %d wierszy publications -> %s\n", nrow(pubs_df), PUBS_FILE))

# ---------- Edge list z wagą = liczba wspólnych prac ----------
# Nieskierowana: kanonizujemy pary (sort alfabetyczny) i agregujemy.
edges_long <- bind_rows(all_edges) %>%
  mutate(
    a = pmin(author_a, author_b),
    b = pmax(author_a, author_b)
  ) %>%
  distinct(a, b, work_id)   # 1 krawędź per (para, praca)

edges_df <- edges_long %>%
  group_by(a, b) %>%
  summarise(weight = n(), .groups = "drop") %>%
  rename(author_a = a, author_b = b)

write_csv(edges_df, EDGES_FILE)
cat(sprintf("Zapisano %d krawędzi coauthorship -> %s\n", nrow(edges_df), EDGES_FILE))

# ---------- Mini-raport ----------
cat("\n========== STATYSTYKI ==========\n")
cat(sprintf("Autorów obsłużonych : %d\n", nrow(matches)))
cat(sprintf("Publikacji łącznie  : %d\n", nrow(pubs_df)))
cat(sprintf("Median prac/autora  : %.0f\n",
            median(pubs_df %>% count(anchor_author_id) %>% pull(n), na.rm = TRUE)))
cat(sprintf("Krawędzi (par)      : %d\n", nrow(edges_df)))
cat(sprintf("Median waga krawędzi: %.1f\n", median(edges_df$weight, na.rm = TRUE)))
