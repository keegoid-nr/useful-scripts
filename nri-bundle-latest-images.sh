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

# --- Script Functions ---

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

# 3. Render the chart templates and extract image names
log "Templating the '$CHART_NAME' chart to find container images..."
# We use helm template to generate the kubernetes manifests locally
# A dummy cluster name and license key are required for the template rendering to succeed.
# Then we grep for lines containing 'image:'
# awk is used to print the second field (the image name and tag)
# We then sort the results and get unique entries
images=$(helm template "$RELEASE_NAME" "$REPO_NAME/$CHART_NAME" --set global.cluster=temp-cluster-name --set global.licenseKey=dummy-key | \
    grep -E '\s+image:' | \
    awk '{print $2}' | \
    sort | \
    uniq)

if [ -z "$images" ]; then
    echo "No images found. This could be due to an issue with the Helm chart or the template command."
    exit 1
fi

# 4. Display the results
log "Latest container images found in the '$CHART_NAME' chart:"
echo "$images"

log "Script finished successfully!"
