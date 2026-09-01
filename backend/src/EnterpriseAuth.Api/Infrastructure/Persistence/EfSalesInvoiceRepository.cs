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
                    LTRIM(RTRIM(c.BCGCOD_0)) as Bcgcod,
                    LTRIM(RTRIM(c.TSCCOD_0)) as Tsccod,
                    c.BETFCY_0 as FacilityFlag,
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
                LEFT JOIN {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.STOCK stk 
                    ON itm.ITMREF_0 = stk.ITMREF_0 AND stk.STA_0 = 'A'
                LEFT JOIN {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.STOLOT sl 
                    ON stk.ITMREF_0 = sl.ITMREF_0 AND stk.LOT_0 = sl.LOT_0
                WHERE 
                    itm.ITMSTA_0 = 1
                    AND (sl.SHLDAT_0 IS NULL OR sl.SHLDAT_0 >= CAST(GETDATE() AS DATE))
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
                    LTRIM(RTRIM(stk.STOFCY_0)) AS Warehouse, 
                    LTRIM(RTRIM(zlw.WRHNAM_0)) AS WarehouseName, 
                    LTRIM(RTRIM(stk.LOC_0)) AS Location, 
                    LTRIM(RTRIM(zlw.LOCTYPNAM_0)) AS LocationType,
                    LTRIM(RTRIM(itm.ITMREF_0)) AS ItemCode,
                    LTRIM(RTRIM(itm.ITMDES1_0)) AS ItemName,  
                    SUM(COALESCE(stk.QTYSTU_0, 0)) AS TotalQty,
                    LTRIM(RTRIM(stk.LOT_0)) AS LotNumber,
                    LTRIM(RTRIM(itm.VACITM_0)) AS TaxLevel,
                    LTRIM(RTRIM(itm.CCE_0)) AS Cce0
                FROM {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.ITMMASTER itm
                LEFT JOIN {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.STOCK stk 
                    ON itm.ITMREF_0 = stk.ITMREF_0 AND stk.STA_0 = 'A'
                LEFT JOIN {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.ZLOCWRH zlw 
                    ON stk.STOFCY_0 = zlw.WAREHOUSE_0 AND stk.LOC_0 = zlw.LOCATION_0
                LEFT JOIN {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.STOLOT sl 
                    ON stk.ITMREF_0 = sl.ITMREF_0 AND stk.LOT_0 = sl.LOT_0
                WHERE itm.ITMSTA_0 = 1 
                  AND (sl.SHLDAT_0 IS NULL OR sl.SHLDAT_0 >= CAST(GETDATE() AS DATE))
                GROUP BY 
                    stk.STOFCY_0, zlw.WRHNAM_0, stk.LOC_0, zlw.LOCTYPNAM_0,
                    itm.ITMREF_0, itm.ITMDES1_0, stk.LOT_0, itm.VACITM_0, itm.CCE_0
                ORDER BY 
                    stk.STOFCY_0, itm.ITMREF_0, stk.LOT_0";

            return await db.QueryAsync<SalesInvoiceItemStockDto>(sql);
        }

        public async Task<IEnumerable<TaxMatrixDto>> GetTaxDeterminationsAsync()
        {
            using IDbConnection db = new SqlConnection(_connectionString);
            string sql = $@"
                SELECT 
                    LTRIM(RTRIM(VACBPR_0)) AS CustomerTaxRule,
                    LTRIM(RTRIM(VACITM_0)) AS ItemTaxLevel,
                    VAT_0 AS TaxCode
                FROM {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.TABVAC WITH (NOLOCK)";
            return await db.QueryAsync<TaxMatrixDto>(sql);
        }

        public async Task<IEnumerable<TaxRateDto>> GetTaxRatesAsync()
        {
            using IDbConnection db = new SqlConnection(_connectionString);
            string sql = $@"
                SELECT 
                    VAT_0 AS TaxCode,
                    LTRIM(RTRIM(VATDES_0)) AS Description,
                    VATRAT_0 AS TaxRatePercent
                FROM {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.TABVAT WITH (NOLOCK)";
            return await db.QueryAsync<TaxRateDto>(sql);
        }

        public async Task<IEnumerable<PriceListDto>> GetPriceListsAsync()
        {
            using IDbConnection db = new SqlConnection(_connectionString);
            string schema = _schemaProvider.GetSchemaName();
            if (string.IsNullOrEmpty(schema) || schema == "INLDRYRUN") 
            {
                // To adhere strictly to no-fallback rule if the header is not provided properly, 
                // but if we want to ensure we get the explicit one. 
                // Let's just trust _schemaProvider.GetSchemaName() and use it.
            }
            
            string sql = $@"
                SELECT 
                    LTRIM(RTRIM(c.PLI_0)) AS PliCode,
                    c.PIO_0 AS Priority,
                    c.PRIPRO_0 AS RuleType,
                    c.PRIQTYFLG_0 AS IsQtyBased,
                    c.FOCPRO_0 AS FocType,
                    LTRIM(RTRIM(c.FIL_0)) AS Fil0,
                    LTRIM(RTRIM(c.FLD_0)) AS Fld0,
                    LTRIM(RTRIM(c.FIL_1)) AS Fil1,
                    LTRIM(RTRIM(c.FLD_1)) AS Fld1,
                    LTRIM(RTRIM(l.PLICRI1_0)) AS MatchKey1,
                    LTRIM(RTRIM(l.PLICRI2_0)) AS MatchKey2,
                    l.PRI_0 AS BasePrice,
                    l.DCGVAL_0 AS DiscountPct,
                    l.DCGVAL_2 AS DiscountAmt,
                    l.FOCQTYMIN_0 AS FocQtyMin,
                    l.FOCQTYBKT_0 AS FocQtyBkt,
                    LTRIM(RTRIM(l.FOCITMREF_0)) AS FocItmRef,
                    l.FOCQTY_0 AS FocQty,
                    l.MINQTY_0 AS MinQty,
                    l.MAXQTY_0 AS MaxQty,
                    CONVERT(VARCHAR(10), l.ZDATE1_0, 23) AS ValidFrom,
                    CONVERT(VARCHAR(10), l.ZDATE2_0, 23) AS ValidTo
                FROM {_syncSettings.X3DatabaseName}.{schema}.SPRICCONF c WITH (NOLOCK)
                JOIN {_syncSettings.X3DatabaseName}.{schema}.SPRICLIST l WITH (NOLOCK) ON c.PLI_0 = l.PLI_0
                WHERE c.PLIENAFLG_0 = 2
            ";
            return await db.QueryAsync<PriceListDto>(sql);
        }
    }
}
