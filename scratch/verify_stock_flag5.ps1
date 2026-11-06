$srv = "192.168.120.3\EMDATA"
$pwd1 = '3##rJtT2})4A'
function Run($db, $sql) {
    $connStr = "Server=$srv;Database=$db;User Id=hipo;Password=$pwd1;TrustServerCertificate=True;Connect Timeout=10;"
    $conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
    try {
        $conn.Open()
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = $sql
        $r = $cmd.ExecuteReader()
        while ($r.Read()) {
            $row = @()
            for ($i = 0; $i -lt $r.FieldCount; $i++) { $row += "$($r.GetName($i))=$($r.GetValue($i))" }
            Write-Output ($row -join " | ")
        }
        $r.Close()
    } catch { Write-Output "ERR: $($_.Exception.Message)" }
    finally { $conn.Close() }
}
$s = "INLDRYRUN"
Write-Output "=== X. WIN001 category -> BPCCATEG.STOFCY ==="
Run "x3" "SELECT c.BPCNUM_0, c.BCGCOD_0, g.STOFCY_0 AS CategoryStoFcy FROM $s.BPCUSTOMER c LEFT JOIN $s.BPCCATEG g ON g.BCGCOD_0=c.BCGCOD_0 WHERE c.BPCNUM_0 IN ('WIN001','WIN006','WIN003')"
Write-Output "=== Y. Category STOFCY distribution ==="
Run "x3" "SELECT STOFCY_0, COUNT(*) AS Cnt FROM $s.BPCCATEG GROUP BY STOFCY_0"
Write-Output "=== Z. Warehouse table columns ==="
Run "x3" "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='$s' AND TABLE_NAME='WAREHOUSE' AND (COLUMN_NAME LIKE 'WRH%' OR COLUMN_NAME LIKE '%FCY%')"
Write-Output "=== AA. Warehouse E2 ==="
Run "x3" "SELECT WRH_0, STOFCY_0 FROM $s.WAREHOUSE WHERE WRH_0 IN ('E2','CGD','POD')"
