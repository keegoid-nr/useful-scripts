# ----------------------------------------------
# New Relic Synthetics Monitor Manager
# Manage your monitors via NerdGraph!
#
# Author : Keegan Mullaney
# Company: New Relic
# Email  : kmullaney@newrelic.com
# Website: github.com/keegoid-nr/useful-scripts
# License: Apache License 2.0
# ----------------------------------------------

import httpx
import os
import sys
import time
import json
import argparse
import secrets
import random

# --- Configuration (read from environment variables) ---
API_KEY = os.getenv("NEW_RELIC_API_KEY")
ACCOUNT_ID = os.getenv("NEW_RELIC_ACCOUNT_ID")
PRIVATE_LOCATION_GUID = os.getenv("NEW_RELIC_PRIVATE_LOCATION_GUID")
NERDGRAPH_URL = "https://api.newrelic.com/graphql"

# --- Color Class for Terminal Output ---
class Colors:
    YELLOW = '\033[93m'
    CYAN = '\033[96m'
    GREEN = '\033[92m'
    MAGENTA = '\033[95m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'

# --- Validate that environment variables are set ---
def validate_env_vars(for_creation=False):
    """Validates the necessary environment variables are set."""
    if not API_KEY or not ACCOUNT_ID:
        print("❌ Error: NEW_RELIC_API_KEY and NEW_RELIC_ACCOUNT_ID must be set.")
        sys.exit(1)
    if for_creation and not PRIVATE_LOCATION_GUID:
        print("❌ Error: NEW_RELIC_PRIVATE_LOCATION_GUID must be set for creation.")
        sys.exit(1)

# --- Synthetics Script Templates ---
SYNTHETIC_API_SCRIPT_TPL = (
    "const assert = require('assert');\n"
    "$http.get('%s', (error, response) => {\n"
    "  assert.ok(response.statusCode == 200, 'Expected 200 OK response');\n"
    "});"
)
SYNTHETIC_BROWSER_SCRIPT_TPL = (
    "const { By } = $selenium;\n"
    "const assert = require('assert');\n"
    "$webDriver.get('%s').then(() => {\n"
    "  return $webDriver.findElement(By.tagName('body')).then((element) => {\n"
    "    console.log('Page body found.');\n"
    "    assert.ok(element, 'Page body should exist');\n"
    "  });\n"
    "});"
)

# --- Helper Functions ---
def make_nerdgraph_request(mutation):
    """Sends a mutation and returns a tuple (success: bool, error_message: str|None)."""
    headers = {"API-Key": API_KEY, "Content-Type": "application/json"}
    try:
        with httpx.Client() as client:
            response = client.post(NERDGRAPH_URL, headers=headers, json={"query": mutation})
            response.raise_for_status()
        result = response.json()
        if result.get("data") and result["data"].get(next(iter(result["data"]))) and result["data"][next(iter(result["data"]))].get("errors"):
            return False, json.dumps(result['data'][next(iter(result['data']))]['errors'])
        elif result.get("errors"):
            return False, json.dumps(result['errors'])
        return True, None
    except httpx.HTTPStatusError as e:
        return False, f"HTTP Error: {e.response.status_code} - {e.response.text}"
    except Exception as e:
        return False, f"An unexpected error occurred: {e}"

# --- Creation Logic ---
def create_ping_monitor(name, url, location_guid, period):
    print(f"  Creating SIMPLE monitor: '{name}'...", end="", flush=True)
    mutation = f'''mutation{{syntheticsCreateSimpleMonitor(accountId:{ACCOUNT_ID},monitor:{{name:"{name}",uri:"{url}",locations:{{private:["{location_guid}"]}},period:{period},status:ENABLED,tags:[{{key:"ManagedBy",values:["BulkScript"]}}]}}){{errors{{description}}}}}}'''
    success, error_msg = make_nerdgraph_request(mutation)
    print(f"\r✅" if success else f"\r❌\n     └─ Error: {error_msg}")

def create_simple_browser_monitor(name, url, location_guid, period):
    print(f"  Creating BROWSER monitor: '{name}'...", end="", flush=True)
    mutation = f'''mutation{{syntheticsCreateSimpleBrowserMonitor(accountId:{ACCOUNT_ID},monitor:{{name:"{name}",uri:"{url}",locations:{{private:["{location_guid}"]}},period:{period},status:ENABLED,tags:[{{key:"ManagedBy",values:["BulkScript"]}}],advancedOptions:{{enableScreenshotOnFailureAndScript:true}}}}){{errors{{description}}}}}}'''
    success, error_msg = make_nerdgraph_request(mutation)
    print(f"\r✅" if success else f"\r❌\n     └─ Error: {error_msg}")

