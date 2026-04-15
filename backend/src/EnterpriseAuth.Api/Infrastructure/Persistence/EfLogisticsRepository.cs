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

using Microsoft.Extensions.Options;
using EnterpriseAuth.Api.Core.Application.Common;

namespace EnterpriseAuth.Api.Infrastructure.Persistence
{
    public class EfLogisticsRepository : ILogisticsRepository
    {
        private readonly string _connectionString;
        private readonly ApplicationDbContext _context;
        private readonly ScanProductionDbContext _scanContext;
        private readonly SyncSettings _syncSettings;

        public EfLogisticsRepository(IConfiguration configuration, ApplicationDbContext context, ScanProductionDbContext scanContext, IOptions<SyncSettings> syncSettings)
        {
            _connectionString = configuration.GetConnectionString("Innodis") 
                                ?? throw new System.ArgumentNullException("Innodis connection string is missing");
            _context = context;
            _scanContext = scanContext;
            _syncSettings = syncSettings.Value;
        }

        public async Task<IEnumerable<ProductionTrackingDto>> GetProductionTrackingAsync(string? siteCode)
        {
            // Read from optimized aggregated states
            var query = _scanContext.ProductionLineStates
                .Include(s => s.OrderLine)
                .ThenInclude(l => l.Order)
                .AsNoTracking();

            if (!string.IsNullOrEmpty(siteCode))
            {
                query = query.Where(s => s.OrderLine.Order.Site == siteCode);
            }

            // Exclude closed orders from active production tracking
            query = query.Where(s => s.OrderLine.Order.Status != 2);

            var states = await query
                .OrderByDescending(s => s.OrderLine.Order.OrderDate)
                .Take(500) // Performance safety
                .ToListAsync();

            var results = states.Select(s => new ProductionTrackingDto
            {
                SoNumber = s.OrderLine.Order.SourceOrderId,
                ItemCode = s.OrderLine.ItemCode,
                Description = s.OrderLine.Description,
                Quantity = s.OrderLine.OrderedQuantity,
                Manufactured = s.TotalManufacturedQty,
                Remaining = Math.Max(0m, s.OrderLine.OrderedQuantity - s.TotalManufacturedQty),
                Site = s.OrderLine.Order.Site ?? "IPL",
                Location = "PROD",
                CustomerCode = s.OrderLine.Order.CustomerCode,
                CustomerName = s.OrderLine.Order.CustomerName,
                PoNumber = s.OrderLine.Order.PoNumber,
                Salesman = s.OrderLine.Order.Salesman,
                IsPrepared = s.IsPrepared || s.IsLineCompleted
            })
            .OrderByDescending(x => x.Quantity)
            .ToList();

            return results;
        }

        public async Task<IEnumerable<SalesOrderHeaderDto>> GetSalesOrderHeadersAsync(int? status, DateTime? date, string? customerCode, string? rep0, string? rep1)
        {
            // Read from centralized SalesOrder table
            var query = _scanContext.SalesOrders.AsNoTracking();

            if (status.HasValue)
            {
                query = query.Where(o => o.Status == status.Value);
            }

            if (date.HasValue)
            {
                var targetDate = date.Value.Date;
                query = query.Where(o => o.DeliveryDate >= targetDate && o.DeliveryDate < targetDate.AddDays(1));
            }

            if (!string.IsNullOrEmpty(customerCode))
            {
                query = query.Where(o => o.CustomerCode == customerCode);
            }

            if (!string.IsNullOrEmpty(rep0))
            {
                query = query.Where(o => o.Salesman.Contains(rep0));
            }

            if (!string.IsNullOrEmpty(rep1))
            {
                query = query.Where(o => o.Salesman.Contains(rep1));
            }

            var orders = await query
                .OrderByDescending(o => o.OrderDate)
                .Take(500)
                .ToListAsync();

            // Fetch shipment preparation statuses from OrderShipmentStatus (KEPT table)
            var soNumbers = orders.Select(o => o.SourceOrderId).ToList();
            var shipmentStatuses = await _scanContext.OrderShipmentStatuses
                .Where(s => soNumbers.Contains(s.SoNumber) && s.IsPreparedForShipment)
                .Select(s => s.SoNumber)
                .ToListAsync();

            return orders.Select(o => new SalesOrderHeaderDto
            {
                SohNum = o.SourceOrderId,
                PoNo = o.PoNumber ?? "",
                OrderDate = o.OrderDate,
                DeliveryDate = o.DeliveryDate,
                CustomerCode = o.CustomerCode,
                CustomerName = o.CustomerName,
                Rep0 = o.Salesman,
                Rep1 = "",
                Site = o.Site,
                Status = o.Status,
                Source = o.SourceSystem,
                IsPreparedForShipment = shipmentStatuses.Contains(o.SourceOrderId)
            });
        }

