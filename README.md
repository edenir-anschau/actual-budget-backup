# Actual Budget export

This project exports an Actual Budget budget as a timestamped ZIP backup by directly calling the Actual API's `exportBudget()` method inside a Docker container. Backups can be created manually or scheduled every 15 minutes with a systemd user timer, which then uses rclone to copy new backup files to a configurable destination. Credentials and destination settings are stored locally outside the project.

## Install the backup routine with a systemd timer

Before installing, prepare the image and credentials file as described below. The user's rootless Docker must be available as `docker.service`, with the `actual-network` network, and the Actual Budget server must be reachable. Also configure an rclone remote with write access to your chosen destination.

Create a local configuration file to set the destination independently of the storage provider:

```bash
mkdir -p "$HOME/.config/actual-budget-export"
(umask 077; touch "$HOME/.config/actual-budget-export/rclone.env")
chmod 600 "$HOME/.config/actual-budget-export/rclone.env"
```

Edit this file and add the following line, replacing `my-remote` with your remote name and adjusting the path. Local configuration and credentials stay outside the project.

```dotenv
RCLONE_DESTINATION="my-remote:backups/actual-budget"
```

Run the installer from this project directory in your user session to install the units in `~/.config/systemd/user/`, test a real backup, and enable the timer:

```bash
sh ./install-backup-systemd-timer.sh
```

The routine exports the budget through Docker, creating a ZIP in `~/backups/actual-budget`. Only after this step succeeds does it upload to the destination configured in `RCLONE_DESTINATION`. The equivalent command, using an example destination, is:

```bash
rclone copy "$HOME/backups/actual-budget" "my-remote:backups/actual-budget" --ignore-existing --verbose
```

The service does not depend on shell aliases and always uses this local directory, regardless of `BACKUP_HOST_DIR`. Files already present at the destination are skipped, even if they have changed locally. Local and remote backups are not automatically deleted.

The `actual-budget-backup.timer` timer triggers `actual-budget-backup.service` every 15 minutes, at minutes 00, 15, 30, and 45 in local time. Runs of this service do not overlap. With `Persistent=true`, a missed run is caught up when the timer becomes active again. The computer must be on. To run after logout, lingering must be enabled for the user.

Check the next scheduled run with:

```bash
systemctl --user list-timers actual-budget-backup.timer --no-pager
```

View results and errors with:

```bash
journalctl --user -u actual-budget-backup.service -n 50 --no-pager
```

If the initial test fails, the installer stops before enabling the timer. Fix the issue reported in the logs and rerun the installer. This failure does not disable a timer already enabled by an earlier installation.

To run a backup manually through the service:

```bash
systemctl --user start actual-budget-backup.service
```

To disable future scheduled runs:

```bash
systemctl --user disable --now actual-budget-backup.timer
```

## Setup and manual execution

Build the image from this directory to install the API and run the plain JavaScript script:

```bash
docker build -t actual-budget-export:local .
```

Create a private configuration file outside the project:

```bash
mkdir -p "$HOME/.config/actual-budget-export"
(umask 077; touch "$HOME/.config/actual-budget-export/backup.env")
chmod 600 "$HOME/.config/actual-budget-export/backup.env"
```

Add your values to `~/.config/actual-budget-export/backup.env` without quotes or `export` (add `ACTUAL_ENCRYPTION_PASSWORD` only for encrypted budgets):

```dotenv
ACTUAL_SERVER_URL=http://actual-server:5006
ACTUAL_PASSWORD=your-server-password
ACTUAL_SYNC_ID=your-sync-id
```

Export the ZIP to `BACKUP_HOST_DIR`, defaulting to `~/backups/actual-budget` when unset or empty:

```bash
mkdir -p "${BACKUP_HOST_DIR:-$HOME/backups/actual-budget}"

docker run --rm --network actual-network \
  --env-file "$HOME/.config/actual-budget-export/backup.env" \
  -e BACKUP_DIR=/backups \
  --mount "type=bind,source=${BACKUP_HOST_DIR:-$HOME/backups/actual-budget},target=/backups" \
  actual-budget-export:local
```

Backups use `actual-<sync-id>-20261016T211443Z.zip` (UTC), permissions `600`, and no ZIP password; the container runs as root by default.

Start an isolated test server with a random name, localhost port, and data directory under `/tmp`:

```bash
RESTORE_DATA_DIR=$(mktemp -d /tmp/actual-restore.XXXXXXXXXX)
RESTORE_CONTAINER_NAME="$(basename "$RESTORE_DATA_DIR")"

docker run --rm --detach \
  --publish 127.0.0.1::5006 \
  --mount "type=bind,source=$RESTORE_DATA_DIR,target=/data" \
  --name "$RESTORE_CONTAINER_NAME" \
  actualbudget/actual-server:latest

docker port "$RESTORE_CONTAINER_NAME" 5006/tcp
```

Open `http://<printed-address>`, import the ZIP, and compare accounts, balances, and transactions.

Stop and remove the test container in the same terminal; its data remains in `$RESTORE_DATA_DIR`:

```bash
docker stop "$RESTORE_CONTAINER_NAME"
```
