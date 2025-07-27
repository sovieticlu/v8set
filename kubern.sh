#!/bin/bash

# Kubernetes Installation Script for Debian
# This script installs Docker, kubeadm, kubelet, and kubectl
# Compatible with Debian 10, 11, and 12

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        log_error "This script should not be run as root. Please run as a regular user with sudo privileges."
        exit 1
    fi
}

# Check if user has sudo privileges
check_sudo() {
    if ! sudo -n true 2>/dev/null; then
        log_error "This script requires sudo privileges. Please ensure your user can run sudo commands."
        exit 1
    fi
}

# Check Debian version
check_debian_version() {
    if ! grep -q -E "ID=(debian|kali)|ID_LIKE=debian" /etc/os-release; then
        log_error "This script is designed for Debian-based systems only."
        exit 1
    fi
    
    local version=$(grep VERSION_ID /etc/os-release | cut -d'"' -f2)
    log_info "Detected Debian version: $version"
    
    if [[ "$version" < "10" ]]; then
        log_warn "Debian version $version may not be fully supported. Recommended: Debian 10 or newer."
    fi
}

# Update system packages
update_system() {
    log_step "Updating system packages..."
    sudo apt-get update
    sudo apt-get upgrade -y
    sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
}

# Disable swap
disable_swap() {
    log_step "Disabling swap..."
    sudo swapoff -a
    sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
    log_info "Swap disabled permanently"
}

# Configure kernel modules
configure_kernel_modules() {
    log_step "Configuring kernel modules..."
    
    # Load required modules
    sudo modprobe overlay
    sudo modprobe br_netfilter
    
    # Make modules persistent
    cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
    
    # Configure sysctl parameters
    cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

    # Configure Raspberry Pi specific settings if needed
    if grep -q "Raspberry Pi" /proc/cpuinfo; then
        log_info "Raspberry Pi detected, configuring cgroups..."
        
        # Backup cmdline.txt if it hasn't been backed up
        if [ ! -f /boot/firmware/cmdline.txt.backup ]; then
            sudo cp /boot/firmware/cmdline.txt /boot/firmware/cmdline.txt.backup
        fi

        # Read current cmdline content
        local cmdline=$(cat /boot/firmware/cmdline.txt)
        local modified=false
        local needs_reboot=false

        # Add required cgroup parameters if they're not present
        for param in "cgroup_enable=cpuset" "cgroup_enable=memory" "cgroup_memory=1"; do
            if [[ ! $cmdline =~ $param ]]; then
                cmdline="$cmdline $param"
                modified=true
                needs_reboot=true
            fi
        done

        # Also check for required boot config parameters
        if [ ! -f /boot/config.txt.backup ]; then
            sudo cp /boot/config.txt /boot/config.txt.backup
        fi

        # Ensure arm_64bit=1 is set in config.txt
        if ! grep -q "^arm_64bit=1" /boot/config.txt; then
            echo "arm_64bit=1" | sudo tee -a /boot/config.txt
            modified=true
            needs_reboot=true
        fi

        # Write modified cmdline if changes were made
        if [ "$modified" = true ]; then
            echo $cmdline | sudo tee /boot/firmware/cmdline.txt > /dev/null
            log_warn "Raspberry Pi boot configuration has been updated"
        fi

        # Handle reboot if needed
        if [ "$needs_reboot" = true ]; then
            log_warn "System needs to be rebooted to enable required features"
            read -p "Do you want to reboot now? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                log_info "Rebooting system..."
                sudo reboot
            else
                log_warn "Please reboot your system manually before continuing with Kubernetes installation"
                exit 0
            fi
        fi
    fi
    
    sudo sysctl --system
    log_info "Kernel modules and sysctl parameters configured"
}

# Install Docker
install_docker() {
    log_step "Installing Docker..."
    
    # Remove old Docker versions
    sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # Add Docker's official GPG key
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    # Add Docker repository
    echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    jammy stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Configure Docker daemon for Kubernetes
    sudo mkdir -p /etc/docker
    cat <<EOF | sudo tee /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF
    
    # Enable and start Docker
    sudo systemctl enable docker
    sudo systemctl daemon-reload
    sudo systemctl restart docker
    
    # Add current user to docker group
    sudo usermod -aG docker $USER
    
    log_info "Docker installed and configured"
}

