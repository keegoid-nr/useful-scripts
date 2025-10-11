#!/bin/bash
# shellcheck disable=SC2016
: '
Helm Chart Image Inspector

This script inspects a Helm chart to discover all container images and their
versions used across its sub-charts. It can operate in three modes:
1. Repo Mode: Fetches a chart from any specified Helm repository.
2. Local Mode (`--local`): Inspects a Helm release already installed in your cluster.
3. New Relic Mode (`--newrelic`): Interactively select a chart from the New Relic
   repo and automatically apply preset configurations from `chart-presets.txt`.

This is useful for quickly verifying image versions before a deployment or for
security scanning purposes.

Usage:
  ./helm-image-inspector.sh <REPO>/<CHART> [VERSION] [helm-flags]
  ./helm-image-inspector.sh --local
  ./helm-image-inspector.sh --newrelic

Arguments:
  <REPO>/<CHART> (Repo Mode): The name of the chart to inspect (e.g., `newrelic/nri-bundle`).
  [VERSION] (Repo Mode, Optional): The specific chart version to inspect.
  [helm-flags] (Optional): Pass-through flags for `helm template`, like `--set key=value`.
  --local: Switch to local mode to inspect a deployed Helm release.
  --newrelic: Use interactive mode for New Relic charts.

Author : Keegan Mullaney
Company: New Relic
Email  : kmullaney@newrelic.com
Website: github.com/keegoid-nr/useful-scripts
License: Apache License 2.0
'

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Colors ---
if [ -t 1 ]; then
  BOLD="\033[1m"; DIM="\033[2m"; SUCCESS_GREEN="\033[1;32m"; YELLOW="\033[1;33m"
  CYAN="\033[1;36m"; WHITE="\033[1;37m"; RED="\033[1;31m"; RESET="\033[0m"
else
  BOLD=""; DIM=""; SUCCESS_GREEN=""; YELLOW=""; CYAN=""; WHITE=""; RED=""; RESET=""
fi

# Create a temporary directory that gets cleaned up on exit.
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT # Silent cleanup

# --- Helper Functions ---
command_exists() { command -v "$1" >/dev/null 2>&1; }
log() {
    echo -e "${YELLOW}--------------------------------------------------${RESET}"
    echo -e "${BOLD}$1${RESET}"
    echo -e "${YELLOW}--------------------------------------------------${RESET}"
}

# --- Core Logic ---

