# GKE Configuration Scraper

![Language](https://img.shields.io/badge/language-Shell%20Script-green.svg)

This script inspects a Google Kubernetes Engine (GKE) cluster and its associated node pools using the `gcloud` command-line tool. It then outputs the configuration in a declarative format that resembles the `gcloud container create` and `gcloud container node-pools create` commands.

## Purpose

The primary goal of this script is to provide a quick and readable summary of a GKE cluster's configuration. This is useful for:

* **Auditing:** Quickly reviewing key cluster settings.
* **Documentation:** Generating a snapshot of the cluster's state for record-keeping.
* **Replication:** Providing a template that can be adapted to recreate a similar cluster in another project or region.
* **Troubleshooting:** Comparing configurations between different clusters.

## Prerequisites

Before running this script, you must have the following installed and configured:

1. **Google Cloud SDK (`gcloud`)**: The script relies on `gcloud` to interact with your GCP project. You must be authenticated with an account that has at least the `container.clusters.get` IAM permission for the target project.
2. **`jq`**: This script uses `jq`, a lightweight and flexible command-line JSON processor, to parse the output from `gcloud` commands.

## Usage

Follow these steps to run the script:

1. **Configure Environment Variables:**
    This script reads its configuration from a `.env` file in the same directory. Copy the example file to create your own configuration:

    ```sh
    cp .env.example .env
    ```

    Open the newly created `.env` file and replace the placeholder values with your specific cluster information.

    ```sh
    # .env
    PROJECT_ID="your-gcp-project-id"
    CLUSTER_NAME="your-cluster-name"
    REGION="your-cluster-region"
    ```

2. **Make the Script Executable:**
    In your terminal, grant execute permissions to the script:

    ```sh
    chmod +x gke_config_scraper.sh
    ```

3. **Run the Script:**
    Execute the script from your terminal:

    ```sh
    ./gke_config_scraper.sh
    ```

## Example Output

The script will print the configuration directly to your terminal. The output will look similar to this:

```sh
Fetching cluster data for my-gke-cluster in project my-gcp-project...

project "my-gcp-project" "my-gke-cluster"
region "us-central1"
no-enable-basic-auth
cluster-version "1.28.2-gke.1098000"
release-channel "regular"
machine-type "e2-medium"

# ... more cluster configuration
 && gcloud beta container \
project "my-gcp-project" node-pools create "default-pool"
cluster "my-gke-cluster"
region "us-central1"
node-version "1.28.2-gke.1098000"
machine-type "e2-medium"

# ... more node pool configuration
```

## How It Works

The script performs the following actions:

1. Loads the `PROJECT_ID`, `CLUSTER_NAME`, and `REGION` from the `.env` file.
2. Executes a single `gcloud container clusters describe` command to fetch a comprehensive JSON object containing all cluster and node pool data.
3. Uses `jq` to parse this JSON object, extracting key-value pairs and formatting them into the desired output format.
4. It includes helper functions to gracefully handle optional or `null` configuration values (like taints, labels, and tags) to prevent errors.

## License

This project is licensed under the Apache 2.0 License.
