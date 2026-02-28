"""
ArgoCD GitOps Sync Waves Diagram for ECK 2026 Project.

Shows the deployment ordering: 7 sync waves from cert-manager
through network policies, with ArgoCD orchestrating from GitHub.
"""

import os
from diagrams import Diagram, Cluster, Edge
from diagrams.onprem.gitops import Argocd
from diagrams.onprem.vcs import Github
from diagrams.onprem.certificates import CertManager
from diagrams.onprem.network import Istio
from diagrams.onprem.monitoring import Prometheus
from diagrams.elastic.elasticsearch import Elasticsearch, Kibana
from diagrams.elastic.agent import Fleet, Agent
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
    "nodesep": "0.6",
    "ranksep": "0.8",
}

with Diagram(
    "ArgoCD Sync Wave Deployment Order — ECK 2026",
    filename=os.path.join(OUTPUT_DIR, "gitops_sync_waves"),
    outformat="png",
    show=False,
    direction="TB",
    graph_attr=graph_attr,
):
    github = Github("GitHub Repo\n(main branch)")
    argocd = Argocd("ArgoCD\n(App of Apps)")

    github >> Edge(label="git sync") >> argocd

    with Cluster("Wave 1 — TLS Foundation"):
        cm = CertManager("cert-manager")

    with Cluster("Wave 2 — Issuers + Service Mesh Base"):
        ca = CertManager("CA +\nClusterIssuers")
        istio_base = Istio("Istio Base\n(CRDs)")

    with Cluster("Wave 3 — Control Planes + Certs"):
        istiod = Istio("istiod")
        prom = Prometheus("Prometheus")
        kiali = Custom("Kiali", os.path.join(ICON_DIR, "kiali.png"))
        tls = CertManager("TLS\nCertificates")

    with Cluster("Wave 4 — Operators"):
        eck_op = Elasticsearch("ECK\nOperator")

    with Cluster("Wave 5 — Core Applications"):
        es = Elasticsearch("Elasticsearch")
        kibana = Kibana("Kibana")
        ksm = Prometheus("kube-state\n-metrics")

    with Cluster("Wave 6 — Identity + Monitoring"):
        keycloak = Custom("Keycloak", os.path.join(ICON_DIR, "keycloak.png"))
        fleet = Fleet("Fleet Server")
        agent = Agent("Elastic Agent")

    with Cluster("Wave 7 — Security Policies"):
        netpol = Firewall("Network\nPolicies\n(default-deny)")

    # Deployment order arrows
    argocd >> cm
    cm >> Edge(label="then") >> ca
    cm >> Edge(label="then") >> istio_base
    [ca, istio_base] >> Edge(label="then") >> istiod
    istiod >> Edge(label="then") >> eck_op
    eck_op >> Edge(label="then") >> es
    es >> Edge(label="then") >> keycloak
    keycloak >> Edge(label="then") >> netpol
