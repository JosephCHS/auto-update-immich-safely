#!/bin/bash

set -euo pipefail  # Exit on error, prevent unset variables, and catch pipeline failures

# Check if script is run with sudo and reject if it is
if [ "$(id -u)" -eq 0 ]; then
    echo "❌ This script should not be run as root or with sudo."
    exit 1
fi

# Configuration
CONFIG_FILE="$HOME/immich-app/.immich.conf"
LOG_FILE="$HOME/immich-app/update_log.txt"
MIN_DAYS_SINCE_RELEASE=7
CURL_TIMEOUT=30

# Ensure config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Config file $CONFIG_FILE not found. Exiting."
    exit 1
fi

# Load variables from config file
# shellcheck disable=SC1090
source "$CONFIG_FILE"

# Check if required variables are set
REQUIRED_VARS=("IMMICH_API_KEY" "DOCKER_COMPOSE_PATH" "IMMICH_PATH" "IMMICH_LOCALHOST" "NOTIFICATION_METHOD")
[[ "$NOTIFICATION_METHOD" == "email" ]] && REQUIRED_VARS+=("NOTIFICATION_EMAIL")
[[ "$NOTIFICATION_METHOD" == "gotify" ]] && REQUIRED_VARS+=("GOTIFY_TOKEN" "GOTIFY_URL")
[[ "$NOTIFICATION_METHOD" == "none" ]] || [[ " email gotify " =~ " $NOTIFICATION_METHOD " ]] || {
    echo "❌ Error: NOTIFICATION_METHOD must be 'email', 'gotify', or 'none'"
    exit 1
}

for var in "${REQUIRED_VARS[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        echo "❌ Error: Required variable '$var' is not set in $CONFIG_FILE."
        exit 1
    fi
done

# Check for required dependencies : jq
command -v jq >/dev/null 2>&1 || { echo "❌ jq is required but not installed. Exiting."; exit 1; }

# Check for required dependencies : check for mail command only if email notifications are enabled
if [[ "$NOTIFICATION_METHOD" == "email" ]]; then
    command -v mail >/dev/null 2>&1 || { echo "❌ mail command is required but not installed. Exiting."; exit 1; }
fi

# Function to log messages
log_message() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" | tee -a "$LOG_FILE"
}

# Function to send notifications
send_notification() {
    local title="$1"
    local message="$2"
    local priority="${3:-5}"
    
    case "${NOTIFICATION_METHOD:-}" in
        "email")
            echo -e "$message" | mail -s "$title" "$NOTIFICATION_EMAIL"
            if [ $? -ne 0 ]; then
                log_message "⚠️ Failed to send email notification."
            fi
            ;;
        "gotify")
            # Escape quotes in message and title
            message="${message//\"/\\\"}"
            title="${title//\"/\\\"}"
            
            if ! curl --max-time "$CURL_TIMEOUT" -s -X POST "$GOTIFY_URL/message" \
                -H "Content-Type: application/json" \
                -H "X-Gotify-Key: $GOTIFY_TOKEN" \
                -d "{\"title\":\"$title\",\"message\":\"$message\",\"priority\":$priority}"; then
                log_message "⚠️ Failed to send Gotify notification."
            fi
            ;;
        "none")
            # Skip notifications
            return 0
            ;;
        *)
            log_message "⚠️ Invalid NOTIFICATION_METHOD: must be 'email', 'gotify', or 'none'"
            exit 1
            ;;
    esac
}

# Create log directory if it doesn't exist
mkdir -p "$(dirname "$LOG_FILE")"

log_message "🔄 Starting Immich update check..."

# Get latest Immich release info with retry
get_github_release_info() {
    local max_retries=3
    local retry_count=0
    local response=""
    
    while [ "$retry_count" -lt "$max_retries" ]; do
        response=$(curl --max-time "$CURL_TIMEOUT" -s -f "$IMMICH_RELEASE_URL")
        if [[ -n "$response" && "$response" != "null" ]]; then
            echo "$response"
            return 0
        fi
        retry_count=$((retry_count + 1))
        log_message "⚠️ GitHub API request failed, retrying ($retry_count/$max_retries)..."
        sleep 2
    done
    
    return 1
}

