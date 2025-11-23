# Clean Data

This directory contains utility scripts for cleaning data.

## Data Processing Workflow

The `process_data.py` script orchestrates the entire data cleaning pipeline, converting text files to CSV and then sanitizing them.

**Usage:**

```bash
python3 process_data.py <input_txt_directory>
```

**Workflow:**

1. **Convert**: Runs `convert.py` to convert `.txt` files in the input directory to `.csv` files in a sibling `csv` directory.
2. **Sanitize**: Runs `sanitize.py` to redact sensitive data from the `.csv` files, saving them to a sibling `sanitized_csv` directory.

**Directory Structure:**

```text
parent_dir/
├── txt/            # Input (Raw Text Files)
├── csv/            # Intermediate (Converted CSVs)
└── sanitized_csv/  # Output (Redacted CSVs)
```

## `convert.py`

**Purpose:**
Parses text files containing HTML content (often from email dumps) and converts them into a CSV format suitable for spreadsheets. It cleans the HTML body to plain text.

**Usage:**

```bash
python3 convert.py <input_txt_directory> [output_csv_directory]
```

**Arguments:**

- `<input_txt_directory>`: Path to the directory containing `.txt` files to process.
- `[output_csv_directory]`: (Optional) Path to the directory where CSV files will be saved. If omitted, a `csv` or `processed_csv` directory will be created.

**Input File Format:**
The script expects text files with a specific structure:

```text
Header1
Header2
...
<blank line>
Value1_Row1
Value2_Row1
...
Value1_Row2
Value2_Row2
...
```

The script pairs headers with values. It supports multiple records (rows) per file, as long as the values are stacked sequentially and the total number of values is a multiple of the number of headers.

**Dependencies:**

- `pandas`
- `beautifulsoup4`

## Sanitize

A production-grade tool to redact sensitive data (PII, Secrets, Credit Cards) from CSV files using Python and Pandas.

### Features

- **High Performance**: Uses vectorized operations for fast processing of large files.
- **Secure**:
  - Redacts API Keys (Google, Stripe, AWS, generic).
  - Redacts PII (Emails, Phones, SSNs).
  - Redacts Credit Cards (with Luhn algorithm validation to prevent false positives).
- **Smart**:
  - Preserves "New Relic" product names while scrubbing other competitors.
  - Avoids aggressive false positives (e.g., won't redact "San Francisco" as a name).

### Installation

This tool requires Python 3 and the `pandas` and `numpy` libraries.

#### 1. Create a Virtual Environment (Recommended)

To avoid conflicts with system packages:

```bash
python3 -m venv .venv
source .venv/bin/activate
```

#### 2. Install Dependencies

```bash
pip install pandas numpy
```

### Usage

Run the script by pointing it to a directory containing CSV files. It will recursively scan for `.csv` files and save redacted versions to a sibling `sanitized_csv` directory by default.

```bash
python3 sanitize.py /path/to/input_directory
```

#### Example

```bash
# Process all CSVs in the 'data' folder
python3 sanitize.py ./data
```

The output will be saved to a sibling `sanitized_csv` directory by default (e.g., `./sanitized_csv/...`). You can override this with `--output_dir`.

#### Redaction Rules

| Category | Patterns Redacted |
|----------|-------------------|
| **Network** | IPv4, IPv6, MAC Addresses, Container IDs |
| **PII** | Emails, Phone Numbers, SSNs |
| **Financial** | Credit Cards (Luhn Validated), Stripe Keys |
| **Secrets** | Google API Keys, AWS Keys, Generic `key=value` secrets |
| **Business** | Common tech company names except for "New Relic" |
