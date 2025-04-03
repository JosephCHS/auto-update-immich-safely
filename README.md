# auto-update-immich-safely

## Overview

This Bash script automates the process of updating Immich while ensuring safety and stability. It performs the following tasks:

* Retrieves the current running version of Immich from your server
* Fetches the latest version information from GitHub
* Checks if the latest release is at least 7 days old (configurable)
* Scans release notes for breaking changes, warnings, or important notes
* Sends notifications via Gotify about update status
* Maintains a detailed log of all update operations
* Automatically updates Immich using Docker Compose when safe to do so

## Features

* **Safety First**: Checks for breaking changes and waits for new releases to stabilize
* **Robust Error Handling**: Includes retry logic for API calls and detailed error reporting
* **Comprehensive Logging**: Maintains a timestamped log file of all operations
* **Notifications**: Sends status updates via Gotify for successful updates and warnings
* **Reliability**: Multiple checks ensure system stability during updates

## Prerequisites

### 1. Install Required Tools

Ensure you have the following installed:

* `jq` (for parsing JSON)
* `curl` (for API requests)
* `docker` & `docker compose` (V2 compose command)

### 2. Configuration File

Create a config file at `~/immich-app/.immich.conf` with the following content:

```bash
DOCKER_COMPOSE_PATH="/path/to/docker-compose"
GOTIFY_TOKEN="your_gotify_token"
GOTIFY_URL="http://your_gotify_instance"
IMMICH_API_KEY="your_immich_api_key"
IMMICH_LOCALHOST="192.168.1.X:2283"  # Adjust to your Immich instance
IMMICH_PATH="/path/to/immich"
```

## Installation

1. Place the script in a location such as `~/immich-app/update-immich.sh`
2. Make the script executable:

```bash
chmod +x ~/immich-app/update-immich.sh
```

## Usage

### Manual Execution

Run the script manually:

```bash
~/immich-app/update-immich.sh
```

### Scheduled Updates

Schedule it with cron (e.g., run every night at 2 AM):

```bash
0 2 * * * $HOME/immich-app/update-immich.sh
```

The script creates its own log file at `~/immich-app/update_log.txt`, so redirecting output in the cron job is optional.

## Script Functionality

1. **Configuration Loading**: Reads credentials and settings from the config file
2. **Safety Checks**: Verifies all required variables are set
3. **Version Comparison**: 
   - Retrieves current version from Immich API
   - Fetches latest version from GitHub API
4. **Release Analysis**:
   - Checks if the release is at least 7 days old
   - Scans release notes for any breaking changes or warnings
5. **Update Process**:
   - Pulls latest Docker images
   - Restarts the Immich stack with docker compose
6. **Notification System**:
   - Sends status updates via Gotify
   - Different priority levels based on message importance

## Customization

You can modify the following variables at the top of the script:

* `MIN_DAYS_SINCE_RELEASE`: Change the waiting period for new releases (default: 7 days)
* `LOG_FILE`: Customize the location of the log file

## Troubleshooting

Check the log file at `~/immich-app/update_log.txt` for detailed information about each update attempt. The log includes timestamped entries that can help diagnose any issues with the update process.
