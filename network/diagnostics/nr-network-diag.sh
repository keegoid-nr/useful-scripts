#!/bin/bash
: '
New Relic Network Diagnostics

This script gathers comprehensive network diagnostics to help troubleshoot
connectivity issues between a host and New Relic endpoints. It is designed
to be run on a problematic host and the output bundled for a support case.

It performs the following actions:
- Checks system compatibility and for required tools (mtr, curl, dig/host).
- Allows selection of which New Relic agent type to troubleshoot (APM, Browser, Mobile, Infrastructure, etc.).
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
    echo "Usage: sudo $0 [-c <count>] [-p <proxy_url>] [-a <agent_type>] [-r <region>]"
    echo "  -c <count>: Optional. Number of packets for mtr to send (default: 20)."
    echo "  -p <proxy_url>: Optional. Proxy server URL (e.g., http://proxy.example.com:8080)."
    echo "  -a <agent_type>: Optional. Agent type to test (apm, browser, mobile, infrastructure, opentelemetry, all). If not specified, will prompt."
    echo "  -r <region>: Optional. Data center region (us or eu). Default: us."
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


# --- Section 1: Shell Best Practices & Helper Functions ---

# Enable strict error handling after prerequisite checks
set -euo pipefail

# Color output (disable if not a TTY or TERM not set)
if [[ -t 1 ]] && [[ "${TERM:-}" != "dumb" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    CYAN=''
    BOLD=''
    NC=''
fi

# Test result tracking
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0
declare -a FAILURES
declare -a WARNINGS
declare -a RECOMMENDATIONS

# Helper function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Log section header
log_section() {
    echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}$1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Log a test being run
log_test() {
    echo -e "${YELLOW}[TEST]${NC} $1"
}

# Log a successful test
log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((PASS_COUNT++)) || true
}

# Log a failed test
log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((FAIL_COUNT++)) || true
    FAILURES+=("$1")
}

# Log a warning
log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    ((WARN_COUNT++)) || true
    WARNINGS+=("$1")
}

# Log info message
log_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

# Cleanup function
cleanup() {
    # Only cleanup on error or interrupt, not on normal exit
    if [[ $? -ne 0 ]] && [[ -n "${OUTPUT_DIR:-}" ]] && [[ -d "$OUTPUT_DIR" ]]; then
        echo -e "\n${YELLOW}Cleaning up partial output directory...${NC}"
        # Don't remove, keep for debugging
    fi
}
trap cleanup EXIT INT TERM


# --- Section 2: Configuration & Argument Parsing ---

# Default number of packets for MTR to send in each trace.
MTR_PACKET_COUNT=20
# Default region
REGION="us"
# Agent type will be set by user selection or command line
AGENT_TYPE=""

# Parse command-line flags (e.g., -c for packet count, -p for proxy).
while getopts ":c:p:a:r:h" opt; do
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
    a )
      AGENT_TYPE=$(echo "${OPTARG}" | tr '[:upper:]' '[:lower:]')
      ;;
    r )
      REGION=$(echo "${OPTARG}" | tr '[:upper:]' '[:lower:]')
      if [[ "$REGION" != "us" && "$REGION" != "eu" ]]; then
        echo "❌ Error: Invalid region. Must be 'us' or 'eu'." >&2
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
# Remove the parsed options from the script's arguments.
shift $((OPTIND -1))

# Function to display agent selection menu
select_agent_type() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${BOLD}Select New Relic Agent Type to Troubleshoot${NC}              ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "  1) APM (Application Performance Monitoring)"
    echo "  2) Browser Monitoring"
    echo "  3) Mobile Monitoring"
    echo "  4) Infrastructure Monitoring"
    echo "  5) OpenTelemetry"
    echo "  6) All Ingest APIs (Event, Log, Metric, Trace)"
    echo "  7) All Agent Types (comprehensive test)"
    echo ""
    echo -n "Enter your choice (1-7): "
    read -r choice

    case $choice in
        1) AGENT_TYPE="apm" ;;
        2) AGENT_TYPE="browser" ;;
        3) AGENT_TYPE="mobile" ;;
        4) AGENT_TYPE="infrastructure" ;;
        5) AGENT_TYPE="opentelemetry" ;;
        6) AGENT_TYPE="apis" ;;
        7) AGENT_TYPE="all" ;;
        *)
            echo -e "${RED}❌ Invalid choice. Please run the script again.${NC}"
            exit 1
            ;;
    esac
}

