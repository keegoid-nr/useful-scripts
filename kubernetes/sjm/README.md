# SJM Scripts

![Language](https://img.shields.io/badge/language-Shell%20Script-green.svg)

This directory contains scripts for analyzing and manipulating logs related to the Synthetics Job Manager (SJM).

---

## `parking-lot-jobs.sh`

This script helps assess if jobs are making their way through the job manager's "parking lot." It does this by comparing the number of **jobs put into the lot**, **jobs retrieved by runtime pods**, **jobs that time out**, and **jobs submitted to New Relic**. This is useful for diagnosing scenarios where jobs are submitted but never completed.

### Features

- **Time-Series Analysis**: Splits the log file's duration into a configurable number of intervals for granular analysis.
- **Multi-Format Log Parsing**: Handles multiple log line and timestamp formats in a single pass.
- **Full Lifecycle Tracking**: Monitors four types of events:
    1. **Parking Lot Entry**: Counts `Putting job...` informational log lines.
    2. **Parking Lot Timeout**: Counts `A job was not removed...` error log lines.
    3. **Job Retrieval**: Tracks `GET` requests from runtime pods for `script_api` and `script_browser` jobs.
    4. **Job Submission**: Tracks `POST` requests to `/api/v1/submit/job` where results are sent to New Relic.
- **Rate Calculation**: Calculates the jobs submitted per minute for each interval and as an overall average.
- **Detailed Summaries**: Provides both per-interval breakdowns and a final, overall summary of the entire log file.
- **Verbose Debug Mode**: Includes a `--verbose` flag to print detailed, line-by-line processing information for easy verification.

### Prerequisites

This script requires **GNU Awk** (`gawk`) for its advanced time-handling functions. The script will automatically check if `gawk` is installed and provide instructions if it's missing.

- **macOS (with Homebrew)**: `brew install gawk`
- **Debian/Ubuntu**: `sudo apt-get install gawk`

### Usage

```bash
./parking-lot-jobs.sh <path_to_log_file> [number_of_intervals] [--verbose]
```

- **`<path_to_log_file>`**: The SJM log file to analyze.
- **`[number_of_intervals]`**: Optional. The number of time intervals to split the analysis into. Defaults to 5.
- **`--verbose`**: Optional. Enables verbose logging to show line-by-line processing details.

### Understanding the Logic

The script uses a hybrid approach to determine the outcome of each log line:

- **Job Put into Parking Lot**: Counted when a line matches the pattern `"Putting job .* into the parking lot"`.
- **Job Timed Out**: Counted when a line matches the pattern `"A job was not removed from the parkinglot"`.
- **Job Submitted to New Relic**: A `POST` to `/api/v1/submit/job` is counted if it has a **`202 Accepted`** response code. The script sums the number at the end of these lines for the total count.
- **Job Retrieved (Found)**: A `GET` request for `script_api` or `script_browser` is counted as "Found" if its **response size** (the final number on the line) is **greater than 0**.
- **Job Not Retrieved (Not Found)**: A `GET` request is counted as "Not Found" if its **response size** is **exactly 0**.

The "Discrepancy" in the final summary is calculated as `(Jobs Put into Lot) - (Jobs Retrieved + Jobs Timed Out)`.

---

## `remove-ping-logs.sh`

This script filters an SJM log file to remove "ping" or "(SIMPLE)" jobs, which are often noisy and not relevant for analysis. It identifies the GUIDs of these simple jobs and then removes all log lines associated with those GUIDs.

### Usage

```bash
./remove-ping-logs.sh [input_log_file] [output_log_file]
```

- **`[input_log_file]`**: Optional. The log file to filter. Defaults to `your_log_file.log`.
- **`[output_log_file]`**: Optional. The name of the filtered output file. Defaults to `filtered_log.log`.