# Inspects a chart fetched from a remote Helm repository.
inspect_from_repo() {
    local repo_chart="$1"
    local chart_version="$2"
    shift 2
    local set_flags=("$@")
    local repo
    repo=$(echo "$repo_chart" | cut -d'/' -f1)
    local chart
    chart=$(echo "$repo_chart" | cut -d'/' -f2)

    for cmd in helm grep awk sort uniq jq; do
        if ! command_exists "$cmd"; then
            echo -e "${RED}Error: Required command '$cmd' is not installed.${RESET}" >&2; exit 1
        fi
    done

    # Silently check and update the repo.
    if ! helm repo list | grep -q "^$repo\s"; then
        read -r -p "Helm repository '$repo' not found. Would you like to add the New Relic repository? (y/n) " choice >&2
        if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
            helm repo add "$repo" "https://helm-charts.newrelic.com" >/dev/null 2>&1
        else
            echo "Please add the repo manually and try again." >&2; exit 1
        fi
    fi
    helm repo update "$repo" >/dev/null 2>&1

    local version_flag=""
    if [ -n "$chart_version" ]; then
        log "Inspecting '$repo_chart' version '$chart_version'..."
        version_flag="--version $chart_version"
    else
        log "Inspecting the latest version of '$repo_chart'..."
        latest_version=$(helm search repo "$repo_chart" --versions -o json | jq -r '.[0].version')
        if [ -z "$latest_version" ] || [ "$latest_version" == "null" ]; then
            echo -e "${RED}Error: Could not find the latest version for '$repo_chart'.${RESET}" >&2
            exit 1
        fi
        version_flag="--version $latest_version"
    fi

    cd "$WORK_DIR"
    # shellcheck disable=SC2086
    helm pull "$repo_chart" --untar $version_flag >/dev/null 2>&1
    cd "$chart"

    MAX_RETRIES=3
    RETRY_COUNT=0
    SUCCESS=false
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        UPDATE_OUTPUT=$(helm dependency update 2>&1)
        EXIT_CODE=$?
        if [ $EXIT_CODE -eq 0 ]; then SUCCESS=true; break; fi
        RETRY_COUNT=$((RETRY_COUNT+1))
        if [[ "$UPDATE_OUTPUT" == *"EOF"* ]]; then
            echo -e "\n${RED}A network connectivity issue was detected (EOF error).${RESET}" >&2
            echo -e "${YELLOW}This is common for New Relic employees. Please ensure your WARP by Cloudflare VPN is connected.${RESET}\n" >&2
        fi
        if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
            echo -e "${YELLOW}Retrying dependency update...${RESET} (Attempt $RETRY_COUNT/$MAX_RETRIES)" >&2
            sleep 5
        fi
    done
    if [ "$SUCCESS" != true ]; then echo -e "${RED}Error: helm dependency update failed after $MAX_RETRIES attempts.${RESET}" >&2; exit 1; fi

    parent_version=$(grep '^version:' "Chart.yaml" | awk '{print $2}')
    versions_str="${chart}|${parent_version}§"
    if [ -f "Chart.lock" ]; then
        versions_str+=$(awk '/^- name:/ { gsub(/"|\047/, "", $3); name = $3; } /  version:/ { if (name != "") { gsub(/"|\047/, "", $2); printf "%s|%s§", name, $2; name=""; } }' "Chart.lock")
    fi

    cd "$WORK_DIR"
    images_by_chart=$(helm template "release-name" ./"$chart" "${set_flags[@]}" --debug 2>&1 | parse_template_output "$chart")

    display_results "$images_by_chart"
}

# Inspects a chart from a locally installed Helm release.
inspect_from_local() {
    log "Inspecting a local Helm release."
    for cmd in helm kubectl jq grep awk; do
        if ! command_exists "$cmd"; then
            echo -e "${RED}Error: Required command '$cmd' is not installed.${RESET}" >&2; exit 1
        fi
    done

    selection=$(select_helm_release)
    if [ -z "$selection" ]; then echo "No release selected. Exiting." >&2; exit 1; fi
    # shellcheck disable=SC2086
    set -- $selection
    local release_name=$1; local namespace=$2; local chart_full=$3

    local chart_name; chart_name=$(echo "$chart_full" | sed -E 's/([a-zA-Z0-9._-]+)-([0-9]+\.[0-9]+\.[0-9]+.*)/\1/')
    local chart_version; chart_version=$(echo "$chart_full" | sed -E 's/([a-zA-Z0-9._-]+)-([0-9]+\.[0-9]+\.[0-9]+.*)/\2/')

    log "Getting images for release '$release_name'..."
    versions_str="${chart_name}|${chart_version}§" # This only contains the parent chart version.
    images_by_chart=$(helm get manifest "$release_name" --namespace "$namespace" | parse_manifest_output)

    display_results "$images_by_chart"
}

