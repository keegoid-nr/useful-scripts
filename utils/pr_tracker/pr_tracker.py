# A Python script to track merged pull requests
#
# Author : Keegan Mullaney
# Company: New Relic
# Email  : kmullaney@newrelic.com
# Website: github.com/keegoid-nr/useful-scripts
# License: Apache License 2.0

import httpx
import os
import time
import csv  # Import the csv library
from datetime import datetime
from dateutil.relativedelta import relativedelta
from collections import defaultdict, Counter
from tqdm import tqdm

# --- CONFIGURATION ---
GITHUB_TOKEN = os.getenv("GITHUB_TOKEN")
REPO_OWNER = "newrelic"
REPO_NAME = "docs-website"

# --- NEW: Load authors from the CSV file ---
AUTHORS = []
try:
    with open('authors.csv', mode='r', encoding='utf-8') as f:
        csv_reader = csv.DictReader(f)
        for row in csv_reader:
            # Check if the 'username' column exists and is not empty
            if row.get('username'):
                AUTHORS.append(row['username'])
except FileNotFoundError:
    print("Error: 'authors.csv' not found. Please create it with a 'username' header.")
except Exception as e:
    print(f"An error occurred while reading 'authors.csv': {e}")


# --- SCRIPT (The rest of the script is unchanged) ---

def create_date_ranges(start_date, end_date):
    # ...
    ranges = []
    current_date = start_date
    while current_date < end_date:
        next_date = current_date + relativedelta(months=1)
        range_end = min(next_date, end_date)
        ranges.append((current_date.strftime('%Y-%m-%d'), range_end.strftime('%Y-%m-%d')))
        current_date = next_date
    return ranges

def get_merged_prs(owner, repo, token, start_date):
    # ...
    all_prs = []
    date_ranges = create_date_ranges(start_date, datetime.now())

    headers = {"Authorization": f"token {token}"}
    with httpx.Client() as client:
        for start, end in tqdm(date_ranges, desc="Processing Months"):
            date_query = f"merged:{start}..{end}"
            search_query = f"repo:{owner}/{repo} is:pr is:merged {date_query}"

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

def analyze_prs(prs, authors):
    # ...
    filtered_prs = [pr for pr in prs if pr["user"]["login"] in authors]
    unique_contributors = set(pr["user"]["login"] for pr in filtered_prs)
    prs_per_month = defaultdict(int)

    for pr in filtered_prs:
        merged_date = pr["pull_request"]["merged_at"][:7]
        prs_per_month[merged_date] += 1

    author_logins = [pr["user"]["login"] for pr in filtered_prs]
    prs_per_author = Counter(author_logins)

    return {
        "total_merged_prs": len(filtered_prs),
        "unique_contributors": len(unique_contributors),
        "prs_per_month": dict(sorted(prs_per_month.items())),
        "prs_per_author": dict(prs_per_author.most_common())
    }

def main():
    # ...
    if not GITHUB_TOKEN or not AUTHORS:
        print("Error: GITHUB_TOKEN must be set and the authors list from authors.csv cannot be empty.")
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
        prs = get_merged_prs(REPO_OWNER, REPO_NAME, GITHUB_TOKEN, start_date)
        analysis = analyze_prs(prs, AUTHORS)

        print("\n--- PR Analysis ---")
        print(f"Showing results since {start_date.strftime('%Y-%m-%d')}")
        print(f"Target Authors: {', '.join(AUTHORS)}")
        print(f"Total Merged PRs by target authors: {analysis['total_merged_prs']}")
        print(f"Unique Contributors: {analysis['unique_contributors']}")

        print("\n--- PRs per Author ---")
        for author, count in analysis["prs_per_author"].items():
            print(f"{author}: {count}")

        print("\n--- Merged PRs per Month ---")
        for month, count in analysis["prs_per_month"].items():
            print(f"{month}: {count}")

    except httpx.HTTPStatusError as e:
        print(f"Error fetching data from GitHub: {e.response.text}")
    except Exception as e:
        print(f"An unexpected error occurred: {e}")

if __name__ == "__main__":
    main()
