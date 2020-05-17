#!/bin/sh

set -e
# set -x

# Source config
source borg-backup-config

# Check if running as root
if [[ $(/usr/bin/id -u) -ne 0 ]]; then
    echo "Please run as root"
    exit
fi

# Quit if borg or rclone running
if pgrep --exact "borg" || pgrep --exact "rclone" >/dev/null; then
    echo "$TIMESTAMP : Backup already running, exiting" 2>&1 | tee -a $LOGFILE
    exit
    exit
fi

# Create backup
SECONDS=0
echo "$TIMESTAMP : Borg create started" 2>&1 | tee -a $LOGFILE
borg create \
    --verbose \
    --info \
    --list \
    --filter AMEx \
    --files-cache=mtime,size \
    --stats \
    --show-rc \
    --compression lz4 \
    --exclude-caches \
    $BORG_REPO::'{hostname}-{now}' \
    $SOURCE_DIR \
    >>$LOGFILE 2>&1
echo "$TIMESTAMP : Borg create finished" 2>&1 | tee -a $LOGFILE

BACKUP_EXIT=$?

# Prune backups
echo "$(date "+%m-%d-%Y %T") : Borg prune has started" 2>&1 | tee -a $LOGFILE
borg prune \
    --list \
    --prefix '{hostname}-' \
    --show-rc \
    --keep-daily $PRUNE_DAILY \
    --keep-weekly $PRUNE_WEEKLY \
    --keep-monthly $PRUNE_MONTHLY \
    >>$LOGFILE 2>&1

PRUNE_EXIT=$?
echo "$TIMESTAMP : Borg prune finished" 2>&1 | tee -a $LOGFILE

# Use highest exit code as global exit code
GLOBAL_EXIT=$((BACKUP_EXIT > PRUNE_EXIT ? BACKUP_EXIT : PRUNE_EXIT))

# Continue if no errors
if [ ${GLOBAL_EXIT} -eq 0 ]; then
    BORGSTART=$SECONDS
    echo "$TIMESTAMP : Borg backup completed in $(($BORGSTART / 3600))h:$(($BORGSTART % 3600 / 60))m:$(($BORGSTART % 60))s" | tee -a >>$LOGFILE 2>&1

    # Reset timer
    SECONDS=0
    echo "$TIMESTAMP : Rclone sync has started" >>$LOGFILE
    rclone sync $BORG_REPO $CLOUDDEST -v 2>&1 | tee -a $LOGFILE
    rclonestart=$SECONDS
    echo "$TIMESTAMP : Rclone sync completed in $(($rclonestart / 3600))h:$(($rclonestart % 3600 / 60))m:$(($rclonestart % 60))s" 2>&1 | tee -a $LOGFILE
# Error output
else
    echo "$TIMESTAMP : Borg has errors code:" $GLOBAL_EXIT 2>&1 | tee -a $LOGFILE
fi
exit ${GLOBAL_EXIT}