        public async Task<IEnumerable<SalesOrderDetailDto>> GetSalesOrderDetailsAsync(string soNumber)
        {
            // Read from optimized aggregated states linked to unified lines
            var states = await _scanContext.ProductionLineStates
                .Include(s => s.OrderLine)
                .ThenInclude(l => l.Order)
                .Where(s => s.OrderLine.Order.SourceOrderId == soNumber)
                .AsNoTracking()
                .ToListAsync();

            return states.Select(s => new SalesOrderDetailDto
            {
                SoNumber = s.OrderLine.Order.SourceOrderId,
                ItemCode = s.OrderLine.ItemCode,
                Description = s.OrderLine.Description,
                BarcodeType = "Variable Weight",
                Quantity = s.OrderLine.OrderedQuantity,
                Site = s.OrderLine.Order.Site,
                Remaining = Math.Max(0m, s.OrderLine.OrderedQuantity - s.TotalManufacturedQty),
                Manufactured = s.TotalManufacturedQty,
                IsPrepared = s.IsPrepared || s.IsLineCompleted
            });
        }

        public async Task<IEnumerable<CustomerLookupDto>> GetCustomerLookupAsync()
        {
            using IDbConnection db = new SqlConnection(_connectionString);
            string sql = $@"
                SELECT DISTINCT 
                    LTRIM(RTRIM(BPCNUM_0)) as Code, 
                    LTRIM(RTRIM(ZFULLBUSNAM_0)) as Name 
                FROM {_syncSettings.X3DatabaseName}.INLPROD.BPCUSTOMER
                WHERE ZFULLBUSNAM_0 IS NOT NULL AND ZFULLBUSNAM_0 <> ''
                ORDER BY Name";
            return await db.QueryAsync<CustomerLookupDto>(sql);
        }

        public async Task<IEnumerable<SalesRepLookupDto>> GetSalesRepLookupAsync()
        {
            using IDbConnection db = new SqlConnection(_connectionString);
            string sql = $@"
                SELECT DISTINCT 
                    LTRIM(RTRIM(REPNUM_0)) as Code, 
                    LTRIM(RTRIM(REPNAM_0)) as Name 
                FROM {_syncSettings.X3DatabaseName}.INLPROD.SALESREP
                WHERE REPNAM_0 IS NOT NULL AND REPNAM_0 <> ''
                ORDER BY Name";
            return await db.QueryAsync<SalesRepLookupDto>(sql);
        }

        public async Task<IEnumerable<string>> GetProductionSitesAsync()
        {
            using IDbConnection db = new SqlConnection(_connectionString);
            string sql = $"SELECT DISTINCT STOFCY_0 FROM {_syncSettings.X3DatabaseName}.INLPROD.STOLOC ORDER BY STOFCY_0";
            return await db.QueryAsync<string>(sql);
        }

        public async Task<IEnumerable<string>> GetLotsAsync(string itemCode, string siteCode)
        {
            using IDbConnection db = new SqlConnection(_connectionString);
            string sql = $@"
                SELECT DISTINCT LOT_0 
                FROM {_syncSettings.X3DatabaseName}.INLPROD.STOCK 
                WHERE ITMREF_0 = @ItemCode AND STOFCY_0 = @SiteCode AND QTYPCU_0 > 0
                ORDER BY LOT_0";
            return await db.QueryAsync<string>(sql, new { ItemCode = itemCode, SiteCode = siteCode });
        }

        public async Task<int> SyncScansAsync(IEnumerable<ScanDto> scans)
        {
            if (scans == null || !scans.Any()) return 0;

            using IDbConnection db = new SqlConnection(_connectionString);
            
            const string sql = @"
                INSERT INTO [{_syncSettings.AppDatabaseName}].[dbo].[MobileAppScans] 
                (SoNumber, ItemCode, ScannedQuantity, ScannedAt, ScannedBy, DeviceId)
                VALUES (@SoNumber, @ItemCode, @ScannedQuantity, @ScannedAt, @ScannedBy, @DeviceId)";

            int totalRows = 0;
            foreach (var scan in scans)
            {
                totalRows += await db.ExecuteAsync(sql, scan);
            }
            return totalRows;
        }

