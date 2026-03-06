using System;
using System.Collections.Generic;
using System.Data;
using System.Linq;
using System.Threading.Tasks;
using Dapper;
using EnterpriseAuth.Api.Core.Application.DTOs;
using EnterpriseAuth.Api.Core.Domain.Interfaces;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;

namespace EnterpriseAuth.Api.Infrastructure.Persistence
{
    public class EfLogisticsRepository : ILogisticsRepository
    {
        private readonly string _connectionString;

        public EfLogisticsRepository(IConfiguration configuration)
        {
            _connectionString = configuration.GetConnectionString("Innodis") 
                                ?? throw new System.ArgumentNullException("Innodis connection string is missing");
        }

        public async Task<IEnumerable<ProductionTrackingDto>> GetProductionTrackingAsync()
        {
            using IDbConnection db = new SqlConnection(_connectionString);
            
            string sql = @"
                SELECT TOP 100
                    LTRIM(RTRIM(f2.ITMREF_0)) as ItemCode,
                    LTRIM(RTRIM(f2.ITMDES1_0)) as Description,
                    SUM(f1.QTY_0) as Quantity
                FROM InnodisTestDB.INLPROD.SORDER f0
                JOIN InnodisTestDB.INLPROD.SORDERQ f1 on f0.SOHNUM_0 = f1.SOHNUM_0
                JOIN InnodisTestDB.INLPROD.ITMMASTER f2 on f1.ITMREF_0 = f2.ITMREF_0
                GROUP BY f2.ITMREF_0, f2.ITMDES1_0
                ORDER BY Quantity DESC";

            return await db.QueryAsync<ProductionTrackingDto>(sql);
        }

        public async Task<IEnumerable<SalesOrderHeaderDto>> GetSalesOrderHeadersAsync(int? status, DateTime? date, string? customerCode)
        {
            using IDbConnection db = new SqlConnection(_connectionString);

            var sql = @"
                SELECT 
                    f0.SOHNUM_0 as SohNum,
                    f2.PONO_0 as PoNo,
                    f0.ORDDAT_0 as OrderDate,
                    f0.SHIDAT_0 as DeliveryDate,
                    f0.BPCORD_0 as CustomerCode,
                    c.ZFULLBUSNAM_0 as CustomerName,
                    f0.REP_0 as Rep0,
                    f0.REP_1 as Rep1,
                    f0.ORDSTA_0 as Status
                FROM InnodisTestDB.INLPROD.SORDER f0
                JOIN InnodisTestDB.INLPROD.ZBTBORD f2 ON f0.SOHNUM_0 = f2.ORISONO_0
                JOIN InnodisTestDB.INLPROD.BPCUSTOMER c ON f0.BPCORD_0 = c.BPCNUM_0
                WHERE 1=1";

            var parameters = new DynamicParameters();

            if (status.HasValue)
            {
                sql += " AND f0.ORDSTA_0 = @Status";
                parameters.Add("Status", status.Value);
            }

            if (date.HasValue)
            {
                sql += " AND f0.SHIDAT_0 = @Date";
                parameters.Add("Date", date.Value.Date);
            }

            if (!string.IsNullOrEmpty(customerCode))
            {
                sql += " AND f0.BPCORD_0 = @CustomerCode";
                parameters.Add("CustomerCode", customerCode);
            }

            sql += " ORDER BY f0.ORDDAT_0 DESC";

            return await db.QueryAsync<SalesOrderHeaderDto>(sql, parameters);
        }

        public async Task<int> SyncScansAsync(IEnumerable<ScanDto> scans)
        {
            if (scans == null || !scans.Any()) return 0;

            using IDbConnection db = new SqlConnection(_connectionString);
            
            // Note: We use EnterpriseAuthDb for scans if it's the sync destination
            // However, the connection string used here is "Innodis".
            // If scans go to EnterpriseAuthDb, we might need a different connection.
            // For now, keeping consistent with previous logic but ensuring it compiles.
            
            const string sql = @"
                INSERT INTO [EnterpriseAuthDb].[dbo].[MobileAppScans] 
                (SoNumber, ItemCode, ScannedQuantity, ScannedAt, ScannedBy, DeviceId)
                VALUES (@SoNumber, @ItemCode, @ScannedQuantity, @ScannedAt, @ScannedBy, @DeviceId)";

            int totalRows = 0;
            foreach (var scan in scans)
            {
                totalRows += await db.ExecuteAsync(sql, scan);
            }
            return totalRows;
        }
    }
}
