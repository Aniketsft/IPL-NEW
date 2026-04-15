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
            var ordersTask = FetchFromInnodisAsync<SalesOrderHeaderDto>($@"
                SELECT TOP 300
                    f0.SOHNUM_0 COLLATE DATABASE_DEFAULT as [SohNum],
                    f2.PONO_0 COLLATE DATABASE_DEFAULT as [PoNo],
                    f0.ORDDAT_0 as [OrderDate],
                    f0.SHIDAT_0 as [DeliveryDate],
                    f0.BPCORD_0 COLLATE DATABASE_DEFAULT as [CustomerCode],
                    c.ZFULLBUSNAM_0 COLLATE DATABASE_DEFAULT as [CustomerName],
                    LTRIM(RTRIM(f0.REP_0)) COLLATE DATABASE_DEFAULT as [Rep0],
                    LTRIM(RTRIM(f0.REP_1)) COLLATE DATABASE_DEFAULT as [Rep1],
                    f0.STOFCY_0 COLLATE DATABASE_DEFAULT as [Site],
                    f0.ORDSTA_0 as [Status],
                    'External' as [Source]
                FROM {_syncSettings.X3DatabaseName}.INLPROD.SORDER f0 WITH (NOLOCK)
                JOIN {_syncSettings.X3DatabaseName}.INLPROD.ZBTBORD f2 WITH (NOLOCK) ON f0.SOHNUM_0 = f2.ORISONO_0
                JOIN {_syncSettings.X3DatabaseName}.INLPROD.BPCUSTOMER c WITH (NOLOCK) ON f0.BPCORD_0 = c.BPCNUM_0
                ORDER BY f0.ORDDAT_0 DESC");

            var detailsTask = FetchFromInnodisAsync<SalesOrderDetailDto>($@"
                SELECT 
                    f0.SOHNUM_0 as SoNumber,
                    f2.ITMREF_0 as ItemCode,
                    f2.ITMDES1_0 as Description,
                    'Variable Weight' as BarcodeType,
                    f1.QTY_0 as Quantity,
                    f2.SAU_0 as Unit,
                    f1.STOFCY_0 as Site
                FROM {_syncSettings.X3DatabaseName}.INLPROD.SORDER f0 WITH (NOLOCK)
                JOIN {_syncSettings.X3DatabaseName}.INLPROD.SORDERQ f1 WITH (NOLOCK) on f0.SOHNUM_0 = f1.SOHNUM_0
                JOIN {_syncSettings.X3DatabaseName}.INLPROD.ITMMASTER f2 WITH (NOLOCK) on f1.ITMREF_0 = f2.ITMREF_0
                JOIN {_syncSettings.X3DatabaseName}.INLPROD.ZBTBORD f3 WITH (NOLOCK) on f0.SOHNUM_0 = f3.ORISONO_0
                WHERE f0.SOHNUM_0 IN (
                    SELECT TOP 300 s.SOHNUM_0 
                    FROM {_syncSettings.X3DatabaseName}.INLPROD.SORDER s WITH (NOLOCK) 
                    JOIN {_syncSettings.X3DatabaseName}.INLPROD.ZBTBORD z WITH (NOLOCK) ON s.SOHNUM_0 = z.ORISONO_0
                    JOIN {_syncSettings.X3DatabaseName}.INLPROD.BPCUSTOMER bc WITH (NOLOCK) ON s.BPCORD_0 = bc.BPCNUM_0
                    ORDER BY s.ORDDAT_0 DESC
                )");

            var customersTask = FetchFromInnodisAsync<CustomerLookupDto>($"SELECT DISTINCT BPCNUM_0 as Code, ZFULLBUSNAM_0 as Name FROM {_syncSettings.X3DatabaseName}.INLPROD.BPCUSTOMER WITH (NOLOCK)");
            var repsTask = FetchFromInnodisAsync<SalesRepLookupDto>($"SELECT DISTINCT REPNUM_0 as Code, REPNAM_0 as Name FROM {_syncSettings.X3DatabaseName}.INLPROD.SALESREP WITH (NOLOCK)");
            var sitesTask = FetchFromInnodisAsync<SiteLookupDto>($"SELECT DISTINCT FCY_0 as Code, FCYNAM_0 as Name FROM {_syncSettings.X3DatabaseName}.INLPROD.FACILITY WITH (NOLOCK)");
            
            var locSql = $@"
                SELECT 
                    T1.STOFCY_0 as Site, T1.LOC_0 as Location, T1.WRH_0 as Warehouse,
                    WRH.WRHNAM_0 as WarehouseName, T1.LOCTYP_0 as LocationType,
                    ATRA.TEXTE_0 as LocationTypeName
                FROM {_syncSettings.X3DatabaseName}.INLPROD.STOLOC T1 WITH (NOLOCK)
                LEFT JOIN {_syncSettings.X3DatabaseName}.INLPROD.WAREHOUSE WRH WITH (NOLOCK) on WRH.WRH_0 = T1.WRH_0 
                LEFT JOIN {_syncSettings.X3DatabaseName}.INLPROD.[ATEXTRA] ATRA WITH (NOLOCK) on T1.STOFCY_0 = ATRA.IDENT1_0 
                    and T1.LOCTYP_0 = ATRA.IDENT2_0 
                    and ATRA.CODFIC_0 = 'TABLOCTYP' and ATRA.LANGUE_0 = 'BRI' and ATRA.ZONE_0 = 'TYPDESAXX'
                WHERE T1.STOFCY_0 = @Site";
            var locationsTask = FetchFromInnodisAsync<LocationLookupDto>(locSql, new { Site = site });

            var productsSql = $@"
                SELECT T1.*
                FROM (
                    SELECT DISTINCT
                        f1.STOFCY_0 AS [Site],
                        f0.TCLCOD_0 AS [Category],
                        f0.ITMREF_0 AS [ProductCode],
                        f0.ITMDES1_0 AS [ProductDescription],
                        f0.STU_0 AS [StockUnit],
                        f0.SAU_0 AS [SalesUnit],
                        f0.ITMWEI_0 AS [StandardWeight],
                        f0.EANCOD_0 AS [Barcode]
                    FROM {_syncSettings.X3DatabaseName}.INLPROD.ITMMASTER f0 WITH (NOLOCK)
                    JOIN {_syncSettings.X3DatabaseName}.INLPROD.ITMFACILIT f1 WITH (NOLOCK) ON f0.ITMREF_0 = f1.ITMREF_0
                ) AS T1
                WHERE T1.Site = @Site
                  AND T1.Category NOT IN ('ADMIN','CONSU','TECHN')";
            var productsTask = FetchFromInnodisAsync<ProductLookupDto>(productsSql, new { Site = site });

            var lotsSql = $@"
                SELECT DISTINCT ITMREF_0 as ItemCode, STOFCY_0 as SiteCode, LOT_0 as Lot
                FROM {_syncSettings.X3DatabaseName}.INLPROD.STOCK WITH (NOLOCK)
                WHERE STOFCY_0 = @Site AND QTYPCU_0 > 0";
            var lotsTask = FetchFromInnodisAsync<LotLookupDto>(lotsSql, new { Site = site });

            // Execute tasks in parallel
            await Task.WhenAll(ordersTask, detailsTask, customersTask, repsTask, locationsTask, productsTask, sitesTask, lotsTask);

            package.Orders = ordersTask.Result.ToList();
            package.Details = detailsTask.Result.ToList();
            package.Customers = customersTask.Result.ToList();
            package.Reps = repsTask.Result.ToList();
            package.Sites = sitesTask.Result.ToList();
            package.Locations = locationsTask.Result.ToList();
            package.Products = productsTask.Result.ToList();
            package.Lots = lotsTask.Result.ToList();

            // Override status from NORMALIZED tables
            var allSoNumbers = package.Orders.Select(o => o.SohNum).ToList();
            if (allSoNumbers.Any())
            {
                // Closed orders — from OrderStatusHistory (KEPT table)
                var closedSoNumbers = await _scanContext.OrderStatusHistories
                    .Where(h => allSoNumbers.Contains(h.SoNumber) && h.Status == 2)
                    .Select(h => h.SoNumber)
                    .Distinct()
                    .ToListAsync();

                // Shipment readiness — from OrderShipmentStatus (KEPT table)
                var shipmentReady = await _scanContext.OrderShipmentStatuses
                    .Where(s => allSoNumbers.Contains(s.SoNumber) && s.IsPreparedForShipment)
                    .Select(s => s.SoNumber)
                    .ToListAsync();

                foreach (var header in package.Orders)
                {
                    if (closedSoNumbers.Contains(header.SohNum))
                        header.Status = 2;
                    if (shipmentReady.Contains(header.SohNum))
                        header.IsPreparedForShipment = true;
                }
            }

            // Centralize: Cache all discovered headers (external + internal) to unified enterprise tables
            await SyncEnterpriseOrdersAndLinesAsync(package.Orders, package.Details);
            await _scanContext.SaveChangesAsync();

            // Pull Aggregated States from Enterprise Tables
            var orderLineStates = await _scanContext.ProductionLineStates
                .Include(s => s.OrderLine)
                .ThenInclude(l => l.Order)
                .Where(s => allSoNumbers.Contains(s.OrderLine.Order.SourceOrderId))
                .ToListAsync();

            // Update External Order Details from Enterprise Aggregates
            foreach (var detail in package.Details)
            {
                var state = orderLineStates.FirstOrDefault(s => 
                    s.OrderLine.Order.SourceOrderId == detail.SoNumber && 
                    s.OrderLine.ItemCode == detail.ItemCode);
                
                if (state != null)
                {
                    detail.Manufactured = state.TotalManufacturedQty;
                    detail.Remaining = Math.Max(0m, (detail.Quantity ?? 0m) - detail.Manufactured);
                    detail.IsPrepared = state.IsPrepared || state.IsLineCompleted;
                }
                else
                {
                    detail.Remaining = detail.Quantity ?? 0m;
                }
            }

            // Build Internal Orders (Cut & Bulk) from Enterprise SalesOrders
            var internalOrders = await _scanContext.SalesOrders
                .Include(o => o.Lines)
                .Where(o => o.SourceSystem == "Internal" && !o.IsArchived)
                .ToListAsync();

            foreach (var order in internalOrders)
            {
                var line = order.Lines.FirstOrDefault();
                var state = await _scanContext.ProductionLineStates
                    .FirstOrDefaultAsync(s => s.SalesOrderLineId == (line != null ? line.Id : Guid.Empty));

                var manufactured = state?.TotalManufacturedQty ?? 0m;

                package.CutBulkEntries.Add(new CutBulkEntryDto {
                    EntryNumber = order.SourceOrderId,
                    Type = line?.ItemCode == "PROD-CUT" ? "Cuts" : "Bulk",
                    CustomerCode = order.CustomerCode,
                    CustomerName = order.CustomerName,
                    Date = order.OrderDate,
                    AmountKg = line?.OrderedQuantity ?? 0m,
                    ManufacturedQuantity = manufactured,
                    RemainingQuantity = (line?.OrderedQuantity ?? 0m) - manufactured
                });
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

            // 1. Process Production Scans (Enterprise Tables only)
            if (request.Scans != null && request.Scans.Any())
            {
                using var scanTransaction = await _scanContext.Database.BeginTransactionAsync();
                try
                {
                    // Batch resolve Order Line GUIDs for performance
                    var soNumbers = request.Scans.Select(s => s.SoNumber).Distinct().ToList();
                    var itemCodes = request.Scans.Select(s => s.ItemCode).Distinct().ToList();
                    var syncIds = request.Scans.Select(s => s.SyncId).ToList();

                    var lines = await _scanContext.SalesOrderLines
                        .Include(l => l.Order)
                        .Where(l => soNumbers.Contains(l.Order.SourceOrderId) && itemCodes.Contains(l.ItemCode))
                        .ToListAsync();

                    // Pre-fetch check for existing scans (Idempotency)
                    var existingSyncIds = await _scanContext.ProductionScanTransactions
                        .Where(s => syncIds.Contains(s.SyncId))
                        .Select(s => s.SyncId)
                        .ToListAsync();

                    // Pre-fetch existing States
                    var lineIds = lines.Select(l => l.Id).ToList();
                    var states = await _scanContext.ProductionLineStates
                        .Where(s => lineIds.Contains(s.SalesOrderLineId))
                        .ToDictionaryAsync(s => s.SalesOrderLineId);

                    // Pre-fetch existing Excess pools
                    var existingExcesses = await _scanContext.Excesses
                        .Where(e => soNumbers.Contains(e.SourceBulkSoNumber) && itemCodes.Contains(e.ItemCode))
                        .ToListAsync();
                    
                    // Dictionary for tracking new/updated Excess records in this batch
                    var excessTracker = existingExcesses.ToDictionary(e => (e.SourceBulkSoNumber, e.ItemCode));

                    foreach (var scanDto in request.Scans)
                    {
                        if (existingSyncIds.Contains(scanDto.SyncId)) continue;

                        var line = lines.FirstOrDefault(l => 
                            l.Order.SourceOrderId == scanDto.SoNumber && 
                            l.ItemCode == scanDto.ItemCode);
                        
                        if (line == null) continue;

                        // Insert Transaction (Append-Only)
                        var transaction = new ProductionScanTransaction
                        {
                            SalesOrderLineId = line.Id,
                            ScanAmountKg = scanDto.ScanAmountKg,
                            Barcode = scanDto.Barcode, 
                            LotNumber = scanDto.Lot,
                            Location = scanDto.Location,
                            SyncId = scanDto.SyncId ?? Guid.NewGuid().ToString(),
                            ItemStatus = scanDto.ItemStatus,
                            DeviceId = request.DeviceId,
                            CreatedBy = scanDto.CreatedBy ?? "system",
                            CreatedAt = DateTime.UtcNow
                        };
                        _scanContext.ProductionScanTransactions.Add(transaction);

                        // Update Aggregated State (In-Memory)
                        if (!states.TryGetValue(line.Id, out var state))
                        {
                            state = new ProductionLineState { SalesOrderLineId = line.Id };
                            _scanContext.ProductionLineStates.Add(state);
                            states[line.Id] = state;
                        }
                        
                        state.TotalManufacturedQty += scanDto.ScanAmountKg;
                        state.LastScanId = transaction.Id;
                        state.UpdatedAt = DateTime.UtcNow;

                        // --- AUTO-POPULATE EXCESS TABLE (AGGREGATED) ---
                        if (scanDto.SoNumber.StartsWith("BLK-") || scanDto.SoNumber.StartsWith("CUTS-") || scanDto.SoNumber.StartsWith("FRZ-"))
                        {
                            if (!excessTracker.TryGetValue((scanDto.SoNumber, scanDto.ItemCode), out var excess))
                            {
                                excess = new Excess
                                {
                                    SourceBulkSoNumber = scanDto.SoNumber,
                                    ItemCode = scanDto.ItemCode,
                                    DeliveryDate = line.Order.DeliveryDate ?? DateTime.UtcNow,
                                    TotalManufacturedQuantity = 0,
                                    AllocatedQuantity = 0,
                                    RemainingExcess = 0,
                                    CreatedBy = scanDto.CreatedBy ?? "system-sync"
                                };
                                _scanContext.Excesses.Add(excess);
                                excessTracker[(scanDto.SoNumber, scanDto.ItemCode)] = excess;
                            }
                            
                            excess.TotalManufacturedQuantity += scanDto.ScanAmountKg;
                            excess.RemainingExcess = excess.TotalManufacturedQuantity - excess.AllocatedQuantity;
                            excess.UpdatedAt = DateTime.UtcNow;
                            excess.UpdatedBy = scanDto.CreatedBy ?? "system-sync";
                        }

                        // --- HANDLE ALLOCATIONS FROM POOLS (AGGREGATED) ---
                        if (!string.IsNullOrEmpty(scanDto.Location) && scanDto.Location.StartsWith("ALLOC-"))
                        {
                            var sourceBulkSo = scanDto.Location.Replace("ALLOC-", "");
                            if (excessTracker.TryGetValue((sourceBulkSo, scanDto.ItemCode), out var poolExcess))
                            {
                                poolExcess.AllocatedQuantity += scanDto.ScanAmountKg;
                                poolExcess.RemainingExcess = poolExcess.TotalManufacturedQuantity - poolExcess.AllocatedQuantity;
                                poolExcess.UpdatedAt = DateTime.UtcNow;
                                poolExcess.UpdatedBy = scanDto.CreatedBy ?? "system-sync";
                            }
                            else
                            {
                                // We might need to fetch it if it wasn't in the initial pre-fetch 
                                // (because pre-fetch only looked at soNumbers of current scans)
                                var poolExcessFromDb = await _scanContext.Excesses
                                    .FirstOrDefaultAsync(e => e.SourceBulkSoNumber == sourceBulkSo && e.ItemCode == scanDto.ItemCode);
                                
                                if (poolExcessFromDb != null)
                                {
                                    poolExcessFromDb.AllocatedQuantity += scanDto.ScanAmountKg;
                                    poolExcessFromDb.RemainingExcess = poolExcessFromDb.TotalManufacturedQuantity - poolExcessFromDb.AllocatedQuantity;
                                    poolExcessFromDb.UpdatedAt = DateTime.UtcNow;
                                    poolExcessFromDb.UpdatedBy = scanDto.CreatedBy ?? "system-sync";
                                    excessTracker[(sourceBulkSo, scanDto.ItemCode)] = poolExcessFromDb;
                                }
                            }
                        }
                    }

                    try 
                    {
                        await _scanContext.SaveChangesAsync();
                    }
                    catch (Exception ex)
                    {
                        Console.WriteLine($"DB SAVE ERROR in Sync: {ex.Message}");
                        if (ex.InnerException != null) Console.WriteLine($"INNER ERROR: {ex.InnerException.Message}");
                        throw;
                    }
                    
                    await scanTransaction.CommitAsync();
                    totalCount += request.Scans.Count;
                }
                catch
                {
                    await scanTransaction.RollbackAsync();
                    throw;
                }
            }

            // 2. Process Cut & Bulk Entries (Enterprise Tables only — no legacy writes)
            if (request.CutBulkEntries != null && request.CutBulkEntries.Any())
            {
                using var syncTransaction = await _scanContext.Database.BeginTransactionAsync();
                try
                {
                    // Build DTOs for enterprise sync
                    var headerDtos = request.CutBulkEntries.Select(cb => new SalesOrderHeaderDto
                    {
                        SohNum = cb.EntryNumber,
                        PoNo = cb.PoNumber ?? "",
                        OrderDate = cb.Date,
                        DeliveryDate = cb.Date,
                        CustomerCode = cb.CustomerCode,
                        CustomerName = cb.CustomerName,
                        Rep0 = cb.Salesman1Code ?? "",
                        Rep1 = cb.Salesman2Code ?? "",
                        Site = "INTERNAL",
                        Status = 1,
                        Source = "Internal"
                    }).ToList();

                    var detailDtos = request.CutBulkEntries.Select(cb => new SalesOrderDetailDto
                    {
                        SoNumber = cb.EntryNumber,
                        ItemCode = cb.ItemCode ?? (cb.Type == "Cuts" ? "PROD-CUT" : "PROD-BLK"),
                        Description = cb.ProductName ?? (cb.Type == "Cuts" ? "Internal Production - Cuts" : "Internal Production - Bulk"),
                        Quantity = cb.AmountKg,
                        Unit = "KG"
                    }).ToList();

                    await SyncEnterpriseOrdersAndLinesAsync(headerDtos, detailDtos);

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

            // 3. Process Preparation Status Updates → UPSERT into ProductionLineState.IsPrepared
            if (request.PreparationStatusUpdates != null && request.PreparationStatusUpdates.Any())
            {
                foreach (var update in request.PreparationStatusUpdates)
                {
                    // Resolve the ProductionLineState via SalesOrderLine
                    var line = await _scanContext.SalesOrderLines
                        .Include(l => l.Order)
                        .FirstOrDefaultAsync(l => l.Order.SourceOrderId == update.SoNumber && l.ItemCode == update.ItemCode);

                    if (line == null) continue;

                    var state = await _scanContext.ProductionLineStates.FindAsync(line.Id);
                    if (state != null)
                    {
                        state.IsPrepared = update.IsPrepared;
                        state.UpdatedAt = DateTime.UtcNow;
                    }
                    else
                    {
                        _scanContext.ProductionLineStates.Add(new ProductionLineState
                        {
                            SalesOrderLineId = line.Id,
                            IsPrepared = update.IsPrepared,
                            UpdatedAt = DateTime.UtcNow
                        });
                    }
                }

                await _scanContext.SaveChangesAsync();
                totalCount += request.PreparationStatusUpdates.Count;
            }

            // 4. Process Shipment Preparation Updates → UPSERT into OrderShipmentStatus (KEPT table)
            if (request.ShipmentPreparationUpdates != null && request.ShipmentPreparationUpdates.Any())
            {
                foreach (var update in request.ShipmentPreparationUpdates)
                {
                    var existing = await _scanContext.OrderShipmentStatuses
                        .FirstOrDefaultAsync(s => s.SoNumber == update.SoNumber);

                    if (existing != null)
                    {
                        existing.IsPreparedForShipment = update.IsPreparedForShipment;
                        if (update.IsValidated.HasValue) existing.IsValidated = update.IsValidated.Value;
                        existing.UpdatedAt = DateTime.UtcNow;
                    }
                    else
                    {
                        _scanContext.OrderShipmentStatuses.Add(new OrderShipmentStatus
                        {
                            SoNumber = update.SoNumber,
                            IsPreparedForShipment = update.IsPreparedForShipment,
                            IsValidated = update.IsValidated ?? false,
                            UpdatedAt = DateTime.UtcNow
                        });
                    }
                }

                await _scanContext.SaveChangesAsync();
                totalCount += request.ShipmentPreparationUpdates.Count;
            }

            // 5. Process Order Status Updates → INSERT into OrderStatusHistory (KEPT table)
            if (request.OrderStatusUpdates != null && request.OrderStatusUpdates.Any())
            {
                foreach (var update in request.OrderStatusUpdates)
                {
                    if (update.Status == 2)
                    {
                        // Check if already closed
                        var alreadyClosed = await _scanContext.OrderStatusHistories
                            .AnyAsync(h => h.SoNumber == update.SoNumber && h.Status == 2);

                        if (!alreadyClosed)
                        {
                            _scanContext.OrderStatusHistories.Add(new OrderStatusHistory
                            {
                                SoNumber = update.SoNumber,
                                Status = 2,
                                ChangedBy = "sync-push",
                                ChangedAt = DateTime.UtcNow
                            });
                        }
                    }
                }

                await _scanContext.SaveChangesAsync();
                totalCount += request.OrderStatusUpdates.Count;
            }

            return totalCount;
        }

        private async Task SyncEnterpriseOrdersAndLinesAsync(IEnumerable<SalesOrderHeaderDto> orderDtos, IEnumerable<SalesOrderDetailDto> detailDtos)
        {
            if (orderDtos == null || !orderDtos.Any()) return;

            // 1. Sync Headers (SalesOrders)
            var sohNums = orderDtos.Select(d => d.SohNum).Distinct().ToList();
            var existingOrders = await _scanContext.SalesOrders
                .Where(o => sohNums.Contains(o.SourceOrderId))
                .ToListAsync();

            foreach (var dto in orderDtos)
            {
                var existing = existingOrders.FirstOrDefault(o => o.SourceOrderId == dto.SohNum);
                var salesman = string.IsNullOrEmpty(dto.Rep1) ? dto.Rep0 : $"{dto.Rep0} / {dto.Rep1}";

                if (existing != null)
                {
                    existing.PoNumber = dto.PoNo;
                    existing.DeliveryDate = dto.DeliveryDate;
                    existing.Salesman = salesman;
                    existing.CustomerCode = dto.CustomerCode;
                    existing.CustomerName = dto.CustomerName;
                    existing.Site = dto.Site;
                    existing.Status = dto.Status;
                    existing.UpdatedAt = DateTime.UtcNow;
                }
                else
                {
                    existing = new SalesOrder
                    {
                        SourceOrderId = dto.SohNum,
                        SourceSystem = dto.Source ?? "X3",
                        PoNumber = dto.PoNo,
                        OrderDate = dto.OrderDate,
                        DeliveryDate = dto.DeliveryDate,
                        Salesman = salesman,
                        CustomerCode = dto.CustomerCode,
                        CustomerName = dto.CustomerName,
                        Site = dto.Site,
                        Status = dto.Status,
                        CreatedAt = DateTime.UtcNow
                    };
                    _scanContext.SalesOrders.Add(existing);
                    existingOrders.Add(existing);
                }
            }

            await _scanContext.SaveChangesAsync();

            // 2. Sync Lines (SalesOrderLines)
            var linesToProcess = detailDtos.ToList();
            var existingLines = await _scanContext.SalesOrderLines
                .Include(l => l.Order)
                .Where(l => sohNums.Contains(l.Order.SourceOrderId))
                .ToListAsync();

            foreach (var dto in linesToProcess)
            {
                var order = existingOrders.FirstOrDefault(o => o.SourceOrderId == dto.SoNumber);
                if (order == null) continue;

                var existingLine = existingLines.FirstOrDefault(l => 
                    l.SalesOrderId == order.Id && l.ItemCode == dto.ItemCode);

                if (existingLine != null)
                {
                    existingLine.Description = dto.Description;
                    existingLine.OrderedQuantity = dto.Quantity ?? 0;
                    existingLine.Unit = dto.Unit;
                }
                else
                {
                    existingLine = new SalesOrderLine
                    {
                        SalesOrderId = order.Id,
                        ItemCode = dto.ItemCode,
                        Description = dto.Description,
                        OrderedQuantity = dto.Quantity ?? 0,
                        Unit = dto.Unit,
                        LineStatus = 1,
                        CreatedAt = DateTime.UtcNow
                    };
                    _scanContext.SalesOrderLines.Add(existingLine);
                    existingLines.Add(existingLine);
                }
            }

            await _scanContext.SaveChangesAsync();

            // 3. Initialize ProductionLineStates for any new lines
            var lineIds = existingLines.Select(l => l.Id).ToList();
            var existingStates = await _scanContext.ProductionLineStates
                .Where(s => lineIds.Contains(s.SalesOrderLineId))
                .Select(s => s.SalesOrderLineId)
                .ToListAsync();

            var newStates = existingLines
                .Where(l => !existingStates.Contains(l.Id))
                .Select(l => new ProductionLineState
                {
                    SalesOrderLineId = l.Id,
                    UpdatedAt = DateTime.UtcNow
                })
                .ToList();

            if (newStates.Any())
            {
                _scanContext.ProductionLineStates.AddRange(newStates);
            }
        }
    }
}
