#!/bin/bash
# shellcheck disable=SC2016
: '
New Relic Bundle Chart Image Inspector

This script fetches the latest `nri-bundle` Helm chart and inspects it to
discover all container images and their versions used across its various
sub-charts. It renders the chart templates locally without needing a live
Kubernetes cluster and parses the output to group images by the sub-chart
they belong to.

This is useful for quickly verifying image versions before a deployment or for
security scanning purposes.

It performs the following actions:
- Checks for required command-line tools (helm, awk, etc.).
- Adds and updates the New Relic Helm chart repository.
- Fetches and unpacks the `nri-bundle` chart into a temporary directory.
- Renders the Helm templates for all enabled sub-charts.
- Parses the template output to extract and list all unique container images.
- Prints a final, formatted list of images grouped by their respective chart.

Author : Keegan Mullaney
Company: New Relic
Email  : kmullaney@newrelic.com
Website: github.com/keegoid-nr/useful-scripts
License: Apache License 2.0
'

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
CHART_NAME="nri-bundle"
REPO_NAME="newrelic"
REPO_URL="https://helm-charts.newrelic.com"
RELEASE_NAME="nri-bundle-release" # A temporary release name for templating

# --- Colors ---
# Only use colors if outputting to a terminal
if [ -t 1 ]; then
  BOLD="\033[1m"
  SUCCESS_GREEN="\033[1;32m"
  YELLOW="\033[1;33m"
  CYAN="\033[1;36m"
  WHITE="\033[1;37m"
  RED="\033[1;31m"
  RESET="\033[0m"
else
  BOLD=""
  SUCCESS_GREEN=""
  YELLOW=""
  CYAN=""
  WHITE=""
  RED=""
  RESET=""
fi

# Create a temporary directory for our work that gets cleaned up on exit.
WORK_DIR=$(mktemp -d)
trap 'echo -e "${YELLOW}Cleaning up...${RESET}"; rm -rf "$WORK_DIR"' EXIT

# --- Helper Functions ---

# Checks if a command-line tool is available in the user's PATH.
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Prints a formatted message to the console.
log() {
    echo -e "${YELLOW}--------------------------------------------------${RESET}"
    echo -e "${BOLD}$1${RESET}"
    echo -e "${YELLOW}--------------------------------------------------${RESET}"
}

# --- Main Script ---

# 1. Check for required tools
log "Checking for required tools (helm, grep, awk, sort, uniq)..."
for cmd in helm grep awk sort uniq; do
    if ! command_exists "$cmd"; then
        echo -e "${RED}Error: Required command '$cmd' is not installed. Please install it and try again.${RESET}"
        exit 1
    fi
done
echo -e "${SUCCESS_GREEN}All required tools are present.${RESET}"

# 2. Add and Update the New Relic Helm Repo
log "Adding and updating the New Relic Helm repository..."
if ! helm repo list | grep -q "$REPO_NAME"; then
    echo "Adding New Relic Helm repo..."
    helm repo add "$REPO_NAME" "$REPO_URL"
else
    echo "New Relic Helm repo already exists."
fi
helm repo update "$REPO_NAME"
echo -e "${SUCCESS_GREEN}Repo update complete.${RESET}"

# 3. Fetch, Unpack, and Update Dependencies for the Chart
log "Fetching chart and its dependencies locally..."
cd "$WORK_DIR"

# Retry helm pull to guard against transient network issues.
MAX_RETRIES=3
RETRY_COUNT=0
until helm pull "$REPO_NAME/$CHART_NAME" --untar > /dev/null 2>&1 || [ $RETRY_COUNT -eq $MAX_RETRIES ]; do
  RETRY_COUNT=$((RETRY_COUNT+1))
  echo -e "helm pull failed. ${YELLOW}Retrying in 5 seconds...${RESET} (Attempt $RETRY_COUNT/$MAX_RETRIES)"
  sleep 5
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
  echo -e "${RED}Error: helm pull failed after $MAX_RETRIES attempts.${RESET}"
  exit 1
fi

cd "$CHART_NAME"
helm dependency update
echo -e "${SUCCESS_GREEN}Local chart dependencies are up to date.${RESET}"
cd "$WORK_DIR"


# 4. Render the chart templates and extract image names
log "Templating the '$CHART_NAME' chart to find container images..."
# The following pipeline renders the chart with all sub-charts enabled to
# ensure we find all possible images. The output is then piped to a powerful
# awk script that parses the template source comments to group images by the
# sub-chart they originated from.
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
    awk -v c_chart="${CYAN}${BOLD}" -v c_version="${WHITE}" -v c_reset="${RESET}" '
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
      /^[ \t]+image:/ {
          gsub(/"|\047/, "", $2) # Remove quotes
          image_full = $2

          if (image_full != "") {
              # Find the position of the last colon to isolate the version tag
              last_colon_pos = match(image_full, /:[^:]+$/)
              formatted_image = image_full

              if (last_colon_pos) {
                  # Reconstruct the string with color codes around the version
                  base = substr(image_full, 1, RSTART)
                  tag = substr(image_full, RSTART + 1)
                  formatted_image = base c_version tag c_reset
              }

              if (images[current_chart] == "") {
                  images[current_chart] = "\t- " formatted_image
              } else {
                  # Avoid adding duplicates by checking against the original, uncolored image name
                  if (index(images[current_chart], image_full) == 0) {
                    images[current_chart] = images[current_chart] "\n\t- " formatted_image
                  }
              }
          }
      }

      # After processing all lines, print the formatted output.
      END {
          PROCINFO["sorted_in"] = "@ind_str_asc"
          for (chart in images) {
              print c_chart chart ":" c_reset
              print images[chart]
          }
      }
    ')


if [ -z "$images_by_chart" ]; then
    echo -e "${RED}No images found. This could be due to an issue with the Helm chart or the template command.${RESET}"
    exit 1
fi

# 5. Display the results
log "Container images found in '$CHART_NAME' and its dependencies:"
echo -e "$images_by_chart"

log "${SUCCESS_GREEN}Script finished successfully!${RESET}"
