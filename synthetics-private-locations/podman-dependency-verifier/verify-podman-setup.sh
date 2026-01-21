#!/bin/bash
# shellcheck disable=SC2016
: '
This script performs a deep inspection of the Podman configuration,
checking versions, config files, systemd delegation, API availability,
networking (slirp4netns), and host connectivity.

Author : Keegan Mullaney
Company: New Relic
Email  : kmullaney@newrelic.com
Website: github.com/keegoid-nr/useful-scripts
License: Apache License 2.0
'

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global pass/fail tracker
FAILURES=0

print_pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
print_fail() { echo -e "${RED}[FAIL]${NC} $1"; ((FAILURES++)); }
print_info() { echo -e "${YELLOW}[INFO]${NC} $1"; }
print_skip() { echo -e "${BLUE}[SKIPPED]${NC} $1"; }
print_header() { echo -e "\n${YELLOW}=== $1 ===${NC}"; }


show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Verifies Podman setup for New Relic Synthetics Job Manager."
    echo ""
    echo "Options:"
    echo "  -h, --help    Show this help message and exit"
    echo ""
    echo "Description:"
    echo "  This script performs a deep inspection of the Podman configuration,"
    echo "  checking versions, config files, systemd delegation, API availability,"
    echo "  networking (slirp4netns), and host connectivity."
}

# Check for help flag
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    show_usage
    exit 0
fi

echo "Starting configuration verification..."

# ------------------------------------------------------------------------------
# 1. Check Podman Version
# ------------------------------------------------------------------------------
print_header "1. Checking Podman Version"

if ! command -v podman &> /dev/null; then
    print_fail "Podman is not installed or not in PATH."
else
    PODMAN_VER=$(podman --version | awk '{print $3}' | sed 's/-.*//')
    REQUIRED_VER="5.0.0"
    if [[ "$(printf '%s\n%s' "$REQUIRED_VER" "$PODMAN_VER" | sort -V | head -n1)" == "$REQUIRED_VER" ]]; then
        print_pass "Podman version $PODMAN_VER is installed (>= $REQUIRED_VER)."
    else
        print_fail "Podman version is $PODMAN_VER. Version 5.0.0+ is required."
    fi
fi

# ------------------------------------------------------------------------------
# 2. Check Rootless Config (containers.conf)
# ------------------------------------------------------------------------------
print_header "2. Checking Rootless Configuration"
CONF_FILE="$HOME/.config/containers/containers.conf"

if [[ -f "$CONF_FILE" ]]; then
    print_pass "Configuration file exists."
    if grep -q 'runtime = "crun"' "$CONF_FILE"; then print_pass "Runtime is 'crun'."; else print_fail "Runtime NOT set to 'crun'."; fi
    if grep -q 'cgroup_manager = "systemd"' "$CONF_FILE"; then print_pass "Cgroup manager is 'systemd'."; else print_fail "Cgroup manager NOT set to 'systemd'."; fi
else
    print_fail "Configuration file missing: $CONF_FILE"
fi

# ------------------------------------------------------------------------------
# 3. Check Cgroups v2 (RHEL/CentOS Only)
# ------------------------------------------------------------------------------
print_header "3. Checking Cgroups v2 (RHEL Specific)"

if [[ -f /etc/os-release ]]; then . /etc/os-release; OS_ID=$ID; OS_LIKE=$ID_LIKE; else OS_ID="unknown"; fi

if [[ "$OS_ID" =~ (rhel|centos|fedora) ]] || [[ "$OS_LIKE" =~ (rhel|centos|fedora) ]]; then
    if findmnt -t cgroup2 &> /dev/null; then
        print_pass "Cgroups v2 filesystem is mounted."
    else
        print_fail "Cgroups v2 filesystem is NOT detected."
    fi
    # Only check GRUB on RHEL 8 or if specifically looking for the flag
    if grep -q "systemd.unified_cgroup_hierarchy=1" /proc/cmdline; then
        print_pass "Kernel booted with systemd.unified_cgroup_hierarchy=1."
    else
        print_info "Kernel flag not found. (Safe to ignore if on RHEL 9+ and Cgroups v2 passed above)."
    fi
else
    print_skip "OS is not RHEL-based ($OS_ID). Skipping GRUB check."
fi

