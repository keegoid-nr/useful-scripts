#!/bin/bash
# shellcheck disable=SC2016
: '
Description
This script inspects a Google Kubernetes Engine (GKE) cluster and its node pool
and prints the configuration in a format similar to a series of gcloud create commands

Prerequisites
1. `gcloud` CLI installed and authenticated
2. `jq` command-line JSON processor installed
3. The user running the script must have the `container.clusters.get` permission

Usage
1. Copy the `.env.example` file to `.env` and fill in your cluster details
2. Make the script executable: chmod +x gke_config_scraper.s
3. Run the script: ./gke_config_scraper.sh
'

# --- Configuration Loading ---
# Load configuration from .env file if it exists
if [ -f .env ]; then
  # Use `set -a` to export all variables created from the file
  set -a
  source .env
  set +a
fi

# Check for required variables
if [ -z "$PROJECT_ID" ] || [ -z "$CLUSTER_NAME" ] || [ -z "$REGION" ]; then
    echo "ERROR: Configuration variables are not set."
    echo "Please create a '.env' file from the '.env.example' template and fill in your details,"
    echo "or set PROJECT_ID, CLUSTER_NAME, and REGION as environment variables."
    exit 1
fi
# ---------------------------


# --- Helper Functions ---
# Function to format key-value pairs from a jq object
format_key_value() {
    # Gracefully handle null or empty input
    echo "$1" | jq -r 'if . == null or . == {} then "" else to_entries | map("\(.key)=\(.value)") | join(",") end'
}

# Function to format taints from a jq array
format_taints() {
    # Gracefully handle null or empty input
    echo "$1" | jq -r 'if . == null or . == [] then "" else .[] | "\(.key)=\(.value):\(.effect)" end' | paste -sd "," -
}

# --- Main Script ---

# Validate prerequisites
if ! command -v gcloud &> /dev/null; then
    echo "ERROR: gcloud command could not be found. Please install the Google Cloud SDK."
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "ERROR: jq command could not be found. Please install jq."
    exit 1
fi

echo "Fetching cluster data for $CLUSTER_NAME in project $PROJECT_ID..."

# Fetch cluster data once to avoid multiple API calls
CLUSTER_DATA=$(gcloud container clusters describe "$CLUSTER_NAME" --region="$REGION" --project="$PROJECT_ID" --format="json")
if [ -z "$CLUSTER_DATA" ]; then
    echo "Error: Failed to fetch cluster data. Check your configuration and permissions."
    exit 1
fi

echo ""
# --- Print Cluster Configuration ---
echo "project \"$PROJECT_ID\" \"$CLUSTER_NAME\""
echo "region \"$(echo "$CLUSTER_DATA" | jq -r .location)\""

if [[ "$(echo "$CLUSTER_DATA" | jq -r '.masterAuth.username')" == "null" || -z "$(echo "$CLUSTER_DATA" | jq -r '.masterAuth.username')" ]]; then
    echo "no-enable-basic-auth"
else
    echo "enable-basic-auth"
fi

echo "cluster-version \"$(echo "$CLUSTER_DATA" | jq -r .currentMasterVersion)\""
echo "release-channel \"$(echo "$CLUSTER_DATA" | jq -r .releaseChannel.channel | tr '[:upper:]' '[:lower:]')\""

# Display settings from the primary/default node pool for context
DEFAULT_POOL_DATA=$(echo "$CLUSTER_DATA" | jq '.nodePools[] | select(.initialNodeCount != null)')
if [ -n "$DEFAULT_POOL_DATA" ]; then
    echo "machine-type \"$(echo "$DEFAULT_POOL_DATA" | jq -r .config.machineType)\""
    echo "image-type \"$(echo "$DEFAULT_POOL_DATA" | jq -r .config.imageType)\""
    echo "disk-type \"$(echo "$DEFAULT_POOL_DATA" | jq -r .config.diskType)\""
    echo "disk-size \"$(echo "$DEFAULT_POOL_DATA" | jq -r .config.diskSizeGb)\""
    labels=$(format_key_value "$(echo "$DEFAULT_POOL_DATA" | jq .config.labels)")
    [ -n "$labels" ] && echo "node-labels $labels"
    metadata=$(format_key_value "$(echo "$DEFAULT_POOL_DATA" | jq .config.metadata)")
    [ -n "$metadata" ] && echo "metadata $metadata"
    taints=$(format_taints "$(echo "$DEFAULT_POOL_DATA" | jq .config.taints)")
    [ -n "$taints" ] && echo "node-taints $taints"
    echo "service-account \"$(echo "$DEFAULT_POOL_DATA" | jq -r .config.serviceAccount)\""
    echo "max-pods-per-node \"$(echo "$DEFAULT_POOL_DATA" | jq -r .maxPodsConstraint.maxPodsPerNode)\""
    echo "num-nodes \"$(echo "$DEFAULT_POOL_DATA" | jq -r .initialNodeCount)\""
fi

