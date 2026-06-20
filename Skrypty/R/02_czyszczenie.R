# LTeX: enabled=false
# ============================================================
# 02 - Czyszczenie surowych zbiorow z CRIS (4 uczelnie Omega-PSIR, dyscyplina rolnictwo i ogrodnictwo)
# Proba FINAL 2026-05-26: UPWr(A), SGGW(A), URK(A), UWM(B+) - wszystkie wczytywane.
# Input:  Dane/raw/<uczelnia>_rolnictwo_i_ogrodnictwo_<timestamp>.csv
#         (UP Poznan i UP Lublin zarchiwizowane w Dane/raw/_archive/ - nie wczytywane)
# Output: Dane/master/profiles_clean.csv
# ============================================================

library(dplyr)
library(tidyr)
library(stringr)
library(readr)
library(purrr)
library(fs)
library(here)

# Pliki uczelni kategorii A. UP Poznan ma DWA pliki:
# - osoby (Person z metrykami z ETAP 2): up_poznan_rolnictwo_*.csv
# - publikacje per autor (do warstwy 04): up_poznan_publications_rolnictwo_*.csv (POMIJAMY tu)
# Tylko pliki profili 4 uczelni w dyscyplinie. Glob na "_rolnictwo_i_ogrodnictwo_"
# odsiewa slowniki pomocnicze (np. udzial_przyznanych_kategorii_naukowych_ogolem.csv).
raw_files <- dir_ls(here("Dane", "raw"), glob = "*_rolnictwo_i_ogrodnictwo_*.csv") %>%
  keep(~ !str_detect(., "_publications_"))   # tylko Person CSV, nie publikacyjne

stopifnot(length(raw_files) > 0)
cat("Wczytuje pliki:\n"); cat(paste("  -", path_file(raw_files), collapse = "\n"), "\n\n")

# ---------- 1. Wczytanie i scalenie ----------
# Why regex uczelnia: stary "^[a-z]+(?=_)" urywal up_poznan do "up".
# Nowy regex: bierze wszystko do _rolnictwo_ (zakladamy 1 dyscyplina po zmianie koncepcji).
df_all <- raw_files %>%
  set_names(path_file) %>%
  map_dfr(read_csv, .id = "plik_zrodlowy", show_col_types = FALSE) %>%
  mutate(
    # Leniwy kwantyfikator "+?" lapie NAJKROTSZY ciag liter/podkreslen az do
    # lookahead "_rolnictwo_". Zachlanne "+" zjadloby tez czesc po dyscyplinie,
    # ale tu kluczowe jest, ze przy nazwach typu "up_poznan_rolnictwo_..." leniwy
    # wariant nie uznaje przedwczesnie "_" za koniec dopasowania (lookahead
    # przesuwa go dalej), wiec zwraca pelne "up_poznan", a nie samo "up".
    uczelnia = str_extract(plik_zrodlowy, "^[a-z_]+?(?=_rolnictwo_)")
  )

cat("Wczytano profili:", nrow(df_all), "z", length(raw_files), "plikow\n")
cat("Uczelnie:", paste(unique(df_all$uczelnia), collapse = ", "), "\n\n")

# ---------- 2. Standaryzacja stanowiska ----------
# UPWr ma stanowiska typu "specjalista", "starszy specjalista" - to nie naukowcy,
# odsiewamy w kroku 3. Zachowujemy oryginalny string do diagnostyki.
df_all <- df_all %>%
  mutate(
    stanowisko_raw = stanowisko,
    stanowisko = case_when(
      # KOLEJNOSC LOAD-BEARING: "profesor uczelni" MUSI byc przed wzorcem
      # "^profesor", bo case_when bierze pierwsze pasujace dopasowanie. Gdyby
      # "^profesor" bylo wyzej, "profesor uczelni" tez by go spelnil i zostalby
      # blednie sklasyfikowany jako zwykly "profesor" (utrata rozroznienia
      # stanowiska, kluczowego dla gradientu kariery w dalszej analizie).
      str_detect(tolower(stanowisko %||% ""), "profesor uczelni") ~ "profesor uczelni",
      str_detect(tolower(stanowisko %||% ""), "^profesor") ~ "profesor",
      str_detect(tolower(stanowisko %||% ""), "adiunkt") ~ "adiunkt",
      str_detect(tolower(stanowisko %||% ""), "asystent") ~ "asystent",
      str_detect(tolower(stanowisko %||% ""), "wykładowca|wykladowca") ~ "wykladowca",
      !is.na(stanowisko) ~ tolower(stanowisko),
      TRUE ~ NA_character_
    )
  )

# ---------- 3. Filtr nie-naukowcow ----------
# Why: UPWr i podobne ekspozucja Omega-PSIR zwraca takze pracownikow technicznych
# (specjalista, starszy specjalista, pracownik pomocniczy). Maja n_pub=0/NA i pusty
# orcid - nie sa naukowcami w sensie analizy bibliometrycznej.
nie_naukowcy <- c("specjalista", "starszy specjalista", "starszy specjalista inzynieryjno-techniczny",
                  "pracownik pomocniczy", "pracownik gospodarczy")
df_naukowcy <- df_all %>%
  filter(!stanowisko %in% nie_naukowcy)

n_dropped <- nrow(df_all) - nrow(df_naukowcy)
cat(sprintf("Filtr nie-naukowcow: usunieto %d profili (%.1f%%)\n",
            n_dropped, 100*n_dropped/nrow(df_all)))

# ---------- 4. Deduplikacja po (uczelnia, profil) ----------
# Zakladamy, ze para (uczelnia, profil) jest unikalnym kluczem osoby. .keep_all
# zachowuje wszystkie kolumny PIERWSZEGO wiersza w grupie - przy ewentualnych
# imiennikach w tej samej uczelni zostanie tylko pierwszy (akceptowalne ryzyko
# przy tej skali proby; bardziej szkodliwe byloby liczenie ich podwojnie).
df_clean <- df_naukowcy %>%
  distinct(uczelnia, profil, .keep_all = TRUE) %>%
  select(-plik_zrodlowy, -any_of(c("error")))

# ---------- 5. Raport brakow ----------
braki <- df_clean %>%
  summarise(across(everything(), ~sum(is.na(.)))) %>%
  pivot_longer(everything(), names_to = "kolumna", values_to = "brak_n") %>%
  mutate(brak_pct = round(100 * brak_n / nrow(df_clean), 1))
print(braki, n = nrow(braki))

cat("\nProfile per uczelnia (po filtrowaniu i deduplikacji):\n")
df_clean %>% count(uczelnia) %>% print()

# ---------- 6. Zapis ----------
dir_create(here("Dane", "master"))
write_csv(df_clean, here("Dane", "master", "profiles_clean.csv"))
cat("\nZapisano:", here("Dane", "master", "profiles_clean.csv"),
    "\nRekordow:", nrow(df_clean), "\n")
