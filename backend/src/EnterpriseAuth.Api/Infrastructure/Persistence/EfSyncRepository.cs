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
using EnterpriseAuth.Api.Core.Application.Interfaces;
using Microsoft.Extensions.Options;

namespace EnterpriseAuth.Api.Infrastructure.Persistence
{
    public class EfSyncRepository : ISyncRepository
    {
        private readonly string _connectionString;
        private readonly ApplicationDbContext _context;
        private readonly ScanProductionDbContext _scanContext;
        private readonly SyncSettings _syncSettings;
        private readonly ILogisticsRepository _logisticsRepository;
        private readonly IStagingService _stagingService;
        private readonly IX3SchemaProvider _schemaProvider;

        public EfSyncRepository(IConfiguration configuration, ApplicationDbContext context, ScanProductionDbContext scanContext, IOptions<SyncSettings> syncSettings, ILogisticsRepository logisticsRepository, IStagingService stagingService, IX3SchemaProvider schemaProvider)
        {
            _connectionString = configuration.GetConnectionString("Innodis") 
                                ?? throw new ArgumentNullException("Innodis connection string is missing");
            _context = context;
            _scanContext = scanContext;
            _syncSettings = syncSettings.Value;
            _logisticsRepository = logisticsRepository;
            _stagingService = stagingService;
            _schemaProvider = schemaProvider;
        }

