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
for dependency in node rclone; do
  if ! command -v "$dependency" >/dev/null; then
    echo "Required command not found: $dependency" >&2
    exit 1
  fi
done
node_path=$(command -v node)
# Resolve and quote paths for systemd without relying on shell startup files.
# Import from the project to check that npm dependencies are installed and loadable.
(
  cd "$source_dir"
  "$node_path" --input-type=module - "$staging_dir" <<'NODE'
import { readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';

if (Number(process.versions.node.split('.')[0]) < 22) {
  throw new Error('Node.js 22 or newer is required.');
}
try {
  await import('@actual-app/api');
} catch (error) {
  console.error('Cannot load @actual-app/api. Run npm ci --omit=dev in the project directory.');
  throw error;
}
function quoteExec(value) {
  if (/[\r\n\0]/.test(value)) throw new Error('Paths must not contain line breaks or NUL.');
  return '"' + value.replaceAll('\\', '\\\\').replaceAll('"', '\\"')
    .replaceAll('%', '%%').replaceAll('$', () => '$$') + '"';
}
const template = readFileSync('systemd/actual-budget-backup.service', 'utf8');
const unit = template.replace(/@NODE@|@SCRIPT@/g, (token) => quoteExec(
  token === '@NODE@' ? process.execPath : path.resolve('backup.mjs'),
));
writeFileSync(path.join(process.argv[2], 'actual-budget-backup.service'), unit);
NODE
)
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
