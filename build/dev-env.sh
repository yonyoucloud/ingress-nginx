#!/bin/bash

# Copyright 2018 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

if [ -n "$DEBUG" ]; then
	set -x
fi

set -o errexit
set -o nounset
set -o pipefail

DIR=$(cd $(dirname "${BASH_SOURCE}") && pwd -P)

export TAG=0.33.0-dev
export REGISTRY=${REGISTRY:-ingress-controller}

DEV_IMAGE=${REGISTRY}/nginx-ingress-controller:${TAG}

# if ! command -v kind &> /dev/null; then
#   echo "kind is not installed"
#   echo "Use a package manager (i.e 'brew install kind') or visit the official site https://kind.sigs.k8s.io"
#   exit 1
# fi

if ! command -v kubectl &> /dev/null; then
  echo "Please install kubectl 1.15 or higher"
  exit 1
fi

if ! docker buildx version &> /dev/null; then
  echo "Make sure you have Docker 19.03 or higher and experimental features enabled"
  exit 1
fi

if ! command -v helm &> /dev/null; then
  echo "Please install helm"
  exit 1
fi

KUBE_CLIENT_VERSION=$(kubectl version --client --short 2> /dev/null | awk '{if (NR==1){print $3}}' | cut -d. -f2) || true
if [[ ${KUBE_CLIENT_VERSION} -lt 14 ]]; then
  echo "Please update kubectl to 1.15 or higher"
  exit 1
fi

echo "[dev-env] building image"
make build image
docker tag "${REGISTRY}/nginx-ingress-controller:${TAG}" "${DEV_IMAGE}"

# export K8S_VERSION=${K8S_VERSION:-v1.18.0@sha256:0e20578828edd939d25eb98496a685c76c98d54084932f76069f886ec315d694}

# export DOCKER_CLI_EXPERIMENTAL=enabled

# KIND_CLUSTER_NAME="ingress-nginx-dev"

# if ! kind get clusters -q | grep -q ${KIND_CLUSTER_NAME}; then
# echo "[dev-env] creating Kubernetes cluster with kind"
# cat <<EOF | kind create cluster --name ${KIND_CLUSTER_NAME} --image "kindest/node:${K8S_VERSION}" --config=-
# kind: Cluster
# apiVersion: kind.x-k8s.io/v1alpha4
# nodes:
# - role: control-plane
#   kubeadmConfigPatches:
#   - |
#     kind: InitConfiguration
#     nodeRegistration:
#       kubeletExtraArgs:
#         node-labels: "ingress-ready=true"
#         authorization-mode: "AlwaysAllow"
#   extraPortMappings:
#   - containerPort: 80
#     hostPort: 80
#     protocol: TCP
#   - containerPort: 443
#     hostPort: 443
#     protocol: TCP
# EOF
# else
#   echo "[dev-env] using existing Kubernetes kind cluster"
# fi

# echo "[dev-env] copying docker images to cluster..."
# kind load docker-image --name="${KIND_CLUSTER_NAME}" "${DEV_IMAGE}"

echo "[dev-env] deploying NGINX Ingress controller..."
kubectl create namespace ingress-nginx &> /dev/null || true

cat << EOF | helm template ingress-nginx ${DIR}/../charts/ingress-nginx --namespace=ingress-nginx --values - | kubectl apply -n ingress-nginx -f -
controller:
  image:
    repository: ${REGISTRY}/nginx-ingress-controller
    tag: ${TAG}
  config:
    worker-processes: "1"
  podLabels:
    deploy-date: "$(date +%s)"
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
  hostPort:
    enabled: true
  terminationGracePeriodSeconds: 0
  service:
    type: NodePort
EOF

cat <<EOF

Kubernetes cluster ready and ingress-nginx listening in localhost using ports 80 and 443

To delete the dev cluster execute: 'kind delete cluster --name ingress-nginx-dev'

EOF
