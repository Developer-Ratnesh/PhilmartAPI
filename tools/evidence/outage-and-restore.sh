#!/usr/bin/env bash
# PHILMART evidence: backup -> restore -> outage -> restart (client review N30,
# N23 and checklist O.1).
#
#   1. Backs up the source database (COPY_ONLY, so the normal backup chain is untouched)
#   2. Restores it under a new name and checks migrations and row counts match
#   3. With no API running (the "outage"), plants auctions that end in the next minute:
#      one with bids, one without
#   4. Waits until they are overdue, then starts the API against the restored copy
#   5. Records that the start-up sweep closed both correctly (winner + sale + email, unsold + item back)
#   6. Stops the API and drops the restored copy
#
# Local or an isolated staging server only: it needs BACKUP/RESTORE rights and
# starts its own API. Never point it at the live database.
#
#   tools/evidence/outage-and-restore.sh <api-publish-folder> <out-dir>
# Environment: PHILMART_SQL_SERVER (default localhost), SOURCE_DB (default PhilmartDev), API_PORT (default 5081)

set -euo pipefail

api_dir="${1:?API publish folder}"
out="${2:?output folder}"
server="${PHILMART_SQL_SERVER:-localhost}"
source_db="${SOURCE_DB:-PhilmartDev}"
copy_db="PhilmartRestoreCheck"
port="${API_PORT:-5081}"
mkdir -p "$out"
log="$out/O1_N23_N30_outage_and_restore.log"
: > "$log"

say() { echo "[$(date -u +%H:%M:%S)] $*" | tee -a "$log"; }
sql() { sqlcmd -S "$server" -E -C -b -I -f 65001 -h -1 -W "$@"; }

say "Source database: $server/$source_db"
backup_dir="$(sql -d master -Q "SET NOCOUNT ON; SELECT CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS NVARCHAR(400))" | tr -d '\r' | head -1)"
data_dir="$(sql -d master -Q "SET NOCOUNT ON; SELECT CAST(SERVERPROPERTY('InstanceDefaultDataPath') AS NVARCHAR(400))" | tr -d '\r' | head -1)"
bak="${backup_dir%\\}\\${source_db}_evidence_copy.bak"

say "1. Backup (COPY_ONLY) to $bak"
sql -d master -Q "BACKUP DATABASE [$source_db] TO DISK = N'$bak' WITH COPY_ONLY, INIT, CHECKSUM, STATS = 50" >> "$log"
sql -d master -Q "RESTORE VERIFYONLY FROM DISK = N'$bak' WITH CHECKSUM" >> "$log"

say "2. Restore as $copy_db"
files="$(sql -d master -s '|' -Q "SET NOCOUNT ON; RESTORE FILELISTONLY FROM DISK = N'$bak'" | tr -d '\r')"
moves=""
while IFS='|' read -r logical physical type rest; do
    [[ -z "$logical" ]] && continue
    ext="mdf"; [[ "$type" == "L" ]] && ext="ldf"
    moves+="MOVE N'$logical' TO N'${data_dir%\\}\\${copy_db}_${logical}.$ext', "
done <<< "$files"
sql -d master -Q "IF DB_ID(N'$copy_db') IS NOT NULL BEGIN ALTER DATABASE [$copy_db] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$copy_db]; END" >> "$log"
sql -d master -Q "RESTORE DATABASE [$copy_db] FROM DISK = N'$bak' WITH ${moves} REPLACE, RECOVERY, STATS = 50" >> "$log"

compare_q="SET NOCOUNT ON; EXEC sp_set_session_context N'philmart.actor_kind', N'system';
SELECT 'migrations' AS T, COUNT(*) AS N FROM dbo.SchemaMigration UNION ALL
SELECT 'buyers', COUNT(*) FROM philmart.Buy_Buyer UNION ALL
SELECT 'listings', COUNT(*) FROM philmart.List_Listing UNION ALL
SELECT 'bids', COUNT(*) FROM philmart.List_Bid UNION ALL
SELECT 'sales', COUNT(*) FROM philmart.Sale_Transaction UNION ALL
SELECT 'invoices', COUNT(*) FROM philmart.Sale_Invoice UNION ALL
SELECT 'payments', COUNT(*) FROM philmart.Sale_Payment UNION ALL
SELECT 'audit', COUNT(*) FROM philmart.Sys_AuditEvent UNION ALL
SELECT 'emails', COUNT(*) FROM philmart.Sys_EmailMessage
UNION ALL SELECT 'last migration ' + MAX(Name), 0 FROM dbo.SchemaMigration"
src_counts="$(sql -d "$source_db" -s '|' -Q "$compare_q" | tr -d '\r')"
copy_counts="$(sql -d "$copy_db" -s '|' -Q "$compare_q" | tr -d '\r')"
{ echo "source:"; echo "$src_counts"; echo "restored:"; echo "$copy_counts"; } >> "$log"
if [[ "$src_counts" != "$copy_counts" ]]; then
    say "FAIL: restored copy differs from the source"; exit 1
fi
say "   restored copy matches the source (migrations and row counts)"

