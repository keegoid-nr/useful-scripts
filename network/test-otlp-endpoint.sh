#!/bin/bash
# Test OTLP Endpoint Script
#
# Author : Keegan Mullaney
# Company: New Relic
# Email  : kmullaney@newrelic.com
# Website: github.com/keegoid-nr/useful-scripts
# License: Apache License 2.0


# Define the target domain for mtr
TARGET_DOMAIN="otlp.nr-data.net"
TARGET_PORT="4318"
PAGE="v1/metrics"
URL="https://$TARGET_DOMAIN:$TARGET_PORT/$PAGE"

# Send a POST request to the specified URL with the specified headers
# The -o /dev/null discards the body of the response, keeping just the HTTP status code
# The -w option specifies a custom output format to include the IP address and HTTP status code
OTLP_INFO=$(curl -X POST -o /dev/null -s -w "IP: %{remote_ip}, Response Code: %{http_code}\n" -H "Content-Type: application/json" -H "api-key: $NEW_RELIC_LICENSE_KEY" $URL)

# Print the IP address and response code for the OTLP request
echo "$OTLP_INFO"
