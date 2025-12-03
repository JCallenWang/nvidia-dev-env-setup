# NVIDIA Developer Environment Auto Setup
the script works on **Ubuntu Desktop OS**

This repository contains a script to automatically install or uninstall NVIDIA development environment components:
- NVIDIA Driver 580
- CUDA 13.x
- Docker CE
- NVIDIA Container Toolkit 1.17.8

## Usage

After cloning the repository:

```bash
# Change to repository directory
cd nvidia-dev-env-setup

# Install environment
sudo bash setup_nv_env.sh install

# Uninstall environment
sudo bash setup_nv_env.sh uninstall

## Logs

Installation and uninstallation logs are stored in the `logs/` directory within the repository.
- `logs/install.log`: Detailed log of operations.
- `logs/installed.list`: List of successfully installed components.

These files and the repository itself are preserved after uninstallation.
