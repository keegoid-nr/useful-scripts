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

# A recursive function to stop all containers and prune containers, images, and networks not in use until no docker containers exist.
function stop_and_prune_containers {
  # stop all containers (assuming this host is dedicated to the CPM)
  docker stop $(docker ps -aq) 2>/dev/null

  # prune containers, images, and networks not in use
  docker system prune -af

  # check if any containers still exist
  if [ "$(docker ps -aq)" ]; then
    stop_and_prune_containers # recursively call function until no containers exist
  fi
}

# stop and prune all containers until none exist
stop_and_prune_containers

# start new job manager to support monitoring activities
# avoid using sudo with the docker run command since containers spawned by the minion won't inherit elevated permissions
docker run --name YOUR_CONTAINER_NAME -e MINION_PRIVATE_LOCATION_KEY=YOUR_PRIVATE_LOCATION_KEY -v /tmp:/tmp:rw -v /var/run/docker.sock:/var/run/docker.sock:rw -d --restart unless-stopped quay.io/newrelic/synthetics-minion:latest
