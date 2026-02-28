"""
AWS Infrastructure Architecture Diagram for ECK 2026 Project.

Generates a PNG showing the full AWS infrastructure:
VPC, subnets, NAT, EKS, ALB, Route53, ACM, S3 state, IRSA.
"""

import os
from diagrams import Diagram, Cluster, Edge
from diagrams.aws.network import VPC, ALB, NATGateway, Route53, InternetGateway
from diagrams.aws.compute import EKS
from diagrams.aws.security import ACM, IAMRole
from diagrams.aws.storage import EBS, S3
from diagrams.aws.general import Users

# Resolve paths relative to this script
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
OUTPUT_DIR = os.path.join(SCRIPT_DIR, "..", "output")
os.makedirs(OUTPUT_DIR, exist_ok=True)

graph_attr = {
    "fontsize": "20",
    "pad": "0.5",
    "bgcolor": "white",
    "compound": "true",
}

with Diagram(
    "AWS Infrastructure — ECK 2026",
    filename=os.path.join(OUTPUT_DIR, "aws_architecture"),
    outformat="png",
    show=False,
    direction="TB",
    graph_attr=graph_attr,
):
    users = Users("Users\n(Browser)")
    dns = Route53("Route53\nhermanwong.io")
    acm = ACM("ACM\n*.hermanwong.io")
    s3 = S3("S3\nTerraform State")
    irsa = IAMRole("IRSA Roles\n(LB Controller,\nExternal DNS,\nEBS CSI)")

    users >> Edge(label="HTTPS") >> dns

    with Cluster("VPC — 10.0.0.0/16"):
        with Cluster("Public Subnets\n10.0.100.0/24, 10.0.101.0/24"):
            alb = ALB("ALB\n(internet-facing)")
            nat = NATGateway("NAT Gateway\n(single, ~$1/day)")

        dns >> alb
        acm - Edge(style="dashed", label="TLS cert") - alb

        with Cluster("Private Subnets\n10.0.0.0/24, 10.0.1.0/24"):
            with Cluster("EKS Cluster v1.33"):
                node1 = EKS("SPOT Node 1\nm5.xlarge")
                node2 = EKS("SPOT Node 2\nm5.xlarge")
                ebs1 = EBS("gp3\nVolumes")

            alb >> Edge(label="→ ArgoCD, Kibana, Keycloak, Kiali") >> node1
            alb >> node2
            node1 - ebs1
            node2 - ebs1

        [node1, node2] >> Edge(label="image pulls,\noutbound") >> nat
