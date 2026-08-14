using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using EnterpriseAuth.Api.Core.Application.Common;
using EnterpriseAuth.Api.Core.Application.DTOs;

namespace EnterpriseAuth.Api.Core.Application.Interfaces
{
    public interface ILogisticsService
    {
        Task<Result<IEnumerable<ProductionTrackingDto>>> GetProductionTrackingAsync(string? siteCode);
        Task<Result<IEnumerable<SalesOrderHeaderDto>>> GetSalesOrderHeadersAsync(int? status, DateTime? date, string? customerCode, string? rep0, string? rep1);
        Task<Result<IEnumerable<ProductionTrackingDto>>> GetProductionSummaryAsync(DateTime date);
        Task<Result<IEnumerable<ProductionTrackingDto>>> GetProductionSummaryByWorkOrderAsync(string workOrder);
        Task<Result<bool>> CompleteEndOfDayAsync(string workOrder, IEnumerable<ProductionTrackingDto> items);
        Task<Result<IEnumerable<SalesOrderDetailDto>>> GetSalesOrderDetailsAsync(string soNumber);
        Task<Result<IEnumerable<CustomerLookupDto>>> GetCustomerLookupAsync();
        Task<Result<IEnumerable<SalesRepLookupDto>>> GetSalesRepLookupAsync();
        Task<Result<int>> SyncScansAsync(IEnumerable<ScanDto> scans);
        Task<Result<IEnumerable<string>>> GetProductionSitesAsync();
        Task<Result<IEnumerable<string>>> GetLotsAsync(string itemCode, string siteCode);

        Task<Result<IEnumerable<LocationLookupDto>>> GetLocationLookupsAsync(string site);
        Task<Result<IEnumerable<LocationLookupDto>>> GetTargetLocationsAsync(string site, string itemCode);
        Task<Result<IEnumerable<BarcodeMappingDto>>> GetBarcodeMappingsAsync(string siteCode);
        Task<Result<bool>> CloseOrderAsync(string soNumber, string closedBy);
        Task<Result<string>> SaveCutBulkAsync(CutBulkEntryDto dto);
        Task<Result<ProductionScanDto>> SaveProductionScanAsync(ProductionScanDto scanDto);
        Task<Result<IEnumerable<ProductionScanDto>>> GetProductionScansAsync(string soNumber, string itemCode);
        Task<Result<int>> SaveProductionScansBatchAsync(List<ProductionScanDto> scans);
        Task<Result<bool>> UpdateItemPreparationStatusAsync(string soNumber, string itemCode, bool isPrepared, string performedBy = "system");
        Task<Result<bool>> UpdateItemValidationStatusAsync(string soNumber, string itemCode, bool isValidated, string performedBy = "system");
        Task<Result<bool>> BulkUpdateItemStatusAsync(BulkStatusUpdateDto dto);
        Task<Result<IEnumerable<ExcessDto>>> GetExcessByDateAndItemAsync(DateTime deliveryDate, string itemCode);
        Task<Result<bool>> AllocateExcessAsync(AllocateExcessDto dto);
        Task<Result<LabelAuditDto>> LogLabelAuditAsync(LabelAuditDto auditDto);
        Task<Result<IEnumerable<WorkOrderDto>>> GetWorkOrdersAsync(string? searchQuery);
        Task<Result<bool>> RolloverOrderAsync(OrderRolloverDto dto, string performedBy = "system");
        Task<Result<bool>> UpdateEodExclusionAsync(UpdateEodExclusionRequest request);
        Task<Result<IEnumerable<LorryDto>>> GetLorriesAsync();
        Task<Result<bool>> UpdateTargetLorryAsync(string soNumber, string lorryValue);
        Task<int> GetPendingStagingEodCountAsync();
    }
}
