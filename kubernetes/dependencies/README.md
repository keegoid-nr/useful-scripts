# Helm Chart Image Inspector

![Language](https://img.shields.io/badge/language-Shell%20Script-green.svg)

A versatile command-line tool to inspect any Helm chart—local or remote—and discover all container images used across the chart and its dependencies.

This is useful for quickly verifying image versions before a deployment, for security scanning, or for simply understanding what's inside a complex chart.

## Features

* **Universal**: Inspects any Helm chart from any repository.
* **Local & Remote Modes**: Can inspect a chart from a remote repository or a release already deployed to your Kubernetes cluster.
* **New Relic Aware**: An interactive mode (`--newrelic`) provides a curated list of New Relic charts and automatically applies the necessary presets for a seamless inspection.
* **Dependency Aware**: Resolves and includes images from all sub-charts.
* **External Configuration**: Chart presets are managed in an external `chart-presets.txt` file, making them easy to update without modifying the script.
* **Readability**: Provides clear, color-coded output that groups images by their parent chart and highlights version tags for easy scanning.

## Prerequisites

Before running the script, ensure you have the following command-line tools installed:

* `helm`
* `kubectl` (for local mode)
* `jq`
* `grep`
* `awk`
* `sort`
* `uniq`

## Usage

1. **Make the script executable:**

   ```sh
   chmod +x helm-image-inspector.sh
   ```

2. **Run the script in one of the three modes:**

   **A) New Relic Interactive Mode (Recommended for New Relic charts):**

   This mode will prompt you to select a chart from the New Relic repository and automatically apply the necessary configurations.

   ```sh
   ./helm-image-inspector.sh --newrelic
   ```

   **B) Repo Mode (For any chart in a repository):**

   Specify the repository and chart name. You can also provide an optional version and pass-through any standard Helm flags, like `--set`.

   ```sh
   # Inspect the latest version
   ./helm-image-inspector.sh newrelic/synthetics-job-manager --set synthetics.privateLocationKey=dummy-key

   # Inspect a specific version
   ./helm-image-inspector.sh jetstack/cert-manager v1.10.0
   ```

   **C) Local Mode (For a deployed release):**

   This mode will scan your current Kubernetes context for deployed Helm releases and prompt you to select one to inspect.

   ```sh
   ./helm-image-inspector.sh --local
   ```

## Managing Presets

The script uses a `chart-presets.txt` file to manage the required `--set` flags for complex charts in the `--newrelic` mode. This file must be in the same directory as the script.

You can easily add or modify presets by editing this file. The format is simple:

```txt
<repo>/<chart-name>: --set key1=value1 --set key2=value2
```

**Example:**
`newrelic/nri-bundle: --set global.cluster=dummy --set global.licenseKey=dummy`

## How It Works

The script automates the following workflow:

1. **Mode Detection**: It first determines whether to run in `repo`, `local`, or `newrelic` mode based on the arguments provided.
2. **Setup**: It creates a temporary directory for all operations, which is automatically cleaned up when the script exits.
3. **Fetch & Template (Repo Mode)**:
   * It uses `helm search` to find the latest version, then `helm pull` to download the chart.
   * It runs `helm dependency update` to fetch any sub-charts.
   * It runs `helm template --debug`, which adds `# Source:` comments that trace each manifest back to its parent chart.
4. **Get Manifest (Local Mode)**: It runs `helm get manifest` to retrieve the rendered Kubernetes YAML from a deployed release.
5. **Parse**: The output from either mode is piped to a powerful `awk` script. This script reads the stream, tracks the current chart using the source comments or Helm labels, and extracts all the image names. It also enriches the output with version information from the chart's `Chart.lock` file (in repo mode) or from the `helm.sh/chart` label (in local mode).
6. **Display**: The final, formatted list is printed to the console.

## License

This project is licensed under the Apache 2.0 License.
