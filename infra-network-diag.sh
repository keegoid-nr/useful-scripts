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

# --- Configuration ---
# New Relic endpoints to test
ENDPOINTS=(
  "metric-api.newrelic.com"
  "infra-api.newrelic.com"
  "infrastructure-command-api.newrelic.com"
  "log-api.newrelic.com"
)
# Number of packets for mtr to send
MTR_PACKET_COUNT=20

# --- Script Start ---
# Create a unique directory for the output files
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
OUTPUT_DIR="nr_diagnostics_${TIMESTAMP}"
mkdir -p "${OUTPUT_DIR}"
echo "✅ All outputs will be saved in the ./${OUTPUT_DIR}/ directory."
echo "------------------------------------------------------------"

# 1. Collect System and DNS Info
echo "🔎 Collecting DNS and system info..."
cp /etc/resolv.conf "${OUTPUT_DIR}/resolv.conf.txt"
cp /etc/nsswitch.conf "${OUTPUT_DIR}/nsswitch.conf.txt"
# Dynamically get DNS servers from resolv.conf
DNS_SERVERS=($(grep '^nameserver' /etc/resolv.conf | awk '{print $2}'))
if [ ${#DNS_SERVERS[@]} -eq 0 ]; then
  echo "⚠️  Could not find any DNS nameservers in /etc/resolv.conf"
else
  echo "Found DNS Servers: ${DNS_SERVERS[*]}"
fi
# Get systemd-resolved status if available
if command -v systemd-resolve &> /dev/null; then
  systemd-resolve --status > "${OUTPUT_DIR}/systemd-resolve_status.txt"
fi
echo "------------------------------------------------------------"


# 2. Run Network Connectivity Tests for each endpoint
echo "🔎 Running network tests for New Relic endpoints..."
for endpoint in "${ENDPOINTS[@]}"; do
  echo "--- Testing ${endpoint} ---"

  # dig, host, nc, curl
  echo "[*] Running dig, host, nc, and curl for ${endpoint}"
  dig "${endpoint}" > "${OUTPUT_DIR}/dig_${endpoint}.txt"
  host -v -t A "${endpoint}" > "${OUTPUT_DIR}/host_${endpoint}.txt"
  nc -vz "${endpoint}" 443 &> "${OUTPUT_DIR}/nc_${endpoint}.txt"
  curl -v "https://${endpoint}/cdn-cgi/trace" &> "${OUTPUT_DIR}/curl_${endpoint}.txt"

  # mtr
  echo "[*] Running mtr for ${endpoint}. This may take a minute..."
  mtr -bzwT -c ${MTR_PACKET_COUNT} "${endpoint}" > "${OUTPUT_DIR}/mtr_${endpoint}.txt"

  # Targeted dig against each DNS server
  if [ ${#DNS_SERVERS[@]} -gt 0 ]; then
    echo "[*] Running targeted 'dig' against each DNS server for ${endpoint}"
    for server in "${DNS_SERVERS[@]}"; do
      dig "${endpoint}" @"${server}" > "${OUTPUT_DIR}/dig_on_${server}_for_${endpoint}.txt"
    done
  fi
  echo "--- Finished ${endpoint} ---"
done
echo "------------------------------------------------------------"


# 3. Test Connectivity to Local DNS Resolvers
echo "🔎 Running network tests for local DNS resolvers..."
for server in "${DNS_SERVERS[@]}"; do
    echo "[*] Testing connectivity to DNS resolver ${server}"
    nc -vz -w 5 ${server} 53 &> "${OUTPUT_DIR}/nc_dns_${server}_port53.txt"
    echo "[*] Running mtr to DNS resolver ${server}. This may take a minute..."
    mtr -bzwT -c ${MTR_PACKET_COUNT} "${server}" > "${OUTPUT_DIR}/mtr_dns_${server}.txt"
done
echo "------------------------------------------------------------"


# 4. Collect Firewall Details
echo "🔎 Collecting firewall rules..."
if command -v iptables &> /dev/null; then
  sudo iptables -L -v -n > "${OUTPUT_DIR}/iptables_rules.txt"
fi
if command -v firewall-cmd &> /dev/null; then
  sudo firewall-cmd --list-all > "${OUTPUT_DIR}/firewalld_rules.txt"
fi
echo "Note: If using a cloud provider, please also export security group/network ACL rules."
echo "------------------------------------------------------------"


# 5. Collect Logs
echo "🔎 Collecting system and New Relic agent logs..."
if [ -d "/var/db/newrelic-infra/newrelic-agent" ]; then
    cp -r /var/db/newrelic-infra/newrelic-agent "${OUTPUT_DIR}/"
elif [ -d "/var/db/newrelic-infra/logs" ]; then
    cp -r /var/db/newrelic-infra/logs "${OUTPUT_DIR}/"
fi
journalctl --since "1 hour ago" > "${OUTPUT_DIR}/journalctl_last_hour.txt"
if [ -f "/var/log/messages" ]; then tail -n 5000 /var/log/messages > "${OUTPUT_DIR}/messages_last5000.txt"; fi
if [ -f "/var/log/syslog" ]; then tail -n 5000 /var/log/syslog > "${OUTPUT_DIR}/syslog_last5000.txt"; fi
echo "------------------------------------------------------------"


# 6. Final step: Package all results
echo "📦 Compressing all output files..."
tar -czvf "${OUTPUT_DIR}.tar.gz" "${OUTPUT_DIR}"
echo "✅ Done! Please attach the '${OUTPUT_DIR}.tar.gz' file to your New Relic support case for analysis."