def create_scripted_browser_monitor(name, url, location_guid, period):
    print(f"  Creating SCRIPT_BROWSER monitor: '{name}'...", end="", flush=True)
    script_text = SYNTHETIC_BROWSER_SCRIPT_TPL % url
    json_escaped_script = json.dumps(script_text)
    mutation = f'''mutation{{syntheticsCreateScriptBrowserMonitor(accountId:{ACCOUNT_ID},monitor:{{name:"{name}",locations:{{private:[{{guid:"{location_guid}"}}]}},period:{period},status:ENABLED,script:{json_escaped_script},runtime:{{runtimeType:"CHROME_BROWSER",runtimeTypeVersion:"100",scriptLanguage:"JAVASCRIPT"}},tags:[{{key:"ManagedBy",values:["BulkScript"]}}],advancedOptions:{{enableScreenshotOnFailureAndScript:true}}}}){{errors{{description}}}}}}'''
    success, error_msg = make_nerdgraph_request(mutation)
    print(f"\r✅" if success else f"\r❌\n     └─ Error: {error_msg}")

def create_scripted_api_monitor(name, url, location_guid, period):
    print(f"  Creating SCRIPT_API monitor: '{name}'...", end="", flush=True)
    script_text = SYNTHETIC_API_SCRIPT_TPL % url
    json_escaped_script = json.dumps(script_text)
    mutation = f'''mutation{{syntheticsCreateScriptApiMonitor(accountId:{ACCOUNT_ID},monitor:{{name:"{name}",locations:{{private:[{{guid:"{location_guid}"}}]}},period:{period},status:ENABLED,script:{json_escaped_script},runtime:{{runtimeType:"NODE_API",runtimeTypeVersion:"16.10",scriptLanguage:"JAVASCRIPT"}},tags:[{{key:"ManagedBy",values:["BulkScript"]}}]}}){{errors{{description}}}}}}'''
    success, error_msg = make_nerdgraph_request(mutation)
    print(f"\r✅" if success else f"\r❌\n     └─ Error: {error_msg}")

# --- Management Logic ---
def find_monitors_by_tag():
    """Finds all monitors with the 'ManagedBy: BulkScript' tag."""
    print("🔍 Finding monitors with tag 'ManagedBy:BulkScript'...")
    search_query = f"accountId = {ACCOUNT_ID} AND tags.ManagedBy = 'BulkScript' AND domain = 'SYNTH'"
    # UPDATED: The GraphQL query now also fetches the 'period' of each monitor.
    query = f"""
    query {{
      actor {{
        entitySearch(query: "{search_query}") {{
          results {{
            entities {{
              guid
              name
              ... on SyntheticMonitorEntityOutline {{
                monitorType
                monitorId
                period
                monitorSummary {{
                  status
                }}
              }}
            }}
          }}
        }}
      }}
    }}
    """
    headers = {"API-Key": API_KEY, "Content-Type": "application/json"}
    try:
        with httpx.Client() as client:
            response = client.post(NERDGRAPH_URL, headers=headers, json={"query": query})
            response.raise_for_status()
        data = response.json()
        if data.get("errors"):
            print(f"    ❌ GraphQL Error: {data['errors']}")
            return []
        return data["data"]["actor"]["entitySearch"]["results"]["entities"]
    except Exception as e:
        print(f"    ❌ An error occurred while finding monitors: {e}")
        return []

def update_monitor_status(guid, name, monitor_type, monitor_id, status):
    action_verb = "Enabling" if status == "ENABLED" else "Disabling"
    print(f"  {action_verb} monitor '{name}' (ID: {monitor_id})...", end="", flush=True)
    update_mutation_map = {'SIMPLE':'syntheticsUpdateSimpleMonitor','BROWSER':'syntheticsUpdateSimpleBrowserMonitor','SCRIPT_API':'syntheticsUpdateScriptApiMonitor','SCRIPT_BROWSER':'syntheticsUpdateScriptBrowserMonitor'}
    mutation_name = update_mutation_map.get(monitor_type)
    if not mutation_name:
        print(f"\r❓ Unknown monitor type '{monitor_type}'. Skipping.")
        return
    mutation = f"""mutation{{ {mutation_name}(guid:"{guid}",monitor:{{status:{status}}}){{errors{{description}}}}}}"""
    success, error_msg = make_nerdgraph_request(mutation)
    print(f"\r✅" if success else f"\r❌\n     └─ Error: {error_msg}")

