# Automated Backup & Integrity Verifier

A lightweight, dependency-free Bash automation utility for creating compressed backups, enforcing retention policies, generating **SHA-256** checksums, and automatically validating archive integrity via test extraction before alerting.

## Why This Exists
A backup is only useful if it can be verified and restored reliably. This script automates routine archival while adding a post-backup integrity check to catch silent corruption or incomplete archives early.

## Key Features
- **Compressed Archives:** Creates timestamped `.tar.gz` archives from one or more target directories.
- **Checksum Generation & Verification:** Generates a `.sha256` manifest and validates it immediately after creation.
- **Restore Sanity Check:** Extracts the archive into a temporary directory and verifies file count/readability before cleaning up.
- **Retention Policy:** Automatically purges old archives beyond a configurable retention window (`RETENTION_DAYS`).
- **Structured Logging & Alerting:** Writes timestamped logs and supports an optional webhook/alert hook on failure.

## Usage
1. Copy the sample configuration and adjust paths and retention settings:
   ```bash
   cp config/backup.conf.example config/backup.conf

   ```
   ## Run manually or schedule via cron:
   
    ```bash
    ./scripts/backup_verifier.sh --config ./config/backup.conf
   ```
## Test mode (dry-run / verbose check without deleting old backups):

 ```bash
    ./scripts/backup_verifier.sh --config ./config/backup.conf --dry-run
 ```
