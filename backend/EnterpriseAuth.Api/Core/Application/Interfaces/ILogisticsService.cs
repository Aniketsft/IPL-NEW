using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using EnterpriseAuth.Api.Core.Application.Common;
using EnterpriseAuth.Api.Core.Application.DTOs;

namespace EnterpriseAuth.Api.Core.Application.Interfaces
{
    public interface ILogisticsService
    {
        Task<Result<IEnumerable<ProductionTrackingDto>>> GetProductionTrackingAsync();
        Task<Result<IEnumerable<SalesOrderHeaderDto>>> GetSalesOrderHeadersAsync(int? status, DateTime? date, string? customerCode, string? rep0, string? rep1);
        Task<Result<IEnumerable<SalesOrderDetailDto>>> GetSalesOrderDetailsAsync(string soNumber);
        Task<Result<IEnumerable<CustomerLookupDto>>> GetCustomerLookupAsync();
        Task<Result<IEnumerable<SalesRepLookupDto>>> GetSalesRepLookupAsync();
        Task<Result<int>> SyncScansAsync(IEnumerable<ScanDto> scans);

        Task<Result<IEnumerable<LocationLookupDto>>> GetLocationLookupsAsync(string site);
        Task<Result<bool>> CloseOrderAsync(string soNumber, string closedBy);
        Task<Result<string>> SaveCutBulkAsync(CutBulkEntryDto dto);
        Task<Result<ProductionScanDto>> SaveProductionScanAsync(ProductionScanDto scanDto);
    }
}