# Cluster-wide settings
logging=$(echo "$CLUSTER_DATA" | jq -r '.loggingConfig.componentConfig.enableComponents | join(",")')
echo "logging=$logging"
monitoring=$(echo "$CLUSTER_DATA" | jq -r '.monitoringConfig.componentConfig.enableComponents | join(",")')
echo "monitoring=$monitoring"

[ "$(echo "$CLUSTER_DATA" | jq -r .privateClusterConfig.enablePrivateNodes)" == "true" ] && echo "enable-private-nodes"
[ "$(echo "$CLUSTER_DATA" | jq -r .privateClusterConfig.enablePrivateEndpoint)" == "true" ] && echo "enable-private-endpoint"
[ "$(echo "$CLUSTER_DATA" | jq -r .privateClusterConfig.enableGlobalAccess)" == "true" ] && echo "enable-master-global-access"
[ "$(echo "$CLUSTER_DATA" | jq -r .ipAllocationPolicy.useIpAliases)" == "true" ] && echo "enable-ip-alias"
echo "network \"$(echo "$CLUSTER_DATA" | jq -r .network)\""
echo "subnetwork \"$(echo "$CLUSTER_DATA" | jq -r .subnetwork)\""
[ "$(echo "$CLUSTER_DATA" | jq -r .intraNodeVisibilityConfig.enabled)" == "true" ] && echo "enable-intra-node-visibility"
echo "default-max-pods-per-node \"$(echo "$CLUSTER_DATA" | jq -r .defaultMaxPodsConstraint.maxPodsPerNode)\""

# Autoscaling settings from the default node pool
if [ "$(echo "$DEFAULT_POOL_DATA" | jq -r .autoscaling.enabled)" == "true" ]; then
    echo "enable-autoscaling"
    echo "min-nodes \"$(echo "$DEFAULT_POOL_DATA" | jq -r .autoscaling.minNodeCount)\""
    echo "max-nodes \"$(echo "$DEFAULT_POOL_DATA" | jq -r .autoscaling.maxNodeCount)\""
    echo "location-policy \"$(echo "$DEFAULT_POOL_DATA" | jq -r .autoscaling.locationPolicy)\""
fi

# Security settings
[ "$(echo "$CLUSTER_DATA" | jq -r .masterAuthorizedNetworksConfig.gcpPublicCidrsAccessEnabled)" == "true" ] && echo "enable-ip-access"
echo "security-posture=$(echo "$CLUSTER_DATA" | jq -r .securityPostureConfig.mode | tr '[:upper:]' '[:lower:]')"
echo "workload-vulnerability-scanning=$(echo "$CLUSTER_DATA" | jq -r .securityPostureConfig.vulnerabilityMode | tr '[:upper:]' '[:lower:]')"

if [ "$(echo "$CLUSTER_DATA" | jq -r .networkConfig.datapathProvider)" == "ADVANCED_DATAPATH" ]; then
    echo "enable-dataplane-v2"
fi

if [ "$(echo "$CLUSTER_DATA" | jq -r .masterAuthorizedNetworksConfig.enabled)" == "true" ]; then
    echo "enable-master-authorized-networks"
    # Use ? to handle null cidrBlocks array gracefully
    networks=$(echo "$CLUSTER_DATA" | jq -r '.masterAuthorizedNetworksConfig.cidrBlocks[]? | .cidrBlock' | paste -sd " " -)
    echo "master-authorized-networks $networks"
fi

if [ "$(echo "$CLUSTER_DATA" | jq -r .privateClusterConfig.privateEndpointAccessType)" != "OUTBOUND_PEERING" ]; then
    echo "no-enable-google-cloud-access"
fi

# Addons
addons=""
[ "$(echo "$CLUSTER_DATA" | jq -r .addonsConfig.horizontalPodAutoscaling.disabled)" != "true" ] && addons="${addons}HorizontalPodAutoscaling,"
[ "$(echo "$CLUSTER_DATA" | jq -r .addonsConfig.httpLoadBalancing.disabled)" != "true" ] && addons="${addons}HttpLoadBalancing,"
[ "$(echo "$CLUSTER_DATA" | jq -r .addonsConfig.gcePersistentDiskCsiDriverConfig.enabled)" == "true" ] && addons="${addons}GcePersistentDiskCsiDriver,"
[ "$(echo "$CLUSTER_DATA" | jq -r .addonsConfig.configConnectorConfig.enabled)" == "true" ] && addons="${addons}ConfigConnector,"
[ "$(echo "$CLUSTER_DATA" | jq -r .addonsConfig.gcsFuseCsiDriverConfig.enabled)" == "true" ] && addons="${addons}GcsFuseCsiDriver,"
echo "addons ${addons%,}" # Remove trailing comma

# Maintenance Window
window=$(echo "$CLUSTER_DATA" | jq .maintenancePolicy.window.recurringWindow)
# Check for a non-null start time before printing window details
if [ "$(echo "$window" | jq -r '.window.startTime')" != "null" ]; then
    start_time=$(echo "$window" | jq -r .window.startTime)
    end_time=$(echo "$window" | jq -r .window.endTime)
    recurrence=$(echo "$window" | jq -r .recurrence)
    echo "maintenance-window-start \"$start_time\""
    echo "maintenance-window-end \"$end_time\""
    echo "maintenance-window-recurrence \"$recurrence\""
