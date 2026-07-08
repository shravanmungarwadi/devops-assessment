#!/usr/bin/env bash
#
# backup.sh - create a timestamped plain-SQL dump of the running database.
#
# Usage:
#   ./scripts/backup.sh
#
# Requires: docker compose stack from docker-compose.yml already running
# (`docker compose up -d`). Does NOT require psql/pg_dump on the host - the
# dump runs inside the db container.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="$ROOT_DIR/backups"

# Load environment variables (DB name/user, service name) if a .env file
# exists, falling back to the same defaults used in docker-compose.yml.
if [ -f "$ROOT_DIR/.env" ]; then
  # shellcheck disable=SC1091
  set -a
  source "$ROOT_DIR/.env"
  set +a
fi

POSTGRES_DB="${POSTGRES_DB:-hotelbook}"
POSTGRES_USER="${POSTGRES_USER:-app_admin}"
DB_SERVICE_NAME="${DB_SERVICE_NAME:-db}"

mkdir -p "$BACKUP_DIR"

TIMESTAMP="$(date -u +%Y%m%d_%H%M%S)"
BACKUP_FILE="$BACKUP_DIR/backup_${POSTGRES_DB}_${TIMESTAMP}.sql"

echo "==> Checking that the '$DB_SERVICE_NAME' service is running..."
if ! docker compose ps --status running --services 2>/dev/null | grep -qx "$DB_SERVICE_NAME"; then
  echo "ERROR: the '$DB_SERVICE_NAME' service is not running. Start it first with:"
  echo "    docker compose up -d"
  exit 1
fi

echo "==> Dumping database '$POSTGRES_DB' (user: $POSTGRES_USER) to:"
echo "    $BACKUP_FILE"

# --clean / --if-exists: makes the dump self-contained, so restoring it into
# a database that already has objects (e.g. re-running restore.sh) drops
# them first instead of erroring out on "already exists".
docker compose exec -T "$DB_SERVICE_NAME" \
  pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists \
  > "$BACKUP_FILE"

SIZE="$(du -h "$BACKUP_FILE" | cut -f1)"
echo "==> Backup complete: $BACKUP_FILE ($SIZE)"

# Keep a stable "latest" pointer so restore.sh has a sensible default.
ln -sf "$(basename "$BACKUP_FILE")" "$BACKUP_DIR/latest.sql"
echo "==> Updated pointer: $BACKUP_DIR/latest.sql -> $(basename "$BACKUP_FILE")"
