using System;
using System.Collections.Generic;
using System.Data;
using System.Linq;
using System.Threading.Tasks;
using Dapper;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;
using Microsoft.EntityFrameworkCore;
using EnterpriseAuth.Api.Core.Domain.Entities;
using EnterpriseAuth.Api.Core.Domain.Interfaces;
using EnterpriseAuth.Api.Core.Application.DTOs;
using EnterpriseAuth.Api.Infrastructure.Persistence;
using EnterpriseAuth.Api.Core.Application.Common;
using Microsoft.Extensions.Options;

namespace EnterpriseAuth.Api.Infrastructure.Persistence
{
    public class EfSyncRepository : ISyncRepository
    {
        private readonly string _connectionString;
        private readonly ApplicationDbContext _context;
        private readonly ScanProductionDbContext _scanContext;
        private readonly SyncSettings _syncSettings;

        public EfSyncRepository(IConfiguration configuration, ApplicationDbContext context, ScanProductionDbContext scanContext, IOptions<SyncSettings> syncSettings)
        {
            _connectionString = configuration.GetConnectionString("Innodis") 
                                ?? throw new ArgumentNullException("Innodis connection string is missing");
            _context = context;
            _scanContext = scanContext;
            _syncSettings = syncSettings.Value;
        }

        public async Task<SyncPackageDto> GetRefreshPackageAsync(string site)
        {
            var package = new SyncPackageDto();

            // Define fetching tasks with separate connections for parallel execution
            var ordersTask = FetchFromInnodisAsync<SalesOrderHeaderDto>(@"
                SELECT TOP 100
                    f0.SOHNUM_0 COLLATE DATABASE_DEFAULT as [SohNum],
                    f2.PONO_0 COLLATE DATABASE_DEFAULT as [PoNo],
                    f0.ORDDAT_0 as [OrderDate],
                    f0.SHIDAT_0 as [DeliveryDate],
                    f0.BPCORD_0 COLLATE DATABASE_DEFAULT as [CustomerCode],
                    c.ZFULLBUSNAM_0 COLLATE DATABASE_DEFAULT as [CustomerName],
                    f0.REP_0 COLLATE DATABASE_DEFAULT as [Rep0],
                    f0.REP_1 COLLATE DATABASE_DEFAULT as [Rep1],
                    f0.SALFCY_0 COLLATE DATABASE_DEFAULT as [Site],
                    f0.ORDSTA_0 as [Status],
                    'External' as [Source]
                FROM InnodisTestDB.INLPROD.SORDER f0 WITH (NOLOCK)
                JOIN InnodisTestDB.INLPROD.ZBTBORD f2 WITH (NOLOCK) ON f0.SOHNUM_0 = f2.ORISONO_0
                JOIN InnodisTestDB.INLPROD.BPCUSTOMER c WITH (NOLOCK) ON f0.BPCORD_0 = c.BPCNUM_0
                ORDER BY f0.ORDDAT_0 DESC");

            var detailsTask = FetchFromInnodisAsync<SalesOrderDetailDto>(@"
                SELECT 
                    f0.SOHNUM_0 as SoNumber,
                    f2.ITMREF_0 as ItemCode,
                    f2.ITMDES1_0 as Description,
                    'Variable Weight' as BarcodeType,
                    f1.QTY_0 as Quantity
                FROM InnodisTestDB.INLPROD.SORDER f0 WITH (NOLOCK)
                JOIN InnodisTestDB.INLPROD.SORDERQ f1 WITH (NOLOCK) on f0.SOHNUM_0 = f1.SOHNUM_0
                JOIN InnodisTestDB.INLPROD.ITMMASTER f2 WITH (NOLOCK) on f1.ITMREF_0 = f2.ITMREF_0
                WHERE f0.SOHNUM_0 IN (
                    SELECT TOP 100 s.SOHNUM_0 
                    FROM InnodisTestDB.INLPROD.SORDER s WITH (NOLOCK) 
                    ORDER BY s.ORDDAT_0 DESC
                )");

            var customersTask = FetchFromInnodisAsync<CustomerLookupDto>("SELECT DISTINCT BPCNUM_0 as Code, ZFULLBUSNAM_0 as Name FROM InnodisTestDB.INLPROD.BPCUSTOMER WITH (NOLOCK)");
            var repsTask = FetchFromInnodisAsync<SalesRepLookupDto>("SELECT DISTINCT REPNUM_0 as Code, REPNAM_0 as Name FROM InnodisTestDB.INLPROD.SALESREP WITH (NOLOCK)");
            
            var locSql = @"
                SELECT 
                    T1.STOFCY_0 as Site, T1.LOC_0 as Location, T1.WRH_0 as Warehouse,
                    WRH.WRHNAM_0 as WarehouseName, T1.LOCTYP_0 as LocationType,
                    ATRA.TEXTE_0 as LocationTypeName
                FROM InnodisTestDB.INLPROD.STOLOC T1 WITH (NOLOCK)
                LEFT JOIN InnodisTestDB.INLPROD.WAREHOUSE WRH WITH (NOLOCK) on WRH.WRH_0 = T1.WRH_0 
                LEFT JOIN InnodisTestDB.INLPROD.[ATEXTRA] ATRA WITH (NOLOCK) on T1.STOFCY_0 = ATRA.IDENT1_0 
                    and T1.LOCTYP_0 = ATRA.IDENT2_0 
                    and ATRA.CODFIC_0 = 'TABLOCTYP' and ATRA.LANGUE_0 = 'BRI' and ATRA.ZONE_0 = 'TYPDESAXX'
                WHERE T1.STOFCY_0 = @Site";
            var locationsTask = FetchFromInnodisAsync<LocationLookupDto>(locSql, new { Site = site });

            var productsSql = @"
                SELECT 
                    f0.ITMREF_0 as ProductCode,
                    f0.ITMDES1_0 as ProductDescription,
                    f0.STU_0 as StockUnit,
                    f0.SAU_0 as SalesUnit
                FROM InnodisTestDB.INLPROD.ITMMASTER f0 WITH (NOLOCK)
                JOIN InnodisTestDB.INLPROD.ITMFACILIT f1 WITH (NOLOCK) ON f0.ITMREF_0 = f1.ITMREF_0
                WHERE f1.STOFCY_0 = @Site";
            var productsTask = FetchFromInnodisAsync<ProductLookupDto>(productsSql, new { Site = site });

            // Execute tasks in parallel
            await Task.WhenAll(ordersTask, detailsTask, customersTask, repsTask, locationsTask, productsTask);

            package.Orders = ordersTask.Result.ToList();
            package.Details = detailsTask.Result.ToList();
            package.Customers = customersTask.Result.ToList();
            package.Reps = repsTask.Result.ToList();
            package.Locations = locationsTask.Result.ToList();
            package.Products = productsTask.Result.ToList();

            // 5.5 Include Cut & Bulk Entries from ScanProduction (Sequential due to DbContext thread safety)
            var cutsBulkEntities = await _scanContext.CutBulkEntries
                .Where(e => e.SyncStatus == "Synced")
                .ToListAsync();

            var cutsBulkDetails = await _scanContext.SalesOrderDetailCutsBulk
                .Where(d => d.SyncStatus == "Synced")
                .ToListAsync();

            // 6. Aggregate Production Scans for EXTERNAL orders ONLY (Internal orders use persisted totals)
            var orderNumbers = package.Orders.Select(o => o.SohNum).ToList();
            
            var externalScanAggregates = await _scanContext.ProductionScans
                .Where(s => orderNumbers.Contains(s.SoNumber) && !s.IsDeleted)
                .GroupBy(s => new { s.SoNumber, s.ItemCode })
                .Select(g => new {
                    g.Key.SoNumber,
                    g.Key.ItemCode,
                    TotalCalculated = g.Sum(s => s.ScanAmountKg)
                })
                .ToListAsync();

            // Update External Order Details
            foreach (var detail in package.Details)
            {
                var aggregate = externalScanAggregates.FirstOrDefault(a => 
                    a.SoNumber == detail.SoNumber && 
                    a.ItemCode == detail.ItemCode);
                
                if (aggregate != null)
                {
                    detail.Manufactured = aggregate.TotalCalculated;
                    detail.Remaining = Math.Max(0, detail.Quantity - detail.Manufactured);
                }
                else
                {
                    detail.Remaining = detail.Quantity;
                }
            }

            // 7. Process Internal Orders (Virtual Orders) - RECONCILIATION
            foreach (var cb in cutsBulkEntities)
            {
                // Create Virtual Order Header
                package.Orders.Add(new SalesOrderHeaderDto
                {
                    SohNum = cb.EntryNumber,
                    PoNo = cb.PoNumber ?? "",
                    OrderDate = cb.Date,
                    DeliveryDate = cb.Date,
                    CustomerCode = cb.CustomerCode,
                    CustomerName = cb.CustomerName,
                    Rep0 = cb.Salesman1Code ?? "",
                    Rep1 = cb.Salesman2Code ?? "",
                    Site = site,
                    Status = 1, // Open
                    Source = "Internal"
                });

                // Map to legacy CutBulkEntryDto for backward compatibility if needed
                var detail = cutsBulkDetails.FirstOrDefault(d => d.SoNumber == cb.EntryNumber);
                var manufactured = detail?.ManufacturedQuantity ?? 0;

                package.CutBulkEntries.Add(new CutBulkEntryDto {
                    EntryNumber = cb.EntryNumber,
                    Type = cb.Type,
                    CustomerCode = cb.CustomerCode,
                    CustomerName = cb.CustomerName,
                    Date = cb.Date,
                    AmountKg = cb.AmountKg,
                    ManufacturedQuantity = manufactured,
                    RemainingQuantity = Math.Max(0, cb.AmountKg - manufactured)
                });

                // Create Virtual Order Detail
                if (detail != null)
                {
                    package.Details.Add(new SalesOrderDetailDto
                    {
                        SoNumber = cb.EntryNumber,
                        ItemCode = detail.ItemCode,
                        Description = detail.Description,
                        BarcodeType = "Internal",
                        Quantity = detail.Quantity,
                        Manufactured = manufactured,
                        Remaining = Math.Max(0, detail.Quantity - manufactured)
                    });
                }
            }

            return package;
        }

        private async Task<IEnumerable<T>> FetchFromInnodisAsync<T>(string sql, object? parameters = null)
        {
            using IDbConnection db = new SqlConnection(_connectionString);
            return await db.QueryAsync<T>(sql, parameters);
        }

        public async Task<int> PushUpdatesAsync(SyncPushRequestDto request)
        {
            int totalCount = 0;

            // 1. Process Production Scans (to ScanProduction DB)
            if (request.Scans != null && request.Scans.Any())
            {
                using var scanTransaction = await _scanContext.Database.BeginTransactionAsync();
                try
                {
                    foreach (var scanDto in request.Scans)
                    {
                        var entity = new ProductionScan
                        {
                            ItemCode = scanDto.ItemCode ?? string.Empty,
                            LineNo = scanDto.LineNo,
                            ScanAmountKg = scanDto.ScanAmountKg,
                            SoNumber = scanDto.SoNumber ?? string.Empty,
                            OrderStatus = scanDto.OrderStatus,
                            ItemStatus = scanDto.ItemStatus ?? "Q",
                            Location = scanDto.Location,
                            Lot = scanDto.Lot,
                            CreatedBy = scanDto.CreatedBy ?? "system",
                            CreatedAt = DateTime.UtcNow
                        };
                        _scanContext.ProductionScans.Add(entity);

                        // RECONCILIATION: Update persisted totals for Internal Orders (Cut/Bulk)
                        var internalDetail = await _scanContext.SalesOrderDetailCutsBulk
                            .FirstOrDefaultAsync(d => d.SoNumber == scanDto.SoNumber && d.ItemCode == scanDto.ItemCode);
                        
                        if (internalDetail != null)
                        {
                            internalDetail.ManufacturedQuantity += scanDto.ScanAmountKg;
                        }
                    }
                    totalCount += await _scanContext.SaveChangesAsync();
                    await scanTransaction.CommitAsync();
                }
                catch
                {
                    await scanTransaction.RollbackAsync();
                    throw;
                }
            }

            // 2. Process Cut & Bulk Entries (Atomic Overwrite in ScanProduction DB)
            if (request.CutBulkEntries != null && request.CutBulkEntries.Any())
            {
                using var syncTransaction = await _scanContext.Database.BeginTransactionAsync();
                try
                {
                    var entryNumbersToRenew = request.CutBulkEntries.Select(e => e.EntryNumber).ToList();

                    // PERFORMANCE: Use Atomic Delete-then-Insert strategy for enterprise data freshness (v13 Isolation)
                    var existingHeaders = await _scanContext.CutBulkEntries
                        .Where(e => entryNumbersToRenew.Contains(e.EntryNumber))
                        .ToListAsync();
                    
                    var existingDetails = await _scanContext.SalesOrderDetailCutsBulk
                        .Where(d => entryNumbersToRenew.Contains(d.SoNumber))
                        .ToListAsync();

                    if (existingHeaders.Any()) _scanContext.CutBulkEntries.RemoveRange(existingHeaders);
                    if (existingDetails.Any()) _scanContext.SalesOrderDetailCutsBulk.RemoveRange(existingDetails);

                    foreach (var cbDto in request.CutBulkEntries)
                    {
                        var entryEntity = new CutBulkEntry
                        {
                            EntryNumber = cbDto.EntryNumber,
                            Type = cbDto.Type,
                            CustomerCode = cbDto.CustomerCode,
                            CustomerName = cbDto.CustomerName,
                            Date = cbDto.Date,
                            PoNumber = cbDto.PoNumber,
                            Salesman1Code = cbDto.Salesman1Code,
                            Salesman2Code = cbDto.Salesman2Code,
                            AmountKg = cbDto.AmountKg,
                            SyncStatus = "Synced",
                            DeviceId = request.DeviceId,
                            SyncTimestamp = DateTime.UtcNow
                        };

                        var detailEntity = new SalesOrderDetailCutsBulk
                        {
                            SoNumber = cbDto.EntryNumber,
                            ItemCode = cbDto.Type == "Cuts" ? "PROD-CUT" : "PROD-BLK",
                            Description = cbDto.Type == "Cuts" ? "Internal Production - Cuts" : "Internal Production - Bulk",
                            Quantity = cbDto.AmountKg,
                            SyncStatus = "Synced",
                            CreatedAt = DateTime.UtcNow
                        };

                        _scanContext.CutBulkEntries.Add(entryEntity);
                        _scanContext.SalesOrderDetailCutsBulk.Add(detailEntity);
                    }

                    await _scanContext.SaveChangesAsync();
                    await syncTransaction.CommitAsync();
                    totalCount += request.CutBulkEntries.Count;
                }
                catch
                {
                    await syncTransaction.RollbackAsync();
                    throw;
                }
            }

            return totalCount;
        }
    }
}
