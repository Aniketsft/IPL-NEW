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

        public async Task<Result<IEnumerable<ProductionTrackingDto>>> GetProductionTrackingAsync(string? location = null)
        {
            try
            {
                var tracking = await _logisticsRepository.GetProductionTrackingAsync(location);
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

        public async Task<Result<ProductionTrackingDto>> GetProductionTrackingInfoAsync(string soNumber, string itemCode)
        {
            try
            {
                var info = await _logisticsRepository.GetProductionTrackingInfoAsync(soNumber, itemCode);
                if (info == null) return Result<ProductionTrackingDto>.Failure("Product info not found.");
                return Result<ProductionTrackingDto>.Success(info);
            }
            catch (Exception ex)
            {
                return Result<ProductionTrackingDto>.Failure($"Failed to fetch production tracking info: {ex.Message}");
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

        public async Task<Result<IEnumerable<LotLookupDto>>> GetLotLookupsAsync(string site, string itemCode, string? location = null)
        {
            try
            {
                var lots = await _logisticsRepository.GetLotLookupsAsync(site, itemCode, location);
                return Result<IEnumerable<LotLookupDto>>.Success(lots);
            }
            catch (Exception ex)
            {
                return Result<IEnumerable<LotLookupDto>>.Failure($"Failed to fetch lots: {ex.Message}");
            }
        }

        public async Task<Result<string>> SaveCutBulkAsync(CutBulkEntryDto entry)
        {
            try
            {
                var entryNumber = await _logisticsRepository.SaveCutBulkEntryAsync(entry);
                return Result<string>.Success(entryNumber);
            }
            catch (Exception ex)
            {
                return Result<string>.Failure($"Failed to save Cuts / Bulk entry: {ex.Message}");
            }
        }

        public async Task<Result<ProductionScanDto>> SaveProductionScanAsync(ProductionScanDto scan)
        {
            try
            {
                var result = await _logisticsRepository.SaveProductionScanAsync(scan);
                return Result<ProductionScanDto>.Success(result);
            }
            catch (Exception ex)
            {
                return Result<ProductionScanDto>.Failure($"Failed to save production scan: {ex.Message}");
            }
        }
    }
}
