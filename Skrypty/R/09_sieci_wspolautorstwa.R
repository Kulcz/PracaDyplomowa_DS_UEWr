# LTeX: enabled=false
# ============================================================
# 09 - Warstwa 4 z planu DS: sieci współautorstwa
# Cel: graf coauthorship wewnątrz kohorty, community detection (Louvain),
#      centralności, zgodność ze stanowiskiem/uczelnią (ARI/NMI)
#
# Decyzje metodyczne (2026-06-13):
#  - Krawedzie (coauthorship_edges.csv) sa kluczowane OpenAlex ID; master nie
#    ma openalex_id -> dolaczamy go z author_match.csv (match_accepted) po
#    author_id. Wezly = profile ZMATCHOWANE w OpenAlex (367).
#  - Zmienna grupujaca: stanowisko + uczelnia (dawniej dyscyplina - usunieta).
#  - UWM ma najslabszy match OpenAlex (67.1%) -> jest niedoreprezentowany
#    w sieci; do raportu "Ograniczenia".
# Input:  Dane/openalex/{coauthorship_edges,author_match}.csv + master/profiles_features.csv
# Output: Wykresy/sieci/*.png, output/network_metrics.rds, Dashboard/network.html
# ============================================================

library(dplyr)
library(tidyr)
library(ggplot2)
library(readr)
library(here)
library(fs)
library(igraph)
library(tidygraph)
library(ggraph)
library(visNetwork)

set.seed(42)

EDGES_FILE <- here("Dane", "openalex", "coauthorship_edges.csv")
NODES_FILE <- here("Dane", "master", "profiles_features.csv")
MATCH_FILE <- here("Dane", "openalex", "author_match.csv")
stopifnot(file_exists(EDGES_FILE), file_exists(NODES_FILE), file_exists(MATCH_FILE))

edges_raw <- read_csv(EDGES_FILE, show_col_types = FALSE)
nodes_raw <- read_csv(NODES_FILE, show_col_types = FALSE)
match_raw <- read_csv(MATCH_FILE, show_col_types = FALSE)

PLOT_DIR <- here("Wykresy", "sieci");    dir_create(PLOT_DIR)
OUT_DIR  <- here("output");                dir_create(OUT_DIR)
DASH_DIR <- here("Dashboard");             dir_create(DASH_DIR)

EDGE_WEIGHT_MIN <- 2     # wycina przypadkowe wspolne pojedyncze publikacje

# ---------- 1. Węzły: master + openalex_id z author_match ----------
# author_match linkuje author_id (Omega-PSIR) <-> openalex_id; bierzemy
# tylko zaakceptowane dopasowania.
match_ok <- match_raw %>%
  mutate(match_accepted = as.logical(match_accepted)) %>%
  filter(match_accepted, !is.na(openalex_id)) %>%
  distinct(author_id, .keep_all = TRUE) %>%
  select(author_id, openalex_id)

nodes <- nodes_raw %>%
  inner_join(match_ok, by = "author_id") %>%
  distinct(openalex_id, .keep_all = TRUE) %>%
  select(openalex_id, profil, uczelnia, stanowisko)

# Krawedzie wewnetrzne: oba endpointy w kohorcie, waga >= prog.
edges <- edges_raw %>%
  filter(author_a %in% nodes$openalex_id,
         author_b %in% nodes$openalex_id,
         weight >= EDGE_WEIGHT_MIN)

cat(sprintf("[FILTR] nodes=%d (zmatchowane), edges (weight>=%d, wewn.)=%d\n",
            nrow(nodes), EDGE_WEIGHT_MIN, nrow(edges)))

# ---------- 2. Budowa grafu ----------
g <- graph_from_data_frame(
  d = edges %>% select(from = author_a, to = author_b, weight),
  vertices = nodes %>% select(openalex_id, profil, uczelnia, stanowisko),
  directed = FALSE
)
cat(sprintf("[GRAPH] V=%d E=%d density=%.4f transitivity=%.3f\n",
            vcount(g), ecount(g),
            edge_density(g), transitivity(g, type = "global")))

# ---------- 3. Wybierz największą komponentę spójności ----------
comps <- components(g)
giant_id <- which.max(comps$csize)
g_main <- induced_subgraph(g, V(g)[comps$membership == giant_id])
cat(sprintf("[GIANT] V=%d (%.0f%% węzłów) E=%d\n",
            vcount(g_main), 100 * vcount(g_main) / vcount(g), ecount(g_main)))

