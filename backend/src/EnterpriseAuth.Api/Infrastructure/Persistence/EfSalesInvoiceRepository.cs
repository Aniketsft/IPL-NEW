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

        public async Task<IEnumerable<SalesInvoiceCustomerDto>> GetCustomersAsync()
        {
            using IDbConnection db = new SqlConnection(_connectionString);
            string sql = $@"
                SELECT 
                    LTRIM(RTRIM(BPCNUM_0)) as Code,
                    LTRIM(RTRIM(ZFULLBUSNAM_0)) as Name,
                    LTRIM(RTRIM(PTE_0)) as PaymentTerm,
                    OSTAUZ_0 as CreditLimit,
                    LTRIM(RTRIM(OSTCTL_0)) as StatusFlag
                FROM {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.BPCUSTOMER
                WHERE ZFULLBUSNAM_0 IS NOT NULL AND ZFULLBUSNAM_0 <> ''";

            return await db.QueryAsync<SalesInvoiceCustomerDto>(sql);
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

        public async Task<IEnumerable<SalesInvoiceItemStockDto>> GetItemStockDetailsAsync()
        {
            using IDbConnection db = new SqlConnection(_connectionString);
            string sql = $@"
                SELECT 
                    LTRIM(RTRIM(F0.ITMREF_0)) AS ItemCode,
                    LTRIM(RTRIM(F0.LOT_0)) AS LotNumber,
                    LTRIM(RTRIM(F1.LOC_0)) AS Location,
                    LTRIM(RTRIM(F1.WRH_0)) AS Warehouse
                FROM {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.STOLOT F0
                JOIN {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.ZSTKBYLOC F1 
                    ON F0.ITMREF_0 = F1.ITMREF_0";

            return await db.QueryAsync<SalesInvoiceItemStockDto>(sql);
        }
    }
}
