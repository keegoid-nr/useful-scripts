#!/bin/bash
# -----------------------------------------------------
# CPM Cron Job
# Helps to keep docker clean and the CPM updated.
# Can also be used to start the CPM.
#
# Author : Keegan Mullaney
# Company: New Relic
# Email  : kmullaney@newrelic.com
# Website: github.com/keegoid-nr/useful-scripts
# License: MIT
# -----------------------------------------------------

# Global variables (edit these variables before running the script)
CONTAINER_NAME="YOUR_CONTAINER_NAME"
PRIVATE_LOCATION_KEY="YOUR_PRIVATE_LOCATION_KEY"
MINION_IMAGE="quay.io/newrelic/synthetics-minion:latest"

# A recursive function to stop all containers and prune containers, images, and networks not in use until no docker containers exist.
function stop_and_prune_containers {
  local cnt=${1:-1} # Initialize counter or get it as an argument
  echo "recursive loop: $cnt"

  # stop only CPM-related containers
  docker stop $(docker ps -qf "label=name=synthetics-minion") 2>/dev/null
  docker stop $(docker ps -qf "label=name=synthetics-minion-runner") 2>/dev/null

  # prune containers, images, and networks not in use
  docker system prune -af

  # check if CPM-related containers still exist
  if [ "$(docker ps -qf 'label=name=synthetics-minion')" ] || [ "$(docker ps -qf 'label=name=synthetics-minion-runner')" ]; then
    stop_and_prune_containers $((cnt+1)) # recursively call function with incremented counter until no CPM containers exist
  fi
}

# stop and prune all containers until none exist
stop_and_prune_containers

# start a new minion to support monitoring activities
docker run --name $CONTAINER_NAME \
  -e MINION_PRIVATE_LOCATION_KEY=$PRIVATE_LOCATION_KEY \
  -v /tmp:/tmp:rw \
  -v /var/run/docker.sock:/var/run/docker.sock:rw \
  -p 8080:8080 \
  -p 8180:8180 \
  -d --restart unless-stopped \
  --log-opt tag="{{.Name}}/{{.ID}}" \
  $MINION_IMAGE | tee -a docker-run.log 2>&1