# New: Interactive mode for New Relic charts.
inspect_newrelic_interactive() {
    log "New Relic Interactive Mode"
    local chart_to_inspect; chart_to_inspect=$(select_newrelic_chart)
    if [ -z "$chart_to_inspect" ]; then echo "No chart selected. Exiting." >&2; exit 1; fi

    local preset_flags; preset_flags=($(get_preset_flags_from_file "$chart_to_inspect"))

    # Special handling for charts that have moved to their own repos.
    if [[ "$chart_to_inspect" == "newrelic/newrelic-infra-operator" ]]; then
        local temp_repo_name="temp-infra-operator-repo"
        local temp_repo_url="https://newrelic.github.io/newrelic-infra-operator"

        trap 'helm repo remove "$temp_repo_name" &>/dev/null; rm -rf "$WORK_DIR"' EXIT

        helm repo add "$temp_repo_name" "$temp_repo_url" >/dev/null 2>&1
        inspect_from_repo "$temp_repo_name/newrelic-infra-operator" "" "${preset_flags[@]}"
    elif [[ "$chart_to_inspect" == "newrelic/newrelic-infrastructure" ]]; then
        local temp_repo_name="temp-infra-repo"
        local temp_repo_url="https://newrelic.github.io/nri-kubernetes"

        trap 'helm repo remove "$temp_repo_name" &>/dev/null; rm -rf "$WORK_DIR"' EXIT

        helm repo add "$temp_repo_name" "$temp_repo_url" >/dev/null 2>&1
        inspect_from_repo "$temp_repo_name/newrelic-infrastructure" "" "${preset_flags[@]}"
    elif [[ "$chart_to_inspect" == "newrelic/newrelic-k8s-metrics-adapter" ]]; then
        local temp_repo_name="temp-metrics-adapter-repo"
        local temp_repo_url="https://newrelic.github.io/newrelic-k8s-metrics-adapter"

        trap 'helm repo remove "$temp_repo_name" &>/dev/null; rm -rf "$WORK_DIR"' EXIT

        helm repo add "$temp_repo_name" "$temp_repo_url" >/dev/null 2>&1
        inspect_from_repo "$temp_repo_name/newrelic-k8s-metrics-adapter" "" "${preset_flags[@]}"
    elif [[ "$chart_to_inspect" == "newrelic/nri-kube-events" ]]; then
        local temp_repo_name="temp-kube-events-repo"
        local temp_repo_url="https://newrelic.github.io/nri-kube-events"

        trap 'helm repo remove "$temp_repo_name" &>/dev/null; rm -rf "$WORK_DIR"' EXIT

        helm repo add "$temp_repo_name" "$temp_repo_url" >/dev/null 2>&1
        inspect_from_repo "$temp_repo_name/nri-kube-events" "" "${preset_flags[@]}"
    elif [[ "$chart_to_inspect" == "newrelic/nri-metadata-injection" ]]; then
        local temp_repo_name="temp-metadata-injection-repo"
        local temp_repo_url="https://newrelic.github.io/k8s-metadata-injection"

        trap 'helm repo remove "$temp_repo_name" &>/dev/null; rm -rf "$WORK_DIR"' EXIT

        helm repo add "$temp_repo_name" "$temp_repo_url" >/dev/null 2>&1
        inspect_from_repo "$temp_repo_name/nri-metadata-injection" "" "${preset_flags[@]}"
    elif [[ "$chart_to_inspect" == "newrelic/nri-prometheus" ]]; then
        local temp_repo_name="temp-prometheus-repo"
        local temp_repo_url="https://newrelic.github.io/nri-prometheus"

        trap 'helm repo remove "$temp_repo_name" &>/dev/null; rm -rf "$WORK_DIR"' EXIT

        helm repo add "$temp_repo_name" "$temp_repo_url" >/dev/null 2>&1
        inspect_from_repo "$temp_repo_name/nri-prometheus" "" "${preset_flags[@]}"
    else
        # Standard logic for charts in the main 'newrelic' repo.
        inspect_from_repo "$chart_to_inspect" "" "${preset_flags[@]}"
    fi
}

# Displays a list of Helm releases and prompts the user to select one.
select_helm_release() {
    echo "Fetching Helm releases from your current Kubernetes context..." >&2
    releases_json=$(helm list --all-namespaces -o json)
    if [ -z "$releases_json" ] || [ "$releases_json" == "[]" ]; then
        echo -e "${RED}No Helm releases found in the current context.${RESET}" >&2; return 1; fi

    releases=(); while IFS= read -r line; do releases+=("$line"); done < <(echo "$releases_json" | jq -r '.[] | .name + " " + .namespace + " " + .chart')

    echo -e "${BOLD}Please select a Helm release to inspect:${RESET}" >&2
    for i in "${!releases[@]}"; do printf "  ${BOLD}%2d)${RESET} %s\n" "$((i+1))" "${releases[$i]}" >&2; done

    local choice; printf "\n${CYAN}Enter number: ${RESET}" >&2; read -r choice
    if [[ $choice =~ ^[0-9]+$ ]] && [ "$choice" -gt 0 ] && [ "$choice" -le "${#releases[@]}" ]; then
        echo "${releases[$((choice-1))]}"; else echo -e "${RED}Invalid selection.${RESET}" >&2; return 1; fi
}

