#!/bin/bash
# A script to inspect permissions and capabilities inside one or more pods.
#
# Author : Keegan Mullaney
# Company: New Relic
# Email  : kmullaney@newrelic.com
# Website: github.com/keegoid-nr/useful-scripts
# License: Apache License 2.0

# --- Functions ---
usage() {
  echo "Usage: $0 -l <label_selector> [-n <namespace>] [-c <container>] [-f <output_file>] [-r <retries>] [-s <seconds>] [-h]"
  echo "       <command> | $0 [-n <namespace>] [-c <container>] [-f <output_file>] [-r <retries>] [-s <seconds>]"
  echo
  echo "  -l <label_selector>   (Required in flag mode) Find pod by label."
  echo "  -n <namespace>        (Optional) The namespace for the pod(s)."
  echo "  -c <container>        (Optional) The container name to exec into."
  echo "  -f <output_file>      (Optional) File to save all output."
  echo "  -r <retries>          (Optional) Number of times to retry a failed exec command. Default: 3."
  echo "  -s <seconds>          (Optional) Seconds to sleep between retries. Default: 2."
  echo "  -h                    Display this help message."
  exit 1
}

run_inspection() {
  local POD_NAME="$1"
  local KCTL_GET_CMD="$2"
  local KCTL_EXEC_CMD_BASE="$3"
  local LOG_FILE="$4"
  local CONTAINER_NAME_ARG="$5"
  local MAX_RETRIES="$6"
  local RETRY_INTERVAL="$7"

  if [[ -n "$CONTAINER_NAME_ARG" ]]; then
    local ALL_CONTAINERS=$($KCTL_GET_CMD "$POD_NAME" -o jsonpath='{.spec.containers[*].name}' 2>/dev/null)
    if ! [[ " $ALL_CONTAINERS " =~ " $CONTAINER_NAME_ARG " ]]; then
      echo "⚠️ Skipping pod '$POD_NAME' (container '$CONTAINER_NAME_ARG' not found)"
      return
    fi
  fi

  local CONTAINER_TO_INSPECT="$CONTAINER_NAME_ARG"
  local CONTAINER_LOG_MSG

  # If user didn't specify a container, find the default (first) one.
  if [[ -z "$CONTAINER_TO_INSPECT" ]]; then
    CONTAINER_TO_INSPECT=$($KCTL_GET_CMD "$POD_NAME" -o jsonpath='{.spec.containers[0].name}' 2>/dev/null)
    CONTAINER_LOG_MSG="default container ('$CONTAINER_TO_INSPECT')"
  else
    # Verify the specified container actually exists in the pod.
    local ALL_CONTAINERS=$($KCTL_GET_CMD "$POD_NAME" -o jsonpath='{.spec.containers[*].name}' 2>/dev/null)
    if ! [[ " $ALL_CONTAINERS " =~ " $CONTAINER_TO_INSPECT " ]]; then
      echo "⚠️ Skipping pod '$POD_NAME' (container '$CONTAINER_TO_INSPECT' not found)"
      return
    fi
    CONTAINER_LOG_MSG="specified container ('$CONTAINER_TO_INSPECT')"
  fi

  # Always build the command with the -c flag using the determined container.
  local FINAL_EXEC_CMD="$KCTL_EXEC_CMD_BASE -i $POD_NAME -c $CONTAINER_TO_INSPECT"

  echo "✅ Inspecting pod: $POD_NAME ($CONTAINER_LOG_MSG)..."

  local attempt=1
  while (( attempt <= MAX_RETRIES )); do
    local exec_output
    # The final "--" separates kubectl options from the command to be executed
    exec_output=$($FINAL_EXEC_CMD -- bash <<EOF
# This part of the script runs INSIDE the pod
echo "****** User and Group ID ******"; id;
echo; echo "****** Process Capabilities (PID 1) ******"; cat /proc/1/status | grep Cap || echo "Could not read process status.";
echo; echo "****** Current Shell Capabilities ******"; capsh --print;
echo; echo "****** Filesystem Permissions (/tmp) ******"; ls -ld /tmp;
echo; echo "****** Running Processes & Security Context ******"; ps auxZ || ps aux;
echo; echo "****** DNS Configuration ******"; cat /etc/resolv.conf;
echo; echo "****** Mount Points ******"; mount;
if command -v node &> /dev/null; then
    echo; echo "****** Node.js Info ******"; ls -lZ \$(command -v node); getcap \$(command -v node); node --version;
else
    echo; echo "****** Node.js Not Found ******";
fi
EOF
2>&1)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
      {
        echo "-------------------------------------------"
        echo "✅ Inspecting pod: $POD_NAME ($CONTAINER_LOG_MSG)"
        echo "-------------------------------------------"
        echo "$exec_output"
      } >> "$LOG_FILE"
      return 0 # Success
    fi

    if (( attempt < MAX_RETRIES )); then
      echo "⚠️ Exec failed for pod '$POD_NAME' (Attempt $attempt/$MAX_RETRIES). Retrying in $RETRY_INTERVAL seconds..."
      sleep "$RETRY_INTERVAL"
    fi
    (( attempt++ ))
  done

  echo "❌ Error: Command failed after $MAX_RETRIES attempts for pod '$POD_NAME'."
  {
    echo "-------------------------------------------"
    echo "❌ FAILED: Pod: $POD_NAME ($CONTAINER_LOG_MSG) after $MAX_RETRIES attempts."
    echo "Final error output:"
    echo "$exec_output"
    echo "-------------------------------------------"
  } >> "$LOG_FILE"
}

