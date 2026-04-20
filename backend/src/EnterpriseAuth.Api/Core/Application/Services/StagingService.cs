using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using EnterpriseAuth.Api.Core.Domain.Entities;
using EnterpriseAuth.Api.Core.Application.Interfaces;
using EnterpriseAuth.Api.Infrastructure.Persistence;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Options;
using EnterpriseAuth.Api.Core.Application.Common;
using Dapper;
using Microsoft.Data.SqlClient;

namespace EnterpriseAuth.Api.Core.Application.Services
{
    public class StagingService : IStagingService
    {
        private readonly ScanProductionDbContext _context;
        private readonly string _x3ConnectionString;
        private readonly SyncSettings _syncSettings;

        public StagingService(
            ScanProductionDbContext context, 
            IConfiguration configuration, 
            IOptions<SyncSettings> syncSettings)
        {
            _context = context;
            _x3ConnectionString = configuration.GetConnectionString("Innodis") 
                                  ?? throw new ArgumentException("Innodis connection string missing");
            _syncSettings = syncSettings.Value;
        }

        public async Task<bool> PopulateStagingAsync(string soNumber)
        {
            // 1. Avoid duplicates: Check if staging records already exist for this SO
            var exists = await _context.StagingRecords.AnyAsync(s => s.ZSOHNUM_0 == soNumber);
            if (exists) return false;

            // 2. Fetch the metadata from X3 using the comprehensive query
            var metadata = await GetX3MetadataAsync(soNumber);
            
            // SECURITY CHECK: Skip if not found in ZCONSORDERS
            if (metadata == null)
            {
                Console.WriteLine($"[Staging] Skipping {soNumber}: Not found in ZCONSORDERS master table.");
                return false;
            }

            // 3. Fetch local data: SalesOrder, SalesOrderLines, ProductionLineStates, and Locations
            var order = await _context.SalesOrders
                .Include(o => o.Lines)
                .FirstOrDefaultAsync(o => o.SourceOrderId == soNumber);

            if (order == null) return false;

            var lineIds = order.Lines.Select(l => l.Id).ToList();
            var lineStates = await _context.ProductionLineStates
                .Where(s => lineIds.Contains(s.SalesOrderLineId))
                .ToListAsync();

            var scans = await _context.ProductionScanTransactions
                .Where(t => lineIds.Contains(t.SalesOrderLineId) && !t.IsDeleted)
                .Select(t => new { t.SalesOrderLineId, t.Location, t.CreatedAt })
                .ToListAsync();

            var scanLocations = scans
                .GroupBy(t => t.SalesOrderLineId)
                .ToDictionary(
                    g => g.Key, 
                    g => g.OrderByDescending(x => x.CreatedAt).Select(x => x.Location).FirstOrDefault()
                );

            // 4. Map to Staging Entity
            var stagingRecords = new List<Staging>();
            int lineNumber = 1000; // X3 Principle: Start at 1000

            // Mapping ZLOCFCY_0 logic: First 2 characters 
            string lorryCode = "IPL"; // Default
            if (!string.IsNullOrEmpty(metadata.SO_LORRY))
            {
                lorryCode = metadata.SO_LORRY.Length >= 2 
                    ? metadata.SO_LORRY.Substring(0, 2) 
                    : metadata.SO_LORRY;
            }

            // A. Create Header Record (H)
            stagingRecords.Add(new Staging
            {
                ZREC_0 = "H",
                ZSDHTYP_0 = "SDH",
                ZSALFCY_0 = "IPL",
                ZSTOFCY_0 = "IPL",
                ZSDHNUM_0 = $"STG-{soNumber}", // Grouped shipment ID
                ZBPCORD_0 = order.CustomerCode,
                ZSUR_0 = "MUR",
                ZSHIDAT_0 = order.DeliveryDate,
                ZDLVDAT_0 = order.DeliveryDate,
                ZCFMFLG_0 = 2,
                ZLOCFCY_0 = lorryCode,
                ZLOC_0 = null, // Header usually doesn't have a specific scan location
                ZSOHNUM_0 = soNumber,
                ZSOPLIN_0 = 0,
                ZITMREF_0 = null,
                ZITMDES_0 = null,
                ZSAU_0 = null,
                ZQTY_0 = 0,
                CreatedAt = DateTime.UtcNow
            });

            // B. Create Line Records (L)
            foreach (var line in order.Lines)
            {
                var state = lineStates.FirstOrDefault(s => s.SalesOrderLineId == line.Id);
                if (state == null || state.TotalManufacturedQty <= 0) continue;

                stagingRecords.Add(new Staging
                {
                    ZREC_0 = "L",
                    ZSDHTYP_0 = "SDH",
                    ZSALFCY_0 = "IPL",
                    ZSTOFCY_0 = "IPL",
                    ZSDHNUM_0 = $"STG-{soNumber}", // Grouped shipment ID
                    ZBPCORD_0 = order.CustomerCode,
                    ZSUR_0 = "MUR",
                    ZSHIDAT_0 = order.DeliveryDate,
                    ZDLVDAT_0 = order.DeliveryDate,
                    ZCFMFLG_0 = 2,
                    ZLOCFCY_0 = lorryCode,
                    ZLOC_0 = scanLocations.ContainsKey(line.Id) ? scanLocations[line.Id] : null,
                    ZSOHNUM_0 = soNumber,
                    ZSOPLIN_0 = lineNumber,
                    ZITMREF_0 = line.ItemCode,
                    ZITMDES_0 = line.Description,
                    ZSAU_0 = line.Unit,
                    ZQTY_0 = state.TotalManufacturedQty,
                    CreatedAt = DateTime.UtcNow
                });

                lineNumber += 1000; // X3 Principle: Increment by 1000
            }

            if (stagingRecords.Any())
            {
                _context.StagingRecords.AddRange(stagingRecords);
                await _context.SaveChangesAsync();
                return true;
            }

            return false;
        }

