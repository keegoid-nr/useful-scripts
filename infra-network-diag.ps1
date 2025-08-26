#Requires -RunAsAdministrator

# New Relic Infra Network Diagnostics Script for Windows
# This script collects network diagnostics information
# related to the Infra agent for New Relic support cases.
#
# Author : Keegan Mullaney
# Company: New Relic
# Email  : kmullaney@newrelic.com
# Website: github.com/keegoid-nr/useful-scripts
# License: Apache License 2.0


# --- Section 0: Prerequisite Checks ---
# Check if script is being run as Administrator
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run as an Administrator to access system logs and tools."
    Write-Error "Please right-click the script and select 'Run as Administrator'."
    exit 1
}

# Check for critical tools
$CRITICAL_TOOLS = @("pathping", "curl")
foreach ($tool in $CRITICAL_TOOLS) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        Write-Error "'$tool' is not installed and is required for this script."
        Write-Error "Please ensure it is available in your system's PATH and rerun the script."
        exit 1
    }
}
Write-Host "Prerequisite checks passed."


# --- Section 1: Configuration ---
# New Relic endpoints to test
$ENDPOINTS = @(
  "metric-api.newrelic.com",
  "infra-api.newrelic.com",
  "infrastructure-command-api.newrelic.com",
  "log-api.newrelic.com"
)


# --- Script Start ---
# Create a unique directory for the output files
$TIMESTAMP = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$OUTPUT_DIR = "infra_network_diag_${TIMESTAMP}"
New-Item -ItemType Directory -Path $OUTPUT_DIR | Out-Null
Write-Host "All outputs will be saved in the .\$($OUTPUT_DIR) directory."
Write-Host "------------------------------------------------------------"


# --- Section 2: System and DNS Info ---
Write-Host "Collecting DNS and system info..."
ipconfig /all | Out-File -FilePath "${OUTPUT_DIR}\ipconfig_all.txt"
Get-DnsClientServerAddress -AddressFamily IPv4 | Format-List | Out-File -FilePath "${OUTPUT_DIR}\dns_servers.txt"
systeminfo | Out-File -FilePath "${OUTPUT_DIR}\systeminfo.txt"
Get-NetIPConfiguration | Format-List | Out-File -FilePath "${OUTPUT_DIR}\net_ip_configuration.txt"
Write-Host "------------------------------------------------------------"


# --- Section 3: Network Tests for New Relic Endpoints ---
Write-Host "Running network tests for New Relic endpoints..."
foreach ($endpoint in $ENDPOINTS) {
  Write-Host "--- Testing ${endpoint} ---"

  # DNS Lookup and Curl
  Write-Host "[*] Running DNS lookup and curl for ${endpoint}"
  Resolve-DnsName -Name $endpoint | Out-File -FilePath "${OUTPUT_DIR}\dns_lookup_${endpoint}.txt"
  curl.exe -v "https://${endpoint}/cdn-cgi/trace" 2>&1 | Out-File -FilePath "${OUTPUT_DIR}\curl_${endpoint}.txt"

  # Port check
  Write-Host "[*] Checking port connectivity to ${endpoint}:443"
  Test-NetConnection -ComputerName $endpoint -Port 443 | Format-List | Out-File -FilePath "${OUTPUT_DIR}\port_check_${endpoint}_443.txt"

  # Path analysis using pathping
  Write-Host "[*] Running pathping for ${endpoint}. This may take several minutes..."
  Write-Host "[*] Note: pathping uses ICMP and may provide incomplete results if firewalls block it."
  pathping.exe -n -q 20 "${endpoint}" | Out-File -FilePath "${OUTPUT_DIR}\pathping_${endpoint}.txt"

  Write-Host "--- Finished ${endpoint} ---"
}
Write-Host "------------------------------------------------------------"


# --- Section 4: Collect Firewall Details and Logs ---
Write-Host "Collecting firewall rules and logs..."
netsh advfirewall firewall show rule name=all | Out-File -FilePath "${OUTPUT_DIR}\firewall_rules.txt"
Write-Host "Note: If using a cloud provider, please also export security group/network ACL rules."

# Get New Relic agent logs if they exist
$nrLogPath = "C:\Program Files\New Relic\newrelic-infra\newrelic-infra.log"
if (Test-Path $nrLogPath) {
    Get-Content $nrLogPath -Tail 5000 | Out-File -FilePath "${OUTPUT_DIR}\newrelic-infra_last5000.log"
}

# Get recent system and application event logs
Write-Host "Collecting recent event logs..."
Get-WinEvent -LogName System -MaxEvents 1000 | Format-List | Out-File -FilePath "${OUTPUT_DIR}\eventlog_system_last1000.txt"
Get-WinEvent -LogName Application -MaxEvents 1000 | Format-List | Out-File -FilePath "${OUTPUT_DIR}\eventlog_application_last1000.txt"
Write-Host "------------------------------------------------------------"


# --- Section 5: Final Step ---
Write-Host "Compressing all output files..."
Compress-Archive -Path "${OUTPUT_DIR}\*" -DestinationPath "${OUTPUT_DIR}.zip"
Write-Host "Done! Please attach the $($OUTPUT_DIR).zip file to your New Relic support case for analysis."
