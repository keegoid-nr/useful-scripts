# Pod Permission Inspector

A command-line utility to run a suite of diagnostic checks inside a running Kubernetes pod to troubleshoot permissions, capabilities, and configuration issues. The script can find pods via label selectors or accept a list of pods from a command pipeline.

## Features ✨

- **Flexible Pod Targeting**: Find a target pod using a label selector or pipe a list of pod names directly from `kubectl get po`.
- **Namespace Support**: Specify a target namespace using the `-n` flag.
- **Comprehensive Checks**: Runs checks for user/group IDs, Linux capabilities, filesystem permissions, process security contexts, and more.
- **Conditional Logic**: Intelligently skips checks for binaries that don't exist in the container (e.g., `node`).
- **File Logging**: Saves all output to a timestamped log file, which can be overridden with a custom filename using the `-f` flag.
- **Robust CLI**: Includes a full `getopts` implementation with a `-h` flag for help and usage instructions.

## Prerequisites

- **`bash`**: The script is written in bash and should run on any modern Linux or macOS system.
- **`kubectl`**: You must have `kubectl` installed and configured to access a Kubernetes cluster.

## Installation

1. Save the script to a file named `inspect_permissions.sh`.
2. Make it executable:

        chmod +x inspect_permissions.sh

3. (Optional) Move it to a directory in your system's `PATH` (like `/usr/local/bin`) to make it runnable from anywhere.

## Usage

The script can be run in two main modes: Flag Mode (to find a single pod) or Pipeline Mode (to process multiple pods).

    Usage: ./inspect_permissions.sh -l <label_selector> [-n <namespace>] [-f <output_file>] [-h]
           <command> | ./inspect_permissions.sh [-n <namespace>] [-f <output_file>]

### Examples

**1. Inspect a pod by label in the default namespace:**

    ./inspect_permissions.sh -l "app.kubernetes.io/name=node-api-runtime"

**2. Inspect a pod by label in a specific namespace:**

    ./inspect_permissions.sh -n "production" -l "app=my-api"

**3. Inspect a pod and save the output to a specific file:**

    ./inspect_permissions.sh -n "staging" -l "app=web-server" -f web-server-check.log

**4. Inspect all pods matching a label using a pipeline:**

    kubectl get po -n "data-processing" -l "component=worker" -o name | ./inspect_permissions.sh -n "data-processing"

## Checks Performed

The script runs the following commands inside the container to provide a full diagnostic picture:

- **`id`**: Shows the user (`uid`) and group (`gid`) the container is running as.
- **`cat /proc/1/status | grep Cap`**: Displays the Linux capabilities of the container's main process (PID 1).
- **`capsh --print`**: Shows the capabilities of the current shell process.
- **`ls -ld /tmp`**: Checks the ownership and permissions of the `/tmp` directory.
- **`ps auxZ`**: Lists all running processes along with their security context (e.g., SELinux labels).
- **`cat /etc/resolv.conf`**: Shows the DNS configuration, crucial for troubleshooting network connectivity.
- **`mount`**: Displays all mounted filesystems inside the container.
- **`node` checks (conditional)**: If the `node` binary is found, it checks its file permissions, binary capabilities (`getcap`), and version.
