# Pod Permission Inspector

![Language](https://img.shields.io/badge/language-Shell%20Script-green.svg)

A command-line utility to run a suite of diagnostic checks inside a running Kubernetes pod to troubleshoot permissions, capabilities, and configuration issues.

## Features ✨

- **Flexible Pod Targeting**: Find pods using a label selector or pipe a list of pod names directly from `kubectl get po`.
- **Multi-Pod Processing**: Inspects all pods that match the criteria, not just the first one.
- **Namespace & Container Selection**: Specify a target namespace (`-n`) and a specific container (`-c`) within the pod.
- **Intelligent Validation**: Automatically verifies that pods are running and that specified containers exist before attempting to run checks.
- **Resilient Execution**: Includes an automatic retry mechanism with configurable retries (`-r`) and intervals (`-s`) to handle transient errors when a pod is starting up.
- **Split Output**: Keeps the terminal clean with high-level status messages while logging all detailed inspection output to a file.

## Prerequisites

- **`bash`**: The script is written in bash and should run on any modern Linux or macOS system.
- **`kubectl`**: You must have `kubectl` installed and configured to access a Kubernetes cluster.

## Installation

1. Save the script to a file named `inspect_permissions.sh`.
2. Make it executable:

        chmod +x inspect_permissions.sh

3. (Optional) Move it to a directory in your system's `PATH` (like `/usr/local/bin`) to make it runnable from anywhere.

## Usage

    Usage: ./inspect_permissions.sh -l <label_selector> [-n <namespace>] [-c <container>] [-f <output_file>] [-r <retries>] [-s <seconds>] [-h]
           <command> | ./inspect_permissions.sh [-n <namespace>] [-c <container>] [-f <output_file>] [-r <retries>] [-s <seconds>]

### Examples

**1. Inspect all pods matching a label:**

    ./inspect_permissions.sh -l "app=my-app"

**2. Inspect pods in a specific namespace and container:**

    ./inspect_permissions.sh -n "production" -l "component=api" -c "api-server"

**3. Inspect pods from a pipeline with custom retry logic:**

    kubectl get po -n "jobs" -o name | ./inspect_permissions.sh -n "jobs" -r 5 -s 1

## Checks Performed

The script runs the following commands inside the container:

- **`id`**: Shows the user (`uid`) and group (`gid`) the container is running as.
- **`cat /proc/1/status | grep Cap`**: Displays the Linux capabilities of the container's main process.
- **`capsh --print`**: Shows the capabilities of the current shell process.
- **`ls -ld /tmp`**: Checks permissions of the `/tmp` directory.
- **`ps auxZ`**: Lists running processes with their security context.
- **`cat /etc/resolv.conf`**: Shows the DNS configuration.
- **`mount`**: Displays all mounted filesystems.
- **`node` checks (conditional)**: If `node` is present, checks its version and capabilities.

## License

This project is licensed under the Apache 2.0 License. See the [LICENSE](/LICENSE) file for details.