# Configure containerd
configure_containerd() {
    log_step "Configuring containerd..."
    
    # Create containerd config directory
    sudo mkdir -p /etc/containerd
    
    # Generate default containerd configuration
    cat << EOF | sudo tee /etc/containerd/config.toml
version = 2
root = "/var/lib/containerd"
state = "/run/containerd"

[grpc]
  address = "/run/containerd/containerd.sock"
  uid = 0
  gid = 0

[plugins."io.containerd.grpc.v1.cri"]
  stream_server_address = "127.0.0.1"
  stream_server_port = "0"
  enable_selinux = false
  enable_unprivileged_ports = true
  enable_unprivileged_icmp = true
  
  [plugins."io.containerd.grpc.v1.cri".containerd]
    snapshotter = "overlayfs"
    default_runtime_name = "runc"
    
    [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
      runtime_type = "io.containerd.runc.v2"
      
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
        SystemdCgroup = true
        
  [plugins."io.containerd.grpc.v1.cri".cni]
    bin_dir = "/opt/cni/bin"
    conf_dir = "/etc/cni/net.d"
    
  [plugins."io.containerd.grpc.v1.cri".registry]
    [plugins."io.containerd.grpc.v1.cri".registry.mirrors]
      [plugins."io.containerd.grpc.v1.cri".registry.mirrors."docker.io"]
        endpoint = ["https://registry-1.docker.io"]
EOF

    # Create CNI directories
    sudo mkdir -p /opt/cni/bin
    sudo mkdir -p /etc/cni/net.d
    
    # Install CNI plugins
    CNI_VERSION="v1.3.0"
    sudo mkdir -p /opt/cni/bin
    curl -L "https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-linux-$(dpkg --print-architecture)-${CNI_VERSION}.tgz" | sudo tar -C /opt/cni/bin -xz
    
    # Restart containerd
    sudo systemctl restart containerd
    sudo systemctl enable containerd
    
    log_info "containerd configured with systemd cgroup driver and CNI plugins installed"
}

# Install Kubernetes components
install_kubernetes() {
    log_step "Installing Kubernetes components..."
    
    # Add Kubernetes GPG key
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    
    # Add Kubernetes repository
    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
    
    # Install Kubernetes components
    sudo apt-get update
    sudo apt-get install -y kubelet kubeadm kubectl
    
    # Hold Kubernetes packages to prevent automatic updates
    sudo apt-mark hold kubelet kubeadm kubectl
    
    log_info "Kubernetes components installed (kubelet, kubeadm, kubectl)"
}

# Configure kubelet
configure_kubelet() {
    log_step "Configuring kubelet..."
    
    # Create kubelet configuration directory
    sudo mkdir -p /etc/systemd/system/kubelet.service.d/
    
    # Configure kubelet service
    cat << EOF | sudo tee /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
[Service]
Environment="KUBELET_KUBECONFIG_ARGS=--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf"
Environment="KUBELET_CONFIG_ARGS=--config=/var/lib/kubelet/config.yaml"
Environment="KUBELET_EXTRA_ARGS=--cgroup-driver=systemd --fail-swap-on=false"
ExecStart=
ExecStart=/usr/bin/kubelet \$KUBELET_KUBECONFIG_ARGS \$KUBELET_CONFIG_ARGS \$KUBELET_EXTRA_ARGS
EOF
    
    # Reload systemd and restart kubelet
    sudo systemctl daemon-reload
    sudo systemctl enable kubelet
    sudo systemctl restart kubelet
    
    log_info "kubelet service configured and enabled"
}

# Initialize Kubernetes cluster (master node)
init_cluster() {
    read -p "Do you want to initialize this node as a Kubernetes master? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_step "Initializing Kubernetes cluster..."
        
        # Get the primary IP address
        local primary_ip=$(ip route get 8.8.8.8 | awk '{print $7; exit}')
        
        # Initialize cluster with ignoring preflight errors and proper networking
        cat << EOF | sudo tee /tmp/kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
bootstrapTokens:
- groups:
  - system:bootstrappers:kubeadm:default-node-token
  ttl: 24h0m0s
  usages:
  - signing
  - authentication
localAPIEndpoint:
  advertiseAddress: $primary_ip
  bindPort: 6443
nodeRegistration:
  name: $(hostname -s)
  criSocket: unix:///var/run/containerd/containerd.sock
  taints: []
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
networking:
  podSubnet: 10.244.0.0/16
  serviceSubnet: 10.96.0.0/12
apiServer:
  extraArgs:
    bind-address: "0.0.0.0"
    secure-port: "6443"
    advertise-address: "$primary_ip"
    enable-bootstrap-token-auth: "true"
controlPlaneEndpoint: "$primary_ip:6443"
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
failSwapOn: false
authentication:
  anonymous:
    enabled: false
  webhook:
    enabled: true
  x509:
    clientCAFile: /etc/kubernetes/pki/ca.crt
EOF

        # Configure kubelet to use the correct API server address
        cat << EOF | sudo tee /etc/default/kubelet
KUBELET_EXTRA_ARGS="--node-ip=$primary_ip --pod-infra-container-image=registry.k8s.io/pause:3.9 --address=0.0.0.0 --anonymous-auth=false"
EOF

        # Create kubelet configuration
        cat << EOF | sudo tee /var/lib/kubelet/config.yaml
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
address: 0.0.0.0
authentication:
  anonymous:
    enabled: false
  webhook:
    enabled: true
  x509:
    clientCAFile: /etc/kubernetes/pki/ca.crt
cgroupDriver: systemd
failSwapOn: false
containerRuntimeEndpoint: unix:///run/containerd/containerd.sock
staticPodPath: /etc/kubernetes/manifests
evictionHard:
  memory.available: "100Mi"
  nodefs.available: "10%"
  nodefs.inodesFree: "5%"
maxPods: 110
serializeImagePulls: false
featureGates:
  SupportPodPidsLimit: true
  SupportNodePidsLimit: true
systemReserved:
  memory: 512Mi
  cpu: 500m
  ephemeral-storage: 1Gi
kubeReserved:
  memory: 512Mi
  cpu: 500m
  ephemeral-storage: 1Gi
enforceNodeAllocatable:
- pods
- system-reserved
- kube-reserved
EOF
        
        # Reset any previous kubernetes configuration
        sudo kubeadm reset -f
        sudo rm -rf /etc/cni/net.d/*
        sudo rm -rf $HOME/.kube
        sudo systemctl stop kubelet
        sudo systemctl stop docker
        sudo rm -rf /var/lib/kubelet/*
        sudo rm -rf /etc/kubernetes/*
        sudo systemctl start docker
        sudo systemctl start kubelet
        sudo systemctl restart containerd
        
        # Wait for services to be ready
        sleep 5
        
        # Initialize the cluster with the configuration
        sudo kubeadm init --config=/tmp/kubeadm-config.yaml --ignore-preflight-errors=all --v=5 --skip-phases=addon/kube-proxy
        
        # Verify API server is running
        timeout=60
        while [[ $timeout -gt 0 ]]; do
            if sudo netstat -tlpn | grep -q ":6443.*kube-apiserver"; then
                log_info "API server is running on port 6443"
                break
            fi
            log_warn "Waiting for API server to start... (${timeout}s remaining)"
            sleep 5
            ((timeout-=5))
        done
        
        # Configure kubectl for regular user
        mkdir -p $HOME/.kube
        sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
        sudo chown $(id -u):$(id -g) $HOME/.kube/config

        log_info "Kubernetes cluster initialized successfully!"
        log_info "Master node IP: $primary_ip"
        log_warn "Save the 'kubeadm join' command shown above to join worker nodes to this cluster."
        
        # Install Flannel CNI
        read -p "Do you want to install Flannel CNI plugin? (Y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            log_step "Installing Flannel CNI..."
              # Download flannel manifest
            curl -L https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml -o /tmp/kube-flannel.yml
            
            # Update interface in flannel configuration if on Raspberry Pi
            if grep -q "Raspberry Pi" /proc/cpuinfo; then
                # Get the primary interface name
                PRIMARY_INT=$(ip route | grep default | cut -d' ' -f5)
                # Update the flannel configuration
                sed -i "s/      - --iface=\$(DEFAULT_LOCAL_IP)/      - --iface=${PRIMARY_INT}/" /tmp/kube-flannel.yml
            fi
            
            # Apply flannel configuration
            kubectl apply -f /tmp/kube-flannel.yml
            
            # Wait for flannel pods to be ready
            log_info "Waiting for Flannel pods to be ready..."
            kubectl -n kube-flannel wait --for=condition=ready pod --selector app=flannel --timeout=1200s
            
            # Remove the taint from the control-plane node if it's a single-node cluster
            log_info "Removing control-plane taint to allow pod scheduling..."
            kubectl taint nodes --all node-role.kubernetes.io/control-plane:NoSchedule- 2>/dev/null || true
            kubectl taint nodes --all node-role.kubernetes.io/master:NoSchedule- 2>/dev/null || true
 
            log_info "Flannel CNI installed"
        fi
    else
        log_info "Cluster initialization skipped. You can run 'sudo kubeadm init' manually later."
        log_info "Or use 'sudo kubeadm join' to join this node to an existing cluster."
    fi
}

# Verification function
verify_installation() {
    log_step "Verifying installation..."
    
    # Check Docker
    if docker --version >/dev/null 2>&1; then
        log_info "✓ Docker is installed: $(docker --version)"
    else
        log_error "✗ Docker installation failed"
    fi
    
    # Check Kubernetes components
    if kubelet --version >/dev/null 2>&1; then
        log_info "✓ kubelet is installed: $(kubelet --version)"
    else
        log_error "✗ kubelet installation failed"
    fi
    
    if kubeadm version >/dev/null 2>&1; then
        log_info "✓ kubeadm is installed: $(kubeadm version --short)"
    else
        log_error "✗ kubeadm installation failed"
    fi
    
    if kubectl version --client >/dev/null 2>&1; then
        log_info "✓ kubectl is installed: $(kubectl version --client --short)"
    else
        log_error "✗ kubectl installation failed"
    fi
    
    # Check if cluster is initialized
    if kubectl cluster-info >/dev/null 2>&1; then
        log_info "✓ Kubernetes cluster is running"
        kubectl get nodes
    else
        log_warn "Kubernetes cluster is not initialized yet"
    fi
}

# Cleanup function
cleanup_on_error() {
    log_error "Installation failed. Check the error messages above."
    exit 1
}

# Main installation function
main() {
    log_info "Starting Kubernetes installation on Debian..."
    
    # Set error handler
    trap cleanup_on_error ERR
    
    # Prerequisite checks
    check_root
    check_sudo
    check_debian_version
    
    # Installation steps
    update_system
    disable_swap
    configure_kernel_modules
    install_docker
    configure_containerd
    install_kubernetes
    configure_kubelet
    
    log_info "Base Kubernetes installation completed successfully!"
    log_warn "Please log out and log back in for Docker group changes to take effect."
    
    # Optional cluster initialization
    init_cluster
    
    # Verify installation
    verify_installation
    
    log_info "Installation script completed!"
    log_info "Next steps:"
    echo "  1. Log out and log back in (for Docker group membership)"
    echo "  2. If this is a master node and you didn't initialize: sudo kubeadm init"
    echo "  3. If this is a worker node: sudo kubeadm join <master-ip>:<port> --token <token> --discovery-token-ca-cert-hash <hash>"
    echo "  4. Install a CNI plugin if not already done (e.g., Flannel, Calico, Weave)"
    echo "  5. Deploy your applications with kubectl"
}

# Run main function
main "$@"