#!/usr/bin/env bash

# Creates supported Kubernetes environments

set -eo pipefail

CAF_LCL_K8S_MEMORY="${CAF_LCL_K8S_MEMORY:-16}"
CAF_LCL_K8S_VERSION="${CAF_LCL_K8S_VERSION:-v1.27.4}"

CAF_RESTART_ORBSTACK=0

# Update Orbstack config and trigger a restart if necessary
function f_orbctl_update {
  orbkey="$1"
  orbval="$2"
  orbset="$(orbctl config show)"
  if echo "${orbset}" | grep -q "${orbkey}: ${orbval}"; then
    true
  else
    orbctl config set "${orbkey}" "${orbval}"
    CAF_RESTART_ORBSTACK=1
  fi

}

case ${OSTYPE} in
  darwin*)

    MAX_CPU="$(sysctl -n hw.ncpu)"

    if which orbctl > /dev/null; then
      true
    else
      echo "Orbstack is the only supported Docker / Kubernetes provider for now on Mac"
      echo " installing it with 'brew install orbstack'"
      echo " and request a licence through Helpdesk"
      exit 1
    fi

    # Configuration we need in Orbstack
    f_orbctl_update rosetta true
    f_orbctl_update setup.use_admin true
    f_orbctl_update k8s.enable true
    f_orbctl_update cpu "${MAX_CPU}"
    f_orbctl_update memory_mib "${CAF_LCL_K8S_MEMORY}384"
    f_orbctl_update network_proxy auto
    f_orbctl_update network_bridge true
    f_orbctl_update docker.set_context true
    f_orbctl_update k8s.expose_services true

    if [[ "${CAF_RESTART_ORBSTACK}" == "1" ]]; then
      orbctl stop
      orbctl start
      orbctl status
      echo "Finished restarting"
    fi

    ;;
  linux*)

    if minikube status; then
      true
    else
      minikube start \
        --kubernetes-version="${CAF_LCL_K8S_VERSION}" \
        --driver="docker" \
        --memory="${CAF_LCL_K8S_MEMORY}G" \
        --cpus="max" \
        --addons="registry" \
        --embed-certs
    fi

    ;;
  *)
    echo "Unsupported OS: aborting"
    exit 1
    ;;
esac