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

namespace EnterpriseAuth.Api.Infrastructure.Persistence
{
    public class EfLogisticsRepository : ILogisticsRepository
    {
        private readonly string _connectionString;
        private readonly ApplicationDbContext _context;
        private readonly ScanProductionDbContext _scanContext;

        public EfLogisticsRepository(IConfiguration configuration, ApplicationDbContext context, ScanProductionDbContext scanContext)
        {
            _connectionString = configuration.GetConnectionString("Innodis") 
                                ?? throw new System.ArgumentNullException("Innodis connection string is missing");
            _context = context;
            _scanContext = scanContext;
        }

        public async Task<IEnumerable<ProductionTrackingDto>> GetProductionTrackingAsync()
        {
            using IDbConnection db = new SqlConnection(_connectionString);
            
            var sql = @"
                SELECT TOP 100
                    f0.SOHNUM_0 COLLATE DATABASE_DEFAULT as SoNumber,
                    f1.STOFCY_0 COLLATE DATABASE_DEFAULT as Site,
                    LTRIM(RTRIM(f2.ITMREF_0)) COLLATE DATABASE_DEFAULT as ItemCode,
                    LTRIM(RTRIM(f2.ITMDES1_0)) COLLATE DATABASE_DEFAULT as Description,
                    'Variable Weight' COLLATE DATABASE_DEFAULT as BarcodeType,
                    f1.QTY_0 as Quantity,
                    f1.LOC_0 COLLATE DATABASE_DEFAULT as Location,
                    f0.BPCORD_0 COLLATE DATABASE_DEFAULT as CustomerCode,
                    c.ZFULLBUSNAM_0 COLLATE DATABASE_DEFAULT as CustomerName
                FROM InnodisTestDB.INLPROD.SORDER f0
                JOIN InnodisTestDB.INLPROD.SORDERQ f1 on f0.SOHNUM_0 = f1.SOHNUM_0
                JOIN InnodisTestDB.INLPROD.ITMMASTER f2 on f1.ITMREF_0 = f2.ITMREF_0
                JOIN InnodisTestDB.INLPROD.ZBTBORD f3 on f0.SOHNUM_0 = f3.ORISONO_0
                LEFT JOIN InnodisTestDB.INLPROD.BPCUSTOMER c on f0.BPCORD_0 = c.BPCNUM_0
                WHERE 1=1";

            var parameters = new DynamicParameters();

            sql += " ORDER BY f0.ORDDAT_0 DESC";

            var sageItems = (await db.QueryAsync<ProductionTrackingDto>(sql, parameters)).ToList();

            // Fetch Local Bulk/Cuts and map them individually
            var localEntries = await _scanContext.CutBulkEntries.ToListAsync();
            var localDetails = await _scanContext.SalesOrderDetailCutsBulk.ToListAsync();

            var localItems = localDetails.Select(d => {
                var header = localEntries.FirstOrDefault(e => e.EntryNumber == d.SoNumber);
                return new ProductionTrackingDto
                {
                    SoNumber = d.SoNumber,
                    ItemCode = d.ItemCode,
                    Description = d.Description,
                    Quantity = d.Quantity,
                    Site = "IPL",
                    Location = "PROD",
                    CustomerCode = header?.CustomerCode ?? "",
                    CustomerName = header?.CustomerName ?? ""
                };
            }).ToList();

            var combinedItems = localItems.Concat(sageItems).ToList();

            // Calculate Manufactured for each item
            var soNumbers = combinedItems.Select(x => x.SoNumber).Where(x => !string.IsNullOrEmpty(x)).Distinct().ToList();
            var itemCodes = combinedItems.Select(x => x.ItemCode).Where(x => !string.IsNullOrEmpty(x)).Distinct().ToList();

            var scans = new List<ProductionScan>();
            if (soNumbers.Any() && itemCodes.Any())
            {
                scans = await _scanContext.ProductionScans
                    .Where(s => soNumbers.Contains(s.SoNumber) && itemCodes.Contains(s.ItemCode) && !s.IsDeleted && s.ItemStatus == "A")
                    .ToListAsync();
            }

            foreach (var item in combinedItems)
            {
                var manufactured = scans
                    .Where(s => s.SoNumber == item.SoNumber && s.ItemCode == item.ItemCode)
                    .Sum(s => s.ScanAmountKg);

                item.Manufactured = manufactured;
                item.Remaining = (item.Quantity ?? 0m) - manufactured;
                if (string.IsNullOrEmpty(item.Site)) item.Site = "IPL"; // Default
            }

            return combinedItems.OrderByDescending(x => x.Quantity);
        }

