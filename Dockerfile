FROM node:22-bookworm
WORKDIR /app
RUN npm install --omit=dev --no-audit --no-fund @actual-app/api@26.10.0
COPY backup.mjs ./
ENV BACKUP_DIR=/backups
ENTRYPOINT ["node", "backup.mjs"]
