#!/usr/bin/env bash
set -xeo pipefail

. ../common.sh
init

. ./vars.sh

if ! [ -f "$ARTIFACTS/cilium" ]
then
  pushd $ARTIFACTS
  $SCRIPT/get_ciliumcli.sh
  popd
fi

$ARTIFACTS/cilium install --version $CILIUM_VERSION \
  --helm-values $CILIUM_VALUES_FILE

SKIP_CT="skip-ct" wait_cilium_ready

