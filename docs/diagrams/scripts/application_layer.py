"""
Application Layer Architecture Diagram for ECK 2026 Project.

Shows how the deployed applications connect to each other:
OIDC SSO flow, data ingestion, GitOps management, service mesh.
"""

import os
from diagrams import Diagram, Cluster, Edge
from diagrams.aws.network import ALB
from diagrams.aws.general import Users
from diagrams.elastic.elasticsearch import Elasticsearch, Kibana
from diagrams.elastic.agent import Fleet, Agent
from diagrams.onprem.gitops import Argocd
from diagrams.onprem.network import Istio
from diagrams.onprem.monitoring import Prometheus
from diagrams.onprem.certificates import CertManager
from diagrams.onprem.vcs import Github
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
    "nodesep": "1.0",
    "ranksep": "1.2",
}

with Diagram(
    "Application Architecture — ECK 2026",
    filename=os.path.join(OUTPUT_DIR, "application_layer"),
    outformat="png",
    show=False,
    direction="LR",
    graph_attr=graph_attr,
):
    users = Users("Users")
    alb = ALB("ALB\n(HTTPS)")

    users >> Edge(label="*.hermanwong.io") >> alb

    with Cluster("Identity"):
        keycloak = Custom(
            "Keycloak\n(eck-2026 realm)",
            os.path.join(ICON_DIR, "keycloak.png"),
        )

    with Cluster("Elastic Stack"):
        kibana = Kibana("Kibana")
        es = Elasticsearch("Elasticsearch\n(2-3 nodes)")
        fleet = Fleet("Fleet Server")
        agent = Agent("Elastic Agent\n(DaemonSet)")

        kibana >> Edge(label=":9200") >> es
        agent >> Edge(label=":8220") >> fleet
        fleet >> Edge(label=":9200") >> es

    with Cluster("Service Mesh"):
        kiali = Custom("Kiali", os.path.join(ICON_DIR, "kiali.png"))
        prom = Prometheus("Prometheus")
        istiod = Istio("istiod")
        kiali >> prom
        prom >> Edge(label="scrape sidecars") >> istiod

    with Cluster("GitOps"):
        argocd = Argocd("ArgoCD")
        github = Github("GitHub")
        github >> argocd

    certmgr = CertManager("cert-manager")

    # ALB routes to user-facing services
    alb >> kibana
    alb >> keycloak
    alb >> kiali
    alb >> argocd

    # OIDC SSO flow (highlighted)
    kibana >> Edge(
        label="OIDC redirect",
        color="darkgreen",
        style="bold",
    ) >> keycloak
    argocd >> Edge(
        label="OIDC redirect",
        color="darkgreen",
        style="bold",
    ) >> keycloak
    es >> Edge(
        label="validate tokens\n+ role mapping",
        color="darkgreen",
        style="bold",
    ) >> keycloak

    # GitOps manages deployments
    argocd >> Edge(style="dashed", label="manages") >> es
    argocd >> Edge(style="dashed") >> keycloak

    # cert-manager provides TLS
    certmgr >> Edge(style="dotted") >> keycloak
    certmgr >> Edge(style="dotted") >> kibana
