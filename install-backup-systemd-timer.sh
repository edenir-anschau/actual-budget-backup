#!/bin/sh
set -eu

source_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
unit_dir="$HOME/.config/systemd/user"

# Fail before installing if the user manager is unavailable.
systemctl --user show-environment >/dev/null
test -r "$HOME/.config/actual-budget-export/backup.env"
if [ ! -r "$HOME/.config/actual-budget-export/rclone.env" ]; then
  echo 'Configure RCLONE_DESTINATION in ~/.config/actual-budget-export/rclone.env first; see README.md.' >&2
  exit 1
fi
command -v docker >/dev/null
command -v rclone >/dev/null
systemd-analyze --user verify "$source_dir/systemd/actual-budget-backup.service" "$source_dir/systemd/actual-budget-backup.timer"

install -d "$unit_dir"
install -m 644 "$source_dir/systemd/actual-budget-backup.service" "$source_dir/systemd/actual-budget-backup.timer" "$unit_dir/"
systemctl --user daemon-reload

# Validate one real export and upload before enabling the schedule.
systemctl --user start actual-budget-backup.service
systemctl --user enable --now actual-budget-backup.timer
systemctl --user list-timers actual-budget-backup.timer --no-pager
