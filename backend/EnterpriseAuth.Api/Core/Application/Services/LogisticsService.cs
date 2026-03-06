using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using EnterpriseAuth.Api.Core.Application.Common;
using EnterpriseAuth.Api.Core.Application.DTOs;
using EnterpriseAuth.Api.Core.Application.Interfaces;
using EnterpriseAuth.Api.Core.Domain.Interfaces;

namespace EnterpriseAuth.Api.Core.Application.Services
{
    public class LogisticsService : ILogisticsService
    {
        private readonly ILogisticsRepository _logisticsRepository;

        public LogisticsService(ILogisticsRepository logisticsRepository)
        {
            _logisticsRepository = logisticsRepository;
        }

        public async Task<Result<IEnumerable<ProductionTrackingDto>>> GetProductionTrackingAsync()
        {
            try
            {
                var tracking = await _logisticsRepository.GetProductionTrackingAsync();
                return Result<IEnumerable<ProductionTrackingDto>>.Success(tracking);
            }
            catch (Exception ex)
            {
                return Result<IEnumerable<ProductionTrackingDto>>.Failure($"Failed to fetch production tracking data: {ex.Message}");
            }
        }

        public async Task<Result<IEnumerable<SalesOrderHeaderDto>>> GetSalesOrderHeadersAsync(int? status, DateTime? date, string? customerCode)
        {
            try
            {
                var headers = await _logisticsRepository.GetSalesOrderHeadersAsync(status, date, customerCode);
                return Result<IEnumerable<SalesOrderHeaderDto>>.Success(headers);
            }
            catch (Exception ex)
            {
                return Result<IEnumerable<SalesOrderHeaderDto>>.Failure($"Failed to fetch sales order headers: {ex.Message}");
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
    }
}
