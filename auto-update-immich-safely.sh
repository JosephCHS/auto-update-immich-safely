#!/bin/bash

set -euo pipefail  # Exit on error, prevent unset variables, and catch pipeline failures

CONFIG_FILE="$HOME/immich-app/.immich.conf"

# Ensure config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Config file $CONFIG_FILE not found. Exiting."
    exit 1
fi

# Load variables from config file
source "$CONFIG_FILE"

# Check if required variables are set
REQUIRED_VARS=("IMMICH_API_KEY" "DOCKER_COMPOSE_PATH" "GOTIFY_TOKEN" "GOTIFY_URL" "IMMICH_PATH" "IMMICH_LOCALHOST")
for var in "${REQUIRED_VARS[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        echo "❌ Error: Required variable '$var' is not set in $CONFIG_FILE"
        exit 1
    fi
done

# Get latest Immich release info
IMMICH_RELEASE_URL="https://api.github.com/repos/immich-app/immich/releases/latest"
IMMICH_RESPONSE=$(curl -s "$IMMICH_RELEASE_URL")

# Validate GitHub API response
if [[ -z "$IMMICH_RESPONSE" || "$IMMICH_RESPONSE" == "null" ]]; then
    echo "❌ Failed to fetch latest Immich release info. Exiting."
    exit 1
fi

# Extract version and release notes
LATEST_VERSION=$(echo "$IMMICH_RESPONSE" | jq -r '.tag_name' | sed 's/v//')
RELEASE_NOTES=$(echo "$IMMICH_RESPONSE" | jq -r '.body')

# Get current running version
CURRENT_VERSION_RESPONSE=$(curl -s -L "http://$IMMICH_LOCALHOST/api/server/about" -H "Accept:application/json" -H "x-api-key: $IMMICH_API_KEY")

# Validate Immich API response
if [[ -z "$CURRENT_VERSION_RESPONSE" || "$CURRENT_VERSION_RESPONSE" == "null" ]]; then
    echo "❌ Failed to fetch Immich current version. Ensure Immich is running and API key is valid."
    exit 1
fi

CURRENT_VERSION=$(echo "$CURRENT_VERSION_RESPONSE" | jq -r '.version' | sed 's/v//')

# Get latest release date from GitHub
LATEST_RELEASE_DATE=$(echo "$IMMICH_RESPONSE" | jq -r '.published_at' | cut -d'T' -f1)
CURRENT_DATE=$(date +"%Y-%m-%d")
DAYS_SINCE_RELEASE=$(( ( $(date -d "$CURRENT_DATE" +%s) - $(date -d "$LATEST_RELEASE_DATE" +%s) ) / 86400 ))

# If the release is less than 7 days old, do not update
if [ "$DAYS_SINCE_RELEASE" -lt 7 ]; then
    echo "⏳ Skipping update: Immich v$LATEST_VERSION was released only $DAYS_SINCE_RELEASE days ago."
    exit 0
fi

# Function to send Gotify notification
send_gotify_notification() {
    local title="$1"
    local message="$2"
    curl -X POST "$GOTIFY_URL/message" \
        -H "Content-Type: application/json" \
        -H "X-Gotify-Key: $GOTIFY_TOKEN" \
        -d "{\"title\":\"$title\",\"message\":\"$message\",\"priority\":5}"
}

# Check for breaking changes
if echo "$RELEASE_NOTES" | grep -iq "breaking change"; then
    echo "🚨 Breaking Changes detected in Immich update ($LATEST_VERSION). Manual review required."
    send_gotify_notification "🚨 Immich Update Warning!" "Breaking changes detected in v$LATEST_VERSION. Manual update required."
    exit 1
fi

# Compare versions & update if needed
if [ "$CURRENT_VERSION" != "$LATEST_VERSION" ]; then
    echo "🚀 Updating Immich from v$CURRENT_VERSION to v$LATEST_VERSION..."
    cd "$IMMICH_PATH" && docker compose pull && docker compose up -d
    echo "✅ Immich updated successfully to $LATEST_VERSION."

    send_gotify_notification "✅ Immich Updated!" "Successfully updated to v$LATEST_VERSION."
else
    echo "✅ Immich is already up-to-date (v$CURRENT_VERSION)."
fi
