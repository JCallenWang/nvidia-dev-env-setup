#!/bin/bash

# 0. Ask and save sudo password at the beginning
echo
echo "Please enter your sudo password for the following installation steps."
# Read password silently
read -s -p "[sudo] password: " SUDO_PASS
echo

# Validate password and update sudo timestamp
if ! echo "$SUDO_PASS" | sudo -S -v 2>/dev/null; then
    echo "Incorrect password. Exiting."
    exit 1
fi

# Keep sudo timestamp alive in the background while script runs
( while true; do sleep 60; echo "$SUDO_PASS" | sudo -S -v; done ) &
SUDO_KEEPALIVE_PID=$!

# Cleanup function to kill the keepalive background process on exit
cleanup() {
    kill $SUDO_KEEPALIVE_PID
}
trap cleanup EXIT

# 1. Check if git is installed, install if not
if ! command -v git &> /dev/null; then
    echo "Git is not installed. Attempting to install..."
    if [ -x "$(command -v apt-get)" ]; then
        sudo apt-get update && sudo apt-get install -y git
    elif [ -x "$(command -v yum)" ]; then
        sudo yum install -y git
    elif [ -x "$(command -v pacman)" ]; then
        sudo pacman -S --noconfirm git
    else
        echo "Error: Could not detect package manager. Please install git manually."
        exit 1
    fi
else
    echo "Git is already installed."
fi

# 2. Git clone the repository
REPO_URL="https://github.com/JCallenWang/nvidia-dev-env-setup.git"
DIR_NAME="nvidia-dev-env-setup"

if [ -d "$DIR_NAME" ]; then
    echo "Directory '$DIR_NAME' already exists. Skipping clone."
else
    echo "Cloning $REPO_URL..."
    git clone "$REPO_URL"
fi

# 3. cd into directory and run uninstall
cd "$DIR_NAME" || { echo "Failed to enter directory $DIR_NAME"; exit 1; }

echo "Running uninstall..."
sudo bash setup_nv_env.sh uninstall

# 4. Run install
echo "Running install..."
sudo bash setup_nv_env.sh install

# 5. Cleanup repository
# Repository is preserved to keep logs and scripts for future use.
# cd ..
# if [ -d "$DIR_NAME" ]; then
#     echo "Removing repository directory '$DIR_NAME'..."
#     sudo rm -rf "$DIR_NAME"
# fi

echo "Setup completed successfully."
