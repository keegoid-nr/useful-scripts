# New Relic Network Diagnostics Scripts

![Language](https://img.shields.io/badge/language-Shell%20Script-green.svg) &nbsp; &nbsp; ![Language](https://img.shields.io/badge/language-PowerShell-012456.svg)

This directory contains scripts designed to help diagnose network connectivity issues between a host and the New Relic platform for all New Relic agents and telemetry endpoints.

These scripts are intended to be run on hosts experiencing connectivity issues with New Relic. They collect a variety of network and system information, run connectivity tests to New Relic endpoints, and package the results into a compressed archive for easy sharing with New Relic support.

## Supported Agent Types

- **APM** (Application Performance Monitoring)
- **Browser Monitoring**
- **Mobile Monitoring**
- **Infrastructure Monitoring**
- **OpenTelemetry**
- **Ingest APIs** (Event, Log, Metric, Trace)

## Scripts

- **`nr-network-diag.sh`**: A Bash script for Linux and macOS systems supporting all New Relic agent types.
- **`infra-network-diag.ps1`**: A PowerShell script for Windows systems (Infrastructure agent only).

## Features

- **Multi-Agent Support**: Interactive menu to select which New Relic agent type to troubleshoot (APM, Browser, Mobile, Infrastructure, OpenTelemetry, APIs, or all).
- **Data Center Region Support**: Test endpoints for US or EU data center regions.
- **System & DNS Information**: Collects details about the host's network configuration, DNS resolvers, and system information.
- **New Relic Endpoint Testing**: Performs a series of tests against agent-specific New Relic endpoints, including:
  - DNS lookups
  - `curl` requests to check for HTTPS connectivity and trace routes.
  - Port checks on `443` (and `4317`/`4318` for OpenTelemetry).
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

1. **Download** the `nr-network-diag.sh` script to the affected host.
2. **Make it executable**:

    ```sh
    chmod +x nr-network-diag.sh
    ```

3. **Run the script with `sudo`**:

    ```sh
    sudo ./nr-network-diag.sh
    ```

    The script will prompt you to select which agent type to troubleshoot.

#### Command-Line Arguments

- `-a <agent_type>`: Agent type to test. Options: `apm`, `browser`, `mobile`, `infrastructure`, `opentelemetry`, `apis`, `all`. If omitted, an interactive menu will be displayed.
- `-r <region>`: Data center region. Options: `us` (default), `eu`.
- `-c <count>`: Number of packets `mtr` sends to each endpoint (default: `20`).
- `-p <proxy_url>`: Proxy server URL for `curl` requests. Supports HTTP, HTTPS, and SOCKS proxies with optional authentication. Note that `mtr` traffic will not use the proxy.

#### Examples

**Interactive mode** (prompts for agent selection):

```sh
sudo ./nr-network-diag.sh
```

**Test APM agent in US region**:

```sh
sudo ./nr-network-diag.sh -a apm
```

**Test Browser monitoring in EU region**:

```sh
sudo ./nr-network-diag.sh -a browser -r eu
```

**Test Infrastructure agent with custom MTR packet count**:

```sh
sudo ./nr-network-diag.sh -a infrastructure -c 50
```

**Test all agent types**:

```sh
sudo ./nr-network-diag.sh -a all
```

#### Proxy Examples

The script supports a wide range of proxy configurations through curl's proxy support:

**HTTP proxy**:

```sh
sudo ./nr-network-diag.sh -a apm -p "http://proxy.example.com:8080"
```

**HTTPS proxy**:

```sh
sudo ./nr-network-diag.sh -a apm -p "https://proxy.example.com:8080"
```

**HTTP proxy with authentication**:

```sh
sudo ./nr-network-diag.sh -a apm -p "http://username:password@proxy.example.com:8080"
```

**HTTP proxy with custom port**:

```sh
sudo ./nr-network-diag.sh -a apm -p "http://proxy.example.com:3128"
```

**SOCKS5 proxy**:

```sh
sudo ./nr-network-diag.sh -a apm -p "socks5://proxy.example.com:1080"
```

**SOCKS5 proxy with authentication**:

```sh
sudo ./nr-network-diag.sh -a apm -p "socks5://username:password@proxy.example.com:1080"
```

**Combined example** (APM, EU region, custom packet count, proxy with auth):

```sh
sudo ./nr-network-diag.sh -a apm -r eu -c 30 -p "http://user:pass@proxy.example.com:8080"
```

> **Note**: Special characters in passwords may need to be URL-encoded (e.g., `@` becomes `%40`, `:` becomes `%3A`).

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

The script will create a directory named `nr-network-diag_<agent_type>_<region>_<timestamp>` containing all the diagnostic files, including:

- **`SUMMARY.txt`**: A comprehensive summary report with test results, detected issues, and recommendations
- DNS lookup results for each endpoint
- HTTPS connectivity test results
- MTR/pathping network traces
- Port connectivity checks
- System and DNS configuration files
- Firewall rules and agent logs (when available)

The script will then create a compressed archive of this directory (`.tar.gz` or `.zip`).

**Important**: Review the `SUMMARY.txt` file first to understand any detected issues, then attach the compressed archive to your New Relic support case.

### Example Output Directories

- `nr-network-diag_apm_us_2026-02-17_14-30-45/`
- `nr-network-diag_browser_eu_2026-02-17_14-35-22/`
- `nr-network-diag_all_us_2026-02-17_14-40-10/`

## License

This project is licensed under the Apache 2.0 License.
