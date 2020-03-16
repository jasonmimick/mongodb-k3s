#!/bin/bash

set -u
. ./clusters/k3sup-gce.sh up
kubectl create ns mongodb
helm install -n mongodb mongodb .

