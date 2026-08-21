using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using EnterpriseAuth.Api.Core.Application.Common;
using EnterpriseAuth.Api.Core.Application.DTOs;
using EnterpriseAuth.Api.Core.Application.Interfaces;
using EnterpriseAuth.Api.Core.Domain.Interfaces;
using EnterpriseAuth.Api.Core.Domain.Entities;
using Microsoft.Extensions.Options;

namespace EnterpriseAuth.Api.Core.Application.Services;

public class LogisticsService : ILogisticsService
{
    private readonly ILogisticsRepository _logisticsRepository;
    private readonly EodSettings _eodSettings;

    public LogisticsService(ILogisticsRepository logisticsRepository, IOptions<EodSettings> eodSettings)
    {
        _logisticsRepository = logisticsRepository;
        _eodSettings = eodSettings.Value;
    }

    public async Task<Result<IEnumerable<ProductionTrackingDto>>> GetProductionTrackingAsync(string? siteCode)
    {
        try
        {
            var tracking = await _logisticsRepository.GetProductionTrackingAsync(siteCode);
            return Result<IEnumerable<ProductionTrackingDto>>.Success(tracking);
        }
        catch (Exception ex)
        {
            return Result<IEnumerable<ProductionTrackingDto>>.Failure($"Failed to fetch production tracking data: {ex.Message}");
        }
    }

    public async Task<Result<IEnumerable<SalesOrderHeaderDto>>> GetSalesOrderHeadersAsync(int? status, DateTime? date, string? customerCode, string? rep0, string? rep1)
    {
        try
        {
            var headers = await _logisticsRepository.GetSalesOrderHeadersAsync(status, date, customerCode, rep0, rep1);
            return Result<IEnumerable<SalesOrderHeaderDto>>.Success(headers);
        }
        catch (Exception ex)
        {
            return Result<IEnumerable<SalesOrderHeaderDto>>.Failure($"Failed to fetch sales order headers: {ex.Message}");
        }
    }

    public async Task<Result<IEnumerable<ProductionTrackingDto>>> GetProductionSummaryAsync(DateTime date)
    {
        try
        {
            var summary = await _logisticsRepository.GetProductionSummaryAsync(date);
            return Result<IEnumerable<ProductionTrackingDto>>.Success(summary);
        }
        catch (Exception ex)
        {
            return Result<IEnumerable<ProductionTrackingDto>>.Failure($"Failed to fetch production summary: {ex.Message}");
        }
    }

    public async Task<Result<IEnumerable<ProductionTrackingDto>>> GetProductionSummaryByWorkOrderAsync(string workOrder)
    {
        try
        {
            var summary = await _logisticsRepository.GetProductionSummaryByWorkOrderAsync(workOrder);
            return Result<IEnumerable<ProductionTrackingDto>>.Success(summary);
        }
        catch (Exception ex)
        {
            return Result<IEnumerable<ProductionTrackingDto>>.Failure($"Failed to fetch work order summary: {ex.Message}");
        }
    }

