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
Write-Output "=== STOCK for item 38278 @POD ==="
Run "x3" "SELECT ITMREF_0, STOFCY_0, WRH_0, LOC_0, LOT_0, STA_0, QTYSTU_0 FROM $s.STOCK WHERE ITMREF_0='38278' AND STOFCY_0='POD'"
Write-Output "=== STOCK for item 3388 @POD ==="
Run "x3" "SELECT ITMREF_0, STOFCY_0, WRH_0, LOC_0, LOT_0, STA_0, QTYSTU_0 FROM $s.STOCK WHERE ITMREF_0='3388' AND STOFCY_0='POD'"
Write-Output "=== ITMMASTER SAU/VACITM ==="
Run "x3" "SELECT ITMREF_0, SAU_0, STU_0, VACITM_0, LOTMGTCOD_0 FROM $s.ITMMASTER WHERE ITMREF_0 IN ('38278','3388')"
Write-Output "=== Sales-site POD parameters (FACILITY) ==="
Run "x3" "SELECT * FROM $s.FACILITY WHERE FCY_0='POD'"
