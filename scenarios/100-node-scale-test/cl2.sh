#!/usr/bin/env bash
set -xeo pipefail
. ../common.sh
init

SKIP_CT="skip-ct" wait_cilium_ready

. ./vars.sh

cl2="$ARTIFACTS/perf-tests/clusterloader2"
report_dir="$ARTIFACTS/report-$(date +%s)"
config="$(pwd)/config.yaml"

if ! [ -d "$cl2" ]
then
  git clone https://github.com/learnitall/perf-tests $ARTIFACTS/perf-tests \
    -b pr/learnitall/add-arbitrary-pprof-measurement
fi

cd $cl2
cat $config > ./testing/load/config.yaml

mkdir -p $report_dir

export CL2_PROMETHEUS_PVC_ENABLED=false
export CL2_ENABLE_PVS=false
export CL2_ENABLE_NETWORKPOLICIES=true
export CL2_ALLOWED_SLOW_API_CALLS=1

go run ./cmd/clusterloader.go \
  -v=4 \
  --provider $CL2_PROVIDER \
  --testconfig ./testing/load/config.yaml \
  --enable-prometheus-server \
  --tear-down-prometheus-server=false \
  --report-dir=$report_dir \
  --kubeconfig=$HOME/.kube/config \
  --experimental-prometheus-snapshot-to-report-dir=true \
  --testoverrides=./testing/overrides/load_throughput.yaml \
  --testoverrides=./testing/experiments/use_simple_latency_query.yaml 2>&1 | \
  tee -a $report_dir/run.log