    public async Task<Result<bool>> CompleteEndOfDayAsync(string workOrder, IEnumerable<ProductionTrackingDto> items)
    {
        try
        {
            var now = DateTime.UtcNow;

            // 1. Fetch work order headers from X3 for CCE_0 / CCE_1 per product
            var woHeaders = await _logisticsRepository.GetWorkOrdersAsync(workOrder);

            // 2. Fetch ALL BOM components using the fixed parent item codes from configuration.
            //    These 3 parent codes (e.g. 3302, 3397, 31169) expand to ~240 component products.
            //    The scanned items are the COMPONENTS, not the parents — do NOT use scanned codes here.
            var parentCodes = _eodSettings.BomParentItemCodes;
            var bomComponents = await _logisticsRepository.GetBomComponentsAsync(parentCodes);

            // Deduplicated set of all BOM component codes
            var allBomComponentCodes = bomComponents
                .Select(b => b.ComponentItemCode)
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToHashSet(StringComparer.OrdinalIgnoreCase);

            // Retrieve authoritative scans directly from server database (ProductionScanTransactions)
            IEnumerable<ProductionTrackingDto> dbItems;
            if (workOrder.StartsWith("ALL-") && workOrder.Length >= 12)
            {
                var dateStr = workOrder.Substring(4, 8);
                if (DateTime.TryParseExact(dateStr, "yyyyMMdd", null, System.Globalization.DateTimeStyles.None, out var parsedDate))
                {
                    dbItems = await _logisticsRepository.GetProductionSummaryAsync(parsedDate);
                }
                else
                {
                    dbItems = await _logisticsRepository.GetProductionSummaryByWorkOrderAsync(workOrder);
                }
            }
            else
            {
                dbItems = await _logisticsRepository.GetProductionSummaryByWorkOrderAsync(workOrder);
            }
            var itemsList = dbItems != null && dbItems.Any() ? dbItems.ToList() : items.ToList();

            var records = new List<StagingEod>();
            var transactionId = Guid.NewGuid();

            // ── 4a: Insert ALL scanned items with their real manufactured qty ───────
            // This preserves actual scan data regardless of BOM membership.
            foreach (var item in itemsList)
            {
                if (item.UnprocessedQuantity <= 0 && item.UnprocessedEaQuantity <= 0) continue; // Skip already processed items

                var header  = woHeaders.FirstOrDefault(h => h.Product == item.ItemCode);
                var mfgDate = item.CreatedAt ?? now;

                records.Add(new StagingEod
                {
                    WorkOrderNumber           = workOrder,
                    ProductCode               = item.ItemCode,
                    TotalManufacturedQuantity = item.UnprocessedQuantity,
                    EaQuantity                = item.UnprocessedEaQuantity,
                    DateOfManufacturing       = mfgDate,
                    ExpiryDate                = mfgDate.AddDays(5),
                    Unit                      = string.IsNullOrEmpty(item.Unit) ? "KG" : item.Unit,
                    Location                  = string.IsNullOrEmpty(item.Location) ? "IPLCH" : item.Location,
                    ItemStatus                = item.StatusLabel ?? "A",
                    LotNumber                 = !string.IsNullOrEmpty(item.LotNumber) ? item.LotNumber : item.Lot,
                    Location2                 = header?.CCE_0 ?? "",
                    Location3                 = header?.CCE_1 ?? "",
                    EodTransactionId          = transactionId
                });
            }

            var success = await _logisticsRepository.SaveStagingEodAsync(records);
            return Result<bool>.Success(success);
        }
        catch (Exception ex)
        {
            return Result<bool>.Failure($"Failed to complete end of day: {ex.Message}");
        }
    }

    public async Task<Result<IEnumerable<SalesOrderDetailDto>>> GetSalesOrderDetailsAsync(string soNumber)
    {
        try
        {
            var details = await _logisticsRepository.GetSalesOrderDetailsAsync(soNumber);
            return Result<IEnumerable<SalesOrderDetailDto>>.Success(details);
        }
        catch (Exception ex)
        {
            return Result<IEnumerable<SalesOrderDetailDto>>.Failure($"Failed to fetch sales order details: {ex.Message}");
        }
    }

    public async Task<Result<IEnumerable<CustomerLookupDto>>> GetCustomerLookupAsync()
    {
        try
        {
            var customers = await _logisticsRepository.GetCustomerLookupAsync();
            return Result<IEnumerable<CustomerLookupDto>>.Success(customers);
        }
        catch (Exception ex)
        {
            return Result<IEnumerable<CustomerLookupDto>>.Failure($"Failed to fetch customers: {ex.Message}");
        }
    }

    public async Task<Result<IEnumerable<SalesRepLookupDto>>> GetSalesRepLookupAsync()
    {
        try
        {
            var salesreps = await _logisticsRepository.GetSalesRepLookupAsync();
            return Result<IEnumerable<SalesRepLookupDto>>.Success(salesreps);
        }
        catch (Exception ex)
        {
            return Result<IEnumerable<SalesRepLookupDto>>.Failure($"Failed to fetch sales representatives: {ex.Message}");
        }
    }

    public async Task<Result<int>> SyncScansAsync(IEnumerable<ScanDto> scans)
    {
        try
        {
            var count = await _logisticsRepository.SyncScansAsync(scans);
            return Result<int>.Success(count);
        }
        catch (Exception ex)
        {
            return Result<int>.Failure($"Failed to sync scans: {ex.Message}");
        }
    }

    public async Task<Result<IEnumerable<LocationLookupDto>>> GetLocationLookupsAsync(string site)
    {
        try
        {
            var locations = await _logisticsRepository.GetLocationLookupsAsync(site);
            return Result<IEnumerable<LocationLookupDto>>.Success(locations);
        }
        catch (Exception ex)
        {
            return Result<IEnumerable<LocationLookupDto>>.Failure($"Failed to fetch locations: {ex.Message}");
        }
    }

