#!/bin/bash

# This script connects your local machine to local K8s routing and DNS

set -eo pipefail

if [[ "${UID}" == 0 ]]; then
  echo "Please don't run this as root, the script will sudo when necessary"
  exit 1
fi

# Can we talk to the configured cluster?
if kubectl cluster-info; then
  true
else
  echo "Can't contact K8s, aborting"
  exit 1
fi

# Handle different OS
case ${OSTYPE} in
  darwin*)

    if colima status; then
      true
    else
      echo "Only Colima is supported on OS X ( brew install colima )"
      exit 1
    fi

    if which ip > /dev/null; then
      true
    else
      echo "Please install ip for Mac: brew install iproute2mac"
      exit 1
    fi

    DNS_DOMAIN="cluster.local"
    SERVICE_CIDR="10.43.0.0/16"

    ;;
  linux*)
    DNS_DOMAIN="$(kubectl get cm kubeadm-config -n kube-system -o jsonpath='{.data.ClusterConfiguration}' | yq '.networking.dnsDomain')"
    SERVICE_CIDR="$(kubectl get cm kubeadm-config -n kube-system -o jsonpath='{.data.ClusterConfiguration}' | yq '.networking.serviceSubnet')"
    true
    ;;
  *)
    echo "Unsupported OS: aborting"
    exit 1
    ;;
esac

# Get the info from K8s for what we need to connect to
declare ADAPTIVE_DOMAIN POD_CIDR NODE_IP DNS_IP NODE_INTERFACE EMISSARY_NS EMISSARY_SVC DNS_DOMAIN SERVICE_CIDR
ADAPTIVE_DOMAIN="${ADAPTIVE_DOMAIN:-adaptive.local}"
POD_CIDR="$(kubectl get nodes -o jsonpath='{.items[0].spec}' | jq -r ".podCIDR")"
NODE_IP="$(kubectl get nodes -o jsonpath="{.items[0].status.addresses[?(@.type=='InternalIP')].address}")"
DNS_IP="$(kubectl -n kube-system get svc kube-dns -o jsonpath="{.spec.clusterIP}")"
NODE_INTERFACE="$(ip route get "${NODE_IP}" | grep "${NODE_IP}" | awk '{print $3}')"
EMISSARY_NS="$(kubectl get svc -l app.kubernetes.io/name=emissary-ingress -A --no-headers | grep -v admin | awk '{print $1}' || echo 'unknown')"
EMISSARY_SVC="$(kubectl get svc -l app.kubernetes.io/name=emissary-ingress -A --no-headers | grep -v admin | awk '{print $2}' || echo 'unknown')"

export ADAPTIVE_DOMAIN POD_CIDR NODE_IP DNS_IP NODE_INTERFACE EMISSARY_NS EMISSARY_SVC DNS_DOMAIN SERVICE_CIDR

echo "Using:"
echo "DNS_DOMAIN: ${DNS_DOMAIN:? Not found}"
echo "ADAPTIVE_DOMAIN: ${ADAPTIVE_DOMAIN:? Not found}"
echo "POD_CIDR: ${POD_CIDR:? Not found}"
echo "SERVICE_CIDR: ${SERVICE_CIDR:? Not found}"
echo "DNS_IP: ${DNS_IP:? Not found}"
echo "NODE_IP: ${NODE_IP:? Not found}"
echo "NODE_INTERFACE: ${NODE_INTERFACE:? Not found}"
echo "EMMISSARY_NS: ${EMISSARY_NS:? Not found}"
echo "EMISSARY_SVC: ${EMISSARY_SVC:? Not found}"

function f_cleanup_routing() {

  echo -e "\nCleaning up"
  sudo ip route del "${POD_CIDR}" via "${NODE_IP}"
  ip route del "${SERVICE_CIDR}" via "${NODE_IP}"

  case ${OSTYPE} in
    darwin*)
      rm -f "/etc/resolver/${ADAPTIVE_DOMAIN}"
      rm -f "/etc/resolver/${DNS_DOMAIN}"
      ;;
    linux*)
      resolvectl revert "${NODE_INTERFACE}"
      ;;
    *)
      echo "Unsupported OS: aborting"
      exit 1
      ;;
  esac

  echo "Finished"
}

function f_add_routing() {

  # cleanup on interrupt
  trap f_cleanup_routing INT

  echo "Routing traffic to K8s"
  ip route add "${POD_CIDR}" via "${NODE_IP}"
  ip route add "${SERVICE_CIDR}" via "${NODE_IP}"

  echo "Updating system with K8s DNS servers"
  case ${OSTYPE} in
    darwin*)
      mkdir -p '/etc/resolver'
      echo "nameserver ${DNS_IP}" > "/etc/resolver/${ADAPTIVE_DOMAIN}"
      echo "nameserver ${DNS_IP}" > "/etc/resolver/${DNS_DOMAIN}"
      ;;
    linux*)
      resolvectl dns "${NODE_INTERFACE}" "${DNS_IP}"
      resolvectl domain "${NODE_INTERFACE}" "${ADAPTIVE_DOMAIN}" "${DNS_DOMAIN}"
      ;;
    *)
      echo "Unsupported OS: aborting"
      exit 1
      ;;
  esac

  echo "Press ctrl-c to exit"
  # We don't use 'infinity' as Macs don't support it
  sleep 99999999
}

# What config do we have already in coredns?
OLD_COREDNS_CONFIG="$(kubectl -n kube-system get configmap coredns -o jsonpath='{.data.Corefile}')"
# Stanza to inject into coredns configmap
export NEW_COREDNS_CONFIG="${ADAPTIVE_DOMAIN}:53 {
    template ANY A ${ADAPTIVE_DOMAIN} {
        answer \"{{ .Name }} 60 IN CNAME ${EMISSARY_SVC}.${EMISSARY_NS}.svc.${DNS_DOMAIN}\"
    }
}
${OLD_COREDNS_CONFIG}
"

# Already configured coredns or non-existant emmissary?
if kubectl -n kube-system get -o yaml configmap coredns | grep -q "${ADAPTIVE_DOMAIN}" || [[ "${EMISSARY_SVC}" == 'unknown' ]]; then
  true
else
  echo "Updating coredns for ingress records under: ${ADAPTIVE_DOMAIN}"
  # Create a patchfile for coredns configmap
  yq e -n '.data.Corefile = strenv(NEW_COREDNS_CONFIG)' > /tmp/coredns_patch.yml
  # Apply the patch
  kubectl patch -n kube-system configmap coredns --patch-file=/tmp/coredns_patch.yml
  # Restart coredns to apply the config
  kubectl -n kube-system rollout restart deployment.apps/coredns
fi

# We have to define to functions we've declared inside the sudo session dynamically
# As we must have the running sudo session active for the cleanup to be guarenteed to work
sudo -E bash -c "$(declare -f f_cleanup_routing); $(declare -f f_add_routing); f_add_routing"
