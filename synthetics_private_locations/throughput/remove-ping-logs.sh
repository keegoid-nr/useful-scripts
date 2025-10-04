#!/bin/bash
# Removes ping jobs from SJM logs
#
# Author : Keegan Mullaney
# Company: New Relic
# Email  : kmullaney@newrelic.com
# Website: github.com/keegoid-nr/useful-scripts
# License: Apache License 2.0

# --- Configuration ---
LOG_FILE="${1:-your_log_file.log}" # Use first argument or default
FILTERED_LOG="${2:-filtered_log.log}" # Use second argument or default
GUID_LIST="guids_to_remove.tmp"

# Check if the input file exists
if [ ! -f "$LOG_FILE" ]; then
    echo "❌ Error: Input file '$LOG_FILE' not found."
    exit 1
fi

echo "🔎 Step 1: Finding unique GUIDs from '(SIMPLE)' lines..."
# Find all unique GUIDs from lines containing (SIMPLE) and save them to a temp file
grep '(SIMPLE)' "$LOG_FILE" | grep -oE '[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}' | sort -u > "$GUID_LIST"

echo "✍️  Step 2: Filtering the log file..."
# Use grep's -v flag to invert the match (i.e., select non-matching lines)
# First, remove all lines containing (SIMPLE)
# Then, from that result, remove all lines containing a GUID from our list using the temp file
grep -vF '(SIMPLE)' "$LOG_FILE" | grep -vFf "$GUID_LIST" > "$FILTERED_LOG"

# Clean up the temporary GUID list file
rm "$GUID_LIST"

echo "✅ Processing complete. Filtered log written to '$FILTERED_LOG'."
