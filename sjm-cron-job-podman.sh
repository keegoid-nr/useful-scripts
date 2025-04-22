#!/bin/bash
# -----------------------------------------------------
# SJM Cron Job for Podman
# Helps to keep Podman clean and the SJM updated.
# Can also be used to start the SJM.
#
# Author : Keegan Mullaney
# Company: New Relic
# Email  : kmullaney@newrelic.com
# Website: github.com/keegoid-nr/useful-scripts
# License: MIT
# -----------------------------------------------------

# Default values for global variables
DEFAULT_SJM_CONTAINER_NAME="YOUR_SJM_CONTAINER_NAME"
DEFAULT_SJM_POD_NAME="YOUR_SJM_POD_NAME"
DEFAULT_SJM_PRIVATE_LOCATION_KEY="YOUR_SJM_PRIVATE_LOCATION_KEY"
SJM_IMAGE="docker.io/newrelic/synthetics-job-manager:latest"

# Use provided command-line arguments or fallback to default values
SJM_CONTAINER_NAME="${1:-$DEFAULT_SJM_CONTAINER_NAME}"
SJM_POD_NAME="${2:-$DEFAULT_SJM_POD_NAME}"
SJM_PRIVATE_LOCATION_KEY="${3:-$DEFAULT_SJM_PRIVATE_LOCATION_KEY}"

# Function to stop and prune containers and pods
function stop_and_prune_containers {
    # Stop and remove the pod if it exists
    if podman pod exists "$SJM_POD_NAME"; then
        podman pod stop "$SJM_POD_NAME" 2>/dev/null
        podman pod rm -f "$SJM_POD_NAME" 2>/dev/null
    fi
    # Prune containers, images, and networks not in use
    podman system prune -af
}

# Stop and prune existing containers and pods
stop_and_prune_containers

# Create a new pod with port mappings and host entry for Podman API
podman pod create --network slirp4netns --name "$SJM_POD_NAME" --add-host=podman.service:$(hostname -i) -p 8080:8080 -p 8082:8082

# Start new job manager to support monitoring activities
podman run \
    --name "$SJM_CONTAINER_NAME" \
    --pod "$SJM_POD_NAME" \
    -e "PRIVATE_LOCATION_KEY=$SJM_PRIVATE_LOCATION_KEY" \
    -e "CONTAINER_ENGINE=PODMAN" \
    -e "PODMAN_API_SERVICE_PORT=8000" \
    -e "PODMAN_POD_NAME=$SJM_POD_NAME" \
    -d \
    --restart unless-stopped \
    "$SJM_IMAGE" | tee -a podman-run.log 2>&1

# This script can be run in one of two ways:
# 1. Save it to a file and replace global variables with your values, or
# 2. Run with curl and supply variables with command-line arguments
#
# To run with curl:
# curl -sSL https://raw.githubusercontent.com/keegoid-nr/useful-scripts/main/sjm-cron-job-podman.sh | bash -s -- "YOUR_CONTAINER_NAME" "YOUR_POD_NAME" "YOUR_PRIVATE_LOCATION_KEY"