        public async Task<string> SaveCutBulkEntryAsync(CutBulkEntryDto dto, bool skipScan = false)
        {
            string soNumber = dto.ExistingSoNumber ?? string.Empty;
            bool isNew = string.IsNullOrEmpty(soNumber);

            if (isNew)
            {
                var today = DateTime.Now;
                var dateStr = today.ToString("yyyyMMdd");
                
                int count = _scanContext.SalesOrders.Count(e => e.SourceOrderId.StartsWith($"CB-{dateStr}"));
                soNumber = $"CB-{dateStr}-{(count + 1):D4}";

                // 1. Unified SalesOrder
                var order = new SalesOrder
                {
                    SourceOrderId = soNumber,
                    SourceSystem = "Internal",
                    CustomerCode = dto.CustomerCode ?? string.Empty,
                    CustomerName = dto.CustomerName ?? string.Empty,
                    OrderDate = dto.Date ?? DateTime.Now,
                    DeliveryDate = dto.Date ?? DateTime.Now,
                    PoNumber = dto.PoNumber,
                    Salesman = string.IsNullOrEmpty(dto.Salesman2Code) ? dto.Salesman1Code : $"{dto.Salesman1Code} / {dto.Salesman2Code}",
                    Site = "IPL",
                    Status = 1
                };
                _scanContext.SalesOrders.Add(order);

                // 2. Unified SalesOrderLine
                var itemCode = !string.IsNullOrEmpty(dto.ItemCode) ? dto.ItemCode : (dto.Type == "Cuts" ? "PROD-CUT" : "PROD-BLK");
                var line = new SalesOrderLine
                {
                    Order = order,
                    ItemCode = itemCode,
                    Description = !string.IsNullOrEmpty(dto.ProductName) ? dto.ProductName : (dto.Type == "Cuts" ? "Internal Production - Cuts" : "Internal Production - Bulk"),
                    OrderedQuantity = 0m,
                    LineNumber = 1,
                    LineStatus = 1
                };
                _scanContext.SalesOrderLines.Add(line);

                // 3. Initialize ProductionLineState
                var state = new ProductionLineState { OrderLine = line };
                _scanContext.ProductionLineStates.Add(state);

                await _scanContext.SaveChangesAsync();
            }

            if (!skipScan)
            {
                await SaveProductionScanAsync(new ProductionScanDto
                {
                    SoNumber = soNumber,
                    ItemCode = !string.IsNullOrEmpty(dto.ItemCode) ? dto.ItemCode : (dto.Type == "Cuts" ? "PROD-CUT" : "PROD-BLK"),
                    ScanAmountKg = dto.AmountKg,
                    ItemStatus = "A",
                    Location = "PROD",
                    Lot = "INTERNAL",
                    CreatedBy = "mobile-user"
                });
            }

            return soNumber;
        }

        public async Task<ProductionScanDto> SaveProductionScanAsync(ProductionScanDto scanDto)
        {
            using var transaction = await _scanContext.Database.BeginTransactionAsync();
            try
            {
                // Resolve the Order Line GUID
                var line = await _scanContext.SalesOrderLines
                    .Include(l => l.Order)
                    .FirstOrDefaultAsync(l => l.Order.SourceOrderId == scanDto.SoNumber && l.ItemCode == scanDto.ItemCode);

                if (line == null) throw new Exception($"Order Line not found: {scanDto.SoNumber} / {scanDto.ItemCode}");

                // 1. Insert Transaction (Append-Only)
                var entity = new ProductionScanTransaction
                {
                    SalesOrderLineId = line.Id,
                    ScanAmountKg = scanDto.ScanAmountKg,
                    Barcode = scanDto.Barcode,
                    LotNumber = scanDto.Lot,
                    Location = scanDto.Location ?? string.Empty,
                    ItemStatus = scanDto.ItemStatus ?? "Q",
                    SyncId = Guid.NewGuid().ToString(),
                    CreatedBy = scanDto.CreatedBy ?? "system",
                    CreatedAt = DateTime.UtcNow
                };

                _scanContext.ProductionScanTransactions.Add(entity);

                // 2. Update Aggregated State (ProductionLineState)
                var state = await _scanContext.ProductionLineStates.FindAsync(line.Id);
                if (state == null)
                {
                    state = new ProductionLineState { SalesOrderLineId = line.Id };
                    _scanContext.ProductionLineStates.Add(state);
                }
                
                state.TotalManufacturedQty += scanDto.ScanAmountKg;
                state.LastScanId = entity.Id;
                state.UpdatedAt = DateTime.UtcNow;

                await _scanContext.SaveChangesAsync();

                // Generate Audit Log
                var audit = new AuditLog
                {
                    EntityName = "ProductionScanTransactions",
                    EntityId = 0,
                    ActionType = "INSERT",
                    Payload = System.Text.Json.JsonSerializer.Serialize(entity),
                    PerformedBy = entity.CreatedBy ?? "system",
                    PerformedAt = DateTime.UtcNow
                };
                _scanContext.AuditLogs.Add(audit);
                await _scanContext.SaveChangesAsync();

                await transaction.CommitAsync();

                scanDto.ScanId = 0;
                scanDto.CreatedAt = entity.CreatedAt;
                return scanDto;
            }
            catch
            {
                await transaction.RollbackAsync();
                throw;
            }
        }

