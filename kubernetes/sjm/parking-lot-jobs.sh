#!/bin/bash
# Script with submission rate calculation in jobs/minute
#
# Author : Keegan Mullaney
# Company: New Relic
# Email  : kmullaney@newrelic.com
# Website: github.com/keegoid-nr/useful-scripts
# License: Apache License 2.0

set -e # Exit immediately if a command exits with a non-zero status.

## --- Dependency Check ---
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
LOG_FILE="${POS_ARGS[0]}"; NUM_INTERVALS=${POS_ARGS[1]:-5}

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

## --- Step 1: Find the Time Range (Using YYYY-MM-DD format) ---
echo "🔎 Finding first and last valid timestamps (YYYY-MM-DD format)..."
time_boundaries=$(gawk '/^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2},[0-9]{3}\{/ { if (first == "") { first = $1 " " $2 }; last = $1 " " $2 } END { print first; print last }' "$LOG_FILE")

if [ -z "$time_boundaries" ]; then
    echo "Error: Could not find any log lines with the 'YYYY-MM-DD' timestamp format to determine the time range." >&2
    exit 1
fi

first_ts_str=$(echo "$time_boundaries" | head -n 1); last_ts_str=$(echo "$time_boundaries" | tail -n 1)
start_epoch=$(date -d "$(echo "$first_ts_str" | sed 's/,.*//; s/{.*}//')" +%s)
end_epoch=$(date -d "$(echo "$last_ts_str" | sed 's/,.*//; s/{.*}//')" +%s)

# --- CORRECTED: More robust duration and interval calculation ---
total_duration=$((end_epoch - start_epoch))
# Handle case where duration is 0 to avoid division by zero
if [ "$total_duration" -eq 0 ]; then
    total_duration=1
fi
interval_length=$((total_duration / NUM_INTERVALS))
# Handle case where integer division results in 0 for very short logs
if [ "$interval_length" -lt 1 ]; then
    interval_length=1
fi
# --- END CORRECTION ---

echo "   - Log starts at: $(date -d @$start_epoch)"
echo "   - Log ends at:   $(date -d @$end_epoch)"
echo "   - Analyzing in $NUM_INTERVALS intervals of $interval_length seconds each."
echo

## --- Step 2 & 3: Process the log and generate reports ---
gawk -v start="$start_epoch" -v interval="$interval_length" -v num_intervals="$NUM_INTERVALS" -v verbose="$VERBOSE_MODE" -v total_dur="$total_duration" '
function format_time(epoch) { return strftime("%Y-%m-%d %H:%M:%S", epoch) }
BEGIN {
    months_str = "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec"; split(months_str, months_arr, " ")
    for (i in months_arr) { month_map[months_arr[i]] = sprintf("%02d", i) }
}
{
    if ($4 ~ /\[[0-9]{2}\/[A-Z][a-z]{2}\/[0-9]{4}:/) {
        ts_str = $4; gsub(/\[/, "", ts_str)
        year = substr(ts_str, 8, 4); month_abbr = substr(ts_str, 4, 3); month_num = month_map[month_abbr]
        day = substr(ts_str, 1, 2); hour = substr(ts_str, 13, 2); min = substr(ts_str, 16, 2); sec = substr(ts_str, 19, 2)
        mktime_str = year " " month_num " " day " " hour " " min " " sec
        current_epoch = mktime(mktime_str)
        bucket = int((current_epoch - start) / interval)
        if (bucket >= num_intervals) { bucket = num_intervals - 1 }
        
        if ($7 ~ /submit\/job/) {
            if (verbose) { print "DEBUG (Submit):   Line " FNR ": Found submission. Adding count: " $NF > "/dev/stderr" }
            submitted_count[bucket] += $NF
            next
        }
        
        runtime = $7; sub(/.*\//, "", runtime)
        if (runtime == "script_api" || runtime == "script_browser") {
            if (verbose) { print "DEBUG (Complete): Line " FNR ": Found completion for \"" runtime "\". Status: " $NF > "/dev/stderr" }
            status = $NF
            count[bucket, runtime, status]++
            runtimes[runtime] = 1
        }
    }
}
END {
    grand_total_submitted = 0; grand_total_found = 0; grand_total_not_found = 0
    
    for (b = 0; b < num_intervals; b++) {
        interval_start = start + (b * interval); interval_end = interval_start + interval - 1
        if (b == num_intervals - 1) { interval_end = start + total_dur } # Ensure last interval ends at the true end time
        print "--- 📊 Time Interval " (b+1) " of " num_intervals " (" format_time(interval_start) " to " format_time(interval_end) ") ---"
        interval_submitted = submitted_count[b] + 0
        grand_total_submitted += interval_submitted
        has_data = 0
        for (rt in runtimes) {
            found = count[b, rt, 1] + 0; not_found = count[b, rt, 0] + 0; total = found + not_found
            grand_total_found += found; grand_total_not_found += not_found
            if (total > 0) {
                has_data = 1
                found_pct = sprintf("%.2f", (found / total) * 100); not_found_pct = sprintf("%.2f", (not_found / total) * 100)
                print "   - Runtime: " rt
                print "     Jobs Found (1):      " found " (" found_pct "%)"
                print "     Jobs Not Found (0):  " not_found " (" not_found_pct "%)"
            }
        }
        if (!has_data) { print "   (No job completion data in this interval)" }
        
        rate = 0
        if (interval > 0) { rate = (interval_submitted / interval) * 60 }
        print "   Jobs Submitted in Interval: " interval_submitted
        print "   Submission Rate:            " sprintf("%.2f jobs/min", rate)
        print "----------------------------------------------------------------------"
    }
    
    print "\n======================================================================"
    print "✅ OVERALL SUMMARY"
    print "======================================================================"
    
    overall_rate = 0
    if (total_dur > 0) { overall_rate = (grand_total_submitted / total_dur) * 60 }
    print "Total Jobs Submitted: " grand_total_submitted " (" sprintf("%.2f jobs/min avg", overall_rate) ")"
    print "Total Jobs Found:     " grand_total_found
    print "Total Jobs Not Found: " grand_total_not_found
    
    if (grand_total_submitted == grand_total_found) {
        print "Status:               ✅ OK (All submitted jobs were accounted for)"
    } else {
        discrepancy = grand_total_submitted - grand_total_found
        loss_pct_str = "N/A"
        if (grand_total_submitted > 0) {
            loss_pct = (discrepancy / grand_total_submitted) * 100
            loss_pct_str = sprintf("%.2f%%", loss_pct)
        }
        print "Status:               ❌ MISMATCH"
        print "Discrepancy:          " discrepancy " jobs (" loss_pct_str " discrepancy)"
    }
    print "======================================================================"
}
' "$LOG_FILE"
