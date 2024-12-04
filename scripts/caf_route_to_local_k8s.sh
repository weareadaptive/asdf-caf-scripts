#!/usr/bin/env bash

# This script connects your local machine to local K8s routing and DNS

set -eo pipefail

function f_check_kube_context {

  target_context="${1}"
  if [[ "$(kubectl config current-context)" == "${target_context}" ]]
  then true
  else
    echo "** Current active kubeconfig context is not the expected: '${target_context}'"
    echo "** aborting cowardly **"
    exit 1
  fi
}

# check for YQ
echo $(yq --version)
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

# Get the info from K8s for what we need to connect to
declare ADAPTIVE_DOMAIN POD_CIDR NODE_IP DNS_IP NODE_INTERFACE INGRESS_CONTROLLER_NS INGRESS_CONTROLLER_SVC DNS_DOMAIN SERVICE_CIDR

ADAPTIVE_DOMAIN="${ADAPTIVE_DOMAIN:-adaptive.local}"
DNS_DOMAIN="cluster.local"

# Handle different OS
# On Mac/Orbstack, the IP routing is already set up for us, we just need to sort the DNS
# On Linux, we need to do both the IP routing and DNS routing
case ${OSTYPE} in
  darwin*)

    if orbctl status; then
      true
    else
      echo "Only Orbstack is supported on OS X ( brew install orbstack )"
      echo "Please make sure orbstack config is created with caf_ scripts"
      echo "or make sure appropriate resources and direct routing is set"
      exit 1
    fi

    f_check_kube_context orbstack

    SERVICE_CIDR="Orbstack defined"
    POD_CIDR="Orbstack defined"
    NODE_IP="Orbstack defined"
    NODE_INTERFACE="Orbstack defined"

    ;;
  linux*)

    f_check_kube_context minikube

    SERVICE_CIDR="$(kubectl get cm kubeadm-config -n kube-system -o jsonpath='{.data.ClusterConfiguration}' | yq '.networking.serviceSubnet')"
    POD_CIDR="$(kubectl get nodes -o jsonpath='{.items[0].spec}' | jq -r ".podCIDR")"
    NODE_IP="$(kubectl get nodes -o jsonpath="{.items[0].status.addresses[?(@.type=='InternalIP')].address}")"
    NODE_INTERFACE="$(ip route get "${NODE_IP}" | grep "${NODE_IP}" | awk '{print $3}')"
    true
    ;;
  *)
    echo "Unsupported OS: aborting"
    exit 1
    ;;
esac

DNS_IP="$(kubectl -n kube-system get svc kube-dns -o jsonpath="{.spec.clusterIP}")"

if kubectl get ns nginx-ingress; then
  label="caf/is-ingress-controller=true"
elif kubectl get ns emissary-ingress; then
  label="app.kubernetes.io/name=emissary-ingress"
else
  echo "Unable to create a route to K8s: unsupported ingress controller"
  exit 1
fi
INGRESS_CONTROLLER_NS="$(kubectl get svc -l "${label}" -A --no-headers | grep -v admin | awk '{print $1}' || echo 'unknown')"
INGRESS_CONTROLLER_SVC="$(kubectl get svc -l "${label}" -A --no-headers | grep -v admin | awk '{print $2}' || echo 'unknown')"

export ADAPTIVE_DOMAIN POD_CIDR NODE_IP DNS_IP NODE_INTERFACE INGRESS_CONTROLLER_NS INGRESS_CONTROLLER_SVC DNS_DOMAIN SERVICE_CIDR

echo "Using:"
echo "DNS_DOMAIN: ${DNS_DOMAIN:? Not found}"
echo "ADAPTIVE_DOMAIN: ${ADAPTIVE_DOMAIN:? Not found}"
echo "POD_CIDR: ${POD_CIDR:? Not found}"
echo "SERVICE_CIDR: ${SERVICE_CIDR:? Not found}"
echo "DNS_IP: ${DNS_IP:? Not found}"
echo "NODE_IP: ${NODE_IP:? Not found}"
echo "NODE_INTERFACE: ${NODE_INTERFACE:? Not found}"
echo "INGRESS_CONTROLLER_NS ${INGRESS_CONTROLLER_NS:? Not found}"
echo "INGRESS_CONTROLLER_SVC: ${INGRESS_CONTROLLER_SVC:? Not found}"

function f_cleanup_routing() {

  echo -e "\nCleaning up"

  case ${OSTYPE} in
    darwin*)
      rm -f "/etc/resolver/${ADAPTIVE_DOMAIN}"
      rm -f "/etc/resolver/${DNS_DOMAIN}"
      ;;
    linux*)
      ip route del "${POD_CIDR}" via "${NODE_IP}"
      ip route del "${SERVICE_CIDR}" via "${NODE_IP}"
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

  echo "Routing traffic/DNS to K8s"

  case ${OSTYPE} in
    darwin*)
      mkdir -p '/etc/resolver'
      echo "nameserver ${DNS_IP}" > "/etc/resolver/${ADAPTIVE_DOMAIN}"
      echo "nameserver ${DNS_IP}" > "/etc/resolver/${DNS_DOMAIN}"
      ;;
    linux*)
      ip route add "${POD_CIDR}" via "${NODE_IP}"
      ip route add "${SERVICE_CIDR}" via "${NODE_IP}"
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
  sleep ${CAF_ROUTE_TO_LOCAL_K8S_TIMEOUT:-99999999}
}

# What config do we have already in coredns?
OLD_COREDNS_CONFIG="$(kubectl -n kube-system get configmap coredns -o jsonpath='{.data.Corefile}')"
# Stanza to inject into coredns configmap
export NEW_COREDNS_CONFIG="${ADAPTIVE_DOMAIN}:53 {
    template ANY A ${ADAPTIVE_DOMAIN} {
        answer \"{{ .Name }} 60 IN CNAME ${INGRESS_CONTROLLER_SVC}.${INGRESS_CONTROLLER_NS}.svc.${DNS_DOMAIN}\"
    }
}
${OLD_COREDNS_CONFIG}
"

# Already configured coredns or non-existant ingress controller?
if kubectl -n kube-system get -o yaml configmap coredns | grep -q "${ADAPTIVE_DOMAIN}" || [[ "${INGRESS_CONTROLLER_SVC}" == 'unknown' ]]; then
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
