# Kubernetes Cleanup Script

This script is used to clean up Kubernetes resources based on a label selector. It can remove both namespaced and cluster-scoped resources.

## Description

The script performs the following actions:

1. **Identifies resources:** It finds all resources matching a given label selector. It can be configured to run with a default set of labels or a label provided as an argument.
2. **Removes finalizers:** It patches the identified resources to remove any finalizers. This is useful for resources that are stuck in a `Terminating` state.
3. **Deletes resources:** It deletes the resources after the finalizers have been removed.

The script categorizes resources into two types for processing:

- **Namespaced Resources:** `deploy`, `sts`, `ds`, `rs`, `job`, `service`, `sa`, `po`, `secret`, `role`, `rolebinding`, `configmap`, `cj`
- **Cluster-Scoped Resources:** `clusterrole`, `clusterrolebinding`, `validatingwebhookconfigurations`, `mutatingwebhookconfigurations`

A confirmation prompt is included to prevent accidental deletion of resources.

## Usage

```shell
./k8s-cleanup.sh [LABEL_SELECTOR] [NAMESPACE]
```

### Arguments

- `LABEL_SELECTOR` (optional): The label selector to use for finding resources. If not provided, the script will use a default list of selectors:
  - `app.kubernetes.io/instance=nri-bundle`
  - `app.kubernetes.io/name=newrelic-logging`
- `NAMESPACE` (optional): The namespace to clean up. If not provided, the script will use the current namespace from your `kubectl` context, or `default` if not set.

### Examples

**Clean up resources with a specific label:**

```shell
./k8s-cleanup.sh "app.kubernetes.io/instance=my-app"
```

**Clean up resources with a specific label in a specific namespace:**

```shell
./k8s-cleanup.sh "app.kubernetes.io/instance=my-app" "my-namespace"
```

**Clean up resources using the default labels in a specific namespace:**

```shell
./k8s-cleanup.sh "" "my-namespace"
```

**Clean up resources using the default labels:**

```shell
./k8s-cleanup.sh
```
