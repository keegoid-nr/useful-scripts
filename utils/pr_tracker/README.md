# GitHub PR Tracker

![Language](https://img.shields.io/badge/language-Python-3776AB.svg)

A Python script to track merged pull requests for a specific group of authors in a public GitHub repository. It provides key metrics to help measure contributions and documentation improvements over time.

## Features

* **Custom Timeframe**: Track merged PRs within a user-defined timeframe (e.g., the last 6 months).
* **Targeted Author List**: Filter contributions by a specific list of authors managed in a simple `authors.csv` file.
* **Key Metrics**: Display total contributions, unique contributors, PRs per author, and PRs per month.
* **Robust API Handling**: Gracefully handles GitHub API limitations like rate limits and search result caps.

## Setup

### Prerequisites

* Python 3.11+
* A [GitHub Personal Access Token](https://github.com/settings/tokens) with `public_repo` scope.

### Installation

1. **Create Project Files**: Place the script (`pr_tracker.py`) in a new directory.
2. **Create `requirements.txt`**: In the same directory, create a `requirements.txt` file with the following content:

    ```txt
    httpx
    tqdm
    python-dateutil
    ```

3. **Install Dependencies**: Open your terminal in the project directory and run:

    ```bash
    pip install -r requirements.txt
    ```

## Configuration

1. **Set GitHub Token**
    Create a system environment variable named `GITHUB_TOKEN` and set its value to your GitHub Personal Access Token. This keeps your token secure and out of the source code.

    **Note on SSO**: Some organizations, including New Relic, require you to authorize your Personal Access Token for use with SSO. After creating your token, you may need to click "Configure SSO" or "Authorize" next to its name on the [tokens page](https://github.com/settings/tokens) to grant it access.

2. **Define Authors**
    Create a file named `authors.csv` in the project directory. It must contain a single column header named `username`. Add the GitHub usernames of the engineers you want to track, one per line:

    ```csv
    username
    github-username-1
    github-username-2
    another-user
    ```

3. **Change Target Repository (Optional)**
    The script is hardcoded to target the `newrelic/docs-website` repository. To change this, edit the `REPO_OWNER` and `REPO_NAME` variables at the top of the `pr_tracker.py` script.

## Usage

1. Run the script from your terminal:

    ```bash
    python pr_tracker.py
    ```

2. When prompted, enter the number of months you wish to search back and press Enter.

    ```bash
    Enter the number of months to search: 6
    ```

### Example Output

```bash
$ python pr_tracker.py
Enter the number of months to search: 6

Processing Months: 100%|██████████████████| 7/7 [00:15<00:00,  2.15s/it]

--- PR Analysis ---
Showing results since 2025-04-09
Target Authors: github-username-1, github-username-2, another-user
Total Merged PRs by target authors: 105
Unique Contributors: 3

--- PRs per Author ---
github-username-2: 58
github-username-1: 32
another-user: 15

--- Merged PRs per Month ---
2025-05: 18
2025-06: 22
2025-07: 19
2025-08: 25
2025-09: 16
2025-10: 5
```
