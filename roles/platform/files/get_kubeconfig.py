#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Create kubeconfig from output of `google.cloud.gcp_container_cluster`

Use `google-auth` module to get an OAuth bearer token for the given
service account, which can then be passed to kubectl in order to
authenticate to the cluster.

References:
* https://kubernetes.io/docs/reference/access-authn-authz/authentication/#client-go-credential-plugins
* https://github.com/mie00/gke-kubeconfig
* https://google-auth.readthedocs.io/en/master/user-guide.html

Requires `google-auth` and `requests` to be installed.
"""
import argparse
import base64
import json
import logging
import os
import shlex
import subprocess
import sys
import typing as t

from google.auth.transport.requests import Request
from google.oauth2 import service_account

KUBECONFIG_TEMPLATE = """
apiVersion: v1
kind: Config
clusters:
- name: gke_{cluster_name}
  cluster:
    server: https://{cluster_server}
    certificate-authority-data: {cluster_ca}
users:
- name: my-gke-sa-user
  user:
    token: {user_token}
contexts:
- context:
    cluster: gke_{cluster_name}
    user: my-gke-sa-user
  name: gke_{cluster_project}_{cluster_zone}_{cluster_name}
current-context: gke_{cluster_project}_{cluster_zone}_{cluster_name}
"""
GOOGLE_AUTH_API_BASE = "https://www.googleapis.com/auth/"
SA_MANIFEST = """
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: perfci-sa-admin
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: perfci-sa-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: perfci-sa-admin
    namespace: kube-system

"""


def get_google_sa_token(path_to_sa: str) -> str:
    """Use given service account private key to get token for k8s api server."""

    credentials = service_account.Credentials.from_service_account_file(
        path_to_sa,
        scopes=[
            GOOGLE_AUTH_API_BASE + scope
            for scope in (
                "userinfo.email",
                "cloud-platform",
                "compute",
                "appengine.admin",
            )
        ],
    )
    credentials.refresh(Request())
    return credentials.token


def build_kubeconfig(
    kubeconfig_template: str,
    cluster_server: str,
    cluster_name: str,
    cluster_ca: str,
    cluster_zone: str,
    cluster_project: str,
    user_token: str,
) -> str:
    """Use the given arguments to build a kubeconfig."""

    return kubeconfig_template.format(
        cluster_name=cluster_name,
        cluster_server=cluster_server,
        cluster_ca=cluster_ca,
        cluster_zone=cluster_zone,
        cluster_project=cluster_project,
        user_token=user_token,
    )


def get_kubeconfig_params_from_gcp_container_cluster_json(
    gcp_container_cluster_json: str,
) -> t.Dict[str, str]:
    """Get params for `build_kubeconfig` from `gcp_container_cluster` results."""

    results = json.loads(gcp_container_cluster_json)
    return {
        "cluster_ca": results["masterAuth"]["clusterCaCertificate"],
        "cluster_name": results["name"],
        "cluster_server": results["endpoint"],
        "cluster_zone": results["zone"],
    }


def run_kubectl_command(cmd: str, stdin: t.Optional[str] = None) -> str:
    """Run the given kubectl command, assuming `set_kubeconfig`."""

    cmd = "kubectl " + cmd
    logging.info("Running '%s'", cmd)
    try:
        result = subprocess.run(
            shlex.split(cmd),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            input=stdin,
            env=os.environ,
            timeout=20,
            check=True,
            text=True,
        )
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as err:
        logging.warning(
            "Got error while running kubectl command '%s': %s, %s",
            cmd,
            err,
            err.stdout,
        )
        raise

    logging.info("Result: %s", result.stdout)
    return result.stdout


def generate_kubeconfig(
    gke_ansible_json: str, kubeconfig_dest: str, token: str, project: str
) -> None:
    """Generate kubeconfig for ansible-provisioned cluster"""

    logging.info(
        "Parsing through gcp_container_cluster json: %s",
        gke_ansible_json,
    )
    with open(gke_ansible_json, "r") as gke_ansible_json_file_handler:
        gke_ansible_json = gke_ansible_json_file_handler.read()
    kubeconfig_args = get_kubeconfig_params_from_gcp_container_cluster_json(
        gke_ansible_json
    )

    kubeconfig_args["user_token"] = token
    kubeconfig_args["cluster_project"] = project
    kubeconfig = build_kubeconfig(KUBECONFIG_TEMPLATE, **kubeconfig_args)
    with open(kubeconfig_dest, "w") as kubeconfig_file_handler:
        kubeconfig_file_handler.write(kubeconfig)
    logging.info("Kubeconfig written to %s", kubeconfig_dest)

    os.environ["KUBECONFIG"] = kubeconfig_dest
    run_kubectl_command("config view")
    run_kubectl_command("get nodes")


def create_k8s_sa() -> str:
    """Create cluster admin SA in k8s"""

    run_kubectl_command("apply -f -", stdin=SA_MANIFEST)
    secrets = run_kubectl_command("-n kube-system get secret")
    sa_secret = None
    for secret in secrets.splitlines():
        if secret.startswith("perfci-sa-admin"):
            # Each of these entries is:
            # 'name<w>type<w>data<w>age' where <w> is whitespace
            sa_secret = secret.split(" ")[0].strip()
    if sa_secret is None:
        raise ValueError("Unable to find service account secret for 'perfci-sa-admin")
    token_b64 = run_kubectl_command(
        f"-n kube-system get secret {sa_secret} -o jsonpath={{.data.token}}"
    )
    token = base64.b64decode(token_b64).decode("utf-8")
    return token


def setup_logging() -> None:
    """Configure global console logging."""

    logging.basicConfig(
        format="%(asctime)s - %(levelname)s: %(message)s",
        level=logging.INFO,
        stream=sys.stdout,
    )


def create_argument_parser() -> argparse.ArgumentParser:
    """Create argument parser for the script."""

    parser = argparse.ArgumentParser()
    parser.add_argument(
        "service_account_file", help="Path to private key of Google IAM service account"
    )
    parser.add_argument(
        "gke_ansible_json",
        help="File path to output of google.cloud.gcp_container_cluster",
    )
    parser.add_argument("kubeconfig_dest", help="Destination of kubeconfig")
    parser.add_argument(
        "gke_project",
        help="Project where gke cluster is deployed",
    )

    return parser


def main() -> None:

    parser = create_argument_parser()
    args = parser.parse_args()

    setup_logging()

    kubeconfig_args = {
        "gke_ansible_json": args.gke_ansible_json,
        "kubeconfig_dest": args.kubeconfig_dest,
        "project": args.gke_project
    }

    logging.info("Getting token for gcp sa authentication")
    gcp_token = get_google_sa_token(args.service_account_file)
    generate_kubeconfig(token=gcp_token, **kubeconfig_args)
    sa_token = create_k8s_sa()
    generate_kubeconfig(token=sa_token, **kubeconfig_args)


if __name__ == "__main__":
    main()
