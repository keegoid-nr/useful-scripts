# SJM Scripts

This directory contains scripts for analyzing and manipulating logs related to the Synthetics Job Manager (SJM).

## `parking-lot-jobs.sh`

This script analyzes SJM logs to calculate job submission rates and identify discrepancies between submitted and completed jobs. It's useful for diagnosing "parking lot" scenarios where jobs are submitted but never picked up.

### Usage

```bash
./parking-lot-jobs.sh <path_to_log_file> [number_of_intervals] [--verbose]
```

*   `<path_to_log_file>`: The SJM log file to analyze.
*   `[number_of_intervals]`: The number of time intervals to split the analysis into. Defaults to 5.
*   `--verbose`: Optional flag to enable verbose logging.

### Output

The script outputs a summary for each time interval, including:

*   The number of jobs submitted.
*   The submission rate in jobs per minute.
*   A breakdown of completed jobs by runtime (`script_api` or `script_browser`) and status (found or not found).

Finally, it provides an overall summary with total submitted jobs, total found jobs, and any discrepancy between the two.

## `remove-ping-logs.sh`

This script filters an SJM log file to remove "ping" or "(SIMPLE)" jobs, which are often noisy and not relevant for analysis. It identifies the GUIDs of these simple jobs and then removes all log lines associated with those GUIDs.

### Usage

```bash
./remove-ping-logs.sh [input_log_file] [output_log_file]
```

*   `[input_log_file]`: The log file to filter. Defaults to `your_log_file.log`.
*   `[output_log_file]`: The name of the filtered output file. Defaults to `filtered_log.log`.
