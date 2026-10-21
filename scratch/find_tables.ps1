$connStr = "Server=192.168.120.3\EMDATA;Database=x3;User Id=hipo;Password=3##rJtT2})4A;TrustServerCertificate=True;Connect Timeout=10;"
$conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
try {
    $conn.Open()
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = "SELECT TABLE_SCHEMA, TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME LIKE '%AOBJ%' OR TABLE_NAME LIKE '%AOI%' OR TABLE_NAME LIKE '%AOD%'"
    $reader = $cmd.ExecuteReader()
    while ($reader.Read()) {
        Write-Output "$($reader[0]).$($reader[1])"
    }
    $conn.Close()
} catch {
    Write-Output "Error: $($_.Exception.Message)"
}
