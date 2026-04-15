using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using EnterpriseAuth.Api.Core.Application.DTOs;

namespace EnterpriseAuth.Api.Core.Domain.Interfaces
{
    public interface ILogisticsRepository
    {
        Task<IEnumerable<ProductionTrackingDto>> GetProductionTrackingAsync(string? siteCode);
        Task<IEnumerable<SalesOrderHeaderDto>> GetSalesOrderHeadersAsync(int? status, DateTime? date, string? customerCode, string? rep0, string? rep1);
        Task<IEnumerable<SalesOrderDetailDto>> GetSalesOrderDetailsAsync(string soNumber);
        Task<IEnumerable<CustomerLookupDto>> GetCustomerLookupAsync();
        Task<IEnumerable<SalesRepLookupDto>> GetSalesRepLookupAsync();
        Task<int> SyncScansAsync(IEnumerable<ScanDto> scans);
        Task<IEnumerable<string>> GetProductionSitesAsync();
        Task<IEnumerable<string>> GetLotsAsync(string itemCode, string siteCode);

        Task<IEnumerable<LocationLookupDto>> GetLocationLookupsAsync(string site);
        Task<IEnumerable<LocationLookupDto>> GetTargetLocationsAsync(string site, string itemCode);
        Task<IEnumerable<BarcodeMappingDto>> GetBarcodeMappingsAsync(string siteCode);
        Task<bool> CloseOrderAsync(string soNumber, string closedBy);
        Task<string> SaveCutBulkEntryAsync(CutBulkEntryDto dto, bool skipScan = false);
        Task<ProductionScanDto> SaveProductionScanAsync(ProductionScanDto scanDto);
        Task<IEnumerable<ProductionScanDto>> GetProductionScansAsync(string soNumber, string itemCode);
        Task<int> SaveProductionScansBatchAsync(List<ProductionScanDto> scans);
        Task<bool> UpdateItemPreparationStatusAsync(string soNumber, string itemCode, bool isPrepared);
        Task<bool> UpdateItemValidationStatusAsync(string soNumber, string itemCode, bool isValidated);
        Task<bool> BulkUpdateItemStatusAsync(string soNumber, List<string> itemCodes, bool status, bool isValidation);
        Task<IEnumerable<ExcessDto>> GetExcessByDateAndItemAsync(DateTime deliveryDate, string itemCode);
        Task<bool> AllocateExcessAsync(AllocateExcessDto dto);
    }
}
