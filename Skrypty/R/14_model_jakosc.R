# LTeX: enabled=false
# ============================================================
# 14 - Model jakosciowy: predykcja WYSOKIEJ JAKOSCI (nie ilosci)
#
# Motywacja (krytyka tautologii warstwy 3): target high_impact = top 10% sum_IF
# jest kumulatywny -> przewiduje glownie staz/produktywnosc. Tu definiujemy
# target NIEKUMULATYWNY: mean_fwci > 1.0 (impact powyzej swiatowej sredniej
# w dziedzinie, niezalezny od liczby publikacji), i dokladamy jawna ceche
# WIEKU AKADEMICKIEGO. Pytanie: czy jakosc da sie przewidziec ze stazu, czy
# jest od niego niezalezna?
#
# Predyktory: stanowisko, uczelnia, n_pub, wiek_akad, n_unique_coauthors,
#             avg_authors_per_pub. BEZ if_per_pub/sum_IF/h_index/mean_fwci
#             (pochodne IF -> tautologia z targetem).
# Probka: autorzy zmatchowani do OpenAlex z policzonym FWCI (366 z 367 matchu).
# Input:  Dane/master/profiles_features.csv, Dane/openalex/{publications,author_match}.csv
# Output: Wykresy/modele/1{1,2}_jakosc_*.png, output/model_jakosc.rds
# ============================================================

library(dplyr)
library(tidyr)
library(ggplot2)
library(readr)
library(here)
library(fs)
library(rsample)
library(recipes)
library(parsnip)
library(workflows)
library(workflowsets)
library(tune)
library(dials)
library(yardstick)
library(ranger)
library(xgboost)
library(vip)

set.seed(42)

PLOT_DIR <- here("Wykresy", "modele"); dir_create(PLOT_DIR)
OUT_DIR  <- here("output");             dir_create(OUT_DIR)

df    <- read_csv(here("Dane", "master", "profiles_features.csv"), show_col_types = FALSE)
pubs  <- read_csv(here("Dane", "openalex", "publications.csv"), show_col_types = FALSE)
match <- read_csv(here("Dane", "openalex", "author_match.csv"), show_col_types = FALSE)

# ---------- 1. Wiek akademicki (odporny) ----------
# Start kariery = 5. percentyl lat publikacji autora (odporny na bledne
# atrybucje pojedynczych bardzo starych prac w OpenAlex), po odsianiu lat < 1950.
REF_YEAR <- 2026L  # rok referencyjny pracy - przypiety (bylo Sys.Date()); spojnie z 12_dynamika_omega.R
career <- pubs %>%
  filter(!is.na(publication_year), publication_year >= 1950, publication_year <= REF_YEAR) %>%
  group_by(anchor_author_id) %>%
  summarise(start = floor(quantile(publication_year, 0.05, names = FALSE)), .groups = "drop") %>%
  # Clamp wieku akademickiego do przedzialu 0-60 lat:
  #  - pmax(...,0L): nie ma ujemnego stazu (zabezpieczenie na publikacje "z przyszlosci"),
  #  - pmin(...,60L): cap 60 odcina artefakty - blednie przypisana w OpenAlex bardzo
  #    stara pierwsza publikacja zawyzalaby staz do nierealnych wartosci.
  mutate(wiek_akad = pmin(pmax(REF_YEAR - start, 0L), 60L))

# author_id (Omega) <-> openalex_id
age_by_author <- match %>%
  filter(match_accepted, !is.na(openalex_id)) %>%
  select(author_id, openalex_id) %>%
  left_join(career, by = c("openalex_id" = "anchor_author_id")) %>%
  select(author_id, wiek_akad)

df <- df %>% left_join(age_by_author, by = "author_id")

# ---------- 2. Target: high_quality = mean_fwci > 1.0 ----------
# Prog 1.0 nie jest arbitralny: FWCI=1.0 to DEFINICYJNA wartosc odniesienia
# (sredni swiatowy poziom cytowan w danej dziedzinie/roku/typie pracy). Zatem
# mean_fwci > 1.0 = dorobek cytowany powyzej sredniej swiatowej.
df_q <- df %>%
  filter(!is.na(mean_fwci)) %>%
  mutate(high_quality = factor(mean_fwci > 1.0,
                               levels = c(FALSE, TRUE), labels = c("no", "yes")))

cat(sprintf("[TARGET] high_quality = mean_fwci > 1.0 (n=%d)\n", nrow(df_q)))
cat(sprintf("  yes : %d (%.1f%%)\n", sum(df_q$high_quality=="yes"), 100*mean(df_q$high_quality=="yes")))
cat(sprintf("  wiek_akad: mediana=%.0f, NA=%d\n",
            median(df_q$wiek_akad, na.rm = TRUE), sum(is.na(df_q$wiek_akad))))

# ---------- 3. Predyktory (bez pochodnych IF) ----------
predyktory <- c("stanowisko", "uczelnia", "n_pub", "wiek_akad",
                "n_unique_coauthors", "avg_authors_per_pub")
df_model <- df_q %>%
  select(high_quality, all_of(predyktory)) %>%
  mutate(across(where(is.character), as.factor))

# ---------- 4. Split + CV ----------
split <- initial_split(df_model, strata = high_quality, prop = 0.8)
train <- training(split); test <- testing(split)
folds <- vfold_cv(train, v = 5, strata = high_quality)

