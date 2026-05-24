# LTeX: enabled=false
# ============================================================
# 02 - Czyszczenie surowych zbiorow z Omega-PSIR
# Input:  Dane/raw/<uczelnia>_<dyscyplina>_<timestamp>.csv
# Output: Dane/master/profiles_clean.csv
# ============================================================

library(dplyr)
library(tidyr)
library(stringr)
library(readr)
library(purrr)
library(fs)
library(here)

raw_files <- dir_ls(here("Dane", "raw"), glob = "*.csv")
stopifnot(length(raw_files) > 0)

# ---------- 1. Wczytanie i scalenie ----------
df_all <- raw_files %>%
  set_names(path_file) %>%
  map_dfr(read_csv, .id = "plik_zrodlowy", show_col_types = FALSE) %>%
  mutate(
    uczelnia  = str_extract(plik_zrodlowy, "^[a-z]+(?=_)"),
    dyscyplina = str_extract(plik_zrodlowy, "(?<=_)[a-z_]+(?=_\\d{8})")
  )

cat("Wczytano profili:", nrow(df_all), "z", length(raw_files), "plikow\n")

# ---------- 2. Standaryzacja stanowiska ----------
df_all <- df_all %>%
  mutate(stanowisko = case_when(
    str_detect(tolower(stanowisko %||% ""), "profesor uczelni") ~ "profesor uczelni",
    str_detect(tolower(stanowisko %||% ""), "^profesor") ~ "profesor",
    str_detect(tolower(stanowisko %||% ""), "adiunkt") ~ "adiunkt",
    str_detect(tolower(stanowisko %||% ""), "asystent") ~ "asystent",
    str_detect(tolower(stanowisko %||% ""), "wykładowca") ~ "wykladowca",
    !is.na(stanowisko) ~ tolower(stanowisko),
    TRUE ~ NA_character_
  ))

# ---------- 3. Deduplikacja po (uczelnia, profil) ----------
df_clean <- df_all %>%
  distinct(uczelnia, profil, .keep_all = TRUE) %>%
  select(-plik_zrodlowy, -any_of(c("error")))

# ---------- 4. Raport brakow ----------
braki <- df_clean %>%
  summarise(across(everything(), ~sum(is.na(.)))) %>%
  pivot_longer(everything(), names_to = "kolumna", values_to = "brak_n") %>%
  mutate(brak_pct = round(100 * brak_n / nrow(df_clean), 1))
print(braki)

# ---------- 5. Zapis ----------
dir_create(here("Dane", "master"))
write_csv(df_clean, here("Dane", "master", "profiles_clean.csv"))
cat("\nZapisano:", here("Dane", "master", "profiles_clean.csv"),
    "\nRekordow:", nrow(df_clean), "\n")