# ------------------------------------------------------------------------------
# 4 & 5. Check Delegation
# ------------------------------------------------------------------------------
print_header "4 & 5. Checking System & User Delegation"
SYS_DELEGATE="/etc/systemd/system/user@.service.d/delegate.conf"
USER_DELEGATE="$HOME/.config/systemd/user/podman.service.d/override.conf"

[[ -f "$SYS_DELEGATE" ]] && grep -q "Delegate=yes" "$SYS_DELEGATE" && print_pass "System delegation OK." || print_fail "System delegation missing/incorrect."
[[ -f "$USER_DELEGATE" ]] && grep -q "Delegate=yes" "$USER_DELEGATE" && print_pass "User delegation OK." || print_fail "User delegation missing/incorrect."

# ------------------------------------------------------------------------------
# 6, 7 & 8. Check Podman Socket & API
# ------------------------------------------------------------------------------
print_header "6, 7 & 8. Checking Socket & API Service"

systemctl --user is-active --quiet podman.socket && print_pass "Podman socket active." || print_fail "Podman socket inactive."
systemctl --user is-active --quiet podman-api.service && print_pass "API Service active." || print_fail "API Service inactive."

API_SERVICE="$HOME/.config/systemd/user/podman-api.service"
if [[ -f "$API_SERVICE" ]] && grep -q "tcp:0.0.0.0:8000" "$API_SERVICE"; then
    print_pass "API Configured for 0.0.0.0:8000."
else
    print_fail "API Service not binding to 0.0.0.0:8000."
fi

if curl -s --max-time 2 http://localhost:8000/_ping > /dev/null; then
    print_pass "Localhost API Ping successful."
else
    print_fail "API failed to respond on localhost:8000."
fi

# ------------------------------------------------------------------------------
# 9. Check Network Backend (slirp4netns)
# ------------------------------------------------------------------------------
print_header "9. Checking slirp4netns"

if command -v slirp4netns &> /dev/null; then
    print_pass "slirp4netns is installed."
else
    print_fail "slirp4netns is NOT installed. (Required for rootless networking)."
fi

# ------------------------------------------------------------------------------
# 10. HOST IP CHECK (Prevents the common "Cannot communicate" error)
# ------------------------------------------------------------------------------
print_header "10. Host IP & Connectivity Check"

# Detect the primary IP address (route to internet)
HOST_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')

if [[ -z "$HOST_IP" ]]; then
    print_fail "Could not detect a valid HOST IP address."
else
    print_pass "Detected Host IP: $HOST_IP"

    # Verify API is reachable via this IP (Simulating what the container will try)
    if curl -s --max-time 2 "http://$HOST_IP:8000/_ping" > /dev/null; then
        print_pass "Connectivity Confirmed: API is reachable via $HOST_IP."
    else
        print_fail "Connectivity Check Failed: API is NOT reachable via $HOST_IP."
        print_info "Ensure firewall (firewalld/iptables) allows traffic on port 8000."
    fi
fi

# ==============================================================================
# Summary & Next Steps
# ==============================================================================
echo -e "\n${YELLOW}=== Verification Summary ===${NC}"
if [[ $FAILURES -eq 0 ]]; then
    echo -e "${GREEN}SUCCESS: All checks passed.${NC}"

    echo -e "\n${BLUE}# 1. Create the Pod${NC}"
    echo "podman pod create --network slirp4netns --name synthetics-pod --add-host=podman.service:$HOST_IP"
    
    echo -e "\n${BLUE}# 2. Start the Synthetics Job Manager${NC}"
    echo "podman run \\"
    echo "  --name synthetics-job-manager \\"
    echo "  --pod synthetics-pod \\"
    echo "  -e \"PRIVATE_LOCATION_KEY=YOUR_KEY_HERE\" \\"
    echo "  -e \"CONTAINER_ENGINE=PODMAN\" \\"
    echo "  -e \"PODMAN_API_SERVICE_PORT=8000\" \\"
    echo "  -e \"PODMAN_POD_NAME=synthetics-pod\" \\"
    echo "  -d --restart unless-stopped \\"
    echo "  newrelic/synthetics-job-manager:latest"
else
    echo -e "${RED}FAILURE: $FAILURES check(s) failed. Fix issues before running the container.${NC}"
    exit 1
fi
