#!/bin/bash

# --- 0. Check for dependencies ---
if ! command -v jq &> /dev/null
then
    echo "--- ❌ Error: 'jq' is not installed. ---"
    echo "Please install jq to parse JSON responses."
    echo "macOS: brew install jq"
    echo "Linux: sudo apt-get install jq  (or yum)"
    exit 1
fi

# --- 1. Load variables from .env file ---
# Find the directory where this script is located
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
ENV_FILE="$SCRIPT_DIR/.env"

if [ -f "$ENV_FILE" ]; then
  # Source the variables from the .env file
  source "$ENV_FILE"
else
  echo "--- ❌ Error: .env file not found. ---"
  echo "Please create a .env file at: $ENV_FILE"
  exit 1
fi

# Check if required variables are set
if [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ] || [ -z "$CALLBACK_URL" ]; then
  echo "--- ❌ Error: CLIENT_ID, CLIENT_SECRET, or CALLBACK_URL is not set in your .env file. ---"
  exit 1
fi

# Derive SITE_URL from the loaded CALLBACK_URL
SITE_URL=$(echo "$CALLBACK_URL" | awk -F/ '{print $1"//"$3}')
echo "--- ✅ .env file loaded for site: $SITE_URL ---"

# --- 2. Construct the Authorization URL ---
ENCODED_SCOPE=$(echo -n "$SCOPE" | sed -e 's/ /%20/g' -e 's/:/%3A/g')
ENCODED_CALLBACK_URL=$(echo -n "$CALLBACK_URL" | sed -e 's/:/%3A/g' -e 's/\//%2F/g')

AUTH_URL="https://auth.atlassian.com/authorize?audience=api.atlassian.com&client_id=$CLIENT_ID&scope=$ENCODED_SCOPE&redirect_uri=$ENCODED_CALLBACK_URL&response_type=code&prompt=consent"

# --- 3. Instruct the user ---
echo "------------------------------------------------------------------"
echo "STEP 1: Copy this full URL and paste it in your web browser:"
echo
echo "$AUTH_URL"
echo
echo "STEP 2: Log in, grant consent, and you will be redirected."
echo "------------------------------------------------------------------"

# --- 4. Get the full redirect URL from a file ---
# This bypasses the terminal's 1024-character input limit.

TEMP_URL_FILE="$SCRIPT_DIR/url.txt"

echo
echo "STEP 3: Copy the *full* (and very long) URL from your browser."
echo
echo "STEP 4: Paste that URL into this text file:"
echo "         $TEMP_URL_FILE"
echo
echo "(It will be a unique URL per request.)"
echo
read -p "Press [ENTER] after you have saved the file..."

if [ ! -f "$TEMP_URL_FILE" ]; then
  echo
  echo "--- ❌ Error: File not found! ---"
  echo "I was looking for: $TEMP_URL_FILE"
  exit 1
fi

# Read the entire file content, strip newlines, and save to variable
FULL_REDIRECT_URL=$(cat "$TEMP_URL_FILE" | tr -d '\n\r')

# --- 5. Extract the Auth Code ---
# Strip leading/trailing single quotes just in case user added them
FULL_REDIRECT_URL=$(echo "$FULL_REDIRECT_URL" | sed "s/^'//" | sed "s/'$//")

if [[ "$FULL_REDIRECT_URL" != *code=* ]]; then
  echo
  echo "--- ❌ Error: 'code=' not found in the URL from url.txt. ---"
  echo "Please check the file and try again."
  exit 1
fi

# Extract the code
CODE_AND_REST="${FULL_REDIRECT_URL#*code=}"
AUTH_CODE="${CODE_AND_REST%%&*}"
echo
echo "--- ✅ Auth Code extracted from file ---"

# --- ⭐️ NEW DEBUG LINE ⭐️ ---
# echo "DEBUG: Auth Code is: [$AUTH_CODE]"
# --- END DEBUG ---

# --- 6. Exchange the Auth Code for an Access Token ---
echo "---  exchanging code for access token... ---"

JSON_PAYLOAD=$(printf \
  '{"grant_type": "authorization_code", "client_id": "%s", "client_secret": "%s", "code": "%s", "redirect_uri": "%s"}' \
  "$CLIENT_ID" "$CLIENT_SECRET" "$AUTH_CODE" "$CALLBACK_URL")

# Capture the response in a variable
TOKEN_RESPONSE=$(curl --silent --request POST \
  --url 'https://auth.atlassian.com/oauth/token' \
  --header 'Content-Type: application/json' \
  --data "$JSON_PAYLOAD")

# Parse the access_token from the JSON response using jq
ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r .access_token)

if [ "$ACCESS_TOKEN" == "null" ] || [ -z "$ACCESS_TOKEN" ]; then
  echo "--- ❌ Error: Could not get access token. Response was: ---"
  echo "$TOKEN_RESPONSE"
  exit 1
fi

echo "--- ✅ Access Token received ---"

# --- 7. Get Accessible Resources (find Cloud ID) ---
echo "--- fetching accessible resources (Cloud ID)... ---"

# Capture the resources response
RESOURCES_RESPONSE=$(curl --silent --request GET \
  --url 'https://api.atlassian.com/oauth/token/accessible-resources' \
  --header "Authorization: Bearer $ACCESS_TOKEN" \
  --header 'Accept: application/json')

# Parse the JSON response
CLOUD_ID=$(echo "$RESOURCES_RESPONSE" | jq -r --arg site_url "$SITE_URL" '.[] | select(.url == $site_url) | .id')

if [ "$CLOUD_ID" == "null" ] || [ -z "$CLOUD_ID" ]; then
  echo "--- ❌ Error: Could not find Cloud ID for site '$SITE_URL'. ---"
  echo "Make sure the token scopes are correct and the site is accessible."
  echo "Response was:"
  echo "$RESOURCES_RESPONSE"
  exit 1
fi

echo
echo "------------------------------------------------------------------"
echo "🎉 Success! All values retrieved."
echo
echo "Your Site URL:      $SITE_URL"
echo "Your Cloud ID:      $CLOUD_ID"
echo "Your Access Token:  $ACCESS_TOKEN"
echo "------------------------------------------------------------------"

# --- 8. Construct the final API Base URL ---
API_BASE_URL="https://api.atlassian.com/ex/wiki/$CLOUD_ID"

echo
echo "Your app's Confluence API Base URL is:"
echo "$API_BASE_URL"
echo
echo "Example: To get details about your 'SE' space, you would query:"
echo "$API_BASE_URL/rest/api/space/SE"
echo
