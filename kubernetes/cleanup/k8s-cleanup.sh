#!/bin/bash

: '
K8s Cleanup Script

This script cleans up Kubernetes resources based on a label selector.

Author : Keegan Mullaney
Company: New Relic
Email  : kmullaney@newrelic.com
Website: github.com/keegoid-nr/useful-scripts
License: Apache License 2.0

Usage: ./k8s-cleanup.sh "app.kubernetes.io/instance=my-app" "my-namespace"
'

NAMESPACE=$2

# If a label is provided as the first argument, use it.
# Otherwise, set a default list of labels to process.
if [ -n "$1" ]; then
    LABEL_SELECTORS_LIST=("$1")
    echo "[CONFIG] Using label selector from argument: $1"
else
    LABEL_SELECTORS_LIST=(
        "app.kubernetes.io/instance=nri-bundle"
        "app.kubernetes.io/name=newrelic-logging"
    )
    echo "[CONFIG] Using default label selectors: "
    echo "  - ${LABEL_SELECTORS_LIST[0]}"
    echo "  - ${LABEL_SELECTORS_LIST[1]}"
fi

# Prepare namespace flag for kubectl commands and get target namespace for display
NAMESPACE_FLAG=""
TARGET_NAMESPACE=""
if [ -n "$NAMESPACE" ]; then
    NAMESPACE_FLAG="-n $NAMESPACE"
    TARGET_NAMESPACE="$NAMESPACE"
    echo "[CONFIG] Initial target namespace: $TARGET_NAMESPACE (from argument)"
else
    # No namespace argument, check kubeconfig for display purposes
    CURRENT_KUBECTL_NS=$(kubectl config view --minify --output 'jsonpath={..context.namespace}' 2>/dev/null)
    if [ -n "$CURRENT_KUBECTL_NS" ]; then
        TARGET_NAMESPACE="$CURRENT_KUBECTL_NS"
        echo "[CONFIG] Initial target namespace: $TARGET_NAMESPACE (from kubeconfig)"
    else
        TARGET_NAMESPACE="default"
        echo "[CONFIG] Initial target namespace: $TARGET_NAMESPACE (kubectl default)"
    fi
    # NOTE: NAMESPACE_FLAG remains empty, which is correct.
    # Kubectl will automatically use the current context's namespace or 'default'.
fi
echo "---"


# We separate resource types to handle them more efficiently
NAMESPACED_TYPES="deploy sts ds rs job service sa po secret role rolebinding configmap cj"
CLUSTER_SCOPED_TYPES="clusterrole clusterrolebinding validatingwebhookconfigurations mutatingwebhookconfigurations"

# --- Loop over each label selector ---
for LABEL_SELECTOR in "${LABEL_SELECTORS_LIST[@]}"; do
    echo "================================================================="
    echo "[NEW TASK] Processing for label: $LABEL_SELECTOR"
    echo "[NEW TASK] Using namespace:       $TARGET_NAMESPACE"
    echo "================================================================="

    # --- Confirmation Prompt ---
    echo "[WARNING] This script will patch and delete all resources matching the label:"
    echo "  - LABEL:      $LABEL_SELECTOR"
    echo "  - NAMESPACE:  $TARGET_NAMESPACE (for namespaced resources)"
    echo
    read -p "Are you sure you want to proceed with THIS label? (y/N) " -r response
    echo # move to new line

    if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        echo "Skipping cleanup for label: $LABEL_SELECTOR"
        echo "---"
        continue
    fi

    echo "Proceeding with cleanup for $LABEL_SELECTOR..."
    echo "---"

    # --- 1. Process Cluster-Scoped Resources (Loop Patch, Bulk Delete) ---
    # (These commands ignore the $NAMESPACE_FLAG as they are not namespaced)
    echo "[INFO] Processing Cluster-Scoped Resources..."
    for RESOURCE_TYPE in $CLUSTER_SCOPED_TYPES; do
        # Get the names of all resources of this type matching the label
        RESOURCES=$(kubectl get $RESOURCE_TYPE -l $LABEL_SELECTOR -o name 2>/dev/null)

        if [ -z "$RESOURCES" ]; then
            echo "[INFO] No cluster-scoped resources of type '$RESOURCE_TYPE' found."
            continue
        fi

        echo "[ACTION] Processing $RESOURCE_TYPE(s) with label $LABEL_SELECTOR"

        # 1.1. Loop and patch each resource individually (patch doesn't support -l)
        echo "  - Patching matching $RESOURCE_TYPE(s) to remove finalizers..."
        for RESOURCE_NAME in $RESOURCES; do
            if ! kubectl patch $RESOURCE_NAME -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null; then
                echo "  - WARNING: Patch command failed for $RESOURCE_NAME. (It may already be deleting)"
            fi
        done

        # 1.2. Delete ALL cluster resources of this type in bulk (gracefully)
        echo "  - Deleting all matching $RESOURCE_TYPE(s)..."
        if ! kubectl delete $RESOURCE_TYPE -l $LABEL_SELECTOR; then
            echo "  - ERROR: Delete command failed for $RESOURCE_TYPE(s)."
        fi
        echo "---"
    done

    # --- 2. Process Namespaced Resources (Loop Patch, Bulk Delete in target namespace) ---
    # (These commands WILL use the $NAMESPACE_FLAG)
    echo "[INFO] Processing Namespaced Resources..."
    for RESOURCE_TYPE in $NAMESPACED_TYPES; do
        # Get the names of all resources of this type matching the label in the target namespace
        RESOURCES=$(kubectl get $RESOURCE_TYPE -l $LABEL_SELECTOR $NAMESPACE_FLAG -o name 2>/dev/null)

        if [ -z "$RESOURCES" ]; then
            echo "[INFO] No namespaced resources of type '$RESOURCE_TYPE' found."
            continue
        fi

        echo "[ACTION] Processing $RESOURCE_TYPE(s) with label $LABEL_SELECTOR (in target namespace)"

        # 2.1. Loop and patch each resource individually (patch doesn't support -l)
        echo "  - Patching matching $RESOURCE_TYPE(s) to remove finalizers..."
        for RESOURCE_NAME in $RESOURCES; do
            # $RESOURCE_NAME is like "job/my-job", so we just add the namespace flag
            if ! kubectl patch $RESOURCE_NAME $NAMESPACE_FLAG -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null; then
                echo "  - WARNING: Patch command failed for $RESOURCE_NAME. (It may already be deleting)"
            fi
        done

        # 2.2. Delete ALL namespaced resources of this type in bulk (gracefully)
        echo "  - Deleting all matching $RESOURCE_TYPE(s)..."
        if ! kubectl delete $RESOURCE_TYPE -l $LABEL_SELECTOR $NAMESPACE_FLAG; then
            echo "  - ERROR: Delete command failed for $RESOURCE_TYPE(s) with label $LABEL_SELECTOR."
        fi
        echo "---"
    done

    echo "[SUCCESS] Cleanup pass complete for $LABEL_SELECTOR."

done # End of loop for LABEL_SELECTORS_LIST

echo "All cleanup tasks finished."
