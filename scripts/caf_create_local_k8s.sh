#!/usr/bin/env bash

# Creates supported Kubernetes environments

CAF_LCL_K8S_MEMORY="${CAF_LCL_K8S_MEMORY:-16}"
CAF_LCL_K8S_VERSION="${CAF_LCL_K8S_VERSION:-v1.26.8}"

case ${OSTYPE} in
  darwin*)

    MAX_CPU="$(sysctl -n hw.ncpu)"

    if which colima > /dev/null; then
      true
    else
      echo "Colima is the only supported Docker / Kubernetes provider for now"
      echo " installing it with 'brew install colima socket_vmnet'"
      brew install colima socket_vmnet
    fi

    if colima status; then
      true
    else
      colima start \
        -t vz `# mac native virtualisation` \
        --vz-rosetta `# enable rosetta x86 emulation` \
        -c "${MAX_CPU}" `# CPUs to use` \
        -m "${CAF_LCL_K8S_MEMORY}" `# Memory to use` \
        --network-address `# Assign a network address so we can route to it` \
        --network-driver slirp `# Advanced networking driver - requires socket_vmnet` \
        -k `# enable kubernetes` \
        --kubernetes-version "${CAF_LCL_K8S_VERSION}+k3s1"
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
