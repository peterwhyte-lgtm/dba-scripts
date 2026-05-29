<#
.SYNOPSIS
Drops databases that match a test prefix.

.DESCRIPTION
Useful for lab cleanup and repeatable test environment setup.
#>

param(
    [string]$SqlInstance = '.',
    [string]$Prefix = 'testdb'
)

$server = New-Object Microsoft.SqlServer.Management.Smo.Server($SqlInstance)

foreach ($db in $server.Databases | Where-Object { $_.Name -like "$Prefix*" }) {
    try {
        if ($db.IsAccessible) {
            $db.Drop()
            Write-Host "Dropped $($db.Name)" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Warning "Could not drop $($db.Name): $($_.Exception.Message)"
    }
}
