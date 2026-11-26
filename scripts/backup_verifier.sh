#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE=""
DRY_RUN=false
TMP_RESTORE_DIR=""

usage() {
  echo "Usage: $0 --config <path/to/backup.conf> [--dry-run]"
  exit 1
}

log_msg() {
  local level="$1"
  local message="$2"
  local timestamp
  timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
  local line="[$timestamp] [$level] $message"
  echo "$line"
  if [[ -n "${LOG_FILE:-}" ]] && [[ "$DRY_RUN" == false ]]; then
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "$line" >> "$LOG_FILE"
  fi
}

send_alert() {
  local message="$1"
  log_msg "ALERT" "$message"
  if [[ -n "${ALERT_WEBHOOK_URL:-}" ]] && command -v curl >/dev/null 2>&1; then
    curl -fsS -X POST -H "Content-Type: application/json" \
      -d "{\"text\":\"Backup Integrity Alert: $message\"}" \
      "$ALERT_WEBHOOK_URL" >/dev/null 2>&1 || true
  fi
}

cleanup() {
  if [[ -n "$TMP_RESTORE_DIR" ]] && [[ -d "$TMP_RESTORE_DIR" ]]; then
    rm -rf "$TMP_RESTORE_DIR"
  fi
}
trap cleanup EXIT

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      CONFIG_FILE="${2:-}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    *)
      usage
      ;;
  esac
done

[[ -z "$CONFIG_FILE" ]] && usage
[[ ! -f "$CONFIG_FILE" ]] && { echo "Config file not found: $CONFIG_FILE"; exit 1; }

# shellcheck disable=SC1090
source "$CONFIG_FILE"

: "${SOURCE_DIRS:?SOURCE_DIRS is required in config}"
: "${BACKUP_DIR:?BACKUP_DIR is required in config}"
: "${RETENTION_DAYS:=14}"

for cmd in tar sha256sum find; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd"
    exit 1
  fi
done

DATE_TAG="$(date '+%Y%m%d_%H%M%S')"
ARCHIVE_NAME="backup_${DATE_TAG}.tar.gz"
ARCHIVE_PATH="${BACKUP_DIR}/${ARCHIVE_NAME}"
CHECKSUM_PATH="${ARCHIVE_PATH}.sha256"

if [[ "$DRY_RUN" == true ]]; then
  log_msg "INFO" "[DRY-RUN] Would create archive: $ARCHIVE_PATH from: $SOURCE_DIRS"
  log_msg "INFO" "[DRY-RUN] Would generate SHA-256 checksum at: $CHECKSUM_PATH"
  log_msg "INFO" "[DRY-RUN] Would prune archives older than $RETENTION_DAYS days in: $BACKUP_DIR"
  exit 0
fi

mkdir -p "$BACKUP_DIR"
log_msg "INFO" "Starting backup from: $SOURCE_DIRS"

# Validate source directories exist
for dir in $SOURCE_DIRS; do
  if [[ ! -d "$dir" ]]; then
    send_alert "Source directory does not exist: $dir"
    exit 1
  fi
done

# Create compressed archive
# shellcheck disable=SC2086
if ! tar -czf "$ARCHIVE_PATH" $SOURCE_DIRS 2>/dev/null; then
  send_alert "Archive creation failed for $ARCHIVE_PATH"
  exit 1
fi

# Generate and verify SHA-256 checksum
(
  cd "$BACKUP_DIR"
  sha256sum "$ARCHIVE_NAME" > "$(basename "$CHECKSUM_PATH")"
  if ! sha256sum -c "$(basename "$CHECKSUM_PATH")" >/dev/null 2>&1; then
    send_alert "Checksum verification failed for $ARCHIVE_NAME"
    exit 1
  fi
)

# Test archive extraction into temporary folder
TMP_RESTORE_DIR="$(mktemp -d /tmp/backup_verify_XXXXXX)"
if ! tar -xzf "$ARCHIVE_PATH" -C "$TMP_RESTORE_DIR" >/dev/null 2>&1; then
  send_alert "Test restore extraction failed for $ARCHIVE_NAME"
  exit 1
fi

EXTRACTED_COUNT="$(find "$TMP_RESTORE_DIR" -type f | wc -l)"
if [[ "$EXTRACTED_COUNT" -eq 0 ]]; then
  send_alert "Archive $ARCHIVE_NAME extracted 0 files"
  exit 1
fi

log_msg "INFO" "Backup verified successfully: $ARCHIVE_NAME ($EXTRACTED_COUNT files checked)"

# Enforce retention policy
PRUNED_COUNT=0
while IFS= read -r -d '' old_file; do
  rm -f "$old_file" "${old_file}.sha256"
  PRUNED_COUNT=$((PRUNED_COUNT + 1))
done < <(find "$BACKUP_DIR" -maxdepth 1 -name "backup_*.tar.gz" -type f -mtime +"$RETENTION_DAYS" -print0)

log_msg "INFO" "Retention check complete. Pruned $PRUNED_COUNT expired archive(s) (older than ${RETENTION_DAYS}d)."
