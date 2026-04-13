$connectionString = "Server=192.168.120.3;Database=master;User Id=hipo;Password=3##rJtT2})4A;TrustServerCertificate=True;Connect Timeout=10;"
Write-Host "Testing connection to 192.168.120.3 (Default Instance)..."
try {
    $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
    $connection.Open()
    Write-Host "Success! Connected to Default Instance."
    $connection.Close()
} catch {
    Write-Host "Failed to connect to Default Instance: $($_.Exception.Message)"
}

$connectionString2 = "Server=192.168.120.3\EMDATA;Database=master;User Id=hipo;Password=3##rJtT2})4A;TrustServerCertificate=True;Connect Timeout=10;"
Write-Host "`nTesting connection to 192.168.120.3\EMDATA..."
try {
    $connection2 = New-Object System.Data.SqlClient.SqlConnection($connectionString2)
    $connection2.Open()
    Write-Host "Success! Connected to EMDATA Instance."
    $connection2.Close()
} catch {
    Write-Host "Failed to connect to EMDATA Instance: $($_.Exception.Message)"
}
