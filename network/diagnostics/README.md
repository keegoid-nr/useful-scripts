# New Relic Infrastructure Agent Network Diagnostics Scripts

![Language](https://img.shields.io/badge/language-Shell%20Script-green.svg) &nbsp; &nbsp; ![Language](https://img.shields.io/badge/language-PowerShell-012456.svg)

This directory contains scripts designed to help diagnose network connectivity issues between a host and the New Relic platform, specifically for the Infrastructure agent.

These scripts are intended to be run on the host where the Infrastructure agent is experiencing issues. They collect a variety of network and system information, run connectivity tests to New Relic endpoints, and package the results into a compressed archive for easy sharing with New Relic support.

## Scripts

- **`infra-network-diag.sh`**: A Bash script for Linux and macOS systems.
- **`infra-network-diag.ps1`**: A PowerShell script for Windows systems.

## Features

- **System & DNS Information**: Collects details about the host's network configuration, DNS resolvers, and system information.
- **New Relic Endpoint Testing**: Performs a series of tests against New Relic's core infrastructure endpoints, including:
  - DNS lookups
  - `curl` requests to check for HTTPS connectivity and trace routes.
  - Port checks on `443`.
  - `mtr` (on Linux/macOS) or `pathping` (on Windows) to analyze the network path for packet loss and latency.
- **Intelligent Test Analysis**: Automatically analyzes test results and provides specific recommendations for any connectivity issues detected.
- **Real-Time Progress Tracking**:
  - Displays estimated run time at startup
  - Shows progress indicators during long-running tests
  - Reports pass/fail/warning counts as tests complete
- **Comprehensive Summary Report**: Generates a `SUMMARY.txt` file with:
  - Overall test results and endpoint health status
  - Detected critical issues and warnings
  - Actionable recommendations for resolving problems
- **Proxy Verification**: When using a proxy, verifies connectivity to the proxy server before running diagnostics.
- **Smart DNS Testing**: Checks if DNS servers respond to ICMP before running MTR traces (avoids long timeouts with cloud DNS servers).
- **Firewall & Log Collection**: Gathers local firewall rules and recent New Relic agent and system logs.
- **Automated Archiving**: Compresses all output files into a single `.tar.gz` (Linux/macOS) or `.zip` (Windows) file.

## Usage

### Linux / macOS

1. **Download** the `infra-network-diag.sh` script to the affected host.
2. **Make it executable**:

    ```sh
    chmod +x infra-network-diag.sh
    ```

3. **Run the script with `sudo`**:

    ```sh
    sudo ./infra-network-diag.sh
    ```

#### Optional Arguments

- `-c <count>`: Sets the number of packets `mtr` sends to each New Relic endpoint. The default is `20`.
- `-p <proxy_url>`: Specifies an HTTP proxy server (e.g., `http://proxy.example.com:8080`) to use for `curl` requests. Note that `mtr` traffic will not use the proxy.

    ```sh
    sudo ./infra-network-diag.sh -c 50 -p "http://your-proxy:3128"
    ```

### Windows

1. **Download** the `infra-network-diag.ps1` script to the affected host.
2. **Open PowerShell as an Administrator**.
3. **Navigate to the directory** where you downloaded the script.
4. **Run the script**:

    ```powershell
    .\infra-network-diag.ps1
    ```

#### Optional Arguments

- `-PathpingCount <count>`: Sets the number of pings `pathping` sends to each New Relic endpoint. The default is `20`.
- `-Proxy <proxy_url>`: Specifies an HTTP proxy server (e.g., `http://proxy.example.com:8080`) to use for `curl` requests. Note that `pathping` and `Test-NetConnection` will not use the proxy.

    ```powershell
    .\infra-network-diag.ps1 -PathpingCount 50 -Proxy "http://your-proxy:3128"
    ```

## Output

The script will create a directory named `infra-network-diag_<timestamp>` containing all the diagnostic files, including:

- **`SUMMARY.txt`**: A comprehensive summary report with test results, detected issues, and recommendations
- DNS lookup results for each endpoint
- HTTPS connectivity test results
- MTR/pathping network traces
- Port connectivity checks
- System and DNS configuration files
- Firewall rules and agent logs

The script will then create a compressed archive of this directory (`.tar.gz` or `.zip`).

**Important**: Review the `SUMMARY.txt` file first to understand any detected issues, then attach the compressed archive to your New Relic support case.

## License

This project is licensed under the Apache 2.0 License.
