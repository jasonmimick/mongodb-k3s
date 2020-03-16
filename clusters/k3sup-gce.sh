#!/bin/bash

set -u

#CLUSTER_TAG=mongodb-k3s-${CLUSTER_TAG:-$( mktemp | cut -d'.' -f2 | tr '[:upper:]' '[:lower:]' )}
ORG="mongodb-k3s"
CLUSTER_TAG=${ORG}-${CLUSTER_TAG:-$( curl -s https://frightanic.com/goodies_content/docker-names.php | tr '_' '-' )}
ZONE=${ZONE:-us-central1-b}
echo "Installing MongoDB Enterprise Data Services Cluster"
echo "Powered by Google Compute Engine"
echo "mongodb-k3s sandbox demonstration kit"
echo "For research & development only"
echo "CLUSTER_TAG=${CLUSTER_TAG} ZONE=${ZONE}"

INSTANCE_TYPE=${WORKER_INSTANCE_TYPE:-n1-standard-1}
OPS_MANAGER_INSTANCE_TYPE=${MANAGER_INSTANCE_TYPE:-n1-standard-8}
ZONE=${ZONE:-us-central1-b}

up() {
    (
    set -x
    gcloud compute instances create "${CLUSTER_TAG}-master" \
        --machine-type "${INSTANCE_TYPE}" \
        --zone "${ZONE}" \
        --tags "${ORG}","${CLUSTER_TAG}","${CLUSTER_TAG}-master"

    gcloud compute instances create \
        "${CLUSTER_TAG}-worker-1" "${CLUSTER_TAG}-worker-2" "${CLUSTER_TAG}-worker-3" \
        --machine-type "${INSTANCE_TYPE}" \
        --zone "${ZONE}" \
        --tags "${ORG}","${CLUSTER_TAG}","${CLUSTER_TAG}-worker" 

    gcloud compute instances create "${CLUSTER_TAG}-mongodb-manager" \
        --machine-type "${OPS_MANAGER_INSTANCE_TYPE}" \
        --zone "${ZONE}" \
        --tags "${ORG}","${CLUSTER_TAG}","${CLUSTER_TAG}-ops-manager"

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
        --filter=tags.items="${CLUSTER_TAG}-ops-manager" \
        --format="get(networkInterfaces[0].accessConfigs.natIP)" | \
            xargs -L1 k3sup join \
            --server-ip $primary_server_ip \
            --ssh-key ~/.ssh/google_compute_engine \
            --user $(whoami) \
            --ip

    gcloud compute instances list \
        --filter=tags.items="${CLUSTER_TAG}-worker" \
        --format="get(networkInterfaces[0].accessConfigs.natIP)" | \
            xargs -L1 k3sup join \
            --server-ip $primary_server_ip \
            --ssh-key ~/.ssh/google_compute_engine \
            --user $(whoami) \
            --ip
    )

    export KUBECONFIG=`pwd`/kubeconfig
    kubectl get nodes
}

down() {
    CLUSTER_TAG="${1}"
    (
    set -x
    gcloud compute instances list \
        --filter=tags.items="${CLUSTER_TAG}" --format="get(name)" | \
            xargs gcloud compute instances delete \
              --zone "$ZONE" -q --delete-disks all

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
