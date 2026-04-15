#!/usr/bin/env bash

set -euo pipefail

#######################################
# CONFIGURATION (EDIT THIS)
#######################################
K8S_VERSION="${K8S_VERSION:-v1.34}"
PAUSE_IMAGE="${PAUSE_IMAGE:-registry.k8s.io/pause:3.10}"
HOLD_PACKAGES="${HOLD_PACKAGES:-false}"

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
# PRECHECKS
#######################################
if [[ "$EUID" -ne 0 ]]; then
  error "Please run as root or use sudo"
fi

command -v apt-get >/dev/null || error "This script supports Debian/Ubuntu only"

#######################################
# 1. DISABLE SWAP
#######################################
log "Disabling swap..."

swapoff -a || true
sed -i '/ swap / s/^/#/' /etc/fstab || true

#######################################
# 2. KERNEL MODULES
#######################################
log "Configuring kernel modules..."

cat <<EOF >/etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay || true
modprobe br_netfilter || true

#######################################
# 3. SYSCTL SETTINGS
#######################################
log "Applying sysctl settings..."

cat <<EOF >/etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system

#######################################
# 4. INSTALL CONTAINERD
#######################################
log "Installing containerd..."

apt-get update -y
apt-get install -y ca-certificates curl gnupg

install -m 0755 -d /etc/apt/keyrings

if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
fi

chmod a+r /etc/apt/keyrings/docker.gpg

ARCH=$(dpkg --print-architecture)
CODENAME=$(source /etc/os-release && echo "$VERSION_CODENAME")

echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $CODENAME stable" \
> /etc/apt/sources.list.d/docker.list

apt-get update -y
apt-get install -y containerd.io

#######################################
# CONTAINERD CONFIG
#######################################
log "Configuring containerd..."

mkdir -p /etc/containerd

containerd config default | \
sed -e 's/SystemdCgroup = false/SystemdCgroup = true/' \
    -e "s|sandbox_image = .*|sandbox_image = \"$PAUSE_IMAGE\"|" \
> /etc/containerd/config.toml

systemctl enable containerd
systemctl restart containerd

#######################################
# 5. INSTALL KUBERNETES
#######################################
log "Installing Kubernetes components ($K8S_VERSION)..."

if [[ ! -f /etc/apt/keyrings/kubernetes.gpg ]]; then
  curl -fsSL https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/Release.key \
    | gpg --dearmor -o /etc/apt/keyrings/kubernetes.gpg
fi

echo "deb [signed-by=/etc/apt/keyrings/kubernetes.gpg] \
https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/ /" \
> /etc/apt/sources.list.d/kubernetes.list

apt-get update -y
apt-get install -y kubelet kubeadm kubectl

#######################################
# OPTIONAL: HOLD PACKAGES
#######################################
if [[ "$HOLD_PACKAGES" == "true" ]]; then
  log "Holding Kubernetes packages..."
  apt-mark hold kubelet kubeadm kubectl
fi

#######################################
# FINAL STATUS
#######################################
log "Validating services..."

systemctl is-active containerd || error "containerd not running"
systemctl enable kubelet

log "| Kubernetes node setup complete!"
