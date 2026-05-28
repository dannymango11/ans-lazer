#!/bin/bash
set -a
source /srv/backups/.env
source /srv/backups/services.conf
set +a
set -e

TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p $DUMP_DIR

echo "Dumping PostgreSQL..."
for entry in "${POSTGRES_DUMPS[@]}"; do
    container=$(echo $entry | cut -d: -f1)
    user=$(echo $entry | cut -d: -f2)
    db=$(echo $entry | cut -d: -f3)
    if [ "$db" = "dumpall" ]; then
        docker exec $container pg_dumpall -U $user > $DUMP_DIR/${container}_$TIMESTAMP.sql
    else
        docker exec $container pg_dump -U $user $db > $DUMP_DIR/${db}_$TIMESTAMP.sql
    fi
done

echo "Dumping MariaDB..."
for entry in "${MARIADB_DUMPS[@]}"; do
    container=$(echo $entry | cut -d: -f1)
    user=$(echo $entry | cut -d: -f2)
    db=$(echo $entry | cut -d: -f3)
    docker exec -e MYSQL_PWD=${MYSQL_PASSWORD} $container mariadb-dump -u $user $db > $DUMP_DIR/${db}_$TIMESTAMP.sql
done

echo "Dumping SQLite..."
for db in "${SQLITE_DBS[@]}"; do
    name=$(basename "$db" | sed 's/\.[^.]*$//')
    sqlite3 "$db" ".backup '$DUMP_DIR/${name}_$TIMESTAMP.db'"
done

echo "Pruning old dumps..."
find $DUMP_DIR -type f -mtime +7 -delete

echo "Running Restic backup..."
EXCLUDE_ARGS=""
for pattern in "${BACKUP_EXCLUDES[@]}"; do
    EXCLUDE_ARGS="$EXCLUDE_ARGS --exclude=$pattern"
done

restic -r $RESTIC_REPO backup $EXCLUDE_ARGS "${BACKUP_DIRS[@]}"

echo "Pruning old snapshots..."
restic -r $RESTIC_REPO forget --keep-daily 7 --keep-weekly 4 --keep-monthly 3 --prune

echo "Done."
