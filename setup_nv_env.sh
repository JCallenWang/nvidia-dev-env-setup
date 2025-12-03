# =============================================
# NVIDIA Developer Environment Auto Setup Script
# Components:
#   - NVIDIA Driver 580
#   - CUDA 13.x
#   - Docker CE
#   - NVIDIA Container Toolkit 1.17.8
# Features:
#   - install / uninstall modes
#   - version fixed (GPU assumed RTX or newer)
#   - error handling with descriptive messages
# =============================================

set -e
set -o pipefail

LOG_DIR="./logs"
LOG_FILE="$LOG_DIR/install.log"
INSTALL_RECORD="$LOG_DIR/installed.list"

mkdir -p "$LOG_DIR"

log() {
    echo -e "\n==== $1 ====\n" | tee -a "$LOG_FILE"
}

task_record() {
    echo "$1" >> "$INSTALL_RECORD"
}

handle_error() {
    local exit_code=$?
    echo "ERROR: Command failed with exit code $exit_code at line $1." | tee -a "$LOG_FILE"
    echo "Check $LOG_FILE for details." | tee -a "$LOG_FILE"
    exit $exit_code
}

trap 'handle_error $LINENO' ERR

# ====================================================
# Uninstall Everything
# ====================================================
uninstall_all() {
    log "Fixing broken dependencies (if any)..."
    sudo apt --fix-broken install -y || true
    
    log "Removing NVIDIA Drivers and Libraries"
    sudo apt purge -y nvidia-* libnvidia-* || true
    
    log "Removing CUDA Toolkit"
    sudo apt purge -y cuda* libcublas* libcusparse* libnccl* || true
    sudo rm -rf /usr/local/cuda* || true
    
    log "Removing Docker"
    sudo apt purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || true
    sudo rm -rf /var/lib/docker /var/lib/containerd /etc/docker || true
    sudo rm -f /etc/apt/keyrings/docker.gpg
    sudo rm -f /etc/apt/sources.list.d/docker.list
    
    log "Removing NVIDIA Container Toolkit"
    uninstall_toolkit
    sudo rm -rf /etc/nvidia-container-runtime || true
    
    log " autoremove cleanup"
    sudo apt autoremove --purge -y || true
    
}
uninstall_toolkit() {
    # Purge all related packages
    sudo apt purge -y \
        nvidia-container-toolkit \
        nvidia-container-toolkit-base \
        libnvidia-container-tools \
        libnvidia-container1 || true
    
    # Remove APT source list
    sudo rm -f /etc/apt/sources.list.d/nvidia-container-toolkit.list
   
    # Remove keyring
    sudo rm -f /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    
    # Clean dependencies
    sudo apt autoremove --purge -y || true

    log "NVIDIA Container Toolkit fully uninstalled."
}


# ====================================================
# Install Driver 580
# ====================================================
install_driver() {
    log "Installing dependencies"
    sudo apt install -y linux-headers-$(uname -r) build-essential dkms software-properties-common
    
    log "Adding graphics drivers PPA"
    sudo add-apt-repository -y ppa:graphics-drivers/ppa
    sudo apt update
    
    log "Installing NVIDIA Driver 580-open"
    sudo apt install -y nvidia-driver-580-open
    task_record "driver_580"
}

# ====================================================
# Install CUDA 13
# ====================================================
install_cuda() {
    log "Installing CUDA 13 keyring"
    UBUNTU_VER=$(lsb_release -rs | tr -d '.\r')
    # Cap Ubuntu version at 2404 for CUDA repo compatibility
    if [ "$UBUNTU_VER" -gt "2404" ]; then
        UBUNTU_VER="2404"
    fi
    wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu${UBUNTU_VER}/x86_64/cuda-keyring_1.1-1_all.deb
    sudo dpkg -i cuda-keyring_1.1-1_all.deb
    sudo apt update
    
    log "Installing CUDA Toolkit 13.x"
    sudo apt install -y cuda-toolkit-13-0
    task_record "cuda13"
    
    log "Configuring CUDA environment variables"
    sudo bash -c 'cat > /etc/profile.d/cuda.sh <<EOF
export CUDA_HOME=/usr/local/cuda
export PATH=/usr/local/cuda/bin:\$PATH
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:\$LD_LIBRARY_PATH
EOF'

	log "Cleaning keyring deb"
	rm -f cuda-keyring_1.1-1_all.deb
}

# ====================================================
# Install Docker
# ====================================================
install_docker() {
    log "Setting up Docker repo"
    sudo apt install -y ca-certificates curl gnupg lsb-release
    sudo install -m 0755 -d /etc/apt/keyrings
    
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    sudo gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
    
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu \
$(lsb_release -cs) stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    task_record "docker"
    
    log "Adding current user to docker group"
    sudo usermod -aG docker "${SUDO_USER:-$USER}"
}

# ====================================================
# Install NVIDIA Container Toolkit 1.17.8
# ====================================================
install_toolkit() {
    log "Installing NVIDIA Container Toolkit"
    
    # Remove old list to avoid duplicate entries
    sudo rm -f /etc/apt/sources.list.d/nvidia-container-toolkit.list
    
    # Always use LC_ALL=C to avoid locale breaking sed/curl
    export LC_ALL=C
    
    # --- Download and install key ---
    curl -fsSL "https://nvidia.github.io/libnvidia-container/gpgkey" \
        | sudo gpg --dearmor --yes -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    
    # --- Write source list (fail-proof version) ---
    curl -fsSL "https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list" \
        | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#' \
        | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list >/dev/null
    
    sudo apt update

    # Version pinning (optional, can be removed)
    VERSION="1.17.8-1"

    sudo apt install -y \
        nvidia-container-toolkit="$VERSION" \
        nvidia-container-toolkit-base="$VERSION" \
        libnvidia-container-tools="$VERSION" \
        libnvidia-container1="$VERSION"

    # Configure Docker runtime
    sudo nvidia-ctk runtime configure --runtime=docker
    sudo systemctl restart docker

    log "Verifying NVIDIA Container Toolkit installation"
    if ! nvidia-ctk --version; then
        echo "Error: NVIDIA Container Toolkit install failed"
        exit 1
    fi

    task_record "toolkit_1_17_8"
}


# ====================================================
# Main
# ====================================================
if [[ "$1" == "install" ]]; then
    log "Starting NVIDIA Environment Setup"

    install_driver
    install_cuda
    install_docker
    install_toolkit

    log "Installation complete! Please reboot."
	sudo apt clean
    exit 0
fi

if [[ "$1" == "uninstall" ]]; then
    uninstall_all
    exit 0
fi

echo "Usage: sudo ./setup_nv_env.sh [install|uninstall]"

echo "Notes on error handling:"
echo "- The script uses 'set -e' and 'set -o pipefail' to stop immediately on any command failure."
echo "- The 'trap' function reports the line number and exit code of any error."
echo "- All output and errors are logged to $LOG_FILE."
