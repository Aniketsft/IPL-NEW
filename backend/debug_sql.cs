using System;
using System.Data;
using Microsoft.Data.SqlClient;

string innodisConn = "Server=SFT-OPS1105\\ANIKET;Database=InnodisTestDB;User Id=sa;Password=Password123!;TrustServerCertificate=True;";
string sql = @"
SELECT * FROM (
    SELECT 
        f0.SOHNUM_0 as SohNum,
        f2.PONO_0 as PoNo,
        f0.ORDDAT_0 as OrderDate,
        f0.SHIDAT_0 as DeliveryDate,
        f0.BPCORD_0 as CustomerCode,
        c.ZFULLBUSNAM_0 as CustomerName,
        f0.REP_0 as Rep0,
        f0.REP_1 as Rep1,
        f0.SALFCY_0 as Site,
        f0.ORDSTA_0 as Status,
        'External' as Source
    FROM InnodisTestDB.INLPROD.SORDER f0
    JOIN InnodisTestDB.INLPROD.ZBTBORD f2 ON f0.SOHNUM_0 = f2.ORISONO_0
    JOIN InnodisTestDB.INLPROD.BPCUSTOMER c ON f0.BPCORD_0 = c.BPCNUM_0
    
    UNION ALL
    
    SELECT 
        EntryNumber as SohNum,
        PoNumber as PoNo,
        Date as OrderDate,
        Date as DeliveryDate,
        CustomerCode,
        CustomerName,
        Salesman1Code as Rep0,
        Salesman2Code as Rep1,
        'INTERNAL' as Site,
        1 as Status,
        'Internal' as Source
    FROM [EnterpriseAuthDb].[dbo].[CutBulkEntries]
) AS Combined
WHERE 1=1";

try {
    using (var conn = new SqlConnection(innodisConn)) {
        conn.Open();
        using (var cmd = new SqlCommand(sql, conn)) {
            using (var reader = cmd.ExecuteReader()) {
                Console.WriteLine("Query executed successfully!");
            }
        }
    }
} catch (Exception ex) {
    Console.WriteLine("SQL ERROR: " + ex.Message);
}
