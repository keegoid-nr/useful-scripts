#!/bin/bash
#
# Job Lifecycle & Parking Lot Throughput Analyzer
#
# This script analyzes application logs to track the lifecycle of asynchronous jobs,
# focusing on their flow through a "parking lot" system. It measures throughput
# and identifies potential bottlenecks or discrepancies in the job processing funnel.
#
# The script parses logs for two main job types:
# - Heavyweight jobs (e.g., SCRIPT_BROWSER, SCRIPT_API) which are queued.
# - Lightweight jobs (SIMPLE) which are processed differently.
#
# Key Metrics Calculated:
# - Jobs Staged vs. Jobs Put into the Parking Lot.
# - Successful Job Retrievals (Throughput) vs. Empty Retrievals.
# - Discrepancy between jobs entering the lot and jobs being retrieved.
# - A breakdown of these metrics over a user-defined number of time intervals.
#
# Author : Keegan Mullaney
# Company: New Relic
# Email  : kmullaney@newrelic.com
# Website: github.com/keegoid-nr/useful-scripts
# License: Apache License 2.0
#

# Exit immediately if a command exits with a non-zero status.
set -e

## --- Dependency Check ---
# Ensure GNU Awk (gawk) is installed, as it's required for advanced array and time functions.
if ! command -v gawk &> /dev/null; then
    echo "Error: This script requires GNU Awk (gawk), which was not found." >&2
    echo "Please install it to continue." >&2
    echo "On macOS (with Homebrew): brew install gawk" >&2
    echo "On Debian/Ubuntu: sudo apt-get install gawk" >&2
    exit 1
fi

## --- Argument Parsing ---
VERBOSE_MODE=0; POS_ARGS=()
while [[ $# -gt 0 ]]; do
  case $1 in
    --verbose) VERBOSE_MODE=1; shift ;;
    *) POS_ARGS+=("$1"); shift ;;
  esac
done
LOG_FILE="${POS_ARGS[0]}"
# Default to 5 intervals if not specified by the user.
NUM_INTERVALS=${POS_ARGS[1]:-5}

## --- Input Validation ---
if [ -z "$LOG_FILE" ]; then
  echo "Error: No log file specified." >&2
  echo "Usage: $0 <path_to_log_file> [number_of_intervals] [--verbose]" >&2
  exit 1
fi
if ! [[ "$NUM_INTERVALS" =~ ^[0-9]+$ ]] || [ ! -r "$LOG_FILE" ]; then
    echo "Error: Number of intervals must be a positive integer, and the log file must be readable." >&2
    echo "Usage: $0 <path_to_log_file> [number_of_intervals] [--verbose]" >&2
    exit 1
fi

## --- Step 1: Find the Time Range ---
echo "🔎 Finding first and last valid timestamps (YYYY-MM-DD format)..."
# Scan the log file to find the very first and last matching timestamps to define the analysis window.
time_boundaries=$(gawk '/^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2},[0-9]{3}\{/ { if (first == "") { first = $1 " " $2 }; last = $1 " " $2 } END { print first; print last }' "$LOG_FILE")

if [ -z "$time_boundaries" ]; then
    echo "Error: Could not find any log lines with the 'YYYY-MM-DD' timestamp format to determine the time range." >&2
    exit 1
fi

# Extract the start and end timestamp strings.
first_ts_str=$(echo "$time_boundaries" | head -n 1); last_ts_str=$(echo "$time_boundaries" | tail -n 1)
# Convert timestamp strings to epoch seconds for calculations.
start_epoch=$(date -d "$(echo "$first_ts_str" | sed 's/,.*//; s/{.*}//')" +%s)
end_epoch=$(date -d "$(echo "$last_ts_str" | sed 's/,.*//; s/{.*}//')" +%s)

# Calculate the duration and the length of each analysis interval.
total_duration=$((end_epoch - start_epoch))
if [ "$total_duration" -eq 0 ]; then total_duration=1; fi
interval_length=$((total_duration / NUM_INTERVALS))
if [ "$interval_length" -lt 1 ]; then interval_length=1; fi

