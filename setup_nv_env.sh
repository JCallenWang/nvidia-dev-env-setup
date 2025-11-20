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

LOG_DIR="/var/log/nvidia_env_setup"
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
    log "Removing NVIDIA Drivers"
    sudo apt purge -y nvidia-* || true

    log "Removing CUDA Toolkit"
    sudo apt purge -y cuda-* libcublas* libcusparse* libnccl* || true
    sudo rm -rf /usr/local/cuda* || true

    log "Removing Docker"
    sudo apt purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || true
    sudo rm -rf /var/lib/docker /var/lib/containerd || true

    log "Removing NVIDIA Container Toolkit"
    sudo apt purge -y nvidia-container-toolkit* || true
    sudo rm -f /etc/apt/sources.list.d/nvidia-container-toolkit.list || true

    log " autoremove cleanup"
    sudo apt autoremove -y

    log "Clean complete"
    rm -f "$INSTALL_RECORD"
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
    UBUNTU_VER=$(lsb_release -rs | sed 's/\\.//g')
    wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu$UBUNTU_VER/x86_64/cuda-keyring_1.1-1_all.deb
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
    sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu \
$(lsb_release -cs) stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    task_record "docker"

	log "Cleaning Docker GPG key (keep rop list for future udpate)"
	sudo rm -f /etc/apt/keyrings/docker.gpg
}

# ====================================================
# Install NVIDIA Container Toolkit 1.17.8
# ====================================================
install_toolkit() {
    log "Installing NVIDIA Container Toolkit"
    sudo rm -f /etc/apt/sources.list.d/nvidia-container-toolkit.list

    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
    sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

    sudo apt update

    VERSION=1.17.8-1
    sudo apt install -y \
        nvidia-container-toolkit=$VERSION \
        nvidia-container-toolkit-base=$VERSION \
        libnvidia-container-tools=$VERSION \
        libnvidia-container1=$VERSION

    sudo nvidia-ctk runtime configure --runtime=docker
    sudo systemctl restart docker
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

echo "Usage: sudo ./nvidia_env_setup.sh [install|uninstall]"
echo "if first deployed, give the script permission to execute by running this command:"
echo "chmod +x setup_nvidia_env.sh"

echo "Notes on error handling:"
echo "- The script uses 'set -e' and 'set -o pipefail' to stop immediately on any command failure."
echo "- The 'trap' function reports the line number and exit code of any error."
echo "- All output and errors are logged to $LOG_FILE."
