#!/usr/bin/env bash

# Creates supported Kubernetes environments

set -eo pipefail

CAF_LCL_K8S_MEMORY="${CAF_LCL_K8S_MEMORY:-16}"
CAF_LCL_K8S_VERSION="${CAF_LCL_K8S_VERSION:-v1.30.0}"
CAF_RESTART_ORBSTACK=0

# check for YQ
if yq --version > /dev/null 2>&1
then true
else
  echo "No yq available - please install/enable it, usually through direnv/.tool-versions"
  exit 1
fi

# check for kubectl
if kubectl version --client=true > /dev/null 2>&1
then true
else
  echo "No kubectl available - please install/enable it, usually through direnv/.tool-versions"
  exit 1
fi

# Waits for a context to be available, then switches to it.
function f_wait_for_k8s_context {

  my_context="${1}"
  until kubectl config get-contexts | awk '{print $2}' | grep -q "${my_context}"
  do
    echo "** ... waiting for kube-context ${my_context}"
    sleep 2
  done
  kubectl config use-context "${my_context}"

}

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
    # f_orbctl_update cpu "${MAX_CPU}"
    # f_orbctl_update memory_mib "${CAF_LCL_K8S_MEMORY}384"
    # f_orbctl_update network_proxy auto
    f_orbctl_update network_bridge true
    f_orbctl_update docker.set_context true
    f_orbctl_update k8s.expose_services true

    if [[ "${CAF_RESTART_ORBSTACK}" == "1" ]]; then
      orbctl stop
      orbctl start
      orbctl status
      echo "Finished restarting"
    fi

    f_wait_for_k8s_context orbstack

    # Load metrics server
    until kubectl cluster-info >/dev/null 2>&1
    do
      echo "** ... waiting for Orbstack"
      sleep 2
    done
    echo "** Loading metrics-server"
    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

    ;;
  linux*)

    if minikube status; then
      f_wait_for_k8s_context minikube
    else
      minikube start \
        --kubernetes-version="${CAF_LCL_K8S_VERSION}" \
        --driver="docker" \
        --memory="${CAF_LCL_K8S_MEMORY}G" \
        --cpus="max" \
        --addons="registry,metrics-server" \
        --embed-certs
    fi

    ;;
  *)
    echo "Unsupported OS: aborting"
    exit 1
    ;;
esac

# Check if Coredns is ready
until kubectl -n kube-system get cm coredns >/dev/null 2>&1
do
  echo "** ...Waiting for Coredns"
  sleep 2
done

OLD_COREDNS_CONFIG="$(kubectl -n kube-system get configmap coredns -o jsonpath='{.data.Corefile}')"
# remove existing cache config
updated_stanza="cache {\n      disable denial cluster.local\n      disable success cluster.local\n    }\n}"
export NEW_COREDNS_CONFIG
NEW_COREDNS_CONFIG="$(echo "${OLD_COREDNS_CONFIG}" | sed "s/cache.*/${updated_stanza}/g")"

echo "Checking if DNS caching is disabled for cluster.local subdomain..."
if kubectl -n kube-system get -o yaml configmap coredns | grep "disable denial cluster.local\|disable success cluster.local" &>/dev/null; then
    echo "CoreDNS already has caching disabled for cluster.local"
    true
else
    echo "Updating CoreDNS to disable DNS caching on cluster.local..."
    # Create a patchfile for CoreDNS configmap
    yq e -n '.data.Corefile = strenv(NEW_COREDNS_CONFIG)' > /tmp/coredns_patch.yml
    # Apply the patch
    kubectl patch -n kube-system configmap coredns --patch-file=/tmp/coredns_patch.yml
    # Restart coredns to apply the config
    kubectl -n kube-system rollout restart deployment.apps/coredns
fi
