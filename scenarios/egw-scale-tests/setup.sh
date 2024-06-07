#!/usr/bin/env bash
set -xeo pipefail

. ../common.sh
init

cluster_name="egw-scale-test"

if [ ! -f $ARTIFACTS/cilium ]
then
    pushd $ARTIFACTS
    $SCRIPT/get_ciliumcli.sh
    popd
fi

if ! kind get clusters | grep -i $cluster_name
then
    kind create cluster --config ./kind.yaml
fi

if ! helm list -n kube-system | grep -i cilium
then
    api_server_address=$($SCRIPT/get_node_internal_ip.sh "${cluster_name}-control-plane")
    pod_cidr=$($SCRIPT/get_cluster_cidr.sh)
    $ARTIFACTS/cilium install \
        --version v1.15.5 \
        --set k8sServiceHost=${api_server_address} \
        --set ipv4NativeRoutingCIDR=${pod_cidr} \
        -f ./cilium.yaml
fi

$SCRIPT/retry.sh 3 \
    $ARTIFACTS/toolkit verify k8s-ready --ignored-nodes "${cluster_name}-worker"
$ARTIFACTS/cilium status --wait --wait-duration=1m

pushd ./components
docker build . -t quay.io/cilium-dev/egw-scale-test:latest
kind load docker-image quay.io/cilium-dev/egw-scale-test:latest --name egw-scale-test