        public async Task<IEnumerable<ProductionScanDto>> GetProductionScansAsync(string soNumber, string itemCode)
        {
            var line = await _scanContext.SalesOrderLines
                .Include(l => l.Order)
                .AsNoTracking()
                .FirstOrDefaultAsync(l => l.Order.SourceOrderId == soNumber && l.ItemCode == itemCode);

            if (line == null) return new List<ProductionScanDto>();

            var transactions = await _scanContext.ProductionScanTransactions
                .Where(t => t.SalesOrderLineId == line.Id)
                .OrderByDescending(t => t.CreatedAt)
                .AsNoTracking()
                .ToListAsync();

            return transactions.Select(t => new ProductionScanDto
            {
                ScanId = null, // Id is Guid on entity; not mapped to int? ScanId
                SoNumber = soNumber,
                ItemCode = itemCode,
                ScanAmountKg = t.ScanAmountKg,
                Barcode = t.Barcode,
                Lot = t.LotNumber,
                Location = t.Location,
                ItemStatus = t.ItemStatus,
                CreatedBy = t.CreatedBy,
                CreatedAt = t.CreatedAt,
                SyncId = t.SyncId
            });
        }

        public async Task<int> SaveProductionScansBatchAsync(List<ProductionScanDto> scans)
        {
            if (scans == null || scans.Count == 0) return 0;
            
            // Assume all scans belong to the same SO and ItemCode for batch efficiency
            var firstScan = scans.First();
            var soNumber = firstScan.SoNumber;
            var itemCode = firstScan.ItemCode;

            using var transaction = await _scanContext.Database.BeginTransactionAsync();
            try
            {
                var line = await _scanContext.SalesOrderLines
                    .Include(l => l.Order)
                    .FirstOrDefaultAsync(l => l.Order.SourceOrderId == soNumber && l.ItemCode == itemCode);

                if (line == null) throw new Exception($"Order Line not found: {soNumber} / {itemCode}");

                var state = await _scanContext.ProductionLineStates.FindAsync(line.Id);
                if (state == null)
                {
                    state = new ProductionLineState { SalesOrderLineId = line.Id };
                    _scanContext.ProductionLineStates.Add(state);
                }

                decimal totalNewManufactured = 0m;
                var logsToInsert = new List<AuditLog>();

                foreach (var scanDto in scans)
                {
                    var entity = new ProductionScanTransaction
                    {
                        SalesOrderLineId = line.Id,
                        ScanAmountKg = scanDto.ScanAmountKg,
                        Barcode = scanDto.Barcode,
                        LotNumber = scanDto.Lot,
                        Location = scanDto.Location ?? string.Empty,
                        ItemStatus = scanDto.ItemStatus ?? "A",
                        SyncId = Guid.NewGuid().ToString(),
                        CreatedBy = scanDto.CreatedBy ?? "system",
                        CreatedAt = scanDto.CreatedAt ?? DateTime.UtcNow
                    };

                    _scanContext.ProductionScanTransactions.Add(entity);

                    if (entity.ItemStatus == "A")
                    {
                        totalNewManufactured += entity.ScanAmountKg;
                    }

                    logsToInsert.Add(new AuditLog
                    {
                        EntityName = "ProductionScanTransactions",
                        EntityId = 0,
                        ActionType = "INSERT_BATCH",
                        Payload = System.Text.Json.JsonSerializer.Serialize(new { entity.SalesOrderLineId, entity.Barcode, entity.ScanAmountKg }),
                        PerformedBy = entity.CreatedBy ?? "system",
                        PerformedAt = DateTime.UtcNow
                    });
                }

                state.TotalManufacturedQty += totalNewManufactured;
                state.UpdatedAt = DateTime.UtcNow;

                await _scanContext.SaveChangesAsync();
                
                // If there are scans, the last one gets its ID set in state.
                // But we don't strictly need to set LastScanId correctly if there are many.
                
                if (logsToInsert.Any())
                {
                    _scanContext.AuditLogs.AddRange(logsToInsert);
                    await _scanContext.SaveChangesAsync();
                }

                await transaction.CommitAsync();

                return scans.Count;
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
                    FROM {_syncSettings.X3DatabaseName}.INLPROD.STOLOC STOL 
                    LEFT JOIN {_syncSettings.X3DatabaseName}.INLPROD.WAREHOUSE WRH on WRH.WRH_0 = STOL.WRH_0 
                    WHERE STOL.STOFCY_0 = @Site
                ) AS T1 
                LEFT JOIN {_syncSettings.X3DatabaseName}.INLPROD.[ATEXTRA] ATRA on T1.STOFCY_0 = ATRA.IDENT1_0 
                    and T1.LOCTYP_0 = ATRA.IDENT2_0 
                    and ATRA.CODFIC_0 = 'TABLOCTYP' 
                    and ATRA.LANGUE_0 = 'BRI' 
                    and ATRA.ZONE_0 = 'TYPDESAXX'";

            return await db.QueryAsync<LocationLookupDto>(sql, new { Site = site });
        }

