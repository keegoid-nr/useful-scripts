#!/bin/bash
# -----------------------------------------------------
# SJM Cron Job
# Helps to keep Docker clean and the SJM updated.
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
  if [ "$(docker ps -qf 'label=application=synthetics-job-manager')" ] || [ "$(docker ps -qf 'label=application=synthetics-ping-runtime')" ] || [ "$(docker ps -qf 'ancestor=newrelic/synthetics-node-api-runtime')" ] || [ "$(docker ps -qf 'ancestor=newrelic/synthetics-node-browser-runtime')" ]; then
    stop_and_prune_containers $((cnt+1)) # recursively call function with incremented counter until no SJM containers exist
  fi
}

# stop and prune all containers until none exist
stop_and_prune_containers

# start new job manager to support monitoring activities
docker run --name $SJM_CONTAINER_NAME \
  -e PRIVATE_LOCATION_KEY=$SJM_PRIVATE_LOCATION_KEY \
  -v /var/run/docker.sock:/var/run/docker.sock:rw \
  -p 8080:8080 \
  -p 8082:8082 \
  -d --restart unless-stopped \
  --log-opt tag="{{.Name}}/{{.ID}}" \
  $SJM_IMAGE | tee -a docker-run.log 2>&1

# This script can be run in one of two ways:
  # 1. save it to a file and replace global variables with your values, or
  # 2. run with curl and supply variables with command-line arguments

# To run with curl:
  # curl -sSL https://raw.githubusercontent.com/keegoid-nr/useful-scripts/main/sjm-cron-job.sh | bash -s -- "YOUR_CONTAINER_NAME" "YOUR_PRIVATE_LOCATION_KEY"