echo "   - Log starts at: $(date -d @$start_epoch)"
echo "   - Log ends at:   $(date -d @$end_epoch)"
echo "   - Analyzing in $NUM_INTERVALS intervals of $interval_length seconds each."
echo

## --- Step 2 & 3: Process the log and generate reports ---

# The gawk script below is the core of the analyzer. Here's a summary of its logic:
#
# 1. TIMESTAMP PARSING:
#    - It handles two timestamp formats: "YYYY-MM-DD HH:MM:SS,..." and Nginx-style "[DD/Mon/YYYY:...]".
#    - Each log line's timestamp is converted to an epoch second to determine which time interval ("bucket") it belongs to.
#
# 2. LIFECYCLE EVENT COUNTING:
#    - It scans each line for specific phrases to count key events per time bucket.
#    - "is being staged": Differentiates between heavyweight (SCRIPT_BROWSER, etc.) and lightweight (SIMPLE) jobs.
#    - "Putting job ... into the parking lot": Counts heavyweight jobs entering the queue.
#    - "(SIMPLE) to Processor": Counts lightweight jobs submitted.
#    - "/submit/job" with HTTP 202: Counts all jobs accepted via the API.
#    - Runtime GET requests (e.g., /script_api): Counts successful job retrievals (HTTP 200) and empty polls (HTTP 204).
#
# 3. REPORTING (in the END block):
#    - It iterates through each time bucket to print a formatted summary.
#    - It calculates throughput in jobs/minute.
#    - It derives the "heavyweight submitted" count by subtracting lightweight jobs from the total API submissions.
#    - Finally, it prints an overall summary, including the key "Discrepancy" metric, which is the difference
#      between jobs put into the lot and jobs retrieved.
#
gawk -v start="$start_epoch" -v interval="$interval_length" -v num_intervals="$NUM_INTERVALS" -v verbose="$VERBOSE_MODE" -v total_dur="$total_duration" '
function format_time(epoch) { return strftime("%Y-%m-%d %H:%M:%S", epoch) }
BEGIN {
    months_str = "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec"; split(months_str, months_arr, " ")
    for (i in months_arr) { month_map[months_arr[i]] = sprintf("%02d", i) }
}
{
    current_epoch = 0
    if ($1 ~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/ && $2 ~ /^[0-9]{2}:[0-9]{2}:[0-9]{2},/) {
        year = substr($1, 1, 4); month = substr($1, 6, 2); day = substr($1, 9, 2)
        hour = substr($2, 1, 2); min = substr($2, 4, 2); sec = substr($2, 7, 2)
        current_epoch = mktime(year " " month " " day " " hour " " min " " sec)
    } else if ($4 ~ /\[[0-9]{2}\/[A-Z][a-z]{2}\/[0-9]{4}:/) {
        ts_str = $4; gsub(/\[/, "", ts_str)
        year = substr(ts_str, 8, 4); month_abbr = substr(ts_str, 4, 3); month_num = month_map[month_abbr]
        day = substr(ts_str, 1, 2); hour = substr(ts_str, 13, 2); min = substr(ts_str, 16, 2); sec = substr(ts_str, 19, 2)
        current_epoch = mktime(year " " month_num " " day " " hour " " min " " sec)
    }

    if (current_epoch > 0) {
        bucket = int((current_epoch - start) / interval)
        if (bucket >= num_intervals) { bucket = num_intervals - 1 }

        if ($0 ~ /is being staged for execution/) {
            if ($0 ~ /Type: \[(SCRIPT_BROWSER|SCRIPT_API|BROWSER)\]/) {
                staged_heavyweight_count[bucket]++;
            } else if ($0 ~ /Type: \[SIMPLE\]/) {
                staged_lightweight_count[bucket]++;
            }
            next
        }
        if ($0 ~ /Putting job .* into the parking lot/) {
            put_into_lot_count[bucket]++; next
        }
        if ($0 ~ /\(SIMPLE\) to Processor/) {
            simple_job_count[bucket]++; next
        }
        if ($7 ~ /submit\/job/ && $9 == 202) {
            post_202_count[bucket] += $NF; next
        }

        runtime = $7; sub(/.*\//, "", runtime)
        if (runtime == "script_api" || runtime == "script_browser") {
            http_code = $9
            if (http_code == 200) {
                retrieved_ok_count[bucket]++
            } else if (http_code == 204) {
                retrieved_empty_count[bucket]++
            }
        }
    }
}
END {
    grand_total_staged_hw = 0; grand_total_staged_lw = 0; grand_total_put_in_lot = 0
    grand_total_retrieved_ok = 0; grand_total_retrieved_empty = 0
    grand_total_simple = 0; grand_total_post_202 = 0

    for (b = 0; b < num_intervals; b++) {
        interval_start = start + (b * interval); interval_end = interval_start + interval - 1
        if (b == num_intervals - 1) { interval_end = start + total_dur }
        print "--- 📊 Time Interval " (b+1) " of " num_intervals " (" format_time(interval_start) " to " format_time(interval_end) ") ---"

        staged_hw = staged_heavyweight_count[b] + 0; grand_total_staged_hw += staged_hw
        staged_lw = staged_lightweight_count[b] + 0; grand_total_staged_lw += staged_lw
        put_in_lot = put_into_lot_count[b] + 0; grand_total_put_in_lot += put_in_lot
        retrieved_ok = retrieved_ok_count[b] + 0; grand_total_retrieved_ok += retrieved_ok
        retrieved_empty = retrieved_empty_count[b] + 0; grand_total_retrieved_empty += retrieved_empty
        simple_jobs = simple_job_count[b] + 0; grand_total_simple += simple_jobs
        post_202_jobs = post_202_count[b] + 0; grand_total_post_202 += post_202_jobs

        heavyweight_submitted = post_202_jobs - simple_jobs
        throughput_rate = 0
        if (interval > 0) { throughput_rate = (retrieved_ok / interval) * 60 }

        print "   --- Heavyweight Job Funnel ---"
        print "   - Jobs Staged:                 " staged_hw
        print "   - Jobs Put into Parking Lot:   " put_in_lot
        print "   - Jobs Retrieved (200 OK):     " retrieved_ok " (" sprintf("%.2f jobs/min", throughput_rate) ")"
        print "   - Empty Retrievals (204):      " retrieved_empty
        print "   - Jobs Submitted (202):        " heavyweight_submitted

        print "\n   --- Lightweight Job Funnel ---"
        print "   - Jobs Staged:                 " staged_lw
        print "   - Jobs Submitted (202):        " simple_jobs
        print "----------------------------------------------------------------------"
    }

    print "\n======================================================================"
    print "✅ OVERALL SUMMARY"
    print "======================================================================"

    overall_throughput_rate = 0
    if (total_dur > 0) { overall_throughput_rate = (grand_total_retrieved_ok / total_dur) * 60 }

    grand_total_heavyweight_submitted = grand_total_post_202 - grand_total_simple

    print "--- Heavyweight Job Funnel ---"
    print "   - Total Jobs Staged:                 " grand_total_staged_hw
    print "   - Total Jobs Put into Lot:           " grand_total_put_in_lot
    print "   - Total Jobs Retrieved (Throughput): " grand_total_retrieved_ok " (" sprintf("%.2f jobs/min avg", overall_throughput_rate) ")"
    print "   - Total Jobs Submitted:              " grand_total_heavyweight_submitted

    print "\n--- Lightweight Job Funnel ---"
    print "   - Total Jobs Staged:                 " grand_total_staged_lw
    print "   - Total Jobs Submitted:              " grand_total_simple

    print "\n--- Parking Lot Analysis ---"
    print "   - Total Empty Retrievals:            " grand_total_retrieved_empty
    discrepancy = grand_total_put_in_lot - grand_total_retrieved_ok
    print "   - Discrepancy (Put in Lot vs. Retrieved): " discrepancy
    print "======================================================================"
}
' "$LOG_FILE"
