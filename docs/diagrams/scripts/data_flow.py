"""
Observability Data Flow Diagram for ECK 2026 Project.

Shows how metrics and logs flow from K8s nodes through
Elastic Agent -> Fleet Server -> Elasticsearch -> Kibana,
and the parallel Istio -> Prometheus -> Kiali path.
"""

import os
from diagrams import Diagram, Cluster, Edge
from diagrams.elastic.elasticsearch import Elasticsearch, Kibana
from diagrams.elastic.agent import Fleet, Agent
from diagrams.onprem.network import Istio
from diagrams.onprem.monitoring import Prometheus
from diagrams.k8s.compute import Pod
from diagrams.k8s.infra import Node
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
    "Observability Data Flow — ECK 2026",
    filename=os.path.join(OUTPUT_DIR, "data_flow"),
    outformat="png",
    show=False,
    direction="LR",
    graph_attr=graph_attr,
):
    # Data sources
    with Cluster("EKS Worker Nodes"):
        node1 = Node("Node 1")
        node2 = Node("Node 2")
        pods = Pod("Application\nPods")

    # Elastic pipeline
    with Cluster("Elastic Observability Pipeline"):
        agent = Agent("Elastic Agent\n(DaemonSet)\nhostNetwork: true\nno Istio sidecar")
        fleet = Fleet("Fleet Server\n:8220")
        es = Elasticsearch("Elasticsearch\n:9200\n(data streams:\nlogs-*, metrics-*)")
        kibana = Kibana("Kibana\n:5601\nK8s Overview\nDashboard")

        agent >> Edge(label="enrollment\n+ ship data") >> fleet
        fleet >> Edge(label="index") >> es
        agent >> Edge(label="direct ingest") >> es
        es >> Edge(label="query") >> kibana

    # Collection
    [node1, node2] >> Edge(label="container logs,\nkubelet metrics,\nsystem metrics") >> agent

    # Istio pipeline (parallel path)
    with Cluster("Istio Observability Pipeline"):
        sidecars = Istio("Envoy Sidecars\n(:15020/:15090)")
        prom = Prometheus("Prometheus\n(scrape)")
        kiali = Custom("Kiali\n(service mesh\ntopology)", os.path.join(ICON_DIR, "kiali.png"))

        sidecars >> Edge(label="metrics") >> prom
        prom >> Edge(label="query") >> kiali

    pods >> Edge(label="L7 traffic\nthrough sidecars") >> sidecars
