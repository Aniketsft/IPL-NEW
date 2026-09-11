$connStr = "Server=192.168.120.3\EMDATA;Database=x3;User Id=hipo;Password=3##rJtT2})4A;TrustServerCertificate=True;Connect Timeout=10;"
$conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
try {
    $conn.Open()
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = "SELECT LIG_0, RECFLE_0, OBJECT_0, FOR_0, TXT_0 FROM INLPROD.AOBJIMPD WHERE MOD_0 = 'ZSIHWEBA' ORDER BY LIG_0"
    $reader = $cmd.ExecuteReader()
    while ($reader.Read()) {
        Write-Output "$($reader[0]) | $($reader[1]) | $($reader[2]) | $($reader[3]) | $($reader[4])"
    }
    $conn.Close()
} catch {
    Write-Output "Error: $($_.Exception.Message)"
}