# Function to set endpoints based on agent type and region
set_endpoints() {
    local agent="$1"
    local region="$2"

    case "$agent" in
        apm)
            if [[ "$region" == "eu" ]]; then
                ENDPOINTS=(
                    "collector.eu.newrelic.com"
                    "collector.eu01.nr-data.net"
                )
            else
                ENDPOINTS=(
                    "collector.newrelic.com"
                )
            fi
            ;;
        browser)
            if [[ "$region" == "eu" ]]; then
                ENDPOINTS=(
                    "bam.eu01.nr-data.net"
                )
            else
                ENDPOINTS=(
                    "bam.nr-data.net"
                    "bam-cell.nr-data.net"
                )
            fi
            ;;
        mobile)
            if [[ "$region" == "eu" ]]; then
                ENDPOINTS=(
                    "mobile-collector.eu01.nr-data.net"
                    "mobile-crash.eu01.nr-data.net"
                    "mobile-symbol-upload.eu01.nr-data.net"
                )
            else
                ENDPOINTS=(
                    "mobile-collector.newrelic.com"
                    "mobile-crash.newrelic.com"
                    "mobile-symbol-upload.newrelic.com"
                )
            fi
            ;;
        infrastructure)
            if [[ "$region" == "eu" ]]; then
                ENDPOINTS=(
                    "infra-api.eu.newrelic.com"
                    "infra-api.eu01.nr-data.net"
                    "identity-api.eu.newrelic.com"
                    "infrastructure-command-api.eu.newrelic.com"
                    "log-api.eu.newrelic.com"
                )
            else
                ENDPOINTS=(
                    "infra-api.newrelic.com"
                    "identity-api.newrelic.com"
                    "infrastructure-command-api.newrelic.com"
                    "log-api.newrelic.com"
                    "metric-api.newrelic.com"
                )
            fi
            ;;
        opentelemetry)
            if [[ "$region" == "eu" ]]; then
                ENDPOINTS=(
                    "otlp.eu01.nr-data.net"
                )
            else
                ENDPOINTS=(
                    "otlp.nr-data.net"
                )
            fi
            ;;
        apis)
            if [[ "$region" == "eu" ]]; then
                ENDPOINTS=(
                    "insights-collector.eu01.nr-data.net"
                    "log-api.eu.newrelic.com"
                    "metric-api.eu.newrelic.com"
                    "trace-api.eu.newrelic.com"
                )
            else
                ENDPOINTS=(
                    "insights-collector.newrelic.com"
                    "log-api.newrelic.com"
                    "metric-api.newrelic.com"
                    "trace-api.newrelic.com"
                )
            fi
            ;;
        all)
            if [[ "$region" == "eu" ]]; then
                ENDPOINTS=(
                    "collector.eu.newrelic.com"
                    "collector.eu01.nr-data.net"
                    "bam.eu01.nr-data.net"
                    "mobile-collector.eu01.nr-data.net"
                    "mobile-crash.eu01.nr-data.net"
                    "infra-api.eu.newrelic.com"
                    "infra-api.eu01.nr-data.net"
                    "identity-api.eu.newrelic.com"
                    "infrastructure-command-api.eu.newrelic.com"
                    "insights-collector.eu01.nr-data.net"
                    "log-api.eu.newrelic.com"
                    "metric-api.eu.newrelic.com"
                    "trace-api.eu.newrelic.com"
                    "otlp.eu01.nr-data.net"
                )
            else
                ENDPOINTS=(
                    "collector.newrelic.com"
                    "bam.nr-data.net"
                    "bam-cell.nr-data.net"
                    "mobile-collector.newrelic.com"
                    "mobile-crash.newrelic.com"
                    "infra-api.newrelic.com"
                    "identity-api.newrelic.com"
                    "infrastructure-command-api.newrelic.com"
                    "insights-collector.newrelic.com"
                    "log-api.newrelic.com"
                    "metric-api.newrelic.com"
                    "trace-api.newrelic.com"
                    "otlp.nr-data.net"
                )
            fi
            ;;
        *)
            echo -e "${RED}❌ Error: Unknown agent type: $agent${NC}"
            exit 1
            ;;
    esac
}

# If agent type not specified via command line, prompt user
if [[ -z "$AGENT_TYPE" ]]; then
    select_agent_type
fi

# Set endpoints based on selected agent type and region
set_endpoints "$AGENT_TYPE" "$REGION"


# --- Section 3: Analysis Functions ---

# Analyze DNS lookup output
analyze_dns_output() {
    local dns_file="$1"
    local endpoint="$2"

    if grep -qi "NXDOMAIN\|SERVFAIL\|connection timed out\|no servers could be reached\|communications error" "$dns_file"; then
        log_fail "DNS lookup failed for ${endpoint}"
        RECOMMENDATIONS+=("Check DNS server configuration - cannot resolve ${endpoint}")
        return 1
    elif grep -q "ANSWER SECTION\|has address\|has IPv6 address" "$dns_file"; then
        log_pass "DNS resolution successful for ${endpoint}"
        return 0
    else
        log_warn "Unclear DNS result for ${endpoint}"
        return 2
    fi
}

# Analyze curl connection output
analyze_curl_output() {
    local curl_file="$1"
    local endpoint="$2"

    # Check for connection errors
    if grep -q "Connection refused" "$curl_file"; then
        log_fail "Connection refused to ${endpoint}"
        RECOMMENDATIONS+=("${endpoint} is refusing connections - check if service is down or firewall is blocking")
        return 1
    elif grep -q "Connection timed out\|Operation timed out\|Failed to connect" "$curl_file"; then
        log_fail "Connection timeout to ${endpoint}"
        RECOMMENDATIONS+=("Cannot connect to ${endpoint} - check firewall rules and network connectivity")
        return 1
    elif grep -q "SSL certificate problem\|certificate verify failed\|SSL: certificate verification failed" "$curl_file"; then
        log_fail "SSL certificate error for ${endpoint}"
        RECOMMENDATIONS+=("SSL/TLS certificate validation failed for ${endpoint} - check corporate proxy/SSL inspection")
        return 1
    elif grep -q "Could not resolve host\|Couldn't resolve host" "$curl_file"; then
        log_fail "DNS resolution failed for ${endpoint}"
        RECOMMENDATIONS+=("Cannot resolve ${endpoint} - DNS configuration issue")
        return 1
    elif grep -q "SSL connect error\|error:.*:SSL routines\|TLS handshake" "$curl_file" && ! grep -q "HTTP/[12]" "$curl_file"; then
        log_fail "TLS handshake failed for ${endpoint}"
        RECOMMENDATIONS+=("TLS/SSL handshake failure with ${endpoint} - likely corporate firewall or proxy doing SSL inspection")
        return 1
    elif grep -q "HTTP/[12][.0-9]* 200\|HTTP/[12][.0-9]* 204" "$curl_file"; then
        log_pass "Successful HTTPS connection to ${endpoint}"
        return 0
    elif grep -q "HTTP/[12][.0-9]* 4[0-9][0-9]" "$curl_file"; then
        log_warn "HTTP 4xx response from ${endpoint} (may be expected for test endpoint)"
        return 2
    elif grep -q "HTTP/[12]" "$curl_file"; then
        log_warn "Unexpected HTTP response from ${endpoint}"
        return 2
    else
        log_warn "Could not determine connection status for ${endpoint}"
        return 2
    fi
}

