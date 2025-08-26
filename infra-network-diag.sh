#!/bin/bash

# New Relic Infra Network Diagnostics Script
# This script collects network diagnostics information
# related to the Infra agent for New Relic support cases.
#
# Author : Keegan Mullaney
# Company: New Relic
# Email  : kmullaney@newrelic.com
# Website: github.com/keegoid-nr/useful-scripts
# License: Apache License 2.0


# --- Section 0: Prerequisite Checks ---
# Check if script is being run as root
if [[ $EUID -ne 0 ]]; then
    echo "❌ Error: This script must be run as root to access system logs and tools."
    echo "Please run it with sudo: sudo $0"
    exit 1
fi

# Check for critical tools. Exit if they are not found.
CRITICAL_TOOLS=("mtr" "curl")
for tool in "${CRITICAL_TOOLS[@]}"; do
    if ! command -v "$tool" &> /dev/null; then
        echo "❌ Error: '$tool' is not installed and is required for this script."
        echo "Please install it using your package manager and rerun the script."
        echo "e.g., 'sudo apt-get update && sudo apt-get install $tool' or 'sudo yum install $tool'"
        exit 1
    fi
done

# Check for a DNS lookup tool, trying dig -> host -> nslookup.
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

# Help/Usage function
usage() {
    echo "Usage: sudo $0 [-c <count>]"
    echo "  -c <count>: Optional. Number of packets for mtr to send (default: 20)."
    exit 1
}

# Default number of packets for mtr to send
MTR_PACKET_COUNT=20

# Parse command-line options using getopts
while getopts ":c:h" opt; do
  case ${opt} in
    c )
      # Validate that the argument for -c is a positive integer
      if [[ "${OPTARG}" =~ ^[1-9][0-9]*$ ]]; then
        MTR_PACKET_COUNT=${OPTARG}
      else
        echo "❌ Error: Invalid packet count provided for -c. Must be a positive integer." >&2
        usage
      fi
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
shift $((OPTIND -1)) # Remove parsed options from the positional parameters

# New Relic endpoints to test
ENDPOINTS=(
  "metric-api.newrelic.com"
  "infra-api.newrelic.com"
  "infrastructure-command-api.newrelic.com"
  "log-api.newrelic.com"
)


# --- Script Start ---
# Create a unique directory for the output files
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
OUTPUT_DIR="infra_network_diag_${TIMESTAMP}"
mkdir -p "${OUTPUT_DIR}"
echo "✅ All outputs will be saved in the ./${OUTPUT_DIR}/ directory."
echo "✅ Using mtr packet count of ${MTR_PACKET_COUNT}."
echo "------------------------------------------------------------"


# --- Section 2: System and DNS Info ---
echo "🔎 Collecting DNS and system info..."
cp /etc/resolv.conf "${OUTPUT_DIR}/resolv.conf.txt"
cp /etc/nsswitch.conf "${OUTPUT_DIR}/nsswitch.conf.txt"
DNS_SERVERS=($(grep '^nameserver' /etc/resolv.conf | awk '{print $2}'))
if [ ${#DNS_SERVERS[@]} -eq 0 ]; then
  echo "⚠️  Could not find any DNS nameservers in /etc/resolv.conf"
else
  echo "Found DNS Servers: ${DNS_SERVERS[*]}"
fi
if command -v systemd-resolve &> /dev/null; then
  systemd-resolve --status > "${OUTPUT_DIR}/systemd-resolve_status.txt"
fi
echo "------------------------------------------------------------"


# --- Section 3: Network Tests for New Relic Endpoints ---
echo "🔎 Running network tests for New Relic endpoints..."
for endpoint in "${ENDPOINTS[@]}"; do
  echo "--- Testing ${endpoint} ---"

  # DNS Lookup (using selected tool) and Curl
  echo "[*] Running DNS lookup and curl for ${endpoint}"
  dns_lookup_file="${OUTPUT_DIR}/dns_lookup_${endpoint}.txt"
  case "${DNS_TOOL}" in
      dig)      dig "${endpoint}" > "${dns_lookup_file}" ;;
      host)     host "${endpoint}" > "${dns_lookup_file}" ;;
      nslookup) nslookup "${endpoint}" > "${dns_lookup_file}" ;;
  esac
  curl -v "https://${endpoint}/cdn-cgi/trace" &> "${OUTPUT_DIR}/curl_${endpoint}.txt"

  # Port check: Try nc -vz first, fallback to bash /dev/tcp
  echo "[*] Checking port connectivity to ${endpoint}:443"
  port_check_file="${OUTPUT_DIR}/port_check_${endpoint}_443.txt"
  if command -v nc &>/dev/null && timeout 5 nc -vz "${endpoint}" 443 &> "${port_check_file}"; then
    echo "Port check method: nc -vz" >> "${port_check_file}"
  else
    echo "nc -vz failed or not available, using bash fallback..." > "${port_check_file}"
    (timeout 5 bash -c "echo >/dev/tcp/${endpoint}/443") >> "${port_check_file}" 2>&1
    if [ $? -eq 0 ]; then echo "Port check method: bash. Result: Success" >> "${port_check_file}"; else echo "Port check method: bash. Result: Failure" >> "${port_check_file}"; fi
  fi

  # mtr
  echo "[*] Running mtr for ${endpoint}. This may take a minute..."
  mtr -bzwT -c ${MTR_PACKET_COUNT} "${endpoint}" > "${OUTPUT_DIR}/mtr_${endpoint}.txt"

  # Targeted DNS lookup
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
  echo "--- Finished ${endpoint} ---"
