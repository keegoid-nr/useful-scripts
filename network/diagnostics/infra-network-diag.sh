#!/bin/bash
: '
New Relic Infrastructure Network Diagnostics

This script gathers comprehensive network diagnostics to help troubleshoot
connectivity issues between a host and New Relic endpoints. It is designed
to be run on a problematic host and the output bundled for a support case.

It performs the following actions:
- Checks system compatibility and for required tools (mtr, curl, dig/host).
- Gathers system DNS configuration (/etc/resolv.conf, etc.).
- For each New Relic endpoint, it runs:
    - DNS lookups.
    - Verbose curl tests to check TLS handshakes.
    - TCP port checks.
    - MTR (My Traceroute) reports to inspect the full network path.
- Performs connectivity tests against the configured DNS servers.
- Collects local firewall rules and recent system/agent logs.
- Packages all collected data into a single compressed tarball.

Author : Keegan Mullaney
Company: New Relic
Email  : kmullaney@newrelic.com
Website: github.com/keegoid-nr/useful-scripts
License: Apache License 2.0
'

# --- Section 0: Prerequisite Checks ---

# Displays usage information and exits.
usage() {
    echo "Usage: sudo $0 [-c <count>] [-p <proxy_url>]"
    echo "  -c <count>: Optional. Number of packets for mtr to send (default: 20)."
    echo "  -p <proxy_url>: Optional. Proxy server URL (e.g., http://proxy.example.com:8080)."
    exit 1
}

# This script requires root privileges to run tools like mtr and access certain log files.
if [[ $EUID -ne 0 ]]; then
    echo "❌ Error: This script must be run as root to access system logs and tools."
    echo "Please run it with sudo: sudo $0"
    exit 1
fi

# Function to exit if the OS is too old to support modern TLS standards (1.2+).
# The New Relic agent requires a modern TLS version to connect securely.
unsupported_os_exit() {
    echo "❌ Error: Unsupported Operating System Detected."
    echo "This script requires a modern Linux distribution to ensure tools like curl support current TLS standards (TLS 1.2+)."
    echo "Systems like CentOS/RHEL 6 are no longer supported. Please run this script on a newer host."
    exit 1
}

echo "🔎 Verifying operating system compatibility..."
if [ -f /etc/os-release ]; then
    # Modern systems use /etc/os-release, which is easy to parse.
    . /etc/os-release
    MAJOR_VERSION=$(echo "$VERSION_ID" | cut -d. -f1)

    # Check major versions of common distributions.
    case "$ID" in
        centos|rhel|almalinux|rocky)
            if [ "$MAJOR_VERSION" -lt 7 ]; then unsupported_os_exit; fi
            ;;
        ubuntu)
            if [ "$MAJOR_VERSION" -lt 16 ]; then unsupported_os_exit; fi
            ;;
        debian)
            if [ "$MAJOR_VERSION" -lt 9 ]; then unsupported_os_exit; fi
            ;;
        *)
            echo "✅ OS ($ID $VERSION_ID) not in explicit check list, proceeding."
            ;;
    esac
elif [ -f /etc/redhat-release ]; then
    # Fallback for older RHEL-based systems without /etc/os-release.
    if grep -q "release 6" /etc/redhat-release; then
        unsupported_os_exit
    fi
else
    echo "⚠️  Could not definitively determine OS version. Proceeding with caution."
fi
echo "✅ Operating system is supported."


# Verify that critical diagnostic tools are installed.
CRITICAL_TOOLS=("mtr" "curl")
for tool in "${CRITICAL_TOOLS[@]}"; do
    if ! command -v "$tool" &> /dev/null; then
        echo "❌ Error: '$tool' is not installed and is required for this script."
        echo "Please install it using your package manager and rerun the script."
        echo "e.g., 'sudo apt-get update && sudo apt-get install $tool' or 'sudo yum install $tool'"
        exit 1
    fi
done

# Find a suitable DNS lookup tool, preferring 'dig' for its detailed output.
DNS_TOOL=""
if command -v dig &> /dev/null; then
    DNS_TOOL="dig"
elif command -v host &> /dev/null; then
    DNS_TOOL="host"
elif command -v nslookup &> /dev/null; then
    DNS_TOOL="nslookup"
else
    echo "❌ Error: No DNS lookup tool found. This script requires 'dig', 'host', or 'nslookup'."
    echo "Please install 'dnsutils' (Debian/Ubuntu) or 'bind-utils' (Red Hat/CentOS) and rerun."
    exit 1
