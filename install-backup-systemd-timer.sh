#!/bin/sh
set -eu

source_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
unit_dir="$HOME/.config/systemd/user"
BACKUP_SCHEDULE=${BACKUP_SCHEDULE:-'*-*-* *:00/15:00'}
export BACKUP_SCHEDULE
case "$BACKUP_SCHEDULE" in
  *'
'*) echo 'BACKUP_SCHEDULE must be a single calendar expression.' >&2; exit 1 ;;
esac
systemd-analyze calendar "$BACKUP_SCHEDULE" >/dev/null

staging_dir=$(mktemp -d)
trap 'rm -rf "$staging_dir"' EXIT
trap 'exit 1' HUP INT TERM
cp "$source_dir/systemd/actual-budget-backup.service" "$staging_dir/"
awk '/^OnCalendar=/ { print "OnCalendar=" ENVIRON["BACKUP_SCHEDULE"]; next } { print }' \
  "$source_dir/systemd/actual-budget-backup.timer" > "$staging_dir/actual-budget-backup.timer"

# Fail before installing if the user manager is unavailable.
echo 'Checking prerequisites...'
systemctl --user show-environment >/dev/null
if [ ! -r "$HOME/.config/actual-budget-backup/backup.env" ]; then
  echo 'Missing or unreadable ~/.config/actual-budget-backup/backup.env; see README.md.' >&2
  exit 1
fi
if [ ! -r "$HOME/.config/actual-budget-backup/rclone.env" ]; then
  echo 'Configure RCLONE_DESTINATION in ~/.config/actual-budget-backup/rclone.env first; see README.md.' >&2
  exit 1
fi
for dependency in docker rclone; do
  if ! command -v "$dependency" >/dev/null; then
    echo "Required command not found: $dependency" >&2
    exit 1
  fi
done
systemd-analyze --user verify "$staging_dir/actual-budget-backup.service" "$staging_dir/actual-budget-backup.timer"

echo 'Installing systemd user units...'
install -d "$unit_dir"
install -m 644 "$staging_dir/actual-budget-backup.service" "$staging_dir/actual-budget-backup.timer" "$unit_dir/"
systemctl --user daemon-reload

# Validate one real export and upload before enabling the schedule.
echo 'Running the initial backup and upload...'
if ! systemctl --user start actual-budget-backup.service; then
  echo 'Backup failed. Inspect: journalctl --user -u actual-budget-backup.service -n 50 --no-pager' >&2
  exit 1
fi
echo "Enabling backup timer with schedule: $BACKUP_SCHEDULE"
systemctl --user enable --now actual-budget-backup.timer
systemctl --user restart actual-budget-backup.timer
systemctl --user list-timers actual-budget-backup.timer --no-pager