say "3. Outage: no API is running against $copy_db. Planting auctions ending in 45 seconds."
plant="SET NOCOUNT ON; SET XACT_ABORT ON; EXEC sp_set_session_context N'philmart.actor_kind', N'system';
DECLARE @shop UNIQUEIDENTIFIER = (SELECT ID FROM philmart.Shop_Shop WHERE Reference = 'DEMO-001');
DECLARE @buyer UNIQUEIDENTIFIER = (SELECT TOP (1) ID FROM philmart.Buy_Buyer WHERE RegistrationCompletedAt IS NOT NULL AND DisabledAt IS NULL ORDER BY CreatedAt);
DECLARE @i1 UNIQUEIDENTIFIER = NEWID(), @i2 UNIQUEIDENTIFIER = NEWID(), @l1 UNIQUEIDENTIFIER = NEWID(), @l2 UNIQUEIDENTIFIER = NEWID(), @bid UNIQUEIDENTIFIER;
DECLARE @end DATETIMEOFFSET(7) = DATEADD(SECOND, 45, philmart.ServerNow());
INSERT INTO philmart.Item_Item (ID, ShopID, Reference, Title, State) VALUES
  (@i1, @shop, 'OUT-' + FORMAT(SYSUTCDATETIME(), 'HHmmss') + '-1', N'Outage check: with a bid', 'listed'),
  (@i2, @shop, 'OUT-' + FORMAT(SYSUTCDATETIME(), 'HHmmss') + '-2', N'Outage check: no bids', 'listed');
INSERT INTO philmart.List_Listing (ID, ShopID, ItemID, ListingType, State, Reference, StartingPriceMinor, BidIncrementMinor, StartsAt, EndsAt) VALUES
  (@l1, @shop, @i1, 'auction', 'live', 'A-OUT-' + FORMAT(SYSUTCDATETIME(), 'HHmmss') + '-1', 10000, 500, DATEADD(MINUTE, -5, philmart.ServerNow()), @end),
  (@l2, @shop, @i2, 'auction', 'live', 'A-OUT-' + FORMAT(SYSUTCDATETIME(), 'HHmmss') + '-2', 10000, 500, DATEADD(MINUTE, -5, philmart.ServerNow()), @end);
EXEC philmart.P_List_Bid_Place @l1, @buyer, 12000, 'outage-check', @bid OUTPUT;
SELECT CAST(@l1 AS VARCHAR(40)) + '|' + CAST(@l2 AS VARCHAR(40)) + '|' + CONVERT(VARCHAR(40), @end, 127);"
ids="$(sql -d "$copy_db" -Q "$plant" | tr -d '\r' | grep '|' | tail -1)"
IFS='|' read -r l1 l2 ends <<< "$ids"
say "   with bid: $l1   no bids: $l2   end: $ends"

say "4. Waiting until both are overdue (API still down)"
sleep 60
sql -d "$copy_db" -s '|' -Q "SET NOCOUNT ON; SELECT ID, State, EndsAt, ClosedAt FROM philmart.List_Listing WHERE ID IN ('$l1','$l2')" | tee -a "$log"

say "5. Restart: API on port $port against the restored copy"
export ASPNETCORE_ENVIRONMENT=Development ASPNETCORE_URLS="http://localhost:$port"
export ConnectionStrings__Philmart="Server=$server;Database=$copy_db;Integrated Security=True;TrustServerCertificate=True"
export Auth__SigningKey="outage-check-signing-key-0123456789abcdef-xyz"
( cd "$api_dir" && exec dotnet Philmart.Api.dll ) > "$out/O1_api_restart.log" 2>&1 &
api_pid=$!
for _ in $(seq 1 60); do
    curl -s -o /dev/null "http://localhost:$port/health" && break
    sleep 1
done
sleep 12
say "   API up: $(curl -s "http://localhost:$port/api/version")"

result="$(sql -d "$copy_db" -s '|' -Q "SET NOCOUNT ON; EXEC sp_set_session_context N'philmart.actor_kind', N'system';
SELECT l.Reference, l.State, CONVERT(VARCHAR(40), l.EndsAt, 127) AS EndsAt, CONVERT(VARCHAR(40), l.ClosedAt, 127) AS ClosedAt, i.State AS ItemState,
       (SELECT COUNT(*) FROM philmart.Sale_Transaction t WHERE t.ListingID = l.ID) AS Sales,
       (SELECT COUNT(*) FROM philmart.Sys_EmailMessage e JOIN philmart.Sale_Transaction t ON t.BuyerID = e.BuyerID AND t.ListingID = l.ID WHERE e.TemplateCode = 'EML-012') AS WonEmails
FROM philmart.List_Listing l JOIN philmart.Item_Item i ON i.ID = l.ItemID WHERE l.ID IN ('$l1','$l2') ORDER BY l.Reference" | tr -d '\r')"
echo "$result" | tee -a "$log"

kill "$api_pid" 2>/dev/null || true
wait "$api_pid" 2>/dev/null || true
grep -iE "auction|sweep|closed" "$out/O1_api_restart.log" | head -20 >> "$log" || true

ok=1
echo "$result" | grep -q "|sold|.*|sold_fulfilment_pending|1|1" || ok=0
echo "$result" | grep -q "|unsold|.*|ready_to_list|0|0" || ok=0

say "6. Dropping the restored copy"
sql -d master -Q "ALTER DATABASE [$copy_db] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$copy_db];" >> "$log"

if [[ $ok == 1 ]]; then
    say "PASS: restored copy matched; after the outage the restarted API closed both overdue auctions correctly in its start-up sweep."
else
    say "FAIL: see the rows above."
    exit 1
fi
