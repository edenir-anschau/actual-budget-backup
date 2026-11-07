# Actual Budget backup

Export ZIP backups and upload them with rclone every 30 minutes.

## 1. Install dependencies

Requires Node.js 22+, npm, rclone, systemd, and access to your Actual Budget server.
Run commands from this project directory:

```bash
npm ci --omit=dev
rclone config
```

## 2. Configure

Create private configuration files:

```bash
mkdir -p "$HOME/.config/actual-budget-backup"
(umask 077; touch "$HOME/.config/actual-budget-backup/backup.env" "$HOME/.config/actual-budget-backup/rclone.env")
chmod 600 "$HOME/.config/actual-budget-backup/backup.env" "$HOME/.config/actual-budget-backup/rclone.env"
```

Edit `~/.config/actual-budget-backup/backup.env` with your server URL and credentials:

```dotenv
ACTUAL_SERVER_URL=http://127.0.0.1:5006
ACTUAL_PASSWORD=your-server-password
ACTUAL_SYNC_ID=your-sync-id
```

For encrypted budgets, also add `ACTUAL_ENCRYPTION_PASSWORD`. Use a server URL reachable from this machine.

Edit `~/.config/actual-budget-backup/rclone.env` with your configured remote:

```dotenv
RCLONE_DESTINATION="my-remote:backups/actual-budget"
```

## 3. Install the schedule

```bash
sh ./install-backup-systemd-timer.sh
```

Runs at minutes **00 and 30**, in local time. The installer does not test the backup.
To change the schedule, rerun with a calendar expression (example: daily at 20:00):

```bash
BACKUP_SCHEDULE='*-*-* 20:00:00' sh ./install-backup-systemd-timer.sh
```

Keep this project and `node_modules` in place. After moving the project or changing Node versions, rerun `npm ci --omit=dev` and the installer.
To allow scheduled runs after logout:

```bash
loginctl enable-linger "$USER"
```

## 4. Validate manually

Follow logs in one terminal:

```bash
journalctl --user -u actual-budget-backup.service -f
```

Start a backup in another:

```bash
systemctl --user start actual-budget-backup.service
```

Confirm the ZIP exists in `~/backups/actual-budget` and at the rclone destination.
If it fails, fix the error shown in the logs and run again.

## Useful commands

```bash
# Next scheduled run
systemctl --user list-timers actual-budget-backup.timer --no-pager

# Last 50 log entries
journalctl --user -u actual-budget-backup.service -n 50 --no-pager

# Export locally without uploading
node --env-file="$HOME/.config/actual-budget-backup/backup.env" backup.mjs

# Pause the schedule
systemctl --user disable --now actual-budget-backup.timer

# Resume the schedule
systemctl --user enable --now actual-budget-backup.timer

# Uninstall the service and timer (keeps configuration and backups)
sh ./uninstall-backup-systemd-timer.sh
```

Backups are retained locally and remotely without automatic deletion. Existing remote files are skipped. ZIP files have no password; store them securely.

To validate a restore, import a ZIP into a separate Actual Budget server and compare accounts, balances, and transactions.
