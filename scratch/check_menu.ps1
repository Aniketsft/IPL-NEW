$connStr = "Server=192.168.120.3\EMDATA;Database=x3;User Id=hipo;Password=3##rJtT2})4A;TrustServerCertificate=True;Connect Timeout=10;"
$conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
try {
    $conn.Open()
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = "SELECT NOMLOC_0, NUM_0, LAN_0, TEXTE_0 FROM INLDRYRUN.APLSTD WHERE NOMLOC_0 IN (1, 280) AND LAN_0 = 'ENG' ORDER BY NOMLOC_0, NUM_0"
    $r = $cmd.ExecuteReader()
    while ($r.Read()) {
        Write-Output "Menu $($r[0]) Item $($r[1]): $($r[3])"
    }
    $conn.Close()
} catch {
    Write-Output "Error: $($_.Exception.Message)"
}