        public async Task<IEnumerable<SalesOrderHeaderDto>> GetSalesOrderHeadersAsync(int? status, DateTime? date, string? customerCode, string? rep0, string? rep1)
        {
            using IDbConnection db = new SqlConnection(_connectionString);

            var sql = @"
                SELECT 
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
                    CAST('External' AS NVARCHAR(20)) COLLATE DATABASE_DEFAULT as [Source]
                FROM InnodisTestDB.INLPROD.SORDER f0
                JOIN InnodisTestDB.INLPROD.ZBTBORD f2 ON f0.SOHNUM_0 = f2.ORISONO_0
                JOIN InnodisTestDB.INLPROD.BPCUSTOMER c ON f0.BPCORD_0 = c.BPCNUM_0
                WHERE 1=1";

            var parameters = new DynamicParameters();

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

            if (!string.IsNullOrEmpty(rep0))
            {
                sql += " AND f0.REP_0 = @Rep0";
                parameters.Add("Rep0", rep0);
            }

            if (!string.IsNullOrEmpty(rep1))
            {
                sql += " AND f0.REP_1 = @Rep1";
                parameters.Add("Rep1", rep1);
            }

            sql += @"
                UNION ALL
                SELECT 
                    EntryNumber COLLATE DATABASE_DEFAULT as [SohNum],
                    ISNULL(PoNumber, '') COLLATE DATABASE_DEFAULT as [PoNo],
                    Date as [OrderDate],
                    Date as [DeliveryDate],
                    CustomerCode COLLATE DATABASE_DEFAULT as [CustomerCode],
                    CustomerName COLLATE DATABASE_DEFAULT as [CustomerName],
                    ISNULL(Salesman1Code, '') COLLATE DATABASE_DEFAULT as [Rep0],
                    ISNULL(Salesman2Code, '') COLLATE DATABASE_DEFAULT as [Rep1],
                    CAST('INTERNAL' AS NVARCHAR(20)) COLLATE DATABASE_DEFAULT as [Site],
                    1 as [Status],
                    CAST('Internal' AS NVARCHAR(20)) COLLATE DATABASE_DEFAULT as [Source]
                FROM [ScanProduction].[dbo].[cut_bulk_entries]
                WHERE 1=1";

            if (date.HasValue)
            {
                sql += " AND CAST(Date as DATE) = @Date";
            }

            if (!string.IsNullOrEmpty(customerCode))
            {
                sql += " AND CustomerCode = @CustomerCode";
            }

            if (!string.IsNullOrEmpty(rep0))
            {
                sql += " AND Salesman1Code = @Rep0";
            }

            if (!string.IsNullOrEmpty(rep1))
            {
                sql += " AND Salesman2Code = @Rep1";
            }

            sql += " ORDER BY [OrderDate] DESC";

            var allHeaders = (await db.QueryAsync<SalesOrderHeaderDto>(sql, parameters)).ToList();

            // Override status from ScanProduction table (a locally closed order has OrderStatus = "2")
            var allSoNumbers = allHeaders.Select(h => h.SohNum).ToList();
            if (allSoNumbers.Any())
            {
                var closedSoNumbers = await _scanContext.ProductionScans
                    .Where(s => allSoNumbers.Contains(s.SoNumber) && s.OrderStatus == "2" && !s.IsDeleted)
                    .Select(s => s.SoNumber)
                    .Distinct()
                    .ToListAsync();

                foreach (var header in allHeaders)
                {
                    if (closedSoNumbers.Contains(header.SohNum))
                        header.Status = 2;
                }
            }

            // Apply status filter after merge
            if (status.HasValue)
            {
                allHeaders = allHeaders.Where(h => h.Status == status.Value).ToList();
            }

            return allHeaders.OrderByDescending(h => h.OrderDate);
        }

