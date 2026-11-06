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
Write-Output "=== K. Recent POD STD invoices: who created, flag, ship site ==="
Run "x3" "SELECT TOP 25 v.NUM_0, i.CREUSR_0, i.CREDAT_0, v.SALFCY_0, v.STOFCY_0, v.STOMVTFLG_0 FROM $s.SINVOICEV v JOIN $s.SINVOICE i ON i.NUM_0=v.NUM_0 WHERE v.SIVTYP_0='STD' AND v.SALFCY_0='POD' ORDER BY i.CREDAT_0 DESC, v.NUM_0 DESC"

Write-Output "=== L. STD invoices where ship site <> sales site (count by combos) ==="
Run "x3" "SELECT SALFCY_0, STOFCY_0, STOMVTFLG_0, COUNT(*) AS Cnt FROM $s.SINVOICEV WHERE SIVTYP_0='STD' GROUP BY SALFCY_0, STOFCY_0, STOMVTFLG_0 ORDER BY SALFCY_0, Cnt DESC"

Write-Output "=== M. Lines of recent POD STD invoices with stock flag 2: WRH/LOC/LOT ==="
Run "x3" "SELECT TOP 15 d.NUM_0, d.ITMREF_0, d.STOFCY_0, d.WRH_0, d.LOC_0, d.LOT_0 FROM $s.SINVOICED d JOIN $s.SINVOICEV v ON v.NUM_0=d.NUM_0 WHERE v.SIVTYP_0='STD' AND v.SALFCY_0='POD' AND v.STOMVTFLG_0=2 ORDER BY d.NUM_0 DESC"

Write-Output "=== N. Warehouse tables ==="
Run "x3" "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA='$s' AND (TABLE_NAME LIKE '%WAREHOUS%' OR TABLE_NAME='TABWRH' OR TABLE_NAME LIKE 'WRH%')"

Write-Output "=== O. Web user WEB2 defaults (AUTILIS) ==="
Run "x3" "SELECT LOGIN_0, USR_0, FCY_0, DEFFCY_0 FROM $s.AUTILIS WHERE LOGIN_0='WEB2'"
