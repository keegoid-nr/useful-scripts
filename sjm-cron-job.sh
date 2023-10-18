#!/usr/bin/env bash
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

# A function to stop and delete all synthetics containers and images, plus prune volumes and networks not in use.
function stop_and_prune_containers {
  # stop and delete all containers related to New Relic Synthetics
  for i in $(docker inspect --format="{{.ID}} {{.Config.Image}}" $(docker ps -aq) | grep "newrelic/synthetics" | awk '{print $1}'); do
    docker stop "$i" 2>/dev/null
    docker rm -f "$i" 2>/dev/null
  done

  # remove all synthetics-related images
  docker image rm -f $(docker images | grep "newrelic/synthetics" | awk '{print $1}')

  # prune unused Docker volumes
  docker volume prune -af

  # prune unused networks
  docker network prune -f
}

# stop and prune all containers
stop_and_prune_containers

# start new job manager to support monitoring activities
# avoid using sudo with the docker run command since containers spawned by the job manager won't inherit elevated permissions
docker run --name YOUR_CONTAINER_NAME -e PRIVATE_LOCATION_KEY=YOUR_PRIVATE_LOCATION_KEY -v /var/run/docker.sock:/var/run/docker.sock:rw -d --restart unless-stopped newrelic/synthetics-job-manager:latest
