using System;
using Microsoft.Data.SqlClient;

class Program {
    static void Main() {
        string connStr = "Server=SFT-OPS1105\\ANIKET;Database=InnodisTestDB;User Id=sa;Password=Password123!;TrustServerCertificate=True;";
        using (var conn = new SqlConnection(connStr)) {
            conn.Open();
            var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'SORDER' AND COLUMN_NAME LIKE '%QTY%'";
            using (var reader = cmd.ExecuteReader()) {
                while(reader.Read()) {
                    Console.WriteLine(reader.GetString(0));
                }
            }
        }
    }
}