        private async Task<X3MetadataDto?> GetX3MetadataAsync(string soNumber)
        {
            try 
            {
                using var connection = new SqlConnection(_x3ConnectionString);
                string sql = $@"
                    SELECT TOP 1
                        SDH.SOHNUM_0 AS SO_NO,
                        SDH.SDHNUM_0 AS DELIVERY_NO,
                        TRP.LANMES_0 AS SO_LORRY,
                        TRP3.LANMES_0 AS ORI_SO_LORRY,
                        SDH.ORIGINALSO_0 AS ORI_SO_NO
                    FROM {_syncSettings.X3DatabaseName}.INLPROD.ZCONSORDERS SDH
                    LEFT JOIN {_syncSettings.X3DatabaseName}.INLPROD.SORDER SOH ON SDH.SOHNUM_0 = SOH.SOHNUM_0
                    LEFT JOIN {_syncSettings.X3DatabaseName}.INLPROD.SDELIVERY SDH2 ON SDH.SDHNUM_0 = SDH2.SDHNUM_0
                    LEFT JOIN {_syncSettings.X3DatabaseName}.INLPROD.SORDER SOHORI ON SDH.ORIGINALSO_0 = SOHORI.SOHNUM_0
                    LEFT JOIN {_syncSettings.X3DatabaseName}.INLPROD.APLSTD TRP 
                        ON TRP.LANCHP_0 = 409
                       AND TRP.LANNUM_0 = SOH.DRN_0
                       AND TRP.LAN_0 = 'BRI'
                    LEFT JOIN {_syncSettings.X3DatabaseName}.INLPROD.APLSTD TRP3 
                        ON TRP3.LANCHP_0 = 409
                       AND TRP3.LANNUM_0 = SOHORI.DRN_0
                       AND TRP3.LAN_0 = 'BRI'
                    WHERE SDH.SOHNUM_0 = @SoNumber";

                return await connection.QueryFirstOrDefaultAsync<X3MetadataDto>(sql, new { SoNumber = soNumber });
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[Staging] Error fetching X3 metadata for {soNumber}: {ex.Message}");
                return null;
            }
        }

        private class X3MetadataDto
        {
            public string SO_NO { get; set; } = string.Empty;
            public string? DELIVERY_NO { get; set; }
            public string? SO_LORRY { get; set; }
            public string? ORI_SO_LORRY { get; set; }
            public string? ORI_SO_NO { get; set; }
        }
    }
}