done
echo "------------------------------------------------------------"


# --- Section 4: Network Tests for Local DNS Resolvers ---
echo "🔎 Running network tests for local DNS resolvers..."
for server in "${DNS_SERVERS[@]}"; do
    echo "[*] Testing connectivity to DNS resolver ${server}:53"
    dns_port_check_file="${OUTPUT_DIR}/port_check_dns_${server}_53.txt"
    if command -v nc &>/dev/null && timeout 5 nc -vzu "${server}" 53 &> "${dns_port_check_file}"; then
      echo "Port check method: nc -vzu" >> "${dns_port_check_file}"
    else
      echo "nc -vzu failed or not available, using bash fallback..." > "${dns_port_check_file}"
      (timeout 5 bash -c "echo >/dev/udp/${server}/53") >> "${dns_port_check_file}" 2>&1
      if [ $? -eq 0 ]; then echo "Port check method: bash. Result: Success" >> "${dns_port_check_file}"; else echo "Port check method: bash. Result: Failure" >> "${dns_port_check_file}"; fi
    fi

    echo "[*] Running mtr to DNS resolver ${server}. This may take a minute..."
    mtr -bzwT -c ${MTR_PACKET_COUNT} "${server}" > "${OUTPUT_DIR}/mtr_dns_${server}.txt"
done
echo "------------------------------------------------------------"


# --- Section 5: Collect Firewall Details and Logs ---
echo "🔎 Collecting firewall rules and logs..."
if command -v iptables &> /dev/null; then iptables -L -v -n > "${OUTPUT_DIR}/iptables_rules.txt"; fi
if command -v firewall-cmd &> /dev/null; then firewall-cmd --list-all > "${OUTPUT_DIR}/firewalld_rules.txt"; fi
echo "Note: If using a cloud provider, please also export security group/network ACL rules."

if [ -d "/var/db/newrelic-infra/newrelic-agent" ]; then cp -r /var/db/newrelic-infra/newrelic-agent "${OUTPUT_DIR}/"; fi
if [ -d "/var/db/newrelic-infra/logs" ]; then cp -r /var/db/newrelic-infra/logs "${OUTPUT_DIR}/"; fi
journalctl --since "1 hour ago" > "${OUTPUT_DIR}/journalctl_last_hour.txt"
if [ -f "/var/log/messages" ]; then tail -n 5000 /var/log/messages > "${OUTPUT_DIR}/messages_last5000.txt"; fi
if [ -f "/var/log/syslog" ]; then tail -n 5000 /var/log/syslog > "${OUTPUT_DIR}/syslog_last5000.txt"; fi
echo "------------------------------------------------------------"


# --- Section 6: Final Step ---
echo "📦 Compressing all output files..."
tar -czvf "${OUTPUT_DIR}.tar.gz" "${OUTPUT_DIR}"
# Ensure the final archive is accessible by the user who ran sudo
chown -R "${SUDO_USER}:${SUDO_GID}" "${OUTPUT_DIR}" "${OUTPUT_DIR}.tar.gz" &> /dev/null
echo "✅ Done! Please attach the '${OUTPUT_DIR}.tar.gz' file to your New Relic support case for analysis."