def delete_monitor(guid, name, monitor_id):
    print(f"  Deleting monitor '{name}' (ID: {monitor_id})...", end="", flush=True)
    mutation = f"""mutation{{syntheticsDeleteMonitor(guid:"{guid}"){{deletedGuid}}}}"""
    success, error_msg = make_nerdgraph_request(mutation)
    print(f"\r✅" if success else f"\r❌\n     └─ Error: {error_msg}")

def parse_selection(selection_str, max_index):
    """Parses a selection string like '1-3,5' into a set of indices."""
    selected_indices = set()
    selection_str = selection_str.strip()
    if not selection_str or selection_str.upper() == 'ALL':
        return set(range(1, max_index + 1))

    parts = selection_str.split(',')
    for part in parts:
        part = part.strip()
        if not part:
            continue
        if '-' in part:
            try:
                start, end = map(int, part.split('-'))
                if start > end or start < 1 or end > max_index:
                    raise ValueError
                selected_indices.update(range(start, end + 1))
            except ValueError:
                print(f"⚠️ Invalid range '{part}'. Skipping.")
                continue
        else:
            try:
                num = int(part)
                if 1 <= num <= max_index:
                    selected_indices.add(num)
                else:
                    raise ValueError
            except ValueError:
                print(f"⚠️ Invalid number '{part}'. Skipping.")
                continue
    return selected_indices

