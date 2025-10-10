# New Relic Synthetics Monitor Manager

![Language](https://img.shields.io/badge/language-Python-3776AB.svg)

A command-line Python script for creating, enabling, disabling, deleting, and checking the results of New Relic Synthetics monitors in bulk using the NerdGraph API.

This script is designed to simplify the management of synthetic monitors by tagging them and allowing for bulk actions based on type and status.

## Features

* **Create** multiple monitors of different types (`SIMPLE`, `BROWSER`, `SCRIPT_BROWSER`, `SCRIPT_API`).
* **Enable**, **Disable**, or **Delete** monitors in bulk.
* **Check Results**: Queries and displays a summary of `SyntheticCheck` results for the tagged monitors, calculating jobs per minute and providing a throughput summary.
* **Tagging:** Automatically tags all created monitors with `ManagedBy:BulkScript` for easy identification.
* **Interactive Prompts:** User-friendly menus for selecting actions, quantity, and period.
* **Granular Selection:** Filter by monitor type and select specific monitors from a numbered list for management actions.
* **Colored & Aligned Output:** Clean, readable terminal output with colors for status and aligned columns.

## 1. Prerequisites

Before using this script, you will need:

* **Python 3.11+** installed.
* A **New Relic User API Key**. You can generate one from **Your Profile > API Keys**.
* Your **New Relic Account ID**.
* The **GUID of a New Relic Private Location** where the monitors will run.

## 2. Setup

### Step 1: Set Environment Variables

This script reads your credentials from environment variables to keep them secure. Set the following variables in your terminal session before running the script.

**For macOS or Linux:**

```bash
export NEW_RELIC_API_KEY="YOUR_API_KEY_HERE"
export NEW_RELIC_ACCOUNT_ID="YOUR_ACCOUNT_ID_HERE"
export NEW_RELIC_PRIVATE_LOCATION_GUID="YOUR_PRIVATE_LOCATION_GUID_HERE"
```

**For Windows (PowerShell):**

```bash
$env:NEW_RELIC_API_KEY="YOUR_API_KEY_HERE"
$env:NEW_RELIC_ACCOUNT_ID="YOUR_ACCOUNT_ID_HERE"
$env:NEW_RELIC_PRIVATE_LOCATION_GUID="YOUR_PRIVATE_LOCATION_GUID_HERE"
```

### Step 2: Install Required Python Package

The script uses the `httpx` library to make API requests. Install it using pip:

```bash
pip install httpx
```

### Step 3: Create `monitors.json`

Create a file named `monitors.json` in the same directory as the script. This file defines the base names and URLs for the monitors you want to create. The script will randomly pick from this list.

**Example `monitors.json`:**

```json
[
 { "baseName": "NR Home Page", "url": "https://newrelic.com/" },
 { "baseName": "NR Platform", "url": "https://newrelic.com/platform" },
 { "baseName": "NR Pricing", "url": "https://newrelic.com/pricing" },
 { "baseName": "NR Docs", "url": "https://docs.newrelic.com/" }
]
```

## 3. Usage

Run the script from your terminal:

```bash
python3 manage-monitors.py [-t/--types TYPE [TYPE ...]]
```

The script will present a main menu of actions. The optional `-t`/`--types` flag can be used to filter the monitors that the chosen action will apply to.

### Main Actions

1. **Create monitors:** Uses the `--types` flag to determine which types to create (defaults to ALL if the flag is omitted), then interactively prompts for quantity and monitoring period.
2. **Enable monitors:** Finds all `DISABLED` monitors with the `ManagedBy:BulkScript` tag and prompts you to select which ones to enable.
3. **Disable monitors:** Finds all `ENABLED` monitors with the tag and prompts you to select which ones to disable.
4. **Delete monitors:** Finds all monitors with the tag and prompts you to select which ones to delete.
5. **Check Results**: Queries NRDB for `SyntheticCheck` events from the tagged monitors. It interactively prompts for a time window and displays a summary table of jobs per minute, faceted by result and type, along with a throughput summary.

### Command-Line Examples

#### **Creating Monitors**

* **Create (Default Behavior):**
  If run without flags, the script will default to creating all monitor types.

  ```bash
  python3 manage-monitors.py
  # Choose '1'. It will then prompt for quantity and period for all types
  ```

* **Create Specific Types:**
  Use the `-t` or `--types` flag to specify which types to create.

  ```bash
  # Using the long flag
  python3 manage-monitors.py --types SIMPLE BROWSER
  # Choose '1'. It will then prompt for quantity and period for only SIMPLE and BROWSER

  # Using the short flag is also valid
  python3 manage-monitors.py -t SCRIPT_API
  ```

#### **Managing Monitors**

* **Manage All Monitors:**

  ```bash
  python3 manage-monitors.py
  # Choose '2', '3', or '4'. A full list of relevant monitors will be shown
  ```

* **Manage Only Scripted Monitors:**

  ```bash
  python3 manage-monitors.py -t SCRIPT_BROWSER SCRIPT_API
  # Choose '2', '3', or '4'. Only scripted monitors will be listed
  ```

* **Selection Prompt:**
  When managing monitors, you will be prompted to select which ones to act on. You can use ranges, commas, or simply press Enter to select all.

  ```bash
  # Which monitors to act on? (e.g., 1-3, 5, 8 or press Enter for ALL): 1-2,4
  ```

#### **Checking Monitor Results**

* **Check results for all monitor types:**

  ```bash
  python3 manage-monitors.py
  # Choose '5'. It will then prompt for the number of minutes to query
  ```

* **Check results for specific monitor types:**

  ```bash
  python3 manage-monitors.py -t SCRIPT_API SCRIPT_BROWSER
  # Choose '5'. It will show results only for the specified monitor types
  ```

## License

This project is licensed under the Apache 2.0 License. See the [LICENSE](/LICENSE) file for details.
