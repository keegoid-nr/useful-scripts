#!/bin/bash
# SJM Cron Job
# Helps to keep Docker clean and the SJM updated.
# Can also be used to start the SJM.
#
# Author : Keegan Mullaney
# Company: New Relic
# Email  : kmullaney@newrelic.com
# Website: github.com/keegoid-nr/useful-scripts
# License: Apache License 2.0

# Usage function
function usage {
  echo "Usage: $0 [SJM_CONTAINER_NAME] [SJM_PRIVATE_LOCATION_KEY]"
  echo "This script helps to keep Docker clean and the Synthetics Job Manager (SJM) updated."
  echo "It can also be used to start the SJM."
  echo
  echo "Arguments:"
  echo "  SJM_CONTAINER_NAME         (Optional) The name for the SJM container. Defaults to YOUR_SJM_CONTAINER_NAME."
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
DEFAULT_SJM_PRIVATE_LOCATION_KEY="YOUR_SJM_PRIVATE_LOCATION_KEY"
SJM_IMAGE="newrelic/synthetics-job-manager:latest"

# Use provided command-line arguments or fallback to default values
SJM_CONTAINER_NAME="${1:-$DEFAULT_SJM_CONTAINER_NAME}"
SJM_PRIVATE_LOCATION_KEY="${2:-$DEFAULT_SJM_PRIVATE_LOCATION_KEY}"

# A recursive function to stop all containers and prune containers, images, and networks not in use until no docker containers exist.
function stop_and_prune_containers {
  local cnt=${1:-1} # Initialize counter or get it as an argument
  echo "recursive loop: $cnt"

  # stop only SJM-related containers
  docker stop $(docker ps -qf 'label=application=synthetics-job-manager') 2>/dev/null
  docker stop $(docker ps -qf 'label=application=synthetics-ping-runtime') 2>/dev/null
  docker stop $(docker ps -qf 'ancestor=newrelic/synthetics-node-api-runtime') 2>/dev/null
  docker stop $(docker ps -qf 'ancestor=newrelic/synthetics-node-browser-runtime') 2>/dev/null

  # prune containers, images, and networks not in use
  docker system prune -af

  # check if SJM-related containers still exist
  if [ "$(docker ps -aqf 'label=application=synthetics-job-manager')" ] || [ "$(docker ps -aqf 'label=application=synthetics-ping-runtime')" ] || [ "$(docker ps -aqf 'ancestor=newrelic/synthetics-node-api-runtime')" ] || [ "$(docker ps -aqf 'ancestor=newrelic/synthetics-node-browser-runtime')" ]; then
    stop_and_prune_containers $((cnt+1)) # recursively call function with incremented counter until no SJM containers exist
  fi
}

# A function to pull the runtime images
function pull_images {
  docker pull newrelic/synthetics-ping-runtime:latest 2>/dev/null
  docker pull newrelic/synthetics-node-api-runtime:latest 2>/dev/null
  docker pull newrelic/synthetics-node-browser-runtime:latest 2>/dev/null
}

# stop and prune all containers until none exist
stop_and_prune_containers

# pull the runtime images before starting the job manager to avoid timeouts on slow connections
# in conjunction with --pull missing, this will allow the job manager to quickly skip over the pulling of images on startup
pull_images

# start new job manager to support monitoring activities
docker run --name "${SJM_CONTAINER_NAME}" \
  -e PRIVATE_LOCATION_KEY=$SJM_PRIVATE_LOCATION_KEY \
  -v /var/run/docker.sock:/var/run/docker.sock:rw \
  -p 8080:8080 \
  -p 8082:8082 \
  -d --restart unless-stopped --pull missing \
  --log-opt tag="{{.Name}}/{{.ID}}" \
  $SJM_IMAGE | tee -a docker-run.log 2>&1
