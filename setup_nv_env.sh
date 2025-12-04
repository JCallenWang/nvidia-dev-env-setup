#!/bin/bash
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
    
    log "Removing logs directory"
    rm -rf "$LOG_DIR" || true
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
# ====================================================
# Setup NVIDIA Repository (Shared)
# ====================================================
setup_nvidia_repo() {
    log "Setting up NVIDIA Official Repository"
    UBUNTU_VER=$(lsb_release -rs | tr -d '.\r')
    # Cap Ubuntu version at 2404 for repo compatibility
    if [ "$UBUNTU_VER" -gt "2404" ]; then
        UBUNTU_VER="2404"
    fi
    
    # Remove PPA if present to avoid conflicts
    if grep -q "graphics-drivers/ppa" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
        log "Removing graphics-drivers PPA..."
        sudo add-apt-repository --remove -y ppa:graphics-drivers/ppa || true
    fi

    # Install keyring
    wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu${UBUNTU_VER}/x86_64/cuda-keyring_1.1-1_all.deb
    sudo dpkg -i cuda-keyring_1.1-1_all.deb
    sudo apt update
    rm -f cuda-keyring_1.1-1_all.deb
}

# ====================================================
# Install Driver 580
# ====================================================
install_driver() {
    log "Installing dependencies"
    sudo apt install -y linux-headers-$(uname -r) build-essential dkms software-properties-common

    setup_nvidia_repo
    
    log "Installing NVIDIA Driver 580-open (from Official Repo)"
    sudo apt install -y nvidia-driver-580-open
    task_record "driver_580"
}

# ====================================================
# Install CUDA 13
# ====================================================
install_cuda() {
    # Repo is already set up by install_driver, but ensure it's there if run standalone
    if ! dpkg -l | grep -q cuda-keyring; then
        setup_nvidia_repo
    fi
    
    log "Installing CUDA Toolkit 13.x"
    sudo apt install -y cuda-toolkit-13-0
    task_record "cuda13"
    
    log "Configuring CUDA environment variables"
    sudo bash -c 'cat > /etc/profile.d/cuda.sh <<EOF
export CUDA_HOME=/usr/local/cuda
export PATH=/usr/local/cuda/bin:\$PATH
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:\$LD_LIBRARY_PATH
EOF'
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
    
    # --- Download and install key (with retry) ---
    local max_retries=5
    local count=0
    local success=false

    while [ $count -lt $max_retries ]; do
        if curl -fsSL -4 "https://nvidia.github.io/libnvidia-container/gpgkey" | sudo gpg --dearmor --yes -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg; then
            success=true
            break
        fi
        log "Download failed (Attempt $((count+1))/$max_retries). Retrying in 5 seconds..."
        sleep 5
        ((++count))
    done

    if [ "$success" = false ]; then
        echo "Error: Failed to download NVIDIA GPG key after $max_retries attempts."
        exit 1
    fi

    # --- Write source list (fail-proof version) ---
    curl -fsSL -4 "https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list" \
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

    # --- OS Version Check ---
    UBUNTU_VER=$(lsb_release -rs | tr -d '.\r')
    FORCE_INSTALL=false
    NO_CUDA=false

    # Parse flags
    for arg in "$@"; do
        if [[ "$arg" == "--force" ]]; then FORCE_INSTALL=true; fi
        if [[ "$arg" == "--no-cuda" ]]; then NO_CUDA=true; fi
    done

    # Strict Version Check (Allow 22.04 and 24.04 only)
    if [[ "$UBUNTU_VER" != "2204" && "$UBUNTU_VER" != "2404" ]]; then
        if [[ "$FORCE_INSTALL" == "true" ]]; then
            log "WARNING: Unsupported Ubuntu version ($UBUNTU_VER) detected."
            log "Continuing because --force was specified. Expect issues."
            sleep 3
        else
            echo "ERROR: This script officially supports only Ubuntu 22.04 LTS and 24.04 LTS."
            echo "Detected version: $(lsb_release -rs)"
            echo "Use '--force' to override this check at your own risk."
            exit 1
        fi
    fi

    install_driver
    
    if [[ "$NO_CUDA" == "true" ]]; then
        log "Skipping CUDA Toolkit installation (--no-cuda flag detected)"
    else
        install_cuda
    fi

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

echo "Usage: sudo ./setup_nv_env.sh [install|uninstall] [--no-cuda] [--force]"

echo "Notes on error handling:"
echo "- The script uses 'set -e' and 'set -o pipefail' to stop immediately on any command failure."
echo "- The 'trap' function reports the line number and exit code of any error."
echo "- All output and errors are logged to $LOG_FILE."
