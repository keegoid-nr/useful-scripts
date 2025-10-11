# GitHub PR Tracker

![Language](https://img.shields.io/badge/language-Python-3776AB.svg)

A Python script to track the status (open, merged, unmerged) and size (lines changed) of pull requests for a specific group of authors in a public GitHub repository. It provides key metrics to help measure contribution activity over time.

## Features

* **Custom Timeframe**: Track open and closed PRs within a user-defined timeframe (e.g., the last 6 months).
* **Targeted Author List**: Filter contributions by a specific list of authors managed in a simple plain text file (`authors.txt`).
* **Key Metrics**: Display counts of merged, unmerged, and open PRs per author, including total lines changed.
* **Robust API Handling**: Gracefully handles GitHub API limitations like rate limits and search result caps.

## Setup

### Prerequisites

* Python 3.11+
* A [GitHub Personal Access Token](https://github.com/settings/tokens) with `public_repo` scope.

### Installation

1. **Create Project Files**: Place the script (`pr-tracker.py`) in a new directory.
2. **Create `requirements.txt`**: In the same directory, create a `requirements.txt` file with the following content:

    ```txt
    httpx
    tqdm
    python-dateutil
    ```

3. **Install Dependencies**: Open your terminal in the project directory and run:

    ```sh
    pip install -r requirements.txt
    ```

## Configuration

1. **Set GitHub Token**
    Create a system environment variable named `GITHUB_TOKEN` and set its value to your GitHub Personal Access Token. This keeps your token secure and out of the source code.

    **Note on SSO**: Some organizations, including New Relic, require you to authorize your Personal Access Token for use with SSO. After creating your token, you may need to click "Configure SSO" or "Authorize" next to its name on the [tokens page](https://github.com/settings/tokens) to grant it access.

2. **Define Authors**
    Create a plain text file named `authors.txt` in the project directory. Add the GitHub usernames you want to track, with one username per line:

    ```text
    github-username-1
    github-username-2
    another-user
    ```

3. **Change Target Repository (Optional)**
    The script is hardcoded to target the `newrelic/docs-website` repository. To change this, edit the `REPO_OWNER` and `REPO_NAME` variables at the top of the `pr-tracker.py` script.

## Usage

1. Run the script from your terminal:

    ```sh
    python pr-tracker.py
    ```

2. When prompted, enter the number of months you wish to search back and press Enter.

    ```txt
    Enter the number of months to search: 12
    ```

### Example Output

```txt
$ python pr-tracker.py
Enter the number of months to search: 6

Fetching Closed PRs: 100%|██████████████████| 7/7 [00:15<00:00,  2.15s/it]
Fetching Open PRs  : 100%|██████████████████| 7/7 [00:15<00:00,  2.15s/it]
Analyzing PR Details: 100%|█████████████████| 125/125 [01:02<00:00, 2.01it/s]

--- PR Analysis ---
Showing results for PRs created or closed since 2025-04-10
Target Authors: github-username-1, github-username-2, another-user
Total Merged PRs by target authors: 105
Unique Contributors: 3

--- PRs per Author ---
github-username-2: 58 merged, 5 unmerged, 3 open (14551 total lines: +10250, -4301)
another-user: 15 merged, 1 unmerged, 1 open (5798 total lines: +4500, -1298)
github-username-1: 32 merged, 12 unmerged, 0 open (1112 total lines: +812, -300)

--- Merged PRs per Month ---
2025-05: 18
2025-06: 22
2025-07: 19
2025-08: 25
2025-09: 16
2025-10: 5
```

## License

This project is licensed under the Apache 2.0 License.