# --- Main Script Logic ---
LABEL=""
LOG_FILE=""
NAMESPACE=""
CONTAINER_NAME=""
RETRIES=3
INTERVAL=2
while getopts "l:n:f:c:r:s:h" opt; do
  case ${opt} in
    l) LABEL=$OPTARG ;;
    n) NAMESPACE=$OPTARG ;;
    f) LOG_FILE=$OPTARG ;;
    c) CONTAINER_NAME=$OPTARG ;;
    r) RETRIES=$OPTARG ;;
    s) INTERVAL=$OPTARG ;;
    h) usage ;;
    \?) usage ;;
  esac
done

if [[ -z "$LOG_FILE" ]]; then
  TIMESTAMP=$(date +'%Y%m%d-%H%M%S')
  LOG_FILE="pod-permissions-${TIMESTAMP}.log"
fi

KCTL_GET_CMD="kubectl get pod"
KCTL_EXEC_CMD_BASE="kubectl exec"
if [[ -n "$NAMESPACE" ]]; then
  KCTL_GET_CMD+=" --namespace $NAMESPACE"
  KCTL_EXEC_CMD_BASE+=" --namespace $NAMESPACE"
fi

if [ ! -t 0 ]; then
  echo "📥 Detected piped input. Processing..."
  if [[ -n "$LABEL" ]]; then
    echo "⚠️ Warning: Label '-l $LABEL' is ignored when using piped input."
  fi
  tail -n +2 | awk '{print $1}' | while read -r POD_NAME; do
    if [[ -z "$POD_NAME" ]]; then continue; fi
    POD_NAME=${POD_NAME#pod/}
    STATUS=$($KCTL_GET_CMD "$POD_NAME" -o jsonpath='{.status.phase}' 2>/dev/null)
    if [[ "$STATUS" == "Running" ]]; then
      run_inspection "$POD_NAME" "$KCTL_GET_CMD" "$KCTL_EXEC_CMD_BASE" "$LOG_FILE" "$CONTAINER_NAME" "$RETRIES" "$INTERVAL"
    else
      echo "⚠️ Skipping pod '$POD_NAME' (Status: $STATUS)"
    fi
  done
else
  if [[ -z "$LABEL" ]]; then
    echo "❌ Error: A label selector is required in flag mode. Use the -l flag or pipe input."
    usage
  fi
  echo "🔎 Finding all pods with label '$LABEL'..."
  POD_NAMES=$($KCTL_GET_CMD --selector="$LABEL" --output=jsonpath='{.items[*].metadata.name}')
  if [[ -z "$POD_NAMES" ]]; then
    echo "❌ Error: No pods found with label '$LABEL'."
    exit 1
  fi
  for POD_NAME in $POD_NAMES; do
    STATUS=$($KCTL_GET_CMD "$POD_NAME" -o jsonpath='{.status.phase}' 2>/dev/null)
    if [[ "$STATUS" == "Running" ]]; then
      run_inspection "$POD_NAME" "$KCTL_GET_CMD" "$KCTL_EXEC_CMD_BASE" "$LOG_FILE" "$CONTAINER_NAME" "$RETRIES" "$INTERVAL"
    else
      echo "⚠️ Skipping pod '$POD_NAME' (Status: $STATUS)"
    fi
  done
fi

echo "✨ Inspection complete."