fi
echo "✅ Using '${DNS_TOOL}' for DNS lookups."


# --- Section 1: Configuration & Argument Parsing ---

# Default number of packets for MTR to send in each trace.
MTR_PACKET_COUNT=20

# Parse command-line flags (e.g., -c for packet count, -p for proxy).
while getopts ":c:p:h" opt; do
  case ${opt} in
    c )
      # Validate that the argument for -c is a positive integer.
      if [[ "${OPTARG}" =~ ^[1-9][0-9]*$ ]]; then
        MTR_PACKET_COUNT=${OPTARG}
      else
        echo "❌ Error: Invalid packet count provided for -c. Must be a positive integer." >&2
        usage
      fi
      ;;
    p )
      PROXY_URL=${OPTARG}
      ;;
    h )
      usage
      ;;
    \? )
      echo "Invalid option: -$OPTARG" >&2
      usage
      ;;
    : )
      echo "Invalid option: -$OPTARG requires an argument" >&2
      usage
      ;;
  esac
done
# Remove the parsed options from the script's arguments.
shift $((OPTIND -1))

# A list of critical New Relic ingestion endpoints for the Infrastructure agent.
ENDPOINTS=(
  "metric-api.newrelic.com"
  "infra-api.newrelic.com"
  "infrastructure-command-api.newrelic.com"
  "log-api.newrelic.com"
)


# --- Script Start ---
# Create a unique, timestamped directory to store all output files.
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
OUTPUT_DIR="infra-network-diag_${TIMESTAMP}"
mkdir -p "${OUTPUT_DIR}"
echo "✅ All outputs will be saved in the ./${OUTPUT_DIR}/ directory."
echo "✅ Using mtr packet count of ${MTR_PACKET_COUNT}."
if [ -n "$PROXY_URL" ]; then
  echo "✅ Proxy configuration detected: $PROXY_URL"
else
  echo "✅ No proxy configured."
fi
echo "------------------------------------------------------------"


# --- Section 2: System and DNS Info ---
# Collect core system files that define DNS resolution behavior.
echo "🔎 Collecting DNS and system info..."
cp /etc/resolv.conf "${OUTPUT_DIR}/resolv.conf.txt"
cp /etc/nsswitch.conf "${OUTPUT_DIR}/nsswitch.conf.txt"

