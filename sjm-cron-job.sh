#!/bin/bash
# -----------------------------------------------------
# SJM Cron Job
# Helps to keep docker clean and the SJM updated.
# Can also be used to start the SJM.
#
# Author : Keegan Mullaney
# Company: New Relic
# Email  : kmullaney@newrelic.com
# Website: github.com/keegoid-nr/useful-scripts
# License: MIT
# -----------------------------------------------------

# A recursive function to stop all containers and prune containers, images, and networks not in use until no docker containers exist.
function stop_and_prune_containers {
  local cnt=${1:-1} # Initialize counter or get it as an argument
  echo "recursive loop: $cnt"

  # stop all containers (assuming this host is dedicated to the SJM)
  # docker stop $(docker ps -aq) 2>/dev/null

  # stop only SJM-related containers
  docker stop $(docker ps -qf 'label=application=synthetics-job-manager') 2>/dev/null
  docker stop $(docker ps -qf 'label=application=synthetics-ping-runtime') 2>/dev/null
  docker stop $(docker ps -qf 'ancestor=newrelic/synthetics-node-api-runtime') 2>/dev/null
  docker stop $(docker ps -qf 'ancestor=newrelic/synthetics-node-browser-runtime') 2>/dev/null

  # prune containers, images, and networks not in use
  docker system prune -af

  # # check if any containers still exist
  # if [ "$(docker ps -aq)" ]; then
  #   stop_and_prune_containers # recursively call function until no containers exist
  # fi

  # check if SJM-related containers still exist
  if [ "$(docker ps -qf 'label=application=synthetics-job-manager')" ] || [ "$(docker ps -qf 'label=application=synthetics-ping-runtime')" ] || [ "$(docker ps -qf 'ancestor=newrelic/synthetics-node-api-runtime')" ] || [ "$(docker ps -qf 'ancestor=newrelic/synthetics-node-browser-runtime')" ]; then
    stop_and_prune_containers $((cnt+1)) # recursively call function with incremented counter until no SJM containers exist
  fi
}

# stop and prune all containers until none exist
stop_and_prune_containers

# start new job manager to support monitoring activities
# avoid using sudo with the docker run command since containers spawned by the job manager won't inherit elevated permissions
# the log-opt tag will make it easier to find container logs if forwarding to New Relic
# ports 8080 and 8082 expose admin endpoints like http://localhost:8080/status/check and http://localhost:8082/healthcheck?pretty=true
docker run --name YOUR_CONTAINER_NAME -e PRIVATE_LOCATION_KEY=YOUR_PRIVATE_LOCATION_KEY -v /var/run/docker.sock:/var/run/docker.sock:rw -p 8080:8080 -p 8082:8082 -d --restart unless-stopped --log-opt tag="{{.Name}}/{{.ID}}" newrelic/synthetics-job-manager:latest | tee -a docker-run.log 2>&1
