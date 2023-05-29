#!/usr/bin/env bash
set -xo pipefail

. ./vars.sh

# Create cluster with N nodes, then add a larger node for prometheus.
# We start with N nodes so the control plane is scaled properly
# off the bat. See https://cloud.google.com/kubernetes-engine/docs/how-to/node-pools
#
# Additionally, we'll make this private so we can save on public
# IP usage and avoid routing traffic through the internet. See
# https://cloud.google.com/kubernetes-engine/docs/how-to/private-clusters#all_access
#
# In order to create a private cluster, we need to configure NAT, as nodes will
# not have access to the internet by default.
# NAT example: https://cloud.google.com/nat/docs/gke-example#gcloud
#
# Additionally, we need to create a firewall rule that allows control plane nodes
# access to the cluster on port 9090. This is to allow clusterloader2 to use the
# k8s apiserver proxy to query prometheus' status.
region=$(gcloud config get compute/region)
project=$(gcloud config get project)

if [  "${1}" == "clean" ]
then
  gcloud container clusters delete $GKE_CLUSTER_NAME
  gcloud compute routers delete $GKE_ROUTER_NAME
  gcloud compute networks subnets delete $GKE_SUBNET_NAME
  gcloud compute firewall-rules delete allow-cp-proxy-to-prom
  gcloud compute networks delete $GKE_NETWORK_NAME

  exit 0
fi

gcloud compute networks create $GKE_NETWORK_NAME \
  --subnet-mode custom

gcloud compute networks subnets create $GKE_SUBNET_NAME \
  --network $GKE_NETWORK_NAME \
  --region $region \
  --range $GKE_SUBNET_RANGE

gcloud compute routers create $GKE_ROUTER_NAME \
  --network $GKE_NETWORK_NAME \
  --region $region

gcloud compute routers nats create nat-config \
  --router $GKE_ROUTER_NAME \
  --router-region $region \
  --nat-all-subnet-ip-ranges \
  --auto-allocate-nat-external-ips

gcloud compute firewall-rules create allow-cp-proxy-to-prom \
  --network $GKE_NETWORK_NAME \
  --direction INGRESS \
  --source-ranges 172.16.0.0/28 \
  --allow tcp:9090 

gcloud container clusters create \
  $GKE_CLUSTER_NAME \
  --no-enable-master-authorized-networks \
  --network "projects/$project/global/networks/$GKE_NETWORK_NAME" \
  --subnetwork "projects/$project/regions/$region/subnetworks/$GKE_SUBNET_NAME" \
  --enable-ip-alias \
  --enable-private-nodes \
  --master-ipv4-cidr 172.16.0.0/28 \
  --labels "usage=$GKE_DEV_REASON,owner=$GKE_OWNER" \
  --num-nodes="$GKE_N_NODES" \
  --machine-type e2-custom-2-4096 \
  --disk-type pd-standard \
  --disk-size 20GB \
  --node-taints "node.cilium.io/agent-not-ready=true:NoExecute"

gcloud container node-pools create \
  large-pool \
  --cluster $GKE_CLUSTER_NAME \
  --enable-private-nodes \
  --labels "usage=$GKE_DEV_REASON,owner=$GKE_OWNER" \
  --num-nodes 1 \
  --machine-type e2-standard-8 \
  --disk-type pd-standard \
  --disk-size 40GB \
  --node-taints "node.cilium.io/agent-not-ready=true:NoExecute"

# Cluster will go into reconciling state after a bit, wait for this to happen.
while ! gcloud container clusters describe $GKE_CLUSTER_NAME | grep RECONCILING
do
  sleep 10
done

while ! gcloud container clusters describe $GKE_CLUSTER_NAME | grep RUNNING
do
  sleep 10
done