# Extract DNS server IPs from resolv.conf to use for targeted tests later.
DNS_SERVERS=($(grep '^nameserver' /etc/resolv.conf | awk '{print $2}'))
if [ ${#DNS_SERVERS[@]} -eq 0 ]; then
  echo "⚠️  Could not find any DNS nameservers in /etc/resolv.conf"
else
  echo "Found DNS Servers: ${DNS_SERVERS[*]}"
fi

# If systemd-resolved is in use, get its status for more detailed DNS info.
if command -v systemd-resolve &> /dev/null; then
  systemd-resolve --status > "${OUTPUT_DIR}/systemd-resolve_status.txt"
fi
if [ -n "$PROXY_URL" ]; then
  echo "🔎 Checking connectivity to proxy..."
  # Use curl to check if the proxy itself is reachable.
  # We use -I (HEAD) and -m (max time) for a quick check.
  # We target the proxy URL itself or a known reliable site through it?
  # Usually checking the proxy port open is enough.
  
  # Extract host and port from PROXY_URL
  # Assuming format http://host:port or host:port
  # This simple extraction might be fragile but works for standard inputs.
  PROXY_HOST=$(echo $PROXY_URL | sed -E 's/https?:\/\///' | cut -d: -f1)
  PROXY_PORT=$(echo $PROXY_URL | sed -E 's/https?:\/\///' | cut -d: -f2 | sed 's/[^0-9]//g')
  
  if [ -z "$PROXY_PORT" ]; then PROXY_PORT=8080; fi # Default guess if parsing fails, mostly for log
  
  proxy_check_file="${OUTPUT_DIR}/proxy_connectivity.txt"
  echo "Testing connection to proxy $PROXY_HOST on port $PROXY_PORT..." > "$proxy_check_file"
  
  if command -v nc &>/dev/null && timeout 5 nc -vz "$PROXY_HOST" "$PROXY_PORT" &>> "$proxy_check_file"; then
      echo "Proxy reachable via nc." >> "$proxy_check_file"
      echo "✅ Proxy reachable."
  else
      echo "⚠️  Proxy check via nc failed. Trying direct curl to proxy..." >> "$proxy_check_file"
      # Just try to fetch the proxy root or a site through it.
      if curl -x "$PROXY_URL" -I "https://www.google.com" -m 5 &>> "$proxy_check_file"; then
          echo "Proxy working via curl check." >> "$proxy_check_file"
          echo "✅ Proxy working."
      else
          echo "❌ Proxy check failed. Diagnostics may fail if proxy is required."
          echo "❌ Proxy check failed." >> "$proxy_check_file"
      fi
  fi
fi
echo "------------------------------------------------------------"


# --- Section 3: Network Tests for New Relic Endpoints ---
echo "🔎 Running network tests for New Relic endpoints..."
for endpoint in "${ENDPOINTS[@]}"; do
  echo -e "\n--- Testing ${endpoint} ---"

  # Perform a standard DNS lookup and a verbose curl test.
  # The curl to /cdn-cgi/trace is a Cloudflare endpoint that returns useful connection data.
  # The -v flag shows the TLS handshake, which is critical for debugging connection errors.
  echo "[*] Running DNS lookup and curl for ${endpoint}"
  dns_lookup_file="${OUTPUT_DIR}/dns_lookup_${endpoint}.txt"
  case "${DNS_TOOL}" in
      dig)      dig "${endpoint}" > "${dns_lookup_file}" ;;
      host)     host "${endpoint}" > "${dns_lookup_file}" ;;
      nslookup) nslookup "${endpoint}" > "${dns_lookup_file}" ;;
  esac
  echo -e "\n--- Running verbose curl for ${endpoint}/cdn-cgi/trace ---" &> "${OUTPUT_DIR}/curl_${endpoint}.txt"
  
  CURL_ARGS="-v"
  if [ -n "$PROXY_URL" ]; then
      CURL_ARGS="$CURL_ARGS -x $PROXY_URL"
  fi
  
  curl $CURL_ARGS "https://${endpoint}/cdn-cgi/trace" &>> "${OUTPUT_DIR}/curl_${endpoint}.txt"
  if [ "$endpoint" != "infrastructure-command-api.newrelic.com" ]; then
    echo -e "\n\n--- Running verbose curl for ${endpoint}/worker/health ---" &>> "${OUTPUT_DIR}/curl_${endpoint}.txt"
    curl $CURL_ARGS "https://${endpoint}/worker/health" &>> "${OUTPUT_DIR}/curl_${endpoint}.txt"
  fi

  # Check raw TCP connectivity to port 443.
  # First, try 'nc' which is a standard network utility.
  # If 'nc' is unavailable or fails, fall back to bash's built-in /dev/tcp device
  # for a more reliable check that doesn't depend on external tools.
  echo "[*] Checking port connectivity to ${endpoint}:443"
  port_check_file="${OUTPUT_DIR}/port_check_${endpoint}_443.txt"
  if command -v nc &>/dev/null && timeout 5 nc -vz "${endpoint}" 443 &> "${port_check_file}"; then
    echo "Port check method: nc -vz" >> "${port_check_file}"
  else
    echo "nc -vz failed or not available, using bash fallback..." > "${port_check_file}"
    (timeout 5 bash -c "echo >/dev/tcp/${endpoint}/443") >> "${port_check_file}" 2>&1
    if [ $? -eq 0 ]; then echo "Port check method: bash. Result: Success" >> "${port_check_file}"; else echo "Port check method: bash. Result: Failure" >> "${port_check_file}"; fi
  fi

  # Run an MTR trace to inspect the network path for packet loss or latency.
  # -b: Show both IP addresses and hostnames.
  # -z: Show ASN (Autonomous System Number) information.
  # -w: Use wide report format for full hostnames.
  # -T: Use TCP mode, which is more likely to pass through firewalls than ICMP.
  echo "[*] Running mtr for ${endpoint}. This may take a minute..."
  mtr -bzwr -T -P 443 -c ${MTR_PACKET_COUNT} "${endpoint}" > "${OUTPUT_DIR}/mtr_${endpoint}.txt"

  # Run targeted DNS lookups against each specific server from resolv.conf.
  # This helps diagnose issues with a single faulty DNS resolver.
  if [ ${#DNS_SERVERS[@]} -gt 0 ]; then
    echo "[*] Running targeted '${DNS_TOOL}' against each DNS server for ${endpoint}"
    for server in "${DNS_SERVERS[@]}"; do
      targeted_dns_file="${OUTPUT_DIR}/${DNS_TOOL}_on_${server}_for_${endpoint}.txt"
      case "${DNS_TOOL}" in
          dig)      dig "${endpoint}" "@${server}" > "${targeted_dns_file}" ;;
          host)     host "${endpoint}" "${server}" > "${targeted_dns_file}" ;;
          nslookup) nslookup "${endpoint}" "${server}" > "${targeted_dns_file}" ;;
      esac
    done
  fi
