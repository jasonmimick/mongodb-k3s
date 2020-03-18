#!/bin/bash

set -u

ORG="mongodb-k3s"
NEW_TAG=$( curl -s https://frightanic.com/goodies_content/docker-names.php | tr '_' '-' )
NEW_CLUSTER_TAG="${ORG}-${NEW_TAG}"

CLUSTER_TAG=${CLUSTER_TAG:-${NEW_CLUSTER_TAG}}

echo "Installing MongoDB Enterprise Data Services Cluster"
echo "Powered by Google Compute Engine"
echo "mongodb-k3s sandbox demonstration kit"
echo "For research & development purposes only."
echo "Settings:"
INSTANCE_TYPE=${WORKER_INSTANCE_TYPE:-n1-standard-1}
OPS_MANAGER_INSTANCE_TYPE=${MANAGER_INSTANCE_TYPE:-n1-standard-8}
ZONE=${ZONE:-us-central1-b}
ZONE_DR=${ZONE_DR:-us-central1-c}
MMS_NODES_TAG="${CLUSTER_TAG}-ops-manager"

echo "CLUSTER_TAG=${CLUSTER_TAG}"
echo "ZONE=${ZONE}"
echo "ZONE_DR=${ZONE_DR}"
echo "INSTANCE_TYPE=${INSTANCE_TYPE}"
echo "OPS_MANAGER_INSTANCE_TYPE=${OPS_MANAGER_INSTANCE_TYPE}"
echo "MMS_NODES_TAG=${MMS_NODES_TAG}"

up() {
    (
    set -x
    gcloud compute instances create "${CLUSTER_TAG}-master" \
        --machine-type "${INSTANCE_TYPE}" \
        --zone "${ZONE}" \
        --tags "${ORG}","${CLUSTER_TAG}","${CLUSTER_TAG}-master"

    gcloud compute instances create \
        "${CLUSTER_TAG}-worker-0" "${CLUSTER_TAG}-worker-1" "${CLUSTER_TAG}-worker-2" \
        --machine-type "${INSTANCE_TYPE}" \
        --zone "${ZONE}" \
        --tags "${ORG}","${CLUSTER_TAG}","${CLUSTER_TAG}-worker" 

    gcloud compute instances create "${MMS_NODES_TAG}-0" \
        --machine-type "${OPS_MANAGER_INSTANCE_TYPE}" \
        --zone "${ZONE}" \
        --tags "${ORG}","${CLUSTER_TAG}","${MMS_NODES_TAG}","${MMS_NODES_TAG}-${ZONE}"

    gcloud compute instances create "${MMS_NODES_TAG}-1" \
        --machine-type "${OPS_MANAGER_INSTANCE_TYPE}" \
        --zone "${ZONE}" \
        --tags "${ORG}","${CLUSTER_TAG}","${MMS_NODES_TAG}","${MMS_NODES_TAG}-${ZONE}"

    gcloud compute instances create "${MMS_NODES_TAG}-2" \
        --machine-type "${OPS_MANAGER_INSTANCE_TYPE}" \
        --zone "${ZONE_DR}" \
        --tags "${ORG}","${CLUSTER_TAG}","${MMS_NODES_TAG}","${MMS_NODES_TAG}-${ZONE_DR}"

    gcloud compute config-ssh
    )

    primary_server_ip=$(gcloud compute instances list \
    --filter=tags.items="${CLUSTER_TAG}-master" \
    --format="get(networkInterfaces[0].accessConfigs.natIP)")

    (
    set -x
    k3sup install --ip "${primary_server_ip}" \
                  --context "${CLUSTER_TAG}" \
                  --ssh-key ~/.ssh/google_compute_engine \
                  --user $(whoami)

    gcloud compute firewall-rules create "${CLUSTER_TAG}" \
                  --allow=tcp:6443 \
                  --target-tags="${CLUSTER_TAG}"

    gcloud compute instances list \
        --filter=tags.items="${CLUSTER_TAG}-worker" \
        --format="get(networkInterfaces[0].accessConfigs.natIP)" | \
            xargs -L1 k3sup join \
            --server-ip $primary_server_ip \
            --ssh-key ~/.ssh/google_compute_engine \
            --user $(whoami) \
            --ip

    gcloud compute instances list \
        --filter=tags.items="${MMS_NODES_TAG}" \
        --format="get(networkInterfaces[0].accessConfigs.natIP)" | \
            xargs -L1 k3sup join \
            --server-ip $primary_server_ip \
            --ssh-key ~/.ssh/google_compute_engine \
            --user $(whoami) \
            --ip
    )

    export KUBECONFIG=`pwd`/kubeconfig
    kubectl get nodes
    kubectl label node ${MMS_NODES_TAG}-{0,1,2} kubernetes.io/role=mongodb-ops-manager
    kubectl label node ${CLUSTER_TAG}-worker-{0,1,2} kubernetes.io/role=mongodb-node

}

down() {
    CLUSTER_TAG="${1}"
    MMS_NODES_TAG="${CLUSTER_TAG}-ops-manager"
    (
    set -x
    gcloud compute instances list \
        --filter=tags.items="${CLUSTER_TAG}-worker" --format="get(name)" | \
            xargs gcloud compute instances delete \
              --zone "${ZONE}" -q --delete-disks all 
    gcloud compute instances list \
        --filter=tags.items="${MMS_NODES_TAG}-${ZONE}" --format="get(name)" | \
            xargs gcloud compute instances delete \
              --zone "${ZONE}" -q --delete-disks all 
    gcloud compute instances list \
        --filter=tags.items="${MMS_NODES_TAG}-${ZONE_DR}" --format="get(name)" | \
            xargs gcloud compute instances delete \
              --zone "${ZONE_DR}" -q --delete-disks all 
    gcloud compute instances list \
        --filter=tags.items="${CLUSTER_TAG}-master" --format="get(name)" | \
            xargs gcloud compute instances delete \
              --zone "${ZONE}" -q --delete-disks all 

    gcloud compute firewall-rules delete "${CLUSTER_TAG}" -q
    )
}

list() {
    (
    set -x
    gcloud compute instances list \
        --filter=tags.items="${ORG}"
    )
}

usage() {
    echo "Bootstrap or tear down a mongodb-k8s cluster running k3s on GCE"
    echo "k3sup-gcp up"
    echo "   Provisions k3s cluster. Sets CLUSTER_TAG env variable. " 
    echo ""
    echo "k3sup down <CLUSTER_TAG>"
    echo "   Tears down cluster, requires CLUSTER_TAG argument."
}

case "${1:-usage}" in
  list)
    shift
    list "$@"
    ;;
  up)
    shift
    up "$@"
    ;;
  down)
    shift
    down "$@"
    ;;
  *)
    usage
    exit 1
    ;;
esac
