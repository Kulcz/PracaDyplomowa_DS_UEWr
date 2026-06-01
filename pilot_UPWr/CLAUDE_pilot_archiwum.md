# Pamięć projektu: UPWr_bibliometria (ARCHIWUM — wchłonięty do PracaDyplomowa_DS_UEWr)

> **2026-05-31:** Ten plik to archiwum pamięci dawnego samodzielnego projektu.
> `UPWr_bibliometria` jest teraz **pilotażem** w podfolderze `pilot_UPWr/`
> nadrzędnej pracy **PracaDyplomowa_DS_UEWr** — jedno repo, jeden `renv`,
> jeden `.venv`, jeden git. Aktualną pamięcią projektu jest nadrzędny `CLAUDE.md`.
> Treść poniżej zachowana wyłącznie dla kontekstu historycznego.

## 📋 Informacje zasadnicze
    1. Najpierw przemyśl problem, przeczytaj kod źródłowy w poszukiwaniu odpowiednich plików i zapisz plan w pliku Tasks/todo.md.
    2. Plan powinien zawierać listę zadań do wykonania (todo), które możesz odhaczać w miarę postępów.
    3. Zanim zaczniesz pracę, skontaktuj się ze mną, a ja zatwierdzę plan.
    4. Następnie rozpocznij pracę nad zadaniami, zaznaczając je jako wykonane w miarę postępu.
    5. Na każdym etapie po prostu przedstaw mi ogólny opis dokonanych zmian.
    6. Wykonuj każde zadanie i każdą zmianę w kodzie w możliwie najprostszy sposób. Chcemy unikać jakichkolwiek dużych lub złożonych zmian. 
       Każda zmiana powinna wpływać na jak najmniejszą część kodu. Wszystko sprowadza się do prostoty.
    7. Na końcu dodaj sekcję recenzji do pliku todo.md z podsumowaniem dokonanych zmian oraz innymi istotnymi informacjami.
    8. NIE BĄDŹ LENIWY. NIGDY NIE BĄDŹ LENIWY. JEŚLI JEST BŁĄD – ZNAJDŹ JEGO PRAWDZIWĄ PRZYCZYNĘ I GO NAPRAW. ŻADNYCH TYMCZASOWYCH POPRAWEK. 
       JESTEŚ STARSZYM PROGRAMISTĄ. NIGDY NIE BĄDŹ LENIWY.
    9. WPROWADZAJ WSZYSTKIE POPRAWKI I ZMIANY W KODZIE W NAJPROSTSZY MOŻLIWY SPOSÓB. POWINNY DOTYCZYĆ TYLKO KODU ZWIĄZANEGO Z ZADANIEM I NICZEGO WIĘCEJ. 
       WPŁYW NA KOD POWINIEN BYĆ JAK NAJMNIEJSZY. TWOIM CELEM JEST NIE WPROWADZAĆ ŻADNYCH BŁĘDÓW. WSZYSTKO SPROWADZA SIĘ DO PROSTOTY.


## 📋 Informacje podstawowe
- **Nazwa:** UPWr_bibliometria
- **Typ:** Analiza statystyczna
- **Języki:** R + Python
- **Data utworzenia:** 2026-03-06
- **Autor:** grzegorz

## 📁 Struktura katalogów
- `Skrypty/R/` — kod R (scraper, czyszczenie/analiza, analiza pracowników)
- `Skrypty/Python/` — kod Python (utility, obecnie pusty)
- `output_bibliometria/` — dane (surowe ze scrapera + oczyszczone) i wyniki w CSV/Excel
- `Wykresy/` — wykresy i wizualizacje (PNG)
- `Raport/` — raporty Quarto (.qmd) i PDF: wydziałowy + indywidualne
- `Tasks/` — zadania do wykonania (todo.md)

## 🔧 Środowisko
- **IDE:** Positron (getwd() = root projektu, tam gdzie .Rproj)
- **R:** zarządzane przez renv
- **Python:** venv w katalogu venv/
- **Git:** repozytorium lokalne + backup w pCloud