        public async Task<SyncPackageDto> GetRefreshPackageAsync(string site)
        {
            var package = new SyncPackageDto();

            // Define fetching tasks with separate connections for parallel execution
            // Pre-fetch customer mappings from ZBTBORD to avoid slow OUTER APPLY
            var ordersTask = FetchFromInnodisAsync<SalesOrderHeaderDto>($@"
                WITH CustMap AS (
                    SELECT MapKey, ORISOCUST_0, ORISOCUSTNAM_0, PONO_0,
                           ROW_NUMBER() OVER(PARTITION BY MapKey ORDER BY PONO_0) as rn
                    FROM (
                        SELECT SONO_0 as MapKey, ORISOCUST_0, ORISOCUSTNAM_0, PONO_0 FROM {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.ZBTBORD
                        UNION ALL
                        SELECT ORISONO_0 as MapKey, ORISOCUST_0, ORISOCUSTNAM_0, PONO_0 FROM {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.ZBTBORD WHERE ORISONO_0 IS NOT NULL AND ORISONO_0 <> ''
                    ) t
                )
                SELECT 
                    f0.SOHNUM_0 COLLATE DATABASE_DEFAULT as [SohNum],
                    m.PONO_0 COLLATE DATABASE_DEFAULT as [PoNo],
                    f0.ORDDAT_0 as [OrderDate],
                    f0.SHIDAT_0 as [DeliveryDate],
                    COALESCE(NULLIF(m.ORISOCUST_0, ''), f0.BPCORD_0) COLLATE DATABASE_DEFAULT as [CustomerCode],
                    COALESCE(NULLIF(m.ORISOCUSTNAM_0, ''), c.ZFULLBUSNAM_0) COLLATE DATABASE_DEFAULT as [CustomerName],
                    LTRIM(RTRIM(f0.REP_0)) COLLATE DATABASE_DEFAULT as [Rep0],
                    f0.REP_1 COLLATE DATABASE_DEFAULT as [Rep1],
                    f0.STOFCY_0 COLLATE DATABASE_DEFAULT as [Site],
                    ISNULL(CONCAT(LTRIM(RTRIM(sdh.REPNUM2_0)), ' - ', LTRIM(RTRIM(sdh.REP2_0))), LTRIM(RTRIM(f0.REP_0))) COLLATE DATABASE_DEFAULT as [Salesman],
                    f0.ORDSTA_0 as [Status],
                    'External' as [Source]
                FROM {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.SORDER f0 WITH (NOLOCK)
                LEFT JOIN {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.ZCONSORDERS sdh WITH (NOLOCK) ON f0.SOHNUM_0 = sdh.SOHNUM_0
                LEFT JOIN CustMap m ON f0.SOHNUM_0 = m.MapKey AND m.rn = 1
                JOIN {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.BPCUSTOMER c WITH (NOLOCK) ON f0.BPCORD_0 = c.BPCNUM_0
                WHERE f0.STOFCY_0 = @Site AND f0.SHIDAT_0 >= DATEADD(day, -7, CAST(GETDATE() AS DATE))
                ORDER BY f0.ORDDAT_0 DESC", new { Site = site });

            var detailsTask = FetchFromInnodisAsync<SalesOrderDetailDto>($@"
                WITH CustMap AS (
                    SELECT MapKey, ORISOCUST_0, ORISOCUSTNAM_0,
                           ROW_NUMBER() OVER(PARTITION BY MapKey ORDER BY ORISOCUST_0) as rn
                    FROM (
                        SELECT SONO_0 as MapKey, ORISOCUST_0, ORISOCUSTNAM_0 FROM {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.ZBTBORD
                        UNION ALL
                        SELECT ORISONO_0 as MapKey, ORISOCUST_0, ORISOCUSTNAM_0 FROM {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.ZBTBORD WHERE ORISONO_0 IS NOT NULL AND ORISONO_0 <> ''
                    ) t
                )
                SELECT 
                    f0.SOHNUM_0 as SoNumber,
                    f2.ITMREF_0 as ItemCode,
                    f2.ITMDES1_0 as Description,
                    'Variable Weight' as BarcodeType,
                    f1.QTY_0 as Quantity,
                    f1.SOPLIN_0 as Soplin,
                    f2.SAU_0 as Unit,
                    f1.STOFCY_0 as Site,
                    COALESCE(NULLIF(m.ORISOCUST_0, ''), f0.BPCORD_0) as CustomerCode,
                    COALESCE(NULLIF(m.ORISOCUSTNAM_0, ''), c.ZFULLBUSNAM_0) as CustomerName
                FROM {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.SORDER f0 WITH (NOLOCK)
                JOIN {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.SORDERQ f1 WITH (NOLOCK) on f0.SOHNUM_0 = f1.SOHNUM_0
                JOIN {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.ITMMASTER f2 WITH (NOLOCK) on f1.ITMREF_0 = f2.ITMREF_0
                JOIN {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.BPCUSTOMER c WITH (NOLOCK) ON f0.BPCORD_0 = c.BPCNUM_0
                LEFT JOIN CustMap m ON f0.SOHNUM_0 = m.MapKey AND m.rn = 1
                WHERE f0.STOFCY_0 = @Site AND f0.SHIDAT_0 >= DATEADD(day, -7, CAST(GETDATE() AS DATE))", new { Site = site });

            var customersTask = FetchFromInnodisAsync<CustomerLookupDto>($"SELECT DISTINCT BPCNUM_0 as Code, ZFULLBUSNAM_0 as Name FROM {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.BPCUSTOMER WITH (NOLOCK)");
            var repsTask = FetchFromInnodisAsync<SalesRepLookupDto>($"SELECT DISTINCT REPNUM_0 as Code, REPNAM_0 as Name FROM {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.SALESREP WITH (NOLOCK)");
            var sitesTask = FetchFromInnodisAsync<SiteLookupDto>($"SELECT DISTINCT FCY_0 as Code, FCYNAM_0 as Name FROM {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.FACILITY WITH (NOLOCK)");
            
            var locSql = $@"
                SELECT 
                    T1.STOFCY_0 as Site, T1.LOC_0 as Location, T1.WRH_0 as Warehouse,
                    WRH.WRHNAM_0 as WarehouseName, T1.LOCTYP_0 as LocationType,
                    ATRA.TEXTE_0 as LocationTypeName
                FROM {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.STOLOC T1 WITH (NOLOCK)
                LEFT JOIN {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.WAREHOUSE WRH WITH (NOLOCK) on WRH.WRH_0 = T1.WRH_0 
                LEFT JOIN {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.[ATEXTRA] ATRA WITH (NOLOCK) on T1.STOFCY_0 = ATRA.IDENT1_0 
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
                    FROM {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.ITMMASTER f0 WITH (NOLOCK)
                    JOIN {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.ITMFACILIT f1 WITH (NOLOCK) ON f0.ITMREF_0 = f1.ITMREF_0
                ) AS T1
                WHERE T1.Site = @Site
                  AND T1.Category NOT IN ('ADMIN','CONSU','TECHN')";
            var productsTask = FetchFromInnodisAsync<ProductLookupDto>(productsSql, new { Site = site });

            var lotsSql = $@"
                SELECT DISTINCT ITMREF_0 as ItemCode, STOFCY_0 as SiteCode, LOT_0 as Lot
                FROM {_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}.STOCK WITH (NOLOCK)
                WHERE STOFCY_0 = @Site AND QTYPCU_0 > 0";
            var lotsTask = FetchFromInnodisAsync<LotLookupDto>(lotsSql, new { Site = site });

            // Execute tasks in parallel
            await Task.WhenAll(ordersTask, detailsTask, customersTask, repsTask, locationsTask, productsTask, sitesTask, lotsTask);

            package.Orders = ordersTask.Result.ToList();
            package.Details = detailsTask.Result.ToList();

            // --- MERGE INTERNAL ORDERS ---
            var internalOrders = await _scanContext.SalesOrders
                .Include(o => o.Lines)
                .Where(o => o.SourceSystem == "Internal" && !o.IsArchived)
                .ToListAsync();

            foreach (var order in internalOrders)
            {
                if (!package.Orders.Any(o => o.SohNum == order.SourceOrderId))
                {
                    package.Orders.Add(new SalesOrderHeaderDto
                    {
                        SohNum = order.SourceOrderId,
                        PoNo = order.PoNumber ?? "",
                        OrderDate = order.OrderDate,
                        DeliveryDate = order.DeliveryDate,
                        CustomerCode = order.CustomerCode,
                        CustomerName = order.CustomerName ?? "",
                        Rep0 = order.Rep0 ?? "",
                        Rep1 = order.Rep1 ?? "",
                        Site = order.Site ?? "IPL",
                        Salesman = order.Salesman ?? "INTERNAL",
                        Status = order.Status,
                        Source = "Internal",
                        IsProcessed = order.IsProcessed
                    });

                    foreach (var line in order.Lines)
                    {
                        package.Details.Add(new SalesOrderDetailDto
                        {
                            SoNumber = order.SourceOrderId,
                            ItemCode = line.ItemCode,
                            Description = line.Description,
                            Quantity = line.OrderedQuantity,
                            Unit = line.Unit,
                            Soplin = line.LineNumber,
                            Site = order.Site ?? "INTERNAL"
                        });
                    }
                }
            }

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

                var processedOrders = await _scanContext.SalesOrders
                    .Where(o => allSoNumbers.Contains(o.SourceOrderId) && o.IsProcessed)
                    .Select(o => o.SourceOrderId)
                    .ToListAsync();
                
                foreach (var header in package.Orders)
                {
                    if (closedSoNumbers.Contains(header.SohNum))
                        header.Status = 2;
                    if (shipmentReady.Contains(header.SohNum))
                        header.IsPreparedForShipment = true;
                    if (processedOrders.Contains(header.SohNum))
                        header.IsProcessed = true;
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

            // Pull latest scanned lot number from active scans
            var scans = await _scanContext.ProductionScanTransactions
                .Where(t => !t.IsDeleted && !t.IsArchived)
                .Join(_scanContext.SalesOrderLines,
                    t => t.SalesOrderLineId,
                    l => l.Id,
                    (t, l) => new { t.CreatedAt, t.LotNumber, l.ItemCode, l.SalesOrderId })
                .Join(_scanContext.SalesOrders,
                    x => x.SalesOrderId,
                    o => o.Id,
                    (x, o) => new { x.CreatedAt, x.LotNumber, x.ItemCode, o.SourceOrderId })
                .Where(x => allSoNumbers.Contains(x.SourceOrderId))
                .Select(x => new { x.SourceOrderId, x.ItemCode, x.LotNumber, x.CreatedAt })
                .ToListAsync();

            var latestLots = scans
                .GroupBy(x => new { x.SourceOrderId, x.ItemCode })
                .ToDictionary(
                    g => $"{g.Key.SourceOrderId}|{g.Key.ItemCode}",
                    g => g.OrderByDescending(x => x.CreatedAt).Select(x => x.LotNumber).FirstOrDefault() ?? "",
                    StringComparer.OrdinalIgnoreCase
                );

            // Update External Order Details from Enterprise Aggregates
            foreach (var detail in package.Details)
            {
                var state = orderLineStates.FirstOrDefault(s => 
                    s.OrderLine.Order.SourceOrderId == detail.SoNumber && 
                    s.OrderLine.ItemCode == detail.ItemCode);
                
                if (state != null)
                {
                    detail.Manufactured = state.TotalManufacturedQty;
                    detail.EaQuantity = state.TotalEaQty;
                    detail.Remaining = Math.Max(0m, (detail.Quantity ?? 0m) - detail.Manufactured);
                    detail.IsPrepared = state.IsPrepared || state.IsLineCompleted;
                }
                else
                {
                    detail.Remaining = detail.Quantity ?? 0m;
                }

                // Populate Lot number from latest scan transaction
                var lotKey = $"{detail.SoNumber}|{detail.ItemCode}";
                if (latestLots.TryGetValue(lotKey, out var lotNum))
                {
                    detail.Lot = lotNum;
                }
            }

            // Build Internal Orders (Cut & Bulk) from Enterprise SalesOrders
            internalOrders = await _scanContext.SalesOrders
                .Include(o => o.Lines)
                .Where(o => o.SourceSystem == "Internal" && !o.IsArchived)
                .ToListAsync();

            foreach (var order in internalOrders)
            {
                var line = order.Lines.FirstOrDefault();
                var state = orderLineStates.FirstOrDefault(s => s.OrderLine.SalesOrderId == order.Id);

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

            // Fetch Global Settings for Sync (Latest Version from Ledger)
            var globalSettingsList = await _scanContext.GlobalSettings.ToListAsync();
            package.GlobalSettingsMap = globalSettingsList
                .GroupBy(s => s.SettingKey)
                .Select(g => g.OrderByDescending(x => x.UpdatedAt).First())
                .ToDictionary(s => s.SettingKey, s => s.SettingValue);

            // Pull EodProcessAudits to sync down to device
            var eodAudits = await _scanContext.EodProcessAudits
                .Select(e => new EodProcessAuditDto
                {
                    Id = e.Id,
                    EodDate = e.EodDate,
                    WorkOrderNumber = e.WorkOrderNumber,
                    TriggeredBy = e.TriggeredBy,
                    DeviceId = e.DeviceId,
                    CreatedAt = e.CreatedAt,
                    IsDeactivated = e.IsDeactivated
                })
                .ToListAsync();
            package.EodProcessAudits = eodAudits;

            package.SyncTimestamp = DateTime.UtcNow;
            return package;
        }

        private async Task<IEnumerable<T>> FetchFromInnodisAsync<T>(string sql, object? parameters = null)
        {
            using IDbConnection db = new SqlConnection(_connectionString);
            return await db.QueryAsync<T>(sql, parameters);
        }

        public async Task<int> PushUpdatesAsync(SyncPushRequestDto request, string performedBy)
        {
            int totalCount = 0;

            // 1. Process Cut & Bulk Entries (Enterprise Tables only — no legacy writes)
            // MUST happen before scans to ensure SO/Lines exist for on-the-fly entries
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
                        CustomerName = cb.CustomerName ?? "",
                        Rep0 = cb.Salesman1Code ?? "",
                        Rep1 = cb.Salesman2Code ?? "",
                        Site = "IPL",
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

                    foreach (var cb in request.CutBulkEntries)
                    {
                        _scanContext.AuditLogs.Add(new AuditLog
                        {
                            EntityName = "CutBulkEntry",
                            EntityIdString = cb.EntryNumber ?? "UNKNOWN",
                            ActionType = "SYNC_INSERT",
                            Payload = System.Text.Json.JsonSerializer.Serialize(cb),
                            PerformedBy = performedBy,
                            PerformedAt = DateTime.UtcNow,
                            DeviceId = cb.DeviceId ?? request.DeviceId
                        });
                    }


                    await _scanContext.SaveChangesAsync();
                    await syncTransaction.CommitAsync();
                    totalCount += request.CutBulkEntries.Count;
                }
                catch (Exception cbEx)
                {
                    await syncTransaction.RollbackAsync();
                    // Log and continue — do not abort shipment/staging steps downstream
                    Console.WriteLine($"[Sync] WARNING: CutBulk transaction failed and was rolled back. Continuing. Error: {cbEx.Message}");
                    if (cbEx.InnerException != null)
                        Console.WriteLine($"[Sync] INNER: {cbEx.InnerException.Message}");
                }
            }

            // 2. Process Production Scans (Enterprise Tables only)
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
                    
                    var auditLogsToInsert = new List<AuditLog>();

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
                            EaQuantity = scanDto.EaQuantity,
                            Barcode = scanDto.Barcode, 
                            LotNumber = scanDto.Lot,
                            Location = scanDto.Location,
                            SyncId = scanDto.SyncId ?? Guid.NewGuid().ToString(),
                            ItemStatus = scanDto.ItemStatus,
                            DeviceId = scanDto.DeviceId ?? request.DeviceId,
                            CreatedBy = performedBy,
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
                        state.TotalEaQty += scanDto.EaQuantity ?? 0m;
                        state.LastScanId = transaction.Id;
                        state.UpdatedAt = DateTime.UtcNow;

                        // Add to Audit Log Collection
                        auditLogsToInsert.Add(new AuditLog
                        {
                            EntityName = "ProductionScanTransactions",
                            EntityIdString = scanDto.SoNumber,
                            ActionType = "SYNC_INSERT",
                            Payload = System.Text.Json.JsonSerializer.Serialize(new { scanDto.SoNumber, scanDto.ItemCode, scanDto.ScanAmountKg, scanDto.SyncId }),
                            PerformedBy = performedBy,
                            PerformedAt = DateTime.UtcNow,
                            DeviceId = request.DeviceId
                        });

                        // --- AUTO-POPULATE EXCESS TABLE (AGGREGATED) ---
                        if (scanDto.SoNumber.StartsWith("BLK-") || scanDto.SoNumber.StartsWith("CUTS-"))
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
                                    CreatedBy = performedBy
                                };
                                _scanContext.Excesses.Add(excess);
                                excessTracker[(scanDto.SoNumber, scanDto.ItemCode)] = excess;
                            }
                            
                            excess.TotalManufacturedQuantity += scanDto.ScanAmountKg;
                            excess.RemainingExcess = excess.TotalManufacturedQuantity - excess.AllocatedQuantity;
                            excess.UpdatedAt = DateTime.UtcNow;
                            excess.UpdatedBy = performedBy;
                        }

                        // --- HANDLE ALLOCATIONS FROM POOLS (AGGREGATED) ---
                        string? sourceBulkSo = null;
                        if (!string.IsNullOrEmpty(scanDto.Location) && scanDto.Location.StartsWith("ALLOC-"))
                        {
                            sourceBulkSo = scanDto.Location.Replace("ALLOC-", "");
                        }
                        else if (!string.IsNullOrEmpty(scanDto.Barcode) && scanDto.Barcode.StartsWith("ALLOC-"))
                        {
                            // Barcode format: ALLOC-sourceSoNumber-timestamp
                            var parts = scanDto.Barcode.Split('-');
                            if (parts.Length >= 3)
                            {
                                // The source SO number is everything between 'ALLOC-' and the last segment (timestamp)
                                sourceBulkSo = string.Join("-", parts.Skip(1).Take(parts.Length - 2));
                            }
                        }

                        if (sourceBulkSo != null)
                        {
                            if (excessTracker.TryGetValue((sourceBulkSo, scanDto.ItemCode), out var poolExcess))
                            {
                                poolExcess.AllocatedQuantity += scanDto.ScanAmountKg;
                                poolExcess.RemainingExcess = poolExcess.TotalManufacturedQuantity - poolExcess.AllocatedQuantity;
                                poolExcess.UpdatedAt = DateTime.UtcNow;
                                poolExcess.UpdatedBy = performedBy;
                            }
                            else
                            {
                                // We might need to fetch it if it wasn't in the initial pre-fetch
                                var poolExcessFromDb = await _scanContext.Excesses
                                    .FirstOrDefaultAsync(e => e.SourceBulkSoNumber == sourceBulkSo && e.ItemCode == scanDto.ItemCode);
                                
                                if (poolExcessFromDb != null)
                                {
                                    poolExcessFromDb.AllocatedQuantity += scanDto.ScanAmountKg;
                                    poolExcessFromDb.RemainingExcess = poolExcessFromDb.TotalManufacturedQuantity - poolExcessFromDb.AllocatedQuantity;
                                    poolExcessFromDb.UpdatedAt = DateTime.UtcNow;
                                    poolExcessFromDb.UpdatedBy = performedBy;
                                    excessTracker[(sourceBulkSo, scanDto.ItemCode)] = poolExcessFromDb;
                                }
                            }
                        }
                    }

                    try 
                    {
                        if (auditLogsToInsert.Any())
                        {
                            _scanContext.AuditLogs.AddRange(auditLogsToInsert);
                        }
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
                catch (Exception scanEx)
                {
                    await scanTransaction.RollbackAsync();
                    // Log the scan failure but DO NOT rethrow — other sync steps
                    // (StagingEod, LabelAudits, Settings) must still execute.
                    Console.WriteLine($"[Sync] WARNING: Scan transaction failed and was rolled back. Continuing with remaining sync steps. Error: {scanEx.Message}");
                    if (scanEx.InnerException != null)
                        Console.WriteLine($"[Sync] INNER: {scanEx.InnerException.Message}");
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
                        state.IsValidated = update.IsValidated;
                        state.UpdatedAt = DateTime.UtcNow;
                    }
                    else
                    {
                        _scanContext.ProductionLineStates.Add(new ProductionLineState
                        {
                            SalesOrderLineId = line.Id,
                            IsPrepared = update.IsPrepared,
                            IsValidated = update.IsValidated,
                            UpdatedAt = DateTime.UtcNow
                        });
                    }

                    if (update.IsPrepared)
                    {
                        _scanContext.AuditLogs.Add(new AuditLog
                        {
                            EntityName = "ProductionLineState",
                            EntityIdString = $"{update.SoNumber}_{update.ItemCode}",
                            ActionType = "UPDATE_PREP_STATUS",
                            Payload = System.Text.Json.JsonSerializer.Serialize(update),
                            PerformedBy = performedBy,
                            PerformedAt = DateTime.UtcNow,
                            DeviceId = update.DeviceId ?? request.DeviceId
                        });
                    }

                    if (update.IsValidated)
                    {
                        _scanContext.AuditLogs.Add(new AuditLog
                        {
                            EntityName = "ProductionLineState",
                            EntityIdString = $"{update.SoNumber}_{update.ItemCode}",
                            ActionType = "VALIDATE_ITEM",
                            Payload = System.Text.Json.JsonSerializer.Serialize(update),
                            PerformedBy = performedBy,
                            PerformedAt = DateTime.UtcNow,
                            DeviceId = update.DeviceId ?? request.DeviceId
                        });
                    }
                }

                await _scanContext.SaveChangesAsync();
                totalCount += request.PreparationStatusUpdates.Count;
            }

            // 4. Process Shipment Preparation Updates → UPSERT into OrderShipmentStatus (KEPT table)
            Console.WriteLine($"[Sync] ShipmentPreparationUpdates received: {request.ShipmentPreparationUpdates?.Count ?? 0}");
            if (request.ShipmentPreparationUpdates != null && request.ShipmentPreparationUpdates.Any())
            {
                try 
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
                            existing.UpdatedBy = performedBy;
                        }
                        else
                        {
                            _scanContext.OrderShipmentStatuses.Add(new OrderShipmentStatus
                            {
                                SoNumber = update.SoNumber,
                                IsPreparedForShipment = update.IsPreparedForShipment,
                                IsValidated = update.IsValidated ?? false,
                                UpdatedAt = DateTime.UtcNow,
                                UpdatedBy = performedBy
                            });
                        }

                        _scanContext.AuditLogs.Add(new AuditLog
                        {
                            EntityName = "OrderShipmentStatus",
                            EntityIdString = update.SoNumber,
                            ActionType = "UPDATE_SHIP_STATUS",
                            Payload = System.Text.Json.JsonSerializer.Serialize(update),
                            PerformedBy = performedBy,
                            PerformedAt = DateTime.UtcNow,
                            DeviceId = request.DeviceId
                        });

                        // TRIGGER: Populate Staging Table if marked as prepared
                        if (update.IsPreparedForShipment)
                        {
                            Console.WriteLine($"[Sync] Triggering Staging Population for {update.SoNumber}...");
                            await _stagingService.PopulateStagingAsync(update.SoNumber);
                        }
                    }

                    await _scanContext.SaveChangesAsync();
                    totalCount += request.ShipmentPreparationUpdates.Count;
                }
                catch (Exception shipEx)
                {
                    Console.WriteLine($"[Sync] WARNING: Shipment Preparation processing failed. Error: {shipEx.Message}");
                    if (shipEx.InnerException != null)
                        Console.WriteLine($"[Sync] INNER: {shipEx.InnerException.Message}");
                }
            }

            // 5. Process Order Status Updates → INSERT into OrderStatusHistory (KEPT table)
            if (request.OrderStatusUpdates != null && request.OrderStatusUpdates.Any())
            {
                try 
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
                                    ChangedBy = performedBy,
                                    ChangedAt = DateTime.UtcNow
                                });

                                _scanContext.AuditLogs.Add(new AuditLog
                                {
                                    EntityName = "OrderStatusHistory",
                                    EntityIdString = update.SoNumber,
                                    ActionType = "CLOSE_ORDER",
                                    Payload = System.Text.Json.JsonSerializer.Serialize(update),
                                    PerformedBy = performedBy,
                                    PerformedAt = DateTime.UtcNow,
                                    DeviceId = request.DeviceId
                                });
                            }
                        }
                    }

                    await _scanContext.SaveChangesAsync();
                    totalCount += request.OrderStatusUpdates.Count;
                }
                catch (Exception statusEx)
                {
                    Console.WriteLine($"[Sync] WARNING: Order Status update failed. Error: {statusEx.Message}");
                }
            }

            // 6. Process Label Audits
            if (request.LabelAudits != null && request.LabelAudits.Any())
            {
                var labelIds = request.LabelAudits.Select(a => a.LabelId).Distinct().ToList();
                var existingLabels = await _scanContext.LabelAudits
                    .Where(l => labelIds.Contains(l.LabelId))
                    .Select(l => l.LabelId)
                    .ToListAsync();

                foreach (var auditDto in request.LabelAudits)
                {
                    if (existingLabels.Contains(auditDto.LabelId)) continue;

                    _scanContext.LabelAudits.Add(new LabelAudit
                    {
                        LabelId = auditDto.LabelId,
                        ReferenceNumber = auditDto.ReferenceNumber,
                        LabelType = auditDto.LabelType,
                        ProductCode = auditDto.ProductCode,
                        CustomerName = auditDto.CustomerName,
                        TotalWeight = auditDto.TotalWeight,
                        ManifestJson = auditDto.ManifestJson,
                        PrintedBy = performedBy,
                        CreatedAt = auditDto.CreatedAt,
                        IsOfflineCreated = auditDto.IsOfflineCreated,
                        DeviceId = auditDto.DeviceId ?? request.DeviceId
                    });
                }
                await _scanContext.SaveChangesAsync();
                totalCount += request.LabelAudits.Count;
            }

            // 7. Process Global Settings Updates (Sync from Device)
            if (request.GlobalSettingsUpdates != null && request.GlobalSettingsUpdates.Any())
            {
                var keys = request.GlobalSettingsUpdates.Select(u => u.SettingKey).ToList();
                // To maintain the ledger correctly and generate AuditLog entries, we get the LATEST setting for each key.
                var existingSettings = await _scanContext.GlobalSettings
                    .Where(s => keys.Contains(s.SettingKey))
                    .OrderByDescending(s => s.UpdatedAt)
                    .ToListAsync();

                foreach (var updateDto in request.GlobalSettingsUpdates)
                {
                    var existing = existingSettings.FirstOrDefault(s => s.SettingKey == updateDto.SettingKey);
                    
                    // If the value hasn't changed from the absolute latest, we could skip it to avoid blowing up the ledger.
                    // But if it's identical, maybe we do skip, or do we log an update? Usually ledger doesn't append if nothing changes.
                    if (existing != null && existing.SettingValue == updateDto.SettingValue)
                    {
                        continue; // No actual change
                    }

                    string oldValue = existing?.SettingValue ?? "NOT_SET";
                    string author = !string.IsNullOrEmpty(updateDto.UpdatedBy) ? updateDto.UpdatedBy : request.DeviceId;

                    // ALWAYS INSERT A NEW RECORD (Append-Only Ledger)
                    _scanContext.GlobalSettings.Add(new GlobalSetting
                    {
                        SettingKey = updateDto.SettingKey,
                        SettingValue = updateDto.SettingValue,
                        LastUpdatedBy = author,
                        UpdatedAt = DateTime.UtcNow,
                        Action = existing == null ? "INSERT" : "UPDATE"
                    });

                    // Create Audit Entry
                    _scanContext.AuditLogs.Add(new AuditLog
                    {
                        EntityName = "GlobalSetting",
                        EntityIdString = updateDto.SettingKey,
                        ActionType = existing == null ? "INSERT" : "UPDATE",
                        Payload = $"{{\"key\":\"{updateDto.SettingKey}\",\"old\":\"{oldValue}\",\"new\":\"{updateDto.SettingValue}\"}}",
                        PerformedBy = performedBy,
                        PerformedAt = DateTime.UtcNow,
                        DeviceId = request.DeviceId
                    });

                    // --- CASCADE TO EXCESS TABLE ---
                    if (updateDto.SettingKey == "ExcessDefaultCustomer" || updateDto.SettingKey == "ExcessDefaultSalesman")
                    {
                        var today = DateTime.UtcNow.Date;
                        var activeExcesses = await _scanContext.Excesses
                            .Where(e => e.DeliveryDate >= today)
                            .ToListAsync();

                        foreach (var excess in activeExcesses)
                        {
                            string oldVal = updateDto.SettingKey == "ExcessDefaultCustomer" ? excess.CustomerCode : excess.Salesman;
                            
                            if (updateDto.SettingKey == "ExcessDefaultCustomer") excess.CustomerCode = updateDto.SettingValue;
                            if (updateDto.SettingKey == "ExcessDefaultSalesman") excess.Salesman = updateDto.SettingValue;

                            _scanContext.AuditLogs.Add(new AuditLog
                            {
                                EntityName = "Excess",
                                EntityIdString = excess.SourceBulkSoNumber,
                                ActionType = "CASCADE_UPDATE",
                                Payload = $"{{\"excessId\":\"{excess.Id}\",\"triggeredBySetting\":\"{updateDto.SettingKey}\",\"old\":\"{oldVal ?? "NULL"}\",\"new\":\"{updateDto.SettingValue}\"}}",
                                PerformedBy = author,
                                PerformedAt = DateTime.UtcNow,
                                DeviceId = request.DeviceId
                            });
                        }
                    }
                }
                await _scanContext.SaveChangesAsync();
                totalCount += request.GlobalSettingsUpdates.Count;
            }

            // 8. Process Staging EOD Entries (Offline Production Tracking)
            Console.WriteLine($"[Sync] StagingEodEntries received: {request.StagingEodEntries?.Count ?? 0}");
            if (request.StagingEodEntries != null && request.StagingEodEntries.Any())
            {
                // Process all entries — do not silently drop zero-quantity records
                // (the device may have valid entries with small decimals that round to 0 in transit)
                var validEntries = request.StagingEodEntries
                    .Where(e => e.TotalManufacturedQuantity >= 0)
                    .ToList();
                
                if (validEntries.Any())
                {
                    Console.WriteLine($"[Sync] Processing {validEntries.Count} valid StagingEod entries from device {request.DeviceId}");

                var eodIds = validEntries.Select(e => e.Id).ToList();
                var existingEodIds = await _scanContext.StagingEodRecords
                    .Where(e => eodIds.Contains(e.Id))
                    .Select(e => e.Id)
                    .ToListAsync();

                // 1. Fetch CCE_0, CCE_1 and STU_0 (stock unit) from ITMMASTER
                var productCodes = validEntries.Select(e => e.ProductCode).Distinct().ToList();
                var cceMapping = new Dictionary<string, (string Cce0, string Cce1, string Unit)>();
                
                if (productCodes.Any())
                {
                    try 
                    {
                        using IDbConnection db = new SqlConnection(_connectionString);
                        string schema = $"{_syncSettings.X3DatabaseName}.{_schemaProvider.GetSchemaName()}";
                        string sql = $@"SELECT ITMREF_0 as ProductCode, CCE_0 as Cce0, CCE_1 as Cce1, STU_0 as Unit FROM {schema}.ITMMASTER WHERE ITMREF_0 IN @Codes";
                        var results = await db.QueryAsync(sql, new { Codes = productCodes });
                        foreach (var row in results)
                        {
                            string prodCode = row.ProductCode;
                            string c0   = row.Cce0?.ToString() ?? string.Empty;
                            string c1   = row.Cce1?.ToString() ?? string.Empty;
                            string unit = row.Unit?.ToString().Trim() ?? string.Empty;
                            cceMapping[prodCode] = (c0, c1, unit);
                        }
                    }
                    catch (Exception ex)
                    {
                        Console.WriteLine($"[Sync] Warning: Could not fetch CCE/Unit mapping from X3: {ex.Message}. Falling back to DTO values.");
                    }
                }

                // Pre-fetch ALL existing unprocessed records for this work order keyed by WorkOrder|Product|Lot
                var workOrderNumbers = validEntries.Select(e => e.WorkOrderNumber).Distinct().ToList();
                var existingEodRecords = await _scanContext.StagingEodRecords
                    .Where(e => workOrderNumbers.Contains(e.WorkOrderNumber) && !e.IsProcessed)
                    .ToListAsync();
                // Key includes LotNumber so each lot gets its own distinct row
                var existingEodLookup = existingEodRecords
                    .ToDictionary(e => $"{e.WorkOrderNumber}|{e.ProductCode}|{e.LotNumber ?? ""}", StringComparer.OrdinalIgnoreCase);

                foreach (var dto in validEntries)
                {                    
                    var cce = cceMapping.ContainsKey(dto.ProductCode) ? cceMapping[dto.ProductCode] : (Cce0: string.Empty, Cce1: string.Empty, Unit: string.Empty);
                    // Resolve authoritative unit: prefer ITMMASTER.STU_0, fall back to DTO, then 'KG'
                    var resolvedUnit = !string.IsNullOrEmpty(cce.Unit) ? cce.Unit
                                    : !string.IsNullOrEmpty(dto.Unit)  ? dto.Unit
                                    : "KG";
                    // Include LotNumber in key so each lot is stored as a separate EOD row
                    var key = $"{dto.WorkOrderNumber}|{dto.ProductCode}|{dto.LotNumber ?? ""}";

                    if (existingEodLookup.TryGetValue(key, out var existing))
                    {
                        // UPSERT: update the quantity, dates, lot and unit on the existing row
                        // Preserve full quantity, no rounding applied
                        existing.TotalManufacturedQuantity = dto.TotalManufacturedQuantity;
                        existing.EaQuantity = dto.EaQuantity;
                        existing.DateOfManufacturing = dto.DateOfManufacturing;
                        existing.ExpiryDate = dto.ExpiryDate;
                        existing.Location = dto.Location;
                        existing.ItemStatus = dto.ItemStatus;
                        existing.LotNumber = dto.LotNumber;             // ← fix: persist lot
                        existing.DeviceId = dto.DeviceId ?? request.DeviceId; // ← fix: persist device ID
                        existing.Unit = resolvedUnit;                   // ← fix: use ITMMASTER unit
                        if (!string.IsNullOrEmpty(cce.Cce0)) existing.Location2 = cce.Cce0;
                        if (!string.IsNullOrEmpty(cce.Cce1)) existing.Location3 = cce.Cce1;
                        Console.WriteLine($"[Sync] StagingEod UPSERT (update): {dto.WorkOrderNumber} / {dto.ProductCode} / lot={dto.LotNumber ?? "none"} → qty={dto.TotalManufacturedQuantity}");
                    }
                    else
                    {
                        // INSERT new record
                        var entity = new StagingEod
                        {
                            Id = dto.Id,
                            WorkOrderNumber = dto.WorkOrderNumber,
                            ProductCode = dto.ProductCode,
                            TotalManufacturedQuantity = dto.TotalManufacturedQuantity,
                            DateOfManufacturing = dto.DateOfManufacturing,
                            Unit = resolvedUnit,                       // ← fix: use ITMMASTER unit
                            Location = dto.Location,
                            ItemStatus = dto.ItemStatus,
                            ExpiryDate = dto.ExpiryDate,
                            LotNumber = dto.LotNumber,                 // ← fix: persist lot
                            DeviceId = dto.DeviceId ?? request.DeviceId, // ← fix: persist device ID
                            Location2 = !string.IsNullOrEmpty(cce.Cce0) ? cce.Cce0 : (dto.Location2 ?? string.Empty),
                            Location3 = !string.IsNullOrEmpty(cce.Cce1) ? cce.Cce1 : (dto.Location3 ?? string.Empty),
                            CreatedAt = dto.CreatedAt == default ? DateTime.UtcNow : dto.CreatedAt,
                            IsCompleted = true,
                            EaQuantity = dto.EaQuantity
                        };
                        _scanContext.StagingEodRecords.Add(entity);
                        existingEodLookup[key] = entity; // track within this batch
                        Console.WriteLine($"[Sync] StagingEod INSERT: {dto.WorkOrderNumber} / {dto.ProductCode} / lot={dto.LotNumber ?? "none"} / unit={resolvedUnit} → qty={dto.TotalManufacturedQuantity}");
                    }
                }

                // Consolidated Audit Log for the batch
                _scanContext.AuditLogs.Add(new AuditLog
                {
                    EntityName = "StagingEodBatch",
                    EntityIdString = validEntries.First().WorkOrderNumber,
                    ActionType = "SYNC_UPSERT_BATCH",
                    Payload = $"Upserted {validEntries.Count} EOD records for device {request.DeviceId}",
                    PerformedBy = performedBy,
                    PerformedAt = DateTime.UtcNow,
                    DeviceId = request.DeviceId
                });

                await _scanContext.SaveChangesAsync();
                totalCount += validEntries.Count;
                Console.WriteLine($"[Sync] Successfully upserted {validEntries.Count} StagingEod records.");
                }
                else
                {
                    Console.WriteLine($"[Sync] No valid StagingEod entries found in request (Total: {request.StagingEodEntries.Count}).");
                }
            }

            // 9. Process Offline Audits
            if (request.OfflineAudits != null && request.OfflineAudits.Any())
            {
                foreach (var dto in request.OfflineAudits)
                {
                    if (dto.Entity == "ProductionScan" && dto.Action == "DELETE")
                    {
                        try
                        {
                            var payload = System.Text.Json.JsonDocument.Parse(dto.Payload);
                            var barcode = payload.RootElement.GetProperty("barcode").GetString();

                            var scan = await _scanContext.ProductionScanTransactions
                                .Include(t => t.OrderLine)
                                .ThenInclude(l => l.Order)
                                .FirstOrDefaultAsync(t => t.Barcode == barcode);

                            if (scan != null)
                            {
                                // 1. EOD Check: If StagingEod exists for this Work Order, EOD is processed
                                var eodProcessed = await _scanContext.StagingEodRecords
                                    .AnyAsync(e => e.WorkOrderNumber == scan.OrderLine.Order.SourceOrderId);

                                if (eodProcessed)
                                {
                                    Console.WriteLine($"[Sync] Rejected DELETE for {barcode}: EOD already processed for WO {scan.OrderLine.Order.SourceOrderId}");
                                }
                                else
                                {
                                    // 2. Create Reversal Transaction
                                    var reversal = new ProductionScanTransaction
                                    {
                                        SalesOrderLineId = scan.SalesOrderLineId,
                                        ScanAmountKg = -scan.ScanAmountKg,
                                        EaQuantity = scan.EaQuantity.HasValue ? -scan.EaQuantity.Value : null,
                                        Barcode = scan.Barcode,
                                        LotNumber = scan.LotNumber,
                                        Location = scan.Location,
                                        SyncId = Guid.NewGuid().ToString(), // Unique SyncId for the reversal
                                        ItemStatus = "REVERSED",
                                        DeviceId = scan.DeviceId,
                                        CreatedBy = performedBy,
                                        CreatedAt = DateTime.UtcNow,
                                        IsDeleted = false
                                    };

                                    _scanContext.ProductionScanTransactions.Add(reversal);

                                    // DO NOT mark original as deleted. Both original (+) and reversal (-) 
                                    // remain IsDeleted=false to perfectly balance the ledger sum.
                                    scan.ItemStatus = "DELETED_ORIGINAL";

                                    // 3. Update Aggregated States
                                    var state = await _scanContext.ProductionLineStates
                                        .FirstOrDefaultAsync(s => s.SalesOrderLineId == scan.SalesOrderLineId);
                                    
                                    if (state != null)
                                    {
                                        state.TotalManufacturedQty -= scan.ScanAmountKg;
                                        if (scan.EaQuantity.HasValue)
                                        {
                                            state.TotalEaQty -= scan.EaQuantity.Value;
                                        }
                                        state.UpdatedAt = DateTime.UtcNow;
                                    }

                                    // 4. Update Excess Pools (if applicable)
                                    var soNumber = scan.OrderLine.Order.SourceOrderId;
                                    if (soNumber.StartsWith("BLK-") || soNumber.StartsWith("CUTS-"))
                                    {
                                        var excess = await _scanContext.Excesses
                                            .FirstOrDefaultAsync(e => e.SourceBulkSoNumber == soNumber && e.ItemCode == scan.OrderLine.ItemCode);
                                        
                                        if (excess != null)
                                        {
                                            excess.TotalManufacturedQuantity -= scan.ScanAmountKg;
                                            excess.RemainingExcess = excess.TotalManufacturedQuantity - excess.AllocatedQuantity;
                                            excess.UpdatedAt = DateTime.UtcNow;
                                            excess.UpdatedBy = performedBy;
                                        }
                                    }

                                    Console.WriteLine($"[Sync] Processed DELETE OfflineAudit for scan {barcode} (Reversal Inserted)");
                                }
                            }
                        }
                        catch (Exception ex)
                        {
                            Console.WriteLine($"[Sync] Failed to process DELETE OfflineAudit: {ex.Message}");
                        }
                    }

                    string entityId = request.DeviceId;
                    try
                    {
                        if (!string.IsNullOrEmpty(dto.Payload))
                        {
                            using (var doc = System.Text.Json.JsonDocument.Parse(dto.Payload))
                            {
                                if (dto.Entity == "ProductionScan")
                                {
                                    if (doc.RootElement.TryGetProperty("barcode", out var barcodeProp))
                                    {
                                        entityId = barcodeProp.GetString() ?? entityId;
                                    }
                                    else if (doc.RootElement.TryGetProperty("syncId", out var syncIdProp))
                                    {
                                        entityId = syncIdProp.GetString() ?? entityId;
                                    }
                                }
                                else if (dto.Entity == "EndOfDay")
                                {
                                    if (doc.RootElement.TryGetProperty("workOrder", out var woProp))
                                    {
                                        entityId = woProp.GetString() ?? entityId;
                                    }
                                }
                                else if (dto.Entity == "CutBulk")
                                {
                                    if (doc.RootElement.TryGetProperty("entryNo", out var entryNoProp))
                                    {
                                        entityId = entryNoProp.GetString() ?? entityId;
                                    }
                                }
                                else if (dto.Entity == "Synchronization")
                                {
                                    if (doc.RootElement.TryGetProperty("timestamp", out var tsProp))
                                    {
                                        entityId = tsProp.GetString() ?? entityId;
                                    }
                                }
                            }
                        }
                    }
                    catch (Exception ex)
                    {
                        Console.WriteLine($"[Sync] Failed to parse offline audit payload for EntityIdString: {ex.Message}");
                    }

                    _scanContext.AuditLogs.Add(new AuditLog
                    {
                        EntityName = dto.Entity,
                        ActionType = dto.Action,
                        Payload = dto.Payload,
                        EntityIdString = entityId,
                        PerformedBy = performedBy,
                        PerformedAt = dto.Timestamp,
                        DeviceId = dto.DeviceId ?? request.DeviceId
                    });
                }
                await _scanContext.SaveChangesAsync();
                totalCount += request.OfflineAudits.Count;
            }

            // 10. Process EOD Process Audits (Offline-first audit trail for EOD completion)
            if (request.EodProcessAudits != null && request.EodProcessAudits.Any())
            {
                try
                {
                    // Fetch existing EodDates to avoid duplicates (idempotent)
                    var incomingDates = request.EodProcessAudits.Select(e => e.EodDate).Distinct().ToList();
                    var existingAudits = await _scanContext.EodProcessAudits
                        .Where(e => incomingDates.Contains(e.EodDate))
                        .ToListAsync();
                    var existingAuditsMap = existingAudits.ToDictionary(e => e.EodDate);

                    foreach (var dto in request.EodProcessAudits)
                    {
                        if (existingAuditsMap.TryGetValue(dto.EodDate, out var existing))
                        {
                            existing.IsDeactivated = dto.IsDeactivated;
                            existing.WorkOrderNumber = dto.WorkOrderNumber;
                            existing.TriggeredBy = dto.TriggeredBy;
                            existing.DeviceId = dto.DeviceId;
                            existing.CreatedAt = dto.CreatedAt == default ? DateTime.UtcNow : dto.CreatedAt;
                        }
                        else
                        {
                            var newAudit = new EodProcessAudit
                            {
                                Id = dto.Id == Guid.Empty ? Guid.NewGuid() : dto.Id,
                                EodDate = dto.EodDate,
                                WorkOrderNumber = dto.WorkOrderNumber,
                                TriggeredBy = dto.TriggeredBy,
                                DeviceId = dto.DeviceId,
                                CreatedAt = dto.CreatedAt == default ? DateTime.UtcNow : dto.CreatedAt,
                                IsDeactivated = dto.IsDeactivated
                            };
                            _scanContext.EodProcessAudits.Add(newAudit);
                            existingAuditsMap[dto.EodDate] = newAudit;
                        }
                    }

                    await _scanContext.SaveChangesAsync();
                    totalCount += request.EodProcessAudits.Count;
                    Console.WriteLine($"[Sync] Stored {request.EodProcessAudits.Count} EodProcessAudit records.");
                }
                catch (Exception eodAuditEx)
                {
                    Console.WriteLine($"[Sync] WARNING: EodProcessAudit sync failed. Error: {eodAuditEx.Message}");
                }
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
                var salesman = !string.IsNullOrEmpty(dto.Salesman) 
                    ? dto.Salesman 
                    : (string.IsNullOrEmpty(dto.Rep1) ? dto.Rep0 : $"{dto.Rep0} / {dto.Rep1}");

                if (existing != null)
                {
                    existing.PoNumber = dto.PoNo;
                    existing.DeliveryDate = dto.DeliveryDate;
                    existing.Salesman = salesman;
                    existing.Rep0 = dto.Rep0;
                    existing.Rep1 = dto.Rep1;
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
                        Rep0 = dto.Rep0,
                        Rep1 = dto.Rep1,
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
                        LineNumber = dto.Soplin,
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
