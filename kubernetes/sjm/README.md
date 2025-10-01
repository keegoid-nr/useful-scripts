# SJM Job Throughput Analyzer

![Language](https://img.shields.io/badge/language-Shell%20Script-green.svg)

This directory contains a script for analyzing Synthetics Job Manager (SJM) logs to calculate job throughput and track the full lifecycle of heavyweight jobs that use the "parking lot."

---

## `parking-lot-jobs.sh`

This script provides a detailed analysis of the SJM job funnel to measure the throughput of jobs successfully processed by the parking lot. It tracks and groups the lifecycle stages for both heavyweight and lightweight jobs to identify potential bottlenecks or discrepancies.

### Features

- **Grouped Funnel Tracking**: The output is organized into clear "Heavyweight" and "Lightweight" sections to easily compare the lifecycle of different job types.
- **Parking Lot Focus**: Precisely measures the flow of heavyweight jobs by comparing how many are put into the lot versus how many are successfully retrieved.
- **Throughput Calculation**: Measures the rate of successfully retrieved heavyweight jobs (`200 OK`) in jobs per minute.
- **Time-Series Analysis**: Splits the log file's duration into a configurable number of intervals for granular analysis.
- **Multi-Format Log Parsing**: Handles multiple log line and timestamp formats in a single pass.
- **Verbose Debug Mode**: Includes a `--verbose` flag for detailed, line-by-line processing information.

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
- **`--verbose`**: Optional. Enables verbose logging.

### Understanding the Logic

The script identifies the stage of a job's lifecycle based on distinct patterns in the log file:

| Stage                         | Log Line Indicator                                                                                                  |
|-------------------------------|---------------------------------------------------------------------------------------------------------------------|
| **Heavyweight Job Staged**    | Contains `"is being staged for execution"` and Type: `[SCRIPT_API]`, `[SCRIPT_BROWSER]`, or `[BROWSER]` |
| **Lightweight Job Staged**    | Contains `"is being staged for execution"` and Type: `[SIMPLE]`                                                     |
| **Put into Lot** (Input)      | Contains `"Putting job .* into the parking lot"`                                                                    |
| **Retrieved** (Throughput)    | A `GET` request with HTTP response code **`200 OK`**                                                                |
| **Not Retrieved (Empty)**     | A `GET` request with HTTP response code **`204 No Content`**                                                        |
| **Lightweight Job Submitted** | Contains `"(SIMPLE) to Processor"`                                                                                  |
| **Heavyweight Job Submitted** | Calculated as `(Total POST 202 Submissions) - (Total Lightweight Jobs)`                                             |

The primary **Discrepancy** is calculated as `(Jobs Put into Lot) - (Jobs Retrieved)`

---

## `remove-ping-logs.sh`

This script filters an SJM log file to remove "ping" or "(SIMPLE)" jobs, which are often noisy and not relevant for analysis. It identifies the GUIDs of these simple jobs and then removes all log lines associated with those GUIDs.

### Usage

```bash
./remove-ping-logs.sh [input_log_file] [output_log_file]
```

- **`[input_log_file]`**: Optional. The log file to filter. Defaults to `your_log_file.log`.
- **`[output_log_file]`**: Optional. The name of the filtered output file. Defaults to `filtered_log.log`.
