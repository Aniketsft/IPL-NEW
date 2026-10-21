$connStr = "Server=192.168.120.3\EMDATA;Database=x3;User Id=hipo;Password=3##rJtT2})4A;TrustServerCertificate=True;Connect Timeout=10;"
$conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
try {
    $conn.Open()
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = "SELECT NUMLIG_0, FIL_0, FLD_0, COM_0, OBL_0 FROM INLDRYRUN.AOBJEXTD WHERE EXT_0 = 'ZSIHWEBA' ORDER BY NUMLIG_0"
    $reader = $cmd.ExecuteReader()
    while ($reader.Read()) {
        Write-Output "$($reader[0]) | $($reader[1]) | $($reader[2]) | $($reader[3]) | Obligatory: $($reader[4])"
    }
    $conn.Close()
} catch {
    Write-Output "Error: $($_.Exception.Message)"
}
