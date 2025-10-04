# New Relic Infrastructure Agent Network Diagnostics Scripts

![Language](https://img.shields.io/badge/language-Shell%20Script-green.svg) &nbsp; &nbsp; ![Language](https://img.shields.io/badge/language-PowerShell-012456.svg)

This directory contains scripts designed to help diagnose network connectivity issues between a host and the New Relic platform, specifically for the Infrastructure agent.

These scripts are intended to be run on the host where the Infrastructure agent is experiencing issues. They collect a variety of network and system information, run connectivity tests to New Relic endpoints, and package the results into a compressed archive for easy sharing with New Relic support.

## Scripts

- **`infra_network_diag.sh`**: A Bash script for Linux and macOS systems.
- **`infra_network_diag.ps1`**: A PowerShell script for Windows systems.

## Features

- **System & DNS Information**: Collects details about the host's network configuration, DNS resolvers, and system information.
- **New Relic Endpoint Testing**: Performs a series of tests against New Relic's core infrastructure endpoints, including:
  - DNS lookups
  - `curl` requests to check for HTTPS connectivity and trace routes.
  - Port checks on `443`.
  - `mtr` (on Linux/macOS) or `pathping` (on Windows) to analyze the network path for packet loss and latency.
- **Firewall & Log Collection**: Gathers local firewall rules and recent New Relic agent and system logs.
- **Automated Archiving**: Compresses all output files into a single `.tar.gz` (Linux/macOS) or `.zip` (Windows) file.

## Usage

### Linux / macOS

1. **Download** the `infra_network_diag.sh` script to the affected host.
2. **Make it executable**:

    ```bash
    chmod +x infra_network_diag.sh
    ```

3. **Run the script with `sudo`**:

    ```bash
    sudo ./infra_network_diag.sh
    ```

#### Optional Arguments

- `-c <count>`: Sets the number of packets `mtr` sends to each New Relic endpoint. The default is `20`.

    ```bash
    sudo ./infra_network_diag.sh -c 50
    ```

### Windows

1. **Download** the `infra_network_diag.ps1` script to the affected host.
2. **Open PowerShell as an Administrator**.
3. **Navigate to the directory** where you downloaded the script.
4. **Run the script**:

    ```powershell
    .\infra_network_diag.ps1
    ```

#### Optional Arguments

- `-PathpingCount <count>`: Sets the number of pings `pathping` sends to each New Relic endpoint. The default is `20`.

    ```powershell
    .\infra_network_diag.ps1 -PathpingCount 50
    ```

## Output

The script will create a directory named `infra_network_diag_<timestamp>` containing all the diagnostic files. It will then create a compressed archive of this directory (`.tar.gz` or `.zip`).

Please attach this compressed archive to your New Relic support case.

## License

This project is licensed under the Apache 2.0 License. See the [LICENSE](/LICENSE) file for details.
