using System;
using System.Data.SqlClient;

string connStr = "Server=192.168.120.3\\EMDATA;Database=Hipo;User Id=hipo;Password=3##rJtT2})4A;TrustServerCertificate=True;";

try
{
    using (SqlConnection connection = new SqlConnection(connStr))
    {
        connection.Open();
        string sql = @"
            SELECT COLUMN_NAME, DATA_TYPE, NUMERIC_PRECISION, NUMERIC_SCALE 
            FROM INFORMATION_SCHEMA.COLUMNS 
            WHERE TABLE_NAME = 'StagingEod' AND COLUMN_NAME = 'TotalManufacturedQuantity'";
            
        using (SqlCommand command = new SqlCommand(sql, connection))
        {
            using (SqlDataReader reader = command.ExecuteReader())
            {
                while (reader.Read())
                {
                    Console.WriteLine($"{reader["COLUMN_NAME"]} - {reader["DATA_TYPE"]}({reader["NUMERIC_PRECISION"]}, {reader["NUMERIC_SCALE"]})");
                }
            }
        }
    }
}
catch (Exception ex)
{
    Console.WriteLine(ex.ToString());
}
