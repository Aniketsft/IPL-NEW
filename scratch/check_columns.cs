using Microsoft.Data.SqlClient;
using System;

string connectionString = "Server=localhost;Database=ScanProduction;Trusted_Connection=True;TrustServerCertificate=True;";
using (var connection = new SqlConnection(connectionString))
{
    connection.Open();
    var command = connection.CreateCommand();
    command.CommandText = "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'SalesOrders' AND COLUMN_NAME IN ('Rep0', 'Rep1', 'DeliveryRepCode')";
    using (var reader = command.ExecuteReader())
    {
        while (reader.Read())
        {
            Console.WriteLine($"COLUMN FOUND: {reader.GetString(0)}");
        }
    }
}