# New: Displays a list of New Relic charts for selection.
select_newrelic_chart() {
    echo "Fetching charts from the 'newrelic' Helm repository..." >&2
    charts_json=$(helm search repo newrelic -o json)
    if [ -z "$charts_json" ] || [ "$charts_json" == "[]" ]; then
        echo -e "${RED}No charts found in the 'newrelic' repo.${RESET}" >&2; return 1; fi

    charts=(); while IFS= read -r line; do charts+=("$line"); done < <(echo "$charts_json" | jq -r '.[] | .name' | \
        grep '^newrelic/' | \
        grep -v -e 'newrelic/common-library' -e 'newrelic/agent-control$' -e 'newrelic/simple-nginx' -e 'newrelic/agent-control-deployment' -e 'newrelic/agent-control-cd' -e 'newrelic/agent-control-bootstrap' | \
        sed 's|^newrelic/||' | \
        sort | uniq)

    echo -e "${BOLD}Please select a New Relic chart to inspect:${RESET}" >&2
    for i in "${!charts[@]}"; do printf "  ${BOLD}%2d)${RESET} %s\n" "$((i+1))" "${charts[$i]}" >&2; done

    local choice; printf "\n${CYAN}Enter number: ${RESET}" >&2; read -r choice
    if [[ $choice =~ ^[0-9]+$ ]] && [ "$choice" -gt 0 ] && [ "$choice" -le "${#charts[@]}" ]; then
        echo "newrelic/${charts[$((choice-1))]}";
    else
        echo -e "${RED}Invalid selection.${RESET}" >&2; return 1;
    fi
}

# New: Reads preset flags from an external file.
get_preset_flags_from_file() {
    local chart_name="$1"
    local script_dir; script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    local preset_file="$script_dir/chart-presets.txt"

    if [ ! -f "$preset_file" ]; then
        # No preset file found, so return no flags.
        return
    fi

    # Grep for the exact chart name at the beginning of a line, then cut out the flags.
    grep "^${chart_name}:" "$preset_file" | cut -d':' -f2-
}


# Awk script to parse the output of 'helm template --debug'.
parse_template_output() {
    local parent_chart_name="$1"
    awk -v parent_chart="$parent_chart_name" -v versions="$versions_str" -v c_chart="${CYAN}${BOLD}" -v c_version="${WHITE}" -v c_reset="${RESET}" '
      BEGIN {
          current_chart="parent-chart";
          split(versions, pairs, "§"); for (i in pairs) { if (pairs[i] != "") { split(pairs[i], kv, "|"); chart_versions[kv[1]] = kv[2] } }
      }
      /^# Source: / {
          split($3, path_parts, "/");
          if (path_parts[2] == "charts") { current_chart = path_parts[3]; } else { current_chart = "parent-chart"; }
      }
      /^[ \t]+image:/ {
          gsub(/"|\047/, "", $2); image_full = $2;
          if (image_full != "" && index(images[current_chart], image_full) == 0) {
              formatted_image = image_full;
              if (match(image_full, /:[^:]+$/)) { formatted_image = substr(image_full, 1, RSTART) c_version substr(image_full, RSTART + 1) c_reset; }
              if (images[current_chart] == "") { images[current_chart] = "\t- " formatted_image; }
              else { images[current_chart] = images[current_chart] "\n\t- " formatted_image; }
          }
      }
      END {
          PROCINFO["sorted_in"] = "@ind_str_asc";
          for (chart in images) {
              display_chart = chart; if (chart == "parent-chart") { display_chart = parent_chart; }
              version = chart_versions[display_chart]
              if (version == "" && display_chart == "pixie-chart") {
                  version = chart_versions["pixie-operator-chart"]
              }
              version_str = (version != "") ? " (v" c_version version c_reset ")" : "";
              print c_chart display_chart c_reset version_str ":"; print images[chart];
          }
      }'
}

