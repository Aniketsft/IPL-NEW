$connStr = "Server=192.168.120.3\EMDATA;Database=x3;User Id=hipo;Password=3##rJtT2})4A;TrustServerCertificate=True;Connect Timeout=10;"
$conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
try {
    $conn.Open()
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = "SELECT CODE_0, ENAFLG_0 FROM INLDRYRUN.ATABDIV WHERE NUMTAB_0 = 8"
    $reader = $cmd.ExecuteReader()
    while ($reader.Read()) {
        Write-Output "Code: '$($reader[0])' | ENAFLG: $($reader[1])"
    }
    $conn.Close()
} catch {
    Write-Output "Error: $($_.Exception.Message)"
}
