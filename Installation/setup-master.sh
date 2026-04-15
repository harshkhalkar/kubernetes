#!/usr/bin/env bash

set -euo pipefail

#######################################
# CONFIGURATION
#######################################
POD_CIDR="${POD_CIDR:-192.168.0.0/16}"
CALICO_VERSION="${CALICO_VERSION:-v3.28.0}"
KUBECONFIG_PATH="$HOME/.kube/config"

#######################################
# LOGGING
#######################################
log() {
  echo -e "\n[INFO] $1"
}

error() {
  echo -e "\n[ERROR] $1" >&2
  exit 1
}

#######################################
# PRECHECK
#######################################
if [[ "$EUID" -ne 0 ]]; then
  error "Run as root or with sudo"
fi

#######################################
# 1. INITIALIZE CLUSTER
#######################################
if [[ -f /etc/kubernetes/admin.conf ]]; then
  log "Kubernetes already initialized. Skipping kubeadm init..."
else
  log "Initializing Kubernetes cluster..."

  kubeadm init \
    --pod-network-cidr="$POD_CIDR" \
    --upload-certs

fi

#######################################
# 2. SETUP KUBECONFIG
#######################################
log "Setting up kubeconfig..."

mkdir -p "$HOME/.kube"
cp -i /etc/kubernetes/admin.conf "$KUBECONFIG_PATH"
chown "$(id -u):$(id -g)" "$KUBECONFIG_PATH"

export KUBECONFIG="$KUBECONFIG_PATH"

#######################################
# 3. WAIT FOR API SERVER
#######################################
log "Waiting for API server..."

until kubectl get nodes >/dev/null 2>&1; do
  sleep 2
done

#######################################
# 4. INSTALL CALICO
#######################################
if kubectl get pods -n kube-system | grep -q calico; then
  log "Calico already installed. Skipping..."
else
  log "Installing Calico ($CALICO_VERSION)..."

  kubectl apply -f \
  "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml"
fi

#######################################
# 5. WAIT FOR NODES READY
#######################################
log "Waiting for node to be Ready..."

kubectl wait --for=condition=Ready node --all --timeout=180s || true

#######################################
# 6. GENERATE JOIN COMMAND
#######################################
log "Generating worker join command..."

kubeadm token create --print-join-command | tee /root/join-command.sh

chmod +x /root/join-command.sh

#######################################
# FINAL STATUS
#######################################
log "Cluster status:"
kubectl get nodes -o wide

log "| Master node setup complete!"
log "| Join command saved at: /root/join-command.sh"
