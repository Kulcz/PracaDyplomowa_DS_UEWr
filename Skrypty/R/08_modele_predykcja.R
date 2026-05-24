# LTeX: enabled=false
# ============================================================
# 08 - Warstwa 3 z planu DS: modelowanie predykcyjne
# Cel: klasyfikacja "high-impact" (top 10% IF w obrębie dyscypliny)
#      z cech strukturalnych — bez h_index/sum_IF jako predyktorów (tautologia).
# Input:  Dane/master/profiles_features.csv
# Output: Wykresy/modele/*.png, output/model_results.rds
# ============================================================

library(dplyr)
library(tidyr)
library(ggplot2)
library(readr)
library(here)
library(fs)
library(tidymodels)
library(ranger)
library(xgboost)
library(shapviz)
library(vip)
library(yardstick)
library(patchwork)

set.seed(42)

stopifnot(file_exists(here("Dane", "master", "profiles_features.csv")))
df <- read_csv(here("Dane", "master", "profiles_features.csv"), show_col_types = FALSE)

PLOT_DIR <- here("Wykresy", "modele"); dir_create(PLOT_DIR)
OUT_DIR  <- here("output");             dir_create(OUT_DIR)

# ---------- 1. Definicja targetu: high_impact = top 10% IF w obrębie dyscypliny ----------
df <- df %>%
  filter(!is.na(sum_IF), !is.na(dyscyplina)) %>%
  group_by(dyscyplina) %>%
  mutate(high_impact = factor(
    sum_IF >= quantile(sum_IF, 0.9, na.rm = TRUE),
    levels = c(FALSE, TRUE), labels = c("no", "yes")
  )) %>%
  ungroup()

cat(sprintf("[TARGET] high_impact = top 10%% sum_IF per dyscyplina\n"))
cat(sprintf("  yes : %d (%.1f%%)\n",
            sum(df$high_impact == "yes"), 100 * mean(df$high_impact == "yes")))
cat(sprintf("  no  : %d (%.1f%%)\n",
            sum(df$high_impact == "no"),  100 * mean(df$high_impact == "no")))

# ---------- 2. Predyktory ----------
# Stałe: cechy strukturalne dostępne od razu po 02_czyszczenie + 05_features.
# Opcjonalne: zostaną dodane po 05_features (jeśli OpenAlex zwróci coauthors).
strukturalne <- c("stanowisko", "dyscyplina", "uczelnia", "n_pub")
opcjonalne   <- c("n_unique_coauthors", "avg_authors_per_pub", "mean_fwci")
maja         <- intersect(opcjonalne, names(df))

if (length(maja) > 0) {
  cat(sprintf("[FEATURES] doliczam opcjonalne: %s\n", paste(maja, collapse = ", ")))
}
predyktory <- c(strukturalne, maja)
df_model <- df %>%
  select(high_impact, all_of(predyktory)) %>%
  mutate(across(where(is.character), as.factor))

# ---------- 3. Split + CV folds ----------
split  <- initial_split(df_model, strata = high_impact, prop = 0.8)
train  <- training(split)
test   <- testing(split)
folds  <- vfold_cv(train, v = 5, strata = high_impact)

# ---------- 4. Recipe ----------
form_full <- as.formula(paste("high_impact ~", paste(predyktory, collapse = " + ")))
rec <- recipe(form_full, data = train) %>%
  step_impute_median(all_numeric_predictors()) %>%
  step_unknown(all_nominal_predictors()) %>%
  step_dummy(all_nominal_predictors()) %>%
  step_zv(all_predictors())

# ---------- 5. Model specs ----------
rf_spec <- rand_forest(mtry = tune(), trees = 500, min_n = tune()) %>%
  set_engine("ranger", importance = "permutation", num.threads = 4) %>%
  set_mode("classification")

xgb_spec <- boost_tree(
  trees = tune(), learn_rate = tune(), tree_depth = tune(), min_n = tune()
) %>%
  set_engine("xgboost") %>%
  set_mode("classification")

# ---------- 6. Workflow set + tune ----------
wf_set <- workflow_set(
  preproc = list(base = rec),
  models  = list(rf = rf_spec, xgb = xgb_spec)
)

ctrl <- control_grid(save_pred = TRUE, save_workflow = TRUE, verbose = FALSE)
mset <- metric_set(roc_auc, accuracy, sens, spec, j_index)

cat("\n=== Tuning 5-fold CV (RF + XGB) — może potrwać kilka minut ===\n")
res <- wf_set %>%
  workflow_map(
    "tune_grid",
    seed = 42,
    resamples = folds,
    grid = 10,
    metrics = mset,
    control = ctrl,
    verbose = TRUE
  )

# ---------- 7. Ranking + best ----------
ranking <- rank_results(res, rank_metric = "roc_auc", select_best = TRUE)
cat("\n=== Ranking modeli (najlepsza konfiguracja per typ) ===\n")
print(ranking %>% select(wflow_id, .metric, mean, std_err, rank))

# Best per workflow id
best_rf  <- res %>% extract_workflow_set_result("base_rf")  %>%
  select_best(metric = "roc_auc")
