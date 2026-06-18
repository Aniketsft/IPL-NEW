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
                    LTRIM(RTRIM(c.BPCNUM_0)) as Code,
                    LTRIM(RTRIM(c.ZFULLBUSNAM_0)) as Name,
                    LTRIM(RTRIM(c.PTE_0)) as PaymentTerm,
                    c.OSTAUZ_0 as CreditLimit,
                    LTRIM(RTRIM(c.OSTCTL_0)) as StatusFlag,
                    LTRIM(RTRIM(c.VACBPR_0)) as TaxRule,
                    COALESCE(g.OutstandingBalance, 0) as OutstandingBalance
                FROM {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.BPCUSTOMER c
                LEFT JOIN (
                    SELECT 
                        BPR_0, 
                        SUM(AMTCUR_0 - PAYCUR_0) as OutstandingBalance 
                    FROM {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.GACCDUDATE 
                    WHERE (AMTCUR_0 - PAYCUR_0) > 0 AND BPRTYP_0 = 1
                    GROUP BY BPR_0
                ) g ON c.BPCNUM_0 = g.BPR_0
                WHERE c.ZFULLBUSNAM_0 IS NOT NULL AND c.ZFULLBUSNAM_0 <> ''";

            return await db.QueryAsync<SalesInvoiceCustomerDto>(sql);
        }

        public async Task<IEnumerable<SalesInvoiceProductDto>> GetProductsAsync(string sitecode)
        {
            using IDbConnection db = new SqlConnection(_connectionString);
            string sql = $@"
                SELECT 
                    LTRIM(RTRIM(itm.ITMREF_0)) AS Sku,
                    LTRIM(RTRIM(itm.ZFULLDES_0)) AS Name,
                    LTRIM(RTRIM(itm.SAU_0)) AS SalesUnit,
                    SUM(COALESCE(stk.QTYSTU_0, 0)) AS StockQty
                FROM {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.ITMMASTER itm
                LEFT JOIN {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.ZSTKBYLOC stk 
                    ON itm.ITMREF_0 = stk.ITMREF_0
                WHERE 
                    itm.ITMSTA_0 = 1
                GROUP BY 
                    LTRIM(RTRIM(itm.ITMREF_0)),
                    LTRIM(RTRIM(itm.ZFULLDES_0)),
                    LTRIM(RTRIM(itm.SAU_0));";

            return await db.QueryAsync<SalesInvoiceProductDto>(sql, new { sitecode });
        }

        public async Task<IEnumerable<SalesInvoiceItemStockDto>> GetItemStockDetailsAsync()
        {
            using IDbConnection db = new SqlConnection(_connectionString);
            string sql = $@"
                SELECT 
                    LTRIM(RTRIM(zlw.WAREHOUSE_0)) AS Warehouse, 
                    LTRIM(RTRIM(zlw.WRHNAM_0)) AS WarehouseName, 
                    LTRIM(RTRIM(zlw.LOCATION_0)) AS Location, 
                    LTRIM(RTRIM(zlw.LOCTYPNAM_0)) AS LocationType,
                    LTRIM(RTRIM(itm.ITMREF_0)) AS ItemCode,
                    LTRIM(RTRIM(itm.ITMDES1_0)) AS ItemName,  
                    SUM(COALESCE(stk.QTYSTU_0, 0)) AS TotalQty,
                    LTRIM(RTRIM(stk.LOT_0)) AS LotNumber,
                    LTRIM(RTRIM(itm.VACITM_0)) AS TaxLevel
                FROM {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.ITMMASTER itm
                LEFT JOIN {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.ZSTKBYLOC zsbl 
                    ON itm.ITMREF_0 = zsbl.ITMREF_0
                LEFT JOIN {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.ZLOCWRH zlw 
                    ON zsbl.WRH_0 = zlw.WAREHOUSE_0 AND zsbl.LOC_0 = zlw.LOCATION_0
                LEFT JOIN {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.STOCK stk 
                    ON zsbl.WRH_0 = stk.STOFCY_0 AND zsbl.LOC_0 = stk.LOC_0 AND zsbl.ITMREF_0 = stk.ITMREF_0 AND stk.STA_0 = 'A'
                LEFT JOIN {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.STOLOT sl 
                    ON stk.ITMREF_0 = sl.ITMREF_0 AND stk.LOT_0 = sl.LOT_0
                WHERE itm.ITMSTA_0 = 1
                GROUP BY 
                    zlw.WAREHOUSE_0, zlw.WRHNAM_0, zlw.LOCATION_0, zlw.LOCTYPNAM_0,
                    itm.ITMREF_0, itm.ITMDES1_0, stk.LOT_0, itm.VACITM_0
                ORDER BY 
                    zlw.WAREHOUSE_0, itm.ITMREF_0, stk.LOT_0";

            return await db.QueryAsync<SalesInvoiceItemStockDto>(sql);
        }
    }
}
