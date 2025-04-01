# auto-update-immich-safely

## Overview
This Bash script automates the process of updating Immich while ensuring that no breaking changes are introduced. It does the following:

- Retrieves the current running version of Immich inside the docker container.
- Fetches the latest version from GitHub.
- Checks for breaking changes in the release notes.
- Notifies the user via Gotify if a breaking change is detected and exit the update process.
- If no breaking changes exist and an update is available, it automatically updates Immich using Docker Compose.

## Prerequisites
### 1. Install Required Tools
Ensure you have the following installed:
- `jq` (for parsing JSON)
- `curl` (for fetching API data)
- `docker` & `docker-compose`

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

## Usage
1. Place the script in a location such as `~/immich-app/update-immich.sh`.
2. Make the script executable:
   ```bash
   chmod +x ~/immich-app/update-immich.sh
   ```
3. Run it manually:
   ```bash
   ~/immich-app/update-immich.sh
   ```
4. Schedule it with cron (e.g., run every night at 2 AM):
   ```bash
   0 2 * * * $HOME/immich-app/update-immich.sh >> /var/log/immich_update.log 2>&1
   ```

## Script Breakdown
1. **Loads Configuration**: Reads sensitive credentials from `~/immich-app/.immich.conf`.
2. **Fetches Current Version**: Calls Immich API to retrieve the running version.
3. **Fetches Latest Version**: Uses GitHub API to check the latest release.
4. **Checks for Breaking Changes**: If found, sends a Gotify notification and aborts the update.
5. **Updates Immich (if safe)**: Pulls the latest Docker image and restarts Immich.
