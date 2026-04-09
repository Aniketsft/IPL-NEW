using System;
using Microsoft.Data.SqlClient;

class Program
{
    static void Main()
    {
        string[] connectionStrings = {
            "Server=SFT-OPS1105\\ANIKET;Database=EnterpriseAuthDb;User Id=sa;Password=$0ftware;TrustServerCertificate=True;",
            "Server=SFT-OPS1105\\ANIKET;Database=InnodisTestDB;User Id=sa;Password=$0ftware;TrustServerCertificate=True;"
        };

        foreach (var connectionString in connectionStrings)
        {
            Console.WriteLine($"Testing: {connectionString.Split(';')[1]}");
            try
            {
                using (var connection = new SqlConnection(connectionString))
                {
                    connection.Open();
                    Console.WriteLine("  SUCCESS: Connected.");
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"  FAILURE: {ex.Message}");
            }
        }
    }
}
