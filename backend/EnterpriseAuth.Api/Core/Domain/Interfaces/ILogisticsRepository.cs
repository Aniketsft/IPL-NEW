using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using EnterpriseAuth.Api.Core.Application.DTOs;

namespace EnterpriseAuth.Api.Core.Domain.Interfaces
{
    public interface ILogisticsRepository
    {
        Task<IEnumerable<ProductionTrackingDto>> GetProductionTrackingAsync();
        Task<IEnumerable<SalesOrderHeaderDto>> GetSalesOrderHeadersAsync(int? status, DateTime? date, string? customerCode);
        Task<int> SyncScansAsync(IEnumerable<ScanDto> scans);
    }
}