fi

# Other cluster settings
echo "binauthz-evaluation-mode=$(echo "$CLUSTER_DATA" | jq -r .binaryAuthorization.evaluationMode)"
[ "$(echo "$CLUSTER_DATA" | jq -r .verticalPodAutoscaling.enabled)" == "true" ] && echo "enable-vertical-pod-autoscaling"
WORKLOAD_POOL=$(echo "$CLUSTER_DATA" | jq -r .workloadIdentityConfig.workloadPool)
[ "$WORKLOAD_POOL" != "null" ] && echo "workload-pool \"$WORKLOAD_POOL\""
[ "$(echo "$CLUSTER_DATA" | jq -r .shieldedNodes.enabled)" == "true" ] && echo "enable-shielded-nodes"

# --- Print Node Pool Configurations ---
NODE_POOLS=$(echo "$CLUSTER_DATA" | jq -r '.nodePools[].name')

for POOL in $NODE_POOLS; do
    POOL_DATA=$(echo "$CLUSTER_DATA" | jq --arg p "$POOL" '.nodePools[] | select(.name == $p)')
    echo " && gcloud beta container \\"
    echo "project \"$PROJECT_ID\" node-pools create \"$POOL\""
    echo "cluster \"$CLUSTER_NAME\""
    echo "region \"$(echo "$POOL_DATA" | jq -r .locations[0] | cut -d'-' -f1,2)\"" # Infer region from first zone
    echo "node-version \"$(echo "$POOL_DATA" | jq -r .version)\""
    echo "machine-type \"$(echo "$POOL_DATA" | jq -r .config.machineType)\""
    echo "image-type \"$(echo "$POOL_DATA" | jq -r .config.imageType)\""
    echo "disk-type \"$(echo "$POOL_DATA" | jq -r .config.diskType)\""
    echo "disk-size \"$(echo "$POOL_DATA" | jq -r .config.diskSizeGb)\""

    labels=$(format_key_value "$(echo "$POOL_DATA" | jq .config.labels)")
    [ -n "$labels" ] && echo "node-labels $labels"
    metadata=$(format_key_value "$(echo "$POOL_DATA" | jq .config.metadata)")
    [ -n "$metadata" ] && echo "metadata $metadata"
    taints=$(format_taints "$(echo "$POOL_DATA" | jq .config.taints)")
    [ -n "$taints" ] && echo "node-taints $taints"

    echo "service-account \"$(echo "$POOL_DATA" | jq -r .config.serviceAccount)\""
    echo "num-nodes \"$(echo "$POOL_DATA" | jq -r .initialNodeCount)\""

    if [ "$(echo "$POOL_DATA" | jq -r .autoscaling.enabled)" == "true" ]; then
        echo "enable-autoscaling"
        echo "min-nodes \"$(echo "$POOL_DATA" | jq -r .autoscaling.minNodeCount)\""
        echo "max-nodes \"$(echo "$POOL_DATA" | jq -r .autoscaling.maxNodeCount)\""
        echo "location-policy \"$(echo "$POOL_DATA" | jq -r .autoscaling.locationPolicy)\""
    fi

    [ "$(echo "$POOL_DATA" | jq -r .management.autoUpgrade)" == "true" ] && echo "enable-autoupgrade"
    [ "$(echo "$POOL_DATA" | jq -r .management.autoRepair)" == "true" ] && echo "enable-autorepair"

    echo "max-surge-upgrade $(echo "$POOL_DATA" | jq -r .upgradeSettings.maxSurge)"
    MAX_UNAVAILABLE=$(echo "$POOL_DATA" | jq -r .upgradeSettings.maxUnavailable)
    [ "$MAX_UNAVAILABLE" != "null" ] && echo "max-unavailable-upgrade $MAX_UNAVAILABLE"
    echo "max-pods-per-node \"$(echo "$POOL_DATA" | jq -r .maxPodsConstraint.maxPodsPerNode)\""

    [ "$(echo "$POOL_DATA" | jq -r .config.shieldedInstanceConfig.enableIntegrityMonitoring)" == "true" ] && echo "shielded-integrity-monitoring"
    [ "$(echo "$POOL_DATA" | jq -r .config.shieldedInstanceConfig.enableSecureBoot)" == "true" ] && echo "shielded-secure-boot"

    # Handle null tags array gracefully by providing a default empty array
    tags=$(echo "$POOL_DATA" | jq -r '(.config.tags // []) | join(",")')
    [ -n "$tags" ] && echo "tags \"$tags\""
    # Handle null locations array gracefully
    locations=$(echo "$POOL_DATA" | jq -r '(.locations // []) | join(",")')
    [ -n "$locations" ] && echo "node-locations \"$locations\""
done
