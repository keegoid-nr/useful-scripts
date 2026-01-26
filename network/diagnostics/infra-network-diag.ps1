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


# Parse command-line options
param (
    [int]$PathpingCount = 20,
    [string]$Proxy,
    [switch]$Help
)

# --- Section 0: Prerequisite Checks ---

# Help/Usage function
function Show-Usage {
    Write-Host "Usage: .\infra-network-diag.ps1 [-PathpingCount <count>] [-Proxy <proxy_url>]"
    Write-Host "  -PathpingCount <count>: Optional. Number of pings for pathping to send (default: 20)."
    Write-Host "  -Proxy <proxy_url>    : Optional. Proxy server URL (e.g., http://proxy.example.com:8080)."
    exit 1
}

if ($Help) {
    Show-Usage
}

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
$OUTPUT_DIR = "infra-network-diag_${TIMESTAMP}"
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


# --- Section 2b: Proxy Configuration ---
if ($Proxy) {
    Write-Host "Proxy configuration detected: $Proxy"
    Write-Host "Checking connectivity to proxy..."
    
    # Simple check to see if we can reach the proxy host/port
    try {
        $uri = [System.Uri]$Proxy
        $proxyHost = $uri.Host
        $proxyPort = $uri.Port
        if ($proxyPort -eq -1) { $proxyPort = 80 } # Default if not specified, though Uri usually handles it

        Test-NetConnection -ComputerName $proxyHost -Port $proxyPort | Format-List | Out-File -FilePath "${OUTPUT_DIR}\proxy_connectivity.txt"
        Write-Host "Proxy connectivity check saved to ${OUTPUT_DIR}\proxy_connectivity.txt"
    }
    catch {
        Write-Warning "Could not parse proxy URL or connect to proxy: $_"
        "Proxy connectivity check failed: $_" | Out-File -FilePath "${OUTPUT_DIR}\proxy_connectivity_error.txt"
    }
} else {
    Write-Host "No proxy configured."
}
Write-Host "------------------------------------------------------------"


# --- Section 3: Network Tests for New Relic Endpoints ---
Write-Host "Running network tests for New Relic endpoints..."
foreach ($endpoint in $ENDPOINTS) {
  Write-Host "--- Testing ${endpoint} ---"

  # DNS Lookup and Curl
  Write-Host "[*] Running DNS lookup and curl for ${endpoint}"
  Resolve-DnsName -Name $endpoint | Out-File -FilePath "${OUTPUT_DIR}\dns_lookup_${endpoint}.txt"
  
  $curlArgs = "-v", "https://${endpoint}/cdn-cgi/trace"
  if ($Proxy) {
      $curlArgs += "--proxy", "$Proxy"
  }
  # Capture both stdout and stderr (2>&1)
  & curl.exe $curlArgs 2>&1 | Out-File -FilePath "${OUTPUT_DIR}\curl_${endpoint}.txt"

  # Port check
  Write-Host "[*] Checking port connectivity to ${endpoint}:443"
  Test-NetConnection -ComputerName $endpoint -Port 443 | Format-List | Out-File -FilePath "${OUTPUT_DIR}\port_check_${endpoint}_443.txt"

  # Path analysis using pathping
  Write-Host "[*] Running pathping for ${endpoint}. This may take several minutes..."
  Write-Host "[*] Note: pathping uses ICMP and may provide incomplete results if firewalls block it."
  pathping.exe -q -n $PathpingCount "${endpoint}" | Out-File -FilePath "${OUTPUT_DIR}\pathping_${endpoint}.txt"

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
