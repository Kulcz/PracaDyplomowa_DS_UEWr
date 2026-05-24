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

matches <- read_csv(here("Dane", "openalex", "author_match.csv"), show_col_types = FALSE) %>%
  filter(!is.na(openalex_id), similarity >= 0.85)

# ---------- Helper: paginated works fetch ----------
fetch_works <- function(openalex_id, per_page = 100) {
  works <- list()
  cursor <- "*"
  repeat {
    req <- request(paste0(OPENALEX_BASE, "/works")) |>
      req_url_query(
        filter = paste0("authorships.author.id:", openalex_id),
        `per-page` = per_page,
        cursor = cursor,
        select = "id,publication_year,doi,title,authorships,cited_by_count,fwci",
        mailto = MAILTO
      ) |>
      req_retry(max_tries = 3) |>
      req_throttle(rate = 10 / 1)

    resp <- req_perform(req)
    body <- resp_body_json(resp)
    works <- c(works, body$results)
    cursor <- body$meta$next_cursor
    if (is.null(cursor) || length(body$results) == 0) break
  }
  works
}

# TODO: petla po matches z autosave co 50 osob (RDS cache w Dane/openalex/cache/)
# TODO: ekstrakcja publications.csv (work_id, year, fwci, n_authors, anchor_author_id)
# TODO: ekstrakcja coauthorship_edges.csv (author_a, author_b, work_id) z authorships[]
# TODO: budowa edge list z waga = n_wspolnych_publikacji

cat("TODO: implementacja petli Works API (tydzien 5 harmonogramu)\n")
