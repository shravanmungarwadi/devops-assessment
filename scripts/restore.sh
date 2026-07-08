#!/usr/bin/env bash
#
# restore.sh - restore a backup produced by backup.sh into a FRESH database
# (not the original one), then print row counts from both so you can verify
# the restore actually worked.
#
# Usage:
#   ./scripts/restore.sh                     # restores backups/latest.sql
#   ./scripts/restore.sh path/to/backup.sql  # restores a specific file
#
# Requires: docker compose stack already running (`docker compose up -d`).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="$ROOT_DIR/backups"

if [ -f "$ROOT_DIR/.env" ]; then
  # shellcheck disable=SC1091
  set -a
  source "$ROOT_DIR/.env"
  set +a
fi

POSTGRES_DB="${POSTGRES_DB:-hotelbook}"
POSTGRES_USER="${POSTGRES_USER:-app_admin}"
DB_SERVICE_NAME="${DB_SERVICE_NAME:-db}"

BACKUP_FILE="${1:-$BACKUP_DIR/latest.sql}"
RESTORE_DB="${POSTGRES_DB}_restore_check"

if [ ! -f "$BACKUP_FILE" ]; then
  echo "ERROR: backup file not found: $BACKUP_FILE"
  echo "Run ./scripts/backup.sh first, or pass a path explicitly."
  exit 1
fi

echo "==> Checking that the '$DB_SERVICE_NAME' service is running..."
if ! docker compose ps --status running --services 2>/dev/null | grep -qx "$DB_SERVICE_NAME"; then
  echo "ERROR: the '$DB_SERVICE_NAME' service is not running. Start it first with:"
  echo "    docker compose up -d"
  exit 1
fi

echo "==> Restoring into a FRESH database: $RESTORE_DB (original '$POSTGRES_DB' is left untouched)"

echo "    - dropping $RESTORE_DB if it already exists..."
docker compose exec -T "$DB_SERVICE_NAME" \
  psql -U "$POSTGRES_USER" -d postgres -v ON_ERROR_STOP=1 \
  -c "DROP DATABASE IF EXISTS ${RESTORE_DB};"

echo "    - creating fresh database $RESTORE_DB..."
docker compose exec -T "$DB_SERVICE_NAME" \
  psql -U "$POSTGRES_USER" -d postgres -v ON_ERROR_STOP=1 \
  -c "CREATE DATABASE ${RESTORE_DB};"

echo "    - loading $BACKUP_FILE into $RESTORE_DB..."
docker compose exec -T "$DB_SERVICE_NAME" \
  psql -U "$POSTGRES_USER" -d "$RESTORE_DB" -v ON_ERROR_STOP=1 \
  < "$BACKUP_FILE" > /dev/null

echo "==> Restore complete. Verifying row counts (original vs restored):"
echo ""

compare_counts() {
  local table="$1"
  local original restored

  original="$(docker compose exec -T "$DB_SERVICE_NAME" \
    psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -A \
    -c "SELECT COUNT(*) FROM ${table};" | tr -d '[:space:]')"

  restored="$(docker compose exec -T "$DB_SERVICE_NAME" \
    psql -U "$POSTGRES_USER" -d "$RESTORE_DB" -t -A \
    -c "SELECT COUNT(*) FROM ${table};" | tr -d '[:space:]')"

  if [ "$original" = "$restored" ]; then
    printf "  [OK]   %-16s original=%-6s restored=%-6s (match)\n" "$table" "$original" "$restored"
  else
    printf "  [FAIL] %-16s original=%-6s restored=%-6s (MISMATCH)\n" "$table" "$original" "$restored"
    return 1
  fi
}

STATUS=0
compare_counts "hotel_bookings" || STATUS=1
compare_counts "booking_events" || STATUS=1

echo ""
if [ "$STATUS" -eq 0 ]; then
  echo "==> Verification PASSED: restored database '$RESTORE_DB' matches '$POSTGRES_DB' row-for-row."
else
  echo "==> Verification FAILED: row counts differ. Check the backup file and logs above."
fi

echo ""
echo "Tip: the restored database '$RESTORE_DB' is left in place for manual inspection, e.g.:"
echo "    docker compose exec $DB_SERVICE_NAME psql -U $POSTGRES_USER -d $RESTORE_DB"
echo "Drop it when you're done:"
echo "    docker compose exec $DB_SERVICE_NAME psql -U $POSTGRES_USER -d postgres -c \"DROP DATABASE ${RESTORE_DB};\""

exit "$STATUS"
