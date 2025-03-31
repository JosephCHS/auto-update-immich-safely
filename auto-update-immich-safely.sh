#!/bin/bash

## Config file "~/immich-app/.immich.conf" needed with the following variables
# API_KEY
# DOCKER_COMPOSE_PATH
# GOTIFY_TOKEN
# GOTIFY_URL
# IMMICH_PATH
# IMMICH_LOCALHOST

# Load variables from config file
source ~/immich-app/.immich.conf

# Get current running version
CURRENT_VERSION=$(curl -s -L http://$IMMICH_LOCALHOST/api/server/about -H "Accept:application/json" -H "x-api-key: $API_KEY" | jq -r '.version' | sed 's/v//')
# Get latest version from GitHub
LATEST_VERSION=$(curl -s https://api.github.com/repos/immich-app/immich/releases/latest | jq -r '.tag_name' | sed 's/v//')
# Get release notes
RELEASE_NOTES=$(curl -s https://api.github.com/repos/immich-app/immich/releases/latest | jq -r '.body')

# Gotify function
send_gotify_notification() {
    TITLE="🚨 Immich Update Warning!"
    MESSAGE="Breaking changes detected in Immich v$LATEST_VERSION. Manual update required."
    
    curl -X POST "$GOTIFY_URL/message" \
        -H "Content-Type: application/json" \
        -H "X-Gotify-Key: $GOTIFY_TOKEN" \
        -d "{\"title\":\"$TITLE\",\"message\":\"$MESSAGE\",\"priority\":5}"
}

# Check for breaking changes
if echo "$RELEASE_NOTES" | grep -iq "breaking change"; then
    echo "🚨 Breaking Changes detected in Immich update ($LATEST_VERSION). Manual review required."
        send_gotify_notification
    exit 1
fi

# Compare versions & update if needed
if [ "$CURRENT_VERSION" != "$LATEST_VERSION" ]; then
    echo "🚀 Updating Immich from v$CURRENT_VERSION to v$LATEST_VERSION..."
    cd "$IMMICH_PATH" && docker compose pull && docker compose up -d
    echo "✅ Immich updated successfully to $LATEST_VERSION."

else
    echo "✅ Immich is already up-to-date (v$CURRENT_VERSION)."
fi

