using System;
using System.Collections.Generic;
using System.Data;
using System.Linq;
using System.Threading.Tasks;
using Dapper;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Options;
using Microsoft.EntityFrameworkCore;
using EnterpriseAuth.Api.Core.Domain.Entities;
using EnterpriseAuth.Api.Core.Application.Common;
using EnterpriseAuth.Api.Core.Application.Interfaces;
using EnterpriseAuth.Api.Core.Application.DTOs;

namespace EnterpriseAuth.Api.Infrastructure.Persistence
{
    public class EfSalesInvoiceRepository : ISalesInvoiceRepository
    {
        private readonly string _connectionString;
        private readonly ScanProductionDbContext _scanContext;
        private readonly SyncSettings _syncSettings;
        private readonly IX3SchemaProvider _schemaProvider;

        public EfSalesInvoiceRepository(IConfiguration configuration, ScanProductionDbContext scanContext, IOptions<SyncSettings> syncSettings, IX3SchemaProvider schemaProvider)
        {
            _connectionString = configuration.GetConnectionString("Innodis") 
                                ?? throw new ArgumentNullException("Innodis connection string is missing");
            _scanContext = scanContext;
            _syncSettings = syncSettings.Value;
            _schemaProvider = schemaProvider;
        }

        public async Task<IEnumerable<SalesInvoiceCustomer>> GetCustomersAsync()
        {
            return await _scanContext.SalesInvoiceCustomers
                .OrderBy(c => c.Name)
                .AsNoTracking()
                .ToListAsync();
        }

        public async Task SyncCustomersFromX3Async()
        {
            using IDbConnection db = new SqlConnection(_connectionString);
            string sql = $@"
                SELECT DISTINCT 
                    LTRIM(RTRIM(BPCNUM_0)) as Code,
                    LTRIM(RTRIM(ZFULLBUSNAM_0)) as Name,
                    BCGCOD_0 as PaymentTerm,
                    OSTAUZ_0 as CreditLimit,
                    OSTCTL_0 as StatusFlag
                FROM {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.BPCUSTOMER
                WHERE ZFULLBUSNAM_0 IS NOT NULL AND ZFULLBUSNAM_0 <> ''";

            Console.WriteLine($"[Bug Hunter] Executing SQL: {sql}");

            var x3Customers = (await db.QueryAsync<SalesInvoiceCustomer>(sql)).ToList();

            Console.WriteLine($"[Bug Hunter] Retrieved {x3Customers.Count} customers from X3 via Dapper.");

            var existingCustomers = await _scanContext.SalesInvoiceCustomers.ToDictionaryAsync(c => c.Code);
            var now = DateTime.UtcNow;

            int insertCount = 0;
            int updateCount = 0;

            foreach (var x3Cust in x3Customers)
            {
                if (existingCustomers.TryGetValue(x3Cust.Code, out var existing))
                {
                    existing.Name = x3Cust.Name;
                    existing.PaymentTerm = x3Cust.PaymentTerm;
                    existing.CreditLimit = x3Cust.CreditLimit;
                    existing.StatusFlag = x3Cust.StatusFlag;
                    existing.UpdatedAt = now;
                    existing.IsProcessed = true;
                    updateCount++;
                }
                else
                {
                    x3Cust.CreatedAt = now;
                    x3Cust.UpdatedAt = now;
                    x3Cust.IsProcessed = true;
                    _scanContext.SalesInvoiceCustomers.Add(x3Cust);
                    insertCount++;
                }
            }

            Console.WriteLine($"[Bug Hunter] Planned {insertCount} inserts and {updateCount} updates. Saving changes...");
            await _scanContext.SaveChangesAsync();
            Console.WriteLine($"[Bug Hunter] SaveChangesAsync completed successfully.");
        }

        public async Task<IEnumerable<SalesInvoiceProductDto>> GetProductsAsync(string sitecode)
        {
            using IDbConnection db = new SqlConnection(_connectionString);
            string sql = $@"
                SELECT 
                    LTRIM(RTRIM(itm.ITMREF_0)) AS Sku,
                    LTRIM(RTRIM(itm.ZFULLDES_0)) AS Name,
                    COALESCE(stk.QTYSTU_0, 0) AS StockQty,
                    LTRIM(RTRIM(stk.WRH_0)) AS Warehouse,
                    LTRIM(RTRIM(itm.STU_0)) AS StockUnit
                FROM {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.ITMMASTER itm
                LEFT JOIN {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.ZSTKBYLOC stk 
                    ON itm.ITMREF_0 = stk.ITMREF_0
                WHERE 
                    itm.ITMSTA_0 = 1;";

            return await db.QueryAsync<SalesInvoiceProductDto>(sql, new { sitecode });
        }
    }
}
