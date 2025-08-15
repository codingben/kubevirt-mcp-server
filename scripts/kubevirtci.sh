#!/bin/bash
#
# Copyright 2023 Red Hat, Inc.
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

set -ex

export KUBEVIRT_MEMORY_SIZE="${KUBEVIRT_MEMORY_SIZE:-16G}"
export KUBEVIRT_DEPLOY_CDI="true"
export KUBEVIRT_VERSION=${KUBEVIRT_VERSION:-main}
export KUBEVIRTCI_TAG=${KUBEVIRTCI_TAG:-$(curl -sfL https://raw.githubusercontent.com/kubevirt/kubevirt/"${KUBEVIRT_VERSION}"/kubevirtci/cluster-up/version.txt)}

_base_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
_kubevirtci_dir="${_base_dir}/_kubevirtci"
_kubectl="${_kubevirtci_dir}/cluster-up/kubectl.sh"
_kubessh="${_kubevirtci_dir}/cluster-up/ssh.sh"
_kubevirtci_cli="${_kubevirtci_dir}/cluster-up/cli.sh"
_action=$1
shift

function kubevirtci::fetch_kubevirtci() {
  if [[ ! -d ${_kubevirtci_dir} ]]; then
    git clone --depth 1 --branch "${KUBEVIRTCI_TAG}" https://github.com/kubevirt/kubevirtci.git "${_kubevirtci_dir}"
  fi
}

function kubevirtci::up() {
  make cluster-up -C "${_kubevirtci_dir}"
  KUBECONFIG=$(kubevirtci::kubeconfig)
  export KUBECONFIG

  echo "adding kubevirtci registry to cdi-insecure-registries"
  ${_kubectl} patch cdis/cdi --type merge -p '{"spec": {"config": {"insecureRegistries": ["registry:5000"]}}}'

  # Treat main as stable version
  if [ "$KUBEVIRT_VERSION" = "main" ]; then
    KUBEVIRT_VERSION=$(curl -L https://storage.googleapis.com/kubevirt-prow/devel/release/kubevirt/kubevirt/stable.txt)
  fi

  echo "installing kubevirt..."
  ${_kubectl} apply -f "https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-operator.yaml"
  ${_kubectl} apply -f "https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-cr.yaml"

  echo "waiting for kubevirt to become ready, this can take a few minutes..."
  ${_kubectl} -n kubevirt wait kv kubevirt --for condition=Available --timeout=15m
}

function kubevirtci::down() {
  make cluster-down -C "${_kubevirtci_dir}"
}

function kubevirtci::sync() {
  KUBECTL=${_kubectl} BASEDIR=${_base_dir} "${_base_dir}/scripts/sync.sh"
}

function kubevirtci::kubeconfig() {
  "${_kubevirtci_dir}/cluster-up/kubeconfig.sh"
}

function kubevirtci::registry() {
  port=$(${_kubevirtci_cli} ports registry 2>/dev/null)
  echo "localhost:${port}"
}

kubevirtci::fetch_kubevirtci

case ${_action} in
"up")
  kubevirtci::up
  ;;
"down")
  kubevirtci::down
  ;;
"sync")
  kubevirtci::sync
  ;;
"sync-containerdisks")
  kubevirtci::sync-containerdisks
  ;;
"kubeconfig")
  kubevirtci::kubeconfig
  ;;
"registry")
  kubevirtci::registry
  ;;
"ssh")
  ${_kubessh} "$@"
  ;;
"kubectl")
  ${_kubectl} "$@"
  ;;
*)
  echo "No command provided, known commands are 'up', 'down', 'sync', 'ssh', 'kubeconfig', 'registry', 'kubectl'"
  exit 1
  ;;
esac
