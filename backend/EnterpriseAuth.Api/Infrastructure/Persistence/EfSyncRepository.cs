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

namespace EnterpriseAuth.Api.Infrastructure.Persistence
{
    public class EfSyncRepository : ISyncRepository
    {
        private readonly string _connectionString;
        private readonly ApplicationDbContext _context;
        private readonly ScanProductionDbContext _scanContext;

        public EfSyncRepository(IConfiguration configuration, ApplicationDbContext context, ScanProductionDbContext scanContext)
        {
            _connectionString = configuration.GetConnectionString("Innodis") 
                                ?? throw new ArgumentNullException("Innodis connection string is missing");
            _context = context;
            _scanContext = scanContext;
        }

        public async Task<SyncPackageDto> GetRefreshPackageAsync(string site)
        {
            using IDbConnection db = new SqlConnection(_connectionString);
            var package = new SyncPackageDto();

            // 1. Fetch Orders (Header + joined info)
            var ordersSql = @"
                SELECT TOP 200
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
                ORDER BY f0.ORDDAT_0 DESC";

            package.Orders = (await db.QueryAsync<SalesOrderHeaderDto>(ordersSql)).ToList();

            // 2. Fetch Details
            var detailsSql = @"
                SELECT 
                    f0.SOHNUM_0 as SoNumber,
                    f2.ITMREF_0 as ItemCode,
                    f2.ITMDES1_0 as Description,
                    'Variable Weight' as BarcodeType,
                    f1.QTY_0 as Quantity
                FROM InnodisTestDB.INLPROD.SORDER f0 WITH (NOLOCK)
                JOIN InnodisTestDB.INLPROD.SORDERQ f1 WITH (NOLOCK) on f0.SOHNUM_0 = f1.SOHNUM_0
                JOIN InnodisTestDB.INLPROD.ITMMASTER f2 WITH (NOLOCK) on f1.ITMREF_0 = f2.ITMREF_0
                WHERE f0.SOHNUM_0 IN (SELECT TOP 200 SOHNUM_0 FROM InnodisTestDB.INLPROD.SORDER ORDER BY ORDDAT_0 DESC)";

            package.Details = (await db.QueryAsync<SalesOrderDetailDto>(detailsSql)).ToList();

            // 3. Lookups
            package.Customers = (await db.QueryAsync<CustomerLookupDto>("SELECT DISTINCT BPCNUM_0 as Code, ZFULLBUSNAM_0 as Name FROM InnodisTestDB.INLPROD.BPCUSTOMER WITH (NOLOCK)")).ToList();
            package.Reps = (await db.QueryAsync<SalesRepLookupDto>("SELECT DISTINCT REPNUM_0 as Code, REPNAM_0 as Name FROM InnodisTestDB.INLPROD.SALESREP WITH (NOLOCK)")).ToList();
            
            // 4. Locations
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
            
            package.Locations = (await db.QueryAsync<LocationLookupDto>(locSql, new { Site = site })).ToList();

            return package;
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