best_xgb <- res %>% extract_workflow_set_result("base_xgb") %>%
  select_best(metric = "roc_auc")

# Finalize + fit na pelnym train
fit_rf  <- res %>% extract_workflow("base_rf")  %>%
  finalize_workflow(best_rf)  %>% fit(train)
fit_xgb <- res %>% extract_workflow("base_xgb") %>%
  finalize_workflow(best_xgb) %>% fit(train)

# ---------- 8. Test set: metryki + confusion matrix ----------
pred_rf  <- predict(fit_rf,  test, type = "prob") %>%
  bind_cols(predict(fit_rf,  test)) %>% bind_cols(test %>% select(high_impact))
pred_xgb <- predict(fit_xgb, test, type = "prob") %>%
  bind_cols(predict(fit_xgb, test)) %>% bind_cols(test %>% select(high_impact))

test_metrics <- bind_rows(
  pred_rf  %>% mset(truth = high_impact, .pred_yes, estimate = .pred_class, event_level = "second") %>% mutate(model = "RF"),
  pred_xgb %>% mset(truth = high_impact, .pred_yes, estimate = .pred_class, event_level = "second") %>% mutate(model = "XGB")
)
cat("\n=== Test set metrics ===\n"); print(test_metrics)

cm_rf  <- conf_mat(pred_rf,  truth = high_impact, estimate = .pred_class)
cm_xgb <- conf_mat(pred_xgb, truth = high_impact, estimate = .pred_class)
cat("\n[CM RF] \n"); print(cm_rf$table)
cat("\n[CM XGB]\n"); print(cm_xgb$table)

# ---------- 9. ROC curves ----------
roc_rf  <- pred_rf  %>% roc_curve(truth = high_impact, .pred_yes, event_level = "second") %>% mutate(model = "RF")
roc_xgb <- pred_xgb %>% roc_curve(truth = high_impact, .pred_yes, event_level = "second") %>% mutate(model = "XGB")
roc_df  <- bind_rows(roc_rf, roc_xgb)

p_roc <- ggplot(roc_df, aes(x = 1 - specificity, y = sensitivity, color = model)) +
  geom_path(linewidth = 1) +
  geom_abline(slope = 1, intercept = 0, linetype = 2, color = "grey60") +
  coord_equal() +
  scale_color_manual(values = c(RF = "#3C5488", XGB = "#E64B35")) +
  labs(title = "ROC: RF vs XGBoost (test set)",
       x = "1 - Specificity", y = "Sensitivity") +
  theme_minimal(base_size = 12)
ggsave(file.path(PLOT_DIR, "01_roc.png"), p_roc, width = 7, height = 6, dpi = 200)

# ---------- 10. Variable importance (RF permutation) ----------
vi_rf <- fit_rf %>% extract_fit_parsnip() %>% vi()
p_vip_rf <- vi_rf %>% slice_max(Importance, n = 15) %>%
  ggplot(aes(x = reorder(Variable, Importance), y = Importance)) +
  geom_col(fill = "#3C5488") + coord_flip() +
  labs(title = "RF: ważność permutacyjna predyktorów (top 15)",
       x = NULL, y = "Importance") +
  theme_minimal(base_size = 12)
ggsave(file.path(PLOT_DIR, "02_vip_rf.png"), p_vip_rf, width = 8, height = 6, dpi = 200)

# ---------- 11. SHAP dla XGB (natywnie) ----------
# shapviz potrzebuje surowej macierzy X przepuszczonej przez recipe.
xgb_baked <- bake(prep(rec), new_data = test %>% select(-high_impact))
xgb_engine <- extract_fit_engine(fit_xgb)
sv <- shapviz(xgb_engine, X_pred = as.matrix(xgb_baked))

p_shap_imp <- sv_importance(sv, kind = "bar", max_display = 15) +
  labs(title = "XGBoost: SHAP importance (top 15)")
ggsave(file.path(PLOT_DIR, "03_shap_importance.png"),
       p_shap_imp, width = 8, height = 6, dpi = 200)

p_shap_bee <- sv_importance(sv, kind = "beeswarm", max_display = 15) +
  labs(title = "XGBoost: SHAP beeswarm (top 15)")
ggsave(file.path(PLOT_DIR, "04_shap_beeswarm.png"),
       p_shap_bee, width = 9, height = 6, dpi = 200)

# ---------- 12. Zapis ----------
saveRDS(
  list(
    target_def    = "high_impact = top 10% sum_IF per dyscyplina",
    predyktory    = predyktory,
    tune_results  = res,
    ranking       = ranking,
    fit_rf        = fit_rf,
    fit_xgb       = fit_xgb,
    test_metrics  = test_metrics,
    conf_mat      = list(rf = cm_rf, xgb = cm_xgb),
    vip_rf        = vi_rf,
    shap_xgb      = sv
  ),
  file.path(OUT_DIR, "model_results.rds")
)

cat(sprintf("\nZapisano: %s\nWykresy: %s\n",
            file.path(OUT_DIR, "model_results.rds"), PLOT_DIR))
