$connStr = "Server=192.168.120.3\EMDATA;Database=x3;User Id=hipo;Password=3##rJtT2})4A;TrustServerCertificate=True;Connect Timeout=10;"
$conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
try {
    $conn.Open()
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = "SELECT TOP 1 * FROM INLDRYRUN.SINVOICEV WHERE NUM_0 = 'PODSI261040463'"
    $r = $cmd.ExecuteReader()
    if ($r.Read()) {
        for ($i = 0; $i -lt $r.FieldCount; $i++) {
            Write-Output "$($r.GetName($i)) = $($r.GetValue($i))"
        }
    } else {
        $r.Close()
        $cmd.CommandText = "SELECT TOP 1 * FROM INLPROD.SINVOICEV WHERE NUM_0 = 'PODSI261040463'"
        $r = $cmd.ExecuteReader()
        if ($r.Read()) {
            for ($i = 0; $i -lt $r.FieldCount; $i++) {
                Write-Output "[INLPROD] $($r.GetName($i)) = $($r.GetValue($i))"
            }
        } else {
            Write-Output "Not found in either schema"
        }
    }
    $conn.Close()
} catch {
    Write-Output "Error: $($_.Exception.Message)"
}