        public async Task<IEnumerable<SalesOrderDetailDto>> GetSalesOrderDetailsAsync(string soNumber)
        {
            using IDbConnection db = new SqlConnection(_connectionString);
            const string sql = @"
                SELECT 
                    f0.SOHNUM_0 as SoNumber,
                    f2.ITMREF_0 as ItemCode,
                    f2.ITMDES1_0 as Description,
                    'Variable Weight' as BarcodeType,
                    f1.QTY_0 as Quantity,
                    0.0 as Remaining, 
                    0.0 as Manufactured       
                FROM InnodisTestDB.INLPROD.SORDER f0
                JOIN InnodisTestDB.INLPROD.SORDERQ f1 on f0.SOHNUM_0 = f1.SOHNUM_0
                JOIN InnodisTestDB.INLPROD.ITMMASTER f2 on f1.ITMREF_0 = f2.ITMREF_0
                JOIN InnodisTestDB.INLPROD.ZBTBORD f3 on f0.SOHNUM_0 = f3.ORISONO_0
                WHERE f0.SOHNUM_0 = @SoNumber
                
                UNION ALL
                
                SELECT 
                    SoNumber COLLATE DATABASE_DEFAULT as SoNumber,
                    ItemCode COLLATE DATABASE_DEFAULT as ItemCode,
                    Description COLLATE DATABASE_DEFAULT as Description,
                    BarcodeType COLLATE DATABASE_DEFAULT as BarcodeType,
                    Quantity,
                    0.0 as Remaining,
                    0.0 as Manufactured
                FROM [ScanProduction].[dbo].[salesorderdetailscutsbulk]
                WHERE SoNumber = @SoNumber";

            var details = (await db.QueryAsync<SalesOrderDetailDto>(sql, new { SoNumber = soNumber })).ToList();

            // Fetch Scans from separate context and join in memory to avoid cross-DB permission issues
            var scans = await _scanContext.ProductionScans
                .Where(s => s.SoNumber == soNumber && !s.IsDeleted && s.ItemStatus == "A")
                .GroupBy(s => s.ItemCode)
                .Select(g => new { ItemCode = g.Key, TotalAmount = g.Sum(x => x.ScanAmountKg) })
                .ToListAsync();

            foreach (var detail in details)
            {
                var scanSum = scans.FirstOrDefault(s => s.ItemCode == detail.ItemCode)?.TotalAmount ?? 0m;
                detail.Remaining = (detail.Quantity ?? 0m) - scanSum;
                detail.Manufactured = scanSum;
            }

            return details;
        }

        public async Task<IEnumerable<CustomerLookupDto>> GetCustomerLookupAsync()
        {
            using IDbConnection db = new SqlConnection(_connectionString);
            const string sql = @"
                SELECT DISTINCT 
                    LTRIM(RTRIM(BPCNUM_0)) as Code, 
                    LTRIM(RTRIM(ZFULLBUSNAM_0)) as Name 
                FROM InnodisTestDB.INLPROD.BPCUSTOMER
                WHERE ZFULLBUSNAM_0 IS NOT NULL AND ZFULLBUSNAM_0 <> ''
                ORDER BY Name";
            return await db.QueryAsync<CustomerLookupDto>(sql);
        }

