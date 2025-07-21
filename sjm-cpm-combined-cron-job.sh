#!/bin/bash

# SJM/CPM Cron Job
# Helps to keep Docker clean and the SJM/CPM updated.
# Can also be used to start the SJM/CPM.
#
# Author : Keegan Mullaney
# Company: New Relic
# Email  : kmullaney@newrelic.com
# Website: github.com/keegoid-nr/useful-scripts
# License: Apache License 2.0


# Default values for global variables
DEFAULT_SJM_CONTAINER_NAME="YOUR_SJM_CONTAINER_NAME"
DEFAULT_SJM_PRIVATE_LOCATION_KEY="YOUR_SJM_PRIVATE_LOCATION_KEY"
DEFAULT_CPM_CONTAINER_NAME="YOUR_CPM_CONTAINER_NAME"
DEFAULT_CPM_PRIVATE_LOCATION_KEY="YOUR_CPM_PRIVATE_LOCATION_KEY"
SJM_IMAGE="newrelic/synthetics-job-manager:latest"
CPM_IMAGE="quay.io/newrelic/synthetics-minion:latest"

# Use provided command-line arguments or fallback to default values
SJM_CONTAINER_NAME="${1:-$DEFAULT_SJM_CONTAINER_NAME}"
SJM_PRIVATE_LOCATION_KEY="${2:-$DEFAULT_SJM_PRIVATE_LOCATION_KEY}"
CPM_CONTAINER_NAME="${3:-$DEFAULT_CPM_CONTAINER_NAME}"
CPM_PRIVATE_LOCATION_KEY="${4:-$DEFAULT_CPM_PRIVATE_LOCATION_KEY}"

# A recursive function to stop all containers and prune containers, images, and networks not in use until no docker containers exist.
function stop_and_prune_containers {
  local cnt=${1:-1} # Initialize counter or get it as an argument
  echo "recursive loop: $cnt"

  # stop all containers (assuming this host is dedicated to the SJM)
  docker stop $(docker ps -aq) 2>/dev/null

  # prune containers, images, and networks not in use
  docker system prune -af

  # check if any containers still exist
  if [ "$(docker ps -aqf)" ]; then
    stop_and_prune_containers $((cnt+1)) # recursively call function with incremented counter until no containers exist
  fi
}

# stop and prune all containers until none exist
stop_and_prune_containers

# create bridge networks
# note that running the SJM and CPM on the same host may lead to instability and other unexpected issues
# the recommended approach is to use separate hosts or VMs if you can
docker network create sjm-bridge
docker network create cpm-bridge

# start new job manager to support monitoring activities
# avoid using sudo with the docker run command since containers spawned by the job manager won't inherit elevated permissions
# set HEAVYWEIGHT_WORKERS to half the number of cpu cores on your host to avoid resource contention with the CPM
# the log-opt tag will make it easier to find container logs if forwarding to New Relic
# ports 8080 and 8082 expose admin endpoints like http://localhost:8080/status/check and http://localhost:8082/healthcheck?pretty=true
docker run --name "${SJM_CONTAINER_NAME}" \
  -e PRIVATE_LOCATION_KEY=$SJM_PRIVATE_LOCATION_KEY \
  -e HEAVYWEIGHT_WORKERS=1 \
  -e LOG_LEVEL=INFO \
  -v /var/run/docker.sock:/var/run/docker.sock:rw \
  --network sjm-bridge \
  -p 8080:8080 -p 8082:8082 \
  -d --restart unless-stopped --log-opt tag="{{.Name}}/{{.ID}}" \
  $SJM_IMAGE | tee -a sjm-docker-run.log 2>&1

# start a new minion to support monitoring activities
# avoid using sudo with the docker run command since containers spawned by the minion won't inherit elevated permissions
# set MINION_HEAVY_WORKERS to half the number of cpu cores on your host to avoid resource contention with the SJM
# the log-opt tag will make it easier to find container logs if forwarding to New Relic
# 8080 and 8180 expose admin endpoints like http://localhost:8080/status/check and http://localhost:8180/healthcheck?pretty=true
# map port 8081 to avoid port conflicts with SJM
docker run --name "${CPM_CONTAINER_NAME}" \
  -e MINION_PRIVATE_LOCATION_KEY=$CPM_PRIVATE_LOCATION_KEY \
  -e MINION_HEAVY_WORKERS=1 \
  -e MINION_LOG_LEVEL=INFO \
  -v /tmp:/tmp:rw \
  -v /var/run/docker.sock:/var/run/docker.sock:rw \
  --network cpm-bridge \
  -p 8081:8080 -p 8180:8180 \
  -d --restart unless-stopped --log-opt tag="{{.Name}}/{{.ID}}" \
  $CPM_IMAGE | tee -a cpm-docker-run.log 2>&1

# This script can be run in one of two ways:
  # 1. save it to a file and replace global variables with your values, or
  # 2. run with curl and supply variables with command-line arguments

# To run with curl:
  # curl -sSL https://raw.githubusercontent.com/keegoid-nr/useful-scripts/main/sjm-cpm-combined-cron-job.sh | bash -s -- "YOUR_SJM_CONTAINER_NAME" "YOUR_SJM_PRIVATE_LOCATION_KEY" "YOUR_CPM_CONTAINER_NAME" "YOUR_CPM_PRIVATE_LOCATION_KEY"
