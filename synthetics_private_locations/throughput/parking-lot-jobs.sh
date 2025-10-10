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
gawk -v start="$start_epoch" -v interval="$interval_length" -v num_intervals="$NUM_INTERVALS" -v verbose="$VERBOSE_MODE" -v total_dur="$total_duration" '
# A function to format epoch seconds into a human-readable string.
function format_time(epoch) { return strftime("%Y-%m-%d %H:%M:%S", epoch) }

# BEGIN block: Executes once before processing any lines.
BEGIN {
    # Create a mapping from three-letter month abbreviations to numeric months (e.g., "Jan" -> "01").
    # This is necessary for the mktime() function to parse one of the timestamp formats.
    months_str = "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec"; split(months_str, months_arr, " ")
    for (i in months_arr) { month_map[months_arr[i]] = sprintf("%02d", i) }
}

# Main block: Executes for each line in the log file.
{
    current_epoch = 0
    # --- Unified Timestamp Parser ---
    # Attempt to parse one of two known timestamp formats to get the current line's epoch time.

    # Format 1: "YYYY-MM-DD HH:MM:SS,ms{...}"
    if ($1 ~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/ && $2 ~ /^[0-9]{2}:[0-9]{2}:[0-9]{2},/) {
        year = substr($1, 1, 4); month = substr($1, 6, 2); day = substr($1, 9, 2)
        hour = substr($2, 1, 2); min = substr($2, 4, 2); sec = substr($2, 7, 2)
        current_epoch = mktime(year " " month " " day " " hour " " min " " sec)
    }
    # Format 2: Nginx-style "[DD/Mon/YYYY:HH:MM:SS ...]"
    else if ($4 ~ /\[[0-9]{2}\/[A-Z][a-z]{2}\/[0-9]{4}:/) {
        ts_str = $4; gsub(/\[/, "", ts_str)
        year = substr(ts_str, 8, 4); month_abbr = substr(ts_str, 4, 3); month_num = month_map[month_abbr]
        day = substr(ts_str, 1, 2); hour = substr(ts_str, 13, 2); min = substr(ts_str, 16, 2); sec = substr(ts_str, 19, 2)
        current_epoch = mktime(year " " month_num " " day " " hour " " min " " sec)
    }

    # If a valid timestamp was found, process the log line.
    if (current_epoch > 0) {
        # Determine which time interval (bucket) this log line falls into.
        bucket = int((current_epoch - start) / interval)
        if (bucket >= num_intervals) { bucket = num_intervals - 1 } # Put overflow into the last bucket.

        # --- Lifecycle Event Parsing ---
        # Match log patterns to count different job lifecycle events.

        # A job is staged for execution.
        if ($0 ~ /is being staged for execution/) {
            # Differentiate between heavyweight and lightweight jobs being staged.
            if ($0 ~ /Type: \[(SCRIPT_BROWSER|SCRIPT_API|BROWSER)\]/) {
                staged_heavyweight_count[bucket]++;
            } else if ($0 ~ /Type: \[SIMPLE\]/) {
                staged_lightweight_count[bucket]++;
            }
            next # Skip to the next line after a match.
        }
        # A heavyweight job is being queued in the parking lot.
        if ($0 ~ /Putting job .* into the parking lot/) {
            put_into_lot_count[bucket]++; next
        }
        # A lightweight (SIMPLE) job is submitted directly to the processor.
        if ($0 ~ /\(SIMPLE\) to Processor/) {
            simple_job_count[bucket]++; next
        }
        # An API call submitted a job and received a 202 Accepted.
        # This counts BOTH heavyweight and lightweight jobs submitted via the API.
        if ($7 ~ /submit\/job/ && $9 == 202) {
            # The last field ($NF) contains the count of jobs submitted in this request.
            post_202_count[bucket] += $NF; next
        }

        # --- Job Retrieval Parsing ---
        # A runtime is polling the parking lot for a heavyweight job.
        runtime = $7; sub(/.*\//, "", runtime) # Extract runtime name from the URL path.
        if (runtime == "script_api" || runtime == "script_browser") {
            http_code = $9
            if (http_code == 200) { # A job was successfully retrieved.
                retrieved_ok_count[bucket]++
            } else if (http_code == 204) { # The parking lot was polled but was empty.
                retrieved_empty_count[bucket]++
            }
        }
    }
}
# END block: Executes once after all lines have been processed to summarize results.
END {
    # Initialize grand totals for the final summary.
    grand_total_staged_hw = 0; grand_total_staged_lw = 0; grand_total_put_in_lot = 0
    grand_total_retrieved_ok = 0; grand_total_retrieved_empty = 0
    grand_total_simple = 0; grand_total_post_202 = 0

    # --- Interval Reporting ---
    # Loop through each time bucket and print a detailed report.
    for (b = 0; b < num_intervals; b++) {
        # Calculate start and end times for the current interval.
        interval_start = start + (b * interval); interval_end = interval_start + interval - 1
        # Ensure the last interval ends exactly at the last timestamp.
        if (b == num_intervals - 1) { interval_end = start + total_dur }
        print "--- 📊 Time Interval " (b+1) " of " num_intervals " (" format_time(interval_start) " to " format_time(interval_end) ") ---"

        # Safely access array counts, defaulting to 0 if no events occurred in this bucket.
        staged_hw = staged_heavyweight_count[b] + 0; grand_total_staged_hw += staged_hw
        staged_lw = staged_lightweight_count[b] + 0; grand_total_staged_lw += staged_lw
        put_in_lot = put_into_lot_count[b] + 0; grand_total_put_in_lot += put_in_lot
        retrieved_ok = retrieved_ok_count[b] + 0; grand_total_retrieved_ok += retrieved_ok
        retrieved_empty = retrieved_empty_count[b] + 0; grand_total_retrieved_empty += retrieved_empty
        simple_jobs = simple_job_count[b] + 0; grand_total_simple += simple_jobs
        post_202_jobs = post_202_count[b] + 0; grand_total_post_202 += post_202_jobs

        # Calculate the number of heavyweight jobs submitted.
        # This is derived by taking the total jobs submitted (202s) and subtracting the lightweight ones.
        heavyweight_submitted = post_202_jobs - simple_jobs
        # Calculate the throughput rate for this interval in jobs per minute.
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

    # --- Final Summary ---
    print "\n======================================================================"
    print "✅ OVERALL SUMMARY"
    print "======================================================================"

    # Calculate overall average throughput across the entire log duration.
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
    # The discrepancy is a key health indicator: it shows how many jobs entered the lot but were not retrieved.
    # A large positive number could indicate jobs are getting stuck.
    discrepancy = grand_total_put_in_lot - grand_total_retrieved_ok
    print "   - Discrepancy (Put in Lot vs. Retrieved): " discrepancy
    print "======================================================================"
}
' "$LOG_FILE"
