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

function apply_custom_corends_config {
  # The following Corefile configuration file adds a cache block to the CoreDNS configuration.
  # It sets the success cache TTL to 30 seconds and disables the cache for the cluster.local domain.

  temp_file_path="$(mktemp)"
  cat <<EOF > "${temp_file_path}"
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
data:
  Corefile: |
    .:53 {
        log
        errors
        health {
           lameduck 5s
        }
        ready
        kubernetes cluster.local in-addr.arpa ip6.arpa {
           pods insecure
           fallthrough in-addr.arpa ip6.arpa
           ttl 30
        }
        prometheus :9153
        hosts {
           192.168.49.1 host.minikube.internal
           fallthrough
        }
        forward . /etc/resolv.conf {
           max_concurrent 1000
        }
        cache {
          success 30
          disable denial cluster.local
        }
        loop
        reload
        loadbalance
    }
EOF

  echo "Patching CoreDNS configuration to disable DNS negative caching for cluster.local domain..."
  kubectl apply -f "${temp_file_path}" --force
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

# Sets the success cache TTL to 30 seconds and disables the cache for the cluster.local domain.
apply_custom_corends_config
