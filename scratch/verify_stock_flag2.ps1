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
Write-Output "=== A. SINVOICEV header for 466 / 463 ==="
Run "x3" "SELECT NUM_0, SALFCY_0, STOFCY_0, STOMVTFLG_0, SIVTYP_0, BPCINV_0 FROM $s.SINVOICEV WHERE NUM_0 IN ('PODSI261040466','PODSI261040463')"

Write-Output "=== B. SINVOICED lines for 466 ==="
Run "x3" "SELECT NUM_0, SIDLIN_0, ITMREF_0, STOFCY_0, WRH_0, LOC_0, QTY_0 FROM $s.SINVOICED WHERE NUM_0='PODSI261040466'"

Write-Output "=== C. Distribution of STOMVTFLG by invoice type (all SINVOICEV) ==="
Run "x3" "SELECT SIVTYP_0, STOMVTFLG_0, COUNT(*) AS Cnt FROM $s.SINVOICEV GROUP BY SIVTYP_0, STOMVTFLG_0 ORDER BY SIVTYP_0"

Write-Output "=== D. Stock Transaction flag from invoice type table ==="
Run "x3" "SELECT TOP 5 * FROM $s.TABSIVTYP WHERE SIVTYP_0='STD'"

Write-Output "=== E. Tables with LOT near invoice (SINV / SIV / STOCK*) ==="
Run "x3" "SELECT TABLE_NAME, COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='$s' AND COLUMN_NAME='LOT_0' AND (TABLE_NAME LIKE 'SINV%' OR TABLE_NAME LIKE 'SIV%' OR TABLE_NAME LIKE 'STOJOU%')"

Write-Output "=== F. APLSTD columns ==="
Run "x3" "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='$s' AND TABLE_NAME='APLSTD'"

Write-Output "=== G. Customer WIN001 default shipping site ==="
Run "x3" "SELECT BPCNUM_0, BPAADD_0, STOFCY_0 FROM $s.BPDLVCUST WHERE BPCNUM_0='WIN001'"
Write-Output "=== H. Warehouse E2 site ==="
Run "x3" "SELECT WRH_0, WRHFCY_0 FROM $s.TABWRH WHERE WRH_0 IN ('E2','CGD')"
Write-Output "=== I. Warehouses for site POD ==="
Run "x3" "SELECT WRH_0, WRHFCY_0 FROM $s.TABWRH WHERE WRHFCY_0='POD'"

Write-Output "=== J. Stock transaction flag in SINVOICE (same STOMVTFLG)? columns like STOMVT ==="
Run "x3" "SELECT TABLE_NAME, COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='$s' AND COLUMN_NAME LIKE 'STOMVT%' AND TABLE_NAME LIKE 'S%INV%'"
