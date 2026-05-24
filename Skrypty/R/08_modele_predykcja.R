# LTeX: enabled=false
# ============================================================
# 08 - Warstwa 3 z planu DS: modelowanie predykcyjne
# Cel: klasyfikacja "high-impact" (top 10% IF lub FWCI) z cech strukturalnych
#       (bez h-index jako predyktora — unik tautologii)
# Input:  Dane/master/profiles_features.csv
# Output: Wykresy/modele/*.png, output/model_results.rds
# ============================================================

library(dplyr)
library(tidymodels)
library(ranger)
library(xgboost)
library(shapviz)
library(vip)
library(here)
library(readr)

df <- read_csv(here("Dane", "master", "profiles_features.csv"), show_col_types = FALSE)

# ---------- 1. Definicja targetu ----------
df <- df %>%
  group_by(dyscyplina) %>%   # top 10% w obrebie dyscypliny (FWCI lepiej, IF jako fallback)
  mutate(high_impact = factor(sum_IF >= quantile(sum_IF, 0.9, na.rm = TRUE),
                              levels = c(FALSE, TRUE), labels = c("no", "yes"))) %>%
  ungroup()

# ---------- 2. Split + recipe ----------
set.seed(42)
split <- initial_split(df, strata = high_impact, prop = 0.8)
train <- training(split); test <- testing(split)
folds <- vfold_cv(train, v = 5, strata = high_impact)

# Predyktory: stanowisko, dyscyplina, uczelnia, n_pub, n_coauthors, avg_authors
# NIE: h_index_wos, sum_IF (tautologia)
rec <- recipe(high_impact ~ stanowisko + dyscyplina + uczelnia + n_pub +
                            n_unique_coauthors + avg_authors_per_pub,
              data = train) %>%
  step_impute_median(all_numeric_predictors()) %>%
  step_dummy(all_nominal_predictors()) %>%
  step_zv(all_predictors())

# ---------- 3. Modele: RF + XGBoost ----------
rf_spec <- rand_forest(mtry = tune(), trees = 500, min_n = tune()) %>%
  set_engine("ranger", importance = "permutation") %>%
  set_mode("classification")

xgb_spec <- boost_tree(trees = tune(), learn_rate = tune(), tree_depth = tune()) %>%
  set_engine("xgboost") %>%
  set_mode("classification")

# TODO: workflow_set + tune_grid + collect_metrics
# TODO: ROC-AUC, precision/recall, confusion matrix
# TODO: SHAP (shapviz::shapviz + sv_importance + sv_dependence)
# TODO: porownanie RF vs XGB

cat("TODO: implementacja warstwy 3 (tydzien 8 harmonogramu)\n")