## 📝 Notatki projektu
[Dodawaj tutaj ważne informacje o projekcie]

## 🎯 Cele projektu
1. [Cel 1]
2. [Cel 2]
3. [Cel 3]

## 📊 Analizy do wykonania
- [ ] Analiza 1
- [ ] Analiza 2
- [ ] Analiza 3

## 🔗 Linki i zasoby
- [Link do publikacji]
- [Link do danych źródłowych]

## Literatura
Baza artykulow Markdown: ~/pCloudDrive/Zotero_markdown/
Indeks: ~/pCloudDrive/Zotero_markdown/INDEKS.md
Indeks tematyczny: poczatek INDEKS.md — grupy tematyczne ze zrodlami priorytetowymi (*)

**Przeszukiwanie (6 krokow — workflow obowiazkowy przy pisaniu/przepisywaniu):**
0. NAJPIERW przeczytaj sekcje tematyczne z INDEKS.md (linie 38-300) — ZAPISZ liste kandydatow
1. Wielorundowy Grep w INDEKS.md (min. 5 zapytan: tematy, procesy, wyzwania, terminy ang., autorzy):
   Grep pattern="slowo_kluczowe" path="~/pCloudDrive/Zotero_markdown/INDEKS.md"
2. Grep pelnotekstowy w calej bazie (0.3s):
   Grep pattern="konkretny termin" path="~/pCloudDrive/Zotero_markdown/" glob="*_merged.md"
3. Weryfikacja bibliografii oryginalu (jesli przepisywanie) — KAZDA pozycje sprawdz w INDEKS.md
4. Read zrodel + weryfikacja krzyzowa (sprawdz bibliografie czytanego zrodla — nowe pozycje?)
5. Checklist kompletnosci: ile zrodel, z ilu kategorii, czy sa priorytetowe (*),
   czy oryginał pokryty. OBOWIAZKOWY raport zrodel na koncu.

**Zasady pracy z literatura:**
- Kazde twierdzenie merytoryczne weryfikuj w min. 2 niezaleznych zrodlach
- Priorytet: podręczniki referencyjne (*) > monografie > artykuly > skrypty
- Przy cytowaniu ZAWSZE podaj: Autor (Rok), numer linii w pliku _merged.md
- Po weryfikacji zapisz kluczowe wartosci do plikow _ref_*.md w projekcie
- **Przeszukiwanie DWUKIERUNKOWE:**
  - Od tematu: Grep po slowach kluczowych
  - Od indeksu: przeczytaj CALE sekcje tematyczne (linie 38-300 INDEKS.md)
  Sam Grep NIE wystarczy — pomija zrodla ogolne ktore nie zawieraja szukanych terminow
- **Przy przepisywaniu rozdzialu:** ZAWSZE sprawdz bibliografie oryginalu w INDEKS.md
- **Wielorundowy Grep:** min. 5 zapytan (tematy, procesy, wyzwania, terminy ang., autorzy)
- **Weryfikacja krzyzowa:** po przeczytaniu zrodla sprawdz jego bibliografie
- **Checklist + raport:** PRZED pisaniem sprawdz kompletnosc, PO pisaniu dolacz raport zrodel
- **Citation-first:** PRZED pisaniem wypisz cytaty/fakty ze zrodel z numerami linii. Pisz WYLACZNIE na ich podstawie.

**Obrazy:** Claude moze czytac pliki .jpeg z folderow konwersji (wykresy, tabele).
**Zotero MCP:** Dostepny do wyszukiwania metadanych bibliograficznych.
**Subagenty:** Agent tool MA dostep do pCloudDrive (FUSE mount dziedziczy kontekst uzytkownika).
**UWAGA:** NIGDY nie uzywac `sed -i` na pCloudDrive — zeruje pliki!

**Indeks sekcji top-15 podręczników:** ~/pCloudDrive/Zotero_markdown/INDEKS_SEKCJI_TOP15.md
**Pelny poradnik:** ~/Analiza_projekty/Praca_z_literatura/PORADNIK_praca_z_literatura.qmd