# Awk script to parse the output of 'helm get manifest'.
parse_manifest_output() {
    awk -v versions="$versions_str" -v c_chart="${CYAN}${BOLD}" -v c_version="${WHITE}" -v c_reset="${RESET}" '
      BEGIN {
          split(versions, pairs, "§"); for (i in pairs) { if (pairs[i] != "") { split(pairs[i], kv, "|"); chart_versions[kv[1]] = kv[2] } }
      }
      /helm.sh\/chart:/ {
          chart_name_full = $2;
          if (match(chart_name_full, /-([0-9]+\.[0-9]+\.[0-9]+.*)$/)) {
              chart_name_from_label = substr(chart_name_full, 1, RSTART - 1);
              chart_version_from_label = substr(chart_name_full, RSTART + 1);
              chart_versions[chart_name_from_label] = chart_version_from_label;
          }
      }
      /app.kubernetes.io\/name:/ { current_chart_name = $2; }
      /^[ \t]+image:/ {
          gsub(/"|\047/, "", $2); image_full = $2;
          if (image_full != "" && current_chart_name != "" && index(images[current_chart_name], image_full) == 0) {
              formatted_image = image_full;
              if (match(image_full, /:[^:]+$/)) { formatted_image = substr(image_full, 1, RSTART) c_version substr(image_full, RSTART + 1) c_reset; }
              if (images[current_chart_name] == "") { images[current_chart_name] = "\t- " formatted_image; }
              else { images[current_chart_name] = images[current_chart_name] "\n\t- " formatted_image; }
          }
      }
      /^---/ { current_chart_name = ""; }
      END {
          PROCINFO["sorted_in"] = "@ind_str_asc";
          for (chart in images) {
              version_str = chart_versions[chart] ? " (v" c_version chart_versions[chart] c_reset ")" : "";
              print c_chart chart c_reset version_str ":"; print images[chart];
          }
      }'
}


# Prints the final formatted list of images.
display_results() {
    local images_by_chart=$1

    if [ -z "$images_by_chart" ]; then
        echo -e "${RED}No images found. This could be due to a templating error. Try supplying required values with --set.${RESET}" >&2
        exit 1
    fi
    echo # Add a newline for spacing
    echo -e "$images_by_chart"
    echo # Add a newline for spacing
}

# --- Main Execution ---
main() {
    for arg in "$@"; do
        if [[ "$arg" == "--local" ]]; then
            if [ "$#" -ne 1 ]; then
                echo -e "${RED}Error: The --local flag must be used alone.${RESET}" >&2; exit 1
            fi
            inspect_from_local
            return
        fi
        if [[ "$arg" == "--newrelic" ]]; then
            if [ "$#" -ne 1 ]; then
                echo -e "${RED}Error: The --newrelic flag must be used alone.${RESET}" >&2; exit 1
            fi
            inspect_newrelic_interactive
            return
        fi
    done

    if [ "$#" -eq 0 ]; then
        echo -e "${RED}Invalid usage.${RESET}" >&2
        echo "Usage: $0 <REPO>/<CHART> [VERSION] [helm-flags] | --local | --newrelic" >&2
        exit 1
    fi

    if ! [[ "$1" =~ .*/.* ]]; then
        echo -e "${RED}Invalid usage. First argument must be <REPO>/<CHART>, --local, or --newrelic.${RESET}" >&2
        exit 1
    fi

    local repo_chart="$1"
    shift
    local chart_version=""
    local set_flags=()

    while [[ $# -gt 0 ]]; do
        case $1 in
            --set|--set-string)
                if [[ -n "$2" ]]; then
                    set_flags+=("$1" "$2")
                    shift 2
                else
                    echo -e "${RED}Error: $1 requires a value.${RESET}" >&2; exit 1
                fi
                ;;
            -*)
                echo -e "${RED}Error: Unknown flag '$1' in repo mode.${RESET}" >&2
                exit 1
                ;;
            *)
                if [[ -z "$chart_version" ]]; then
                    chart_version="$1"
                    shift
                else
                    echo -e "${RED}Error: Unexpected argument '$1'. Version already set to '$chart_version'.${RESET}" >&2
                    exit 1
                fi
                ;;
        esac
    done

    inspect_from_repo "$repo_chart" "$chart_version" "${set_flags[@]}"
}

main "$@"