# Analyze MTR output for packet loss and latency issues
analyze_mtr_output() {
    local mtr_file="$1"
    local endpoint="$2"

    if [[ ! -s "$mtr_file" ]]; then
        log_warn "MTR output empty or missing for ${endpoint}"
        return 2
    fi

    # Check for 100% packet loss (complete failure)
    if grep -q "100\.0%.*Loss" "$mtr_file" || tail -1 "$mtr_file" | grep -q "100\.0%"; then
        log_fail "Complete packet loss to ${endpoint}"
        RECOMMENDATIONS+=("All packets lost to ${endpoint} - network path is completely blocked")
        return 1
    fi

    # Check for high packet loss (>10% on final hop)
    local last_line
    last_line=$(tail -1 "$mtr_file")
    local loss_pct
    loss_pct=$(echo "$last_line" | awk '{print $3}' | tr -d '%')

    if [[ -n "$loss_pct" ]] && (( $(echo "$loss_pct > 10" | bc -l 2>/dev/null || echo 0) )); then
        log_warn "High packet loss to ${endpoint} (${loss_pct}%)"
        RECOMMENDATIONS+=("Packet loss detected to ${endpoint} - network path may be congested or unstable")
        return 2
    fi

    # Check average latency on last hop
    local avg_latency
    avg_latency=$(echo "$last_line" | awk '{print $6}')

    if [[ -n "$avg_latency" ]] && (( $(echo "$avg_latency > 500" | bc -l 2>/dev/null || echo 0) )); then
        log_warn "High latency to ${endpoint} (${avg_latency}ms average)"
        return 2
    elif [[ -n "$avg_latency" ]]; then
        log_pass "Network path to ${endpoint} looks healthy (${avg_latency}ms average)"
        return 0
    else
        log_pass "Network path to ${endpoint} completed"
        return 0
    fi
}

# Analyze port connectivity check
analyze_port_check() {
    local port_file="$1"
    local endpoint="$2"
    local port="$3"

    if grep -q "succeeded\|Success\|open\|Connected to" "$port_file"; then
        log_pass "Port ${port} is open on ${endpoint}"
        return 0
    elif grep -q "Connection refused" "$port_file"; then
        log_fail "Port ${port} refused on ${endpoint}"
        return 1
    elif grep -q "timed out\|No route to host" "$port_file"; then
        log_fail "Cannot reach ${endpoint}:${port} (timeout)"
        return 1
    else
        log_warn "Port check for ${endpoint}:${port} inconclusive"
        return 2
    fi
}


# --- Script Start ---
# Get friendly name for agent type
get_agent_display_name() {
    case "$1" in
        apm) echo "APM (Application Performance Monitoring)" ;;
        browser) echo "Browser Monitoring" ;;
        mobile) echo "Mobile Monitoring" ;;
        infrastructure) echo "Infrastructure Monitoring" ;;
        opentelemetry) echo "OpenTelemetry" ;;
        apis) echo "Ingest APIs (Event, Log, Metric, Trace)" ;;
        all) echo "All Agent Types" ;;
        *) echo "Unknown" ;;
    esac
}

AGENT_DISPLAY_NAME=$(get_agent_display_name "$AGENT_TYPE")
REGION_DISPLAY=$(echo "$REGION" | tr '[:lower:]' '[:upper:]')

log_section "NEW RELIC NETWORK DIAGNOSTICS"

# Create a unique, timestamped directory to store all output files.
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
OUTPUT_DIR="nr-network-diag_${AGENT_TYPE}_${REGION}_${TIMESTAMP}"
mkdir -p "${OUTPUT_DIR}"

echo ""
log_info "Agent Type: ${AGENT_DISPLAY_NAME}"
log_info "Data Center Region: ${REGION_DISPLAY}"
log_info "Output directory: ./${OUTPUT_DIR}/"
log_info "MTR packet count: ${MTR_PACKET_COUNT}"
if [[ -n "${PROXY_URL:-}" ]]; then
    log_info "Proxy configured: ${PROXY_URL}"
else
    log_info "No proxy configured"
fi

