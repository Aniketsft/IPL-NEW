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
using EnterpriseAuth.Api.Core.Application.Interfaces;

namespace EnterpriseAuth.Api.Infrastructure.Persistence
{
    public class EfLogisticsRepository : ILogisticsRepository
    {
        private readonly string _connectionString;
        private readonly ApplicationDbContext _context;
        private readonly ScanProductionDbContext _scanContext;
        private readonly SyncSettings _syncSettings;
        private readonly EodSettings _eodSettings;
        private readonly IStagingService _stagingService;
        private readonly IX3SchemaProvider _schemaProvider;

        public EfLogisticsRepository(IConfiguration configuration, ApplicationDbContext context, ScanProductionDbContext scanContext, IOptions<SyncSettings> syncSettings, IOptions<EodSettings> eodSettings, IStagingService stagingService, IX3SchemaProvider schemaProvider)
        {
            _connectionString = configuration.GetConnectionString("Innodis") 
                                ?? throw new System.ArgumentNullException("Innodis connection string is missing");
            _context = context;
            _scanContext = scanContext;
            _syncSettings = syncSettings.Value;
            _eodSettings = eodSettings.Value;
            _stagingService = stagingService;
            _schemaProvider = schemaProvider;
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
                Rep0 = o.Rep0 ?? "",
                Rep1 = o.Rep1 ?? "",
                Salesman = o.Salesman ?? "",
                Site = o.Site,
                Status = o.Status,
                Source = o.SourceSystem,
                IsPreparedForShipment = shipmentStatuses.Contains(o.SourceOrderId)
            });
        }

        public async Task<IEnumerable<ProductionTrackingDto>> GetProductionSummaryAsync(DateTime date)
        {
            var targetDate = date.Date;
            
            var nextDate = targetDate.AddDays(1);
            var scans = await _scanContext.ProductionScanTransactions
                .Include(t => t.OrderLine)
                .ThenInclude(l => l.Order)
                .Where(t => t.CreatedAt >= targetDate 
                         && t.CreatedAt < nextDate 
                         && !t.IsDeleted
                         && (t.ItemStatus == "A" || t.ItemStatus == null))
                .AsNoTracking()
                .ToListAsync();

            var itemCodes = scans.Select(s => s.OrderLine.ItemCode).Distinct().ToList();
            var units = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            if (itemCodes.Any())
            {
                using IDbConnection db = new SqlConnection(_connectionString);
                string schema = $"{_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}";
                var sql = $"SELECT ITMREF_0, STU_0 FROM {schema}.ITMMASTER WITH (NOLOCK) WHERE ITMREF_0 IN @Codes";
                var mapping = await db.QueryAsync(sql, new { Codes = itemCodes });
                foreach(var map in mapping)
                {
                    if (map.ITMREF_0 != null && map.STU_0 != null)
                        units[((string)map.ITMREF_0).Trim()] = ((string)map.STU_0).Trim();
                }
            }

            return scans
                .GroupBy(s => new
                {
                    ItemCode    = s.OrderLine.ItemCode,
                    LotNumber   = s.LotNumber ?? "",
                    ItemStatus  = s.ItemStatus ?? "A",
                    CreatedDate = s.CreatedAt.Date
                })
                .Select(g =>
                {
                    var latest   = g.OrderByDescending(s => s.CreatedAt).First();
                    var itemCode = g.Key.ItemCode.Trim();
                    return new ProductionTrackingDto
                    {
                        SoNumber     = latest.OrderLine.Order.SourceOrderId,
                        ItemCode     = itemCode,
                        Description  = latest.OrderLine.Description,
                        Quantity     = latest.OrderLine.OrderedQuantity,
                        Manufactured = (units.TryGetValue(itemCode, out var un) && (un.Trim().Equals("EA", StringComparison.OrdinalIgnoreCase) || un.Trim().Equals("PCS", StringComparison.OrdinalIgnoreCase))) ? g.Sum(s => s.EaQuantity ?? 0m) : g.Sum(s => s.ScanAmountKg),
                        EaQuantity   = g.Sum(s => s.EaQuantity ?? 0m),
                        LotNumber    = g.Key.LotNumber,
                        Location     = latest.Location ?? "",
                        StatusLabel  = g.Key.ItemStatus,
                        CreatedAt    = latest.CreatedAt,
                        Unit         = units.TryGetValue(itemCode, out var u) && !string.IsNullOrWhiteSpace(u) ? u : "KG",
                        Site         = latest.OrderLine.Order.Site ?? "IPL"
                    };
                });
        }

        public async Task<IEnumerable<ProductionTrackingDto>> GetProductionSummaryByWorkOrderAsync(string workOrder)
        {
            using IDbConnection db = new SqlConnection(_connectionString);
            string schema = $"{_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}";

            // 1. Find the SalesOrder Id for the workOrder
            var orderId = await _scanContext.SalesOrders
                .Where(o => o.SourceOrderId == workOrder)
                .Select(o => o.Id)
                .FirstOrDefaultAsync();

            if (orderId == Guid.Empty) return Enumerable.Empty<ProductionTrackingDto>();

            // 2. Query aggregated scans joined with ITMMASTER for conversion and locations
            string sql = $@"
                SELECT 
                    @WorkOrder      AS SoNumber,
                    t.ItemCode      AS ItemCode,
                    l.Description   AS Description,
                    l.OrderedQuantity AS Quantity,
                    CASE WHEN i.STU_0 IN ('EA', 'PCS') THEN SUM(ISNULL(t.EaQuantity, 0)) ELSE SUM(t.ScanAmountKg) END AS Manufactured,
                    SUM(ISNULL(t.EaQuantity, 0)) AS EaQuantity,
                    t.LotNumber     AS LotNumber,
                    i.STU_0         AS Unit,
                    MAX(t.CreatedAt) AS CreatedAt,
                    t.Location      AS Location,
                    t.ItemStatus    AS StatusLabel,
                    i.PCUSTU_0      AS Conversion
                FROM ProductionScanTransactions t
                JOIN SalesOrderLines l ON t.SalesOrderLineId = l.Id
                JOIN {schema}.ITMMASTER i ON l.ItemCode = i.ITMREF_0
                WHERE l.SalesOrderId = @OrderId AND t.IsDeleted = 0 AND (t.ItemStatus = 'A' OR t.ItemStatus IS NULL)
                GROUP BY t.ItemCode, l.Description, l.OrderedQuantity, t.LotNumber, i.STU_0, t.Location, t.ItemStatus, i.PCUSTU_0";

            var results = await db.QueryAsync<ProductionTrackingDto>(sql, new { WorkOrder = workOrder, OrderId = orderId });
            return results;
        }

        public async Task<bool> SaveStagingEodAsync(IEnumerable<StagingEod> records)
        {
            if (records == null || !records.Any()) return true;

            var workOrderNumbers = records.Select(e => e.WorkOrderNumber).Distinct().ToList();
            
            // Fetch existing unprocessed records for these work orders
            var existingRecords = await _scanContext.StagingEodRecords
                .Where(e => workOrderNumbers.Contains(e.WorkOrderNumber) && !e.IsProcessed)
                .ToListAsync();

            var existingLookup = existingRecords
                .ToDictionary(e => $"{e.WorkOrderNumber}|{e.ProductCode}|{e.LotNumber ?? ""}", StringComparer.OrdinalIgnoreCase);

            foreach (var record in records)
            {
                var key = $"{record.WorkOrderNumber}|{record.ProductCode}|{record.LotNumber ?? ""}";
                if (existingLookup.TryGetValue(key, out var existing))
                {
                    // Update existing
                    existing.TotalManufacturedQuantity = record.TotalManufacturedQuantity;
                    existing.EaQuantity = record.EaQuantity;
                    existing.DateOfManufacturing = record.DateOfManufacturing;
                    existing.ExpiryDate = record.ExpiryDate;
                    existing.Location = record.Location;
                    existing.ItemStatus = record.ItemStatus;
                    existing.Location2 = record.Location2;
                    existing.Location3 = record.Location3;
                    existing.LotNumber = record.LotNumber;
                }
                else
                {
                    // Insert new
                    await _scanContext.StagingEodRecords.AddAsync(record);
                    existingLookup[key] = record;
                }
            }

            return await _scanContext.SaveChangesAsync() > 0;
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
                Salesman = s.OrderLine.Order.Salesman,
                CustomerCode = s.OrderLine.Order.CustomerCode,
                CustomerName = s.OrderLine.Order.CustomerName,
                Remaining = Math.Max(0m, s.OrderLine.OrderedQuantity - s.TotalManufacturedQty),
                Manufactured = s.TotalManufacturedQty,
                EaQuantity = s.TotalEaQty,
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
                FROM {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.BPCUSTOMER
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
                FROM {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.SALESREP
                WHERE REPNAM_0 IS NOT NULL AND REPNAM_0 <> ''
                ORDER BY Name";
            return await db.QueryAsync<SalesRepLookupDto>(sql);
        }

        public async Task<IEnumerable<string>> GetProductionSitesAsync()
        {
            using IDbConnection db = new SqlConnection(_connectionString);
            string sql = $"SELECT DISTINCT STOFCY_0 FROM {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.STOLOC ORDER BY STOFCY_0";
            return await db.QueryAsync<string>(sql);
        }

        public async Task<IEnumerable<string>> GetLotsAsync(string itemCode, string siteCode)
        {
            using IDbConnection db = new SqlConnection(_connectionString);
            string sql = $@"
                SELECT DISTINCT LOT_0 
                FROM {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.STOCK 
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
                if (string.IsNullOrEmpty(dto.ItemCode))
                {
                    throw new ArgumentException("ItemCode is strictly required for internal orders.");
                }
                
                var line = new SalesOrderLine
                {
                    Order = order,
                    ItemCode = dto.ItemCode,
                    Description = !string.IsNullOrEmpty(dto.ProductName) ? dto.ProductName : "Internal Production Component",
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
                if (string.IsNullOrEmpty(dto.ItemCode))
                {
                    throw new ArgumentException("ItemCode is strictly required for internal scans.");
                }
                
                await SaveProductionScanAsync(new ProductionScanDto
                {
                    SoNumber = soNumber,
                    ItemCode = dto.ItemCode,
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
                    EaQuantity = scanDto.EaQuantity,
                    Barcode = scanDto.Barcode,
                    LotNumber = scanDto.Lot,
                    Location = scanDto.Location ?? string.Empty,
                    ItemStatus = scanDto.ItemStatus ?? "Q",
                    SyncId = Guid.NewGuid().ToString(),
                    CreatedBy = scanDto.CreatedBy ?? "system",
                    CreatedAt = DateTime.UtcNow,
                    DeviceId = scanDto.DeviceId
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
                state.TotalEaQty += scanDto.EaQuantity ?? 0m;
                state.LastScanId = entity.Id;
                state.UpdatedAt = DateTime.UtcNow;

                await _scanContext.SaveChangesAsync();

                // Generate Audit Log
                var audit = new AuditLog
                {
                    EntityName = "ProductionScanTransactions",
                    EntityIdString = scanDto.SoNumber,
                    ActionType = "INSERT",
                    Payload = System.Text.Json.JsonSerializer.Serialize(entity),
                    PerformedBy = entity.CreatedBy ?? "system",
                    PerformedAt = DateTime.UtcNow,
                    DeviceId = scanDto.DeviceId
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
                EaQuantity = t.EaQuantity,
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
                        EaQuantity = scanDto.EaQuantity,
                        Barcode = scanDto.Barcode,
                        LotNumber = scanDto.Lot,
                        Location = scanDto.Location ?? string.Empty,
                        ItemStatus = scanDto.ItemStatus ?? "A",
                        SyncId = Guid.NewGuid().ToString(),
                        CreatedBy = scanDto.CreatedBy ?? "system",
                        CreatedAt = scanDto.CreatedAt ?? DateTime.UtcNow,
                        DeviceId = scanDto.DeviceId
                    };

                    _scanContext.ProductionScanTransactions.Add(entity);

                    if (entity.ItemStatus == "A")
                    {
                        totalNewManufactured += entity.ScanAmountKg;
                    }

                    logsToInsert.Add(new AuditLog
                    {
                        EntityName = "ProductionScanTransactions",
                        EntityIdString = soNumber,
                        ActionType = "INSERT_BATCH",
                        Payload = System.Text.Json.JsonSerializer.Serialize(new { entity.SalesOrderLineId, entity.Barcode, entity.ScanAmountKg }),
                        PerformedBy = entity.CreatedBy ?? "system",
                        PerformedAt = DateTime.UtcNow,
                        DeviceId = scanDto.DeviceId
                    });
                }

                state.TotalManufacturedQty += totalNewManufactured;
                state.TotalEaQty += scans.Where(s => s.ItemStatus == "A" || s.ItemStatus == null).Sum(s => s.EaQuantity ?? 0m);
                state.UpdatedAt = DateTime.UtcNow;
                
                // If there are scans, the last one gets its ID set in state.
                // But we don't strictly need to set LastScanId correctly if there are many.
                
                if (logsToInsert.Any())
                {
                    _scanContext.AuditLogs.AddRange(logsToInsert);
                }

                // --- AUTO-POPULATE EXCESS TABLE (AGGREGATED) ---
                if (soNumber.StartsWith("BLK-") || soNumber.StartsWith("CUTS-"))
                {
                    var excess = await _scanContext.Excesses
                        .FirstOrDefaultAsync(e => e.SourceBulkSoNumber == soNumber && e.ItemCode == itemCode);
                    
                    if (excess == null)
                    {
                        excess = new Excess
                        {
                            SourceBulkSoNumber = soNumber,
                            ItemCode = itemCode,
                            DeliveryDate = line.Order.DeliveryDate ?? DateTime.UtcNow,
                            TotalManufacturedQuantity = totalNewManufactured,
                            AllocatedQuantity = 0,
                            RemainingExcess = totalNewManufactured,
                            CreatedBy = scans.First().CreatedBy ?? "system"
                        };
                        _scanContext.Excesses.Add(excess);
                    }
                    else
                    {
                        excess.TotalManufacturedQuantity += totalNewManufactured;
                        excess.RemainingExcess = excess.TotalManufacturedQuantity - excess.AllocatedQuantity;
                        excess.UpdatedAt = DateTime.UtcNow;
                        excess.UpdatedBy = scans.First().CreatedBy ?? "system";
                    }
                }

                // --- HANDLE ALLOCATIONS FROM POOLS (AGGREGATED) ---
                var allocations = scans.Where(s => !string.IsNullOrEmpty(s.Location) && s.Location.StartsWith("ALLOC-")).ToList();
                if (allocations.Any())
                {
                    // Group allocations by source pool in case this batch has mixed sources (though unlikely per line 394)
                    var groupedAllocations = allocations.GroupBy(a => a.Location.Replace("ALLOC-", ""));
                    foreach (var group in groupedAllocations)
                    {
                        var sourceBulkSo = group.Key;
                        var excess = await _scanContext.Excesses
                            .FirstOrDefaultAsync(e => e.SourceBulkSoNumber == sourceBulkSo && e.ItemCode == itemCode);
                        
                        if (excess != null)
                        {
                            var totalAllocatedInBatch = group.Sum(a => a.ScanAmountKg);
                            excess.AllocatedQuantity += totalAllocatedInBatch;
                            excess.RemainingExcess = excess.TotalManufacturedQuantity - excess.AllocatedQuantity;
                            excess.UpdatedAt = DateTime.UtcNow;
                            excess.UpdatedBy = scans.First().CreatedBy ?? "system-sync";
                        }
                    }
                }

                await _scanContext.SaveChangesAsync();

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
                    FROM {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.STOLOC STOL 
                    LEFT JOIN {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.WAREHOUSE WRH on WRH.WRH_0 = STOL.WRH_0 
                    WHERE STOL.STOFCY_0 = @Site
                ) AS T1 
                LEFT JOIN {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.[ATEXTRA] ATRA on T1.STOFCY_0 = ATRA.IDENT1_0 
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
                    from {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.STOCK f0
                    JOIN {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.ITMMASTER f1 ON f0.ITMREF_0 = f1.ITMREF_0
                    LEFT JOIN {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.STOLOT f2 ON f0.LOT_0 = f2.LOT_0
                ) as T1
                WHERE T1.Site = @Site AND T1.Product = @ItemCode";
            
            return await db.QueryAsync<LocationLookupDto>(sql, new { Site = site, ItemCode = itemCode });
        }

        // ===== STATUS METHODS =====

        public async Task<bool> UpdateItemPreparationStatusAsync(string soNumber, string itemCode, bool isPrepared, string performedBy = "system")
        {
            return await UpsertProductionLineStatePreparationAsync(soNumber, itemCode, isPrepared, performedBy: performedBy);
        }

        public async Task<bool> UpdateOrderShipmentPreparationStatusAsync(string soNumber, bool isPrepared, string performedBy = "system")
        {
            return await UpsertOrderShipmentStatusAsync(soNumber, isPreparedForShipment: isPrepared, performedBy: performedBy);
        }

        public async Task<bool> UpdateOrderValidationStatusAsync(string soNumber, bool isValidated, string performedBy = "system")
        {
            return await UpsertOrderShipmentStatusAsync(soNumber, isValidated: isValidated, performedBy: performedBy);
        }

        public async Task<bool> UpdateItemValidationStatusAsync(string soNumber, string itemCode, bool isValidated, string performedBy = "system")
        {
            return await UpsertOrderShipmentStatusAsync(soNumber, isValidated: isValidated, performedBy: performedBy);
        }

        public async Task<bool> BulkUpdateItemStatusAsync(string soNumber, List<string> itemCodes, bool status, bool isValidation, string performedBy = "system")
        {
            if (isValidation)
            {
                return await UpsertOrderShipmentStatusAsync(soNumber, isValidated: status, performedBy: performedBy);
            }

            foreach (var itemCode in itemCodes)
            {
                await UpsertProductionLineStatePreparationAsync(soNumber, itemCode, status, autoSave: false, performedBy: performedBy);
            }
            await _scanContext.SaveChangesAsync();
            return true;
        }

        /// <summary>
        /// Upserts IsPrepared on ProductionLineState (replaces ItemPreparationStatus table).
        /// </summary>
        private async Task<bool> UpsertProductionLineStatePreparationAsync(
            string soNumber, string itemCode, bool isPrepared, bool autoSave = true, string performedBy = "system")
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

            // Central Audit Log
            _scanContext.AuditLogs.Add(new AuditLog
            {
                EntityName = "ProductionLineState",
                EntityIdString = soNumber,
                ActionType = "UPDATE_PREP_STATUS",
                Payload = System.Text.Json.JsonSerializer.Serialize(new { soNumber, itemCode, isPrepared }),
                PerformedBy = performedBy,
                PerformedAt = DateTime.UtcNow
            });

            if (autoSave) await _scanContext.SaveChangesAsync();
            
            return true;
        }

        /// <summary>
        /// Upserts OrderShipmentStatus (KEPT as separate table).
        /// </summary>
        private async Task<bool> UpsertOrderShipmentStatusAsync(
            string soNumber, 
            bool? isPreparedForShipment = null, 
            bool? isValidated = null,
            bool autoSave = true,
            string performedBy = "system")
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

            // TRIGGER: Populate Staging Table if marked as prepared
            if (isPreparedForShipment == true || (existing != null && existing.IsPreparedForShipment))
            {
                await _stagingService.PopulateStagingAsync(soNumber);
            }

            // Central Audit Log
            _scanContext.AuditLogs.Add(new AuditLog
            {
                EntityName = "OrderShipmentStatus",
                EntityIdString = soNumber,
                ActionType = "UPDATE_SHIPMENT_STATUS",
                Payload = System.Text.Json.JsonSerializer.Serialize(new { soNumber, isPreparedForShipment, isValidated }),
                PerformedBy = performedBy,
                PerformedAt = DateTime.UtcNow
            });

            if (autoSave) await _scanContext.SaveChangesAsync();
            
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
                FROM {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.ITMMASTER f0 WITH (NOLOCK)
                JOIN {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.ITMFACILIT f1 WITH (NOLOCK) ON f0.ITMREF_0 = f1.ITMREF_0
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
                EntityIdString = soNumber,
                ActionType = "CLOSE_ORDER",
                Payload = $"{{\"soNumber\":\"{soNumber}\",\"closedBy\":\"{closedBy}\"}}",
                PerformedBy = closedBy,
                PerformedAt = DateTime.UtcNow
            };
            _scanContext.AuditLogs.Add(audit);

            await _scanContext.SaveChangesAsync();
            return true;
        }

        public async Task<IEnumerable<ExcessDto>> GetExcessByDateAndItemAsync(DateTime deliveryDate, string itemCode)
        {
            var results = await _scanContext.Excesses
                .Where(e => e.DeliveryDate.Date == deliveryDate.Date && e.ItemCode == itemCode && e.RemainingExcess > 0)
                .Select(e => new ExcessDto
                {
                    Id = e.Id,
                    SourceBulkSoNumber = e.SourceBulkSoNumber,
                    ItemCode = e.ItemCode,
                    DeliveryDate = e.DeliveryDate,
                    TotalManufacturedQuantity = e.TotalManufacturedQuantity,
                    AllocatedQuantity = e.AllocatedQuantity,
                    RemainingExcess = e.RemainingExcess
                })
                .ToListAsync();

            return results;
        }

        public async Task<bool> AllocateExcessAsync(AllocateExcessDto dto)
        {
            using var transaction = await _scanContext.Database.BeginTransactionAsync();
            try
            {
                // 1. Find the Excess pool row
                var excess = await _scanContext.Excesses
                    .FirstOrDefaultAsync(e => e.SourceBulkSoNumber == dto.SourceBulkSoNumber && e.ItemCode == dto.ItemCode);

                if (excess == null)
                    throw new Exception($"Excess pool not found: {dto.SourceBulkSoNumber} / {dto.ItemCode}");

                if (dto.AllocateAmountKg > excess.RemainingExcess)
                    throw new Exception($"Insufficient excess. Requested: {dto.AllocateAmountKg}, Available: {excess.RemainingExcess}");

                // 2. Deduct from excess pool
                excess.AllocatedQuantity += dto.AllocateAmountKg;
                excess.RemainingExcess -= dto.AllocateAmountKg;
                excess.UpdatedAt = DateTime.UtcNow;
                excess.UpdatedBy = dto.AllocatedBy ?? "system";

                // 3. Insert a production scan against the REAL target order
                var targetLine = await _scanContext.SalesOrderLines
                    .Include(l => l.Order)
                    .FirstOrDefaultAsync(l => l.Order.SourceOrderId == dto.TargetSoNumber && l.ItemCode == dto.ItemCode);

                if (targetLine == null)
                    throw new Exception($"Target order line not found: {dto.TargetSoNumber} / {dto.ItemCode}");

                var scan = new ProductionScanTransaction
                {
                    SalesOrderLineId = targetLine.Id,
                    ScanAmountKg = dto.AllocateAmountKg,
                    Barcode = $"ALLOC-{dto.SourceBulkSoNumber}-{DateTime.UtcNow.Ticks}",
                    LotNumber = null,
                    Location = "BULK-ALLOC",
                    ItemStatus = "A",
                    SyncId = Guid.NewGuid().ToString(),
                    CreatedBy = dto.AllocatedBy ?? "system",
                    CreatedAt = DateTime.UtcNow
                };
                _scanContext.ProductionScanTransactions.Add(scan);

                // 4. Update target line state
                var targetState = await _scanContext.ProductionLineStates.FindAsync(targetLine.Id);
                if (targetState == null)
                {
                    targetState = new ProductionLineState { SalesOrderLineId = targetLine.Id };
                    _scanContext.ProductionLineStates.Add(targetState);
                }
                targetState.TotalManufacturedQty += dto.AllocateAmountKg;
                targetState.UpdatedAt = DateTime.UtcNow;

                // 5. Audit trail
                _scanContext.AuditLogs.Add(new AuditLog
                {
                    EntityName = "ExcessAllocation",
                    EntityIdString = dto.TargetSoNumber,
                    ActionType = "ALLOCATE",
                    Payload = System.Text.Json.JsonSerializer.Serialize(new
                    {
                        dto.SourceBulkSoNumber,
                        dto.TargetSoNumber,
                        dto.ItemCode,
                        dto.AllocateAmountKg,
                        ExcessRemainingAfter = excess.RemainingExcess
                    }),
                    PerformedBy = dto.AllocatedBy ?? "system",
                    PerformedAt = DateTime.UtcNow
                });

                await _scanContext.SaveChangesAsync();
                await transaction.CommitAsync();
                return true;
            }
            catch
            {
                await transaction.RollbackAsync();
                throw;
            }
        }
        public async Task<LabelAuditDto> LogLabelAuditAsync(LabelAuditDto auditDto)
        {
            // Idempotency: Check if this Label ID already exists (important for sync retries)
            if (!string.IsNullOrEmpty(auditDto.LabelId))
            {
                var existing = await _scanContext.LabelAudits
                    .FirstOrDefaultAsync(l => l.LabelId == auditDto.LabelId);
                
                if (existing != null)
                {
                    // Return existing data to satisfy the request without duplication
                    return new LabelAuditDto
                    {
                        LabelId = existing.LabelId,
                        ReferenceNumber = existing.ReferenceNumber,
                        LabelType = existing.LabelType,
                        ProductCode = existing.ProductCode,
                        CustomerName = existing.CustomerName,
                        TotalWeight = existing.TotalWeight,
                        ManifestJson = existing.ManifestJson,
                        PrintedBy = existing.PrintedBy,
                        IsOfflineCreated = existing.IsOfflineCreated,
                        CreatedAt = existing.CreatedAt
                    };
                }
            }

            var entity = new LabelAudit
            {
                ReferenceNumber = auditDto.ReferenceNumber,
                LabelType = auditDto.LabelType,
                ProductCode = auditDto.ProductCode,
                CustomerName = auditDto.CustomerName,
                TotalWeight = auditDto.TotalWeight,
                ManifestJson = auditDto.ManifestJson,
                PrintedBy = auditDto.PrintedBy,
                IsOfflineCreated = auditDto.IsOfflineCreated,
                CreatedAt = auditDto.IsOfflineCreated ? auditDto.CreatedAt : DateTime.UtcNow,
                DeviceId = auditDto.DeviceId
            };

            if (auditDto.IsOfflineCreated && !string.IsNullOrEmpty(auditDto.LabelId))
            {
                // If it was created offline, use the ID generated by the mobile app
                entity.LabelId = auditDto.LabelId;
            }
            else
            {
                // Online generation: LBL-YYMMDD-[SEQ]
                string datePrefix = DateTime.UtcNow.ToString("yyMMdd");
                
                // Get the high-water mark for today's sequence
                var todayCount = await _scanContext.LabelAudits
                    .Where(l => l.LabelId.StartsWith($"LBL-{datePrefix}"))
                    .CountAsync();
                
                entity.LabelId = $"LBL-{datePrefix}-{(todayCount + 1):D4}";
            }

            _scanContext.LabelAudits.Add(entity);
            
            // Create Audit Entry for unified trail
            _scanContext.AuditLogs.Add(new AuditLog
            {
                EntityName = "LabelAudit",
                EntityIdString = entity.LabelId,
                ActionType = "PRINT_LABEL",
                Payload = System.Text.Json.JsonSerializer.Serialize(new 
                { 
                    entity.LabelId, 
                    entity.ReferenceNumber, 
                    entity.ProductCode, 
                    entity.TotalWeight 
                }),
                PerformedBy = entity.PrintedBy ?? "system",
                PerformedAt = DateTime.UtcNow,
                DeviceId = auditDto.DeviceId
            });

            await _scanContext.SaveChangesAsync();

            // Return the DTO with the generated/persisted ID
            auditDto.LabelId = entity.LabelId;
            auditDto.CreatedAt = entity.CreatedAt;
            return auditDto;
        }

        public async Task<IEnumerable<WorkOrderDto>> GetWorkOrdersAsync(string? searchQuery)
        {
            using IDbConnection db = new SqlConnection(_connectionString);
            string schema = $"{_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}";
            
            string sql;
            object? param = null;

            if (string.IsNullOrEmpty(searchQuery))
            {
                // Simple query for dropdown population
                // Note: When using DISTINCT, the ORDER BY column must be in the SELECT list
                sql = $@"SELECT TOP 100 MFGNUM_0 AS WorkOrder, CREDAT_0 AS Date 
                         FROM {schema}.MFGHEAD 
                         WHERE MFGSTA_0 = 1 AND MFGFCY_0 = 'IPL'
                         ORDER BY Date DESC";
            }
            else
            {
                // Detailed query for metadata (CCE_0/1) during finalization
                sql = $@"
                    SELECT 
                        h.MFGNUM_0    AS WorkOrder,
                        i.ITMREF_0    AS Product,
                        i.UOMEXTQTY_0 AS ReleasedQty,
                        i.UOM_0       AS Unit,
                        m.CCE_0       AS CCE_0,
                        m.CCE_1       AS CCE_1,
                        'IPL'         AS ProductionSite,
                        'IPLCH'       AS Location
                    FROM {schema}.MFGHEAD h
                    JOIN {schema}.MFGITM i ON h.MFGNUM_0 = i.MFGNUM_0
                    JOIN {schema}.ITMMASTER m ON i.ITMREF_0 = m.ITMREF_0
                    WHERE h.MFGNUM_0 = @Query";
                
                param = new { Query = searchQuery };
            }

            return await db.QueryAsync<WorkOrderDto>(sql, param);
        }

        /// <summary>
        /// Fetches all BOM component codes from X3 for the given parent item codes.
        /// Used during End-of-Day to ensure zero-qty placeholder rows are inserted
        /// for components that were not scanned on the day.
        /// Query: SELECT f0.ITMREF_0, f1.CPNITMREF_0 FROM BOM JOIN BOMD WHERE ITMREF_0 IN (@parentCodes)
        /// </summary>
        public async Task<IEnumerable<BomComponentDto>> GetBomComponentsAsync(
            IEnumerable<string> parentItemCodes)
        {
            using IDbConnection db = new SqlConnection(_connectionString);
            string schema = $"{_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}";

            string sql = $@"
                SELECT f0.ITMREF_0    AS ParentItemCode,
                       f1.CPNITMREF_0 AS ComponentItemCode
                FROM   {schema}.BOM  f0
                JOIN   {schema}.BOMD f1 ON f0.ITMREF_0 = f1.ITMREF_0
                WHERE  f0.ITMREF_0 IN @ParentCodes";

            return await db.QueryAsync<BomComponentDto>(
                sql, new { ParentCodes = parentItemCodes.ToArray() });
        }

        public async Task<bool> RolloverOrderAsync(string soNumber, DateTime newDate, string performedBy = "system")
        {
            var order = await _scanContext.SalesOrders.FirstOrDefaultAsync(o => o.SourceOrderId == soNumber);
            if (order == null) return false;

            order.DeliveryDate = newDate.Date;
            await _scanContext.SaveChangesAsync();
            return true;
        }
    }
}