        public async Task<IEnumerable<LocationLookupDto>> GetTargetLocationsAsync(string site, string itemCode)
        {
            using IDbConnection db = new SqlConnection(_connectionString);
            var sql = @"
                SELECT DISTINCT
                    T1.[Site],
                    T1.[Location],
                    T1.[Warehouse],
                    '' as WarehouseName,
                    T1.[LocationType],
                    '' as LocationTypeName
                FROM (
                    select DISTINCT
                        f0.STOFCY_0 as [Site],
                        f0.ITMREF_0 as [Product],
                        f1.ITMDES1_0 as [Description],
                        f0.PCU_0 as [Unit],
                        f0.LOC_0 as [Location],
                        f0.LOCTYP_0 as [LocationType],
                        f0.WRH_0 as [Warehouse]
                    from {_syncSettings.X3DatabaseName}.INLPROD.STOCK f0
                    JOIN {_syncSettings.X3DatabaseName}.INLPROD.ITMMASTER f1 ON f0.ITMREF_0 = f1.ITMREF_0
                    LEFT JOIN {_syncSettings.X3DatabaseName}.INLPROD.STOLOT f2 ON f0.LOT_0 = f2.LOT_0
                ) as T1
                WHERE T1.Site = @Site AND T1.Product = @ItemCode";
            
            return await db.QueryAsync<LocationLookupDto>(sql, new { Site = site, ItemCode = itemCode });
        }

        // ===== STATUS METHODS =====

        public async Task<bool> UpdateItemPreparationStatusAsync(string soNumber, string itemCode, bool isPrepared)
        {
            return await UpsertProductionLineStatePreparationAsync(soNumber, itemCode, isPrepared);
        }

        public async Task<bool> UpdateOrderShipmentPreparationStatusAsync(string soNumber, bool isPrepared)
        {
            return await UpsertOrderShipmentStatusAsync(soNumber, isPreparedForShipment: isPrepared);
        }

        public async Task<bool> UpdateOrderValidationStatusAsync(string soNumber, bool isValidated)
        {
            return await UpsertOrderShipmentStatusAsync(soNumber, isValidated: isValidated);
        }

        public async Task<bool> UpdateItemValidationStatusAsync(string soNumber, string itemCode, bool isValidated)
        {
            return await UpsertOrderShipmentStatusAsync(soNumber, isValidated: isValidated);
        }

        public async Task<bool> BulkUpdateItemStatusAsync(string soNumber, List<string> itemCodes, bool status, bool isValidation)
        {
            if (isValidation)
            {
                return await UpsertOrderShipmentStatusAsync(soNumber, isValidated: status);
            }

            foreach (var itemCode in itemCodes)
            {
                await UpsertProductionLineStatePreparationAsync(soNumber, itemCode, status, autoSave: false);
            }
            await _scanContext.SaveChangesAsync();
            return true;
        }