# --- Main Execution ---
if __name__ == "__main__":
    MONITOR_TYPE_MAP = {
        "SIMPLE": create_ping_monitor,
        "BROWSER": create_simple_browser_monitor,
        "SCRIPT_BROWSER": create_scripted_browser_monitor,
        "SCRIPT_API": create_scripted_api_monitor,
    }

    PERIOD_OPTIONS = {
        "1": "EVERY_MINUTE", "2": "EVERY_5_MINUTES", "3": "EVERY_10_MINUTES",
        "4": "EVERY_15_MINUTES", "5": "EVERY_30_MINUTES", "6": "EVERY_HOUR",
        "7": "EVERY_6_HOURS", "8": "EVERY_12_HOURS", "9": "EVERY_DAY",
    }

    parser = argparse.ArgumentParser(description="Create or manage New Relic Synthetics monitors.")
    parser.add_argument("-t", "--types", nargs="+", choices=list(MONITOR_TYPE_MAP.keys()) + ["ALL"], help="Specify monitor types for the chosen action.")
    args = parser.parse_args()

    # --- Main Menu ---
    print("\nChoose an action:")
    print("  1. Create monitors")
    print("  2. Enable monitors")
    print("  3. Disable monitors")
    print("  4. Delete monitors")

    choice = ""
    while choice not in ["1", "2", "3", "4"]:
        choice = input("\nEnter your choice (1, 2, 3, or 4): ")

    if choice == "1":
        validate_env_vars(for_creation=True)
        if args.types:
            types_to_create = list(MONITOR_TYPE_MAP.keys()) if "ALL" in args.types else args.types
        else:
            types_to_create = list(MONITOR_TYPE_MAP.keys())

        quantity_str = input("\nHow many of each type to create? (Default: 1)\n> ")
        quantity = int(quantity_str) if quantity_str.isdigit() and int(quantity_str) > 0 else 1

        print("\nSelect a monitoring period:")
        for key, value in PERIOD_OPTIONS.items():
            print(f"  {key}. {value}")
        period_choice = ""
        while period_choice not in PERIOD_OPTIONS:
            period_choice = input("Enter your choice (Default: 4 for EVERY_15_MINUTES): ")
            if not period_choice:
                period_choice = "4"
        selected_period = PERIOD_OPTIONS[period_choice]

        try:
            with open('monitors.json', 'r') as f:
                monitor_definitions = json.load(f)
        except FileNotFoundError:
            print("❌ Error: `monitors.json` not found. Please create it first.")
            sys.exit(1)

        print(f"\n🚀 Starting bulk monitor creation for Account ID: {ACCOUNT_ID}")
        for type_name in types_to_create:
            if type_name not in MONITOR_TYPE_MAP:
                print(f"⚠️ Skipping unknown type: {type_name}")
                continue
            create_function = MONITOR_TYPE_MAP[type_name]
            print(f"\n--- Creating {quantity} {type_name} monitor(s) with period {selected_period} ---")
            for _ in range(quantity):
                chosen_monitor = random.choice(monitor_definitions)
                random_suffix = secrets.token_hex(4)
                monitor_name = f"{chosen_monitor['baseName'].replace(' ', '_')}_{random_suffix}"
                create_function(monitor_name, chosen_monitor['url'], PRIVATE_LOCATION_GUID, selected_period)
                time.sleep(0.5)
        print("\n✨ Creation complete.")

    else: # Management Actions
        validate_env_vars()
        all_monitors = find_monitors_by_tag()

        types_to_filter = args.types
        if types_to_filter and "ALL" not in types_to_filter:
            monitors_to_manage = [m for m in all_monitors if m.get('monitorType') in types_to_filter]
        else:
            monitors_to_manage = all_monitors

        action_map = { "2": {"verb": "enable", "status": "ENABLED"}, "3": {"verb": "disable", "status": "DISABLED"}, "4": {"verb": "delete"} }
        action_details = action_map[choice]
        action_verb = action_details["verb"]

        if action_verb == "enable":
            monitors_to_manage = [m for m in monitors_to_manage if m.get('monitorSummary', {}).get('status') == 'DISABLED']
        elif action_verb == "disable":
            monitors_to_manage = [m for m in monitors_to_manage if m.get('monitorSummary', {}).get('status') == 'ENABLED']

        monitors_to_manage.sort(key=lambda m: (m.get('monitorType', ''), m.get('name', '')))

        if not monitors_to_manage:
            print("✅ No monitors found matching the criteria for this action.")
            sys.exit(0)

        max_name_len = max(len(m['name']) for m in monitors_to_manage) if monitors_to_manage else 0

        print("\nMonitors found:")
        for i, m in enumerate(monitors_to_manage, 1):
            status = m.get('monitorSummary', {}).get('status', 'UNKNOWN')
            status_color = Colors.GREEN if status == 'ENABLED' else Colors.YELLOW
            period = m.get('period', 'UNKNOWN')

            name_part = f"  {i}. {m['name']}"
            # UPDATED: Added the formatted period to the details part of the string.
            details_part = (f"({Colors.BOLD}Status:{Colors.ENDC} {status_color}{status}{Colors.ENDC}, "
                            f"{Colors.BOLD}Type:{Colors.ENDC} {Colors.CYAN}{m.get('monitorType')}{Colors.ENDC}, "
                            f"{Colors.BOLD}Period:{Colors.ENDC} {Colors.MAGENTA}{period}{Colors.ENDC}, "
                            f"{Colors.BOLD}ID:{Colors.ENDC} {m.get('monitorId')})")

            print(f"{name_part:<{max_name_len + 6}} {details_part}")

        selection_str = input("\nWhich monitors to act on? (e.g., 1-3, 5, 8 or press Enter for ALL): ")
        selected_indices = parse_selection(selection_str, len(monitors_to_manage))

        if not selected_indices:
            print("\n❌ No valid monitors selected. Action cancelled.")
            sys.exit(0)

        selected_monitors = [monitors_to_manage[i-1] for i in sorted(list(selected_indices))]

        confirm_word = action_verb.upper()
        print(f"\nThis action will {action_verb} the {len(selected_monitors)} selected monitor(s).")
        confirm = input(f"Type '{confirm_word}' to proceed: ")

        if confirm == confirm_word:
            print(f"\n🚀 Starting {action_verb} process...")
            for monitor in selected_monitors:
                monitor_id = monitor.get('monitorId')
                if action_verb == "delete":
                    delete_monitor(monitor['guid'], monitor['name'], monitor_id)
                else:
                    update_monitor_status(monitor['guid'], monitor['name'], monitor.get('monitorType'), monitor_id, action_details["status"])
                time.sleep(0.5)
            print(f"\n✨ {action_verb.capitalize()} complete.")
        else:
            print(f"\n❌ Action cancelled.")
