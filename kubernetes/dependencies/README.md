# New Relic Bundle Chart Image Inspector

![Language](https://img.shields.io/badge/language-Shell%20Script-green.svg)

This script fetches the latest `nri-bundle` Helm chart and inspects it to discover all container images and their versions used across its various sub-charts. It renders the chart templates locally, without needing a live Kubernetes cluster, and parses the output to group images by the sub-chart they belong to.

This is useful for quickly verifying image versions before a deployment or for security scanning purposes.

-----

## Features

- **No Cluster Required**: Inspects chart images without deploying to a Kubernetes cluster.
- **Automatic Updates**: Always fetches the latest version of the `nri-bundle` chart from the New Relic Helm repository.
- **Dependency Aware**: Resolves and includes images from all sub-charts (e.g., `kube-state-metrics`, `nri-prometheus`, etc.).
- **Readability**: Provides clear, color-coded output that groups images by their parent chart and highlights version tags for easy scanning.

-----

## Prerequisites

Before running the script, ensure you have the following command-line tools installed:

- `helm`
- `grep`
- `awk`
- `sort`
- `uniq`

-----

## Usage

1. **Make the script executable:**

    ```sh
    chmod +x nri-bundle_latest_images.sh
    ```

2. **Run the script:**

    ```sh
    ./nri-bundle_latest_images.sh
    ```

    The script will handle creating a temporary directory, fetching the chart, processing the templates, and printing the final formatted list to your console.

-----

## Example Output

The output will be a list of charts and their associated container images, with versions highlighted in white.

```txt
--------------------------------------------------
Container images found in 'nri-bundle' and its dependencies:
--------------------------------------------------
kube-state-metrics:
 - registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.10.1
newrelic-infra-operator:
 - newrelic/newrelic-infra-operator:1.10.0
newrelic-infrastructure:
 - newrelic/k8s-nri-cron:1.4.1
 - newrelic/infrastructure:1.50.1
newrelic-logging:
 - newrelic/fluent-bit-output-plugin:1.14.0
nri-kube-events:
 - newrelic/nri-kube-events:2.9.0
nri-prometheus:
 - newrelic/nri-prometheus:2.11.0
...
```

*Note: Versions shown are for example purposes and may not be the latest.*

-----

## How It Works

The script automates the following workflow:

1. **Setup**: It creates a temporary directory for all operations, which is automatically cleaned up when the script exits.
2. **Helm Repo**: It adds and updates the official New Relic Helm chart repository.
3. **Fetch**: It uses `helm pull --untar` to download and unpack the latest `nri-bundle` chart locally.
4. **Template**: It runs `helm template --debug` with all major sub-charts enabled. The `--debug` flag is key, as it adds `# Source:` comments to the output, which allows us to trace each Kubernetes manifest back to its parent sub-chart.
5. **Parse**: The entire template output is piped to a powerful `awk` script. This script reads the stream line by line, tracks the current chart using the `# Source:` comments, and uses regular expressions to find and extract image names. It then formats, colorizes, and prints the final list.

-----

## License

This project is licensed under the Apache 2.0 License. See the [LICENSE](/LICENSE) file for details.
