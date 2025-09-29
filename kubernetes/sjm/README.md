# SJM Scripts

![Language](https://img.shields.io/badge/language-Shell%20Script-green.svg)

This directory contains scripts for analyzing and manipulating logs related to the Synthetics Job Manager (SJM).

---

## `parking-lot-jobs.sh`

This script helps assess if jobs are making their way through the job manager's "parking lot." It does this by comparing **how many jobs are submitted to New Relic** versus **how many are successfully retrieved by runtime pod GET requests**.

### Features

- **Time-Series Analysis**: Splits the log file's duration into a configurable number of intervals for granular analysis.
- **Hybrid Timestamp Parsing**: Determines the log's total duration from `YYYY-MM-DD HH:MM:SS` timestamps while parsing job-specific lines with a different format.
- **Submission & Completion Tracking**: Monitors two types of events:
    1. **Job Submissions**: Tracks `POST` requests to `/api/v1/submit/job` where results are sent to New Relic.
    2. **Job Completions**: Tracks `GET` requests from runtime pods for `script_api` and `script_browser` jobs.
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

The script is designed to parse specific lines that follow the structure of the **[Common Log Format](https://en.wikipedia.org/wiki/Common_Log_Format)**. It operates based on the following rules:

- **Job Submitted**: A submission log line (`/api/v1/submit/job`) is counted only if its response size (the final number on the line) is **greater than 0**. The script sums this number to get the total jobs submitted.
- **Job Found**: A completion log line (`script_api` or `script_browser`) is counted as "Found" if its response size (the final number) is **greater than 0**.
- **Job Not Found**: A completion log line is counted as "Not Found" if its response size is **exactly 0**.

The "Discrepancy" in the final summary compares the total number of submitted jobs (sum of response sizes) to the total count of "Found" log lines.

---

## `remove-ping-logs.sh`

This script filters an SJM log file to remove "ping" or "(SIMPLE)" jobs, which are often noisy and not relevant for analysis. It identifies the GUIDs of these simple jobs and then removes all log lines associated with those GUIDs.

### Usage

```bash
./remove-ping-logs.sh [input_log_file] [output_log_file]
```

- **`[input_log_file]`**: Optional. The log file to filter. Defaults to `your_log_file.log`.
- **`[output_log_file]`**: Optional. The name of the filtered output file. Defaults to `filtered_log.log`.