        /// <summary>
        /// Upserts IsPrepared on ProductionLineState (replaces ItemPreparationStatus table).
        /// </summary>
        private async Task<bool> UpsertProductionLineStatePreparationAsync(
            string soNumber, string itemCode, bool isPrepared, bool autoSave = true)
        {
            var line = await _scanContext.SalesOrderLines
                .Include(l => l.Order)
                .FirstOrDefaultAsync(l => l.Order.SourceOrderId == soNumber && l.ItemCode == itemCode);

            if (line == null) return false;

            var state = await _scanContext.ProductionLineStates.FindAsync(line.Id);
            if (state != null)
            {
                state.IsPrepared = isPrepared;
                state.UpdatedAt = DateTime.UtcNow;
            }
            else
            {
                _scanContext.ProductionLineStates.Add(new ProductionLineState
                {
                    SalesOrderLineId = line.Id,
                    IsPrepared = isPrepared,
                    UpdatedAt = DateTime.UtcNow
                });
            }

            if (autoSave)
            {
                await _scanContext.SaveChangesAsync();
            }
            
            return true;
        }

        /// <summary>
        /// Upserts OrderShipmentStatus (KEPT as separate table).
        /// </summary>
        private async Task<bool> UpsertOrderShipmentStatusAsync(
            string soNumber, 
            bool? isPreparedForShipment = null, 
            bool? isValidated = null,
            bool autoSave = true)
        {
            var existing = await _scanContext.OrderShipmentStatuses
                .FirstOrDefaultAsync(s => s.SoNumber == soNumber);

            if (existing != null)
            {
                if (isPreparedForShipment.HasValue) existing.IsPreparedForShipment = isPreparedForShipment.Value;
                if (isValidated.HasValue) existing.IsValidated = isValidated.Value;
                existing.UpdatedAt = DateTime.UtcNow;
            }
            else
            {
                _scanContext.OrderShipmentStatuses.Add(new OrderShipmentStatus
                {
                    SoNumber = soNumber,
                    IsPreparedForShipment = isPreparedForShipment ?? false,
                    IsValidated = isValidated ?? false,
                    UpdatedAt = DateTime.UtcNow
                });
            }

            if (autoSave)
            {
                await _scanContext.SaveChangesAsync();
            }
            
            return true;
        }

        public async Task<IEnumerable<BarcodeMappingDto>> GetBarcodeMappingsAsync(string siteCode)
        {
            using IDbConnection db = new SqlConnection(_connectionString);
            var sql = $@"
                SELECT DISTINCT
                    f1.STOFCY_0 AS [Site],
                    f0.TCLCOD_0 AS [Category],
                    LTRIM(RTRIM(f0.ITMREF_0)) AS [Product],
                    LTRIM(RTRIM(f0.ITMDES1_0)) AS [Description],
                    f0.STU_0 AS [Unit],
                    f0.ITMWEI_0 AS [StandardWeight],
                    LTRIM(RTRIM(f0.EANCOD_0)) AS [Barcode],
                    ISNULL(f1.DEFSTOLOC_0, '') AS [Location],
                    '' AS [LocationType],
                    '' AS [Warehouse]
                FROM {_syncSettings.X3DatabaseName}.INLPROD.ITMMASTER f0 WITH (NOLOCK)
                JOIN {_syncSettings.X3DatabaseName}.INLPROD.ITMFACILIT f1 WITH (NOLOCK) ON f0.ITMREF_0 = f1.ITMREF_0
                WHERE f1.STOFCY_0 = @Site
                  AND f0.EANCOD_0 <> ''
                  AND f0.TCLCOD_0 NOT IN ('ADMIN','CONSU','TECHN')";

            return await db.QueryAsync<BarcodeMappingDto>(sql, new { Site = siteCode });
        }

        /// <summary>
        /// Closes an order by inserting into OrderStatusHistory (KEPT table).
        /// </summary>
        public async Task<bool> CloseOrderAsync(string soNumber, string closedBy)
        {
            var existing = await _scanContext.OrderStatusHistories
                .FirstOrDefaultAsync(h => h.SoNumber == soNumber && h.Status == 2);

            if (existing != null)
                return true; // Already closed

            _scanContext.OrderStatusHistories.Add(new OrderStatusHistory
            {
                SoNumber = soNumber,
                Status = 2,
                ChangedBy = closedBy,
                ChangedAt = DateTime.UtcNow
            });

            var audit = new AuditLog
            {
                EntityName = "OrderStatusHistory",
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