# ---------- 4. Centralności ----------
V(g_main)$degree      <- degree(g_main)
V(g_main)$betweenness <- betweenness(g_main, normalized = TRUE)
V(g_main)$eigenvec    <- eigen_centrality(g_main)$vector

centr_df <- tibble(
  openalex_id = V(g_main)$name,
  profil      = V(g_main)$profil,
  uczelnia    = V(g_main)$uczelnia,
  stanowisko  = V(g_main)$stanowisko,
  degree      = V(g_main)$degree,
  betweenness = V(g_main)$betweenness,
  eigenvec    = V(g_main)$eigenvec
)

# Top 20 wg degree
cat("\n=== TOP 20 wg degree (giant component) ===\n")
print(centr_df %>% slice_max(degree, n = 20) %>%
        select(profil, uczelnia, stanowisko, degree, betweenness))

# ---------- 5. Community detection (Louvain) ----------
louvain <- cluster_louvain(g_main, weights = E(g_main)$weight)
V(g_main)$community <- membership(louvain)
mod <- modularity(louvain)
cat(sprintf("\n[LOUVAIN] communities=%d modularity=%.3f\n",
            length(louvain), mod))

# Wielkości społeczności
comm_sizes <- as.data.frame(table(membership(louvain))) %>%
  setNames(c("community", "n")) %>%
  arrange(desc(n))
cat("\n=== Wielkości społeczności (top 10) ===\n")
print(head(comm_sizes, 10))

# ---------- 6. ARI/NMI: community vs (stanowisko, uczelnia) ----------
df_cmp <- centr_df %>%
  mutate(community = membership(louvain)) %>%
  filter(!is.na(stanowisko), !is.na(uczelnia))

ari_stan <- igraph::compare(
  as.integer(factor(df_cmp$community)),
  as.integer(factor(df_cmp$stanowisko)),
  method = "adjusted.rand"
)
ari_ucz <- igraph::compare(
  as.integer(factor(df_cmp$community)),
  as.integer(factor(df_cmp$uczelnia)),
  method = "adjusted.rand"
)
nmi_stan <- igraph::compare(
  as.integer(factor(df_cmp$community)),
  as.integer(factor(df_cmp$stanowisko)),
  method = "nmi"
)
nmi_ucz <- igraph::compare(
  as.integer(factor(df_cmp$community)),
  as.integer(factor(df_cmp$uczelnia)),
  method = "nmi"
)
cat(sprintf("\n[ZGODNOSC] ARI(comm,stan)=%.3f NMI=%.3f\n", ari_stan, nmi_stan))
cat(sprintf("[ZGODNOSC] ARI(comm,ucz )=%.3f NMI=%.3f\n", ari_ucz,  nmi_ucz))

# ---------- 7. Heatmapy zgodności ----------
ct_stan <- table(community = df_cmp$community, stanowisko = df_cmp$stanowisko) %>%
  as.data.frame() %>%
  group_by(community) %>%
  mutate(pct = Freq / sum(Freq)) %>%
  ungroup()

p_heat_stan <- ggplot(ct_stan, aes(x = stanowisko, y = factor(community), fill = pct)) +
  geom_tile() +
  geom_text(aes(label = sprintf("%.0f%%", 100 * pct)), size = 3) +
  scale_fill_gradient(low = "white", high = "#3C5488") +
  labs(title = sprintf("Społeczności Louvain × stanowisko (ARI = %.3f)", ari_stan),
       x = NULL, y = "Społeczność", fill = "% w społ.") +
  theme_minimal(base_size = 12) +
  theme(axis.text.x = element_text(angle = 30, hjust = 1))
ggsave(file.path(PLOT_DIR, "01_comm_vs_stanowisko.png"),
       p_heat_stan, width = 8, height = 7, dpi = 200)

ct_ucz <- table(community = df_cmp$community, uczelnia = df_cmp$uczelnia) %>%
  as.data.frame() %>%
  group_by(community) %>%
  mutate(pct = Freq / sum(Freq)) %>%
  ungroup()

p_heat_ucz <- ggplot(ct_ucz, aes(x = uczelnia, y = factor(community), fill = pct)) +
  geom_tile() +
  geom_text(aes(label = sprintf("%.0f%%", 100 * pct)), size = 3) +
  scale_fill_gradient(low = "white", high = "#E64B35") +
  labs(title = sprintf("Społeczności Louvain × uczelnia (ARI = %.3f)", ari_ucz),
       x = NULL, y = "Społeczność", fill = "% w społ.") +
  theme_minimal(base_size = 12)
