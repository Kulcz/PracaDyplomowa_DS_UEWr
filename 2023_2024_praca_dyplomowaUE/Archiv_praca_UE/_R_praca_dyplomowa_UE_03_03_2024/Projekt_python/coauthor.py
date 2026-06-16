import networkx as nx
import scholar_network as sn

sn.scrape_single_author(scholar_id='ZmwzVQUAAAAJ', scholar_name='Michelle Duong')
graph = sn.build_graph()

G = nx.Graph()
G.add_edges_from(graph.node_pairs())