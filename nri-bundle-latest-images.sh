#!/bin/bash

# nri-bundle-latest-images.sh
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


# 4. Render the chart templates and extract image names
log "Templating the '$CHART_NAME' chart and its sub-charts to find container images..."
# We use helm template on the local chart to ensure all nested dependencies are included.
# We must enable all sub-charts to see their respective images.
# Dummy values for cluster, license key, API key, and Account ID are required for the template rendering to succeed.
# Then we grep for lines containing 'image:'
# awk is used to print the second field (the image name and tag)
# We then sort the results and get unique entries
images=$(helm template "$RELEASE_NAME" ./"$CHART_NAME" \
    --set global.cluster=temp-cluster-name \
    --set global.licenseKey=dummy-key \
    --set newrelic-infrastructure.enabled=true \
    --set nri-prometheus.enabled=true \
    --set nri-metadata-injection.enabled=true \
    --set kube-state-metrics.enabled=true \
    --set nri-kube-events.enabled=true \
    --set newrelic-logging.enabled=true \
    --set newrelic-pixie.enabled=true \
    --set newrelic-eapm-agent.enabled=true \
    --set k8s-agents-operator.enabled=true \
    --set pixie-chart.enabled=true \
    --set newrelic-infra-operator.enabled=true \
    --set newrelic-prometheus-agent.enabled=true \
    --set newrelic-k8s-metrics-adapter.enabled=true \
    --set newrelic-k8s-metrics-adapter.personalAPIKey=dummy-api-key \
    --set newrelic-k8s-metrics-adapter.config.accountID=12345678 | \
    grep -E '\s+image:' | \
    awk '{print $2}' | \
    sort | \
    uniq)

if [ -z "$images" ]; then
    echo "No images found. This could be due to an issue with the Helm chart or the template command."
    exit 1
fi

# 5. Display the results
log "Latest container images found in the '$CHART_NAME' chart and all its dependencies:"
echo "$images"

log "Script finished successfully!"