ggsave(file.path(PLOT_DIR, "02_comm_vs_uczelnia.png"),
       p_heat_ucz, width = 7, height = 7, dpi = 200)

# ---------- 8. Wizualizacja statyczna (ggraph) ----------
# Layout "stress" jest stabilny + szybki dla dużych sieci.
tg <- as_tbl_graph(g_main)

p_net <- ggraph(tg, layout = "stress") +
  geom_edge_link(aes(width = weight), alpha = 0.15, color = "grey30") +
  geom_node_point(aes(color = factor(community), size = degree)) +
  scale_edge_width(range = c(0.2, 1.5), guide = "none") +
  scale_size(range = c(0.5, 5)) +
  labs(title = sprintf("Sieć współautorstwa — kolor: społeczność Louvain (Q=%.3f)", mod),
       color = "Społeczność", size = "Stopień") +
  theme_void(base_size = 12) +
  theme(legend.position = "right")
ggsave(file.path(PLOT_DIR, "03_siec_louvain.png"),
       p_net, width = 12, height = 10, dpi = 200)

# Kolor wg uczelni — czy społeczności pokrywają się z afiliacją?
p_net_ucz <- ggraph(tg, layout = "stress") +
  geom_edge_link(alpha = 0.15, color = "grey30") +
  geom_node_point(aes(color = uczelnia, size = degree), alpha = 0.85) +
  scale_size(range = c(0.5, 5)) +
  labs(title = "Sieć współautorstwa — kolor: uczelnia",
       color = "Uczelnia", size = "Stopień") +
  theme_void(base_size = 12)
ggsave(file.path(PLOT_DIR, "04_siec_uczelnia.png"),
       p_net_ucz, width = 12, height = 10, dpi = 200)

# ---------- 9. Statystyki globalne + degree distribution ----------
deg_df <- tibble(degree = V(g_main)$degree)
p_deg <- ggplot(deg_df, aes(x = degree)) +
  geom_histogram(bins = 40, fill = "#3C5488") +
  scale_x_log10() + scale_y_log10() +
  labs(title = "Rozkład stopni (log-log) — giant component",
       x = "Stopień", y = "Liczba węzłów") +
  theme_minimal(base_size = 12)
ggsave(file.path(PLOT_DIR, "05_degree_distribution.png"),
       p_deg, width = 7, height = 5, dpi = 200)

# ---------- 10. Wizualizacja interaktywna (visNetwork -> HTML) ----------
vis_nodes <- tibble(
  id     = V(g_main)$name,
  label  = V(g_main)$profil,
  group  = as.character(V(g_main)$community),
  value  = V(g_main)$degree,
  title  = sprintf("%s<br>Uczelnia: %s<br>Stanowisko: %s<br>Stopień: %d",
                   V(g_main)$profil, V(g_main)$uczelnia,
                   V(g_main)$stanowisko, V(g_main)$degree)
)
vis_edges <- igraph::as_data_frame(g_main, what = "edges") %>%
  rename(from = from, to = to) %>% mutate(value = weight)

vis <- visNetwork(vis_nodes, vis_edges,
                  main = sprintf("Sieć współautorstwa (Louvain, Q=%.3f)", mod)) %>%
  visIgraphLayout(layout = "layout_with_fr") %>%
  visOptions(highlightNearest = list(enabled = TRUE, degree = 1),
             nodesIdSelection = TRUE) %>%
  visLegend()
visSave(vis, file = file.path(DASH_DIR, "network.html"), selfcontained = TRUE)

# ---------- 11. Zapis ----------
saveRDS(
  list(
    graph        = g_main,
    centralities = centr_df,
    louvain      = louvain,
    modularity   = mod,
    comm_sizes   = comm_sizes,
    ari = list(stan = ari_stan, ucz = ari_ucz),
    nmi = list(stan = nmi_stan, ucz = nmi_ucz),
    crosstabs = list(stan = ct_stan, ucz = ct_ucz),
    global_stats = list(
      V = vcount(g_main), E = ecount(g_main),
      density = edge_density(g_main),
      transitivity = transitivity(g_main, type = "global"),
      mean_degree = mean(V(g_main)$degree),
      diameter = diameter(g_main, weights = NA)
    )
  ),
  file.path(OUT_DIR, "network_metrics.rds")
)

cat(sprintf("\nZapisano:\n  %s\n  %s\nWykresy: %s\n",
            file.path(OUT_DIR, "network_metrics.rds"),
            file.path(DASH_DIR, "network.html"),
            PLOT_DIR))
