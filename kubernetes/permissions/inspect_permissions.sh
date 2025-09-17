#!/bin/bash
# A script to inspect permissions and capabilities inside one or more pods.
#
# Author : Keegan Mullaney
# Company: New Relic
# Email  : kmullaney@newrelic.com
# Website: github.com/keegoid-nr/useful-scripts
# License: Apache License 2.0

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Functions ---
usage() {
  echo "Usage: $0 -l <label_selector> [-n <namespace>] [-f <output_file>] [-h]"
  echo "       <command> | $0 [-n <namespace>] [-f <output_file>]"
  echo
  echo "  -l <label_selector>   (Required in flag mode) Find pod by label."
  echo "  -n <namespace>        (Optional) The namespace for the pod(s)."
  echo "  -f <output_file>      (Optional) File to save all output. Defaults to a timestamped log file."
  echo "  -h                    Display this help message."
  exit 1
}

run_inspection() {
  local POD_NAME="$1"
  local KCTL_EXEC_CMD="$2"
  local LOG_FILE="$3"

  # This status message goes ONLY to the terminal for a clean UX.
  echo "✅ Inspecting pod: $POD_NAME (logging details to $LOG_FILE)..."

  # This command group appends its output (stdout & stderr) ONLY to the log file.
  {
    echo "-------------------------------------------"
    echo "✅ Inspecting pod: $POD_NAME"
    echo "-------------------------------------------"
    $KCTL_EXEC_CMD -i "$POD_NAME" -- bash <<EOF
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
  } >> "$LOG_FILE" 2>&1
}

# --- Main Script Logic ---
LABEL=""
LOG_FILE=""
NAMESPACE=""
while getopts "l:n:f:h" opt; do
  case ${opt} in
    l) LABEL=$OPTARG ;;
    n) NAMESPACE=$OPTARG ;;
    f) LOG_FILE=$OPTARG ;;
    h) usage ;;
    \?) usage ;;
  esac
done

if [[ -z "$LOG_FILE" ]]; then
  TIMESTAMP=$(date +'%Y%m%d-%H%M%S')
  LOG_FILE="pod-permissions-${TIMESTAMP}.log"
fi

KCTL_GET_CMD="kubectl get pod"
KCTL_EXEC_CMD="kubectl exec"
if [[ -n "$NAMESPACE" ]]; then
  KCTL_GET_CMD+=" --namespace $NAMESPACE"
  KCTL_EXEC_CMD+=" --namespace $NAMESPACE"
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
      run_inspection "$POD_NAME" "$KCTL_EXEC_CMD" "$LOG_FILE"
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
  # Get all pods, not just running ones, so we can report on skipped pods.
  POD_NAMES=$($KCTL_GET_CMD \
    --selector="$LABEL" \
    --output=jsonpath='{.items[*].metadata.name}')

  if [[ -z "$POD_NAMES" ]]; then
    echo "❌ Error: No pods found with label '$LABEL'."
    exit 1
  fi
  
  for POD_NAME in $POD_NAMES; do
    # Check the status of each pod before trying to exec.
    STATUS=$($KCTL_GET_CMD "$POD_NAME" -o jsonpath='{.status.phase}' 2>/dev/null)
    if [[ "$STATUS" == "Running" ]]; then
      run_inspection "$POD_NAME" "$KCTL_EXEC_CMD" "$LOG_FILE"
    else
      echo "⚠️ Skipping pod '$POD_NAME' (Status: $STATUS)"
    fi
  done
fi

echo "✨ Inspection complete."
