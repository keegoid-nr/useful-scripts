#!/bin/bash
# SJM Cron Job for Podman
# Helps to keep Podman clean and the SJM updated.
# Can also be used to start the SJM.
#
# Author : Keegan Mullaney
# Company: New Relic
# Email  : kmullaney@newrelic.com
# Website: github.com/keegoid-nr/useful-scripts
# License: Apache License 2.0
#
# Make sure you've completed the necessary pre-requisites:
# https://docs.newrelic.com/docs/synthetics/synthetic-monitoring/private-locations/install-job-manager/#podman-dependencies

# Usage function
function usage {
  echo "Usage: $0 [SJM_CONTAINER_NAME] [SJM_POD_NAME] [HOST_IP_ADDRESS] [SJM_PRIVATE_LOCATION_KEY]"
  echo "This script helps to keep Podman clean and the Synthetics Job Manager (SJM) updated."
  echo "It can also be used to start the SJM."
  echo
  echo "Arguments:"
  echo "  SJM_CONTAINER_NAME         (Optional) The name for the SJM container. Defaults to YOUR_SJM_CONTAINER_NAME."
  echo "  SJM_POD_NAME               (Optional) The name for the SJM pod. Defaults to YOUR_SJM_POD_NAME."
  echo "  HOST_IP_ADDRESS            (Optional) The IP address of your host. Defaults to YOUR_HOST_IP_ADDRESS."
  echo "  SJM_PRIVATE_LOCATION_KEY   (Optional) Your Synthetics private location key. Defaults to YOUR_SJM_PRIVATE_LOCATION_KEY."
  echo
  echo "Options:"
  echo "  -h, --help                 Display this help message."
}

# Check for help flag
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  usage
  exit 0
fi

# Default values for global variables
DEFAULT_SJM_CONTAINER_NAME="YOUR_SJM_CONTAINER_NAME"
DEFAULT_SJM_POD_NAME="YOUR_SJM_POD_NAME"
DEFAULT_HOST_IP_ADDRESS="YOUR_HOST_IP_ADDRESS"
DEFAULT_SJM_PRIVATE_LOCATION_KEY="YOUR_SJM_PRIVATE_LOCATION_KEY"
SJM_IMAGE="docker.io/newrelic/synthetics-job-manager:latest"

# Use provided command-line arguments or fallback to default values
SJM_CONTAINER_NAME="${1:-$DEFAULT_SJM_CONTAINER_NAME}"
SJM_POD_NAME="${2:-$DEFAULT_SJM_POD_NAME}"
HOST_IP_ADDRESS="${3:-$DEFAULT_HOST_IP_ADDRESS}"
SJM_PRIVATE_LOCATION_KEY="${4:-$DEFAULT_SJM_PRIVATE_LOCATION_KEY}"

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

# A function to pull the runtime images
function pull_images {
  podman pull docker.io/newrelic/synthetics-ping-runtime:latest
  podman pull docker.io/newrelic/synthetics-node-api-runtime:latest
  podman pull docker.io/newrelic/synthetics-node-browser-runtime:latest
}

# Stop and prune existing containers and pods
stop_and_prune_containers

# pull the runtime images before starting the job manager to avoid timeouts on slow connections
# in conjunction with --pull missing, this will allow the job manager to quickly skip over the pulling of images on startup
pull_images

# Create a new pod with port mappings and host entry for Podman API
# Replace HOST_IP_ADDRESS with the actual IP address of your host
# If using WSL2 in Windows, access the Linux distribution `wsl -d Ubuntu-24.04` then find the IP address with `ip a s eth0 | grep inet`
podman pod create --network slirp4netns --name "$SJM_POD_NAME" --add-host=podman.service:"$HOST_IP_ADDRESS" -p 8080:8080 -p 8082:8082

# Start new job manager to support monitoring activities
podman run \
    --name "$SJM_CONTAINER_NAME" \
    --pod "$SJM_POD_NAME" \
    -e "PRIVATE_LOCATION_KEY=$SJM_PRIVATE_LOCATION_KEY" \
    -e "CONTAINER_ENGINE=PODMAN" \
    -e "PODMAN_API_SERVICE_PORT=8000" \
    -e "PODMAN_POD_NAME=$SJM_POD_NAME" \
    -d --restart unless-stopped --pull missing \
    "$SJM_IMAGE" | tee -a podman-run.log 2>&1
