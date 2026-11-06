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
Write-Output "=== P. Customer-side tables having a ship/stock site column ==="
Run "x3" "SELECT TABLE_NAME, COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='$s' AND (COLUMN_NAME LIKE '%STOFCY%' OR COLUMN_NAME LIKE 'DEFFCY%') AND (TABLE_NAME LIKE 'BP%' OR TABLE_NAME LIKE 'AUTIL%' OR TABLE_NAME LIKE 'TABSALFCY%' OR TABLE_NAME LIKE 'FACILITY')"

Write-Output "=== Q. BPCUSTOMER columns with FCY ==="
Run "x3" "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='$s' AND TABLE_NAME='BPCUSTOMER' AND COLUMN_NAME LIKE '%FCY%'"
Write-Output "=== R. BPCUSTOMER values WIN001 / WIN006 ==="
Run "x3" "SELECT BPCNUM_0, BPCINV_0, BPCPYR_0, BPCGRU_0 FROM $s.BPCUSTOMER WHERE BPCNUM_0 IN ('WIN001','WIN006')"
Write-Output "=== S. BPDLVCUST columns ==="
Run "x3" "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='$s' AND TABLE_NAME='BPDLVCUST' AND (COLUMN_NAME LIKE '%FCY%' OR COLUMN_NAME LIKE '%WRH%')"
Write-Output "=== T. BPDLVCUST WIN001 full ==="
Run "x3" "SELECT * FROM $s.BPDLVCUST WHERE BPCNUM_0='WIN001'"

Write-Output "=== U. AUTILIS columns with FCY ==="
Run "x3" "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='$s' AND TABLE_NAME='AUTILIS' AND COLUMN_NAME LIKE '%FCY%'"
Write-Output "=== V. WAREHOUSE E2 ==="
Run "x3" "SELECT WAH_0, WRHFCY_0 FROM $s.WAREHOUSE WHERE WAH_0 IN ('E2','CGD')"
Run "x3" "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='$s' AND TABLE_NAME='WAREHOUSE' AND COLUMN_NAME LIKE '%FCY%'"

Write-Output "=== W. Site POD / CGD ==="
Run "x3" "SELECT FCY_0, FCYSHO_0, STOFCY_0 FROM $s.FACILITY WHERE FCY_0 IN ('POD','CGD')"
Run "x3" "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='$s' AND TABLE_NAME='FACILITY' AND (COLUMN_NAME LIKE '%FCY%' OR COLUMN_NAME LIKE '%STO%')"
