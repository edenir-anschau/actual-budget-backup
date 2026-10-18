#!/bin/sh
set -eu

unit_dir="$HOME/.config/systemd/user"
systemctl --user show-environment >/dev/null

# Stop scheduling before stopping a potentially active backup.
if [ -f "$unit_dir/actual-budget-backup.timer" ]; then
  systemctl --user disable --now actual-budget-backup.timer
fi
if [ -f "$unit_dir/actual-budget-backup.service" ]; then
  systemctl --user stop actual-budget-backup.service
fi
rm -f "$unit_dir/actual-budget-backup.timer" "$unit_dir/actual-budget-backup.service"
systemctl --user daemon-reload
echo 'Backup timer and service removed. Configuration, images, and backups were preserved.'
