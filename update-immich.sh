#!/bin/bash

set -euo pipefail  # Exit on error, prevent unset variables, and catch pipeline failures

# Check if script is run with sudo and reject if it is
if [ "$(id -u)" -eq 0 ]; then
    echo "❌ This script should not be run as root or with sudo."
    exit 1
fi

# Set PATH explicitly for cron compatibility
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Configuration
CONFIG_FILE="$HOME/immich-app/.immich.conf"
LOG_FILE="$HOME/immich-app/update_log.txt"
LOCK_FILE="$HOME/immich-app/update.lock"
MIN_DAYS_SINCE_RELEASE=7
CURL_TIMEOUT=30

# Function to cleanup on exit
cleanup() {
    local exit_code=$?
    if [ -f "$LOCK_FILE" ]; then
        rm -f "$LOCK_FILE"
    fi
    exit $exit_code
}

# Set up trap to cleanup lock file on exit
trap cleanup EXIT INT TERM

# Check for existing lock file (prevent multiple instances)
if [ -f "$LOCK_FILE" ]; then
    # Check if the process is actually running
    if kill -0 "$(cat "$LOCK_FILE")" 2>/dev/null; then
        echo "❌ Update script is already running (PID: $(cat "$LOCK_FILE")). Exiting."
        exit 1
    else
        # Stale lock file, remove it
        rm -f "$LOCK_FILE"
    fi
fi

# Create lock file with current PID
echo $$ > "$LOCK_FILE"

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
[[ "$NOTIFICATION_METHOD" == "gotify" ]] && REQUIRED_VARS+=("GOTIFY_TOKEN" "GOTIFY_URL")
[[ "$NOTIFICATION_METHOD" == "none" ]] || [[ " gotify " =~ " $NOTIFICATION_METHOD " ]] || {
    echo "❌ Error: NOTIFICATION_METHOD must be 'gotify' or 'none'"
    exit 1
}

for var in "${REQUIRED_VARS[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        echo "❌ Error: Required variable '$var' is not set in $CONFIG_FILE."
        exit 1
    fi
done

# Check for required dependencies with full paths
DOCKER_CMD=$(command -v docker 2>/dev/null || echo "/usr/bin/docker")
JQ_CMD=$(command -v jq 2>/dev/null || echo "/usr/bin/jq")
CURL_CMD=$(command -v curl 2>/dev/null || echo "/usr/bin/curl")

# Verify commands exist
for cmd in "$DOCKER_CMD" "$JQ_CMD" "$CURL_CMD"; do
    if [ ! -x "$cmd" ]; then
        echo "❌ Required command not found: $cmd"
        exit 1
    fi
done

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
        "gotify")
            # Escape quotes in message and title
            message="${message//\"/\\\"}"
            title="${title//\"/\\\"}"
            
            if ! "$CURL_CMD" --max-time "$CURL_TIMEOUT" -s -X POST "$GOTIFY_URL/message" \
                -H "Content-Type: application/json" \
                -H "X-Gotify-Key: $GOTIFY_TOKEN" \
                -d "{\"title\":\"$title\",\"message\":\"$message\",\"priority\":$priority}" >/dev/null 2>&1; then
                log_message "⚠️ Failed to send Gotify notification."
            fi
            ;;
        "none")
            # Skip notifications
            return 0
            ;;
        *)
            log_message "⚠️ Invalid NOTIFICATION_METHOD: must be 'gotify' or 'none'"
            exit 1
            ;;
    esac
}

# Create log directory if it doesn't exist
mkdir -p "$(dirname "$LOG_FILE")"

log_message "🔄 Starting Immich update check (PID: $$)..."
log_message "📍 Running from: $(pwd)"
log_message "🔧 Using Docker: $DOCKER_CMD"
log_message "🔧 Using jq: $JQ_CMD"
log_message "🔧 Using curl: $CURL_CMD"

# Get latest Immich release info with retry
get_github_release_info() {
    local max_retries=3
    local retry_count=0
    local response=""
    
    while [ "$retry_count" -lt "$max_retries" ]; do
        response=$("$CURL_CMD" --max-time "$CURL_TIMEOUT" -s -f "$IMMICH_RELEASE_URL" 2>/dev/null)
        if [[ -n "$response" && "$response" != "null" ]]; then
            echo "$response"
            return 0
        fi
        retry_count=$((retry_count + 1))
        log_message "⚠️ GitHub API request failed, retrying ($retry_count/$max_retries)..."
        sleep 5  # Increased sleep time between retries
    done
    
    return 1
}