# Calculate estimated run time based on MTR packet count
# Each endpoint: MTR (~2s per count) + DNS/curl/port (~15s) = MTR_PACKET_COUNT*2 + 15
# 4 endpoints + DNS server tests + overhead
ESTIMATED_MINUTES=$(( (${#ENDPOINTS[@]} * (MTR_PACKET_COUNT * 2 + 15) + 60) / 60 ))
ESTIMATED_MINUTES_MAX=$(( ESTIMATED_MINUTES + 2 ))
echo -e "\n${CYAN}⏱️  Estimated run time: ${ESTIMATED_MINUTES}-${ESTIMATED_MINUTES_MAX} minutes (depends on network speed)${NC}"
echo ""


# --- Section 4: System and DNS Info ---
log_section "Collecting DNS and System Information"

# Collect core system files that define DNS resolution behavior.
log_test "Collecting DNS configuration files"
cp /etc/resolv.conf "${OUTPUT_DIR}/resolv.conf.txt"
cp /etc/nsswitch.conf "${OUTPUT_DIR}/nsswitch.conf.txt"

# Extract DNS server IPs from resolv.conf to use for targeted tests later.
mapfile -t DNS_SERVERS < <(grep '^nameserver' /etc/resolv.conf | awk '{print $2}')
if [[ ${#DNS_SERVERS[@]} -eq 0 ]]; then
    log_warn "Could not find any DNS nameservers in /etc/resolv.conf"
else
    log_info "Found DNS Servers: ${DNS_SERVERS[*]}"
fi

# If systemd-resolved is in use, get its status for more detailed DNS info.
if command_exists systemd-resolve; then
    systemd-resolve --status > "${OUTPUT_DIR}/systemd-resolve_status.txt" 2>&1 || true
fi

# Proxy connectivity check
if [[ -n "${PROXY_URL:-}" ]]; then
    log_section "Checking Proxy Connectivity"

    # Extract host and port from PROXY_URL using regex
    if [[ "$PROXY_URL" =~ ^(https?://)?([^:]+):?([0-9]+)?$ ]]; then
        PROXY_HOST="${BASH_REMATCH[2]}"
        PROXY_PORT="${BASH_REMATCH[3]:-8080}"  # Default to 8080 if not specified
    else
        log_warn "Could not parse proxy URL: ${PROXY_URL}"
        PROXY_HOST=""
        PROXY_PORT=""
    fi

    if [[ -n "$PROXY_HOST" ]]; then
        proxy_check_file="${OUTPUT_DIR}/proxy_connectivity.txt"
        {
            echo "Testing connection to proxy ${PROXY_HOST}:${PROXY_PORT}..."
            echo "Proxy URL: ${PROXY_URL}"
        } > "$proxy_check_file"

        log_test "Testing proxy connectivity to ${PROXY_HOST}:${PROXY_PORT}"

        if command_exists nc && timeout 5 nc -vz "$PROXY_HOST" "$PROXY_PORT" &>> "$proxy_check_file"; then
            echo "Proxy reachable via nc." >> "$proxy_check_file"
            log_pass "Proxy is reachable"
        else
            echo "nc check failed or unavailable. Trying curl..." >> "$proxy_check_file"
            # Try to fetch through the proxy
            if curl -x "$PROXY_URL" -I "https://www.google.com" -m 10 &>> "$proxy_check_file"; then
                echo "Proxy working via curl check." >> "$proxy_check_file"
                log_pass "Proxy is working (verified with curl)"
            else
                log_fail "Proxy check failed - diagnostics may fail if proxy is required"
                RECOMMENDATIONS+=("Proxy ${PROXY_URL} is not reachable - verify proxy configuration")
                echo "Proxy check failed." >> "$proxy_check_file"
            fi
        fi
    fi
fi


# --- Section 5: Network Tests for New Relic Endpoints ---
log_section "Testing New Relic Endpoints"

ENDPOINT_COUNT=0
TOTAL_ENDPOINTS=${#ENDPOINTS[@]}

for endpoint in "${ENDPOINTS[@]}"; do
    ((ENDPOINT_COUNT++)) || true
    echo ""
    log_section "Testing ${endpoint} (${ENDPOINT_COUNT}/${TOTAL_ENDPOINTS})"

    # DNS Lookup Test
    log_test "Running DNS lookup for ${endpoint}"
    dns_lookup_file="${OUTPUT_DIR}/dns_lookup_${endpoint}.txt"
    case "${DNS_TOOL}" in
        dig)      dig "${endpoint}" > "${dns_lookup_file}" 2>&1 ;;
        host)     host "${endpoint}" > "${dns_lookup_file}" 2>&1 ;;
        nslookup) nslookup "${endpoint}" > "${dns_lookup_file}" 2>&1 ;;
    esac
    analyze_dns_output "$dns_lookup_file" "$endpoint" || true

    # Curl TLS/HTTPS Test
    log_test "Running HTTPS connection test for ${endpoint}"
    curl_file="${OUTPUT_DIR}/curl_${endpoint}.txt"
    echo "--- Testing ${endpoint}/cdn-cgi/trace ---" > "$curl_file"

    CURL_ARGS=("-v" "-m" "30")
    if [[ -n "${PROXY_URL:-}" ]]; then
        CURL_ARGS+=("-x" "$PROXY_URL")
    fi

    curl "${CURL_ARGS[@]}" "https://${endpoint}/cdn-cgi/trace" &>> "$curl_file" || true

    if [[ "$endpoint" != "infrastructure-command-api.newrelic.com" ]]; then
        echo -e "\n\n--- Testing ${endpoint}/worker/health ---" >> "$curl_file"
        curl "${CURL_ARGS[@]}" "https://${endpoint}/worker/health" &>> "$curl_file" || true
    fi

    analyze_curl_output "$curl_file" "$endpoint" || true

    # Port Connectivity Test
    # OpenTelemetry endpoints use ports 443, 4317, and 4318
    if [[ "$endpoint" == *"otlp"* ]]; then
        PORTS_TO_TEST=(443 4317 4318)
    else
        PORTS_TO_TEST=(443)
    fi

    for port in "${PORTS_TO_TEST[@]}"; do
        log_test "Checking TCP port ${port} connectivity to ${endpoint}"
        port_check_file="${OUTPUT_DIR}/port_check_${endpoint}_${port}.txt"
        if command_exists nc && timeout 5 nc -vz "${endpoint}" "$port" &> "${port_check_file}"; then
            echo "Port check method: nc -vz" >> "${port_check_file}"
            analyze_port_check "$port_check_file" "$endpoint" "$port" || true
        else
            echo "nc -vz failed or not available, using bash fallback..." > "${port_check_file}"
            if timeout 5 bash -c "echo >/dev/tcp/${endpoint}/${port}" >> "${port_check_file}" 2>&1; then
                echo "Port check method: bash. Result: Success" >> "${port_check_file}"
                analyze_port_check "$port_check_file" "$endpoint" "$port" || true
            else
                echo "Port check method: bash. Result: Failure" >> "${port_check_file}"
                analyze_port_check "$port_check_file" "$endpoint" "$port" || true
            fi
        fi
    done

    # MTR Trace Test with progress indicator
    # MTR takes ~2 seconds per packet count
    MTR_ESTIMATED_TIME=$((MTR_PACKET_COUNT * 2))

    # Use port 4317 for OpenTelemetry endpoints (gRPC), 443 for others
    if [[ "$endpoint" == *"otlp"* ]]; then
        MTR_PORT=4317
    else
        MTR_PORT=443
    fi

    log_test "Running MTR trace to ${endpoint}:${MTR_PORT} (~${MTR_ESTIMATED_TIME} seconds)"
    mtr_file="${OUTPUT_DIR}/mtr_${endpoint}.txt"

    # Run MTR in background with progress indicator
    echo -n "  "
    mtr -bzwr -T -P "$MTR_PORT" -c "${MTR_PACKET_COUNT}" "${endpoint}" > "$mtr_file" 2>&1 &
    MTR_PID=$!

    # Show progress dots while MTR runs
    # Show "still running" message at 75% of estimated time
    STILL_RUNNING_THRESHOLD=$((MTR_ESTIMATED_TIME * 3 / 8))  # 75% of time divided by 2 sec intervals
    dot_count=0
    while kill -0 "$MTR_PID" 2>/dev/null; do
        echo -n "."
        sleep 2
        ((dot_count++)) || true
        if [[ $dot_count -ge $STILL_RUNNING_THRESHOLD ]] && [[ $((dot_count % STILL_RUNNING_THRESHOLD)) -eq 0 ]]; then
            echo -n " still running"
        fi
    done
    wait "$MTR_PID" 2>/dev/null || true
    echo " Done"

    analyze_mtr_output "$mtr_file" "$endpoint" || true

    # Targeted DNS server tests
    if [[ ${#DNS_SERVERS[@]} -gt 0 ]]; then
        for server in "${DNS_SERVERS[@]}"; do
            log_test "Testing DNS resolution via DNS server ${server}"
            targeted_dns_file="${OUTPUT_DIR}/${DNS_TOOL}_on_${server}_for_${endpoint}.txt"
            case "${DNS_TOOL}" in
                dig)      dig "${endpoint}" "@${server}" > "${targeted_dns_file}" 2>&1 ;;
                host)     host "${endpoint}" "${server}" > "${targeted_dns_file}" 2>&1 ;;
                nslookup) nslookup "${endpoint}" "${server}" > "${targeted_dns_file}" 2>&1 ;;
            esac

            # Analyze the targeted DNS result
            if analyze_dns_output "$targeted_dns_file" "$endpoint" > /dev/null 2>&1; then
                log_pass "DNS server ${server} can resolve ${endpoint}"
            else
                log_warn "DNS server ${server} had issues resolving ${endpoint}"
            fi
        done
    fi

    # Show running progress
    echo -e "\n${CYAN}Progress: ${ENDPOINT_COUNT}/${TOTAL_ENDPOINTS} endpoints tested | ✓ ${GREEN}${PASS_COUNT}${NC} ${CYAN}passed | ✗ ${RED}${FAIL_COUNT}${NC} ${CYAN}failed | ⚠ ${YELLOW}${WARN_COUNT}${NC} ${CYAN}warnings${NC}"
done


# --- Section 6: Network Tests for Local DNS Resolvers ---
log_section "Testing DNS Server Connectivity"

if [[ ${#DNS_SERVERS[@]} -eq 0 ]]; then
    log_warn "No DNS servers found to test"
else
    for server in "${DNS_SERVERS[@]}"; do
        log_test "Testing connectivity to DNS server ${server}:53"

        dns_port_check_file="${OUTPUT_DIR}/port_check_dns_${server}_53.txt"
        if command_exists nc && timeout 5 nc -vzu "${server}" 53 &> "${dns_port_check_file}"; then
            echo "Port check method: nc -vzu. Result: Success" >> "${dns_port_check_file}"
            log_pass "DNS server ${server} is responding"
        else
            echo "nc -vzu failed or not available, using bash fallback..." > "${dns_port_check_file}"
            if timeout 5 bash -c "echo >/dev/udp/${server}/53" >> "${dns_port_check_file}" 2>&1; then
                echo "Port check method: bash. Result: Success" >> "${dns_port_check_file}"
                log_pass "DNS server ${server} is responding"
            else
                echo "Port check method: bash. Result: Failure" >> "${dns_port_check_file}"
                log_fail "DNS server ${server} is not responding"
                RECOMMENDATIONS+=("DNS server ${server} is not responding - check network connectivity or use alternate DNS")
            fi
        fi

        # Check if DNS server responds to ICMP before running MTR
        log_test "Checking if DNS server ${server} responds to ICMP"
        if timeout 3 ping -c 2 "${server}" > /dev/null 2>&1; then
            log_info "DNS server responds to ICMP, running MTR trace"
            echo -n "  "
            mtr -bzwr -c "${MTR_PACKET_COUNT}" "${server}" > "${OUTPUT_DIR}/mtr_dns_${server}.txt" 2>&1 &
            MTR_PID=$!

            while kill -0 $MTR_PID 2>/dev/null; do
                echo -n "."
                sleep 2
            done
            wait $MTR_PID || true
            echo " Done"
        else
            log_info "DNS server does not respond to ICMP - skipping MTR (common for cloud/corporate DNS servers)"
            cat > "${OUTPUT_DIR}/mtr_dns_${server}.txt" <<EOF
MTR trace skipped for ${server}

Reason: DNS server does not respond to ICMP ping requests.

This is common and expected behavior for:
- AWS VPC DNS resolvers (e.g., 172.31.0.2)
- Azure Virtual Network DNS
- Google Cloud DNS
- Corporate/enterprise DNS servers with ICMP disabled for security

The DNS functionality has been verified via UDP port 53 connectivity check above.
No action needed - this is normal and does not indicate a problem.
EOF
        fi
    done
fi


# --- Section 7: Collect Firewall Details and Logs ---
log_section "Collecting Firewall Rules and Logs"

# Gather local firewall rules
log_test "Collecting local firewall configuration"
if command_exists iptables; then
    iptables -L -v -n > "${OUTPUT_DIR}/iptables_rules.txt" 2>&1 || true
    log_info "iptables rules saved"
fi
if command_exists firewall-cmd; then
    firewall-cmd --list-all > "${OUTPUT_DIR}/firewalld_rules.txt" 2>&1 || true
    log_info "firewalld rules saved"
fi

log_info "Note: If using a cloud provider, also export security group/network ACL rules"

# Collect New Relic agent data and logs
log_test "Collecting New Relic agent logs (if available)"
if [[ "$AGENT_TYPE" == "infrastructure" || "$AGENT_TYPE" == "all" ]]; then
    if [[ -d "/var/db/newrelic-infra/newrelic-agent" ]]; then
        cp -r /var/db/newrelic-infra/newrelic-agent "${OUTPUT_DIR}/" 2>&1 || true
        log_info "Infrastructure agent data copied"
    fi
    if [[ -d "/var/db/newrelic-infra/logs" ]]; then
        cp -r /var/db/newrelic-infra/logs "${OUTPUT_DIR}/" 2>&1 || true
        log_info "Infrastructure agent logs copied"
    fi
fi
# Note: APM, Browser, and Mobile agent logs are typically in application directories
# and vary by language/platform, so we don't attempt to collect them automatically.
log_info "For APM/Browser/Mobile agent logs, please collect them from your application directory"

# Collect system logs
log_test "Collecting system logs"
if command_exists journalctl; then
    journalctl --since "1 hour ago" > "${OUTPUT_DIR}/journalctl_last_hour.txt" 2>&1 || true
    log_info "journalctl logs saved"
fi
if [[ -f "/var/log/messages" ]]; then
    tail -n 5000 /var/log/messages > "${OUTPUT_DIR}/messages_last5000.txt" 2>&1 || true
fi
if [[ -f "/var/log/syslog" ]]; then
    tail -n 5000 /var/log/syslog > "${OUTPUT_DIR}/syslog_last5000.txt" 2>&1 || true
fi


# --- Section 8: Generate Summary Report ---
generate_summary_report() {
    local summary_file="${OUTPUT_DIR}/SUMMARY.txt"

    # Create summary report
    cat > "$summary_file" <<EOF
═══════════════════════════════════════════════════════════════
  NEW RELIC NETWORK DIAGNOSTICS SUMMARY
═══════════════════════════════════════════════════════════════

Agent Type: ${AGENT_DISPLAY_NAME}
Data Center Region: ${REGION_DISPLAY}
Test Results: ${PASS_COUNT} passed, ${FAIL_COUNT} failed, ${WARN_COUNT} warnings
Timestamp: $(date)
Hostname: $(hostname)
Proxy: ${PROXY_URL:-None configured}

EOF

    # Endpoint connectivity section
    echo "───────────────────────────────────────────────────────────" >> "$summary_file"
    echo "NEW RELIC ENDPOINT CONNECTIVITY" >> "$summary_file"
    echo "───────────────────────────────────────────────────────────" >> "$summary_file"
    echo "" >> "$summary_file"

    for endpoint in "${ENDPOINTS[@]}"; do
        local curl_file="${OUTPUT_DIR}/curl_${endpoint}.txt"
        local status="UNKNOWN"

        if grep -q "HTTP/[12][.0-9]* 200\|HTTP/[12][.0-9]* 204" "$curl_file"; then
            status="✅ Healthy"
        elif grep -q "Connection refused" "$curl_file"; then
            status="❌ Connection Refused"
        elif grep -q "Connection timed out\|Operation timed out" "$curl_file"; then
            status="❌ Connection Timeout"
        elif grep -q "SSL certificate problem\|certificate verify failed" "$curl_file"; then
            status="❌ SSL Certificate Error"
        elif grep -q "TLS handshake\|SSL connect error" "$curl_file" && ! grep -q "HTTP/[12]" "$curl_file"; then
            status="❌ TLS Handshake Failed"
        elif grep -q "Could not resolve host" "$curl_file"; then
            status="❌ DNS Resolution Failed"
        else
            status="⚠️  Check Required"
        fi

        printf "%-45s - %s\n" "$endpoint" "$status" >> "$summary_file"
    done

    # DNS server health section
    if [[ ${#DNS_SERVERS[@]} -gt 0 ]]; then
        echo "" >> "$summary_file"
        echo "───────────────────────────────────────────────────────────" >> "$summary_file"
        echo "DNS SERVER HEALTH" >> "$summary_file"
        echo "───────────────────────────────────────────────────────────" >> "$summary_file"
        echo "" >> "$summary_file"

        for server in "${DNS_SERVERS[@]}"; do
            local dns_check_file="${OUTPUT_DIR}/port_check_dns_${server}_53.txt"
            local status="UNKNOWN"

            if [[ -f "$dns_check_file" ]]; then
                if grep -q "succeeded\|Success" "$dns_check_file"; then
                    status="✅ Responding"
                elif grep -q "Failure\|timed out" "$dns_check_file"; then
                    status="❌ Not Responding"
                else
                    status="⚠️  Check Required"
                fi
            fi

            printf "%-45s - %s\n" "$server" "$status" >> "$summary_file"
        done
    fi

    # Proxy status
    if [[ -n "${PROXY_URL:-}" ]]; then
        echo "" >> "$summary_file"
        echo "───────────────────────────────────────────────────────────" >> "$summary_file"
        echo "PROXY STATUS" >> "$summary_file"
        echo "───────────────────────────────────────────────────────────" >> "$summary_file"
        echo "" >> "$summary_file"
        echo "Proxy URL: ${PROXY_URL}" >> "$summary_file"

        local proxy_file="${OUTPUT_DIR}/proxy_connectivity.txt"
        if [[ -f "$proxy_file" ]]; then
            if grep -q "reachable\|working" "$proxy_file"; then
                echo "Status: ✅ Proxy is reachable and working" >> "$summary_file"
            else
                echo "Status: ❌ Proxy check failed" >> "$summary_file"
            fi
        fi
    fi

    # Detected issues section
    # Temporarily disable set -u to safely check empty arrays
    set +u
    local has_failures=$( [[ ${#FAILURES[@]} -gt 0 ]] && echo 1 || echo 0 )
    local has_warnings=$( [[ ${#WARNINGS[@]} -gt 0 ]] && echo 1 || echo 0 )
    local has_recommendations=$( [[ ${#RECOMMENDATIONS[@]} -gt 0 ]] && echo 1 || echo 0 )
    set -u

    if [[ $has_failures -eq 1 || $has_warnings -eq 1 ]]; then
        echo "" >> "$summary_file"
        echo "═══════════════════════════════════════════════════════════════" >> "$summary_file"
        echo "DETECTED ISSUES" >> "$summary_file"
        echo "═══════════════════════════════════════════════════════════════" >> "$summary_file"
        echo "" >> "$summary_file"

        if [[ $has_failures -eq 1 ]]; then
            echo "❌ CRITICAL ISSUES:" >> "$summary_file"
            echo "" >> "$summary_file"
            for failure in "${FAILURES[@]}"; do
                echo "  • $failure" >> "$summary_file"
            done
            echo "" >> "$summary_file"
        fi

        if [[ $has_warnings -eq 1 ]]; then
            echo "⚠️  WARNINGS:" >> "$summary_file"
            echo "" >> "$summary_file"
            for warning in "${WARNINGS[@]}"; do
                echo "  • $warning" >> "$summary_file"
            done
            echo "" >> "$summary_file"
        fi
    fi

    # Recommendations section
    if [[ $has_recommendations -eq 1 ]]; then
        echo "═══════════════════════════════════════════════════════════════" >> "$summary_file"
        echo "RECOMMENDATIONS" >> "$summary_file"
        echo "═══════════════════════════════════════════════════════════════" >> "$summary_file"
        echo "" >> "$summary_file"
        echo "Based on the test results, we recommend:" >> "$summary_file"
        echo "" >> "$summary_file"

        local rec_num=1
        # Deduplicate recommendations
        local -A seen_recs
        for rec in "${RECOMMENDATIONS[@]}"; do
            if [[ -z "${seen_recs[$rec]:-}" ]]; then
                echo "${rec_num}. $rec" >> "$summary_file"
                echo "" >> "$summary_file"
                seen_recs[$rec]=1
                ((rec_num++)) || true
            fi
        done

        # Add standard recommendations based on failure patterns
        if [[ $FAIL_COUNT -gt 0 ]]; then
            if grep -q "TLS\|SSL\|certificate" "$summary_file"; then
                echo "${rec_num}. Check for corporate firewall SSL inspection:" >> "$summary_file"
                echo "   • Whitelist *.newrelic.com domains in SSL inspection bypass" >> "$summary_file"
                echo "   • Contact your network/security team about SSL interception" >> "$summary_file"
                echo "" >> "$summary_file"
                ((rec_num++)) || true
            fi

            echo "${rec_num}. Provide this tarball to New Relic Support:" >> "$summary_file"
            echo "   • Attach ${OUTPUT_DIR}.tar.gz to your support case" >> "$summary_file"
            echo "   • Include this SUMMARY.txt in your case description" >> "$summary_file"
            echo "" >> "$summary_file"
        fi
    else
        echo "═══════════════════════════════════════════════════════════════" >> "$summary_file"
        echo "RESULT" >> "$summary_file"
        echo "═══════════════════════════════════════════════════════════════" >> "$summary_file"
        echo "" >> "$summary_file"
        echo "✅ All tests passed! Network connectivity to New Relic appears healthy." >> "$summary_file"
        echo "" >> "$summary_file"
        echo "If you're still experiencing issues with your New Relic agent:" >> "$summary_file"
        echo "  1. Check the agent configuration file" >> "$summary_file"
        echo "  2. Verify the license key is correct" >> "$summary_file"
        echo "  3. Review agent logs (if collected in the tarball)" >> "$summary_file"
        echo "  4. Verify you're using the correct data center region (US vs EU)" >> "$summary_file"
        echo "  5. Attach this tarball to your support case for further analysis" >> "$summary_file"
        echo "" >> "$summary_file"
    fi

    echo "═══════════════════════════════════════════════════════════════" >> "$summary_file"
    echo "ADDITIONAL RESOURCES" >> "$summary_file"
    echo "═══════════════════════════════════════════════════════════════" >> "$summary_file"
    echo "" >> "$summary_file"
    echo "New Relic Network Traffic Documentation:" >> "$summary_file"
    echo "  https://docs.newrelic.com/docs/new-relic-solutions/get-started/networks/" >> "$summary_file"
    echo "" >> "$summary_file"

    case "$AGENT_TYPE" in
        apm)
            echo "APM Agent Documentation:" >> "$summary_file"
            echo "  https://docs.newrelic.com/docs/apm/" >> "$summary_file"
            ;;
        browser)
            echo "Browser Monitoring Documentation:" >> "$summary_file"
            echo "  https://docs.newrelic.com/docs/browser/" >> "$summary_file"
            ;;
        mobile)
            echo "Mobile Monitoring Documentation:" >> "$summary_file"
            echo "  https://docs.newrelic.com/docs/mobile-monitoring/" >> "$summary_file"
            ;;
        infrastructure)
            echo "Infrastructure Monitoring Documentation:" >> "$summary_file"
            echo "  https://docs.newrelic.com/docs/infrastructure/" >> "$summary_file"
            ;;
        opentelemetry)
            echo "OpenTelemetry Documentation:" >> "$summary_file"
            echo "  https://docs.newrelic.com/docs/more-integrations/open-source-telemetry-integrations/opentelemetry/" >> "$summary_file"
            ;;
        apis)
            echo "Telemetry API Documentation:" >> "$summary_file"
            echo "  https://docs.newrelic.com/docs/data-apis/ingest-apis/" >> "$summary_file"
            ;;
    esac
    echo "" >> "$summary_file"
    echo "═══════════════════════════════════════════════════════════════" >> "$summary_file"
}


# --- Section 9: Generate and Display Summary ---
log_section "Generating Summary Report"

generate_summary_report

# Display summary to console
echo ""
log_section "TEST SUMMARY"
echo ""

# Display the summary file with colors
if [[ -f "${OUTPUT_DIR}/SUMMARY.txt" ]]; then
    # Display summary with color highlighting
    while IFS= read -r line; do
        if [[ "$line" =~ ^═+$ ]] || [[ "$line" =~ ^─+$ ]]; then
            echo -e "${CYAN}${line}${NC}"
        elif [[ "$line" =~ ✅ ]]; then
            echo -e "${GREEN}${line}${NC}"
        elif [[ "$line" =~ ❌ ]]; then
            echo -e "${RED}${line}${NC}"
        elif [[ "$line" =~ ⚠️ ]]; then
            echo -e "${YELLOW}${line}${NC}"
        elif [[ "$line" =~ ^[A-Z\ ]+$ ]] && [[ ${#line} -lt 70 ]]; then
            echo -e "${BOLD}${line}${NC}"
        else
            echo "$line"
        fi
    done < "${OUTPUT_DIR}/SUMMARY.txt"
fi

echo ""
log_section "Creating Archive"

# Compress all output files
log_info "Compressing diagnostic data..."
tar -czf "${OUTPUT_DIR}.tar.gz" "${OUTPUT_DIR}" 2>&1 | head -20 || true

# When run with sudo, files are created as root. Change ownership back to the original user
if [[ -n "${SUDO_USER:-}" ]]; then
    chown -R "${SUDO_USER}:${SUDO_GID:-$(id -g "$SUDO_USER")}" "${OUTPUT_DIR}" "${OUTPUT_DIR}.tar.gz" &> /dev/null || true
fi

echo ""
log_section "DIAGNOSTICS COMPLETE"
echo ""

if [[ $FAIL_COUNT -gt 0 ]]; then
    echo -e "${RED}⚠️  ${FAIL_COUNT} critical issues detected!${NC}"
    echo -e "${YELLOW}Please review the summary above and attach ${OUTPUT_DIR}.tar.gz to your support case.${NC}"
elif [[ $WARN_COUNT -gt 0 ]]; then
    echo -e "${YELLOW}⚠️  ${WARN_COUNT} warnings detected.${NC}"
    echo -e "${YELLOW}Review the summary above. If issues persist, attach ${OUTPUT_DIR}.tar.gz to your support case.${NC}"
else
    echo -e "${GREEN}✅ All tests passed!${NC}"
    echo -e "${GREEN}Network connectivity appears healthy. If issues persist, attach ${OUTPUT_DIR}.tar.gz to your support case.${NC}"
fi

echo ""
echo -e "${CYAN}Output files saved in:${NC} ${OUTPUT_DIR}/"
echo -e "${CYAN}Archive file:${NC}          ${OUTPUT_DIR}.tar.gz"
echo -e "${CYAN}Summary report:${NC}        ${OUTPUT_DIR}/SUMMARY.txt"
echo ""
echo -e "${BOLD}Next steps:${NC}"
echo "  1. Review the summary above"
echo "  2. Check ${OUTPUT_DIR}/SUMMARY.txt for detailed recommendations"
echo "  3. Attach ${OUTPUT_DIR}.tar.gz to your New Relic support case"
echo ""
