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

using Microsoft.Extensions.Caching.Memory;

namespace EnterpriseAuth.Api.Infrastructure.Persistence
{
    public class EfSalesInvoiceRepository : ISalesInvoiceRepository
    {
        private readonly string _connectionString;
        private readonly ScanProductionDbContext _scanContext;
        private readonly SyncSettings _syncSettings;
        private readonly IX3SchemaProvider _schemaProvider;
        private readonly IMemoryCache? _memoryCache;

        public EfSalesInvoiceRepository(
            IConfiguration configuration,
            ScanProductionDbContext scanContext,
            IOptions<SyncSettings> syncSettings,
            IX3SchemaProvider schemaProvider,
            IMemoryCache? memoryCache = null)
        {
            _connectionString = configuration.GetConnectionString("Innodis") 
                                ?? throw new ArgumentNullException("Innodis connection string is missing");
            _scanContext = scanContext;
            _syncSettings = syncSettings.Value;
            _schemaProvider = schemaProvider;
            _memoryCache = memoryCache;
        }

        public async Task<IEnumerable<SalesInvoiceCustomerDto>> GetCustomersAsync(string sitecode)
        {
            var cacheKey = $"Customers_{_schemaProvider.GetSchemaName()}_{sitecode ?? "ALL"}";
            if (_memoryCache != null && _memoryCache.TryGetValue(cacheKey, out IEnumerable<SalesInvoiceCustomerDto>? cached) && cached != null)
            {
                return cached;
            }

            using IDbConnection db = new SqlConnection(_connectionString);
            string sql = $@"
                SELECT 
                    LTRIM(RTRIM(c.BPCNUM_0)) as Code,
                    LTRIM(RTRIM(c.BPCNAM_0)) as Name,
                    LTRIM(RTRIM(c.PTE_0)) as PaymentTerm,
                    c.OSTAUZ_0 as CreditLimit,
                    LTRIM(RTRIM(c.OSTCTL_0)) as StatusFlag,
                    LTRIM(RTRIM(c.VACBPR_0)) as TaxRule,
                    LTRIM(RTRIM(c.BCGCOD_0)) as Bcgcod,
                    LTRIM(RTRIM(c.TSCCOD_0)) as Tsccod,
                    LTRIM(RTRIM(c.BPCSHO_0)) as Bpcsho,
                    COALESCE(b.BETFCY_0, 1) as FacilityFlag,
                    COALESCE(g.OutstandingBalance, 0) as OutstandingBalance
                FROM {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.BPCUSTOMER c
                LEFT JOIN {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.BPARTNER b ON c.BPCNUM_0 = b.BPRNUM_0
                LEFT JOIN (
                    SELECT 
                        BPR_0, 
                        SUM(AMTCUR_0 - PAYCUR_0) as OutstandingBalance 
                    FROM {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.GACCDUDATE 
                    WHERE (AMTCUR_0 - PAYCUR_0) > 0 AND BPRTYP_0 = 1
                    GROUP BY BPR_0
                ) g ON c.BPCNUM_0 = g.BPR_0
                WHERE c.BPCNAM_0 IS NOT NULL AND c.BPCNAM_0 <> ''
                ORDER BY LTRIM(RTRIM(c.BPCNAM_0))";

            var result = (await db.QueryAsync<SalesInvoiceCustomerDto>(sql, new { SiteCode = sitecode ?? string.Empty })).ToList();
            _memoryCache?.Set(cacheKey, result, TimeSpan.FromMinutes(15));
            return result;
        }

        public async Task<SalesInvoiceCustomerDto?> GetCustomerByCodeAsync(string customerCode)
        {
            if (string.IsNullOrWhiteSpace(customerCode)) return null;

            using IDbConnection db = new SqlConnection(_connectionString);
            string sql = $@"
                SELECT 
                    LTRIM(RTRIM(c.BPCNUM_0)) as Code,
                    LTRIM(RTRIM(c.BPCNAM_0)) as Name,
                    LTRIM(RTRIM(c.PTE_0)) as PaymentTerm,
                    c.OSTAUZ_0 as CreditLimit,
                    LTRIM(RTRIM(c.OSTCTL_0)) as StatusFlag,
                    LTRIM(RTRIM(c.VACBPR_0)) as TaxRule,
                    LTRIM(RTRIM(c.BCGCOD_0)) as Bcgcod,
                    LTRIM(RTRIM(c.TSCCOD_0)) as Tsccod,
                    LTRIM(RTRIM(c.BPCSHO_0)) as Bpcsho,
                    COALESCE(b.BETFCY_0, 1) as FacilityFlag,
                    COALESCE(g.OutstandingBalance, 0) as OutstandingBalance
                FROM {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.BPCUSTOMER c
                LEFT JOIN {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.BPARTNER b ON c.BPCNUM_0 = b.BPRNUM_0
                LEFT JOIN (
                    SELECT 
                        BPR_0, 
                        SUM(AMTCUR_0 - PAYCUR_0) as OutstandingBalance 
                    FROM {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.GACCDUDATE 
                    WHERE (AMTCUR_0 - PAYCUR_0) > 0 AND BPRTYP_0 = 1
                    GROUP BY BPR_0
                ) g ON c.BPCNUM_0 = g.BPR_0
                WHERE c.BPCNUM_0 = @CustomerCode";

            return await db.QueryFirstOrDefaultAsync<SalesInvoiceCustomerDto>(sql, new { CustomerCode = customerCode.Trim() });
        }

        public async Task<IEnumerable<SalesInvoiceProductDto>> GetProductsAsync(string sitecode)
        {
            using IDbConnection db = new SqlConnection(_connectionString);
            string sql = $@"
                SELECT 
                    LTRIM(RTRIM(itm.ITMREF_0)) AS Sku,
                    LTRIM(RTRIM(COALESCE(itm.ITMDES1_0, itm.ZFULLDES_0, ''))) AS Name,
                    LTRIM(RTRIM(COALESCE(itm.SAU_0, 'UN'))) AS SalesUnit,
                    SUM(COALESCE(stk.QTYSTU_0, 0)) AS StockQty
                FROM {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.ITMMASTER itm WITH (NOLOCK)
                INNER JOIN {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.STOCK stk WITH (NOLOCK)
                    ON itm.ITMREF_0 = stk.ITMREF_0 AND stk.STA_0 = 'A'
                LEFT JOIN {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.ZLOCWRH zlw WITH (NOLOCK)
                    ON stk.STOFCY_0 = zlw.WAREHOUSE_0 AND stk.LOC_0 = zlw.LOCATION_0
                LEFT JOIN {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.STOLOT sl WITH (NOLOCK)
                    ON stk.ITMREF_0 = sl.ITMREF_0 AND stk.LOT_0 = sl.LOT_0
                WHERE 
                    itm.ITMSTA_0 = 1
                    AND stk.STOFCY_0 = @SiteCode
                    AND stk.QTYSTU_0 > 0
                    AND (sl.SHLDAT_0 IS NULL OR sl.SHLDAT_0 >= CAST(GETDATE() AS DATE))
                    AND LTRIM(RTRIM(COALESCE(zlw.LOCTYPNAM_0, ''))) NOT IN ('IPL Spare Parts', 'IPL Hatchery', 'IPL Packaging Materials', 'IPL Diesel')
                GROUP BY 
                    LTRIM(RTRIM(itm.ITMREF_0)),
                    LTRIM(RTRIM(COALESCE(itm.ITMDES1_0, itm.ZFULLDES_0, ''))),
                    LTRIM(RTRIM(COALESCE(itm.SAU_0, 'UN')));";

            return await db.QueryAsync<SalesInvoiceProductDto>(sql, new { SiteCode = sitecode });
        }

        public async Task<IEnumerable<SalesInvoiceItemStockDto>> GetItemStockDetailsAsync(string sitecode)
        {
            using IDbConnection db = new SqlConnection(_connectionString);
            string sql = $@"
                SELECT 
                    LTRIM(RTRIM(COALESCE(zlw.WAREHOUSE_0, stk.WRH_0, stk.STOFCY_0))) AS Warehouse, 
                    LTRIM(RTRIM(COALESCE(zlw.WRHNAM_0, stk.STOFCY_0))) AS WarehouseName, 
                    LTRIM(RTRIM(stk.LOC_0)) AS Location, 
                    LTRIM(RTRIM(COALESCE(zlw.LOCTYPNAM_0, ''))) AS LocationType,
                    LTRIM(RTRIM(itm.ITMREF_0)) AS ItemCode,
                    LTRIM(RTRIM(COALESCE(itm.ITMDES1_0, itm.ZFULLDES_0, ''))) AS ItemName,  
                    SUM(COALESCE(stk.QTYSTU_0, 0)) AS TotalQty,
                    LTRIM(RTRIM(COALESCE(stk.LOT_0, ''))) AS LotNumber,
                    LTRIM(RTRIM(COALESCE(itm.VACITM_0, 'STD'))) AS TaxLevel,
                    LTRIM(RTRIM(COALESCE(itm.CCE_0, ''))) AS Cce0,
                    LTRIM(RTRIM(COALESCE(itm.SAU_0, 'UN'))) AS SalesUnit,
                    LTRIM(RTRIM(COALESCE(itm.EANCOD_0, ''))) AS Barcode,
                    LTRIM(RTRIM(stk.STOFCY_0)) AS SiteCode,
                    LTRIM(RTRIM(COALESCE(stk.STA_0, 'A'))) AS StockStatus
                FROM {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.STOCK stk WITH (NOLOCK)
                INNER JOIN {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.ITMMASTER itm WITH (NOLOCK)
                    ON stk.ITMREF_0 = itm.ITMREF_0 AND itm.ITMSTA_0 = 1
                LEFT JOIN {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.ZLOCWRH zlw WITH (NOLOCK)
                    ON stk.STOFCY_0 = zlw.WAREHOUSE_0 AND stk.LOC_0 = zlw.LOCATION_0
                LEFT JOIN {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.STOLOT sl WITH (NOLOCK)
                    ON stk.ITMREF_0 = sl.ITMREF_0 AND stk.LOT_0 = sl.LOT_0
                WHERE stk.STOFCY_0 = @SiteCode 
                  AND stk.STA_0 IN ('A', 'Q', 'R')
                  AND stk.QTYSTU_0 > 0
                  AND (sl.SHLDAT_0 IS NULL OR sl.SHLDAT_0 >= CAST(GETDATE() AS DATE))
                  AND LTRIM(RTRIM(COALESCE(zlw.LOCTYPNAM_0, ''))) NOT IN ('IPL Spare Parts', 'IPL Hatchery', 'IPL Packaging Materials', 'IPL Diesel')
                GROUP BY 
                    stk.STOFCY_0, COALESCE(zlw.WAREHOUSE_0, stk.WRH_0, stk.STOFCY_0), COALESCE(zlw.WRHNAM_0, stk.STOFCY_0), 
                    stk.LOC_0, zlw.LOCTYPNAM_0,
                    itm.ITMREF_0, COALESCE(itm.ITMDES1_0, itm.ZFULLDES_0, ''), stk.LOT_0, itm.VACITM_0, itm.CCE_0, itm.SAU_0, itm.EANCOD_0,
                    stk.STA_0
                ORDER BY 
                    stk.STOFCY_0, itm.ITMREF_0, stk.LOT_0, stk.STA_0";

            return await db.QueryAsync<SalesInvoiceItemStockDto>(sql, new { SiteCode = sitecode });
        }

        private static readonly System.Collections.Concurrent.ConcurrentDictionary<string, System.Threading.SemaphoreSlim> _siLocks = new();

        private async Task<IEnumerable<T>> QueryCachedOrLiveAsync<T>(string cacheKey, TimeSpan ttl, string sql, object? parameters = null)
        {
            if (_memoryCache != null && _memoryCache.TryGetValue(cacheKey, out IEnumerable<T>? cached) && cached != null)
            {
                return cached;
            }

            var myLock = _siLocks.GetOrAdd(cacheKey, _ => new System.Threading.SemaphoreSlim(1, 1));
            await myLock.WaitAsync();
            try
            {
                if (_memoryCache != null && _memoryCache.TryGetValue(cacheKey, out cached) && cached != null)
                {
                    return cached;
                }

                using IDbConnection db = new SqlConnection(_connectionString);
                var result = (await db.QueryAsync<T>(sql, parameters)).ToList();
                if (_memoryCache != null && result.Any())
                {
                    _memoryCache.Set(cacheKey, result, ttl);
                }
                return result;
            }
            finally
            {
                myLock.Release();
            }
        }

        public async Task<IEnumerable<TaxMatrixDto>> GetTaxDeterminationsAsync()
        {
            string sql = $@"
                SELECT 
                    LTRIM(RTRIM(VACBPR_0)) AS CustomerTaxRule,
                    LTRIM(RTRIM(VACITM_0)) AS ItemTaxLevel,
                    VAT_0 AS TaxCode
                FROM {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.TABVAC WITH (NOLOCK)";
            return await QueryCachedOrLiveAsync<TaxMatrixDto>($"si_tax_matrix_{_schemaProvider.GetSchemaName()}", TimeSpan.FromMinutes(5), sql);
        }

        public async Task<IEnumerable<TaxRateDto>> GetTaxRatesAsync()
        {
            string sql = $@"
                SELECT 
                    VAT_0 AS TaxCode,
                    LTRIM(RTRIM(VATDES_0)) AS Description,
                    VATRAT_0 AS TaxRatePercent
                FROM {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.TABVAT WITH (NOLOCK)";
            return await QueryCachedOrLiveAsync<TaxRateDto>($"si_tax_rates_{_schemaProvider.GetSchemaName()}", TimeSpan.FromMinutes(5), sql);
        }

        public async Task<IEnumerable<PriceListDto>> GetPriceListsAsync()
        {
            string schema = _schemaProvider.GetSchemaName();
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
                    l.FOCAMTMIN_0 AS FocAmtMin,
                    l.FOCAMTBKT_0 AS FocAmtBkt,
                    LTRIM(RTRIM(l.FOCITMREF_0)) AS FocItmRef,
                    l.FOCQTY_0 AS FocQty,
                    l.MINQTY_0 AS MinQty,
                    l.MAXQTY_0 AS MaxQty,
                    CONVERT(VARCHAR(10), l.PLISTRDAT_0, 23) AS ValidFrom,
                    CONVERT(VARCHAR(10), l.PLIENDDAT_0, 23) AS ValidTo,
                    c.PRIREN_0 AS ReasonType
                FROM {_syncSettings.X3DatabaseName}.{schema}.SPRICCONF c WITH (NOLOCK)
                JOIN {_syncSettings.X3DatabaseName}.{schema}.SPRICLIST l WITH (NOLOCK) ON c.PLI_0 = l.PLI_0
                WHERE (c.PLICPY_0 = '{_syncSettings.X3CompanyCode}' OR LTRIM(RTRIM(c.PLICPY_0)) = '')
                  AND c.PLIENAFLG_0 = 2
                  AND l.PLISTRDAT_0 <= GETDATE()
                  AND (l.PLIENDDAT_0 >= CONVERT(DATE, GETDATE()) OR l.PLIENDDAT_0 IN ('1753-01-01', '1900-01-01'))
            ";
            using IDbConnection db = new SqlConnection(_connectionString);
            return await db.QueryAsync<PriceListDto>(sql);
        }

        public async Task<IEnumerable<SalesRepLookupDto>> GetSalesRepsAsync(string? siteCode = null)
        {
            var cacheKey = $"SalesReps_{_schemaProvider.GetSchemaName()}_{siteCode ?? "ALL"}";
            if (_memoryCache != null && _memoryCache.TryGetValue(cacheKey, out IEnumerable<SalesRepLookupDto>? cached) && cached != null)
            {
                return cached;
            }

            using IDbConnection db = new SqlConnection(_connectionString);
            string sql = $@"
                SELECT 
                    LTRIM(RTRIM(T1.REPNUM_0)) AS Code, 
                    LTRIM(RTRIM(ISNULL(T3.TEXTE_0, T2.BPRNAM_0))) AS Name,
                    LTRIM(RTRIM(T1.FCY_0)) AS AssignedSite 
                FROM {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.SALESREP T1 WITH (NOLOCK)
                INNER JOIN {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.BPARTNER T2 WITH (NOLOCK) 
                    ON T1.REPNUM_0 = T2.BPRNUM_0 
                LEFT JOIN {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.ATEXTRA T3 WITH (NOLOCK)
                    ON T3.CODFIC_0 = 'BPARTNER'
                    AND T3.ZONE_0 = 'BPRNAM'
                    AND T3.LANGUE_0 = 'ENG'
                    AND T3.IDENT1_0 = T2.BPRNUM_0
                    AND (T3.IDENT2_0 = '' OR T3.IDENT2_0 IS NULL)
                WHERE (@SiteCode = '' OR @SiteCode = 'ALL' OR T1.FCY_0 = @SiteCode OR T1.FCY_0 IS NULL OR T1.FCY_0 = '')
                ORDER BY T1.REPNUM_0;
            ";
            var result = (await db.QueryAsync<SalesRepLookupDto>(sql, new { SiteCode = siteCode ?? "" })).ToList();
            _memoryCache?.Set(cacheKey, result, TimeSpan.FromMinutes(30));
            return result;
        }

        public async Task<IEnumerable<OpenInvoiceDto>> GetOpenInvoicesAsync(
            string? siteCode = null, 
            string? customerNo = null, 
            int daysCutoff = 0)
        {
            using IDbConnection db = new SqlConnection(_connectionString);
            var schema = _schemaProvider.GetSchemaName();

            string sql = $@"
                SELECT  
                    BPC.BPCNUM_0                                                         AS CustomerNo,
                    LTRIM(RTRIM(COALESCE(BPC.BPCNAM_0, '')))                             AS CustomerName,
                    DUD.NUM_0                                                            AS DocumentNo,
                    DUD.DUDDAT_0                                                         AS DueDate,
                    LTRIM(RTRIM(DUD.FCY_0))                                              AS Site,
                    LTRIM(RTRIM(DUD.CPY_0))                                              AS Company,
                    'INV'                                                                AS DocType,
                    SUM((DUD.AMTCUR_0 - DUD.PAYCUR_0) * DUD.SNS_0)                       AS RemainingAmtLCY
                FROM {_syncSettings.X3DatabaseName}.{schema}.[GACCDUDATE] DUD WITH (NOLOCK),  
                     {_syncSettings.X3DatabaseName}.{schema}.[COMPANY] CPY WITH (NOLOCK), 
                     {_syncSettings.X3DatabaseName}.{schema}.[GACM] GCM WITH (NOLOCK), 
                     {_syncSettings.X3DatabaseName}.{schema}.[BPCUSTOMER] BPC WITH (NOLOCK)
                WHERE DUD.CPY_0    = CPY.CPY_0
                  AND GCM.GCM_0    = CPY.ACM_0 
                  AND DUD.CUR_0    = GCM.CUR_0
                  AND DUD.BPRPAY_0 = BPC.BPCNUM_0
                  AND DUD.AMTCUR_0 > DUD.PAYCUR_0 + DUD.TMPCUR_0 
                  AND DUD.DUDSTA_0 = 2
                  AND DUD.SNS_0    = 1
                  AND (@SiteCode = '' OR @SiteCode = 'ALL' OR LTRIM(RTRIM(DUD.FCY_0)) = @SiteCode)
                  AND (@DaysCutoff <= 0 OR DUD.DUDDAT_0 >= DATEADD(day, -@DaysCutoff, CAST(GETDATE() AS DATE)))
                  AND (@CustomerNo = '' OR BPC.BPCNUM_0 = @CustomerNo)
                GROUP BY  
                    BPC.BPCNUM_0,
                    BPC.BPCNAM_0,
                    DUD.NUM_0,
                    DUD.DUDDAT_0, 
                    DUD.FCY_0, 
                    DUD.CPY_0
                HAVING SUM((DUD.AMTCUR_0 - DUD.PAYCUR_0) * DUD.SNS_0) > 0.001
                ORDER BY DUD.DUDDAT_0 ASC, DUD.NUM_0 ASC;
            ";

            return await db.QueryAsync<OpenInvoiceDto>(sql, new 
            { 
                SiteCode = (siteCode ?? "").Trim(),
                CustomerNo = (customerNo ?? "").Trim(),
                DaysCutoff = daysCutoff
            });
        }

        public async Task<IEnumerable<X3HistoryDocumentDto>> GetX3HistoryAsync(string siteCode, string? customerCode = null, int months = 6)
        {
            using IDbConnection db = new SqlConnection(_connectionString);
            var dbName = _syncSettings.X3DatabaseName;
            var schema = _schemaProvider.GetSchemaName();

            string sql = $@"
                -- Step 1: Pre-filter invoices and lines by site, date and type into a scoped temp table
                SELECT 
                    H.CPY_0, D.SALFCY_0, H.NUM_0, H.INVTYP_0, D.BPCINV_0,
                    D.INVDAT_0, D.CREUSR_0, D.SOHNUM_0, D.SDHNUM_0, D.SIDLIN_0,
                    D.ITMREF_0, D.ITMDES_0, D.QTY_0, D.SAU_0, D.GROPRI_0,
                    D.NETPRI_0, D.AMTNOTLIN_0, D.AMTATILIN_0, D.DISCRGVAL1_0, D.DISCRGVAL2_0
                INTO #TargetLines
                FROM {dbName}.{schema}.SINVOICED D WITH (NOLOCK)
                INNER JOIN {dbName}.{schema}.SINVOICE H WITH (NOLOCK) ON D.NUM_0 = H.NUM_0
                WHERE (@SiteCode = '' OR @SiteCode = 'ALL' OR LTRIM(RTRIM(D.SALFCY_0)) = @SiteCode)
                  AND D.INVDAT_0 >= DATEADD(month, -@Months, GETDATE())
                  AND H.INVTYP_0 IN (1, 2);

                CREATE CLUSTERED INDEX IX_Target_Doc ON #TargetLines (NUM_0, SIDLIN_0);
                CREATE NONCLUSTERED INDEX IX_Target_Keys ON #TargetLines (SOHNUM_0, SDHNUM_0);

                -- Step 2: Scope order and delivery keys
                SELECT DISTINCT SOHNUM_0 AS KeyVal INTO #OrderKeys FROM #TargetLines WHERE SOHNUM_0 IS NOT NULL AND SOHNUM_0 <> '';
                SELECT DISTINCT SDHNUM_0 AS KeyVal INTO #DlvKeys FROM #TargetLines WHERE SDHNUM_0 IS NOT NULL AND SDHNUM_0 <> '';

                -- Step 3: Match customer details only for the targeted orders and deliveries
                SELECT LTRIM(RTRIM(z.SONO_0)) AS MapKey, LTRIM(RTRIM(z.ORISOCUST_0)) AS ORISOCUST_0, LTRIM(RTRIM(z.ORISOCUSTNAM_0)) AS ORISOCUSTNAM_0
                INTO #CustMapSO
                FROM {dbName}.{schema}.ZBTBORD z WITH (NOLOCK)
                INNER JOIN #OrderKeys k ON z.SONO_0 = k.KeyVal;

                SELECT LTRIM(RTRIM(z.DELIVERYNO_0)) AS MapKey, LTRIM(RTRIM(z.ORISOCUST_0)) AS ORISOCUST_0, LTRIM(RTRIM(z.ORISOCUSTNAM_0)) AS ORISOCUSTNAM_0
                INTO #CustMapDLV
                FROM {dbName}.{schema}.ZBTBORD z WITH (NOLOCK)
                INNER JOIN #DlvKeys k ON z.DELIVERYNO_0 = k.KeyVal;

                -- Step 4: Resolve distinct customer codes for targeted lines
                SELECT DISTINCT 
                    COALESCE(NULLIF(m_so.ORISOCUST_0, ''), NULLIF(m_dlv.ORISOCUST_0, ''), t.BPCINV_0) AS CustomerCode
                INTO #TargetCusts
                FROM #TargetLines t
                LEFT JOIN #CustMapSO m_so ON t.SOHNUM_0 = m_so.MapKey
                LEFT JOIN #CustMapDLV m_dlv ON t.SDHNUM_0 = m_dlv.MapKey;

                SELECT LTRIM(RTRIM(c.BPCNUM_0)) AS BPCNUM_0, LTRIM(RTRIM(c.ZFULLBUSNAM_0)) AS ZFULLBUSNAM_0, LTRIM(RTRIM(c.BPCNAM_0)) AS BPCNAM_0
                INTO #CustMaster
                FROM {dbName}.{schema}.BPCUSTOMER c WITH (NOLOCK)
                INNER JOIN #TargetCusts tc ON c.BPCNUM_0 = tc.CustomerCode;

                -- Step 5: Final high-speed projection
                SELECT 
                    LTRIM(RTRIM(t.CPY_0))                             AS Company,
                    LTRIM(RTRIM(t.SALFCY_0))                          AS SalesSite,
                    LTRIM(RTRIM(t.NUM_0))                             AS InvoiceNumber,
                    t.INVTYP_0                                        AS InvoiceTypeFlag,
                    LTRIM(RTRIM(t.BPCINV_0))                          AS BillToCustomer,
                    COALESCE(
                        NULLIF(m_so.ORISOCUST_0, ''), 
                        NULLIF(m_dlv.ORISOCUST_0, ''), 
                        LTRIM(RTRIM(t.BPCINV_0))
                    ) COLLATE DATABASE_DEFAULT                        AS CustomerCode,
                    COALESCE(
                        NULLIF(m_so.ORISOCUSTNAM_0, ''), 
                        NULLIF(m_dlv.ORISOCUSTNAM_0, ''), 
                        LTRIM(RTRIM(c.ZFULLBUSNAM_0)), 
                        LTRIM(RTRIM(c.BPCNAM_0)), 
                        ''
                    ) COLLATE DATABASE_DEFAULT                        AS CustomerName,
                    t.INVDAT_0                                        AS InvoiceDate,
                    LTRIM(RTRIM(t.CREUSR_0))                          AS CreationUser,
                    LTRIM(RTRIM(t.SOHNUM_0))                          AS SoNumber,
                    LTRIM(RTRIM(t.SDHNUM_0))                          AS DeliveryNumber,
                    t.SIDLIN_0                                        AS LineNumber,
                    LTRIM(RTRIM(t.ITMREF_0))                          AS ProductCode,
                    LTRIM(RTRIM(t.ITMDES_0))                          AS ProductDescription,
                    t.QTY_0                                           AS Quantity,
                    LTRIM(RTRIM(t.SAU_0))                             AS SalesUOM,
                    t.GROPRI_0                                        AS GrossPrice,
                    t.NETPRI_0                                        AS NetPrice,
                    t.AMTNOTLIN_0                                     AS LineAmountNotTax,
                    t.AMTATILIN_0                                     AS LineAmountIncTax,
                    t.DISCRGVAL1_0                                    AS DiscountValue1,
                    t.DISCRGVAL2_0                                    AS DiscountValue2
                FROM #TargetLines t
                LEFT JOIN #CustMapSO m_so ON t.SOHNUM_0 = m_so.MapKey
                LEFT JOIN #CustMapDLV m_dlv ON t.SDHNUM_0 = m_dlv.MapKey
                LEFT JOIN #CustMaster c ON c.BPCNUM_0 = COALESCE(NULLIF(m_so.ORISOCUST_0, ''), NULLIF(m_dlv.ORISOCUST_0, ''), t.BPCINV_0)
                WHERE (@CustomerCode = '' 
                       OR COALESCE(NULLIF(m_so.ORISOCUST_0, ''), NULLIF(m_dlv.ORISOCUST_0, ''), t.BPCINV_0) = @CustomerCode
                       OR LTRIM(RTRIM(t.BPCINV_0)) = @CustomerCode)
                ORDER BY t.INVDAT_0 DESC, t.NUM_0 DESC, t.SIDLIN_0 ASC;

                DROP TABLE #TargetLines;
                DROP TABLE #OrderKeys;
                DROP TABLE #DlvKeys;
                DROP TABLE #CustMapSO;
                DROP TABLE #CustMapDLV;
                DROP TABLE #TargetCusts;
                DROP TABLE #CustMaster;
            ";

            var rows = await db.QueryAsync<X3HistoryRawRowDto>(sql, new 
            { 
                SiteCode = (siteCode ?? "").Trim(),
                CustomerCode = (customerCode ?? "").Trim(),
                Months = months > 0 ? months : 6
            }, commandTimeout: 30);

            var grouped = new Dictionary<string, X3HistoryDocumentDto>();
            foreach (var r in rows)
            {
                if (!grouped.TryGetValue(r.InvoiceNumber, out var doc))
                {
                    doc = new X3HistoryDocumentDto
                    {
                        Company = r.Company,
                        SalesSite = r.SalesSite,
                        InvoiceNumber = r.InvoiceNumber,
                        InvoiceTypeFlag = r.InvoiceTypeFlag,
                        BillToCustomer = r.BillToCustomer,
                        CustomerCode = r.CustomerCode,
                        CustomerName = r.CustomerName,
                        SoNumber = r.SoNumber,
                        DeliveryNumber = r.DeliveryNumber,
                        InvoiceDate = r.InvoiceDate,
                        CreationUser = r.CreationUser,
                        TotalAmountNotTax = 0,
                        TotalAmountIncTax = 0,
                        Lines = new List<X3HistoryLineDto>()
                    };
                    grouped[r.InvoiceNumber] = doc;
                }

                doc.TotalAmountNotTax += r.LineAmountNotTax;
                doc.TotalAmountIncTax += r.LineAmountIncTax;

                doc.Lines.Add(new X3HistoryLineDto
                {
                    LineNumber = r.LineNumber,
                    ProductCode = r.ProductCode,
                    ProductDescription = r.ProductDescription,
                    Quantity = r.Quantity,
                    SalesUOM = r.SalesUOM,
                    GrossPrice = r.GrossPrice,
                    NetPrice = r.NetPrice,
                    LineAmountNotTax = r.LineAmountNotTax,
                    LineAmountIncTax = r.LineAmountIncTax,
                    DiscountValue1 = r.DiscountValue1,
                    DiscountValue2 = r.DiscountValue2
                });
            }

            return grouped.Values;
        }

        public async Task<IEnumerable<CreditNoteReasonDto>> GetCreditNoteReasonsAsync()
        {
            var schema = _schemaProvider.GetSchemaName();
            string sql = $@"
                SELECT 
                    LTRIM(RTRIM(A.CODE_0)) AS Code,
                    LTRIM(RTRIM(COALESCE(T.TEXTE_0, A.CODE_0))) AS Description
                FROM {_syncSettings.X3DatabaseName}.{schema}.[ATABDIV] A WITH (NOLOCK)
                LEFT JOIN {_syncSettings.X3DatabaseName}.{schema}.[ATEXTRA] T WITH (NOLOCK)
                    ON T.CODFIC_0 = 'ATABDIV'
                   AND T.ZONE_0 = 'LNGDES'
                   AND T.IDENT1_0 = CAST(A.NUMTAB_0 AS VARCHAR)
                   AND T.IDENT2_0 = A.CODE_0
                   AND T.LANGUE_0 = 'ENG'
                WHERE A.NUMTAB_0 = 8
                ORDER BY 
                    CASE WHEN T.TEXTE_0 IS NOT NULL AND T.TEXTE_0 <> '' THEN 0 ELSE 1 END,
                    Description ASC;
            ";
            return await QueryCachedOrLiveAsync<CreditNoteReasonDto>($"si_cn_reasons_{schema}", TimeSpan.FromMinutes(5), sql);
        }

        public async Task<IEnumerable<BankDto>> GetBanksAsync()
        {
            var schema = _schemaProvider.GetSchemaName();
            string sql = $@"
                SELECT 
                    LTRIM(RTRIM(b.BAN_0)) AS BankCode,
                    LTRIM(RTRIM(b.DES_0)) AS BankName,
                    LTRIM(RTRIM(b.CPY_0)) AS Company,
                    LTRIM(RTRIM(b.CUR_0)) AS Currency,
                    LTRIM(RTRIM(COALESCE(b.FCY_0, ''))) AS SiteCode
                FROM {_syncSettings.X3DatabaseName}.{schema}.[BANK] b WITH (NOLOCK)
                ORDER BY b.CPY_0, b.BAN_0;
            ";
            return await QueryCachedOrLiveAsync<BankDto>($"si_banks_{schema}", TimeSpan.FromMinutes(5), sql);
        }

        public async Task<string> GetX3HistoryWatermarkAsync(string siteCode, int months = 6)
        {
            using IDbConnection db = new SqlConnection(_connectionString);
            var schema = _schemaProvider.GetSchemaName();
            string sql = $@"
                SELECT 
                    CONCAT(
                        COALESCE(CONVERT(VARCHAR(30), MAX(H.UPDDAT_0), 126), '1970-01-01'), 
                        '_', 
                        COUNT(*), 
                        '_', 
                        COALESCE(MAX(H.NUM_0), '')
                    )
                FROM {_syncSettings.X3DatabaseName}.{schema}.SINVOICEV H WITH (NOLOCK)
                WHERE (@SiteCode = '' OR @SiteCode = 'ALL' OR LTRIM(RTRIM(H.SALFCY_0)) = @SiteCode)
                  AND H.INVDAT_0 >= DATEADD(month, -@Months, GETDATE())
                  AND H.INVTYP_0 IN (1, 2);
            ";
            var watermark = await db.ExecuteScalarAsync<string>(sql, new 
            { 
                SiteCode = (siteCode ?? "").Trim(),
                Months = months > 0 ? months : 6
            });
            return watermark ?? "EMPTY";
        }

        public async Task<string> GetOpenInvoicesWatermarkAsync(string siteCode, int daysCutoff = 0)
        {
            using IDbConnection db = new SqlConnection(_connectionString);
            var schema = _schemaProvider.GetSchemaName();
            string sql = $@"
                SELECT 
                    CONCAT(
                        COALESCE(CONVERT(VARCHAR(30), MAX(DUD.UPDDATTIM_0), 126), '1970-01-01'),
                        '_',
                        COALESCE(SUM(DUD.AMTCUR_0 - DUD.PAYCUR_0), 0),
                        '_',
                        COUNT(*)
                    )
                FROM {_syncSettings.X3DatabaseName}.{schema}.[GACCDUDATE] DUD WITH (NOLOCK)
                WHERE (@SiteCode = '' OR @SiteCode = 'ALL' OR LTRIM(RTRIM(DUD.FCY_0)) = @SiteCode)
                  AND DUD.DUDSTA_0 = 2
                  AND DUD.SNS_0 = 1
                  AND (@DaysCutoff <= 0 OR DUD.DUDDAT_0 >= DATEADD(day, -@DaysCutoff, CAST(GETDATE() AS DATE)));
            ";
            var watermark = await db.ExecuteScalarAsync<string>(sql, new 
            { 
                SiteCode = (siteCode ?? "").Trim(),
                DaysCutoff = daysCutoff
            });
            return watermark ?? "EMPTY";
        }

        public async Task<string> GetStockWatermarkAsync(string siteCode)
        {
            using IDbConnection db = new SqlConnection(_connectionString);
            var schema = _schemaProvider.GetSchemaName();
            string sql = $@"
                SELECT 
                    CONCAT(
                        COALESCE(CONVERT(VARCHAR(30), MAX(stk.UPDDAT_0), 126), '1970-01-01'),
                        '_',
                        COALESCE(SUM(stk.QTYSTU_0), 0),
                        '_',
                        COUNT(*)
                    )
                FROM {_syncSettings.X3DatabaseName}.{schema}.STOCK stk WITH (NOLOCK)
                WHERE (@SiteCode = '' OR @SiteCode = 'ALL' OR LTRIM(RTRIM(stk.STOFCY_0)) = @SiteCode)
                  AND stk.STA_0 = 'A'
                  AND stk.QTYSTU_0 > 0;
            ";
            var watermark = await db.ExecuteScalarAsync<string>(sql, new 
            { 
                SiteCode = (siteCode ?? "").Trim() 
            });
            return watermark ?? "EMPTY";
        }

        public async Task<string> GetPriceListsWatermarkAsync()
        {
            using IDbConnection db = new SqlConnection(_connectionString);
            var schema = _schemaProvider.GetSchemaName();
            string sql = $@"
                SELECT 
                    CONCAT(
                        COALESCE(CONVERT(VARCHAR(30), MAX(l.UPDDAT_0), 126), '1970-01-01'),
                        '_',
                        COUNT(*),
                        '_',
                        COALESCE(MAX(l.PLI_0), '')
                    )
                FROM {_syncSettings.X3DatabaseName}.{schema}.SPRICLIST l WITH (NOLOCK)
                WHERE l.PLISTRDAT_0 <= GETDATE()
                  AND (l.PLIENDDAT_0 >= CONVERT(DATE, GETDATE()) OR l.PLIENDDAT_0 IN ('1753-01-01', '1900-01-01'));
            ";
            var watermark = await db.ExecuteScalarAsync<string>(sql);
            return watermark ?? "EMPTY";
        }

        public async Task<CustomerLiveCreditDto?> GetCustomerLiveCreditAsync(string customerNo)
        {
            using IDbConnection db = new SqlConnection(_connectionString);
            var schema = _schemaProvider.GetSchemaName();
            string sql = $@"
                SELECT 
                    LTRIM(RTRIM(c.BPCNUM_0))                              AS CustomerNo,
                    COALESCE(c.OSTAUZ_0, 0)                               AS AuthorizedCreditLimit,
                    LTRIM(RTRIM(COALESCE(c.OSTCTL_0, '')))                AS CreditControlStatus,
                    COALESCE(SUM((d.AMTCUR_0 - d.PAYCUR_0) * d.SNS_0), 0) AS LiveOutstandingBalance,
                    (COALESCE(c.OSTAUZ_0, 0) - COALESCE(SUM((d.AMTCUR_0 - d.PAYCUR_0) * d.SNS_0), 0)) AS LiveAvailableCredit
                FROM {_syncSettings.X3DatabaseName}.{schema}.BPCUSTOMER c WITH (NOLOCK)
                LEFT JOIN {_syncSettings.X3DatabaseName}.{schema}.GACCDUDATE d WITH (NOLOCK)
                    ON c.BPCNUM_0 = d.BPR_0 AND d.DUDSTA_0 = 2 AND d.BPRTYP_0 = 1
                WHERE c.BPCNUM_0 = @CustomerNo
                GROUP BY c.BPCNUM_0, c.OSTAUZ_0, c.OSTCTL_0;
            ";
            return await db.QueryFirstOrDefaultAsync<CustomerLiveCreditDto>(sql, new { CustomerNo = (customerNo ?? "").Trim() });
        }

        public async Task<ProductLiveStockDto?> GetProductLiveStockAsync(string productCode, string siteCode)
        {
            using IDbConnection db = new SqlConnection(_connectionString);
            var schema = _schemaProvider.GetSchemaName();
            string sql = $@"
                SELECT 
                    @ProductCode                                                        AS ProductCode,
                    @SiteCode                                                           AS SiteCode,
                    ISNULL(SUM(s.QTYSTU_0), 0)                                          AS PhysicalStock,
                    ISNULL(MAX(m.CUMALL_0), 0)                                          AS AllocatedStock,
                    (ISNULL(SUM(s.QTYSTU_0), 0) - ISNULL(MAX(m.CUMALL_0), 0))          AS LiveAvailableStock
                FROM {_syncSettings.X3DatabaseName}.{schema}.ITMMVT m WITH (NOLOCK)
                LEFT JOIN {_syncSettings.X3DatabaseName}.{schema}.STOCK s WITH (NOLOCK)
                    ON m.ITMREF_0 = s.ITMREF_0 AND m.STOFCY_0 = s.STOFCY_0 AND s.STA_0 = 'A' AND s.QTYSTU_0 > 0
                WHERE m.ITMREF_0 = @ProductCode AND m.STOFCY_0 = @SiteCode
                GROUP BY m.ITMREF_0;
            ";
            var result = await db.QueryFirstOrDefaultAsync<ProductLiveStockDto>(sql, new 
            { 
                ProductCode = (productCode ?? "").Trim(), 
                SiteCode = (siteCode ?? "").Trim() 
            });

            return result ?? new ProductLiveStockDto
            {
                ProductCode = productCode ?? "",
                SiteCode = siteCode ?? "",
                PhysicalStock = 0,
                AllocatedStock = 0,
                LiveAvailableStock = 0
            };
        }
    }
}
