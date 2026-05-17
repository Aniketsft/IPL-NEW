using System;
using System.Data;
using System.Diagnostics;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.Data.SqlClient;
using Dapper;

class Program
{
    static async Task Main()
    {
        string connStr = "Data Source=172.26.106.44;Initial Catalog=InnodisTestDB;User ID=sa;Password=your_password;TrustServerCertificate=True"; 
        // Note: I don't have the password, but I can try to use what's in appsettings if I could read it.
        // Actually, I'll just look at the appsettings.json
    }
}