# Get current Immich version with retry
get_current_version() {
    local max_retries=3
    local retry_count=0
    local response=""
    
    while [ "$retry_count" -lt "$max_retries" ]; do
        response=$(curl --max-time "$CURL_TIMEOUT" -s -L -f "http://$IMMICH_LOCALHOST/api/server/about" -H "Accept: application/json" -H "x-api-key: $IMMICH_API_KEY")
        if [[ -n "$response" && "$response" != "null" ]]; then
            echo "$response"
            return 0
        fi
        retry_count=$((retry_count + 1))
        log_message "⚠️ Immich API request failed, retrying ($retry_count/$max_retries)..."
        sleep 2
    done
    
    return 1
}

# Function to compare versions
version_gt() {
    test "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1"
}

# Main execution

# Get latest Immich release info
IMMICH_RELEASE_URL="https://api.github.com/repos/immich-app/immich/releases/latest"
IMMICH_RESPONSE=$(get_github_release_info)

# Validate GitHub API response
if [ $? -ne 0 ]; then
    log_message "❌ Failed to fetch latest Immich release info after multiple attempts. Exiting."
    send_notification "❌ Immich Update Failed" "Could not fetch latest release information from GitHub" 8
    exit 1
fi

# Extract version and release notes
LATEST_VERSION=$(echo "$IMMICH_RESPONSE" | jq -r '.tag_name' | sed 's/^v//')
RELEASE_NOTES=$(echo "$IMMICH_RESPONSE" | jq -r '.body')
RELEASE_URL=$(echo "$IMMICH_RESPONSE" | jq -r '.html_url')

# Get current running version
CURRENT_VERSION_RESPONSE=$(get_current_version)

# Validate Immich API response
if [ $? -ne 0 ]; then
    log_message "❌ Failed to fetch Immich current version after multiple attempts. Ensure Immich is running and API key is valid."
    send_notification "❌ Immich Update Failed" "Could not connect to Immich server to check version" 8
    exit 1
fi

CURRENT_VERSION=$(echo "$CURRENT_VERSION_RESPONSE" | jq -r '.version' | sed 's/^v//')

log_message "📊 Current version: v$CURRENT_VERSION, Latest version: v$LATEST_VERSION"

# Get latest release date from GitHub
LATEST_RELEASE_DATE=$(echo "$IMMICH_RESPONSE" | jq -r '.published_at' | cut -d'T' -f1)
CURRENT_DATE=$(date +"%Y-%m-%d")
DAYS_SINCE_RELEASE=$(( ( $(date -d "$CURRENT_DATE" +%s) - $(date -d "$LATEST_RELEASE_DATE" +%s) ) / 86400 ))

# If the release is less than MIN_DAYS_SINCE_RELEASE days old, do not update
if [ "$DAYS_SINCE_RELEASE" -lt "$MIN_DAYS_SINCE_RELEASE" ]; then
    log_message "⏳ Skipping update: Immich v$LATEST_VERSION was released only $DAYS_SINCE_RELEASE days ago (waiting for $MIN_DAYS_SINCE_RELEASE days)."
    exit 0
fi

# Check for breaking changes or important notes in release
if echo "$RELEASE_NOTES" | grep -iqE "breaking change|important note|caution|warning"; then
    log_message "🚨 Breaking Changes or important notes detected in Immich update (v$LATEST_VERSION). Manual review required."
    send_notification "🚨 Immich Update Warning!" "Breaking changes detected in v$LATEST_VERSION. Manual update required.\n\nSee: $RELEASE_URL" 8
    exit 1
fi

# Compare versions & update if needed
if version_gt "$LATEST_VERSION" "$CURRENT_VERSION"; then
    log_message "🚀 Updating Immich from v$CURRENT_VERSION to v$LATEST_VERSION..."
      
    # Perform update
    if cd "$IMMICH_PATH" && \
       docker compose pull && \
       docker compose up -d; then
        log_message "✅ Immich updated successfully to v$LATEST_VERSION."
        
        # Cleanup old images
        log_message "🧹 Cleaning up old Docker images..."
        if docker image prune -f --filter "until=24h" > /dev/null; then
            log_message "✅ Old Docker images cleaned up successfully."
        else
            log_message "⚠️ Failed to clean up old Docker images."
        fi
        
        send_notification "✅ Immich Updated!" "Successfully updated from v$CURRENT_VERSION to v$LATEST_VERSION" 5
    else
        log_message "❌ Update failed! Please check the logs."
        send_notification "❌ Immich Update Failed" "Error occurred while updating from v$CURRENT_VERSION to v$LATEST_VERSION" 8
        exit 1
    fi
else
    log_message "✅ Immich is already up-to-date (v$CURRENT_VERSION)."
fi

log_message "🏁 Update check completed"
exit 0
