set -euo pipefail

#######################################
# DEFAULTS
#######################################
DEFAULT_POD_CIDR="192.168.0.0/16"
DEFAULT_CALICO_VERSION="v3.28.0"

#######################################
# HELPERS
#######################################
log() {
  echo -e "\n[INFO] $1"
}

#######################################
# SELECT ROLE
#######################################
echo "Select node role:"
echo "1) First Control Plane (init)"
echo "2) Join Control Plane (node 2/3)"
read -rp "Enter choice [1-2]: " ROLE

#######################################
# ROLE 1: INIT CONTROL PLANE
#######################################
if [[ "$ROLE" == "1" ]]; then

  # ✅ FIXED: reliable IP detection
  NODE_IP=$(ip route get 1.1.1.1 | awk '{print $7; exit}')

  read -rp "Enter LOAD BALANCER DNS: " LB_DNS
  read -rp "Enter POD CIDR [default: ${DEFAULT_POD_CIDR}]: " POD_CIDR
  POD_CIDR=${POD_CIDR:-$DEFAULT_POD_CIDR}

  read -rp "Enter Calico version [default: ${DEFAULT_CALICO_VERSION}]: " CALICO_VERSION
  CALICO_VERSION=${CALICO_VERSION:-$DEFAULT_CALICO_VERSION}

  log "Initializing control plane using LOCAL IP ${NODE_IP}"

  #######################################
  # INIT CLUSTER (LOCAL IP ONLY)
  #######################################
  kubeadm init \
    --apiserver-advertise-address="${NODE_IP}" \
    --control-plane-endpoint="${NODE_IP}:6443" \
    --upload-certs \
    --pod-network-cidr="${POD_CIDR}"

  #######################################
  # KUBECONFIG
  #######################################
  log "Setting up kubeconfig..."
  mkdir -p "$HOME/.kube"
  cp /etc/kubernetes/admin.conf "$HOME/.kube/config"
  chown "$(id -u):$(id -g)" "$HOME/.kube/config"
  export KUBECONFIG="$HOME/.kube/config"

  #######################################
  # FIX: ADD LB DNS TO CERT SAN
  #######################################
  log "Fixing API server certificate (adding LB DNS)..."

  cat > kubeadm-config.yaml <<EOF
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
controlPlaneEndpoint: "${LB_DNS}:6443"
apiServer:
  certSANs:
    - "${LB_DNS}"
    - "${NODE_IP}"
EOF

  rm -f /etc/kubernetes/pki/apiserver.crt
  rm -f /etc/kubernetes/pki/apiserver.key

  kubeadm init phase certs apiserver --config kubeadm-config.yaml
  systemctl restart kubelet

  #######################################
  # INSTALL CALICO
  #######################################
  log "Installing Calico ${CALICO_VERSION}..."
  kubectl apply -f "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml"

  #######################################
  # GENERATE JOIN COMMAND
  #######################################
  log "Generating control-plane join command..."

  BASE_JOIN=$(kubeadm token create --print-join-command)
  CERT_KEY=$(kubeadm init phase upload-certs --upload-certs | tail -1)

  # Replace IP with LB DNS
  LB_JOIN_CMD=$(echo "$BASE_JOIN" | sed "s|${NODE_IP}:6443|${LB_DNS}:6443|")

  echo ""
  echo "=================================================="
  echo "CONTROL-PLANE JOIN COMMAND:"
  echo ""
  echo "${LB_JOIN_CMD} --control-plane --certificate-key ${CERT_KEY}"
  echo ""
  echo "=================================================="

#######################################
# ROLE 2: JOIN CONTROL PLANE
#######################################
elif [[ "$ROLE" == "2" ]]; then

  read -rp "Paste FULL control-plane join command: " JOIN_CMD

  log "Resetting node (if needed)..."
  kubeadm reset -f

  log "Joining node to control plane..."
  eval "$JOIN_CMD"

  log "Node joined successfully!"

#######################################
# INVALID OPTION
#######################################
else
  echo "Invalid option"
  exit 1
fi
