# NVIDIA Developer Environment Auto Setup
the script works on **Ubuntu OS** (tested on 2404 server & desktop)

This repository contains a script to automatically install or uninstall NVIDIA development environment components:
- NVIDIA Driver 580
- CUDA 13.x
- Docker CE
- NVIDIA Container Toolkit 1.17.8

## Compatibility
- **Supported OS:** Ubuntu 22.04 LTS, Ubuntu 24.04 LTS
- **Unsupported:** Ubuntu 20.04 (too old), Ubuntu 25.xx (too new/unstable)
- **Architecture:** x86_64 only

## Usage

### Install
```bash
chmod +x setup_nv_env.sh
sudo ./setup_nv_env.sh install
```

**Options:**
- `--no-cuda`: Skips installing the CUDA Toolkit (useful for Docker-only workflows).
- `--force`: Bypasses the OS version check (use at your own risk).

### Uninstall
```bash
sudo ./setup_nv_env.sh uninstall
```

## Logs

Installation and uninstallation logs are stored in the `logs/` directory within the repository.
- `logs/install.log`: Detailed log of operations.
- `logs/installed.list`: List of successfully installed components.

These files and the repository itself are preserved after uninstallation.
