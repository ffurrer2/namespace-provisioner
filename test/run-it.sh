#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail

readonly DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

readonly KUBE_CONTEXT=kind-kind

# This is the test namespace
readonly NAMESPACE=test-namespace

# This is where the operator is deployed
readonly OP_NAMESPACE=default

clean() {
  echo "start clean"

  # Delete config and secret file
  rm -f config kube-config-secret.yaml

  # Delete the ${NAMESPACE} namespace
  kubectl --context="${KUBE_CONTEXT}" delete namespace "${NAMESPACE}" --now --ignore-not-found
  result=$(kubectl --context="${KUBE_CONTEXT}" get namespace "${NAMESPACE}" --no-headers --ignore-not-found | wc -l)
  while [[ $result -gt 0 ]]; do
    result=$(kubectl --context="${KUBE_CONTEXT}" get namespace "${NAMESPACE}" --no-headers --ignore-not-found | wc -l)
    printf "."
    sleep 1
  done

  # Delete the namespace-provisioner deployment
  kubectl --context="${KUBE_CONTEXT}" --namespace="${OP_NAMESPACE}" delete deployment namespace-provisioner-deployment --ignore-not-found

  # Delete the namespace-provisioning-networkpolicy ConfigMap
  kubectl --context="${KUBE_CONTEXT}" --namespace="${OP_NAMESPACE}" delete configmap namespace-provisioning-networkpolicy --ignore-not-found

  echo "end clean"
}

prepare() {
  echo "start prepare"

  docker images

  # Get the kubernetes config file to access your tenant and replace server url
  kubectl config view --raw --minify=true --flatten=true | sed "s/server:.*/server: https:\/\/kubernetes.default.svc/g" > config

  # Create secret deployment file for kube-config
  kubectl create secret generic kube-config --from-file=config --dry-run -oyaml > kube-config-secret.yaml

  # Deploy the secret
  kubectl apply -f kube-config-secret.yaml

  # Deploy the namespace-provisioner
  kubectl --context="${KUBE_CONTEXT}" --namespace="${OP_NAMESPACE}" create -f "${DIR}/../deploy/namespace-provisioner-${KUBE_CONTEXT}.yaml"

  # Deploy the namespace-provisioning-networkpolicy ConfigMap
  kubectl --context="${KUBE_CONTEXT}" --namespace="${OP_NAMESPACE}" create configmap namespace-provisioning-networkpolicy --from-file="${DIR}/deploy/namespace-provisioning-networkpolicy.yaml"

  sleep 10

  kubectl get pods -n kube-system
  kubectl get pods -n test-namespace
  kubectl get pods -n default
  kubectl cluster-info

  echo "end prepare"
}

test_deployment() {
  echo "start test_deployment"

  # Check that namespace-provisioner is installed
  kubectl --context="${KUBE_CONTEXT}" --namespace="${OP_NAMESPACE}" get pod --selector='name=namespace-provisioner'

  # Check that ConfigMap is installed
  kubectl --context="${KUBE_CONTEXT}" --namespace="${OP_NAMESPACE}" get configmap namespace-provisioning-networkpolicy -o yaml

  # Create a new namespace
  kubectl --context="${KUBE_CONTEXT}" create ns "${NAMESPACE}"

  # Add annotation to namespace --> namespace-provisioner deploys all ConfigMaps
  kubectl --context="${KUBE_CONTEXT}" annotate ns "${NAMESPACE}" namespace-provisioner.daimler-tss.com/config=namespace-provisioning-networkpolicy
  sleep 10

  # Check if network policies are deployed
  kubectl --context="${KUBE_CONTEXT}" --namespace="${NAMESPACE}" get netpol

  if [[ $(kubectl --context="${KUBE_CONTEXT}" --namespace="${NAMESPACE}" get netpol | grep -c 'kube-system.app.prometheus-allow-all') -ne 1 ]]; then
    echo "!!! test failed !!!"
    exit 1
  fi

  echo "end test_deployment"
}

clean

prepare

test_deployment
