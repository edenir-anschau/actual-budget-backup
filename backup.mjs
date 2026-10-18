import { mkdir, mkdtemp, open, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';

async function main() {
  const {
    ACTUAL_SERVER_URL: serverURL,
    ACTUAL_PASSWORD: password,
    ACTUAL_SYNC_ID: syncId,
    ACTUAL_ENCRYPTION_PASSWORD: encryptionPassword,
    BACKUP_DIR: backupDir = '/backups',
  } = process.env;

  if (!serverURL || !password || !syncId) {
    throw new Error('Set ACTUAL_SERVER_URL, ACTUAL_PASSWORD, and ACTUAL_SYNC_ID.');
  }
  if (!/^[a-zA-Z0-9_-]+$/.test(syncId)) throw new Error('Invalid ACTUAL_SYNC_ID.');

  const api = await import('@actual-app/api');
  await mkdir(backupDir, { recursive: true });
  const dataDir = await mkdtemp(path.join(tmpdir(), 'actual-backup-'));
  try {
    await api.init({ dataDir, serverURL, password });
    await api.downloadBudget(syncId, encryptionPassword ? { password: encryptionPassword } : {});
    await api.sync();
    const bytes = await api.exportBudget();
    if (!bytes.byteLength) throw new Error('The API returned an empty export.');

    const timestamp = new Date().toISOString().replace(/[-:]/g, '').replace(/\.\d{3}Z$/, 'Z');
    const file = path.resolve(backupDir, `actual-budget-${syncId}-${timestamp}.zip`);
    const handle = await open(file, 'wx', 0o600);
    try {
      await handle.writeFile(bytes);
    } catch (error) {
      await rm(file, { force: true });
      throw error;
    } finally {
      await handle.close();
    }
    console.log(`Backup saved: ${file} (${bytes.byteLength} bytes)`);
  } finally {
    try {
      await api.shutdown();
    } finally {
      await rm(dataDir, { recursive: true, force: true });
    }
  }
}

main().catch((error) => {
  let message = error instanceof Error ? error.message : String(error);
  for (const secret of [process.env.ACTUAL_PASSWORD, process.env.ACTUAL_ENCRYPTION_PASSWORD]) {
    if (secret) message = message.split(secret).join('[redacted]');
  }
  console.error(`Backup failed: ${message}`);
  process.exitCode = 1;
});
