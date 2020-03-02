#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail

readonly DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

readonly KUBE_CONTEXT=kind-kind

# This is the test namespace
readonly NAMESPACE=test-namespace

# This is where the operator is deployed
 readonly OP_NAMESPACE=operator-namespace

prepare() {
  #docker pull docker.pkg.github.com/daimler/namespace-provisioner/namespace-provisioner:latest
  #task -d $DIR/.. docker:build

  # Delete config and secret file
  rm -f config kube-config-secret.yaml

  # Delete the ${NAMESPACE} namespace
  kubectl delete namespace "${NAMESPACE}" --context="${KUBE_CONTEXT}" --now --ignore-not-found --wait

  # Delete the ${OP_NAMESPACE} namespace
  kubectl delete namespace "${OP_NAMESPACE}" --context="${KUBE_CONTEXT}" --now --ignore-not-found --wait

  # Create a new operator namespace
  kubectl create namespace "${OP_NAMESPACE}" --context=${KUBE_CONTEXT}

  # Get the kubernetes config file to access your tenant and replace server url
  kubectl config view --raw --minify=true --flatten=true --context="${KUBE_CONTEXT}" --namespace="${OP_NAMESPACE}" | sed 's/server:.*/server: https:\/\/kubernetes.default.svc/g' > config

  # Create secret deployment file for kube-config
  kubectl create secret generic kube-config --from-file=config --dry-run -oyaml --context="${KUBE_CONTEXT}" --namespace="${OP_NAMESPACE}" > kube-config-secret.yaml

  # Deploy the secret
  kubectl apply -f kube-config-secret.yaml --wait --context="${KUBE_CONTEXT}" --namespace="${OP_NAMESPACE}"

  # Deploy the namespace-provisioner
  kubectl create -f "${DIR}/../deploy/namespace-provisioner-${KUBE_CONTEXT}.yaml" --context="${KUBE_CONTEXT}" --namespace="${OP_NAMESPACE}"

  # Deploy the namespace-provisioning-networkpolicy ConfigMap
  kubectl create configmap namespace-provisioning-networkpolicy --from-file="${DIR}/deploy/namespace-provisioning-networkpolicy.yaml" --context="${KUBE_CONTEXT}" --namespace="${OP_NAMESPACE}"
}

test() {
  # Check that namespace-provisioner is installed
  kubectl get pod --selector='name=namespace-provisioner' --context="${KUBE_CONTEXT}" --namespace="${OP_NAMESPACE}"

  # Check that ConfigMap is installed
  kubectl get configmap namespace-provisioning-networkpolicy -o yaml --context="${KUBE_CONTEXT}" --namespace="${OP_NAMESPACE}"

  # Create a new namespace
  kubectl create namespace "${NAMESPACE}" --context="${KUBE_CONTEXT}"

  # Add annotation to namespace --> namespace-provisioner deploys all ConfigMaps
  kubectl annotate namespace "${NAMESPACE}" namespace-provisioner.daimler-tss.com/config=namespace-provisioning-networkpolicy --context="${KUBE_CONTEXT}"
  sleep 3

  # Check if network policies are deployed
  kubectl get netpol --context="${KUBE_CONTEXT}" --namespace="${NAMESPACE}"

  if [[ $(kubectl --context="${KUBE_CONTEXT}" --namespace="${NAMESPACE}" get netpol | grep -c 'kube-system.app.prometheus-allow-all') -ne 1 ]]; then
    echo "!!! test failed !!!"
  fi

  # Delete config and secret file
  rm -f config kube-config-secret.yaml

  # Delete the ${NAMESPACE} namespace
  kubectl delete namespace "${NAMESPACE}" --context="${KUBE_CONTEXT}" --now --ignore-not-found

  # Delete the ${OP_NAMESPACE} namespace
  kubectl delete namespace "${OP_NAMESPACE}" --context="${KUBE_CONTEXT}" --now --ignore-not-found
}

prepare
test