    public async Task<Result<IEnumerable<BarcodeMappingDto>>> GetBarcodeMappingsAsync(string siteCode)
    {
        try
        {
            var mappings = await _logisticsRepository.GetBarcodeMappingsAsync(siteCode);
            return Result<IEnumerable<BarcodeMappingDto>>.Success(mappings);
        }
        catch (Exception ex)
        {
            return Result<IEnumerable<BarcodeMappingDto>>.Failure($"Failed to fetch barcode mappings: {ex.Message}");
        }
    }

    public async Task<Result<IEnumerable<LocationLookupDto>>> GetTargetLocationsAsync(string site, string itemCode)
    {
        try
        {
            var locations = await _logisticsRepository.GetTargetLocationsAsync(site, itemCode);
            return Result<IEnumerable<LocationLookupDto>>.Success(locations);
        }
        catch (Exception ex)
        {
            return Result<IEnumerable<LocationLookupDto>>.Failure($"Failed to fetch target locations: {ex.Message}");
        }
    }

    public async Task<Result<bool>> CloseOrderAsync(string soNumber, string closedBy)
    {
        try
        {
            var result = await _logisticsRepository.CloseOrderAsync(soNumber, closedBy);
            return Result<bool>.Success(result);
        }
        catch (Exception ex)
        {
            return Result<bool>.Failure($"Failed to close order: {ex.Message}");
        }
    }
    public async Task<Result<string>> SaveCutBulkAsync(CutBulkEntryDto dto)
    {
        try
        {
            var result = await _logisticsRepository.SaveCutBulkEntryAsync(dto);
            return Result<string>.Success(result);
        }
        catch (Exception ex)
        {
            return Result<string>.Failure($"Failed to save cut/bulk entry: {ex.Message}");
        }
    }

    public async Task<Result<ProductionScanDto>> SaveProductionScanAsync(ProductionScanDto scanDto)
    {
        try
        {
            var result = await _logisticsRepository.SaveProductionScanAsync(scanDto);
            return Result<ProductionScanDto>.Success(result);
        }
        catch (Exception ex)
        {
            return Result<ProductionScanDto>.Failure($"Failed to save production scan: {ex.Message}");
        }
    }

    public async Task<Result<IEnumerable<ProductionScanDto>>> GetProductionScansAsync(string soNumber, string itemCode)
    {
        try
        {
            var result = await _logisticsRepository.GetProductionScansAsync(soNumber, itemCode);
            return Result<IEnumerable<ProductionScanDto>>.Success(result);
        }
        catch (Exception ex)
        {
            return Result<IEnumerable<ProductionScanDto>>.Failure($"Failed to fetch production scans: {ex.Message}");
        }
    }

    public async Task<Result<int>> SaveProductionScansBatchAsync(List<ProductionScanDto> scans)
    {
        try
        {
            var result = await _logisticsRepository.SaveProductionScansBatchAsync(scans);
            return Result<int>.Success(result);
        }
        catch (Exception ex)
        {
            return Result<int>.Failure($"Failed to save production scans batch: {ex.Message}");
        }
    }

    public async Task<Result<IEnumerable<string>>> GetProductionSitesAsync()
    {
        try
        {
            var sites = await _logisticsRepository.GetProductionSitesAsync();
            return Result<IEnumerable<string>>.Success(sites);
        }
        catch (Exception ex)
        {
            return Result<IEnumerable<string>>.Failure($"Failed to fetch production sites: {ex.Message}");
        }
    }

    public async Task<Result<IEnumerable<string>>> GetLotsAsync(string itemCode, string siteCode)
    {
        try
        {
            var lots = await _logisticsRepository.GetLotsAsync(itemCode, siteCode);
            return Result<IEnumerable<string>>.Success(lots);
        }
        catch (Exception ex)
        {
            return Result<IEnumerable<string>>.Failure($"Failed to fetch lots: {ex.Message}");
        }
    }

    public async Task<Result<bool>> UpdateItemPreparationStatusAsync(string soNumber, string itemCode, bool isPrepared, string performedBy = "system")
    {
        try
        {
            var result = await _logisticsRepository.UpdateItemPreparationStatusAsync(soNumber, itemCode, isPrepared, performedBy: performedBy);
            return Result<bool>.Success(result);
        }
        catch (Exception ex)
        {
            return Result<bool>.Failure($"Failed to update item preparation status: {ex.Message}");
        }
    }

    public async Task<Result<bool>> UpdateItemValidationStatusAsync(string soNumber, string itemCode, bool isValidated, string performedBy = "system")
    {
        try
        {
            var result = await _logisticsRepository.UpdateItemValidationStatusAsync(soNumber, itemCode, isValidated, performedBy: performedBy);
            return Result<bool>.Success(result);
        }
        catch (Exception ex)
        {
            return Result<bool>.Failure($"Failed to update item validation status: {ex.Message}");
        }
    }

