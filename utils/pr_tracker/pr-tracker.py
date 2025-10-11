"""
GitHub PR Tracker

This script fetches open and closed pull requests from a specified GitHub
repository for a defined list of authors. It calculates key metrics over a
user-defined time period (in months) and prints a summary to the console.

Key metrics include:
- A breakdown of merged, unmerged, and open PRs per author.
- A breakdown of lines added/deleted per author.
- A breakdown of merged PRs per month.
- Total merged PRs and unique contributors.

Author : Keegan Mullaney
Company: New Relic
Email  : kmullaney@newrelic.com
Website: github.com/keegoid-nr/useful-scripts
License: Apache License 2.0
"""

import httpx
import os
import time
from datetime import datetime
from dateutil.relativedelta import relativedelta
from collections import defaultdict
from tqdm import tqdm

# --- CONFIGURATION ---
GITHUB_TOKEN = os.getenv("GITHUB_TOKEN")
REPO_OWNER = "newrelic"
REPO_NAME = "docs-website"

# Load the list of authors from a plain text file.
AUTHORS = []
try:
    with open('authors.txt', mode='r', encoding='utf-8') as f:
        # Read all lines, strip leading/trailing whitespace, and filter out empty lines.
        AUTHORS = [line.strip() for line in f if line.strip()]
except FileNotFoundError:
    print("Error: 'authors.txt' not found. Please create it with one username per line.")
except Exception as e:
    print(f"An error occurred while reading 'authors.txt': {e}")


def create_date_ranges(start_date, end_date):
    """
    Generates a list of monthly date range tuples.
    """
    ranges = []
    current_date = start_date
    while current_date < end_date:
        next_date = current_date + relativedelta(months=1)
        range_end = min(next_date, end_date)
        ranges.append((current_date.strftime('%Y-%m-%d'), range_end.strftime('%Y-%m-%d')))
        current_date = next_date
    return ranges

def fetch_all_prs(owner, repo, token, start_date):
    """
    Fetches all relevant PRs (open and closed) from the GitHub Search API.
    """
    all_prs = []
    date_ranges = create_date_ranges(start_date, datetime.now())
    headers = {"Authorization": f"token {token}"}

    with httpx.Client() as client:
        # Search for CLOSED PRs (merged and unmerged)
        for start, end in tqdm(date_ranges, desc="Fetching Closed PRs"):
            date_query = f"closed:{start}..{end}"
            search_query = f"repo:{owner}/{repo} is:pr is:closed {date_query}"
            page = 1
            while True:
                url = f"https://api.github.com/search/issues?q={search_query}&per_page=100&page={page}"
                response = client.get(url, headers=headers)
                response.raise_for_status()
                data = response.json()
                items = data.get('items', [])
                if not items:
                    break
                all_prs.extend(items)
                if len(items) < 100:
                    break
                page += 1
            time.sleep(2)

        # Search for OPEN PRs
        for start, end in tqdm(date_ranges, desc="Fetching Open PRs  "):
            date_query = f"created:{start}..{end}"
            search_query = f"repo:{owner}/{repo} is:pr is:open {date_query}"
            page = 1
            while True:
                url = f"https://api.github.com/search/issues?q={search_query}&per_page=100&page={page}"
                response = client.get(url, headers=headers)
                response.raise_for_status()
                data = response.json()
                items = data.get('items', [])
                if not items:
                    break
                all_prs.extend(items)
                if len(items) < 100:
                    break
                page += 1
            time.sleep(2)

    return all_prs

def analyze_prs(prs, authors, token):
    """
    Processes a list of PRs to calculate and summarize key metrics,
    including fetching detailed data for line changes.
    """
    filtered_prs = [pr for pr in prs if pr["user"]["login"] in authors]

    prs_per_author = defaultdict(lambda: {
        "merged": 0, "unmerged": 0, "open": 0,
        "additions": 0, "deletions": 0
    })
    merged_prs_per_month = defaultdict(int)
    total_merged = 0

    headers = {"Authorization": f"token {token}"}
    with httpx.Client() as client:
        # This loop makes an API call for EACH PR to get detailed stats.
        for pr in tqdm(filtered_prs, desc="Analyzing PR Details"):
            author_login = pr["user"]["login"]

            # Fetch the full PR object to get additions and deletions
            pr_details_url = pr["pull_request"]["url"]
            response = client.get(pr_details_url, headers=headers)
            try:
                response.raise_for_status()
                details = response.json()
                prs_per_author[author_login]["additions"] += details.get("additions", 0)
                prs_per_author[author_login]["deletions"] += details.get("deletions", 0)
            except httpx.HTTPStatusError:
                print(f"\nWarning: Could not fetch details for PR: {pr['html_url']}")
                continue

            # Categorize each PR into one of the three states.
            if pr["pull_request"].get("merged_at"):
                prs_per_author[author_login]["merged"] += 1
                merged_date = pr["pull_request"]["merged_at"][:7]
                merged_prs_per_month[merged_date] += 1
                total_merged += 1
            elif pr["state"] == "open":
                prs_per_author[author_login]["open"] += 1
            else: # PR is closed but not merged
                prs_per_author[author_login]["unmerged"] += 1

    unique_contributors = set(prs_per_author.keys())
    # Sort authors by their total lines changed (additions + deletions).
    sorted_authors = sorted(
        prs_per_author.items(),
        key=lambda item: item[1]['additions'] + item[1]['deletions'],
        reverse=True
    )

    return {
        "total_merged_prs": total_merged,
        "unique_contributors": len(unique_contributors),
        "prs_per_month": dict(sorted(merged_prs_per_month.items())),
        "prs_per_author": dict(sorted_authors)
    }

def main():
    """
    Main function to orchestrate the script's execution.
    """
    if not GITHUB_TOKEN or not AUTHORS:
        print("Error: GITHUB_TOKEN must be set and the authors list from authors.txt cannot be empty.")
        return

    while True:
        try:
            months_to_search = int(input("Enter the number of months to search: "))
            if months_to_search > 0:
                break
            else:
                print("Please enter a positive number.")
        except ValueError:
            print("Invalid input. Please enter a whole number.")

    start_date = datetime.now() - relativedelta(months=months_to_search)

    try:
        prs = fetch_all_prs(REPO_OWNER, REPO_NAME, GITHUB_TOKEN, start_date)
        analysis = analyze_prs(prs, AUTHORS, GITHUB_TOKEN)

        print("\n--- PR Analysis ---")
        print(f"Showing results for PRs created or closed since {start_date.strftime('%Y-%m-%d')}")
        print(f"Target Authors: {', '.join(AUTHORS)}")
        print(f"Total Merged PRs by target authors: {analysis['total_merged_prs']}")
        print(f"Unique Contributors: {analysis['unique_contributors']}")

        print("\n--- PRs per Author ---")
        for author, counts in analysis["prs_per_author"].items():
            additions = counts['additions']
            deletions = counts['deletions']
            total_lines = additions + deletions
            print(f"{author}: {counts['merged']} merged, {counts['unmerged']} unmerged, {counts['open']} open ({total_lines} total lines: +{additions}, -{deletions})")

        print("\n--- Merged PRs per Month ---")
        for month, count in analysis["prs_per_month"].items():
            print(f"{month}: {count}")

    except httpx.HTTPStatusError as e:
        print(f"Error fetching data from GitHub: {e.response.text}")
    except Exception as e:
        print(f"An unexpected error occurred: {e}")

if __name__ == "__main__":
    # Script entry point
    main()