# Get current Immich version with retry
get_current_version() {
    local max_retries=3
    local retry_count=0
    local response=""
    
    while [ "$retry_count" -lt "$max_retries" ]; do
        response=$("$CURL_CMD" --max-time "$CURL_TIMEOUT" -s -L -f "http://$IMMICH_LOCALHOST/api/server/about" -H "Accept: application/json" -H "x-api-key: $IMMICH_API_KEY" 2>/dev/null)
        if [[ -n "$response" && "$response" != "null" ]]; then
            echo "$response"
            return 0
        fi
        retry_count=$((retry_count + 1))
        log_message "⚠️ Immich API request failed, retrying ($retry_count/$max_retries)..."
        sleep 5  # Increased sleep time between retries
    done
    
    return 1
}

# Function to compare versions
version_gt() {
    test "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1"
}

# Function to wait for Immich to be ready after update
wait_for_immich() {
    local max_wait=300  # 5 minutes
    local wait_time=0
    local sleep_interval=10
    
    log_message "⏳ Waiting for Immich to be ready after update..."
    
    while [ $wait_time -lt $max_wait ]; do
        if "$CURL_CMD" --max-time 10 -s -f "http://$IMMICH_LOCALHOST/api/server/about" -H "x-api-key: $IMMICH_API_KEY" >/dev/null 2>&1; then
            log_message "✅ Immich is ready and responding."
            return 0
        fi
        sleep $sleep_interval
        wait_time=$((wait_time + sleep_interval))
        log_message "⏳ Still waiting for Immich... (${wait_time}s/${max_wait}s)"
    done
    
    log_message "⚠️ Immich did not respond within ${max_wait} seconds."
    return 1
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
LATEST_VERSION=$(echo "$IMMICH_RESPONSE" | "$JQ_CMD" -r '.tag_name' | sed 's/^v//')
RELEASE_NOTES=$(echo "$IMMICH_RESPONSE" | "$JQ_CMD" -r '.body')
RELEASE_URL=$(echo "$IMMICH_RESPONSE" | "$JQ_CMD" -r '.html_url')

# Get current running version
CURRENT_VERSION_RESPONSE=$(get_current_version)

# Validate Immich API response
if [ $? -ne 0 ]; then
    log_message "❌ Failed to fetch Immich current version after multiple attempts. Ensure Immich is running and API key is valid."
    send_notification "❌ Immich Update Failed" "Could not connect to Immich server to check version" 8
    exit 1
fi

CURRENT_VERSION=$(echo "$CURRENT_VERSION_RESPONSE" | "$JQ_CMD" -r '.version' | sed 's/^v//')

log_message "📊 Current version: v$CURRENT_VERSION, Latest version: v$LATEST_VERSION"

# Get latest release date from GitHub
LATEST_RELEASE_DATE=$(echo "$IMMICH_RESPONSE" | "$JQ_CMD" -r '.published_at' | cut -d'T' -f1)
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
       "$DOCKER_CMD" compose pull 2>&1 | tee -a "$LOG_FILE" && \
       "$DOCKER_CMD" compose up -d 2>&1 | tee -a "$LOG_FILE"; then
        
        # Wait for Immich to be ready
        if wait_for_immich; then
            log_message "✅ Immich updated successfully to v$LATEST_VERSION."
            
            # Cleanup old images
            log_message "🧹 Cleaning up old Docker images..."
            if "$DOCKER_CMD" image prune -f --filter "until=24h" >/dev/null 2>&1; then
                log_message "✅ Old Docker images cleaned up successfully."
            else
                log_message "⚠️ Failed to clean up old Docker images."
            fi
            
            send_notification "✅ Immich Updated!" "Successfully updated from v$CURRENT_VERSION to v$LATEST_VERSION" 5
        else
            log_message "⚠️ Immich update completed but service may not be fully ready."
            send_notification "⚠️ Immich Update Warning" "Update completed but service verification failed" 6
        fi
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
