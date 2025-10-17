# Useful Scripts

![Language](https://img.shields.io/badge/language-Shell%20Script-green.svg) &nbsp; &nbsp; ![Language](https://img.shields.io/badge/language-PowerShell-012456.svg) &nbsp; &nbsp; ![Language](https://img.shields.io/badge/language-Python-3776AB.svg)

A collection of scripts for various purposes.

## Disclaimer

**This is not an official New Relic product. This is an open source project, provided as-is. Use at your own risk.**

The scripts and tools in this repository are not officially supported by New Relic. They are provided for experimental and educational purposes. You are solely responsible for any consequences of using these scripts.

## Scripts

### Kubernetes

* [Helm Image Inspector](./kubernetes/dependencies/helm-image-inspector.sh): Inspects images in a Helm chart.
* [Get GKE Info](./kubernetes/gke_info/get-gke-info.sh): Retrieves information about a GKE cluster.
* [Inspect Permissions](./kubernetes/permissions/inspect-permissions.sh): Inspects user/service account permissions in Kubernetes.

### Network

* [Infrastructure Network Diagnostics](./network/diagnostics/infra-network-diag.sh): Runs network diagnostics for infrastructure. (Linux/macOS)
* [Infrastructure Network Diagnostics (PowerShell)](./network/diagnostics/infra-network-diag.ps1): Runs network diagnostics for infrastructure. (Windows)
* [Test OTLP Endpoint](./network/test-otlp-endpoint.sh): Sends a test OTLP trace to an endpoint.

### Synthetics Private Locations

* [SJM Cron Job](./synthetics_private_locations/cron_jobs/sjm-cron-job.sh): Example cron job for running a Synthetics Job Manager.
* [SJM Cron Job (Podman)](./synthetics_private_locations/cron_jobs/sjm-cron-job-podman.sh): Example cron job for running a Synthetics Job Manager using Podman.
* [Manage Monitors](./synthetics_private_locations/manage_monitors/manage-monitors.py): A script to manage Synthetics monitors.
* [Parking Lot Jobs](./synthetics_private_locations/throughput/parking-lot-jobs.sh): Script for managing parking lot jobs.
* [Remove Ping Logs](./synthetics_private_locations/throughput/remove-ping-logs.sh): Removes ping logs.

### Utils

* [Decode HTML](./utils/decode-html.sh): Decodes HTML entities.
* [PR Tracker](./utils/pr_tracker/pr-tracker.py): Tracks pull requests.

## Contributing

Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.

## License

This project is licensed under the [Apache 2.0 License](./LICENSE).
