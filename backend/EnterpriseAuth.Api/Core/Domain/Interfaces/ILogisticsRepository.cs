using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using EnterpriseAuth.Api.Core.Application.DTOs;

namespace EnterpriseAuth.Api.Core.Domain.Interfaces
{
    public interface ILogisticsRepository
    {
        Task<IEnumerable<ProductionTrackingDto>> GetProductionTrackingAsync(string? location = null);
        Task<IEnumerable<SalesOrderHeaderDto>> GetSalesOrderHeadersAsync(int? status, DateTime? date, string? customerCode, string? rep0, string? rep1);
        Task<IEnumerable<SalesOrderDetailDto>> GetSalesOrderDetailsAsync(string soNumber);
        Task<IEnumerable<CustomerLookupDto>> GetCustomerLookupAsync();
        Task<IEnumerable<SalesRepLookupDto>> GetSalesRepLookupAsync();
        Task<int> SyncScansAsync(IEnumerable<ScanDto> scans);

        // Production Tracking
        Task<ProductionTrackingDto> GetProductionTrackingInfoAsync(string soNumber, string productCode);
        Task<IEnumerable<LocationLookupDto>> GetLocationLookupsAsync(string site);
        Task<IEnumerable<LotLookupDto>> GetLotLookupsAsync(string site, string productCode);
    }
}