        public async Task<IEnumerable<SalesRepLookupDto>> GetSalesRepLookupAsync()
        {
            using IDbConnection db = new SqlConnection(_connectionString);
            const string sql = @"
                SELECT DISTINCT 
                    LTRIM(RTRIM(REPNUM_0)) as Code, 
                    LTRIM(RTRIM(REPNAM_0)) as Name 
                FROM InnodisTestDB.INLPROD.SALESREP
                WHERE REPNAM_0 IS NOT NULL AND REPNAM_0 <> ''
                ORDER BY Name";
            return await db.QueryAsync<SalesRepLookupDto>(sql);
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
        public async Task<string> SaveCutBulkEntryAsync(CutBulkEntryDto dto)
        {
            string soNumber = dto.ExistingSoNumber;
            bool isNew = string.IsNullOrEmpty(soNumber);

            if (isNew)
            {
                var today = DateTime.Now;
                var dateStr = today.ToString("yyyyMMdd");
                
                // Simple unique ID logic: count today's entries
                int count = _scanContext.CutBulkEntries.Count(e => e.EntryNumber.StartsWith($"CB-{dateStr}"));
                soNumber = $"CB-{dateStr}-{(count + 1):D4}";

                var entryEntity = new EnterpriseAuth.Api.Core.Domain.Entities.CutBulkEntry
                {
                    EntryNumber = soNumber,
                    Type = dto.Type,
                    CustomerCode = dto.CustomerCode ?? string.Empty,
                    CustomerName = dto.CustomerName ?? string.Empty,
                    Date = dto.Date ?? DateTime.Now,
                    PoNumber = dto.PoNumber,
                    Salesman1Code = dto.Salesman1Code,
                    Salesman2Code = dto.Salesman2Code,
                    AmountKg = dto.AmountKg,
                    SyncStatus = "Local",
                    SyncTimestamp = DateTime.UtcNow
                };

                var detailEntity = new SalesOrderDetailCutsBulk
                {
                    SoNumber = soNumber,
                    ItemCode = !string.IsNullOrEmpty(dto.ItemCode) ? dto.ItemCode : (dto.Type == "Cuts" ? "PROD-CUT" : "PROD-BLK"),
                    Description = !string.IsNullOrEmpty(dto.ProductName) ? dto.ProductName : (dto.Type == "Cuts" ? "Internal Production - Cuts" : "Internal Production - Bulk"),
                    Quantity = 0m, // Ordered amount must always be zero for Cut/Bulk entries
                    SyncStatus = "Local",
                    CreatedAt = DateTime.UtcNow
                };

                _scanContext.CutBulkEntries.Add(entryEntity);
                _scanContext.SalesOrderDetailCutsBulk.Add(detailEntity);
            }

            // Always create a production scan for this entry to update manufactured quantity
            var scan = new ProductionScan
            {
                SoNumber = soNumber,
                ItemCode = !string.IsNullOrEmpty(dto.ItemCode) ? dto.ItemCode : (dto.Type == "Cuts" ? "PROD-CUT" : "PROD-BLK"),
                ScanAmountKg = dto.AmountKg,
                LineNo = 1,
                OrderStatus = "1", // Open
                ItemStatus = "A",   // Accepted
                Location = "PROD",
                Lot = "INTERNAL",
                CreatedBy = "mobile-user",
                CreatedAt = DateTime.UtcNow
            };

            _scanContext.ProductionScans.Add(scan);
            await _scanContext.SaveChangesAsync();

            return soNumber;
        }

        public async Task<ProductionScanDto> SaveProductionScanAsync(ProductionScanDto scanDto)
        {
            using var transaction = await _scanContext.Database.BeginTransactionAsync();
            try
            {
                var entity = new ProductionScan
                {
                    ItemCode = scanDto.ItemCode ?? string.Empty,
                    LineNo = scanDto.LineNo,
                    ScanAmountKg = scanDto.ScanAmountKg,
                    SoNumber = scanDto.SoNumber ?? string.Empty,
                    OrderStatus = scanDto.OrderStatus ?? "1",
                    ItemStatus = scanDto.ItemStatus ?? "Q",
                    Location = scanDto.Location ?? string.Empty,
                    Lot = scanDto.Lot,
                    CreatedBy = scanDto.CreatedBy ?? "system",
                    CreatedAt = DateTime.UtcNow
                };

                _scanContext.ProductionScans.Add(entity);
                await _scanContext.SaveChangesAsync();

                // Generate Audit Log
                var audit = new AuditLog
                {
                    EntityName = "production_scan",
                    EntityId = entity.ScanId,
                    ActionType = "INSERT",
                    Payload = System.Text.Json.JsonSerializer.Serialize(entity),
                    PerformedBy = entity.CreatedBy,
                    PerformedAt = DateTime.UtcNow
                };
                _scanContext.AuditLogs.Add(audit);
                await _scanContext.SaveChangesAsync();

                await transaction.CommitAsync();

                scanDto.ScanId = entity.ScanId;
                scanDto.CreatedAt = entity.CreatedAt;
                return scanDto;
            }
            catch
            {
                await transaction.RollbackAsync();
                throw;
            }
        }

        public async Task<IEnumerable<LocationLookupDto>> GetLocationLookupsAsync(string site)
        {
            using IDbConnection db = new SqlConnection(_connectionString);
            var sql = @"
                SELECT 
                    T1.STOFCY_0 as Site,
                    T1.LOC_0 as Location,
                    T1.WRH_0 as Warehouse,
                    T1.WRHNAM_0 as WarehouseName,
                    T1.LOCTYP_0 as LocationType,
                    ATRA.TEXTE_0 as LocationTypeName
                FROM (
                    SELECT
                        STOL.STOFCY_0,
                        STOL.LOC_0,
                        STOL.WRH_0,
                        WRH.WRHNAM_0,
                        STOL.LOCTYP_0
                    FROM InnodisTestDB.INLPROD.STOLOC STOL 
                    LEFT JOIN InnodisTestDB.INLPROD.WAREHOUSE WRH on WRH.WRH_0 = STOL.WRH_0 
                    WHERE STOL.STOFCY_0 = @Site
                ) AS T1 
                LEFT JOIN InnodisTestDB.INLPROD.[ATEXTRA] ATRA on T1.STOFCY_0 = ATRA.IDENT1_0 
                    and T1.LOCTYP_0 = ATRA.IDENT2_0 
                    and ATRA.CODFIC_0 = 'TABLOCTYP' 
                    and ATRA.LANGUE_0 = 'BRI' 
                    and ATRA.ZONE_0 = 'TYPDESAXX'";

            return await db.QueryAsync<LocationLookupDto>(sql, new { Site = site });
        }

        public async Task<bool> CloseOrderAsync(string soNumber, string closedBy)
        {
            // Check if there's already a close record for this SO
            var existing = await _scanContext.ProductionScans
                .FirstOrDefaultAsync(s => s.SoNumber == soNumber && s.OrderStatus == "2" && !s.IsDeleted);

            if (existing != null)
                return true; // Already closed

            // Insert a sentinel scan record marking the order as closed
            var entity = new ProductionScan
            {
                ItemCode = "ORDER-CLOSE",
                LineNo = 0,
                ScanAmountKg = 0m,
                SoNumber = soNumber,
                OrderStatus = "2",
                ItemStatus = "A",
                CreatedBy = closedBy,
                CreatedAt = DateTime.UtcNow
            };

            _scanContext.ProductionScans.Add(entity);

            var audit = new AuditLog
            {
                EntityName = "production_scan",
                EntityId = 0,
                ActionType = "CLOSE_ORDER",
                Payload = $"{{\"soNumber\":\"{soNumber}\",\"closedBy\":\"{closedBy}\"}}",
                PerformedBy = closedBy,
                PerformedAt = DateTime.UtcNow
            };
            _scanContext.AuditLogs.Add(audit);

            await _scanContext.SaveChangesAsync();
            return true;
        }
    }
}
