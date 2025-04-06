# auto-update-immich-safely

An automated update script for [Immich](https://immich.app/), the self-hosted photo and video backup solution.

## Overview

This script safely automates the Immich update process with several safety features:

- Waits for a minimum number of days after a release before updating
- Detects breaking changes in release notes
- Sends notifications about updates and potential issues
- Includes error handling and retries for API requests
- Cleans up old Docker images after successful updates

## Features

- 🔄 **Automatic Updates**: Checks for and applies new Immich releases
- ⚠️ **Breaking Change Detection**: Warns when release notes contain terms like "breaking change" or "caution"
- 🕒 **Update Delay**: Configurable waiting period after new releases (default: 7 days)
- 📧 **Notifications**: Email or Gotify notification support
- 🧹 **Cleanup**: Removes old Docker images to save disk space
- 📝 **Logging**: Comprehensive logging of all operations

## Prerequisites

- Docker and Docker Compose
- `jq` for JSON processing
- `mail` command (if using email notifications)
- A running Immich installation

## Installation

1. Clone or download this script to your Immich server
2. Create a configuration file at `~/immich-app/.immich.conf`
3. Make the script executable: `chmod +x update-immich.sh`
4. Add a cron job to run the script periodically (e.g., daily)

## Configuration

Create a configuration file at `~/immich-app/.immich.conf` with the following variables:

```bash
# Required variables
IMMICH_API_KEY="your_immich_api_key"
DOCKER_COMPOSE_PATH="/path/to/docker/compose"
IMMICH_PATH="/path/to/immich"
IMMICH_LOCALHOST="localhost:2283"  # Adjust port if needed
NOTIFICATION_METHOD="email"  # or "gotify"

# For email notifications
NOTIFICATION_EMAIL="your@email.com"

# For Gotify notifications
GOTIFY_TOKEN="your_gotify_token"
GOTIFY_URL="https://your-gotify-server"
```

## Usage

Run the script manually:

```bash
./update-immich.sh
```

Or set up a cron job to run it automatically:

```bash
# Run daily at 3 AM
0 3 * * * /path/to/update-immich.sh >> /var/log/immich_update.log 2>&1
```

## Safety Features

- **No Root**: The script refuses to run as root or with sudo
- **Release Aging**: Waits for a configurable number of days after a release before updating
- **Breaking Change Detection**: Alerts you when it detects potentially breaking changes
- **Retries**: Multiple attempts for API calls with timeouts to handle temporary issues

## Logs

Logs are stored at `~/immich-app/update_log.txt` and contain timestamps for all operations, making it easy to troubleshoot issues.

## Customization

The script includes several variables at the top that you can adjust:

- `MIN_DAYS_SINCE_RELEASE`: Minimum days to wait after a release (default: 7)
- `CURL_TIMEOUT`: Timeout in seconds for curl requests (default: 30)
- `LOG_FILE`: Location of the log file

## License

Feel free to modify and distribute according to your needs.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
