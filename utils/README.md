# Utilities

This directory contains utility scripts for various purposes.

## `clean-data`

Contains scripts for cleaning data.

- `txt_to_csv_processor.py`
- `redact-data.py`

## `atlassian-dev`

Contains a script for Atlassian development.

- `oath2-request-url.sh`

## `pr-tracker`

Contains a script for tracking pull requests.

- `pr-tracker.py`

## `decode-html.sh`

**Purpose:**
A simple Bash script to decode common HTML entities (like `&quot;`, `&lt;`, `&amp;`) back to their character representation.

**Usage:**

Read from a file:

```bash
./decode-html.sh filename.txt
```

Read from standard input (pipe):

```bash
echo "&lt;html&gt;" | ./decode-html.sh
```

Read from and write to clipboard (macOS/Linux):

```bash
./decode-html.sh --clipboard
# OR
./decode-html.sh -c
```

**Requirements:**

- Standard Unix tools: `sed`, `cat`
- For clipboard support: `pbpaste`/`pbcopy` (macOS), `xclip`, or `xsel` (Linux)
