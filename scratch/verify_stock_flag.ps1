$ErrorActionPreference = "Continue"
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

Write-Output "=== 1. ZSIHWEBA template fields (INLDRYRUN) ==="
Run "x3" "SELECT NUMLIG_0, FIL_0, FLD_0 FROM INLDRYRUN.AOBJEXTD WHERE EXT_0='ZSIHWEBA' ORDER BY NUMLIG_0"

Write-Output "=== 2. ZSIHWEBA template fields (INLPROD) ==="
Run "x3" "SELECT NUMLIG_0, FIL_0, FLD_0 FROM INLPROD.AOBJEXTD WHERE EXT_0='ZSIHWEBA' ORDER BY NUMLIG_0"

foreach ($sch in @("INLDRYRUN","INLPROD")) {
  Write-Output "=== 3. Invoice header flags PODSI261040466 / 463 in $sch ==="
  Run "x3" "SELECT NUM_0, SALFCY_0, STOFCY_0, STOMVTFLG_0, SIVTYP_0, INVTYP_0, STA_0, BPCINV_0 FROM $sch.SINVOICE WHERE NUM_0 IN ('PODSI261040466','PODSI261040463')"
  Write-Output "=== 4. Invoice lines in $sch ==="
  Run "x3" "SELECT NUM_0, SIDLIN_0, ITMREF_0, STOFCY_0, WRH_0, LOC_0, LOT_0, QTY_0, STOMVTFLG_0 FROM $sch.SINVOICED WHERE NUM_0 IN ('PODSI261040466')"
}

Write-Output "=== 5. Menu 1 / STOMVTFLG meaning (APLSTD) ==="
Run "x3" "SELECT NOMLOC_0, NUM_0, LAN_0, TEXTE_0 FROM INLDRYRUN.APLSTD WHERE NOMLOC_0=1 AND LAN_0='ENG' ORDER BY NUM_0"
Run "x3" "SELECT TOP 5 ZONE_0, NOMLOC_0 FROM INLDRYRUN.ADOSSIER WHERE 1=0"

Write-Output "=== 6. Field STOMVTFLG definition (menu number) ==="
Run "x3" "SELECT ZONE_0, NOMLOC_0 FROM INLDRYRUN.ADOCUMENT WHERE 1=0"

Write-Output "=== 7. Latest SOAP audit payloads for invoice (Hipo) ==="
Run "Hipo" "SELECT TOP 3 CreatedAt, Identifier, IsSuccess, LEFT(RequestPayload, 4000) AS Req FROM X3SoapAudits WHERE ActionName='ImportSalesInvoice' ORDER BY CreatedAt DESC"
