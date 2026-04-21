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
            // 1. Avoid duplicates: use ZSDHNUM_0 (STG-{soNumber}) — stable internal key
            //    We cannot use ZSOHNUM_0 for dedup because it now stores the IPL SO number (not soNumber)
            var exists = await _context.StagingRecords.AnyAsync(s => s.ZSDHNUM_0 == $"STG-{soNumber}");
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

            // 4. Batch-fetch VAT levels for all item codes in the order (from X3 ITMMASTER)
            var itemCodes = order.Lines.Select(l => l.ItemCode).Where(c => c != null).Distinct().ToList();
            var vatLevels = await GetItemVatLevelsAsync(itemCodes);
            Console.WriteLine($"[Staging] Fetched VAT levels for {vatLevels.Count}/{itemCodes.Count} items in SO {soNumber}.");

            // 5. Map to Staging Entity
            var stagingRecords = new List<Staging>();
            int lineNumber = 1000; // X3 Principle: Start at 1000

            // Resolve the X3 Sales Order number:
            //   soNumber           = mobile/POD number (e.g. "PODSO260400794") — used to look up in ZCONSORDERS via ORIGINALSO_0
            //   metadata.SO_NO     = ZCONSORDERS.SOHNUM_0 (e.g. "IPLSO251001075") — what X3 expects in the L record
            string x3SoNumber = !string.IsNullOrEmpty(metadata.SO_NO)
                ? metadata.SO_NO
                : soNumber; // safety fallback if SO_NO is somehow null
            Console.WriteLine($"[Staging] SO resolved: mobile={soNumber} → X3 SOHNUM_0={x3SoNumber}");

            // Mapping ZLOCFCY_0 logic: First 2 characters of Lorry trip code
            string lorryCode = "IPL"; // Default
            if (!string.IsNullOrEmpty(metadata.SO_LORRY))
            {
                lorryCode = metadata.SO_LORRY.Length >= 2 
                    ? metadata.SO_LORRY.Substring(0, 2) 
                    : metadata.SO_LORRY;
            }

            // A. Create Header Record (H) — ZVACITM_0 is null for the header row
            stagingRecords.Add(new Staging
            {
                ZREC_0 = "H",
                ZSDHTYP_0 = "SDH",
                ZSALFCY_0 = "IPL",
                ZSTOFCY_0 = "IPL",
                ZSDHNUM_0 = $"STG-{soNumber}", // Internal grouping ID
                ZBPCORD_0 = metadata.ZBPCORD_0,
                ZSUR_0 = "MUR",
                ZSHIDAT_0 = order.DeliveryDate,
                ZDLVDAT_0 = order.DeliveryDate,
                ZCFMFLG_0 = 2,
                ZLOCFCY_0 = lorryCode,
                ZLOC_0 = scanLocations.Values.FirstOrDefault(),
                ZSOHNUM_0 = x3SoNumber,  // Original IPL SO (ORIGINALSO_0) — used in SOAP payload
                ZSOPLIN_0 = 0,
                ZITMREF_0 = null,
                ZITMDES_0 = null,
                ZSAU_0 = null,
                ZQTY_0 = 0,
                ZVACITM_0 = null,  // Not applicable for header
                CreatedAt = DateTime.UtcNow
            });

            // B. Create Line Records (L) — map ZVACITM_0 from the VAT lookup
            foreach (var line in order.Lines)
            {
                var state = lineStates.FirstOrDefault(s => s.SalesOrderLineId == line.Id);
                if (state == null || state.TotalManufacturedQty <= 0) continue;

                // Resolve VAT level: use lookup result, fallback to "STD" if not found
                var vatLevel = (line.ItemCode != null && vatLevels.ContainsKey(line.ItemCode))
                    ? vatLevels[line.ItemCode]
                    : "STD";

                Console.WriteLine($"[Staging] Line {lineNumber}: Item={line.ItemCode}, VAT={vatLevel}, Qty={state.TotalManufacturedQty:F3}");

                stagingRecords.Add(new Staging
                {
                    ZREC_0 = "L",
                    ZSDHTYP_0 = "SDH",
                    ZSALFCY_0 = "IPL",
                    ZSTOFCY_0 = "IPL",
                    ZSDHNUM_0 = $"STG-{soNumber}",
                    ZBPCORD_0 = metadata.ZBPCORD_0,
                    ZSUR_0 = "MUR",
                    ZSHIDAT_0 = order.DeliveryDate,
                    ZDLVDAT_0 = order.DeliveryDate,
                    ZCFMFLG_0 = 2,
                    ZLOCFCY_0 = lorryCode,
                    ZLOC_0 = scanLocations.ContainsKey(line.Id) ? scanLocations[line.Id] : null,
                    ZSOHNUM_0 = x3SoNumber,  // Original IPL SO (ORIGINALSO_0) — used in SOAP L;{ZSOHNUM_0};...
                    ZSOPLIN_0 = lineNumber,
                    ZITMREF_0 = line.ItemCode,
                    ZITMDES_0 = line.Description,
                    ZSAU_0 = line.Unit,
                    ZQTY_0 = state.TotalManufacturedQty,
                    ZVACITM_0 = vatLevel,  // VAT level from X3 ITMMASTER.VACITM_0
                    CreatedAt = DateTime.UtcNow
                });

                lineNumber += 1000;
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
                        SOH.BPCORD_0 AS ZBPCORD_0,
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
                    WHERE SDH.ORIGINALSO_0 = @SoNumber";

                return await connection.QueryFirstOrDefaultAsync<X3MetadataDto>(sql, new { SoNumber = soNumber });
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[Staging] Error fetching X3 metadata for {soNumber}: {ex.Message}");
                return null;
            }
        }

        private async Task<Dictionary<string, string>> GetItemVatLevelsAsync(List<string?> itemCodes)
        {
            try
            {
                var validCodes = itemCodes.Where(c => c != null).Select(c => c!).Distinct().ToList();
                if (!validCodes.Any()) return new Dictionary<string, string>();

                using var connection = new SqlConnection(_x3ConnectionString);
                string sql = $@"
                    SELECT ITMREF_0, ISNULL(VACITM_0, 'STD') AS VACITM_0
                    FROM {_syncSettings.X3DatabaseName}.INLPROD.ITMMASTER
                    WHERE ITMREF_0 IN @ItemCodes";

                var rows = await connection.QueryAsync(sql, new { ItemCodes = validCodes });
                return rows.ToDictionary(
                    row => (string)row.ITMREF_0,
                    row => (string)row.VACITM_0
                );
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[Staging] Warning: VAT level lookup failed: {ex.Message}. Defaulting all lines to 'STD'.");
                return new Dictionary<string, string>();
            }
        }

        private class X3MetadataDto
        {
            public string SO_NO { get; set; } = string.Empty;
            public string? ZBPCORD_0 { get; set; }
            public string? DELIVERY_NO { get; set; }
            public string? SO_LORRY { get; set; }
            public string? ORI_SO_LORRY { get; set; }
            public string? ORI_SO_NO { get; set; }
        }
    }
}
