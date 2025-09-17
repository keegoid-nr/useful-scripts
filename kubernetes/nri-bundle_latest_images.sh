#!/bin/bash
# Quickly check latest nri-bundle sub chart image versions.
#
# Author : Keegan Mullaney
# Company: New Relic
# Email  : kmullaney@newrelic.com
# Website: github.com/keegoid-nr/useful-scripts
# License: Apache License 2.0

# Exit immediately if a command exits with a non-zero status.
set -e

# Define the Helm chart to inspect.
CHART_NAME="nri-bundle"
REPO_NAME="newrelic"
REPO_URL="https://helm-charts.newrelic.com"
RELEASE_NAME="nri-bundle-release" # A temporary release name for templating

# Create a temporary directory for our work
WORK_DIR=$(mktemp -d)

# --- Script Functions ---

# Function to clean up the temporary directory on exit
cleanup() {
  echo "Cleaning up temporary directory..."
  rm -rf "$WORK_DIR"
}

# Register the cleanup function to be called on script exit
trap cleanup EXIT

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to print a formatted message
log() {
    echo "--------------------------------------------------"
    echo "$1"
    echo "--------------------------------------------------"
}

# --- Main Script ---

# 1. Check for required tools
log "Checking for required tools (helm, grep, awk, sort, uniq)..."
for cmd in helm grep awk sort uniq; do
    if ! command_exists "$cmd"; then
        echo "Error: Required command '$cmd' is not installed. Please install it and try again."
        exit 1
    fi
done
echo "All required tools are present."

# 2. Add and Update the New Relic Helm Repo
log "Adding and updating the New Relic Helm repository..."
if ! helm repo list | grep -q "$REPO_NAME"; then
    echo "Adding New Relic Helm repo..."
    helm repo add "$REPO_NAME" "$REPO_URL"
else
    echo "New Relic Helm repo already exists."
fi
helm repo update "$REPO_NAME"
echo "Repo update complete."

# 3. Fetch, Unpack, and Update Dependencies for the Chart
log "Fetching chart and its dependencies locally..."
cd "$WORK_DIR"

# Retry helm pull in case of transient network issues
MAX_RETRIES=3
RETRY_COUNT=0
until helm pull "$REPO_NAME/$CHART_NAME" --untar > /dev/null 2>&1 || [ $RETRY_COUNT -eq $MAX_RETRIES ]; do
  RETRY_COUNT=$((RETRY_COUNT+1))
  echo "helm pull failed. Retrying in 5 seconds... (Attempt $RETRY_COUNT/$MAX_RETRIES)"
  sleep 5
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
  echo "Error: helm pull failed after $MAX_RETRIES attempts."
  exit 1
fi

cd "$CHART_NAME"
helm dependency update
echo "Local chart dependencies are up to date."
cd "$WORK_DIR"


# 4. Render the chart templates and extract image names grouped by chart
log "Templating the '$CHART_NAME' chart to find container images..."
# We use helm template with --debug to get the source file for each manifest.
# We redirect stderr to stdout (2>&1) to ensure all output is piped to awk.
# An awk script then parses this output, stores images in an array grouped by chart,
# and prints the formatted, indented list at the end.
images_by_chart=$(helm template "$RELEASE_NAME" ./"$CHART_NAME" \
    --set global.cluster=temp-cluster-name \
    --set global.licenseKey=dummy-key \
    --set newrelic-infrastructure.enabled=true \
    --set nri-prometheus.enabled=true \
    --set nri-metadata-injection.enabled=true \
    --set kube-state-metrics.enabled=true \
    --set nri-kube-events.enabled=true \
    --set newrelic-logging.enabled=true \
    --set newrelic-pixie.enabled=true \
    --set newrelic-pixie.deployKey=dummy-deploy-key \
    --set newrelic-eapm-agent.enabled=true \
    --set k8s-agents-operator.enabled=true \
    --set newrelic-infra-operator.enabled=true \
    --set newrelic-prometheus-agent.enabled=true \
    --set newrelic-k8s-metrics-adapter.enabled=true \
    --set newrelic-k8s-metrics-adapter.personalAPIKey=dummy-api-key \
    --set newrelic-k8s-metrics-adapter.config.accountID=12345678 \
    --debug 2>&1 | \
    awk '
      # This awk script collects all images and groups them by their source sub-chart.
      # It then prints a formatted, indented list.

      # Set the default chart name for templates in the parent chart
      BEGIN { current_chart="nri-bundle (parent)" }

      # When a "# Source:" line is found, update the current chart name
      /^# Source: / {
          split($3, path_parts, "/")
          if (path_parts[2] == "charts") {
              current_chart = path_parts[3]
          } else {
              current_chart = "nri-bundle (parent)"
          }
      }

      # When an "image:" line is found, clean up the image name and add it to our array.
      # The array key is the chart name, and the value is a growing list of its images.
      /^[ \t]+image:/ {
          gsub(/"|\047/, "", $2) # Remove quotes
          # Only process if the image name is not empty
          if ($2 != "") {
              # If this is the first image for this chart, initialize it. Otherwise, add a newline.
              if (images[current_chart] == "") {
                  images[current_chart] = "\t- " $2
              } else {
                  # Avoid adding duplicates
                  if (index(images[current_chart], $2) == 0) {
                    images[current_chart] = images[current_chart] "\n\t- " $2
                  }
              }
          }
      }

      # After processing all lines, print the formatted output.
      END {
          # Sort the chart names alphabetically for consistent output
          PROCINFO["sorted_in"] = "@ind_str_asc"
          for (chart in images) {
              print chart ":"
              print images[chart]
          }
      }
    ')


if [ -z "$images_by_chart" ]; then
    echo "No images found. This could be due to an issue with the Helm chart or the template command."
    exit 1
fi

# 5. Display the results
log "Container images found in '$CHART_NAME' and its dependencies:"
echo "$images_by_chart"

log "Script finished successfully!"