# ---------- 5. Recipe ----------
form_full <- as.formula(paste("high_quality ~", paste(predyktory, collapse = " + ")))
rec <- recipe(form_full, data = train) %>%
  step_impute_median(all_numeric_predictors()) %>%
  step_unknown(all_nominal_predictors()) %>%
  step_dummy(all_nominal_predictors()) %>%
  step_zv(all_predictors())

# ---------- 6. Modele ----------
# Ta sama asymetria RF/XGB co w 08: RF ma trees=500 na stalo (wiecej drzew tylko
# stabilizuje usrednienie, nie przeucza - stroimy mtry/min_n), XGB ma trees=tune()
# (boosting sekwencyjny przeucza przy zbyt wielu drzewach - liczbe drzew stroimy
# razem z learn_rate).
rf_spec <- rand_forest(mtry = tune(), trees = 500, min_n = tune()) %>%
  set_engine("ranger", importance = "permutation", num.threads = 4) %>%
  set_mode("classification")
xgb_spec <- boost_tree(trees = tune(), learn_rate = tune(),
                       tree_depth = tune(), min_n = tune()) %>%
  set_engine("xgboost") %>% set_mode("classification")

wf_set <- workflow_set(preproc = list(base = rec),
                       models = list(rf = rf_spec, xgb = xgb_spec))
ctrl <- control_grid(save_pred = TRUE, save_workflow = TRUE, verbose = FALSE)
mset <- metric_set(roc_auc, accuracy, sens, spec, j_index)

cat("\n=== Tuning 5-fold CV (RF + XGB) ===\n")
# verbose=FALSE: cichy tuning (08 ma tu verbose=TRUE - drobna, swiadoma
# niespojnosc, bez wplywu na wyniki). grid=10 jak w 08.
res <- wf_set %>% workflow_map("tune_grid", seed = 42, resamples = folds,
                               grid = 10, metrics = mset, control = ctrl, verbose = FALSE)

ranking <- rank_results(res, rank_metric = "roc_auc", select_best = TRUE)
cat("\n=== Ranking modeli ===\n")
print(ranking %>% select(wflow_id, .metric, mean, std_err, rank))

best_rf  <- res %>% extract_workflow_set_result("base_rf")  %>% select_best(metric = "roc_auc")
best_xgb <- res %>% extract_workflow_set_result("base_xgb") %>% select_best(metric = "roc_auc")
fit_rf  <- res %>% extract_workflow("base_rf")  %>% finalize_workflow(best_rf)  %>% fit(train)
fit_xgb <- res %>% extract_workflow("base_xgb") %>% finalize_workflow(best_xgb) %>% fit(train)

# ---------- 7. Test ----------
pred_rf  <- predict(fit_rf,  test, type = "prob") %>%
  bind_cols(predict(fit_rf,  test)) %>% bind_cols(test %>% select(high_quality))
pred_xgb <- predict(fit_xgb, test, type = "prob") %>%
  bind_cols(predict(fit_xgb, test)) %>% bind_cols(test %>% select(high_quality))
test_metrics <- bind_rows(
  pred_rf  %>% mset(truth = high_quality, .pred_yes, estimate = .pred_class, event_level = "second") %>% mutate(model = "RF"),
  pred_xgb %>% mset(truth = high_quality, .pred_yes, estimate = .pred_class, event_level = "second") %>% mutate(model = "XGB")
)
cat("\n=== Test set metrics ===\n"); print(test_metrics)

# ---------- 8. ROC ----------
roc_df <- bind_rows(
  pred_rf  %>% roc_curve(truth = high_quality, .pred_yes, event_level = "second") %>% mutate(model = "RF"),
  pred_xgb %>% roc_curve(truth = high_quality, .pred_yes, event_level = "second") %>% mutate(model = "XGB")
)
p_roc <- ggplot(roc_df, aes(1 - specificity, sensitivity, color = model)) +
  geom_path(linewidth = 1) + geom_abline(slope = 1, intercept = 0, linetype = 2, color = "grey60") +
  coord_equal() + scale_color_manual(values = c(RF = "#3C5488", XGB = "#E64B35")) +
  labs(title = "Model jakosciowy (FWCI>1): ROC", x = "1 - Specificity", y = "Sensitivity") +
  theme_minimal(base_size = 12)
ggsave(file.path(PLOT_DIR, "11_jakosc_roc.png"), p_roc, width = 7, height = 6, dpi = 200)

# ---------- 9. Vaznosc cech ----------
vi_rf <- fit_rf %>% extract_fit_parsnip() %>% vi()
cat("\n=== RF: vaznosc permutacyjna ===\n"); print(vi_rf)
p_vip <- vi_rf %>% slice_max(Importance, n = 15) %>%
  ggplot(aes(reorder(Variable, Importance), Importance)) +
  geom_col(fill = "#00A087") + coord_flip() +
  labs(title = "Model jakosciowy: waznosc predyktorow (RF)", x = NULL, y = "Importance") +
  theme_minimal(base_size = 12)
ggsave(file.path(PLOT_DIR, "12_jakosc_vip.png"), p_vip, width = 8, height = 6, dpi = 200)

# ---------- 10. Zapis ----------
saveRDS(list(target_def = "high_quality = mean_fwci > 1.0",
             predyktory = predyktory, ranking = ranking,
             test_metrics = test_metrics, vip_rf = vi_rf,
             prevalence = mean(df_q$high_quality == "yes")),
        file.path(OUT_DIR, "model_jakosc.rds"))
cat("\nZapisano: output/model_jakosc.rds, Wykresy/modele/1{1,2}_jakosc_*.png\n")
