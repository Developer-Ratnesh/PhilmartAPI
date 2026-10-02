#!/usr/bin/env bash
# Applies database/migrations/*.sql in order (Delivery Plan task T05).
#
# Each migration runs once through sqlcmd, which honours the GO separators the
# files rely on. Applied migrations are recorded in dbo.SchemaMigration with
# their SHA-256; if an applied file has since changed the run stops, because a
# migration that has shipped is corrected by a new migration, never by editing.
#
# Environment:
#   PHILMART_SQL_SERVER    default localhost
#   PHILMART_SQL_DATABASE  default Philmart (created if missing)
#   PHILMART_SQL_USER      SQL login; omit to use Windows authentication
#   PHILMART_SQL_PASSWORD
#
# Run as philmart_migrator or db_owner. 010_seed refuses to run as philmart_app.

set -euo pipefail

server="${PHILMART_SQL_SERVER:-localhost}"
database="${PHILMART_SQL_DATABASE:-Philmart}"
# Work from the migrations folder: the Windows ODBC sqlcmd misreads absolute
# Git Bash paths (/c/...), so files are always passed by relative name.
cd "$(dirname "$0")/migrations"

auth=(-E)
if [[ -n "${PHILMART_SQL_USER:-}" ]]; then
    auth=(-U "$PHILMART_SQL_USER" -P "${PHILMART_SQL_PASSWORD:?PHILMART_SQL_PASSWORD is required with PHILMART_SQL_USER}")
fi

# -b fails the run on the first error, -f 65001 reads the UTF-8 files correctly
# (accented controlled names), -I sets QUOTED_IDENTIFIER for filtered indexes.
sql() {
    sqlcmd -S "$server" "${auth[@]}" -C -b -f 65001 -I "$@"
}

sql -d master -Q "IF DB_ID(N'$database') IS NULL CREATE DATABASE [$database];"

sql -d "$database" -Q "
IF OBJECT_ID(N'dbo.SchemaMigration') IS NULL
CREATE TABLE dbo.SchemaMigration (
    Name       NVARCHAR(200)     NOT NULL CONSTRAINT PK_SchemaMigration PRIMARY KEY,
    Sha256     CHAR(64)          NOT NULL,
    AppliedAt  DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_SchemaMigration_AppliedAt DEFAULT (SYSDATETIMEOFFSET())
);"

applied=0
for name in *.sql; do
    hash="$(sha256sum "$name" | cut -d' ' -f1)"

    recorded="$(sql -d "$database" -h -1 -W -Q "SET NOCOUNT ON; SELECT Sha256 FROM dbo.SchemaMigration WHERE Name = N'$name';" | tr -d '[:space:]')"

    if [[ -n "$recorded" ]]; then
        if [[ "$recorded" != "$hash" ]]; then
            echo "ERROR: $name was applied with SHA-256 $recorded but the file is now $hash." >&2
            echo "       Applied migrations must not be edited; add a new migration instead." >&2
            exit 1
        fi
        echo "skip   $name"
        continue
    fi

    echo "apply  $name"
    sql -d "$database" -i "$name"
    sql -d "$database" -Q "INSERT INTO dbo.SchemaMigration (Name, Sha256) VALUES (N'$name', '$hash');"
    applied=$((applied + 1))
done

echo "Done: $applied migration(s) applied to $database on $server."