    public async Task<Result<bool>> BulkUpdateItemStatusAsync(BulkStatusUpdateDto dto)
    {
        try
        {
            var result = await _logisticsRepository.BulkUpdateItemStatusAsync(dto.SoNumber, dto.ItemCodes, dto.Status, dto.IsValidation, performedBy: dto.PerformedBy);
            return Result<bool>.Success(result);
        }
        catch (Exception ex)
        {
            return Result<bool>.Failure($"Failed to bulk update item statuses: {ex.Message}");
        }
    }

    public async Task<Result<IEnumerable<ExcessDto>>> GetExcessByDateAndItemAsync(DateTime deliveryDate, string itemCode)
    {
        try
        {
            var result = await _logisticsRepository.GetExcessByDateAndItemAsync(deliveryDate, itemCode);
            return Result<IEnumerable<ExcessDto>>.Success(result);
        }
        catch (Exception ex)
        {
            return Result<IEnumerable<ExcessDto>>.Failure($"Failed to fetch excess data: {ex.Message}");
        }
    }

    public async Task<Result<bool>> AllocateExcessAsync(AllocateExcessDto dto)
    {
        try
        {
            var result = await _logisticsRepository.AllocateExcessAsync(dto);
            return Result<bool>.Success(result);
        }
        catch (Exception ex)
        {
            return Result<bool>.Failure($"Failed to allocate excess: {ex.Message}");
        }
    }

    public async Task<Result<LabelAuditDto>> LogLabelAuditAsync(LabelAuditDto auditDto)
    {
        try
        {
            var result = await _logisticsRepository.LogLabelAuditAsync(auditDto);
            return Result<LabelAuditDto>.Success(result);
        }
        catch (Exception ex)
        {
            return Result<LabelAuditDto>.Failure($"Failed to log label audit: {ex.Message}");
        }
    }

    public async Task<Result<IEnumerable<WorkOrderDto>>> GetWorkOrdersAsync(string? searchQuery)
    {
        try
        {
            var result = await _logisticsRepository.GetWorkOrdersAsync(searchQuery);
            return Result<IEnumerable<WorkOrderDto>>.Success(result);
        }
        catch (Exception ex)
        {
            return Result<IEnumerable<WorkOrderDto>>.Failure($"Failed to fetch work orders: {ex.Message}");
        }
    }

    public async Task<Result<bool>> RolloverOrderAsync(OrderRolloverDto dto, string performedBy = "system")
    {
        try
        {
            var result = await _logisticsRepository.RolloverOrderAsync(dto.SoNumber, dto.UserSelectedDate, performedBy);
            return Result<bool>.Success(result);
        }
        catch (Exception ex)
        {
            return Result<bool>.Failure($"Failed to rollover order: {ex.Message}");
        }
    }

    public async Task<Result<bool>> UpdateEodExclusionAsync(UpdateEodExclusionRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.EntityId) || string.IsNullOrWhiteSpace(request.EntityType))
        {
            return Result<bool>.Failure("Invalid request parameters.");
        }

        try
        {
            var success = await _logisticsRepository.UpdateEodExclusionAsync(request.EntityType, request.EntityId, request.ExcludeFromEod);
            
            if (success)
                return Result<bool>.Success(true);

            return Result<bool>.Failure($"Failed to update EOD exclusion for {request.EntityType} with ID {request.EntityId}.");
        }
        catch (Exception ex)
        {
            return Result<bool>.Failure($"Error updating EOD exclusion: {ex.Message}");
        }
    }

    public async Task<int> GetPendingStagingEodCountAsync()
    {
        return await _logisticsRepository.GetPendingStagingEodCountAsync();
    }

    public async Task<IEnumerable<LorryDto>> GetLorriesAsync()
    {
        return await _logisticsRepository.GetLorriesAsync();
    }

    public async Task<Result<bool>> UpdateTargetLorryAsync(string soNumber, string lorryValue)
    {
        try
        {
            var result = await _logisticsRepository.UpdateTargetLorryAsync(soNumber, lorryValue);
            return Result<bool>.Success(result);
        }
        catch (Exception ex)
        {
            return Result<bool>.Failure($"Failed to update target lorry: {ex.Message}");
        }
    }

    /// <summary>Writes a freeform audit entry through the repository.</summary>
    public async Task LogAuditAsync(string entity, string action, string entityId, string payload)
    {
        try { await _logisticsRepository.WriteAuditAsync(entity, action, entityId, payload); }
        catch { /* audit failures must never break the main flow */ }
    }
}
