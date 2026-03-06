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
        Task<Result<int>> SyncScansAsync(IEnumerable<ScanDto> scans);
    }
}
