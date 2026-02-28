"""
Network Policy Diagram for ECK 2026 Project.

Shows the default-deny + selective-allow network policy
architecture across namespaces, with specific ports labeled.
"""

import os
from diagrams import Diagram, Cluster, Edge
from diagrams.elastic.elasticsearch import Elasticsearch, Kibana
from diagrams.elastic.agent import Fleet, Agent
from diagrams.onprem.gitops import Argocd
from diagrams.onprem.network import Istio
from diagrams.onprem.monitoring import Prometheus
from diagrams.generic.network import Firewall
from diagrams.custom import Custom

# Resolve paths relative to this script
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
OUTPUT_DIR = os.path.join(SCRIPT_DIR, "..", "output")
ICON_DIR = os.path.join(SCRIPT_DIR, "icons")
os.makedirs(OUTPUT_DIR, exist_ok=True)

graph_attr = {
    "fontsize": "20",
    "pad": "0.5",
    "bgcolor": "white",
    "nodesep": "0.8",
    "ranksep": "1.0",
}

with Diagram(
    "Network Policies — ECK 2026",
    filename=os.path.join(OUTPUT_DIR, "network_policies"),
    outformat="png",
    show=False,
    direction="TB",
    graph_attr=graph_attr,
):
    with Cluster("elastic namespace\n(default-deny-ingress)"):
        es_a = Elasticsearch("ES Node A\n:9200")
        es_b = Elasticsearch("ES Node B\n:9200")
        kibana = Kibana("Kibana\n:5601")
        fleet = Fleet("Fleet Server\n:8220")
        agent = Agent("Elastic Agent")

    with Cluster("elastic-system namespace"):
        eck_op = Elasticsearch("ECK Operator")

    with Cluster("istio-system namespace\n(default-deny-ingress)"):
        prom = Prometheus("Prometheus\n:9090")
        kiali = Custom("Kiali\n:20001", os.path.join(ICON_DIR, "kiali.png"))

    with Cluster("keycloak namespace\n(default-deny-ingress)"):
        keycloak_a = Custom("Keycloak A\n:8443", os.path.join(ICON_DIR, "keycloak.png"))
        keycloak_b = Custom("Keycloak B\n:8443", os.path.join(ICON_DIR, "keycloak.png"))

    with Cluster("argocd namespace\n(default-deny-ingress)"):
        argocd = Argocd("ArgoCD")

    # Allowed traffic in elastic namespace
    kibana >> Edge(
        label=":9200", color="green", style="bold"
    ) >> es_a

    agent >> Edge(
        label=":8220", color="green", style="bold"
    ) >> fleet

    fleet >> Edge(
        label=":9200", color="green", style="bold"
    ) >> es_a

    agent >> Edge(
        label=":9200", color="green", style="bold"
    ) >> es_a

    # ES inter-node transport traffic
    es_a >> Edge(
        label=":9300\n(transport)", color="blue", style="bold"
    ) >> es_b

    es_b >> Edge(
        label=":9300\n(transport)", color="blue", style="bold"
    ) >> es_a

    # Cross-namespace allowed traffic
    eck_op >> Edge(
        label=":9200, :5601", color="orange", style="bold"
    ) >> es_a

    prom >> Edge(
        label=":15020, :15090\n(sidecar scrape)", color="orange", style="bold"
    ) >> kibana

    # Kiali queries Prometheus for service mesh telemetry
    kiali >> Edge(
        label=":9090\n(telemetry)", color="green", style="bold"
    ) >> prom

    # Keycloak connections — OIDC authentication
    kibana >> Edge(
        label=":8443\n(OIDC)", color="purple", style="bold"
    ) >> keycloak_a

    es_a >> Edge(
        label=":8443\n(token validation)", color="purple", style="bold"
    ) >> keycloak_a

    argocd >> Edge(
        label=":8443\n(OIDC)", color="purple", style="bold"
    ) >> keycloak_a

    # Keycloak inter-pod discovery
    keycloak_a >> Edge(
        label=":7800\n(discovery)", color="blue", style="bold"
    ) >> keycloak_b

    keycloak_b >> Edge(
        label=":7800\n(discovery)", color="blue", style="bold"
    ) >> keycloak_a
