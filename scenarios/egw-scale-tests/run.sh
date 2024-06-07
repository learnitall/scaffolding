#!/usr/bin/env bash
set -xeo pipefail

. ../common.sh
init

cluster_name="egw-scale-test"

# typ is the type of test to run.
# Can be one of "masq-delay-baseline" or "masq-delay"
typ=$1
N=$2

get_node_ip() {
    role=$1

    kubectl get nodes \
        -l role.scaffolding==$role \
        -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}'
}

# Cleanup previous run, if needed
kubectl delete deploy/egw-metrics-server || true
kubectl delete deploy/egw-external-target || true
kubectl delete job/egw-client || true
kubectl delete cegp/egw-scale-test-route-external || true

# Create the cluster and start infra.
./setup.sh

kubectl apply -f ./manifests/debug-netshoot.yaml

external_target_ip=$(get_node_ip external)
egw_ip=$(get_node_ip egw)

if [ "${typ}" == masq-delay-baseline ]; then
  allowed_cidr="0.0.0.0/0"
else
  allowed_cidr="${egw_ip}/32"
fi

cat ./manifests/external-target.yaml | \
    ALLOWED_CIDR="$allowed_cidr" envsubst | \
    kubectl apply -f - 

kubectl apply -f ./manifests/metrics-server.yaml

$SCRIPT/retry.sh 3 \
    $ARTIFACTS/toolkit verify k8s-ready --ignored-nodes "${cluster_name}-worker"

if [ "${typ}" == masq-delay ]; then
  cat ./manifests/egw.yaml | \
    EXTERNAL_TARGET_CIDR="${external_target_ip}/32" envsubst | \
    kubectl apply -f -

    # Wait 10 seconds for the policy to apply
    # TODO check programatically if policy is applied
    sleep 10
fi


# Run the test
cat ./manifests/client.yaml | \
    EXTERNAL_TARGET="${external_target_ip}:1337" N=$N envsubst | \
    kubectl apply -f -

while kubectl get jobs | grep egw-client; do
    sleep 1
done

# Grab metrics
kubectl exec egw-debug -- curl metrics-server-svc.default.svc.cluster.local:2112/metrics > \
    $ARTIFACTS/$typ-$N-metrics.txt

