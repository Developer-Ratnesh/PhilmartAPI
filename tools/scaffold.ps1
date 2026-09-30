<#
.SYNOPSIS
    Regenerates the EF Core entities and DbContext from the PHILMART database.

.DESCRIPTION
    The database is the source of truth. Every controlled rule is enforced there
    by constraint, trigger, filtered index or Row Level Security policy, so the
    C# model is scaffolded FROM it and never used to generate it.

    There are no EF migrations in this solution. Schema changes are made by
    adding a numbered file under 02_Database\migrations and re-running this.

.NOTES
    Scaffold as a principal that can read the catalogue — a migrator login, not
    philmart_app. philmart_app is deliberately restricted and would produce an
    incomplete model.

    After scaffolding, re-apply the hand-written notes:
      * scaffolding does not carry MS_Description across as XML doc comments,
        so the decision references have to go back on the entities that matter;
      * the generated context configures a DbSet for every table, including the
        append-only ones. Those must never be written through EF — insert via
        the stored procedures, which enforce the ordering and idempotency rules.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Server = 'localhost',

    [Parameter(Mandatory = $false)]
    [string]$Database = 'Philmart',

    [Parameter(Mandatory = $false)]
    [string]$ConnectionString
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$infrastructure = Join-Path $root 'src\Philmart.Infrastructure'
$api = Join-Path $root 'src\Philmart.Api'

if (-not $ConnectionString) {
    $ConnectionString = "Server=$Server;Database=$Database;Trusted_Connection=True;TrustServerCertificate=True;Encrypt=True"
}

Write-Host 'Scaffolding EF Core model from philmart schema...' -ForegroundColor Cyan
Write-Host "  server   : $Server"
Write-Host "  database : $Database"
Write-Host ''

Push-Location $infrastructure
try {
    dotnet ef dbcontext scaffold `
        $ConnectionString `
        Microsoft.EntityFrameworkCore.SqlServer `
        --startup-project $api `
        --context PhilmartContext `
        --context-dir Persistence `
        --context-namespace Philmart.Infrastructure.Persistence `
        --namespace Philmart.Infrastructure.Persistence.Entities `
        --output-dir Persistence\Entities `
        --schema philmart `
        --use-database-names `
        --no-onconfiguring `
        --data-annotations:$false `
        --force

    if ($LASTEXITCODE -ne 0) {
        throw "dotnet ef dbcontext scaffold failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}

Write-Host ''
Write-Host 'Scaffold complete.' -ForegroundColor Green
Write-Host ''
Write-Host 'Now do these by hand:' -ForegroundColor Yellow
Write-Host '  1. Re-add the decision-reference XML comments to the entities that carry rules'
Write-Host '     (ItemItem, ListListing, ListBid, SaleInvoice, FeeShopConfig).'
Write-Host '  2. Confirm no DbSet is used to write an append-only table. Those go'
Write-Host '     through P_List_Bid_Place, P_List_Auction_Close,'
Write-Host '     P_Sale_Fulfilment_FireFinancialTrigger and P_Sale_Payment_Allocate.'
Write-Host '  3. Run the unit tests: the Item state machine in Philmart.Domain must'
Write-Host '     still agree with philmart.Item_TransitionRule.'
Write-Host '  4. dotnet build'
