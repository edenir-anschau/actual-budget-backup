# Actual Budget backup

## 1. Prepare the prerequisites

Install Docker, rclone, and systemd, and make the Actual Budget server accessible. This setup uses the user's rootless `docker.service` and the Docker network `actual-network`. Configure an rclone remote with write access to your chosen destination. Run the following commands from this project directory.

## 2. Build the backup image

Build the image to export timestamped ZIP backups by directly calling the Actual API's `exportBudget()` method:

```bash
docker build -t actual-budget-backup:local .
```

## 3. Configure the Actual Budget credentials

Create private configuration files outside the project:

```bash
mkdir -p "$HOME/.config/actual-budget-backup"
(umask 077; touch "$HOME/.config/actual-budget-backup/backup.env" "$HOME/.config/actual-budget-backup/rclone.env")
chmod 600 "$HOME/.config/actual-budget-backup/backup.env" "$HOME/.config/actual-budget-backup/rclone.env"
```

Edit `~/.config/actual-budget-backup/backup.env` and add your values without quotes or `export`. Add `ACTUAL_ENCRYPTION_PASSWORD` only for encrypted budgets:

```dotenv
ACTUAL_SERVER_URL=http://actual-server:5006
ACTUAL_PASSWORD=your-server-password
ACTUAL_SYNC_ID=your-sync-id
```

If upgrading from the previous project name, copy your existing credentials and destination settings from the previous configuration directory into this new directory before continuing. Rebuild the image using the new name in step 2.

## 4. Configure the rclone destination

Edit `~/.config/actual-budget-backup/rclone.env`, replacing `my-remote` and the destination path with your settings:

```dotenv
RCLONE_DESTINATION="my-remote:backups/actual-budget"
```

The service exports to `~/backups/actual-budget` and then copies new files to this destination using `--ignore-existing`. A failed export prevents the upload. Existing destination files are skipped, even if changed locally. Local and remote backups are retained without automatic deletion.

## 5. Install the service and choose the schedule

Run the installer in your user session to install the units, perform one real export and upload, and enable the timer. The default schedule runs every 15 minutes, at minutes 00, 15, 30, and 45 in local time:

```bash
sh ./install-backup-systemd-timer.sh
```

To choose a different schedule, set `BACKUP_SCHEDULE` to a systemd calendar expression. For example, run every 30 minutes:

```bash
BACKUP_SCHEDULE='*-*-* *:00/30:00' sh ./install-backup-systemd-timer.sh
```

For a daily backup at 20:00, use `BACKUP_SCHEDULE='*-*-* 20:00:00'`. Rerun the installer with your desired schedule to update an existing installation; this also performs a real backup. Running it without `BACKUP_SCHEDULE` restores the 15-minute default.

If the initial backup fails, inspect the logs in step 6, fix the issue, and rerun the installer. A timer enabled by a previous installation remains enabled if this test fails.

The units are installed in `~/.config/systemd/user/`. Runs do not overlap. `Persistent=true` catches up one missed run when the timer becomes active again. The computer must be on; user lingering must be enabled to run after logout. The service always uses `~/backups/actual-budget`, regardless of `BACKUP_HOST_DIR` or shell aliases.

## 6. Check the schedule and logs

Check the next scheduled run:

```bash
systemctl --user list-timers actual-budget-backup.timer --no-pager
```

Read backup results and errors:

```bash
journalctl --user -u actual-budget-backup.service -n 50 --no-pager
```

## 7. Run a backup manually when needed

Start the service to export a new ZIP and upload new files:

```bash
systemctl --user start actual-budget-backup.service
```

ZIP filenames contain the budget sync ID and a UTC timestamp. Files use permissions `600` and have no ZIP password. The container runs as root by default; rootless Docker maps this to the host user.

## 8. Test a restore

Start an isolated Actual Budget server with a temporary data directory and a random localhost port:

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

Open `http://<printed-address>`, import a backup ZIP, and compare accounts, balances, and transactions. Stop the test server in the same terminal when finished; its data remains in the temporary directory:

```bash
docker stop "$RESTORE_CONTAINER_NAME"
```

## 9. Remove the scheduled routine when needed

Run the uninstaller to disable and stop the timer, stop the service, remove both user unit files, and reload the user manager:

```bash
sh ./uninstall-backup-systemd-timer.sh
```

Configuration files, Docker images, and local and remote backups are preserved. Removing the service may interrupt an active backup. To pause scheduling without removing the units, use:

```bash
systemctl --user disable --now actual-budget-backup.timer
```