done
echo -e "\n------------------------------------------------------------"


# --- Section 4: Network Tests for Local DNS Resolvers ---
# Test connectivity to the DNS servers themselves to rule out upstream DNS issues.
echo "🔎 Running network tests for local DNS resolvers..."
for server in "${DNS_SERVERS[@]}"; do
    # Check UDP port 53, the standard port for DNS queries.
    echo "[*] Testing connectivity to DNS resolver ${server}:53"
    dns_port_check_file="${OUTPUT_DIR}/port_check_dns_${server}_53.txt"
    if command -v nc &>/dev/null && timeout 5 nc -vzu "${server}" 53 &> "${dns_port_check_file}"; then
      echo "Port check method: nc -vzu" >> "${dns_port_check_file}"
    else
      echo "nc -vzu failed or not available, using bash fallback..." > "${dns_port_check_file}"
      (timeout 5 bash -c "echo >/dev/udp/${server}/53") >> "${dns_port_check_file}" 2>&1
      if [ $? -eq 0 ]; then echo "Port check method: bash. Result: Success" >> "${dns_port_check_file}"; else echo "Port check method: bash. Result: Failure" >> "${dns_port_check_file}"; fi
    fi

    # Run MTR to the DNS server to check the path for packet loss or latency.
    echo "[*] Running mtr to DNS resolver ${server}. This may take a minute..."
    mtr -bzwT -c ${MTR_PACKET_COUNT} "${server}" > "${OUTPUT_DIR}/mtr_dns_${server}.txt"
done
echo -e "\n------------------------------------------------------------"


# --- Section 5: Collect Firewall Details and Logs ---
# Gather local firewall rules, as these are a common cause of blocked connections.
echo "🔎 Collecting firewall rules and logs..."
if command -v iptables &> /dev/null; then iptables -L -v -n > "${OUTPUT_DIR}/iptables_rules.txt"; fi
if command -v firewall-cmd &> /dev/null; then firewall-cmd --list-all > "${OUTPUT_DIR}/firewalld_rules.txt"; fi
echo "Note: If using a cloud provider, please also export security group/network ACL rules."

# Collect New Relic agent data and logs, which may contain relevant error messages.
if [ -d "/var/db/newrelic-infra/newrelic-agent" ]; then cp -r /var/db/newrelic-infra/newrelic-agent "${OUTPUT_DIR}/"; fi
if [ -d "/var/db/newrelic-infra/logs" ]; then cp -r /var/db/newrelic-infra/logs "${OUTPUT_DIR}/"; fi

# Collect recent system-level logs, which can provide context on network or system-wide issues.
journalctl --since "1 hour ago" > "${OUTPUT_DIR}/journalctl_last_hour.txt"
if [ -f "/var/log/messages" ]; then tail -n 5000 /var/log/messages > "${OUTPUT_DIR}/messages_last5000.txt"; fi
if [ -f "/var/log/syslog" ]; then tail -n 5000 /var/log/syslog > "${OUTPUT_DIR}/syslog_last5000.txt"; fi
echo -e "\n------------------------------------------------------------"


# --- Section 6: Final Step ---
echo "📦 Compressing all output files..."
tar -czvf "${OUTPUT_DIR}.tar.gz" "${OUTPUT_DIR}"

# When run with sudo, files are created as root. This changes ownership
# back to the original user, making the final archive easily accessible.
if [ -n "$SUDO_USER" ]; then
    chown -R "${SUDO_USER}:${SUDO_GID}" "${OUTPUT_DIR}" "${OUTPUT_DIR}.tar.gz" &> /dev/null
fi
echo -e "\n----------------------------------------------------------------------------------------------------------------------------"
echo      "✅ Done! Please attach the '${OUTPUT_DIR}.tar.gz' file to your New Relic support case for analysis."
echo      "----------------------------------------------------------------------------------------------------------------------------"
